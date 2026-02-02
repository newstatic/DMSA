import Foundation

// MARK: - XPC 通知发送器

/// XPC 通知发送器
/// 通过 ServiceDelegate 向所有连接的客户端发送通知
enum XPCNotifier {
    private static let logger = Logger.forService("XPCNotifier")

    /// 发送状态变更通知
    static func notifyStateChanged(oldState: ServiceState, newState: ServiceState, data: Data?) {
        logger.info("[XPC通知] 状态变更: \(oldState.name) -> \(newState.name)")
        ServiceDelegate.shared?.notifyStateChanged(
            oldState: oldState.rawValue,
            newState: newState.rawValue,
            data: data
        )
    }

    /// 发送索引进度
    static func notifyIndexProgress(data: Data) {
        ServiceDelegate.shared?.notifyIndexProgress(data: data)
    }

    /// 发送索引就绪
    static func notifyIndexReady(syncPairId: String) {
        logger.info("[XPC通知] 索引就绪: \(syncPairId)")
        ServiceDelegate.shared?.notifyIndexReady(syncPairId: syncPairId)
    }

    /// 发送同步进度
    static func notifySyncProgress(data: Data) {
        ServiceDelegate.shared?.notifySyncProgress(data: data)
    }

    /// 发送同步状态变更
    static func notifySyncStatusChanged(syncPairId: String, status: SyncStatus, message: String?) {
        logger.info("[XPC通知] 同步状态变更: \(syncPairId) -> \(status.displayName)")
        ServiceDelegate.shared?.notifySyncStatusChanged(
            syncPairId: syncPairId,
            status: status.rawValue,
            message: message
        )
    }

    /// 发送同步完成
    static func notifySyncCompleted(syncPairId: String, filesCount: Int, bytesCount: Int64) {
        logger.info("[XPC通知] 同步完成: \(syncPairId), \(filesCount) 文件")
        ServiceDelegate.shared?.notifySyncCompleted(
            syncPairId: syncPairId,
            filesCount: filesCount,
            bytesCount: bytesCount
        )
    }

    /// 发送淘汰进度
    static func notifyEvictionProgress(data: Data) {
        ServiceDelegate.shared?.notifyEvictionProgress(data: data)
    }

    /// 发送组件错误
    static func notifyComponentError(component: String, code: Int, message: String, isCritical: Bool) {
        logger.info("[XPC通知] 组件错误: \(component) - \(message)")
        ServiceDelegate.shared?.notifyComponentError(
            component: component,
            code: code,
            message: message,
            isCritical: isCritical
        )
    }

    /// 发送配置更新
    static func notifyConfigUpdated() {
        logger.info("[XPC通知] 配置已更新")
        ServiceDelegate.shared?.notifyConfigUpdated()
    }

    /// 发送服务就绪
    static func notifyServiceReady() {
        logger.info("[XPC通知] 服务就绪")
        ServiceDelegate.shared?.notifyServiceReady()
    }

    /// 发送冲突检测
    static func notifyConflictDetected(data: Data) {
        logger.info("[XPC通知] 冲突检测")
        ServiceDelegate.shared?.notifyConflictDetected(data: data)
    }

    /// 发送磁盘状态变更
    static func notifyDiskChanged(diskName: String, isConnected: Bool) {
        logger.info("[XPC通知] 磁盘变更: \(diskName) -> \(isConnected ? "连接" : "断开")")
        ServiceDelegate.shared?.notifyDiskChanged(diskName: diskName, isConnected: isConnected)
    }

    /// 发送活动更新
    static func notifyActivitiesUpdated(data: Data) {
        ServiceDelegate.shared?.notifyActivitiesUpdated(data: data)
    }
}

// MARK: - 活动记录管理器

/// 管理最近 5 条活动记录，实时推送前端
actor ActivityManager {
    static let shared = ActivityManager()

    private let logger = Logger.forService("ActivityManager")
    private var activities: [ActivityRecord] = []
    private let maxCount = 5

    private init() {}

    /// 添加活动记录
    func addActivity(_ activity: ActivityRecord) {
        activities.insert(activity, at: 0)
        if activities.count > maxCount {
            activities = Array(activities.prefix(maxCount))
        }
        pushToClients()
    }

    /// 便捷方法：添加同步相关活动
    func addSyncActivity(type: ActivityType, syncPairId: String, diskId: String? = nil, filesCount: Int? = nil, bytesCount: Int64? = nil, detail: String? = nil) {
        let title: String
        switch type {
        case .syncStarted: title = "开始同步 \(syncPairId)"
        case .syncCompleted: title = "同步完成 \(syncPairId)"
        case .syncFailed: title = "同步失败 \(syncPairId)"
        default: title = "\(syncPairId)"
        }
        let activity = ActivityRecord(type: type, title: title, detail: detail, syncPairId: syncPairId, diskId: diskId, filesCount: filesCount, bytesCount: bytesCount)
        addActivity(activity)
    }

    /// 便捷方法：添加淘汰活动
    func addEvictionActivity(filesCount: Int, bytesCount: Int64, syncPairId: String? = nil, failed: Bool = false) {
        let type: ActivityType = failed ? .evictionFailed : .evictionCompleted
        let sizeStr = ByteCountFormatter.string(fromByteCount: bytesCount, countStyle: .file)
        let title = failed ? "淘汰失败" : "淘汰完成"
        let detail = "\(filesCount) 个文件, \(sizeStr)"
        let activity = ActivityRecord(type: type, title: title, detail: detail, syncPairId: syncPairId, filesCount: filesCount, bytesCount: bytesCount)
        addActivity(activity)
    }

    /// 便捷方法：添加磁盘活动
    func addDiskActivity(diskName: String, isConnected: Bool) {
        let type: ActivityType = isConnected ? .diskConnected : .diskDisconnected
        let title = isConnected ? "磁盘已连接" : "磁盘已断开"
        let activity = ActivityRecord(type: type, title: title, detail: diskName, diskId: diskName)
        addActivity(activity)
    }

    /// 获取当前活动列表
    func getActivities() -> [ActivityRecord] {
        return activities
    }

    /// 推送活动到所有客户端
    private func pushToClients() {
        guard let data = try? JSONEncoder().encode(activities) else { return }
        XPCNotifier.notifyActivitiesUpdated(data: data)
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
            // XPC 就绪，可以接受客户端连接
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
            pendingNotifications: 0,  // 现在使用 XPC 回调，不再有队列
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

    // MARK: - 通知发送 (通过 XPC 回调)

    /// 发送状态变更通知
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

    /// 发送 XPC 就绪通知 (内部使用，不通知客户端)
    private func sendXPCReadyNotification() async {
        // XPC 就绪是内部状态，不需要通知客户端
        logger.info("XPC 就绪，可以接受客户端连接")
    }

    /// 发送服务就绪通知
    private func sendServiceReadyNotification() async {
        XPCNotifier.notifyServiceReady()
    }

    /// 发送服务错误通知
    private func sendServiceErrorNotification(error: ServiceErrorInfo) async {
        XPCNotifier.notifyComponentError(
            component: "Service",
            code: error.code,
            message: error.message,
            isCritical: true
        )
    }

    /// 发送组件错误通知
    private func sendComponentErrorNotification(component: ServiceComponent, error: ComponentError) async {
        XPCNotifier.notifyComponentError(
            component: component.rawValue,
            code: error.code,
            message: error.message,
            isCritical: !error.recoverable
        )
    }

    /// 发送配置状态通知
    private func sendConfigStatusNotification(status: ConfigStatus) async {
        XPCNotifier.notifyConfigUpdated()
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

        if let jsonData = try? JSONSerialization.data(withJSONObject: data) {
            XPCNotifier.notifyConflictDetected(data: jsonData)
        }
    }

    /// 发送 VFS 挂载完成通知 (通过服务就绪通知)
    func sendVFSMountedNotification(syncPairIds: [String], mountPoints: [String]) async {
        // VFS 挂载完成后会设置 READY 状态，不需要单独通知
        logger.info("VFS 挂载完成: \(syncPairIds.joined(separator: ", "))")
    }

    /// 发送索引进度通知
    func sendIndexProgressNotification(progress: IndexProgress) async {
        if let jsonData = try? JSONEncoder().encode(progress) {
            XPCNotifier.notifyIndexProgress(data: jsonData)
        }
    }

    /// 发送索引完成通知
    func sendIndexReadyNotification(syncPairId: String, totalFiles: Int, totalSize: Int64, duration: TimeInterval) async {
        logger.info("索引完成: \(syncPairId), \(totalFiles) 文件, \(totalSize) 字节, 耗时 \(duration)s")
        XPCNotifier.notifyIndexReady(syncPairId: syncPairId)
    }

    /// 发送索引完成通知 (简化版本)
    func sendIndexReadyNotification(syncPairId: String) async {
        XPCNotifier.notifyIndexReady(syncPairId: syncPairId)
    }
}
