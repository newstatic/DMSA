import Foundation

/// DMSA 文件系统 - macFUSE GMUserFileSystem 委托实现
///
/// 此类实现 macFUSE 的 GMUserFileSystem 协议，提供虚拟文件系统功能。
/// 它将 FUSE 回调桥接到 VFSCore 的逻辑处理。
///
/// 使用方式:
/// ```swift
/// let fs = DMSAFileSystem(syncPair: syncPair)
/// fs.mount(at: "~/Downloads")
/// ```
///
/// 注意: 需要安装 macFUSE 才能使用此类
/// 下载地址: https://macfuse.github.io/
@objc final class DMSAFileSystem: NSObject {

    // MARK: - 属性

    /// 同步对配置
    private let syncPair: SyncPairConfig

    /// macFUSE 文件系统实例
    private var userFileSystem: AnyObject?  // GMUserFileSystem

    /// 挂载点路径
    private(set) var mountPath: String?

    /// 是否已挂载
    private(set) var isMounted: Bool = false

    /// VFS 核心引用
    private let vfsCore = VFSCore.shared

    /// 合并引擎
    private let mergeEngine = MergeEngine.shared

    /// 数据库管理器
    private let databaseManager = DatabaseManager.shared

    /// 同步对 ID
    private let syncPairId: UUID

    /// 打开的文件句柄映射
    private var openFileHandles: [String: FileHandle] = [:]
    private let handleLock = NSLock()

    // MARK: - 初始化

    init(syncPair: SyncPairConfig) {
        self.syncPair = syncPair
        self.syncPairId = UUID(uuidString: syncPair.id) ?? UUID()
        super.init()
    }

    deinit {
        if isMounted {
            unmount()
        }
    }

    // MARK: - 挂载/卸载

    /// 挂载文件系统
    /// - Parameter path: 挂载点路径
    /// - Throws: 挂载错误
    func mount(at path: String) throws {
        guard !isMounted else {
            throw FUSEMountError.alreadyMounted
        }

        guard FUSEManager.shared.isAvailable else {
            throw FUSEMountError.fuseNotAvailable
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        mountPath = expandedPath

        // 确保挂载点存在
        let fm = FileManager.default
        if !fm.fileExists(atPath: expandedPath) {
            try fm.createDirectory(atPath: expandedPath, withIntermediateDirectories: true, attributes: nil)
        }

        // 创建 GMUserFileSystem 实例
        guard let gmClass = NSClassFromString("GMUserFileSystem") as? NSObject.Type else {
            throw FUSEMountError.fuseNotAvailable
        }

        // 使用动态调用创建实例
        let fs = gmClass.init()

        // 设置 delegate (使用 KVC)
        fs.setValue(self, forKey: "delegate")

        // 配置挂载选项
        var options: [String] = []
        options.append("volname=\(syncPair.name)")  // 卷名
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
            throw FUSEMountError.mountFailed("GMUserFileSystem mount method not found")
        }

        userFileSystem = fs
        isMounted = true

        Logger.shared.info("DMSAFileSystem: 已挂载到 \(expandedPath)")

        // 发送挂载通知
        NotificationCenter.default.post(
            name: .init("DMSAFileSystemDidMount"),
            object: self,
            userInfo: ["path": expandedPath, "syncPairId": syncPairId.uuidString]
        )
    }

    /// 卸载文件系统
    func unmount() {
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

        Logger.shared.info("DMSAFileSystem: 已卸载 \(path)")

        // 发送卸载通知
        NotificationCenter.default.post(
            name: .init("DMSAFileSystemDidUnmount"),
            object: self,
            userInfo: ["path": path, "syncPairId": syncPairId.uuidString]
        )
    }

    // MARK: - 路径辅助方法

    /// 获取本地路径
    private func localPath(for virtualPath: String) -> String? {
        return PathValidator.localPath(for: virtualPath, in: syncPair)
    }

    /// 获取外部路径
    private func externalPath(for virtualPath: String) -> String? {
        return PathValidator.externalPath(for: virtualPath, in: syncPair)
    }

    /// 解析实际文件路径 (优先本地，其次外部)
    private func resolveActualPath(for virtualPath: String) -> String? {
        let fm = FileManager.default

        // 优先检查本地
        if let local = localPath(for: virtualPath), fm.fileExists(atPath: local) {
            return local
        }

        // 其次检查外部
        if let external = externalPath(for: virtualPath), fm.fileExists(atPath: external) {
            return external
        }

        return nil
    }
}

// MARK: - GMUserFileSystem Delegate Methods (通过 @objc 动态调用)

extension DMSAFileSystem {

    // MARK: - 目录内容

    /// 读取目录内容
    @objc func contentsOfDirectory(atPath path: String) -> [String]? {
        Logger.shared.debug("DMSAFileSystem: contentsOfDirectory \(path)")

        // 使用 MergeEngine 获取合并后的目录列表
        var result: [String]?

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                let entries = try await mergeEngine.listDirectory(path, syncPairId: syncPairId)
                result = entries.map { $0.name }
            } catch {
                Logger.shared.error("DMSAFileSystem: contentsOfDirectory error: \(error)")
                result = nil
            }
            semaphore.signal()
        }
        semaphore.wait()

        return result
    }

    // MARK: - 文件属性

    /// 获取文件属性
    @objc func attributesOfItem(atPath path: String, userData: Any?) -> [String: Any]? {
        Logger.shared.debug("DMSAFileSystem: attributesOfItem \(path)")

        var result: [String: Any]?

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                let attrs = try await mergeEngine.getAttributes(path, syncPairId: syncPairId)

                var dict: [String: Any] = [:]
                dict[FileAttributeKey.size.rawValue] = attrs.size
                dict[FileAttributeKey.modificationDate.rawValue] = attrs.modifiedAt
                dict[FileAttributeKey.creationDate.rawValue] = attrs.createdAt

                if attrs.isDirectory {
                    dict[FileAttributeKey.type.rawValue] = FileAttributeType.typeDirectory
                    dict[FileAttributeKey.posixPermissions.rawValue] = 0o755
                } else {
                    dict[FileAttributeKey.type.rawValue] = FileAttributeType.typeRegular
                    dict[FileAttributeKey.posixPermissions.rawValue] = 0o644
                }

                result = dict
            } catch {
                Logger.shared.debug("DMSAFileSystem: attributesOfItem error: \(path) - \(error)")
                result = nil
            }
            semaphore.signal()
        }
        semaphore.wait()

        return result
    }

    /// 获取文件系统属性
    @objc func attributesOfFileSystem(forPath path: String) -> [String: Any]? {
        // 获取本地目录的文件系统信息
        let localDir = (syncPair.localDir as NSString).expandingTildeInPath

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

    /// 打开文件进行读取
    @objc func openFile(atPath path: String, mode: Int32, userData: inout Any?) -> Bool {
        Logger.shared.debug("DMSAFileSystem: openFile \(path) mode: \(mode)")

        guard let actualPath = resolveActualPath(for: path) else {
            Logger.shared.warning("DMSAFileSystem: openFile - file not found: \(path)")
            return false
        }

        do {
            let url = URL(fileURLWithPath: actualPath)
            let handle: FileHandle

            if mode & O_WRONLY != 0 || mode & O_RDWR != 0 {
                // 写入模式 - 使用本地路径
                guard let localPath = localPath(for: path) else {
                    return false
                }

                // 确保本地文件存在
                let fm = FileManager.default
                let localURL = URL(fileURLWithPath: localPath)

                if !fm.fileExists(atPath: localPath) {
                    // 从外部复制
                    if let extPath = externalPath(for: path), fm.fileExists(atPath: extPath) {
                        try? fm.createDirectory(at: localURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                        try fm.copyItem(atPath: extPath, toPath: localPath)
                    } else {
                        // 创建空文件
                        fm.createFile(atPath: localPath, contents: nil)
                    }
                }

                handle = try FileHandle(forUpdating: localURL)
            } else {
                // 只读模式
                handle = try FileHandle(forReadingFrom: url)
            }

            // 保存句柄
            handleLock.lock()
            openFileHandles[path] = handle
            handleLock.unlock()

            userData = path as AnyObject

            // 更新访问时间
            databaseManager.updateAccessTime(path)

            return true
        } catch {
            Logger.shared.error("DMSAFileSystem: openFile error: \(error)")
            return false
        }
    }

    /// 读取文件数据
    @objc func readFile(atPath path: String, userData: Any?, buffer: UnsafeMutablePointer<Int8>,
                        size: Int, offset: off_t, error: NSErrorPointer) -> Int32 {
        Logger.shared.debug("DMSAFileSystem: readFile \(path) offset:\(offset) size:\(size)")

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
        } catch {
            Logger.shared.error("DMSAFileSystem: readFile error: \(error)")
            return -1
        }
    }

    /// 关闭文件
    @objc func releaseFile(atPath path: String, userData: Any?) {
        Logger.shared.debug("DMSAFileSystem: releaseFile \(path)")

        handleLock.lock()
        if let handle = openFileHandles.removeValue(forKey: path) {
            try? handle.close()
        }
        handleLock.unlock()
    }

    // MARK: - 写入文件

    /// 写入文件数据
    @objc func writeFile(atPath path: String, userData: Any?, buffer: UnsafePointer<Int8>,
                         size: Int, offset: off_t, error: NSErrorPointer) -> Int32 {
        Logger.shared.debug("DMSAFileSystem: writeFile \(path) offset:\(offset) size:\(size)")

        // 确保写入到本地目录
        guard let localPath = localPath(for: path) else {
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
            return -1
        }

        do {
            let fm = FileManager.default
            let url = URL(fileURLWithPath: localPath)

            // 确保父目录存在
            let parentDir = url.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // 确保文件存在
            if !fm.fileExists(atPath: localPath) {
                fm.createFile(atPath: localPath, contents: nil)
            }

            // 写入数据
            let handle = try FileHandle(forWritingTo: url)
            try handle.seek(toOffset: UInt64(offset))

            let data = Data(bytes: buffer, count: size)
            try handle.write(contentsOf: data)
            try handle.close()

            // 标记为脏数据
            Task {
                if var entry = databaseManager.getFileEntry(virtualPath: path) {
                    entry.isDirty = true
                    entry.modifiedAt = Date()
                    databaseManager.saveFileEntry(entry)
                }
                await mergeEngine.invalidateCache(path)
            }

            return Int32(size)
        } catch {
            Logger.shared.error("DMSAFileSystem: writeFile error: \(error)")
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
            return -1
        }
    }

    /// 截断文件
    @objc func truncateFile(atPath path: String, offset: off_t, error: NSErrorPointer) -> Bool {
        Logger.shared.debug("DMSAFileSystem: truncateFile \(path) offset:\(offset)")

        guard let localPath = localPath(for: path) else {
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
            return false
        }

        do {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: localPath))
            try handle.truncate(atOffset: UInt64(offset))
            try handle.close()

            // 更新数据库
            if var entry = databaseManager.getFileEntry(virtualPath: path) {
                entry.size = offset
                entry.isDirty = true
                databaseManager.saveFileEntry(entry)
            }

            return true
        } catch {
            Logger.shared.error("DMSAFileSystem: truncateFile error: \(error)")
            return false
        }
    }

    // MARK: - 创建/删除

    /// 创建目录
    @objc func createDirectory(atPath path: String, attributes: [String: Any]?, error: NSErrorPointer) -> Bool {
        Logger.shared.debug("DMSAFileSystem: createDirectory \(path)")

        guard let localPath = localPath(for: path) else {
            error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL))
            return false
        }

        do {
            try FileManager.default.createDirectory(atPath: localPath, withIntermediateDirectories: true)

            // 添加到数据库
            let entry = FileEntry(virtualPath: path, localPath: localPath)
            entry.isDirectory = true
            entry.location = .localOnly
            entry.isDirty = true
            entry.syncPairId = syncPair.id
            databaseManager.saveFileEntry(entry)

            Task {
                await mergeEngine.invalidateCache(path)
            }

            return true
        } catch {
            Logger.shared.error("DMSAFileSystem: createDirectory error: \(error)")
            return false
        }
    }

    /// 创建文件
    @objc func createFile(atPath path: String, attributes: [String: Any]?,
                          flags: Int32, userData: inout Any?) -> Bool {
        Logger.shared.debug("DMSAFileSystem: createFile \(path)")

        guard let localPath = localPath(for: path) else {
            return false
        }

        let fm = FileManager.default
        let url = URL(fileURLWithPath: localPath)

        do {
            // 确保父目录存在
            let parentDir = url.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // 创建空文件
            fm.createFile(atPath: localPath, contents: nil)

            // 添加到数据库
            let entry = FileEntry(virtualPath: path, localPath: localPath)
            entry.location = .localOnly
            entry.isDirty = true
            entry.syncPairId = syncPair.id
            databaseManager.saveFileEntry(entry)

            // 打开文件句柄
            let handle = try FileHandle(forWritingTo: url)
            handleLock.lock()
            openFileHandles[path] = handle
            handleLock.unlock()

            userData = path as AnyObject

            Task {
                await mergeEngine.invalidateCache(path)
            }

            return true
        } catch {
            Logger.shared.error("DMSAFileSystem: createFile error: \(error)")
            return false
        }
    }

    /// 删除文件
    @objc func removeItem(atPath path: String, error: NSErrorPointer) -> Bool {
        Logger.shared.debug("DMSAFileSystem: removeItem \(path)")

        let fm = FileManager.default
        var success = true

        // 删除本地副本
        if let local = localPath(for: path), fm.fileExists(atPath: local) {
            do {
                try fm.removeItem(atPath: local)
            } catch {
                Logger.shared.error("DMSAFileSystem: removeItem local error: \(error)")
                success = false
            }
        }

        // 删除外部副本
        if let external = externalPath(for: path), fm.fileExists(atPath: external) {
            do {
                try fm.removeItem(atPath: external)
            } catch {
                Logger.shared.warning("DMSAFileSystem: removeItem external error: \(error)")
            }
        }

        // 从数据库删除
        databaseManager.deleteFileEntry(virtualPath: path)

        Task {
            await mergeEngine.invalidateCache(path)
        }

        return success
    }

    /// 删除目录
    @objc func removeDirectory(atPath path: String, error: NSErrorPointer) -> Bool {
        return removeItem(atPath: path, error: error)
    }

    // MARK: - 移动/重命名

    /// 移动文件/目录
    @objc func moveItem(atPath source: String, toPath destination: String, error: NSErrorPointer) -> Bool {
        Logger.shared.debug("DMSAFileSystem: moveItem \(source) -> \(destination)")

        let fm = FileManager.default

        // 移动本地副本
        if let srcLocal = localPath(for: source),
           let dstLocal = localPath(for: destination),
           fm.fileExists(atPath: srcLocal) {
            do {
                // 确保目标目录存在
                let dstParent = (dstLocal as NSString).deletingLastPathComponent
                if !fm.fileExists(atPath: dstParent) {
                    try fm.createDirectory(atPath: dstParent, withIntermediateDirectories: true)
                }
                try fm.moveItem(atPath: srcLocal, toPath: dstLocal)
            } catch {
                Logger.shared.error("DMSAFileSystem: moveItem local error: \(error)")
                return false
            }
        }

        // 移动外部副本
        if let srcExt = externalPath(for: source),
           let dstExt = externalPath(for: destination),
           fm.fileExists(atPath: srcExt) {
            do {
                let dstParent = (dstExt as NSString).deletingLastPathComponent
                if !fm.fileExists(atPath: dstParent) {
                    try fm.createDirectory(atPath: dstParent, withIntermediateDirectories: true)
                }
                try fm.moveItem(atPath: srcExt, toPath: dstExt)
            } catch {
                Logger.shared.warning("DMSAFileSystem: moveItem external error: \(error)")
            }
        }

        // 更新数据库
        if var entry = databaseManager.getFileEntry(virtualPath: source) {
            entry.virtualPath = destination
            if let newLocal = localPath(for: destination) {
                entry.localPath = newLocal
            }
            if let newExt = externalPath(for: destination) {
                entry.externalPath = newExt
            }
            databaseManager.saveFileEntry(entry)
            databaseManager.deleteFileEntry(virtualPath: source)
        }

        Task {
            await mergeEngine.invalidateCache(source)
            await mergeEngine.invalidateCache(destination)
        }

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

        // 解析 null 分隔的名称列表
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
        guard let localPath = localPath(for: path) else {
            return false
        }

        let result = value.withUnsafeBytes { buffer in
            setxattr(localPath, name, buffer.baseAddress, value.count, UInt32(position), options)
        }

        return result == 0
    }

    /// 删除扩展属性
    @objc func removeExtendedAttribute(withName name: String, ofItemAtPath path: String,
                                       error: NSErrorPointer) -> Bool {
        guard let localPath = localPath(for: path) else {
            return false
        }

        return removexattr(localPath, name, 0) == 0
    }
}

// MARK: - 错误类型

enum FUSEMountError: Error, LocalizedError {
    case alreadyMounted
    case fuseNotAvailable
    case mountFailed(String)
    case unmountFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyMounted:
            return "文件系统已挂载"
        case .fuseNotAvailable:
            return "macFUSE 未安装或不可用"
        case .mountFailed(let reason):
            return "挂载失败: \(reason)"
        case .unmountFailed(let reason):
            return "卸载失败: \(reason)"
        }
    }
}
