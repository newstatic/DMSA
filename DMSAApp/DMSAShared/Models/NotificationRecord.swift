import Foundation

/// Notification action type
public enum NotificationActionType: String, Codable, CaseIterable, Sendable {
    case openSettings          // Open settings page
    case openDiskSettings      // Open disk settings
    case openSyncPairSettings  // Open sync pair settings
    case openLogs              // Open logs
    case openHistory           // Open history
    case none                  // No action
}

/// Notification record data model (shared version)
public struct NotificationRecord: Identifiable, Codable, Sendable {
    public var id: UInt64
    public var type: String               // Notification type (NotificationType.rawValue)
    public var title: String              // Notification title
    public var body: String               // Notification content
    public var createdAt: Date            // Creation time
    public var isRead: Bool               // Whether read
    public var userInfo: [String: String] // Additional info (diskId, syncPairId, error, etc.)
    public var actionType: NotificationActionType // Navigation type

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

    /// Determine navigation type based on notification type and userInfo
    public static func determineActionType(type: String, userInfo: [String: String]) -> NotificationActionType {
        // Check for config-related errors
        let hasConfigError = userInfo["configError"] != nil

        switch type {
        case "sync_failed", "error":
            if hasConfigError {
                // Config errors navigate to settings
                if userInfo["diskId"] != nil {
                    return .openDiskSettings
                } else if userInfo["syncPairId"] != nil {
                    return .openSyncPairSettings
                }
                return .openSettings
            }
            // Other errors navigate to logs
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
}
