import Foundation

/// Sync statistics entity (aggregated by day)
/// Used to record and analyze sync performance data
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

    /// Success rate
    var successRate: Double {
        guard totalSyncs > 0 else { return 0 }
        return Double(successfulSyncs) / Double(totalSyncs) * 100
    }

    /// Formatted success rate
    var formattedSuccessRate: String {
        return String(format: "%.1f%%", successRate)
    }

    /// Formatted bytes transferred
    var formattedBytesTransferred: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytesTransferred)
    }

    /// Formatted average duration
    var formattedAverageDuration: String {
        let seconds = Int(averageDuration)
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            let secs = seconds % 60
            return "\(minutes)m \(secs)s"
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }

    /// Formatted date
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    /// Update statistics
    func update(with history: SyncHistory) {
        totalSyncs += 1
        if history.status == .completed {
            successfulSyncs += 1
        } else if history.status == .failed {
            failedSyncs += 1
        }
        totalFilesTransferred += history.filesCount
        totalBytesTransferred += history.totalSize

        // Update average duration
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
