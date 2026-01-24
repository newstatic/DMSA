import Foundation

/// VFS 核心 - 管理 VFS 挂载生命周期
///
/// 作为 XPC 客户端与 DMSAService 通信，所有 FUSE 操作由服务端处理。
/// App 端只负责:
/// 1. 启动/停止 VFS 挂载
/// 2. 目录准备和保护
/// 3. 版本检查和文件树重建
/// 4. 状态查询
class VFSCore {

    // MARK: - 单例

    static let shared = VFSCore()

    // MARK: - 依赖

    private let serviceClient: ServiceClient
    private let configManager: ConfigManager
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
    }

    // MARK: - 初始化

    private init() {
        self.serviceClient = ServiceClient.shared
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

        // 2. 检查服务是否健康
        let isHealthy = try await serviceClient.healthCheck()
        if !isHealthy {
            Logger.shared.warning("VFSCore: DMSAService 健康检查失败")
        }

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

        // 2. 检查并执行版本重建 (启动时检测文件树变更)
        let versionCheck = await TreeVersionManager.shared.checkVersionsOnStartup(for: syncPair)
        if versionCheck.needRebuildLocal {
            Logger.shared.info("VFSCore: LOCAL 需要重建文件树")
            try await TreeVersionManager.shared.rebuildTree(for: syncPair, source: .local)
        }
        if versionCheck.needRebuildExternal && versionCheck.externalConnected {
            Logger.shared.info("VFSCore: EXTERNAL 需要重建文件树")
            try await TreeVersionManager.shared.rebuildTree(for: syncPair, source: .external)
        }

        // 3. 保护 LOCAL_DIR (防止用户直接访问)
        do {
            try await serviceClient.protectDirectory(syncPair.localDir)
        } catch {
            Logger.shared.warning("VFSCore: 保护目录失败 (可能服务未安装): \(error.localizedDescription)")
        }

        // 4. 创建挂载点目录
        let fm = FileManager.default
        let targetDir = (syncPair.targetDir as NSString).expandingTildeInPath
        if !fm.fileExists(atPath: targetDir) {
            try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true, attributes: nil)
        }

        let localDir = (syncPair.localDir as NSString).expandingTildeInPath

        // 5. 通过 XPC 调用 DMSAService 进行 FUSE 挂载
        do {
            try await serviceClient.mountVFS(
                syncPairId: syncPair.id,
                localDir: localDir,
                externalDir: syncPair.externalDir,
                targetDir: targetDir
            )
        } catch {
            Logger.shared.error("VFSCore: DMSAService 挂载失败: \(error.localizedDescription)")
            throw VFSCoreError.mountFailed(targetDir)
        }

        let mountInfo = MountInfo(
            syncPairId: syncPairId,
            syncPair: syncPair,
            targetDir: targetDir,
            localDir: localDir,
            externalDir: syncPair.externalDir,
            isMounted: true
        )

        stateLock.lock()
        mountedPairs[syncPairId] = mountInfo
        stateLock.unlock()

        Logger.shared.info("VFSCore: 已挂载 \(targetDir)")

        // 6. 启动文件变更监控
        startFileMonitoring(for: syncPair)
    }

    /// 卸载单个同步对
    func unmount(syncPairId: UUID) async throws {
        stateLock.lock()
        guard let info = mountedPairs[syncPairId] else {
            stateLock.unlock()
            return
        }
        mountedPairs.removeValue(forKey: syncPairId)
        stateLock.unlock()

        Logger.shared.info("VFSCore: 开始卸载 \(info.targetDir)")

        // 1. 停止文件监控
        stopFileMonitoring(for: info.syncPair)

        // 2. 通过 XPC 调用 DMSAService 卸载 FUSE
        do {
            try await serviceClient.unmountVFS(syncPairId: info.syncPair.id)
        } catch {
            Logger.shared.warning("VFSCore: DMSAService 卸载失败: \(error.localizedDescription)")
        }

        // 3. 解除 LOCAL_DIR 保护
        do {
            try await serviceClient.unprotectDirectory(info.localDir)
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

    // MARK: - 状态查询

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

    /// 获取同步对配置
    func getSyncPair(for syncPairId: UUID) -> SyncPairConfig? {
        stateLock.lock()
        let info = mountedPairs[syncPairId]
        stateLock.unlock()
        return info?.syncPair
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
        var statInfo = statfs()
        if statfs(path, &statInfo) == 0 {
            let fsType = withUnsafePointer(to: &statInfo.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                    String(cString: $0)
                }
            }
            // FUSE 文件系统通常标识为 "osxfuse" 或 "macfuse"
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
}

// MARK: - ConfigManager 扩展

extension ConfigManager {
    /// 获取所有启用的同步对
    func getEnabledSyncPairs() -> [SyncPairConfig] {
        return config.syncPairs.filter { $0.enabled }
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
    case fuseNotAvailable

    var errorDescription: String? {
        switch self {
        case .invalidSyncPairId(let id):
            return "无效的同步对 ID: \(id)"
        case .mountFailed(let path):
            return "挂载失败: \(path)"
        case .unmountFailed(let path):
            return "卸载失败: \(path)"
        case .fuseNotAvailable:
            return "FUSE 不可用"
        }
    }
}
