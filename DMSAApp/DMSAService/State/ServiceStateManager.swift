import Foundation

// MARK: - XPC Notification Sender

/// XPC notification sender
/// Sends notifications to all connected clients via ServiceDelegate
enum XPCNotifier {
    private static let logger = Logger.forService("XPCNotifier")

    /// Send state change notification
    static func notifyStateChanged(oldState: ServiceState, newState: ServiceState, data: Data?) {
        logger.info("[XPC] State changed: \(oldState.name) -> \(newState.name)")
        ServiceDelegate.shared?.notifyStateChanged(
            oldState: oldState.rawValue,
            newState: newState.rawValue,
            data: data
        )
    }

    /// Send index progress
    static func notifyIndexProgress(data: Data) {
        ServiceDelegate.shared?.notifyIndexProgress(data: data)
    }

    /// Send index ready
    static func notifyIndexReady(syncPairId: String) {
        logger.info("[XPC] Index ready: \(syncPairId)")
        ServiceDelegate.shared?.notifyIndexReady(syncPairId: syncPairId)
    }

    /// Send sync progress
    static func notifySyncProgress(data: Data) {
        ServiceDelegate.shared?.notifySyncProgress(data: data)
    }

    /// Send sync status change
    static func notifySyncStatusChanged(syncPairId: String, status: SyncStatus, message: String?) {
        logger.info("[XPC] Sync status changed: \(syncPairId) -> \(status.displayName)")
        ServiceDelegate.shared?.notifySyncStatusChanged(
            syncPairId: syncPairId,
            status: status.rawValue,
            message: message
        )
    }

    /// Send sync completed
    static func notifySyncCompleted(syncPairId: String, filesCount: Int, bytesCount: Int64) {
        logger.info("[XPC] Sync completed: \(syncPairId), \(filesCount) files")
        ServiceDelegate.shared?.notifySyncCompleted(
            syncPairId: syncPairId,
            filesCount: filesCount,
            bytesCount: bytesCount
        )
    }

    /// Send eviction progress
    static func notifyEvictionProgress(data: Data) {
        ServiceDelegate.shared?.notifyEvictionProgress(data: data)
    }

    /// Send component error
    static func notifyComponentError(component: String, code: Int, message: String, isCritical: Bool) {
        logger.info("[XPC] Component error: \(component) - \(message)")
        ServiceDelegate.shared?.notifyComponentError(
            component: component,
            code: code,
            message: message,
            isCritical: isCritical
        )
    }

    /// Send config updated
    static func notifyConfigUpdated() {
        logger.info("[XPC] Config updated")
        ServiceDelegate.shared?.notifyConfigUpdated()
    }

    /// Send service ready
    static func notifyServiceReady() {
        logger.info("[XPC] Service ready")
        ServiceDelegate.shared?.notifyServiceReady()
    }

    /// Send conflict detected
    static func notifyConflictDetected(data: Data) {
        logger.info("[XPC] Conflict detected")
        ServiceDelegate.shared?.notifyConflictDetected(data: data)
    }

    /// Send disk change notification
    static func notifyDiskChanged(diskName: String, isConnected: Bool) {
        logger.info("[XPC] Disk changed: \(diskName) -> \(isConnected ? "connected" : "disconnected")")
        ServiceDelegate.shared?.notifyDiskChanged(diskName: diskName, isConnected: isConnected)
    }

    /// Send activities updated
    static func notifyActivitiesUpdated(data: Data) {
        ServiceDelegate.shared?.notifyActivitiesUpdated(data: data)
    }
}

// MARK: - Activity Record Manager

/// Manages the most recent 5 activity records, pushes updates to clients in real time
actor ActivityManager {
    static let shared = ActivityManager()

    private let logger = Logger.forService("ActivityManager")
    private var activities: [ActivityRecord] = []
    private let maxCount = 5
    private var isLoaded = false

    private init() {}

    /// Load activity records from database (lazy load on first access)
    private func loadFromDatabaseIfNeeded() async {
        guard !isLoaded else { return }
        isLoaded = true
        let dbActivities = await ServiceDatabaseManager.shared.getRecentActivities(limit: maxCount)
        if !dbActivities.isEmpty {
            activities = dbActivities
            logger.info("Loaded \(dbActivities.count) activity records from database")
        }
    }

    /// Add an activity record
    func addActivity(_ activity: ActivityRecord) async {
        await loadFromDatabaseIfNeeded()
        activities.insert(activity, at: 0)
        if activities.count > maxCount {
            activities = Array(activities.prefix(maxCount))
        }
        // Persist to database
        await ServiceDatabaseManager.shared.saveActivityRecord(activity)
        pushToClients()
    }

    /// Convenience: add sync-related activity
    func addSyncActivity(type: ActivityType, syncPairId: String, diskId: String? = nil, filesCount: Int? = nil, bytesCount: Int64? = nil, detail: String? = nil) async {
        let title: String
        switch type {
        case .syncStarted: title = "Sync started \(syncPairId)"
        case .syncCompleted: title = "Sync completed \(syncPairId)"
        case .syncFailed: title = "Sync failed \(syncPairId)"
        default: title = "\(syncPairId)"
        }
        let activity = ActivityRecord(type: type, title: title, detail: detail, syncPairId: syncPairId, diskId: diskId, filesCount: filesCount, bytesCount: bytesCount)
        await addActivity(activity)
    }

    /// Convenience: add eviction activity
    func addEvictionActivity(filesCount: Int, bytesCount: Int64, syncPairId: String? = nil, failed: Bool = false) async {
        let type: ActivityType = failed ? .evictionFailed : .evictionCompleted
        let sizeStr = ByteCountFormatter.string(fromByteCount: bytesCount, countStyle: .file)
        let title = failed ? "Eviction failed" : "Eviction completed"
        let detail = "\(filesCount) files, \(sizeStr)"
        let activity = ActivityRecord(type: type, title: title, detail: detail, syncPairId: syncPairId, filesCount: filesCount, bytesCount: bytesCount)
        await addActivity(activity)
    }

    /// Convenience: add disk activity
    func addDiskActivity(diskName: String, isConnected: Bool) async {
        let type: ActivityType = isConnected ? .diskConnected : .diskDisconnected
        let title = isConnected ? "Disk connected" : "Disk disconnected"
        let activity = ActivityRecord(type: type, title: title, detail: diskName, diskId: diskName)
        await addActivity(activity)
    }

    /// Get current activity list
    func getActivities() async -> [ActivityRecord] {
        await loadFromDatabaseIfNeeded()
        return activities
    }

    /// Push activities to all clients
    private func pushToClients() {
        guard let data = try? JSONEncoder().encode(activities) else { return }
        XPCNotifier.notifyActivitiesUpdated(data: data)
    }
}

// MARK: - Service State Manager

/// Service state manager
/// Reference: SERVICE_FLOW/05_state_manager.md
actor ServiceStateManager {

    // MARK: - Singleton

    static let shared = ServiceStateManager()

    // MARK: - Properties

    private let logger = Logger.forService("StateManager")

    /// Global service state
    private var globalState: ServiceState = .starting

    /// Component states
    private var componentStates: [String: ComponentStateInfo] = [:]

    /// Config status
    private var configStatus = ConfigStatus()

    /// Service start time
    private let startTime = Date()

    /// Last error
    private var lastError: ServiceErrorInfo?

    /// Service version
    private let version = "4.9"

    /// Protocol version
    private let protocolVersion = 1

    // MARK: - Initialization

    private init() {
        // Initialize core component states
        for component in ServiceComponent.allCases {
            componentStates[component.rawValue] = ComponentStateInfo(name: component.rawValue)
        }
    }

    // MARK: - Global State Management

    /// Set global state
    func setState(_ newState: ServiceState) async {
        let oldState = globalState
        guard oldState != newState else { return }

        globalState = newState

        // Update logger state cache (for standard format logging)
        LoggerStateCache.update(newState.name)

        logger.info("State changed: \(oldState.name) -> \(newState.name)")

        // Send state change notification
        await sendStateChangedNotification(oldState: oldState, newState: newState)

        // Special state handling
        switch newState {
        case .xpcReady:
            // XPC ready, can accept client connections
            await sendXPCReadyNotification()

        case .ready:
            // Service ready, send serviceReady notification
            await sendServiceReadyNotification()

        case .error:
            // Error state, send serviceError notification
            if let error = lastError {
                await sendServiceErrorNotification(error: error)
            }

        default:
            break
        }
    }

    /// Get current global state
    func getState() -> ServiceState {
        return globalState
    }

    /// Wait for a specific state
    func waitForState(_ target: ServiceState, timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while globalState != target && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        return globalState == target
    }

    // MARK: - Component State Management

    /// Set component state
    func setComponentState(_ component: ServiceComponent, state: ComponentState, error: ComponentError? = nil) async {
        var info = componentStates[component.rawValue] ?? ComponentStateInfo(name: component.rawValue)
        let oldState = info.state

        info.state = state
        info.lastUpdated = Date()
        info.error = error

        componentStates[component.rawValue] = info

        // Log
        if oldState != state {
            if let error = error {
                logger.error("[\(globalState.name.padding(toLength: 11, withPad: " ", startingAt: 0))] [\(component.logName)] [\(state.logName)] Error: \(error.message)")
            } else {
                logger.info("[\(globalState.name.padding(toLength: 11, withPad: " ", startingAt: 0))] [\(component.logName)] [\(state.logName)]")
            }
        }

        // Send notification on component error
        if state == .error, let error = error {
            await sendComponentErrorNotification(component: component, error: error)
        }
    }

    /// Get component state
    func getComponentState(_ component: ServiceComponent) -> ComponentStateInfo? {
        return componentStates[component.rawValue]
    }

    /// Update component metrics
    func updateComponentMetrics(_ component: ServiceComponent, metrics: ComponentMetrics) async {
        guard var info = componentStates[component.rawValue] else { return }
        info.metrics = metrics
        componentStates[component.rawValue] = info
    }

    // MARK: - Config Status Management

    /// Set config status
    func setConfigStatus(_ status: ConfigStatus) async {
        configStatus = status

        // Send config status notification
        await sendConfigStatusNotification(status: status)

        // If there are conflicts, send conflict notification
        if let conflicts = status.conflicts, !conflicts.isEmpty {
            await sendConfigConflictNotification(conflicts: conflicts)
        }
    }

    /// Get config status
    func getConfigStatus() -> ConfigStatus {
        return configStatus
    }

    // MARK: - Error Management

    /// Set last error
    func setLastError(_ error: ServiceErrorInfo) async {
        lastError = error
    }

    /// Clear last error
    func clearLastError() async {
        lastError = nil
    }

    // MARK: - Full State

    /// Get full service state
    func getFullState() -> ServiceFullState {
        return ServiceFullState(
            globalState: globalState,
            components: componentStates,
            config: configStatus,
            pendingNotifications: 0,  // Now using XPC callbacks, no more queue
            startTime: startTime,
            lastError: lastError,
            version: version,
            protocolVersion: protocolVersion
        )
    }

    // MARK: - Operation Permission Check

    /// Check if a given operation is allowed
    func canPerform(_ operation: ServiceOperation) -> Bool {
        switch operation {
        case .statusQuery:
            return globalState.allowsStatusQuery

        case .configRead:
            return globalState.allowsConfigAccess

        case .configWrite:
            return globalState.allowsConfigAccess && globalState != .error

        case .vfsMount, .vfsUnmount, .syncStart, .syncPause, .evictionTrigger, .fileOperation:
            return globalState.allowsOperations
        }
    }

    // MARK: - Notification Sending (via XPC callbacks)

    /// Send state change notification
    private func sendStateChangedNotification(oldState: ServiceState, newState: ServiceState) async {
        let data: [String: Any] = [
            "oldState": oldState.rawValue,
            "oldStateName": oldState.name,
            "newState": newState.rawValue,
            "newStateName": newState.name,
            "timestamp": Date().timeIntervalSince1970
        ]

        let jsonData = try? JSONSerialization.data(withJSONObject: data)
        XPCNotifier.notifyStateChanged(oldState: oldState, newState: newState, data: jsonData)
    }

    /// Send XPC ready notification (internal use, does not notify clients)
    private func sendXPCReadyNotification() async {
        // XPC ready is an internal state, no need to notify clients
        logger.info("XPC ready, can accept client connections")
    }

    /// Send service ready notification
    private func sendServiceReadyNotification() async {
        XPCNotifier.notifyServiceReady()
    }

    /// Send service error notification
    private func sendServiceErrorNotification(error: ServiceErrorInfo) async {
        XPCNotifier.notifyComponentError(
            component: "Service",
            code: error.code,
            message: error.message,
            isCritical: true
        )
    }

    /// Send component error notification
    private func sendComponentErrorNotification(component: ServiceComponent, error: ComponentError) async {
        XPCNotifier.notifyComponentError(
            component: component.rawValue,
            code: error.code,
            message: error.message,
            isCritical: !error.recoverable
        )
    }

    /// Send config status notification
    private func sendConfigStatusNotification(status: ConfigStatus) async {
        XPCNotifier.notifyConfigUpdated()
    }

    /// Send config conflict notification
    private func sendConfigConflictNotification(conflicts: [ConfigConflict]) async {
        let data: [String: Any] = [
            "conflicts": conflicts.map { conflict -> [String: Any] in
                return [
                    "type": conflict.type.rawValue,
                    "affectedItems": conflict.affectedItems,
                    "requiresUserAction": conflict.requiresUserAction
                ]
            },
            "requiresUserAction": conflicts.contains { $0.requiresUserAction }
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
            XPCNotifier.notifyConflictDetected(data: jsonData)
        }
    }

    /// Send VFS mount completed notification (via service ready notification)
    func sendVFSMountedNotification(syncPairIds: [String], mountPoints: [String]) async {
        // After VFS mount completes, READY state is set; no separate notification needed
        logger.info("VFS mount completed: \(syncPairIds.joined(separator: ", "))")
    }

    /// Send index progress notification
    func sendIndexProgressNotification(progress: IndexProgress) async {
        if let jsonData = try? JSONEncoder().encode(progress) {
            XPCNotifier.notifyIndexProgress(data: jsonData)
        }
    }

    /// Send index ready notification
    func sendIndexReadyNotification(syncPairId: String, totalFiles: Int, totalSize: Int64, duration: TimeInterval) async {
        logger.info("Index completed: \(syncPairId), \(totalFiles) files, \(totalSize) bytes, took \(duration)s")
        XPCNotifier.notifyIndexReady(syncPairId: syncPairId)
    }

    /// Send index ready notification (simplified)
    func sendIndexReadyNotification(syncPairId: String) async {
        XPCNotifier.notifyIndexReady(syncPairId: syncPairId)
    }
}
