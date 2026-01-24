import Foundation

/// VFS 核心 - FUSE 操作入口
/// 根据 VFS_DESIGN.md 负责 FUSE 挂载和回调分发
///
/// 注意: 实际 FUSE-T 集成需要:
/// 1. 安装 FUSE-T: https://github.com/macos-fuse-t/fuse-t
/// 2. 导入 FUSE-T Swift 包装器
/// 3. 实现 fuse_operations 回调
class VFSCore {

    // MARK: - 单例

    static let shared = VFSCore()

    // MARK: - 依赖

    private let mergeEngine: MergeEngine
    private let readRouter: ReadRouter
    private let writeRouter: WriteRouter
    private let lockManager: LockManager
    private let privilegedClient: PrivilegedClient
    private let configManager: ConfigManager
    // TreeVersionManager 是 actor，按需访问 TreeVersionManager.shared
    private let databaseManager: DatabaseManager

    // MARK: - 状态

    private var mountedPairs: [UUID: MountInfo] = [:]
    private let stateLock = NSLock()

    /// 挂载信息
    struct MountInfo {
        let syncPairId: UUID
        let syncPair: SyncPairConfig
        let targetDir: String
        let localDir: String
        let externalDir: String
        var isMounted: Bool
        /// macFUSE 文件系统实例
        var fileSystem: DMSAFileSystem?
    }

    // MARK: - 初始化

    private init() {
        self.mergeEngine = MergeEngine.shared
        self.readRouter = ReadRouter.shared
        self.writeRouter = WriteRouter.shared
        self.lockManager = LockManager.shared
        self.privilegedClient = PrivilegedClient.shared
        self.configManager = ConfigManager.shared
        self.databaseManager = DatabaseManager.shared
    }

    // MARK: - 挂载管理

    /// 启动所有 VFS 挂载
    func startAll() async throws {
        Logger.shared.info("VFSCore: 启动所有 VFS 挂载")

        // 1. 检查 macFUSE 是否可用
        guard FUSEManager.shared.handleStartupCheck() else {
            Logger.shared.error("VFSCore: macFUSE 不可用，无法启动 VFS")
            throw VFSCoreError.fuseNotAvailable
        }

        // 2. 确保 Helper 已安装
        try await privilegedClient.ensureHelperInstalled()

        // 3. 获取所有启用的同步对
        let syncPairs = configManager.getEnabledSyncPairs()

        if syncPairs.isEmpty {
            Logger.shared.warning("VFSCore: 没有启用的同步对")
            return
        }

        // 4. 逐个挂载
        for pair in syncPairs {
            do {
                try await mount(syncPair: pair)
            } catch {
                Logger.shared.error("VFSCore: 挂载失败 \(pair.targetDir): \(error.localizedDescription)")
                // 继续尝试挂载其他同步对
            }
        }

        Logger.shared.info("VFSCore: 已挂载 \(mountedPairs.count) 个 VFS")
    }

    /// 挂载单个同步对
    func mount(syncPair: SyncPairConfig) async throws {
        guard let syncPairId = UUID(uuidString: syncPair.id) else {
            throw VFSCoreError.invalidSyncPairId(syncPair.id)
        }

        stateLock.lock()
        if mountedPairs[syncPairId] != nil {
            stateLock.unlock()
            Logger.shared.warning("VFSCore: \(syncPair.targetDir) 已挂载")
            return
        }
        stateLock.unlock()

        Logger.shared.info("VFSCore: 开始挂载 \(syncPair.targetDir)")

        // 1. 准备目录
        try await prepareDirectories(syncPair: syncPair)

        // 2. 检查并执行版本重建
        // TODO: 需要将 TreeVersionManager.swift 添加到 Xcode 项目中
        // let versionCheck = await TreeVersionManager.shared.checkVersionsOnStartup(for: syncPair)
        // if versionCheck.needRebuildLocal {
        //     try await TreeVersionManager.shared.rebuildTree(for: syncPair, source: TreeSource.local)
        // }
        // if versionCheck.needRebuildExternal && versionCheck.externalConnected {
        //     try await TreeVersionManager.shared.rebuildTree(for: syncPair, source: TreeSource.external)
        // }

        // 3. 保护 LOCAL_DIR (防止用户直接访问)
        do {
            try await privilegedClient.protectDirectory(syncPair.localDir)
        } catch {
            Logger.shared.warning("VFSCore: 保护目录失败 (可能 Helper 未安装): \(error.localizedDescription)")
            // 不阻止挂载，但记录警告
        }

        // 4. 创建挂载点目录
        let fm = FileManager.default
        let targetDir = (syncPair.targetDir as NSString).expandingTildeInPath
        if !fm.fileExists(atPath: targetDir) {
            try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true, attributes: nil)
        }

        // 5. 启动 macFUSE 挂载
        let fileSystem = DMSAFileSystem(syncPair: syncPair)

        do {
            try fileSystem.mount(at: targetDir)
        } catch {
            Logger.shared.error("VFSCore: macFUSE 挂载失败: \(error.localizedDescription)")
            throw VFSCoreError.mountFailed(targetDir)
        }

        let mountInfo = MountInfo(
            syncPairId: syncPairId,
            syncPair: syncPair,
            targetDir: targetDir,
            localDir: (syncPair.localDir as NSString).expandingTildeInPath,
            externalDir: syncPair.externalDir,
            isMounted: true,
            fileSystem: fileSystem
        )

        stateLock.lock()
        mountedPairs[syncPairId] = mountInfo
        stateLock.unlock()

        Logger.shared.info("VFSCore: 已挂载 \(targetDir) (macFUSE)")

        // 6. 启动文件变更监控
        startFileMonitoring(for: syncPair)
    }

    /// 卸载单个同步对
    func unmount(syncPairId: UUID) async throws {
        stateLock.lock()
        guard var info = mountedPairs[syncPairId] else {
            stateLock.unlock()
            return
        }
        mountedPairs.removeValue(forKey: syncPairId)
        stateLock.unlock()

        Logger.shared.info("VFSCore: 开始卸载 \(info.targetDir)")

        // 1. 停止文件监控
        stopFileMonitoring(for: info.syncPair)

        // 2. 停止 macFUSE
        info.fileSystem?.unmount()
        info.isMounted = false

        // 3. 解除 LOCAL_DIR 保护
        do {
            try await privilegedClient.unprotectDirectory(info.localDir)
        } catch {
            Logger.shared.warning("VFSCore: 解除保护失败: \(error.localizedDescription)")
        }

        Logger.shared.info("VFSCore: 已卸载 \(info.targetDir)")
    }

    /// 停止所有挂载
    func stopAll() async throws {
        Logger.shared.info("VFSCore: 停止所有 VFS 挂载")

        let pairIds = stateLock.withLock { Array(mountedPairs.keys) }

        for id in pairIds {
            do {
                try await unmount(syncPairId: id)
            } catch {
                Logger.shared.error("VFSCore: 卸载失败 \(id): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 目录准备

    private func prepareDirectories(syncPair: SyncPairConfig) async throws {
        let fm = FileManager.default
        let targetDir = (syncPair.targetDir as NSString).expandingTildeInPath
        let localDir = (syncPair.localDir as NSString).expandingTildeInPath

        // 如果 TARGET_DIR 已存在且不是 FUSE 挂载点
        if fm.fileExists(atPath: targetDir) {
            // 检查是否已经是挂载点
            if !isMountPoint(targetDir) {
                // 检查 LOCAL_DIR 是否存在
                if !fm.fileExists(atPath: localDir) {
                    // 重命名 TARGET_DIR -> LOCAL_DIR
                    try fm.moveItem(atPath: targetDir, toPath: localDir)
                    Logger.shared.info("VFSCore: 重命名 \(targetDir) -> \(localDir)")
                } else {
                    Logger.shared.warning("VFSCore: LOCAL_DIR 已存在，跳过重命名")
                }
            }
        }

        // 确保 LOCAL_DIR 存在
        if !fm.fileExists(atPath: localDir) {
            try fm.createDirectory(atPath: localDir, withIntermediateDirectories: true, attributes: nil)
            Logger.shared.info("VFSCore: 创建 LOCAL_DIR: \(localDir)")
        }
    }

    /// 检查是否为挂载点
    private func isMountPoint(_ path: String) -> Bool {
        // 简单检查：通过 statfs 判断
        var statInfo = statfs()
        if statfs(path, &statInfo) == 0 {
            let fsType = withUnsafePointer(to: &statInfo.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                    String(cString: $0)
                }
            }
            // FUSE 文件系统通常标识为 "osxfuse" 或 "fuse-t"
            return fsType.lowercased().contains("fuse")
        }
        return false
    }

    // MARK: - 文件监控

    private func startFileMonitoring(for syncPair: SyncPairConfig) {
        // TODO: 集成 FSEventsMonitor
        Logger.shared.debug("VFSCore: 启动文件监控 \(syncPair.localDir)")
    }

    private func stopFileMonitoring(for syncPair: SyncPairConfig) {
        // TODO: 停止 FSEventsMonitor
        Logger.shared.debug("VFSCore: 停止文件监控 \(syncPair.localDir)")
    }

    // MARK: - FUSE 回调 (由 FUSE-T 调用)

    /// getattr - 获取文件属性
    func fuseGetattr(_ path: String, syncPairId: UUID) async -> (st_size: Int64, st_mode: UInt16, errno: Int32) {
        do {
            let attrs = try await mergeEngine.getAttributes(path, syncPairId: syncPairId)

            let mode: UInt16 = attrs.isDirectory ? UInt16(S_IFDIR | 0o755) : UInt16(S_IFREG | 0o644)

            return (attrs.size, mode, 0)
        } catch {
            Logger.shared.debug("VFSCore getattr error: \(path) - \(error)")
            return (0, 0, ENOENT)
        }
    }

    /// readdir - 读取目录
    func fuseReaddir(_ path: String, syncPairId: UUID) async -> ([String]?, Int32) {
        do {
            let entries = try await mergeEngine.listDirectory(path, syncPairId: syncPairId)
            var names = [".", ".."]
            names.append(contentsOf: entries.map { $0.name })
            return (names, 0)
        } catch {
            Logger.shared.debug("VFSCore readdir error: \(path) - \(error)")
            return (nil, ENOENT)
        }
    }

    /// open - 打开文件
    func fuseOpen(_ path: String, flags: Int32, syncPairId: UUID) async -> (fd: Int32, errno: Int32) {
        // 检查锁状态
        if lockManager.isLocked(path) {
            return (-1, EBUSY)
        }

        // 解析实际路径
        let result = readRouter.resolveReadPath(path)
        switch result {
        case .success(let actualPath):
            let fd = open(actualPath, flags)
            if fd >= 0 {
                // 更新访问时间
                databaseManager.updateAccessTime(path)
            }
            return (fd, fd >= 0 ? 0 : errno)
        case .failure:
            return (-1, ENOENT)
        }
    }

    /// read - 读取数据
    func fuseRead(_ path: String, buffer: UnsafeMutablePointer<UInt8>, size: Int, offset: off_t, fd: Int32) -> Int32 {
        let bytesRead = pread(fd, buffer, size, offset)
        return bytesRead >= 0 ? Int32(bytesRead) : -errno
    }

    /// write - 写入数据
    func fuseWrite(_ path: String, buffer: UnsafePointer<UInt8>, size: Int, offset: off_t, syncPairId: UUID) async -> Int32 {
        // 检查锁
        if lockManager.isLocked(path) {
            return -EBUSY
        }

        // 通过 WriteRouter 写入 LOCAL_DIR
        guard let syncPair = getSyncPair(for: syncPairId) else {
            return -ENOENT
        }

        guard let localPath = PathValidator.localPath(for: path, in: syncPair) else {
            return -EINVAL
        }

        // 写入文件
        let fm = FileManager.default
        let url = URL(fileURLWithPath: localPath)

        do {
            // 确保父目录存在
            let parentDir = url.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
            }

            // 写入数据
            let data = Data(bytes: buffer, count: size)
            if fm.fileExists(atPath: localPath) {
                // 追加或覆盖
                let handle = try FileHandle(forWritingTo: url)
                try handle.seek(toOffset: UInt64(offset))
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                // 创建新文件
                try data.write(to: url)
            }

            // 标记为脏数据
            writeRouter.markDirty(path)

            // 使缓存失效
            await mergeEngine.invalidateCache(path)

            return Int32(size)
        } catch {
            Logger.shared.error("VFSCore write error: \(path) - \(error)")
            return -EIO
        }
    }

    /// create - 创建文件
    func fuseCreate(_ path: String, mode: mode_t, syncPairId: UUID) async -> Int32 {
        guard let syncPair = getSyncPair(for: syncPairId) else {
            return -ENOENT
        }

        guard let localPath = PathValidator.localPath(for: path, in: syncPair) else {
            return -EINVAL
        }

        let fm = FileManager.default
        let url = URL(fileURLWithPath: localPath)

        do {
            // 确保父目录存在
            let parentDir = url.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
            }

            // 创建空文件
            fm.createFile(atPath: localPath, contents: nil, attributes: nil)

            // 添加到数据库
            let entry = FileEntry(virtualPath: path, localPath: localPath)
            entry.location = .localOnly
            entry.isDirty = true
            entry.syncPairId = syncPair.id
            databaseManager.saveFileEntry(entry)

            // 使缓存失效
            await mergeEngine.invalidateCache(path)

            return 0
        } catch {
            Logger.shared.error("VFSCore create error: \(path) - \(error)")
            return -EIO
        }
    }

    /// unlink - 删除文件
    func fuseUnlink(_ path: String, syncPairId: UUID) async -> Int32 {
        guard let syncPair = getSyncPair(for: syncPairId) else {
            return -ENOENT
        }

        let fm = FileManager.default

        // 删除 LOCAL 副本
        if let localPath = PathValidator.localPath(for: path, in: syncPair),
           fm.fileExists(atPath: localPath) {
            do {
                try fm.removeItem(atPath: localPath)
            } catch {
                Logger.shared.error("VFSCore unlink LOCAL error: \(error)")
            }
        }

        // 删除 EXTERNAL 副本 (如果已连接)
        if let externalPath = PathValidator.externalPath(for: path, in: syncPair),
           fm.fileExists(atPath: externalPath) {
            do {
                try fm.removeItem(atPath: externalPath)
            } catch {
                Logger.shared.error("VFSCore unlink EXTERNAL error: \(error)")
            }
        }

        // 从数据库删除
        databaseManager.deleteFileEntry(virtualPath: path)

        // 使缓存失效
        await mergeEngine.invalidateCache(path)

        return 0
    }

    /// mkdir - 创建目录
    func fuseMkdir(_ path: String, mode: mode_t, syncPairId: UUID) async -> Int32 {
        guard let syncPair = getSyncPair(for: syncPairId) else {
            return -ENOENT
        }

        guard let localPath = PathValidator.localPath(for: path, in: syncPair) else {
            return -EINVAL
        }

        do {
            try FileManager.default.createDirectory(
                atPath: localPath,
                withIntermediateDirectories: true,
                attributes: nil
            )

            // 添加到数据库
            let entry = FileEntry(virtualPath: path, localPath: localPath)
            entry.isDirectory = true
            entry.location = .localOnly
            entry.isDirty = true
            entry.syncPairId = syncPair.id
            databaseManager.saveFileEntry(entry)

            await mergeEngine.invalidateCache(path)

            return 0
        } catch {
            Logger.shared.error("VFSCore mkdir error: \(path) - \(error)")
            return -EIO
        }
    }

    /// rmdir - 删除目录
    func fuseRmdir(_ path: String, syncPairId: UUID) async -> Int32 {
        guard let syncPair = getSyncPair(for: syncPairId) else {
            return -ENOENT
        }

        let fm = FileManager.default

        // 删除 LOCAL 目录
        if let localPath = PathValidator.localPath(for: path, in: syncPair),
           fm.fileExists(atPath: localPath) {
            do {
                try fm.removeItem(atPath: localPath)
            } catch {
                return -ENOTEMPTY
            }
        }

        // 删除 EXTERNAL 目录
        if let externalPath = PathValidator.externalPath(for: path, in: syncPair),
           fm.fileExists(atPath: externalPath) {
            do {
                try fm.removeItem(atPath: externalPath)
            } catch {
                Logger.shared.warning("VFSCore rmdir EXTERNAL failed: \(error)")
            }
        }

        databaseManager.deleteFileEntry(virtualPath: path)
        await mergeEngine.invalidateCache(path)

        return 0
    }

    /// rename - 重命名
    func fuseRename(_ from: String, to: String, syncPairId: UUID) async -> Int32 {
        guard let syncPair = getSyncPair(for: syncPairId) else {
            return -ENOENT
        }

        let fm = FileManager.default

        // 重命名 LOCAL
        if let fromLocal = PathValidator.localPath(for: from, in: syncPair),
           let toLocal = PathValidator.localPath(for: to, in: syncPair),
           fm.fileExists(atPath: fromLocal) {
            do {
                try fm.moveItem(atPath: fromLocal, toPath: toLocal)
            } catch {
                return -EIO
            }
        }

        // 重命名 EXTERNAL
        if let fromExternal = PathValidator.externalPath(for: from, in: syncPair),
           let toExternal = PathValidator.externalPath(for: to, in: syncPair),
           fm.fileExists(atPath: fromExternal) {
            do {
                try fm.moveItem(atPath: fromExternal, toPath: toExternal)
            } catch {
                Logger.shared.warning("VFSCore rename EXTERNAL failed: \(error)")
            }
        }

        // 更新数据库
        if var entry = databaseManager.getFileEntry(virtualPath: from) {
            entry.virtualPath = to
            if let toLocal = PathValidator.localPath(for: to, in: syncPair) {
                entry.localPath = toLocal
            }
            if let toExternal = PathValidator.externalPath(for: to, in: syncPair) {
                entry.externalPath = toExternal
            }
            databaseManager.saveFileEntry(entry)
            databaseManager.deleteFileEntry(virtualPath: from)
        }

        await mergeEngine.invalidateCache(from)
        await mergeEngine.invalidateCache(to)

        return 0
    }

    // MARK: - 辅助方法

    private func getSyncPair(for syncPairId: UUID) -> SyncPairConfig? {
        stateLock.lock()
        let info = mountedPairs[syncPairId]
        stateLock.unlock()
        return info?.syncPair
    }

    /// 获取挂载状态
    func getMountedPairs() -> [MountInfo] {
        stateLock.lock()
        let pairs = Array(mountedPairs.values)
        stateLock.unlock()
        return pairs
    }

    /// 检查是否已挂载
    func isMounted(syncPairId: UUID) -> Bool {
        stateLock.lock()
        let mounted = mountedPairs[syncPairId]?.isMounted ?? false
        stateLock.unlock()
        return mounted
    }
}

// MARK: - ConfigManager 扩展

extension ConfigManager {
    /// 获取所有启用的同步对
    func getEnabledSyncPairs() -> [SyncPairConfig] {
        return config.syncPairs.filter { $0.enabled }
    }
}

// MARK: - LockManager 已有 isLocked 方法 (在 LockManager.swift:161)
// 不需要额外扩展

// MARK: - WriteRouter 扩展

extension WriteRouter {
    /// 标记文件为脏
    func markDirty(_ virtualPath: String) {
        // 通过 DatabaseManager 标记
        if var entry = DatabaseManager.shared.getFileEntry(virtualPath: virtualPath) {
            entry.isDirty = true
            DatabaseManager.shared.saveFileEntry(entry)
        }
    }
}

// MARK: - NSLock 扩展

extension NSLock {
    func withLock<T>(_ closure: () -> T) -> T {
        lock()
        defer { unlock() }
        return closure()
    }
}

// MARK: - 错误类型

enum VFSCoreError: Error, LocalizedError {
    case invalidSyncPairId(String)
    case mountFailed(String)
    case unmountFailed(String)
    case helperNotInstalled
    case fuseNotAvailable

    var errorDescription: String? {
        switch self {
        case .invalidSyncPairId(let id):
            return "无效的同步对 ID: \(id)"
        case .mountFailed(let path):
            return "挂载失败: \(path)"
        case .unmountFailed(let path):
            return "卸载失败: \(path)"
        case .helperNotInstalled:
            return "特权助手未安装"
        case .fuseNotAvailable:
            return "FUSE 不可用"
        }
    }
}
