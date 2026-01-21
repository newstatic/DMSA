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
