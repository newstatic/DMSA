import Foundation

/// Activity record type
public enum ActivityType: Int, Codable, Sendable {
    case syncStarted = 0
    case syncCompleted = 1
    case syncFailed = 2
    case evictionCompleted = 3
    case evictionFailed = 4
    case diskConnected = 5
    case diskDisconnected = 6
    case indexRebuilt = 7
    case configUpdated = 8
    case error = 9
}

/// Activity record - for Dashboard recent activity display
/// Service maintains latest 5, pushes to App in real-time
public struct ActivityRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var type: ActivityType
    public var title: String
    public var detail: String?
    public var timestamp: Date
    public var syncPairId: String?
    public var diskId: String?
    public var filesCount: Int?
    public var bytesCount: Int64?

    public init(
        type: ActivityType,
        title: String,
        detail: String? = nil,
        syncPairId: String? = nil,
        diskId: String? = nil,
        filesCount: Int? = nil,
        bytesCount: Int64? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.title = title
        self.detail = detail
        self.timestamp = Date()
        self.syncPairId = syncPairId
        self.diskId = diskId
        self.filesCount = filesCount
        self.bytesCount = bytesCount
    }

    public var icon: String {
        switch type {
        case .syncStarted: return "arrow.clockwise"
        case .syncCompleted: return "checkmark.circle.fill"
        case .syncFailed: return "xmark.circle.fill"
        case .evictionCompleted: return "trash.circle.fill"
        case .evictionFailed: return "exclamationmark.circle.fill"
        case .diskConnected: return "externaldrive.fill.badge.plus"
        case .diskDisconnected: return "externaldrive.badge.minus"
        case .indexRebuilt: return "doc.text.magnifyingglass"
        case .configUpdated: return "gear"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    public var colorName: String {
        switch type {
        case .syncStarted: return "blue"
        case .syncCompleted: return "green"
        case .syncFailed: return "red"
        case .evictionCompleted: return "blue"
        case .evictionFailed: return "red"
        case .diskConnected: return "green"
        case .diskDisconnected: return "orange"
        case .indexRebuilt: return "orange"
        case .configUpdated: return "gray"
        case .error: return "red"
        }
    }
}
