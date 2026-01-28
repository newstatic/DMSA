import Foundation
import UserNotifications

/// 通知类型枚举
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

/// 通知处理器
/// 负责处理所有 Service 通知，解析数据，分发到 StateManager，触发系统通知
@MainActor
final class NotificationHandler {

    // MARK: - Singleton

    static let shared = NotificationHandler()

    // MARK: - 依赖

    private let stateManager = StateManager.shared
    private let userNotificationCenter = UNUserNotificationCenter.current()
    private let logger = Logger.shared

    // MARK: - 节流配置

    private var lastProgressNotification: Date = .distantPast
    private let progressThrottleInterval: TimeInterval = 0.1 // 100ms 节流

    // MARK: - 初始化

    private init() {
        setupDistributedNotificationObservers()
        requestNotificationPermission()
    }

    // MARK: - 通知权限

    private func requestNotificationPermission() {
        userNotificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                Logger.shared.error("通知权限请求失败: \(error)")
            } else if granted {
                Logger.shared.debug("通知权限已授予")
            }
        }
    }

    // MARK: - 分布式通知监听

    private func setupDistributedNotificationObservers() {
        let dnc = DistributedNotificationCenter.default()

        // 监听服务就绪通知
        dnc.addObserver(
            self,
            selector: #selector(handleServiceReadyNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.serviceReady),
            object: nil
        )

        // 监听同步进度通知
        dnc.addObserver(
            self,
            selector: #selector(handleSyncProgressNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.syncProgress),
            object: nil
        )

        // 监听同步状态变更通知
        dnc.addObserver(
            self,
            selector: #selector(handleSyncStatusChangedNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.syncStatusChanged),
            object: nil
        )

        // 监听配置更新通知
        dnc.addObserver(
            self,
            selector: #selector(handleConfigUpdatedNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.configUpdated),
            object: nil
        )

        // 监听冲突检测通知
        dnc.addObserver(
            self,
            selector: #selector(handleConflictDetectedNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.conflictDetected),
            object: nil
        )

        // 监听组件错误通知
        dnc.addObserver(
            self,
            selector: #selector(handleComponentErrorNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.componentError),
            object: nil
        )

        // 监听索引进度通知
        dnc.addObserver(
            self,
            selector: #selector(handleIndexProgressNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.indexProgress),
            object: nil
        )

        // 监听淘汰进度通知
        dnc.addObserver(
            self,
            selector: #selector(handleEvictionProgressNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.evictionProgress),
            object: nil
        )

        logger.info("NotificationHandler: 分布式通知监听已设置")
    }

    // MARK: - 通知处理入口

    /// 处理通知 (统一入口)
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

    // MARK: - 分布式通知处理 (Objective-C 回调)

    @objc private func handleServiceReadyNotification(_ notification: Notification) {
        logger.info("收到服务就绪通知")
        Task { @MainActor in
            handleServiceReady(Data())
        }
    }

    @objc private func handleSyncProgressNotification(_ notification: Notification) {
        guard let jsonString = notification.object as? String,
              let data = jsonString.data(using: .utf8) else {
            return
        }

        // 节流: 100ms 内只处理一次
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
        logger.info("收到配置更新通知")
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

    // MARK: - 具体通知处理逻辑

    private func handleStateChanged(_ data: Data) {
        logger.debug("处理状态变更通知")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // 从 Int 值解析 ServiceState
        if let serviceStateRaw = info["serviceState"] as? Int,
           let state = ServiceState(rawValue: serviceStateRaw) {
            stateManager.serviceState = state
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
        logger.debug("处理索引进度通知")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let progress = IndexProgress(
            syncPairId: info["syncPairId"] as? String ?? "",
            phase: info["phase"] as? String ?? "indexing",
            progress: info["progress"] as? Double ?? 0,
            totalFiles: info["totalFiles"] as? Int ?? 0,
            processedFiles: info["processedFiles"] as? Int ?? 0,
            currentPath: info["currentPath"] as? String
        )

        stateManager.updateIndexProgress(progress)
    }

    private func handleIndexReady(_ data: Data) {
        logger.info("处理索引就绪通知")

        stateManager.indexProgress = nil
        stateManager.updateUIState(.ready)
    }

    private func handleSyncProgress(_ data: Data) {
        guard let progressData = try? JSONDecoder().decode(SyncProgressData.self, from: data) else {
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
        logger.debug("处理同步状态变更通知")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let syncPairId = info["syncPairId"] as? String,
              let statusRaw = info["status"] as? Int,
              let status = SyncStatus(rawValue: statusRaw) else {
            return
        }

        let message = info["message"] as? String

        switch status {
        case .pending, .completed, .cancelled:
            stateManager.updateUIState(.ready)
            stateManager.syncProgress = nil

            // 同步完成时发送系统通知
            if status == .completed {
                sendUserNotification(
                    title: "sync.completed".localized,
                    body: message ?? "sync.completed.message".localized,
                    identifier: "sync-completed-\(syncPairId)"
                )
            }

        case .inProgress:
            // 保持当前进度状态
            break

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

            // 同步错误时发送系统通知
            sendUserNotification(
                title: "sync.error".localized,
                body: message ?? "sync.error.message".localized,
                identifier: "sync-error-\(syncPairId)"
            )
        }
    }

    private func handleSyncCompleted(_ data: Data) {
        logger.info("处理同步完成通知")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let syncPairId = info["syncPairId"] as? String ?? "unknown"
        let filesCount = info["filesCount"] as? Int ?? 0

        stateManager.updateUIState(.ready)
        stateManager.syncProgress = nil
        stateManager.statistics.lastSyncTime = Date()
        stateManager.statistics.totalFilesSynced += filesCount

        // 发送系统通知
        sendUserNotification(
            title: "sync.completed".localized,
            body: String(format: "sync.completed.files".localized, filesCount),
            identifier: "sync-completed-\(syncPairId)"
        )
    }

    private func handleConflictDetected(_ data: Data) {
        logger.warning("处理冲突检测通知")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let count = info["count"] as? Int ?? 1
        stateManager.pendingConflicts += count

        // 发送系统通知
        sendUserNotification(
            title: "conflict.detected".localized,
            body: String(format: "conflict.detected.message".localized, count),
            identifier: "conflict-detected-\(Date().timeIntervalSince1970)"
        )
    }

    private func handleEvictionProgress(_ data: Data) {
        logger.debug("处理淘汰进度通知")

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
        logger.error("处理组件错误通知")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let component = info["component"] as? String ?? "unknown"
        let errorMessage = info["message"] as? String ?? "未知错误"
        let errorCode = info["code"] as? Int ?? ErrorCodes.componentError
        let isCritical = info["critical"] as? Bool ?? false

        let error = AppError(
            code: errorCode,
            message: "[\(component)] \(errorMessage)",
            severity: isCritical ? .critical : .warning,
            isRecoverable: !isCritical
        )

        stateManager.updateError(error)

        // 严重错误发送系统通知
        if isCritical {
            sendUserNotification(
                title: "error.critical".localized,
                body: errorMessage,
                identifier: "error-\(component)-\(Date().timeIntervalSince1970)"
            )
        }
    }

    private func handleDiskChanged(_ data: Data) {
        logger.info("处理磁盘变更通知")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let diskName = info["diskName"] as? String ?? ""
        let isConnected = info["connected"] as? Bool ?? false

        // 刷新磁盘状态
        Task {
            await stateManager.syncFullState()
        }

        // 发送系统通知
        let title = isConnected ? "disk.connected".localized : "disk.disconnected".localized
        sendUserNotification(
            title: title,
            body: diskName,
            identifier: "disk-\(diskName)-\(isConnected)"
        )
    }

    private func handleServiceReady(_ data: Data) {
        logger.info("处理服务就绪通知")

        stateManager.updateConnectionState(.connected)
        stateManager.updateUIState(.ready)

        // 刷新完整状态
        Task {
            await stateManager.syncFullState()
        }
    }

    private func handleConfigUpdated(_ data: Data) {
        logger.info("处理配置更新通知")

        // 重新加载配置
        Task {
            await stateManager.syncFullState()
        }
    }

    // MARK: - 系统通知

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
                Logger.shared.error("发送系统通知失败: \(error)")
            }
        }
    }
}

// MARK: - Constants 通知名扩展

extension Constants.Notifications {
    static let conflictDetected = "com.ttttt.dmsa.conflictDetected"
    static let componentError = "com.ttttt.dmsa.componentError"
    static let indexProgress = "com.ttttt.dmsa.indexProgress"
    static let evictionProgress = "com.ttttt.dmsa.evictionProgress"
}
