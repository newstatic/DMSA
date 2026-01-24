import Foundation

// MARK: - Service 配置管理器
// 使用 JSON 存储服务配置和运行时状态
// 配置目录: /Library/Application Support/DMSA/ServiceData/

/// 服务运行时状态
public struct ServiceRuntimeState: Codable, Sendable {
    /// VFS 挂载状态
    public var mountedPairs: [String: MountState] = [:]

    /// 同步状态
    public var syncStates: [String: SyncState] = [:]

    /// 硬盘连接状态
    public var diskStates: [String: DiskState] = [:]

    /// 服务启动时间
    public var serviceStartTime: Date?

    /// 最后活动时间
    public var lastActiveTime: Date = Date()

    public init() {}
}

/// VFS 挂载状态
public struct MountState: Codable, Sendable {
    public var syncPairId: String
    public var targetDir: String
    public var localDir: String
    public var externalDir: String?
    public var isMounted: Bool = false
    public var isExternalOnline: Bool = false
    public var mountedAt: Date?
    public var fileCount: Int = 0
    public var totalSize: Int64 = 0

    public init(syncPairId: String, targetDir: String, localDir: String) {
        self.syncPairId = syncPairId
        self.targetDir = targetDir
        self.localDir = localDir
    }
}

/// 同步状态
public struct SyncState: Codable, Sendable {
    public var syncPairId: String
    public var status: String = "idle"  // idle, syncing, paused, error
    public var lastSyncTime: Date?
    public var nextSyncTime: Date?
    public var dirtyFileCount: Int = 0
    public var pendingTaskCount: Int = 0
    public var currentFile: String?
    public var progress: Double = 0  // 0.0 - 1.0
    public var errorMessage: String?

    public init(syncPairId: String) {
        self.syncPairId = syncPairId
    }
}

/// 硬盘状态
public struct DiskState: Codable, Sendable {
    public var diskId: String
    public var diskName: String
    public var mountPath: String?
    public var isConnected: Bool = false
    public var lastConnectedAt: Date?
    public var lastDisconnectedAt: Date?
    public var totalSpace: Int64 = 0
    public var freeSpace: Int64 = 0

    public init(diskId: String, diskName: String) {
        self.diskId = diskId
        self.diskName = diskName
    }
}

/// 淘汰配置
public struct EvictionConfig: Codable, Sendable {
    /// 触发淘汰的可用空间阈值 (bytes)
    public var triggerThreshold: Int64 = 5 * 1024 * 1024 * 1024  // 5GB

    /// 淘汰目标可用空间 (bytes)
    public var targetFreeSpace: Int64 = 10 * 1024 * 1024 * 1024  // 10GB

    /// 单次淘汰最大文件数
    public var maxFilesPerRun: Int = 100

    /// 最小文件年龄 (秒) - 防止淘汰刚访问的文件
    public var minFileAge: TimeInterval = 3600  // 1小时

    /// 自动淘汰间隔 (秒)
    public var checkInterval: TimeInterval = 300  // 5分钟

    /// 是否启用自动淘汰
    public var autoEnabled: Bool = true

    public init() {}
}

/// 同步配置 (服务端)
public struct ServiceSyncConfig: Codable, Sendable {
    /// 启用校验和
    public var enableChecksum: Bool = true

    /// 校验算法
    public var checksumAlgorithm: String = "md5"

    /// 复制后验证
    public var verifyAfterCopy: Bool = true

    /// 冲突策略
    public var conflictStrategy: String = "localWinsWithBackup"

    /// 启用删除同步
    public var enableDelete: Bool = false

    /// 排除模式
    public var excludePatterns: [String] = []

    /// 防抖间隔 (秒)
    public var debounceInterval: TimeInterval = 5.0

    /// 自动同步间隔 (秒)
    public var autoSyncInterval: TimeInterval = 3600  // 1小时

    public init() {}
}

/// 服务配置
public struct ServiceConfig: Codable, Sendable {
    /// 淘汰配置
    public var eviction: EvictionConfig = EvictionConfig()

    /// 同步配置
    public var sync: ServiceSyncConfig = ServiceSyncConfig()

    /// 日志级别
    public var logLevel: String = "info"

    /// 启用性能监控
    public var enablePerformanceMonitoring: Bool = false

    /// 健康检查间隔 (秒)
    public var healthCheckInterval: TimeInterval = 60

    public init() {}
}

// MARK: - Service 配置管理器

/// DMSAService 配置管理器
/// - 配置文件: /Library/Application Support/DMSA/ServiceData/config.json
/// - 状态文件: /Library/Application Support/DMSA/ServiceData/state.json
actor ServiceConfigManager {

    static let shared = ServiceConfigManager()

    private let logger = Logger.forService("Config")
    private let fileManager = FileManager.default

    // 配置目录
    private let dataDirectory: URL

    // 文件路径
    private let configURL: URL
    private let stateURL: URL

    // 内存数据
    private var config: ServiceConfig = ServiceConfig()
    private var state: ServiceRuntimeState = ServiceRuntimeState()

    // 保存防抖
    private var saveTask: Task<Void, Never>?
    private let saveDebounce: TimeInterval = 1.0

    private init() {
        dataDirectory = URL(fileURLWithPath: "/Library/Application Support/DMSA/ServiceData")
        configURL = dataDirectory.appendingPathComponent("config.json")
        stateURL = dataDirectory.appendingPathComponent("state.json")

        Task {
            await initialize()
        }
    }

    // MARK: - 初始化

    private func initialize() async {
        // 确保目录存在
        do {
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("创建配置目录失败: \(error)")
        }

        // 加载配置
        await loadConfig()
        await loadState()

        // 更新服务启动时间
        state.serviceStartTime = Date()
        state.lastActiveTime = Date()
        await saveState()

        logger.info("ServiceConfigManager 初始化完成")
    }

    // MARK: - Config 操作

    private func loadConfig() async {
        guard let data = try? Data(contentsOf: configURL) else {
            logger.info("配置文件不存在，使用默认配置")
            await saveConfig()
            return
        }

        do {
            config = try JSONDecoder().decode(ServiceConfig.self, from: data)
            logger.info("加载服务配置")
        } catch {
            logger.error("解析配置失败: \(error)")
        }
    }

    func getConfig() -> ServiceConfig {
        return config
    }

    func updateConfig(_ newConfig: ServiceConfig) async {
        config = newConfig
        await saveConfig()
    }

    func updateEvictionConfig(_ eviction: EvictionConfig) async {
        config.eviction = eviction
        await saveConfig()
    }

    func updateSyncConfig(_ sync: ServiceSyncConfig) async {
        config.sync = sync
        await saveConfig()
    }

    private func saveConfig() async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
            logger.debug("保存服务配置")
        } catch {
            logger.error("保存配置失败: \(error)")
        }
    }

    // MARK: - State 操作

    private func loadState() async {
        guard let data = try? Data(contentsOf: stateURL) else {
            return
        }

        do {
            state = try JSONDecoder().decode(ServiceRuntimeState.self, from: data)
            logger.info("加载运行时状态")
        } catch {
            logger.error("解析状态失败: \(error)")
            state = ServiceRuntimeState()
        }
    }

    func getState() -> ServiceRuntimeState {
        return state
    }

    // MARK: - Mount State

    func getMountState(syncPairId: String) -> MountState? {
        return state.mountedPairs[syncPairId]
    }

    func setMountState(_ mountState: MountState) async {
        state.mountedPairs[mountState.syncPairId] = mountState
        state.lastActiveTime = Date()
        scheduleSaveState()
    }

    func removeMountState(syncPairId: String) async {
        state.mountedPairs.removeValue(forKey: syncPairId)
        state.lastActiveTime = Date()
        scheduleSaveState()
    }

    func getAllMountStates() -> [MountState] {
        return Array(state.mountedPairs.values)
    }

    // MARK: - Sync State

    func getSyncState(syncPairId: String) -> SyncState? {
        return state.syncStates[syncPairId]
    }

    func setSyncState(_ syncState: SyncState) async {
        state.syncStates[syncState.syncPairId] = syncState
        state.lastActiveTime = Date()
        scheduleSaveState()
    }

    func updateSyncProgress(syncPairId: String, status: String, progress: Double, currentFile: String?) async {
        var syncState = state.syncStates[syncPairId] ?? SyncState(syncPairId: syncPairId)
        syncState.status = status
        syncState.progress = progress
        syncState.currentFile = currentFile
        state.syncStates[syncPairId] = syncState
        state.lastActiveTime = Date()
        // 不立即保存进度更新，避免频繁 I/O
    }

    func markSyncCompleted(syncPairId: String) async {
        var syncState = state.syncStates[syncPairId] ?? SyncState(syncPairId: syncPairId)
        syncState.status = "idle"
        syncState.progress = 0
        syncState.currentFile = nil
        syncState.lastSyncTime = Date()
        state.syncStates[syncPairId] = syncState
        state.lastActiveTime = Date()
        scheduleSaveState()
    }

    func getAllSyncStates() -> [SyncState] {
        return Array(state.syncStates.values)
    }

    // MARK: - Disk State

    func getDiskState(diskId: String) -> DiskState? {
        return state.diskStates[diskId]
    }

    func setDiskConnected(diskId: String, diskName: String, mountPath: String) async {
        var diskState = state.diskStates[diskId] ?? DiskState(diskId: diskId, diskName: diskName)
        diskState.isConnected = true
        diskState.mountPath = mountPath
        diskState.lastConnectedAt = Date()

        // 获取磁盘空间
        if let attrs = try? fileManager.attributesOfFileSystem(forPath: mountPath) {
            diskState.totalSpace = attrs[.systemSize] as? Int64 ?? 0
            diskState.freeSpace = attrs[.systemFreeSize] as? Int64 ?? 0
        }

        state.diskStates[diskId] = diskState
        state.lastActiveTime = Date()
        scheduleSaveState()
    }

    func setDiskDisconnected(diskId: String) async {
        guard var diskState = state.diskStates[diskId] else { return }
        diskState.isConnected = false
        diskState.mountPath = nil
        diskState.lastDisconnectedAt = Date()
        state.diskStates[diskId] = diskState
        state.lastActiveTime = Date()
        scheduleSaveState()
    }

    func getAllDiskStates() -> [DiskState] {
        return Array(state.diskStates.values)
    }

    // MARK: - 保存状态

    private func scheduleSaveState() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(saveDebounce * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await saveState()
        }
    }

    private func saveState() async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            logger.error("保存状态失败: \(error)")
        }
    }

    func forceSaveState() async {
        saveTask?.cancel()
        await saveState()
    }

    // MARK: - 清理

    func clearState() async {
        state = ServiceRuntimeState()
        state.serviceStartTime = Date()
        await saveState()
    }

    // MARK: - 健康检查

    func healthCheck() -> Bool {
        return fileManager.fileExists(atPath: dataDirectory.path)
    }
}
