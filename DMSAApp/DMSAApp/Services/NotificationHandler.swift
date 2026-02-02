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

        logger.info("设置分布式通知监听器...")

        // 设置挂起行为：即使 App 在后台也接收通知
        // .deliverImmediately: 立即投递，即使 App 被挂起
        // .coalesce: 合并多个相同通知
        // .drop: 丢弃 App 被挂起期间的通知
        // 默认是 .coalesce，但对于状态变更我们需要立即投递

        // 监听服务就绪通知
        dnc.addObserver(
            self,
            selector: #selector(handleServiceReadyNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.serviceReady),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // 监听同步进度通知
        dnc.addObserver(
            self,
            selector: #selector(handleSyncProgressNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.syncProgress),
            object: nil,
            suspensionBehavior: .coalesce  // 进度通知可以合并
        )

        // 监听同步状态变更通知
        dnc.addObserver(
            self,
            selector: #selector(handleSyncStatusChangedNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.syncStatusChanged),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // 监听配置更新通知
        dnc.addObserver(
            self,
            selector: #selector(handleConfigUpdatedNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.configUpdated),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // 监听冲突检测通知
        dnc.addObserver(
            self,
            selector: #selector(handleConflictDetectedNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.conflictDetected),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // 监听组件错误通知
        dnc.addObserver(
            self,
            selector: #selector(handleComponentErrorNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.componentError),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // 监听索引进度通知
        dnc.addObserver(
            self,
            selector: #selector(handleIndexProgressNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.indexProgress),
            object: nil,
            suspensionBehavior: .coalesce  // 进度通知可以合并
        )

        // 监听淘汰进度通知
        dnc.addObserver(
            self,
            selector: #selector(handleEvictionProgressNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.evictionProgress),
            object: nil,
            suspensionBehavior: .coalesce  // 进度通知可以合并
        )

        // 监听服务状态变更通知 (最重要的通知)
        dnc.addObserver(
            self,
            selector: #selector(handleStateChangedNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.stateChanged),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // 监听索引就绪通知
        dnc.addObserver(
            self,
            selector: #selector(handleIndexReadyNotification(_:)),
            name: NSNotification.Name(Constants.Notifications.indexReady),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        logger.info("NotificationHandler: 分布式通知监听已设置 (共 10 个通知)")
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
        logger.info("[通知] <<< 收到 serviceReady 通知")
        logger.debug("[通知] serviceReady object: \(String(describing: notification.object))")
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

    @objc private func handleIndexReadyNotification(_ notification: Notification) {
        logger.info("[通知] <<< 收到 indexReady 通知")

        // indexReady 通知可能有数据也可能没有
        var data = Data()
        if let jsonString = notification.object as? String,
           let jsonData = jsonString.data(using: .utf8) {
            data = jsonData
            logger.debug("[通知] indexReady 数据: \(jsonString.prefix(200))")
        }

        Task { @MainActor in
            handleIndexReady(data)
        }
    }

    @objc private func handleStateChangedNotification(_ notification: Notification) {
        logger.info("[通知] <<< 收到 stateChanged 通知")

        guard let jsonString = notification.object as? String else {
            logger.warning("[通知] stateChanged 通知的 object 不是 String: \(String(describing: notification.object))")
            return
        }

        logger.debug("[通知] stateChanged 数据: \(jsonString.prefix(200))")

        guard let data = jsonString.data(using: .utf8) else {
            logger.warning("[通知] stateChanged JSON 转 Data 失败")
            return
        }

        logger.info("[通知] 开始处理 stateChanged 通知")
        Task { @MainActor in
            handleStateChanged(data)
        }
    }

    // MARK: - 具体通知处理逻辑

    private func handleStateChanged(_ data: Data) {
        logger.debug("处理状态变更通知")

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("状态变更通知数据解析失败")
            return
        }

        // 从 Int 值解析 ServiceState (Service 发送的字段名是 "newState")
        if let serviceStateRaw = info["newState"] as? Int,
           let state = ServiceState(rawValue: serviceStateRaw) {
            let oldStateName = info["oldStateName"] as? String ?? "unknown"
            let newStateName = info["newStateName"] as? String ?? state.name
            logger.info("服务状态变更: \(oldStateName) -> \(newStateName)")
            stateManager.serviceState = state

            // 根据 ServiceState 更新 UI 状态
            stateManager.updateSyncStatusFromServiceState(state)
            logger.info("UI syncStatus 已更新为: \(stateManager.syncStatus.text)")
        } else {
            logger.warning("状态变更通知缺少 newState 字段或值无效: \(info)")
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

        // 尝试直接解码为 IndexProgress
        if let progress = try? JSONDecoder().decode(IndexProgress.self, from: data) {
            stateManager.updateIndexProgress(progress)
            return
        }

        // 兼容旧格式的 JSON
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
        logger.info("处理索引就绪通知")

        stateManager.indexProgress = nil
        stateManager.updateUIState(.ready)
    }

    private func handleSyncProgress(_ data: Data) {
        // 尝试直接解码为 SyncProgress (共享模型)
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

        // 回退：尝试解码为 SyncProgressData
        guard let progressData = try? JSONDecoder().decode(SyncProgressData.self, from: data) else {
            logger.warning("无法解码同步进度数据")
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

        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("无法解析同步状态变更通知 JSON")
            return
        }

        guard let syncPairId = info["syncPairId"] as? String else {
            logger.warning("同步状态变更通知缺少 syncPairId")
            return
        }

        guard let statusRaw = info["status"] as? Int,
              let status = SyncStatus(rawValue: statusRaw) else {
            logger.warning("同步状态变更通知状态无效: \(String(describing: info["status"]))")
            return
        }

        logger.info("同步状态变更: syncPairId=\(syncPairId), status=\(status.displayName)")

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
            // 更新为同步中状态
            stateManager.syncStatus = .syncing
            // 发送通知更新菜单栏
            NotificationCenter.default.post(name: .syncStatusDidChange, object: nil)
            logger.info("同步状态变更为: 同步中")

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
