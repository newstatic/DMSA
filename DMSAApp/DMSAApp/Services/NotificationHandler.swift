import Foundation
import UserNotifications

/// Notification type enum
enum NotificationType: String, CaseIterable {
    case stateChanged = "stateChanged"
    case indexProgress = "indexProgress"
    case indexReady = "indexReady"
    case syncProgress = "syncProgress"
    case syncCompleted = "syncCompleted"
    case conflictDetected = "conflictDetected"
    case evictionProgress = "evictionProgress"
    case componentError = "componentError"
    case diskChanged = "diskChanged"
    case serviceReady = "serviceReady"
    case configUpdated = "configUpdated"
}

/// Notification handler
/// Handles all Service notifications, parses data, dispatches to StateManager, triggers system notifications
@MainActor
final class NotificationHandler {

    // MARK: - Singleton

    static let shared = NotificationHandler()

    // MARK: - Dependencies

    private let stateManager = StateManager.shared
    private let userNotificationCenter = UNUserNotificationCenter.current()
    private let logger = Logger.shared

    // MARK: - Throttle Config

    private var lastProgressNotification: Date = .distantPast
    private let progressThrottleInterval: TimeInterval = 0.1 // 100ms throttle

    // MARK: - Initialization

    private init() {
        setupDistributedNotificationObservers()
        requestNotificationPermission()
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        userNotificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                Logger.shared.error("Notification permission request failed: \(error)")
            } else if granted {
                Logger.shared.debug("Notification permission granted")
            }
        }
    }

    // MARK: - Distributed Notification Listeners

    private func setupDistributedNotificationObservers() {
        let dnc = DistributedNotificationCenter.default()

        logger.info("Setting up distributed notification listeners...")

        // Set suspension behavior: receive notifications even when App is in background
        // .deliverImmediately: deliver immediately even if App is suspended
        // .coalesce: coalesce multiple identical notifications
        // .drop: drop notifications while App is suspended
        // Default is .coalesce, but for state changes we need immediate delivery

        // Listen for service ready notification
        dnc.addObserver(
            self,
            selector: #selector(handleServiceReadyNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.serviceReady),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // Listen for sync progress notification
        dnc.addObserver(
            self,
            selector: #selector(handleSyncProgressNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.syncProgress),
            object: nil,
            suspensionBehavior: .coalesce  // progress notifications can be coalesced
        )

        // Listen for sync status change notification
        dnc.addObserver(
            self,
            selector: #selector(handleSyncStatusChangedNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.syncStatusChanged),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // Listen for config update notification
        dnc.addObserver(
            self,
            selector: #selector(handleConfigUpdatedNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.configUpdated),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // Listen for conflict detection notification
        dnc.addObserver(
            self,
            selector: #selector(handleConflictDetectedNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.conflictDetected),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // Listen for component error notification
        dnc.addObserver(
            self,
            selector: #selector(handleComponentErrorNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.componentError),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // Listen for index progress notification
        dnc.addObserver(
            self,
            selector: #selector(handleIndexProgressNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.indexProgress),
            object: nil,
            suspensionBehavior: .coalesce  // progress notifications can be coalesced
        )

        // Listen for eviction progress notification
        dnc.addObserver(
            self,
            selector: #selector(handleEvictionProgressNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.evictionProgress),
            object: nil,
            suspensionBehavior: .coalesce  // progress notifications can be coalesced
        )

        // Listen for service state change notification (most important)
        dnc.addObserver(
            self,
            selector: #selector(handleStateChangedNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.stateChanged),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // Listen for index ready notification
        dnc.addObserver(
            self,
            selector: #selector(handleIndexReadyNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.indexReady),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        logger.info("NotificationHandler: Distributed notification listeners configured (10 total)")
    }

    // MARK: - Notification Processing Entry

    /// Process notification (unified entry)
    func handleNotification(_ type: NotificationType, data: Data) {
        switch type {
        case .stateChanged:
            handleStateChanged(data)
        case .indexProgress:
            handleIndexProgress(data)
        case .indexReady:
            handleIndexReady(data)
        case .syncProgress:
            handleSyncProgress(data)
        case .syncCompleted:
            handleSyncCompleted(data)
        case .conflictDetected:
            handleConflictDetected(data)
        case .evictionProgress:
            handleEvictionProgress(data)
        case .componentError:
            handleComponentError(data)
        case .diskChanged:
            handleDiskChanged(data)
        case .serviceReady:
            handleServiceReady(data)
        case .configUpdated:
            handleConfigUpdated(data)
        }
    }

    // MARK: - Distributed Notification Handlers (Objective-C callbacks)

    @objc private func handleServiceReadyNotification(_ notification: Notification) {
        logger.info("[Notification] <<< Received serviceReady")
        logger.debug("[Notification] serviceReady object: \(String(describing: notification.object))")
        Task { @MainActor in
            handleServiceReady(Data())
        }
    }

    @objc private func handleSyncProgressNotification(_ notification: Notification) {
        guard let jsonString = notification.object as? String,
              let data = jsonString.data(using: .utf8) else {
            return
        }

        // Throttle: process once per 100ms
        let now = Date()
        guard now.timeIntervalSince(lastProgressNotification) >= progressThrottleInterval else {
            return
        }
        lastProgressNotification = now

        Task { @MainActor in
            handleSyncProgress(data)
        }
    }

    @objc private func handleSyncStatusChangedNotification(_ notification: Notification) {
        guard let jsonString = notification.object as? String,
              let data = jsonString.data(using: .utf8) else {
            return
        }

        Task { @MainActor in
            handleSyncStatusChanged(data)
        }
    }

    @objc private func handleConfigUpdatedNotification(_ notification: Notification) {
        logger.info("Received config update notification")
        Task { @MainActor in
            handleConfigUpdated(Data())
        }
    }

    @objc private func handleConflictDetectedNotification(_ notification: Notification) {
        guard let jsonString = notification.object as? String,
              let data = jsonString.data(using: .utf8) else {
            return
        }

        Task { @MainActor in
            handleConflictDetected(data)
        }
    }

    @objc private func handleComponentErrorNotification(_ notification: Notification) {
        guard let jsonString = notification.object as? String,
              let data = jsonString.data(using: .utf8) else {
            return
        }

        Task { @MainActor in
            handleComponentError(data)
        }
    }

    @objc private func handleIndexProgressNotification(_ notification: Notification) {
        guard let jsonString = notification.object as? String,
              let data = jsonString.data(using: .utf8) else {
            return
        }

        Task { @MainActor in
            handleIndexProgress(data)
        }
    }

    @objc private func handleEvictionProgressNotification(_ notification: Notification) {
        guard let jsonString = notification.object as? String,
              let data = jsonString.data(using: .utf8) else {
            return
        }

        Task { @MainActor in
            handleEvictionProgress(data)
        }
    }

    @objc private func handleIndexReadyNotification(_ notification: Notification) {
        logger.info("[Notification] <<< Received indexReady")

        // indexReady notification may or may not have data
        var data = Data()
        if let jsonString = notification.object as? String,
           let jsonData = jsonString.data(using: .utf8) {
            data = jsonData
            logger.debug("[Notification] indexReady data: \(jsonString.prefix(200))")
        }

        Task { @MainActor in
            handleIndexReady(data)
        }
    }

    @objc private func handleStateChangedNotification(_ notification: Notification) {
        logger.info("[Notification] <<< Received stateChanged")

        guard let jsonString = notification.object as? String else {
            logger.warning("[Notification] stateChanged object is not String: \(String(describing: notification.object))")
            return
        }

        logger.debug("[Notification] stateChanged data: \(jsonString.prefix(200))")

        guard let data = jsonString.data(using: .utf8) else {
            logger.warning("[Notification] stateChanged JSON to Data conversion failed")
            return
        }

        logger.info("[Notification] Processing stateChanged")
        Task { @MainActor in
            handleStateChanged(data)
        }
    }

    // MARK: - Specific Notification Processing

    private func handleStateChanged(_ data: Data) {
        logger.debug("Processing state change notification")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("State change notification data parse failed")
            return
        }

        // Parse ServiceState from Int (Service sends field named "newState")
        if let serviceStateRaw = info["newState"] as? Int,
           let state = ServiceState(rawValue: serviceStateRaw) {
            let oldStateName = info["oldStateName"] as? String ?? "unknown"
            let newStateName = info["newStateName"] as? String ?? state.name
            logger.info("Service state changed: \(oldStateName) -> \(newStateName)")
            stateManager.serviceState = state

            // Update UI state based on ServiceState
            stateManager.updateSyncStatusFromServiceState(state)
            logger.info("UI syncStatus updated to: \(stateManager.syncStatus.text)")
        } else {
            logger.warning("State change notification missing newState field or invalid value: \(info)")
        }

        if let componentsData = info["components"] as? [[String: Any]] {
            var componentStates: [String: ComponentState] = [:]
            for compData in componentsData {
                if let name = compData["name"] as? String,
                   let stateRaw = compData["state"] as? Int,
                   let state = ComponentState(rawValue: stateRaw) {
                    componentStates[name] = state
                }
            }
            stateManager.componentStates = componentStates
        }
    }

    private func handleIndexProgress(_ data: Data) {
        logger.debug("Processing index progress notification")

        // Try direct decode to IndexProgress
        if let progress = try? JSONDecoder().decode(IndexProgress.self, from: data) {
            stateManager.updateIndexProgress(progress)
            return
        }

        // Compatible with old JSON format
        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        var progress = IndexProgress(syncPairId: info["syncPairId"] as? String ?? "")
        if let phaseStr = info["phase"] as? String,
           let phase = IndexPhase(rawValue: phaseStr) {
            progress.phase = phase
        }
        progress.progress = info["progress"] as? Double ?? 0
        progress.scannedFiles = info["processedFiles"] as? Int ?? info["scannedFiles"] as? Int ?? 0
        progress.totalFiles = info["totalFiles"] as? Int
        progress.currentPath = info["currentPath"] as? String

        stateManager.updateIndexProgress(progress)
    }

    private func handleIndexReady(_ data: Data) {
        logger.info("Processing index ready notification")

        stateManager.indexProgress = nil
        stateManager.updateUIState(.ready)
    }

    private func handleSyncProgress(_ data: Data) {
        // Try direct decode to SyncProgress (shared model)
        if let progress = try? JSONDecoder().decode(SyncProgress.self, from: data) {
            let progressInfo = SyncProgressInfo(
                syncPairId: progress.syncPairId,
                progress: progress.fileProgress,
                phase: progress.phase.rawValue,
                currentFile: progress.currentFile,
                processedFiles: progress.processedFiles,
                totalFiles: progress.totalFiles,
                processedBytes: progress.processedBytes,
                totalBytes: progress.totalBytes,
                speed: progress.speed
            )
            stateManager.updateSyncProgress(progressInfo)
            return
        }

        // Fallback: try decode to SyncProgressData
        guard let progressData = try? JSONDecoder().decode(SyncProgressData.self, from: data) else {
            logger.warning("Failed to decode sync progress data")
            return
        }

        let progress = SyncProgressInfo(
            syncPairId: progressData.syncPairId,
            progress: Double(progressData.processedFiles) / Double(max(1, progressData.totalFiles)),
            phase: progressData.phase.rawValue,
            currentFile: progressData.currentFile,
            processedFiles: progressData.processedFiles,
            totalFiles: progressData.totalFiles,
            processedBytes: progressData.processedBytes,
            totalBytes: progressData.totalBytes,
            speed: progressData.speed
        )

        stateManager.updateSyncProgress(progress)
    }

    private func handleSyncStatusChanged(_ data: Data) {
        logger.debug("Processing sync status change notification")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("Failed to parse sync status change notification JSON")
            return
        }

        guard let syncPairId = info["syncPairId"] as? String else {
            logger.warning("Sync status change notification missing syncPairId")
            return
        }

        guard let statusRaw = info["status"] as? Int,
              let status = SyncStatus(rawValue: statusRaw) else {
            logger.warning("Sync status change notification invalid status: \(String(describing: info["status"]))")
            return
        }

        logger.info("Sync status changed: syncPairId=\(syncPairId), status=\(status.displayName)")

        let message = info["message"] as? String

        switch status {
        case .pending, .completed, .cancelled:
            stateManager.updateUIState(.ready)
            stateManager.syncProgress = nil

            // Send system notification on sync completion
            if status == .completed {
                sendUserNotification(
                    title: "sync.completed".localized,
                    body: message ?? "sync.completed.message".localized,
                    identifier: "sync-completed-\(syncPairId)"
                )
            }

        case .inProgress:
            // Update to syncing state
            stateManager.syncStatus = .syncing
            // Post notification to update menu bar
            NotificationCenter.default.post(name: .syncStatusDidChange, object: nil)
            logger.info("Sync status changed to: syncing")

        case .paused:
            stateManager.syncStatus = .paused

        case .failed:
            let error = AppError(
                code: ErrorCodes.syncFailed,
                message: message ?? "sync.error.unknown".localized,
                severity: .warning,
                isRecoverable: true
            )
            stateManager.updateError(error)

            // Send system notification on sync error
            sendUserNotification(
                title: "sync.error".localized,
                body: message ?? "sync.error.message".localized,
                identifier: "sync-error-\(syncPairId)"
            )
        }
    }

    private func handleSyncCompleted(_ data: Data) {
        logger.info("Processing sync completion notification")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let syncPairId = info["syncPairId"] as? String ?? "unknown"
        let filesCount = info["filesCount"] as? Int ?? 0

        stateManager.updateUIState(.ready)
        stateManager.syncProgress = nil
        stateManager.statistics.lastSyncTime = Date()
        stateManager.statistics.totalFilesSynced += filesCount

        // Send system notification
        sendUserNotification(
            title: "sync.completed".localized,
            body: String(format: "sync.completed.files".localized, filesCount),
            identifier: "sync-completed-\(syncPairId)"
        )
    }

    private func handleConflictDetected(_ data: Data) {
        logger.warning("Processing conflict detection notification")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let count = info["count"] as? Int ?? 1
        stateManager.pendingConflicts += count

        // Send system notification
        sendUserNotification(
            title: "conflict.detected".localized,
            body: String(format: "conflict.detected.message".localized, count),
            identifier: "conflict-detected-\(Date().timeIntervalSince1970)"
        )
    }

    private func handleEvictionProgress(_ data: Data) {
        logger.debug("Processing eviction progress notification")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let progress = EvictionProgress(
            progress: info["progress"] as? Double ?? 0,
            freedBytes: info["freedBytes"] as? Int64 ?? 0,
            targetBytes: info["targetBytes"] as? Int64 ?? 0,
            evictedFiles: info["evictedFiles"] as? Int ?? 0,
            currentFile: info["currentFile"] as? String
        )

        stateManager.updateEvictionProgress(progress)
    }

    private func handleComponentError(_ data: Data) {
        logger.error("Processing component error notification")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let component = info["component"] as? String ?? "unknown"
        let errorMessage = info["message"] as? String ?? "Unknown error"
        let errorCode = info["code"] as? Int ?? ErrorCodes.componentError
        let isCritical = info["critical"] as? Bool ?? false

        let error = AppError(
            code: errorCode,
            message: "[\(component)] \(errorMessage)",
            severity: isCritical ? .critical : .warning,
            isRecoverable: !isCritical
        )

        stateManager.updateError(error)

        // Send system notification for critical errors
        if isCritical {
            sendUserNotification(
                title: "error.critical".localized,
                body: errorMessage,
                identifier: "error-\(component)-\(Date().timeIntervalSince1970)"
            )
        }
    }

    private func handleDiskChanged(_ data: Data) {
        logger.info("Processing disk change notification")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let diskName = info["diskName"] as? String ?? ""
        let isConnected = info["connected"] as? Bool ?? false

        // Refresh disk state
        Task {
            await stateManager.syncFullState()
        }

        // Send system notification
        let title = isConnected ? "disk.connected".localized : "disk.disconnected".localized
        sendUserNotification(
            title: title,
            body: diskName,
            identifier: "disk-\(diskName)-\(isConnected)"
        )
    }

    private func handleServiceReady(_ data: Data) {
        logger.info("Processing service ready notification")

        stateManager.updateConnectionState(.connected)
        stateManager.updateUIState(.ready)

        // Refresh full state
        Task {
            await stateManager.syncFullState()
        }
    }

    private func handleConfigUpdated(_ data: Data) {
        logger.info("Processing config update notification")

        // Reload config
        Task {
            await stateManager.syncFullState()
        }
    }

    // MARK: - System Notifications

    private func sendUserNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        userNotificationCenter.add(request) { error in
            if let error = error {
                Logger.shared.error("Failed to send system notification: \(error)")
            }
        }
    }
}

// MARK: - Constants Notification Name Extensions

extension Constants.Notifications {
    static let conflictDetected = "com.ttttt.dmsa.conflictDetected"
    static let componentError = "com.ttttt.dmsa.componentError"
    static let indexProgress = "com.ttttt.dmsa.indexProgress"
    static let evictionProgress = "com.ttttt.dmsa.evictionProgress"
}
