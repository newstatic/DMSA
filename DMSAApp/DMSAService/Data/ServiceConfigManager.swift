import Foundation

// MARK: - Service Config Manager
// Uses JSON to store service configuration and runtime state
// Config directory: /Library/Application Support/DMSA/ServiceData/

/// Service runtime state
public struct ServiceRuntimeState: Codable, Sendable {
    /// VFS mount states
    public var mountedPairs: [String: MountState] = [:]

    /// Sync states
    public var syncStates: [String: SyncState] = [:]

    /// Disk connection states
    public var diskStates: [String: DiskState] = [:]

    /// Service start time
    public var serviceStartTime: Date?

    /// Last active time
    public var lastActiveTime: Date = Date()

    public init() {}
}

/// VFS mount state
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

/// Sync state
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

/// Disk state
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

/// Eviction config
public struct EvictionConfig: Codable, Sendable {
    /// Available space threshold to trigger eviction (bytes)
    public var triggerThreshold: Int64 = 5 * 1024 * 1024 * 1024  // 5GB

    /// Target free space after eviction (bytes)
    public var targetFreeSpace: Int64 = 10 * 1024 * 1024 * 1024  // 10GB

    /// Max files per eviction run
    public var maxFilesPerRun: Int = 100

    /// Min file age (seconds) - prevents evicting recently accessed files
    public var minFileAge: TimeInterval = 3600  // 1 hour

    /// Auto eviction check interval (seconds)
    public var checkInterval: TimeInterval = 300  // 5 minutes

    /// Whether auto eviction is enabled
    public var autoEnabled: Bool = true

    public init() {}
}

/// Sync config (service-side)
public struct ServiceSyncConfig: Codable, Sendable {
    /// Enable checksum
    public var enableChecksum: Bool = true

    /// Checksum algorithm
    public var checksumAlgorithm: String = "md5"

    /// Verify after copy
    public var verifyAfterCopy: Bool = true

    /// Conflict strategy
    public var conflictStrategy: String = "localWinsWithBackup"

    /// Enable delete sync
    public var enableDelete: Bool = false

    /// Exclude patterns
    public var excludePatterns: [String] = []

    /// Debounce interval (seconds)
    public var debounceInterval: TimeInterval = 5.0

    /// Auto sync interval (seconds)
    public var autoSyncInterval: TimeInterval = 3600  // 1 hour

    public init() {}
}

/// Service config
public struct ServiceConfig: Codable, Sendable {
    /// Eviction config
    public var eviction: EvictionConfig = EvictionConfig()

    /// Sync config
    public var sync: ServiceSyncConfig = ServiceSyncConfig()

    /// Log level
    public var logLevel: String = "info"

    /// Enable performance monitoring
    public var enablePerformanceMonitoring: Bool = false

    /// Health check interval (seconds)
    public var healthCheckInterval: TimeInterval = 60

    public init() {}
}

// MARK: - Service Config Manager

/// DMSAService config manager
/// - Config file: /Library/Application Support/DMSA/ServiceData/config.json
/// - State file: /Library/Application Support/DMSA/ServiceData/state.json
actor ServiceConfigManager {

    static let shared = ServiceConfigManager()

    private let logger = Logger.forService("Config")
    private let fileManager = FileManager.default

    // Config directory
    private let dataDirectory: URL

    // File paths
    private let configURL: URL
    private let stateURL: URL

    // In-memory data
    private var config: ServiceConfig = ServiceConfig()
    private var state: ServiceRuntimeState = ServiceRuntimeState()

    // Save debounce
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

    // MARK: - Initialization

    private func initialize() async {
        // Ensure directory exists
        do {
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create config directory: \(error)")
        }

        // Load config
        await loadConfig()
        await loadState()

        // Update service start time
        state.serviceStartTime = Date()
        state.lastActiveTime = Date()
        await saveState()

        logger.info("ServiceConfigManager initialized")
    }

    // MARK: - Config Operations

    private func loadConfig() async {
        guard let data = try? Data(contentsOf: configURL) else {
            logger.info("Config file not found, using defaults")
            await saveConfig()
            return
        }

        do {
            config = try JSONDecoder().decode(ServiceConfig.self, from: data)
            logger.info("Service config loaded")
        } catch {
            logger.error("Failed to parse config: \(error)")
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
            logger.debug("Service config saved")
        } catch {
            logger.error("Failed to save config: \(error)")
        }
    }

    // MARK: - State Operations

    private func loadState() async {
        guard let data = try? Data(contentsOf: stateURL) else {
            return
        }

        do {
            state = try JSONDecoder().decode(ServiceRuntimeState.self, from: data)
            logger.info("Runtime state loaded")
        } catch {
            logger.error("Failed to parse state: \(error)")
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
        // Don't save progress updates immediately to avoid frequent I/O
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

        // Get disk space
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

    // MARK: - Save State

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
            logger.error("Failed to save state: \(error)")
        }
    }

    func forceSaveState() async {
        saveTask?.cancel()
        await saveState()
    }

    // MARK: - Cleanup

    func clearState() async {
        state = ServiceRuntimeState()
        state.serviceStartTime = Date()
        await saveState()
    }

    // MARK: - Health Check

    func healthCheck() -> Bool {
        return fileManager.fileExists(atPath: dataDirectory.path)
    }

    // MARK: - Config Conflict Detection
    // Reference: SERVICE_FLOW/02_config_management.md

    /// Detect config conflicts
    /// Returns a list of conflicts; empty means no conflicts
    func detectConflicts(appConfig: AppConfig) -> [ConfigConflict] {
        var conflicts: [ConfigConflict] = []

        // 1. Detect multiple syncPairs using the same EXTERNAL_DIR
        conflicts.append(contentsOf: detectMultipleExternalDirs(appConfig.syncPairs, disks: appConfig.disks))

        // 2. Detect overlapping LOCAL_DIRs
        conflicts.append(contentsOf: detectOverlappingLocal(appConfig.syncPairs))

        // 3. Detect referenced disk not found
        conflicts.append(contentsOf: detectDiskNotFound(appConfig.syncPairs, disks: appConfig.disks))

        // 4. Detect circular sync
        conflicts.append(contentsOf: detectCircularSync(appConfig.syncPairs, disks: appConfig.disks))

        if !conflicts.isEmpty {
            logger.warning("Detected \(conflicts.count) config conflicts")
            for conflict in conflicts {
                logger.warning("  - [\(conflict.type.rawValue)] \(conflict.affectedItems.joined(separator: ", "))")
            }
        }

        return conflicts
    }

    /// Detect multiple syncPairs using the same EXTERNAL_DIR
    private func detectMultipleExternalDirs(_ syncPairs: [SyncPairConfig], disks: [DiskConfig]) -> [ConfigConflict] {
        var conflicts: [ConfigConflict] = []
        var externalDirMap: [String: [String]] = [:]  // [fullExternalDir: [syncPairIds]]

        for pair in syncPairs where pair.enabled {
            guard let disk = disks.first(where: { $0.id == pair.diskId }) else { continue }
            let fullExternalDir = pair.fullExternalDir(diskMountPath: disk.mountPath)
            externalDirMap[fullExternalDir, default: []].append(pair.id)
        }

        for (externalDir, pairIds) in externalDirMap where pairIds.count > 1 {
            conflicts.append(ConfigConflict(
                type: .multipleExternalDirs,
                affectedItems: pairIds,
                requiresUserAction: true
            ))
            logger.warning("Conflict: multiple SyncPairs use the same EXTERNAL_DIR: \(externalDir)")
        }

        return conflicts
    }

    /// Detect overlapping LOCAL_DIRs
    private func detectOverlappingLocal(_ syncPairs: [SyncPairConfig]) -> [ConfigConflict] {
        var conflicts: [ConfigConflict] = []
        let enabledPairs = syncPairs.filter { $0.enabled }

        for i in 0..<enabledPairs.count {
            for j in (i + 1)..<enabledPairs.count {
                let pair1 = enabledPairs[i]
                let pair2 = enabledPairs[j]

                let local1 = pair1.localDir
                let local2 = pair2.localDir

                // Check for overlap (one is a subpath of the other)
                if local1.hasPrefix(local2 + "/") || local2.hasPrefix(local1 + "/") || local1 == local2 {
                    conflicts.append(ConfigConflict(
                        type: .overlappingLocal,
                        affectedItems: [pair1.id, pair2.id],
                        requiresUserAction: true
                    ))
                    logger.warning("Conflict: LOCAL_DIR overlap: \(local1) and \(local2)")
                }
            }
        }

        return conflicts
    }

    /// Detect referenced disk not found
    private func detectDiskNotFound(_ syncPairs: [SyncPairConfig], disks: [DiskConfig]) -> [ConfigConflict] {
        var conflicts: [ConfigConflict] = []
        let diskIds = Set(disks.map { $0.id })

        for pair in syncPairs where pair.enabled {
            if !diskIds.contains(pair.diskId) {
                conflicts.append(ConfigConflict(
                    type: .diskNotFound,
                    affectedItems: [pair.id, pair.diskId],
                    requiresUserAction: true
                ))
                logger.warning("Conflict: SyncPair '\(pair.id)' references non-existent Disk '\(pair.diskId)'")
            }
        }

        return conflicts
    }

    /// Detect circular sync
    private func detectCircularSync(_ syncPairs: [SyncPairConfig], disks: [DiskConfig]) -> [ConfigConflict] {
        var conflicts: [ConfigConflict] = []
        let enabledPairs = syncPairs.filter { $0.enabled }

        for i in 0..<enabledPairs.count {
            for j in (i + 1)..<enabledPairs.count {
                let pair1 = enabledPairs[i]
                let pair2 = enabledPairs[j]

                guard let disk1 = disks.first(where: { $0.id == pair1.diskId }),
                      let disk2 = disks.first(where: { $0.id == pair2.diskId }) else { continue }

                let external1 = pair1.fullExternalDir(diskMountPath: disk1.mountPath)
                let external2 = pair2.fullExternalDir(diskMountPath: disk2.mountPath)
                let local1 = pair1.localDir
                let local2 = pair2.localDir

                // Check circular: pair1's EXTERNAL_DIR is under pair2's LOCAL_DIR, or vice versa
                if external1.hasPrefix(local2 + "/") || external2.hasPrefix(local1 + "/") {
                    conflicts.append(ConfigConflict(
                        type: .circularSync,
                        affectedItems: [pair1.id, pair2.id],
                        requiresUserAction: true
                    ))
                    logger.warning("Conflict: circular sync detected: \(pair1.id) and \(pair2.id)")
                }

                // Check circular: pair1's LOCAL_DIR is under pair2's EXTERNAL_DIR, or vice versa
                if local1.hasPrefix(external2 + "/") || local2.hasPrefix(external1 + "/") {
                    conflicts.append(ConfigConflict(
                        type: .circularSync,
                        affectedItems: [pair1.id, pair2.id],
                        requiresUserAction: true
                    ))
                    logger.warning("Conflict: circular sync detected: \(pair1.id) and \(pair2.id)")
                }
            }
        }

        return conflicts
    }

    /// Validate config and return conflict status
    func validateConfig(appConfig: AppConfig) async -> ConfigStatus {
        let conflicts = detectConflicts(appConfig: appConfig)

        var status = ConfigStatus(
            isValid: conflicts.isEmpty,
            isPatched: false,
            patchedFields: nil,
            conflicts: conflicts.isEmpty ? nil : conflicts,
            loadedAt: Date(),
            configPath: nil
        )

        // Set config status
        await ServiceStateManager.shared.setConfigStatus(status)

        return status
    }
}
