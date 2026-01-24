import Foundation

/// 通知操作类型
public enum NotificationActionType: String, Codable, CaseIterable, Sendable {
    case openSettings          // 打开设置页面
    case openDiskSettings      // 打开硬盘设置
    case openSyncPairSettings  // 打开同步对设置
    case openLogs              // 打开日志
    case openHistory           // 打开历史
    case none                  // 无操作
}

/// 通知记录数据模型 (共享版本)
public struct NotificationRecord: Identifiable, Codable, Sendable {
    public var id: UInt64
    public var type: String               // 通知类型 (NotificationType.rawValue)
    public var title: String              // 通知标题
    public var body: String               // 通知内容
    public var createdAt: Date            // 创建时间
    public var isRead: Bool               // 是否已读
    public var userInfo: [String: String] // 附加信息 (diskId, syncPairId, error 等)
    public var actionType: NotificationActionType // 跳转类型

    public init(
        id: UInt64 = 0,
        type: String,
        title: String,
        body: String,
        createdAt: Date = Date(),
        isRead: Bool = false,
        userInfo: [String: String] = [:],
        actionType: NotificationActionType = .none
    ) {
        self.id = id == 0 ? UInt64(Date().timeIntervalSince1970 * 1000) : id
        self.type = type
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.isRead = isRead
        self.userInfo = userInfo
        self.actionType = actionType
    }

    /// 根据通知类型和 userInfo 自动确定跳转类型
    public static func determineActionType(type: String, userInfo: [String: String]) -> NotificationActionType {
        // 检查是否有配置相关错误
        let hasConfigError = userInfo["configError"] != nil

        switch type {
        case "sync_failed", "error":
            if hasConfigError {
                // 配置错误跳转设置
                if userInfo["diskId"] != nil {
                    return .openDiskSettings
                } else if userInfo["syncPairId"] != nil {
                    return .openSyncPairSettings
                }
                return .openSettings
            }
            // 其他错误跳转日志
            return .openLogs

        case "cache_warning":
            return .openSettings // 跳转缓存设置

        case "disk_connected", "disk_disconnected":
            return .openDiskSettings

        case "sync_started", "sync_completed":
            return .openHistory

        default:
            return .openLogs
        }
    }
}
