import Foundation

/// 同步历史实体
/// 记录每次同步操作的详细信息
class SyncHistory: Identifiable, Codable {
    var id: UInt64 = 0
    var startedAt: Date = Date()
    var completedAt: Date?
    var status: SyncStatus = .pending
    var direction: SyncDirection = .localToExternal
    var filesCount: Int = 0
    var totalSize: Int64 = 0
    var diskId: String = ""
    var syncPairId: String = ""
    var errorMessage: String?

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "startTime"
        case completedAt = "endTime"
        case status
        case direction
        case filesCount = "totalFiles"
        case totalSize = "bytesTransferred"
        case diskId
        case syncPairId
        case errorMessage
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // ObjectBox Id 可能编码为 Int64 或 UInt64
        if let uint64Id = try? container.decode(UInt64.self, forKey: .id) {
            id = uint64Id
        } else if let int64Id = try? container.decode(Int64.self, forKey: .id) {
            id = UInt64(bitPattern: int64Id)
        } else {
            id = 0
        }
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)

        // status 可能是 Int 或直接是 SyncStatus
        if let statusInt = try? container.decode(Int.self, forKey: .status) {
            status = SyncStatus(rawValue: statusInt) ?? .pending
        } else {
            status = try container.decode(SyncStatus.self, forKey: .status)
        }

        // direction 可能是 Int 或 String
        if let directionInt = try? container.decode(Int.self, forKey: .direction) {
            // Int mapping: 0 = localToExternal, 1 = externalToLocal, 2 = bidirectional
            switch directionInt {
            case 0: direction = .localToExternal
            case 1: direction = .externalToLocal
            case 2: direction = .bidirectional
            default: direction = .localToExternal
            }
        } else if let directionStr = try? container.decode(String.self, forKey: .direction) {
            direction = SyncDirection(rawValue: directionStr) ?? .localToExternal
        } else {
            direction = try container.decode(SyncDirection.self, forKey: .direction)
        }

        filesCount = try container.decode(Int.self, forKey: .filesCount)
        totalSize = try container.decode(Int64.self, forKey: .totalSize)
        diskId = try container.decode(String.self, forKey: .diskId)
        syncPairId = try container.decode(String.self, forKey: .syncPairId)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }

    /// 同步持续时间
    var duration: TimeInterval {
        guard let completed = completedAt else { return 0 }
        return completed.timeIntervalSince(startedAt)
    }

    init() {}

    init(diskId: String, syncPairId: String, direction: SyncDirection = .localToExternal) {
        self.diskId = diskId
        self.syncPairId = syncPairId
        self.direction = direction
        self.startedAt = Date()
    }

    /// 格式化持续时间
    var formattedDuration: String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds) 秒"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            let secs = seconds % 60
            return "\(minutes) 分 \(secs) 秒"
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "\(hours) 小时 \(minutes) 分"
        }
    }

    /// 格式化传输大小
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }

    /// 标记为开始
    func markStarted() {
        status = .inProgress
        startedAt = Date()
    }

    /// 标记为完成
    func markCompleted(filesCount: Int, totalSize: Int64) {
        status = .completed
        completedAt = Date()
        self.filesCount = filesCount
        self.totalSize = totalSize
    }

    /// 标记为失败
    func markFailed(error: String) {
        status = .failed
        completedAt = Date()
        errorMessage = error
    }

    /// 标记为取消
    func markCancelled() {
        status = .cancelled
        completedAt = Date()
    }
}

// MARK: - SyncHistory Equatable

extension SyncHistory: Equatable {
    static func == (lhs: SyncHistory, rhs: SyncHistory) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - SyncHistory Hashable

extension SyncHistory: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
