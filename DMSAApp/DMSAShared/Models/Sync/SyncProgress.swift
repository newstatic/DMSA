import Foundation

/// 同步进度
public struct SyncProgress: Codable, Sendable {
    public var syncPairId: String
    public var status: SyncStatus
    public var totalFiles: Int
    public var processedFiles: Int
    public var totalBytes: Int64
    public var processedBytes: Int64
    public var currentFile: String?
    public var startTime: Date?
    public var endTime: Date?
    public var errorMessage: String?
    public var speed: Int64  // bytes per second

    public init(syncPairId: String) {
        self.syncPairId = syncPairId
        self.status = .pending
        self.totalFiles = 0
        self.processedFiles = 0
        self.totalBytes = 0
        self.processedBytes = 0
        self.currentFile = nil
        self.startTime = nil
        self.endTime = nil
        self.errorMessage = nil
        self.speed = 0
    }

    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(processedBytes) / Double(totalBytes)
    }

    public var fileProgress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(processedFiles) / Double(totalFiles)
    }

    public var elapsedTime: TimeInterval? {
        guard let start = startTime else { return nil }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }

    public var estimatedTimeRemaining: TimeInterval? {
        guard let elapsed = elapsedTime, progress > 0, progress < 1 else { return nil }
        return elapsed * (1 - progress) / progress
    }

    public var formattedProgress: String {
        return String(format: "%.1f%%", progress * 100)
    }

    public var formattedSpeed: String {
        return formatBytes(speed) + "/s"
    }

    public var formattedETA: String? {
        guard let eta = estimatedTimeRemaining else { return nil }
        if eta < 60 {
            return String(format: "%.0f 秒", eta)
        } else if eta < 3600 {
            return String(format: "%.0f 分钟", eta / 60)
        } else {
            return String(format: "%.1f 小时", eta / 3600)
        }
    }

    /// 转换为 Data (用于 XPC 传输)
    public func toData() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    /// 从 Data 创建 (用于 XPC 传输)
    public static func from(data: Data) -> SyncProgress? {
        return try? JSONDecoder().decode(SyncProgress.self, from: data)
    }
}

/// 同步计划
public struct SyncPlan: Codable, Sendable {
    public var syncPairId: String
    public var filesToAdd: [String]
    public var filesToUpdate: [String]
    public var filesToDelete: [String]
    public var filesToSkip: [String]
    public var conflicts: [ConflictInfo]
    public var totalSize: Int64
    public var createdAt: Date

    public init(syncPairId: String) {
        self.syncPairId = syncPairId
        self.filesToAdd = []
        self.filesToUpdate = []
        self.filesToDelete = []
        self.filesToSkip = []
        self.conflicts = []
        self.totalSize = 0
        self.createdAt = Date()
    }

    public var totalOperations: Int {
        return filesToAdd.count + filesToUpdate.count + filesToDelete.count
    }

    public var hasConflicts: Bool {
        return !conflicts.isEmpty
    }
}

/// 冲突信息
public struct ConflictInfo: Codable, Identifiable, Sendable {
    public var id: String
    public var virtualPath: String
    public var localModified: Date?
    public var externalModified: Date?
    public var localSize: Int64
    public var externalSize: Int64
    public var resolution: ConflictResolution?
    public var resolved: Bool

    public init(virtualPath: String) {
        self.id = UUID().uuidString
        self.virtualPath = virtualPath
        self.localModified = nil
        self.externalModified = nil
        self.localSize = 0
        self.externalSize = 0
        self.resolution = nil
        self.resolved = false
    }

    public enum ConflictResolution: String, Codable, Sendable {
        case useLocal
        case useExternal
        case keepBoth
        case skip
    }
}

/// 文件元数据
public struct FileMetadata: Codable, Sendable {
    public var path: String
    public var size: Int64
    public var modifiedAt: Date
    public var createdAt: Date
    public var checksum: String?
    public var isDirectory: Bool
    public var permissions: UInt16

    public init(path: String) {
        self.path = path
        self.size = 0
        self.modifiedAt = Date()
        self.createdAt = Date()
        self.checksum = nil
        self.isDirectory = false
        self.permissions = 0o644
    }

    public init(path: String, attributes: [FileAttributeKey: Any]) {
        self.path = path
        self.size = attributes[.size] as? Int64 ?? 0
        self.modifiedAt = attributes[.modificationDate] as? Date ?? Date()
        self.createdAt = attributes[.creationDate] as? Date ?? Date()
        self.isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
        self.permissions = (attributes[.posixPermissions] as? UInt16) ?? 0o644
        self.checksum = nil
    }
}
