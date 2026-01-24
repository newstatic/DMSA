import Foundation

/// VFS 文件系统委托协议
protocol VFSFileSystemDelegate: AnyObject, Sendable {
    func fileWritten(virtualPath: String, syncPairId: String)
    func fileRead(virtualPath: String, syncPairId: String)
    func fileDeleted(virtualPath: String, syncPairId: String)
}

/// VFS 文件系统实现
/// 注意: 实际 FUSE 实现需要 macFUSE 框架，这里提供核心逻辑
actor VFSFileSystem {

    private let logger = Logger.forService("VFS")
    private let syncPairId: String
    private let localDir: String
    private var externalDir: String?
    private weak var delegate: VFSFileSystemDelegate?

    private var isMounted = false
    private var isExternalOffline = false
    private var isReadOnly = false
    private var mountPoint: String?

    init(syncPairId: String,
         localDir: String,
         externalDir: String?,
         delegate: VFSFileSystemDelegate?) {
        self.syncPairId = syncPairId
        self.localDir = localDir
        self.externalDir = externalDir
        self.delegate = delegate
    }

    // MARK: - 挂载管理

    func mount(at path: String) async throws {
        guard !isMounted else {
            throw VFSError.alreadyMounted(path)
        }

        // 在实际实现中，这里会调用 macFUSE 的 GMUserFileSystem
        // 由于 macFUSE 是 Objective-C 框架，需要通过桥接头使用

        // 模拟挂载过程
        mountPoint = path
        isMounted = true
        isExternalOffline = externalDir == nil

        logger.info("VFS 文件系统已挂载: \(path)")
        logger.info("  LOCAL_DIR: \(localDir)")
        logger.info("  EXTERNAL_DIR: \(externalDir ?? "离线")")
    }

    func unmount() async throws {
        guard isMounted else {
            throw VFSError.notMounted(syncPairId)
        }

        // 在实际实现中，这里会调用 unmount
        // [fileSystem unmount]

        isMounted = false
        mountPoint = nil

        logger.info("VFS 文件系统已卸载")
    }

    // MARK: - 配置更新

    func updateExternalDir(_ path: String?) async {
        externalDir = path
        isExternalOffline = path == nil
        logger.info("EXTERNAL_DIR 已更新: \(path ?? "离线")")
    }

    func setExternalOffline(_ offline: Bool) async {
        isExternalOffline = offline
    }

    func setReadOnly(_ readOnly: Bool) async {
        isReadOnly = readOnly
    }

    // MARK: - 文件系统操作

    /// 获取文件属性
    func getAttributes(path: String) -> [FileAttributeKey: Any]? {
        let realPath = resolveRealPath(for: path)

        guard let realPath = realPath else {
            return nil
        }

        return try? FileManager.default.attributesOfItem(atPath: realPath)
    }

    /// 读取目录内容 (智能合并)
    func readDirectory(path: String) -> [String] {
        var contents = Set<String>()
        let fm = FileManager.default

        // 从 LOCAL_DIR 读取
        let localPath = localDir + path
        if let localContents = try? fm.contentsOfDirectory(atPath: localPath) {
            contents.formUnion(localContents)
        }

        // 从 EXTERNAL_DIR 读取 (如果在线)
        if !isExternalOffline, let externalDir = externalDir {
            let externalPath = externalDir + path
            if let externalContents = try? fm.contentsOfDirectory(atPath: externalPath) {
                contents.formUnion(externalContents)
            }
        }

        // 过滤排除的文件
        return contents.filter { !shouldExclude(name: $0) }.sorted()
    }

    /// 读取文件
    func readFile(path: String, offset: UInt64, size: UInt32) -> Data? {
        guard let realPath = resolveRealPath(for: path) else {
            return nil
        }

        guard let handle = FileHandle(forReadingAtPath: realPath) else {
            return nil
        }

        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: offset)
            let data = handle.readData(ofLength: Int(size))

            // 通知读取事件
            delegate?.fileRead(virtualPath: path, syncPairId: syncPairId)

            return data
        } catch {
            logger.error("读取文件失败: \(path) - \(error)")
            return nil
        }
    }

    /// 写入文件
    func writeFile(path: String, offset: UInt64, data: Data) -> Int {
        guard !isReadOnly else {
            return -1  // EROFS
        }

        // 写入到 LOCAL_DIR
        let localPath = localDir + path

        // 确保父目录存在
        let parentDir = (localPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // 如果文件不存在，创建它
        if !FileManager.default.fileExists(atPath: localPath) {
            FileManager.default.createFile(atPath: localPath, contents: nil)
        }

        guard let handle = FileHandle(forWritingAtPath: localPath) else {
            return -1
        }

        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: offset)
            handle.write(data)

            // 通知写入事件
            delegate?.fileWritten(virtualPath: path, syncPairId: syncPairId)

            return data.count
        } catch {
            logger.error("写入文件失败: \(path) - \(error)")
            return -1
        }
    }

    /// 创建文件
    func createFile(path: String, mode: mode_t) -> Bool {
        guard !isReadOnly else { return false }

        let localPath = localDir + path

        // 确保父目录存在
        let parentDir = (localPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        return FileManager.default.createFile(atPath: localPath, contents: nil)
    }

    /// 创建目录
    func createDirectory(path: String, mode: mode_t) -> Bool {
        guard !isReadOnly else { return false }

        let localPath = localDir + path

        do {
            try FileManager.default.createDirectory(atPath: localPath, withIntermediateDirectories: true)
            return true
        } catch {
            logger.error("创建目录失败: \(path) - \(error)")
            return false
        }
    }

    /// 删除文件/目录
    func removeItem(path: String) -> Bool {
        guard !isReadOnly else { return false }

        let localPath = localDir + path

        do {
            try FileManager.default.removeItem(atPath: localPath)
            delegate?.fileDeleted(virtualPath: path, syncPairId: syncPairId)
            return true
        } catch {
            logger.error("删除失败: \(path) - \(error)")
            return false
        }
    }

    /// 移动/重命名
    func moveItem(from: String, to: String) -> Bool {
        guard !isReadOnly else { return false }

        let fromLocal = localDir + from
        let toLocal = localDir + to

        // 确保目标父目录存在
        let parentDir = (toLocal as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        do {
            try FileManager.default.moveItem(atPath: fromLocal, toPath: toLocal)
            delegate?.fileDeleted(virtualPath: from, syncPairId: syncPairId)
            delegate?.fileWritten(virtualPath: to, syncPairId: syncPairId)
            return true
        } catch {
            logger.error("移动失败: \(from) -> \(to) - \(error)")
            return false
        }
    }

    // MARK: - 路径解析

    /// 解析虚拟路径到实际路径
    /// 优先级: LOCAL_DIR > EXTERNAL_DIR
    private func resolveRealPath(for virtualPath: String) -> String? {
        let fm = FileManager.default

        // 首先检查 LOCAL_DIR
        let localPath = localDir + virtualPath
        if fm.fileExists(atPath: localPath) {
            return localPath
        }

        // 如果 EXTERNAL 在线，检查 EXTERNAL_DIR
        if !isExternalOffline, let externalDir = externalDir {
            let externalPath = externalDir + virtualPath
            if fm.fileExists(atPath: externalPath) {
                return externalPath
            }
        }

        return nil
    }

    private func shouldExclude(name: String) -> Bool {
        for pattern in Constants.defaultExcludePatterns {
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
