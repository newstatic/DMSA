import Foundation

/// Notification action type
enum NotificationActionType: String, Codable, CaseIterable {
    case openSettings          // Open settings page
    case openDiskSettings      // Open disk settings
    case openSyncPairSettings  // Open sync pair settings
    case openLogs              // Open logs
    case openHistory           // Open history
    case none                  // No action

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

/// Notification record data model
class NotificationRecord: Identifiable, Codable {
    var id: UInt64
    var type: String               // Notification type (NotificationType.rawValue)
    var title: String              // Notification title
    var body: String               // Notification body
    var createdAt: Date            // Creation time
    var isRead: Bool               // Whether read
    var userInfo: [String: String] // Additional info (diskId, syncPairId, error, etc.)
    var actionType: NotificationActionType // Navigation action type

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

    /// Automatically determine navigation action type based on notification type and userInfo
    static func determineActionType(type: String, userInfo: [String: String]) -> NotificationActionType {
        // Check for config-related errors
        let hasConfigError = userInfo["configError"] != nil

        switch type {
        case "sync_failed", "error":
            if hasConfigError {
                // Config error -> navigate to settings
                if userInfo["diskId"] != nil {
                    return .openDiskSettings
                } else if userInfo["syncPairId"] != nil {
                    return .openSyncPairSettings
                }
                return .openSettings
            }
            // Other errors -> navigate to logs
            return .openLogs

        case "cache_warning":
            return .openSettings // Navigate to cache settings

        case "disk_connected", "disk_disconnected":
            return .openDiskSettings

        case "sync_started", "sync_completed":
            return .openHistory

        default:
            return .openLogs
        }
    }

    /// Get type icon
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

    /// Get type color name
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
