import Foundation

/// 同步统计实体 (按天聚合)
/// 用于记录和分析同步性能数据
class SyncStatistics: Identifiable, Codable {
    var id: UInt64 = 0
    var date: Date = Date()
    var totalSyncs: Int = 0
    var successfulSyncs: Int = 0
    var failedSyncs: Int = 0
    var totalFilesTransferred: Int = 0
    var totalBytesTransferred: Int64 = 0
    var averageDuration: TimeInterval = 0
    var diskId: String = ""

    init() {}

    init(date: Date, diskId: String) {
        self.date = date
        self.diskId = diskId
    }

    /// 成功率
    var successRate: Double {
        guard totalSyncs > 0 else { return 0 }
        return Double(successfulSyncs) / Double(totalSyncs) * 100
    }

    /// 格式化成功率
    var formattedSuccessRate: String {
        return String(format: "%.1f%%", successRate)
    }

    /// 格式化传输大小
    var formattedBytesTransferred: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytesTransferred)
    }

    /// 格式化平均持续时间
    var formattedAverageDuration: String {
        let seconds = Int(averageDuration)
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

    /// 格式化日期
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    /// 更新统计数据
    func update(with history: SyncHistory) {
        totalSyncs += 1
        if history.status == .completed {
            successfulSyncs += 1
        } else if history.status == .failed {
            failedSyncs += 1
        }
        totalFilesTransferred += history.filesCount
        totalBytesTransferred += history.totalSize

        // 更新平均持续时间
        let totalDuration = averageDuration * Double(totalSyncs - 1) + history.duration
        averageDuration = totalDuration / Double(totalSyncs)
    }
}

// MARK: - SyncStatistics Equatable

extension SyncStatistics: Equatable {
    static func == (lhs: SyncStatistics, rhs: SyncStatistics) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - SyncStatistics Hashable

extension SyncStatistics: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
