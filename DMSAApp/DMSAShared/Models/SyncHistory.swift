import Foundation

/// 同步历史记录
public struct SyncHistory: Codable, Identifiable, Sendable {
    public var id: String
    public var syncPairId: String
    public var diskId: String
    public var startTime: Date
    public var endTime: Date?
    public var status: SyncStatus
    public var filesAdded: Int
    public var filesUpdated: Int
    public var filesDeleted: Int
    public var filesSkipped: Int
    public var bytesTransferred: Int64
    public var errorMessage: String?
    public var details: [SyncOperationDetail]

    public init(syncPairId: String, diskId: String) {
        self.id = UUID().uuidString
        self.syncPairId = syncPairId
        self.diskId = diskId
        self.startTime = Date()
        self.endTime = nil
        self.status = .inProgress
        self.filesAdded = 0
        self.filesUpdated = 0
        self.filesDeleted = 0
        self.filesSkipped = 0
        self.bytesTransferred = 0
        self.errorMessage = nil
        self.details = []
    }

    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    public var formattedDuration: String? {
        guard let dur = duration else { return nil }
        if dur < 60 {
            return String(format: "%.1f 秒", dur)
        } else if dur < 3600 {
            return String(format: "%.1f 分钟", dur / 60)
        } else {
            return String(format: "%.1f 小时", dur / 3600)
        }
    }

    public var totalFiles: Int {
        return filesAdded + filesUpdated + filesDeleted
    }

    public var formattedBytesTransferred: String {
        return formatBytes(bytesTransferred)
    }

    /// 转换为 Data (用于 XPC 传输)
    public func toData() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    /// 从 Data 创建 (用于 XPC 传输)
    public static func from(data: Data) -> SyncHistory? {
        return try? JSONDecoder().decode(SyncHistory.self, from: data)
    }

    /// 从 Data 数组创建
    public static func arrayFrom(data: Data) -> [SyncHistory] {
        return (try? JSONDecoder().decode([SyncHistory].self, from: data)) ?? []
    }
}

/// 同步操作详情
public struct SyncOperationDetail: Codable, Identifiable, Sendable {
    public var id: String
    public var path: String
    public var operation: OperationType
    public var size: Int64
    public var success: Bool
    public var errorMessage: String?
    public var timestamp: Date

    public init(path: String, operation: OperationType, size: Int64 = 0) {
        self.id = UUID().uuidString
        self.path = path
        self.operation = operation
        self.size = size
        self.success = true
        self.errorMessage = nil
        self.timestamp = Date()
    }

    public enum OperationType: String, Codable, Sendable {
        case add
        case update
        case delete
        case skip
        case conflict

        public var displayName: String {
            switch self {
            case .add: return "添加"
            case .update: return "更新"
            case .delete: return "删除"
            case .skip: return "跳过"
            case .conflict: return "冲突"
            }
        }

        public var icon: String {
            switch self {
            case .add: return "plus.circle"
            case .update: return "arrow.triangle.2.circlepath"
            case .delete: return "trash"
            case .skip: return "arrow.right.circle"
            case .conflict: return "exclamationmark.triangle"
            }
        }
    }
}

/// 同步统计
public struct SyncStatistics: Codable, Sendable {
    public var syncPairId: String
    public var date: Date
    public var totalSyncs: Int
    public var successfulSyncs: Int
    public var failedSyncs: Int
    public var totalFilesProcessed: Int
    public var totalBytesTransferred: Int64
    public var averageDuration: TimeInterval

    public init(syncPairId: String, date: Date = Date()) {
        self.syncPairId = syncPairId
        self.date = date
        self.totalSyncs = 0
        self.successfulSyncs = 0
        self.failedSyncs = 0
        self.totalFilesProcessed = 0
        self.totalBytesTransferred = 0
        self.averageDuration = 0
    }

    public var successRate: Double {
        guard totalSyncs > 0 else { return 0 }
        return Double(successfulSyncs) / Double(totalSyncs)
    }
}
