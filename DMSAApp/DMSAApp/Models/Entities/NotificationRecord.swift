import Foundation

/// 通知操作类型
enum NotificationActionType: String, Codable, CaseIterable {
    case openSettings          // 打开设置页面
    case openDiskSettings      // 打开硬盘设置
    case openSyncPairSettings  // 打开同步对设置
    case openLogs              // 打开日志
    case openHistory           // 打开历史
    case none                  // 无操作

    var displayName: String {
        switch self {
        case .openSettings: return "notification.action.openSettings".localized
        case .openDiskSettings: return "notification.action.openDiskSettings".localized
        case .openSyncPairSettings: return "notification.action.openSyncPairSettings".localized
        case .openLogs: return "notification.action.openLogs".localized
        case .openHistory: return "notification.action.openHistory".localized
        case .none: return "notification.action.none".localized
        }
    }

    var icon: String {
        switch self {
        case .openSettings: return "gearshape"
        case .openDiskSettings: return "externaldrive"
        case .openSyncPairSettings: return "folder"
        case .openLogs: return "doc.text"
        case .openHistory: return "clock.arrow.circlepath"
        case .none: return "circle"
        }
    }
}

/// 通知记录数据模型
class NotificationRecord: Identifiable, Codable {
    var id: UInt64
    var type: String               // 通知类型 (NotificationType.rawValue)
    var title: String              // 通知标题
    var body: String               // 通知内容
    var createdAt: Date            // 创建时间
    var isRead: Bool               // 是否已读
    var userInfo: [String: String] // 附加信息 (diskId, syncPairId, error 等)
    var actionType: NotificationActionType // 跳转类型

    init(
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
    static func determineActionType(type: String, userInfo: [String: String]) -> NotificationActionType {
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

    /// 获取类型图标
    var typeIcon: String {
        switch type {
        case "sync_completed": return "checkmark.circle.fill"
        case "sync_failed": return "xmark.circle.fill"
        case "disk_connected": return "externaldrive.fill.badge.checkmark"
        case "disk_disconnected": return "externaldrive.fill.badge.minus"
        case "cache_warning": return "exclamationmark.triangle.fill"
        case "error": return "exclamationmark.circle.fill"
        case "sync_started": return "arrow.triangle.2.circlepath"
        default: return "bell.fill"
        }
    }

    /// 获取类型颜色名称
    var typeColorName: String {
        switch type {
        case "sync_completed": return "green"
        case "sync_failed", "error": return "red"
        case "disk_connected": return "blue"
        case "disk_disconnected": return "gray"
        case "cache_warning": return "orange"
        case "sync_started": return "blue"
        default: return "primary"
        }
    }
}
