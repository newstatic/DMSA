import Foundation

/// VFS 文件系统委托协议
protocol VFSFileSystemDelegate: AnyObject, Sendable {
    func fileWritten(virtualPath: String, syncPairId: String)
    func fileRead(virtualPath: String, syncPairId: String)
    func fileDeleted(virtualPath: String, syncPairId: String)
}

/// FUSE 文件系统实现 - macFUSE GMUserFileSystem 委托
///
/// 此类在 DMSAService (root 权限) 中运行，实现 macFUSE 的文件系统回调。
/// 通过动态加载 macFUSE.framework 来避免编译时依赖。
///
/// 使用方式:
/// ```swift
/// let fs = FUSEFileSystem(syncPairId: "...", localDir: "...", externalDir: "...", delegate: ...)
/// try await fs.mount(at: "~/Downloads")
/// ```
@objc class FUSEFileSystem: NSObject {

    // MARK: - 属性

    private let logger = Logger.forService("FUSE")

    /// 同步对 ID
    private let syncPairId: String

    /// 本地目录 (热数据缓存)
    private let localDir: String

    /// 外部目录 (完整数据源)
    private var externalDir: String?

    /// macFUSE 文件系统实例
    private var userFileSystem: AnyObject?  // GMUserFileSystem

    /// 挂载点路径
    private(set) var mountPath: String?

    /// 是否已挂载
    private(set) var isMounted: Bool = false

    /// 外部存储是否离线
    private var isExternalOffline: Bool = false

    /// 是否只读模式
    private var isReadOnly: Bool = false

    /// 卷名
    private let volumeName: String

    /// 委托
    private weak var delegate: VFSFileSystemDelegate?

    /// 打开的文件句柄映射
    private var openFileHandles: [String: FileHandle] = [:]
    private let handleLock = NSLock()

    // MARK: - 初始化

    init(syncPairId: String,
         localDir: String,
         externalDir: String?,
         volumeName: String = "DMSA",
         delegate: VFSFileSystemDelegate?) {
        self.syncPairId = syncPairId
        self.localDir = localDir
        self.externalDir = externalDir
        self.volumeName = volumeName
        self.delegate = delegate
        self.isExternalOffline = externalDir == nil
        super.init()
    }

    deinit {
        if isMounted {
            unmountSync()
        }
    }

    // MARK: - 挂载/卸载

    /// 挂载文件系统
    func mount(at path: String) async throws {
        guard !isMounted else {
            throw VFSError.alreadyMounted(path)
        }

        // 检查 macFUSE 可用性
        guard FUSEChecker.isAvailable() else {
            throw VFSError.fuseNotAvailable
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        mountPath = expandedPath

        // 确保挂载点存在
        let fm = FileManager.default
        if !fm.fileExists(atPath: expandedPath) {
            try fm.createDirectory(atPath: expandedPath, withIntermediateDirectories: true, attributes: nil)
        }

        // 动态加载 GMUserFileSystem 类
        guard let gmClass = NSClassFromString("GMUserFileSystem") as? NSObject.Type else {
            throw VFSError.fuseNotAvailable
        }

        // 创建实例
        let fs = gmClass.init()

        // 设置 delegate (使用 KVC)
        fs.setValue(self, forKey: "delegate")

        // 配置挂载选项
        var options: [String] = []
        options.append("volname=\(volumeName)")      // 卷名
        options.append("local")                       // 本地卷
        options.append("allow_other")                // 允许其他用户访问
        options.append("default_permissions")        // 使用默认权限检查
        options.append("noappledouble")              // 禁用 AppleDouble 文件
        options.append("noapplexattr")               // 禁用 Apple 扩展属性

        // 调用 mount 方法
        let selector = NSSelectorFromString("mountAtPath:withOptions:")
        if fs.responds(to: selector) {
            _ = fs.perform(selector, with: expandedPath, with: options)
        } else {
            throw VFSError.mountFailed("GMUserFileSystem mount method not found")
        }

        userFileSystem = fs
        isMounted = true

        logger.info("FUSE 已挂载: \(expandedPath)")
        logger.info("  syncPairId: \(syncPairId)")
        logger.info("  LOCAL_DIR: \(localDir)")
        logger.info("  EXTERNAL_DIR: \(externalDir ?? "离线")")
    }

    /// 卸载文件系统
    func unmount() async throws {
        guard isMounted else {
            throw VFSError.notMounted(syncPairId)
        }

        unmountSync()
    }

    /// 同步卸载 (用于 deinit)
    private func unmountSync() {
        guard isMounted, let fs = userFileSystem else { return }

        // 关闭所有打开的文件句柄
        handleLock.lock()
        for (_, handle) in openFileHandles {
            try? handle.close()
        }
        openFileHandles.removeAll()
        handleLock.unlock()

        // 调用 unmount 方法
        let selector = NSSelectorFromString("unmount")
        if fs.responds(to: selector) {
            _ = (fs as AnyObject).perform(selector)
        }

        isMounted = false
        let path = mountPath ?? ""
        mountPath = nil
        userFileSystem = nil

        logger.info("FUSE 已卸载: \(path)")
    }

    // MARK: - 配置更新

    /// 更新外部目录路径
    func updateExternalDir(_ path: String?) {
        externalDir = path
        isExternalOffline = path == nil
        logger.info("EXTERNAL_DIR 已更新: \(path ?? "离线")")
    }

    /// 设置外部存储离线状态
    func setExternalOffline(_ offline: Bool) {
        isExternalOffline = offline
    }

    /// 设置只读模式
    func setReadOnly(_ readOnly: Bool) {
        isReadOnly = readOnly
    }

    // MARK: - 路径辅助方法

    /// 获取本地路径
    private func localPath(for virtualPath: String) -> String {
        let normalized = virtualPath.hasPrefix("/") ? String(virtualPath.dropFirst()) : virtualPath
        return (localDir as NSString).appendingPathComponent(normalized)
    }

    /// 获取外部路径
    private func externalPath(for virtualPath: String) -> String? {
        guard let extDir = externalDir else { return nil }
        let normalized = virtualPath.hasPrefix("/") ? String(virtualPath.dropFirst()) : virtualPath
        return (extDir as NSString).appendingPathComponent(normalized)
    }

    /// 解析实际文件路径 (优先本地，其次外部)
    private func resolveActualPath(for virtualPath: String) -> String? {
        let fm = FileManager.default

        // 优先检查本地
        let local = localPath(for: virtualPath)
        if fm.fileExists(atPath: local) {
            return local
        }

        // 其次检查外部 (如果在线)
        if !isExternalOffline, let external = externalPath(for: virtualPath), fm.fileExists(atPath: external) {
            return external
        }

        return nil
    }

    /// 确保父目录存在
    private func ensureParentDirectory(for path: String) throws {
        let parentDir = (path as NSString).deletingLastPathComponent
        let fm = FileManager.default
        if !fm.fileExists(atPath: parentDir) {
            try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }
    }
}

// MARK: - GMUserFileSystem Delegate Methods

extension FUSEFileSystem {

    // MARK: - 目录内容

    /// 读取目录内容 (智能合并)
    @objc func contentsOfDirectory(atPath path: String) -> [String]? {
        logger.debug("contentsOfDirectory: \(path)")

        var contents = Set<String>()
        let fm = FileManager.default

        // 从 LOCAL_DIR 读取
        let local = localPath(for: path)
        if let localContents = try? fm.contentsOfDirectory(atPath: local) {
            contents.formUnion(localContents)
        }

        // 从 EXTERNAL_DIR 读取 (如果在线)
        if !isExternalOffline, let external = externalPath(for: path) {
            if let externalContents = try? fm.contentsOfDirectory(atPath: external) {
                contents.formUnion(externalContents)
            }
        }

        // 过滤排除的文件
        let filtered = contents.filter { !shouldExclude(name: $0) }
        return filtered.sorted()
    }

    // MARK: - 文件属性

    /// 获取文件属性
    @objc func attributesOfItem(atPath path: String, userData: Any?) -> [String: Any]? {
        logger.debug("attributesOfItem: \(path)")

        // 根目录特殊处理
        if path == "/" || path.isEmpty {
            return [
                FileAttributeKey.type.rawValue: FileAttributeType.typeDirectory,
                FileAttributeKey.posixPermissions.rawValue: 0o755,
                FileAttributeKey.size.rawValue: 0,
                FileAttributeKey.modificationDate.rawValue: Date(),
                FileAttributeKey.creationDate.rawValue: Date()
            ]
        }

        guard let actualPath = resolveActualPath(for: path) else {
            return nil
        }

        // 转换 [FileAttributeKey: Any] 到 [String: Any]
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: actualPath) else {
            return nil
        }
        var result: [String: Any] = [:]
        for (key, value) in attrs {
            result[key.rawValue] = value
        }
        return result
    }

    /// 获取文件系统属性
    @objc func attributesOfFileSystem(forPath path: String) -> [String: Any]? {
        var dict: [String: Any] = [:]

        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: localDir)
            dict[FileAttributeKey.systemSize.rawValue] = attrs[.systemSize]
            dict[FileAttributeKey.systemFreeSize.rawValue] = attrs[.systemFreeSize]
            dict[FileAttributeKey.systemNodes.rawValue] = attrs[.systemNodes]
            dict[FileAttributeKey.systemFreeNodes.rawValue] = attrs[.systemFreeNodes]
        } catch {
            // 返回默认值
            dict[FileAttributeKey.systemSize.rawValue] = Int64(1_000_000_000_000)  // 1TB
            dict[FileAttributeKey.systemFreeSize.rawValue] = Int64(500_000_000_000)  // 500GB
        }

        return dict
    }

    // MARK: - 读取文件

    /// 打开文件
    @objc(openFileAtPath:mode:userData:error:)
    func openFile(atPath path: String, mode: Int32, userData: AutoreleasingUnsafeMutablePointer<AnyObject?>?, error: NSErrorPointer) -> Bool {
        logger.debug("openFile: \(path) mode: \(mode)")

        guard let actualPath = resolveActualPath(for: path) else {
            // 如果文件不存在但是写入模式，在本地创建
            if mode & O_WRONLY != 0 || mode & O_RDWR != 0 || mode & O_CREAT != 0 {
                let local = localPath(for: path)
                do {
                    try ensureParentDirectory(for: local)
                    FileManager.default.createFile(atPath: local, contents: nil)

                    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: local))
                    handleLock.lock()
                    openFileHandles[path] = handle
                    handleLock.unlock()

                    userData?.pointee = path as AnyObject
                    return true
                } catch let err {
                    error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO), userInfo: [NSLocalizedDescriptionKey: err.localizedDescription])
                    return false
                }
            }

            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
            return false
        }

        do {
            let url = URL(fileURLWithPath: actualPath)
            let handle: FileHandle

            if mode & O_WRONLY != 0 || mode & O_RDWR != 0 {
                // 写入模式 - 确保写入到本地
                let local = localPath(for: path)

                // 如果实际路径是外部，先复制到本地
                if actualPath != local {
                    try ensureParentDirectory(for: local)
                    try FileManager.default.copyItem(atPath: actualPath, toPath: local)
                }

                handle = try FileHandle(forUpdating: URL(fileURLWithPath: local))
            } else {
                // 只读模式
                handle = try FileHandle(forReadingFrom: url)
            }

            handleLock.lock()
            openFileHandles[path] = handle
            handleLock.unlock()

            userData?.pointee = path as AnyObject

            // 通知读取事件
            delegate?.fileRead(virtualPath: path, syncPairId: syncPairId)

            return true
        } catch let err {
            logger.error("openFile error: \(err)")
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
            return false
        }
    }

    /// 读取文件数据
    @objc(readFileAtPath:userData:buffer:size:offset:error:)
    func readFile(atPath path: String, userData: Any?, buffer: UnsafeMutablePointer<Int8>, size: Int, offset: off_t, error: NSErrorPointer) -> Int32 {
        handleLock.lock()
        guard let handle = openFileHandles[path] else {
            handleLock.unlock()
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EBADF))
            return -1
        }
        handleLock.unlock()

        do {
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: size) else {
                return 0
            }

            data.copyBytes(to: UnsafeMutableBufferPointer(start: buffer, count: data.count))
            return Int32(data.count)
        } catch let err {
            logger.error("readFile error: \(err)")
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
            return -1
        }
    }

    /// 关闭文件
    @objc(releaseFileAtPath:userData:)
    func releaseFile(atPath path: String, userData: Any?) {
        logger.debug("releaseFile: \(path)")

        handleLock.lock()
        if let handle = openFileHandles.removeValue(forKey: path) {
            try? handle.close()
        }
        handleLock.unlock()
    }

    // MARK: - 写入文件

    /// 写入文件数据
    @objc(writeFileAtPath:userData:buffer:size:offset:error:)
    func writeFile(atPath path: String, userData: Any?, buffer: UnsafePointer<Int8>, size: Int, offset: off_t, error: NSErrorPointer) -> Int32 {
        guard !isReadOnly else {
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS))
            return -1
        }

        // 确保写入到本地目录
        let local = localPath(for: path)

        do {
            let fm = FileManager.default

            // 确保父目录存在
            try ensureParentDirectory(for: local)

            // 确保文件存在
            if !fm.fileExists(atPath: local) {
                fm.createFile(atPath: local, contents: nil)
            }

            // 写入数据
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: local))
            try handle.seek(toOffset: UInt64(offset))

            let data = Data(bytes: buffer, count: size)
            try handle.write(contentsOf: data)
            try handle.close()

            // 通知写入事件
            delegate?.fileWritten(virtualPath: path, syncPairId: syncPairId)

            return Int32(size)
        } catch let err {
            logger.error("writeFile error: \(err)")
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
            return -1
        }
    }

    /// 截断文件
    @objc func truncateFile(atPath path: String, offset: off_t, error: NSErrorPointer) -> Bool {
        guard !isReadOnly else {
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS))
            return false
        }

        let local = localPath(for: path)

        do {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: local))
            try handle.truncate(atOffset: UInt64(offset))
            try handle.close()

            delegate?.fileWritten(virtualPath: path, syncPairId: syncPairId)
            return true
        } catch {
            logger.error("truncateFile error: \(error)")
            return false
        }
    }

    // MARK: - 创建/删除

    /// 创建目录
    @objc(createDirectoryAtPath:attributes:error:)
    func createDirectory(atPath path: String, attributes: [String: Any]?, error: NSErrorPointer) -> Bool {
        guard !isReadOnly else {
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS))
            return false
        }

        let local = localPath(for: path)

        do {
            try FileManager.default.createDirectory(atPath: local, withIntermediateDirectories: true)
            delegate?.fileWritten(virtualPath: path, syncPairId: syncPairId)
            return true
        } catch let err {
            logger.error("createDirectory error: \(err)")
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
            return false
        }
    }

    /// 创建文件
    @objc(createFileAtPath:attributes:flags:userData:error:)
    func createFile(atPath path: String, attributes: [String: Any]?, flags: Int32, userData: AutoreleasingUnsafeMutablePointer<AnyObject?>?, error: NSErrorPointer) -> Bool {
        guard !isReadOnly else {
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS))
            return false
        }

        let local = localPath(for: path)

        do {
            try ensureParentDirectory(for: local)
            FileManager.default.createFile(atPath: local, contents: nil)

            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: local))
            handleLock.lock()
            openFileHandles[path] = handle
            handleLock.unlock()

            userData?.pointee = path as AnyObject

            delegate?.fileWritten(virtualPath: path, syncPairId: syncPairId)
            return true
        } catch let err {
            logger.error("createFile error: \(err)")
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
            return false
        }
    }

    /// 删除文件/目录
    @objc(removeItemAtPath:error:)
    func removeItem(atPath path: String, error: NSErrorPointer) -> Bool {
        guard !isReadOnly else {
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS))
            return false
        }

        let fm = FileManager.default
        var success = true

        // 删除本地副本
        let local = localPath(for: path)
        if fm.fileExists(atPath: local) {
            do {
                try fm.removeItem(atPath: local)
            } catch let err {
                logger.error("removeItem local error: \(err)")
                error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
                success = false
            }
        }

        // 删除外部副本 (如果在线且存在)
        if !isExternalOffline, let external = externalPath(for: path), fm.fileExists(atPath: external) {
            do {
                try fm.removeItem(atPath: external)
            } catch {
                logger.warning("removeItem external error: \(error)")
            }
        }

        if success {
            delegate?.fileDeleted(virtualPath: path, syncPairId: syncPairId)
        }

        return success
    }

    /// 删除目录
    @objc(removeDirectoryAtPath:error:)
    func removeDirectory(atPath path: String, error: NSErrorPointer) -> Bool {
        return removeItem(atPath: path, error: error)
    }

    // MARK: - 移动/重命名

    /// 移动文件/目录
    @objc func moveItem(atPath source: String, toPath destination: String, error: NSErrorPointer) -> Bool {
        guard !isReadOnly else {
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS))
            return false
        }

        let fm = FileManager.default
        let srcLocal = localPath(for: source)
        let dstLocal = localPath(for: destination)

        // 移动本地副本
        if fm.fileExists(atPath: srcLocal) {
            do {
                try ensureParentDirectory(for: dstLocal)
                try fm.moveItem(atPath: srcLocal, toPath: dstLocal)
            } catch {
                logger.error("moveItem local error: \(error)")
                return false
            }
        }

        // 移动外部副本
        if !isExternalOffline,
           let srcExt = externalPath(for: source),
           let dstExt = externalPath(for: destination),
           fm.fileExists(atPath: srcExt) {
            do {
                let dstParent = (dstExt as NSString).deletingLastPathComponent
                if !fm.fileExists(atPath: dstParent) {
                    try fm.createDirectory(atPath: dstParent, withIntermediateDirectories: true)
                }
                try fm.moveItem(atPath: srcExt, toPath: dstExt)
            } catch {
                logger.warning("moveItem external error: \(error)")
            }
        }

        delegate?.fileDeleted(virtualPath: source, syncPairId: syncPairId)
        delegate?.fileWritten(virtualPath: destination, syncPairId: syncPairId)

        return true
    }

    // MARK: - 扩展属性

    /// 获取扩展属性名列表
    @objc func extendedAttributeNames(ofItemAtPath path: String) -> [String]? {
        guard let actualPath = resolveActualPath(for: path) else {
            return nil
        }

        var size = listxattr(actualPath, nil, 0, 0)
        guard size > 0 else { return [] }

        var buffer = [Int8](repeating: 0, count: size)
        size = listxattr(actualPath, &buffer, size, 0)
        guard size > 0 else { return [] }

        let data = Data(bytes: buffer, count: size)
        let names = String(data: data, encoding: .utf8)?
            .split(separator: "\0")
            .map { String($0) }

        return names
    }

    /// 获取扩展属性值
    @objc func value(ofExtendedAttributeWithName name: String, ofItemAtPath path: String,
                     position: off_t, error: NSErrorPointer) -> Data? {
        guard let actualPath = resolveActualPath(for: path) else {
            return nil
        }

        var size = getxattr(actualPath, name, nil, 0, UInt32(position), 0)
        guard size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        size = getxattr(actualPath, name, &buffer, size, UInt32(position), 0)
        guard size > 0 else { return nil }

        return Data(buffer[0..<size])
    }

    /// 设置扩展属性
    @objc func setExtendedAttribute(withName name: String, ofItemAtPath path: String,
                                    value: Data, position: off_t, options: Int32,
                                    error: NSErrorPointer) -> Bool {
        let local = localPath(for: path)

        let result = value.withUnsafeBytes { buffer in
            setxattr(local, name, buffer.baseAddress, value.count, UInt32(position), options)
        }

        return result == 0
    }

    /// 删除扩展属性
    @objc func removeExtendedAttribute(withName name: String, ofItemAtPath path: String,
                                       error: NSErrorPointer) -> Bool {
        let local = localPath(for: path)
        return removexattr(local, name, 0) == 0
    }

    // MARK: - 辅助方法

    /// 检查是否应该排除的文件
    private func shouldExclude(name: String) -> Bool {
        let excludePatterns = [
            ".DS_Store",
            ".Spotlight-V100",
            ".Trashes",
            ".fseventsd",
            ".TemporaryItems",
            "._*",
            ".FUSE"
        ]

        for pattern in excludePatterns {
            if matchPattern(pattern, name: name) {
                return true
            }
        }
        return false
    }

    private func matchPattern(_ pattern: String, name: String) -> Bool {
        if pattern.contains("*") {
            let regex = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            return name.range(of: "^\(regex)$", options: .regularExpression) != nil
        } else {
            return name == pattern
        }
    }
}

// MARK: - FUSE 检查器

struct FUSEChecker {

    private static let macFUSEFrameworkPath = "/Library/Frameworks/macFUSE.framework"

    /// 检查 macFUSE 是否可用
    static func isAvailable() -> Bool {
        let fm = FileManager.default

        // 检查 Framework 存在
        guard fm.fileExists(atPath: macFUSEFrameworkPath) else {
            return false
        }

        // 检查关键文件
        let requiredFiles = [
            "\(macFUSEFrameworkPath)/Versions/A/macFUSE",
            "\(macFUSEFrameworkPath)/Headers/fuse.h"
        ]

        for file in requiredFiles {
            if !fm.fileExists(atPath: file) {
                return false
            }
        }

        // 尝试加载 Framework
        guard let bundle = Bundle(path: macFUSEFrameworkPath) else {
            return false
        }

        if !bundle.isLoaded {
            do {
                try bundle.loadAndReturnError()
            } catch {
                return false
            }
        }

        // 检查核心类
        return NSClassFromString("GMUserFileSystem") != nil
    }

    /// 获取已安装版本
    static func getInstalledVersion() -> String? {
        let infoPlistPath = "\(macFUSEFrameworkPath)/Versions/A/Resources/Info.plist"

        guard let plist = NSDictionary(contentsOfFile: infoPlistPath) else {
            return nil
        }

        return plist["CFBundleShortVersionString"] as? String
            ?? plist["CFBundleVersion"] as? String
    }
}
