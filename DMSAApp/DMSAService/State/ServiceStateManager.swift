import Foundation

// MARK: - 通知队列

/// 通知队列 (用于启动时缓存通知)
actor NotificationQueue {
    private var queue: [PendingNotification] = []
    private var isFlushingEnabled = false
    private let maxQueueSize = 100

    struct PendingNotification {
        let name: String
        let data: String?
        let timestamp: Date
    }

    /// 添加通知到队列
    func enqueue(name: String, data: String?) {
        let notification = PendingNotification(name: name, data: data, timestamp: Date())

        if isFlushingEnabled {
            // 直接发送
            sendNotification(notification)
        } else {
            // 加入队列
            queue.append(notification)
            // 限制队列大小
            if queue.count > maxQueueSize {
                queue.removeFirst()
            }
        }
    }

    /// 启用通知刷新 (XPC 就绪后调用)
    func enableFlushing() {
        isFlushingEnabled = true
        flushQueue()
    }

    /// 刷新队列中的所有通知
    private func flushQueue() {
        for notification in queue {
            sendNotification(notification)
        }
        queue.removeAll()
    }

    /// 发送单个通知
    private nonisolated func sendNotification(_ notification: PendingNotification) {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(notification.name),
            object: notification.data,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    /// 获取队列大小
    var count: Int {
        return queue.count
    }
}

// MARK: - 服务状态管理器

/// 服务状态管理器
/// 参考文档: SERVICE_FLOW/05_状态管理器.md
actor ServiceStateManager {

    // MARK: - 单例

    static let shared = ServiceStateManager()

    // MARK: - 属性

    private let logger = Logger.forService("StateManager")

    /// 全局服务状态
    private var globalState: ServiceState = .starting

    /// 组件状态
    private var componentStates: [String: ComponentStateInfo] = [:]

    /// 通知队列
    private let notificationQueue = NotificationQueue()

    /// 配置状态
    private var configStatus = ConfigStatus()

    /// 服务启动时间
    private let startTime = Date()

    /// 最后一个错误
    private var lastError: ServiceErrorInfo?

    /// 服务版本
    private let version = "4.9"

    /// 协议版本
    private let protocolVersion = 1

    // MARK: - 初始化

    private init() {
        // 初始化核心组件状态
        for component in ServiceComponent.allCases {
            componentStates[component.rawValue] = ComponentStateInfo(name: component.rawValue)
        }
    }

    // MARK: - 全局状态管理

    /// 设置全局状态
    func setState(_ newState: ServiceState) async {
        let oldState = globalState
        guard oldState != newState else { return }

        globalState = newState

        // 更新日志状态缓存 (用于标准格式日志)
        LoggerStateCache.update(newState.name)

        logger.info("状态变更: \(oldState.name) → \(newState.name)")

        // 发送状态变更通知
        await sendStateChangedNotification(oldState: oldState, newState: newState)

        // 特殊状态处理
        switch newState {
        case .xpcReady:
            // XPC 就绪，启用通知刷新
            await notificationQueue.enableFlushing()
            await sendXPCReadyNotification()

        case .ready:
            // 服务就绪，发送 serviceReady 通知
            await sendServiceReadyNotification()

        case .error:
            // 错误状态，发送 serviceError 通知
            if let error = lastError {
                await sendServiceErrorNotification(error: error)
            }

        default:
            break
        }
    }

    /// 获取当前全局状态
    func getState() -> ServiceState {
        return globalState
    }

    /// 等待特定状态
    func waitForState(_ target: ServiceState, timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while globalState != target && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        return globalState == target
    }

    // MARK: - 组件状态管理

    /// 设置组件状态
    func setComponentState(_ component: ServiceComponent, state: ComponentState, error: ComponentError? = nil) async {
        var info = componentStates[component.rawValue] ?? ComponentStateInfo(name: component.rawValue)
        let oldState = info.state

        info.state = state
        info.lastUpdated = Date()
        info.error = error

        componentStates[component.rawValue] = info

        // 日志
        if oldState != state {
            if let error = error {
                logger.error("[\(globalState.name.padding(toLength: 11, withPad: " ", startingAt: 0))] [\(component.logName)] [\(state.logName)] 错误: \(error.message)")
            } else {
                logger.info("[\(globalState.name.padding(toLength: 11, withPad: " ", startingAt: 0))] [\(component.logName)] [\(state.logName)]")
            }
        }

        // 组件错误时发送通知
        if state == .error, let error = error {
            await sendComponentErrorNotification(component: component, error: error)
        }
    }

    /// 获取组件状态
    func getComponentState(_ component: ServiceComponent) -> ComponentStateInfo? {
        return componentStates[component.rawValue]
    }

    /// 更新组件性能指标
    func updateComponentMetrics(_ component: ServiceComponent, metrics: ComponentMetrics) async {
        guard var info = componentStates[component.rawValue] else { return }
        info.metrics = metrics
        componentStates[component.rawValue] = info
    }

    // MARK: - 配置状态管理

    /// 设置配置状态
    func setConfigStatus(_ status: ConfigStatus) async {
        configStatus = status

        // 发送配置状态通知
        await sendConfigStatusNotification(status: status)

        // 如果有冲突，发送冲突通知
        if let conflicts = status.conflicts, !conflicts.isEmpty {
            await sendConfigConflictNotification(conflicts: conflicts)
        }
    }

    /// 获取配置状态
    func getConfigStatus() -> ConfigStatus {
        return configStatus
    }

    // MARK: - 错误管理

    /// 设置最后错误
    func setLastError(_ error: ServiceErrorInfo) async {
        lastError = error
    }

    /// 清除最后错误
    func clearLastError() async {
        lastError = nil
    }

    // MARK: - 完整状态

    /// 获取完整服务状态
    func getFullState() -> ServiceFullState {
        return ServiceFullState(
            globalState: globalState,
            components: componentStates,
            config: configStatus,
            pendingNotifications: 0,  // 通知队列是 actor，需要异步获取
            startTime: startTime,
            lastError: lastError,
            version: version,
            protocolVersion: protocolVersion
        )
    }

    // MARK: - 操作权限检查

    /// 检查是否允许执行指定操作
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

    // MARK: - 通知发送

    /// 发送状态变更通知
    private func sendStateChangedNotification(oldState: ServiceState, newState: ServiceState) async {
        let data: [String: Any] = [
            "oldState": oldState.rawValue,
            "oldStateName": oldState.name,
            "newState": newState.rawValue,
            "newStateName": newState.name,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: jsonData, encoding: .utf8) {
            await notificationQueue.enqueue(name: Constants.Notifications.stateChanged, data: json)
        }
    }

    /// 发送 XPC 就绪通知
    private func sendXPCReadyNotification() async {
        let data: [String: Any] = [
            "version": version,
            "protocolVersion": protocolVersion,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: jsonData, encoding: .utf8) {
            await notificationQueue.enqueue(name: Constants.Notifications.xpcReady, data: json)
        }
    }

    /// 发送服务就绪通知
    private func sendServiceReadyNotification() async {
        let fullState = getFullState()
        if let jsonData = try? JSONEncoder().encode(fullState),
           let json = String(data: jsonData, encoding: .utf8) {
            await notificationQueue.enqueue(name: Constants.Notifications.serviceReady, data: json)
        }
    }

    /// 发送服务错误通知
    private func sendServiceErrorNotification(error: ServiceErrorInfo) async {
        if let jsonData = try? JSONEncoder().encode(error),
           let json = String(data: jsonData, encoding: .utf8) {
            await notificationQueue.enqueue(name: Constants.Notifications.serviceError, data: json)
        }
    }

    /// 发送组件错误通知
    private func sendComponentErrorNotification(component: ServiceComponent, error: ComponentError) async {
        let data: [String: Any] = [
            "component": component.rawValue,
            "errorCode": error.code,
            "errorMessage": error.message,
            "recoverable": error.recoverable,
            "timestamp": error.timestamp.timeIntervalSince1970
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: jsonData, encoding: .utf8) {
            await notificationQueue.enqueue(name: Constants.Notifications.componentError, data: json)
        }
    }

    /// 发送配置状态通知
    private func sendConfigStatusNotification(status: ConfigStatus) async {
        if let jsonData = try? JSONEncoder().encode(status),
           let json = String(data: jsonData, encoding: .utf8) {
            await notificationQueue.enqueue(name: Constants.Notifications.configStatus, data: json)
        }
    }

    /// 发送配置冲突通知
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

        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: jsonData, encoding: .utf8) {
            await notificationQueue.enqueue(name: Constants.Notifications.configConflict, data: json)
        }
    }

    /// 发送 VFS 挂载完成通知
    func sendVFSMountedNotification(syncPairIds: [String], mountPoints: [String]) async {
        let data: [String: Any] = [
            "syncPairIds": syncPairIds,
            "mountPoints": mountPoints,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: jsonData, encoding: .utf8) {
            await notificationQueue.enqueue(name: Constants.Notifications.vfsMounted, data: json)
        }
    }

    /// 发送索引进度通知
    func sendIndexProgressNotification(progress: IndexProgress) async {
        if let jsonData = try? JSONEncoder().encode(progress),
           let json = String(data: jsonData, encoding: .utf8) {
            await notificationQueue.enqueue(name: Constants.Notifications.indexProgress, data: json)
        }
    }

    /// 发送索引完成通知
    func sendIndexReadyNotification(syncPairId: String, totalFiles: Int, totalSize: Int64, duration: TimeInterval) async {
        let data: [String: Any] = [
            "syncPairId": syncPairId,
            "totalFiles": totalFiles,
            "totalSize": totalSize,
            "duration": duration,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: jsonData, encoding: .utf8) {
            await notificationQueue.enqueue(name: Constants.Notifications.indexReady, data: json)
        }
    }

    /// 发送索引完成通知 (简化版本)
    func sendIndexReadyNotification(syncPairId: String) async {
        let data: [String: Any] = [
            "syncPairId": syncPairId,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: jsonData, encoding: .utf8) {
            await notificationQueue.enqueue(name: Constants.Notifications.indexReady, data: json)
        }
    }
}
