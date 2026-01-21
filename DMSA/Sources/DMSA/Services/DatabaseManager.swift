import Foundation

/// 数据库管理器
/// 注意: 这是一个简化实现，使用 JSON 文件存储数据
/// 如果需要更高性能，可以替换为 ObjectBox 或 Core Data
final class DatabaseManager {
    static let shared = DatabaseManager()

    private let fileManager = FileManager.default
    private let dataDirectory: URL

    // 数据存储文件
    private let fileEntriesURL: URL
    private let syncHistoryURL: URL
    private let syncStatisticsURL: URL

    // 内存缓存
    private var fileEntries: [String: FileEntry] = [:]  // virtualPath -> FileEntry
    private var syncHistory: [SyncHistory] = []
    private var syncStatistics: [String: SyncStatistics] = [:]  // dateKey -> Statistics

    private let queue = DispatchQueue(label: "com.ttttt.dmsa.database")

    private init() {
        dataDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DMSA/Data")

        // 确保数据目录存在
        try? fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        fileEntriesURL = dataDirectory.appendingPathComponent("file_entries.json")
        syncHistoryURL = dataDirectory.appendingPathComponent("sync_history.json")
        syncStatisticsURL = dataDirectory.appendingPathComponent("sync_statistics.json")

        loadAllData()
    }

    // MARK: - 数据加载

    private func loadAllData() {
        loadFileEntries()
        loadSyncHistory()
        loadSyncStatistics()
        Logger.shared.info("数据库加载完成")
    }

    private func loadFileEntries() {
        guard let data = try? Data(contentsOf: fileEntriesURL),
              let entries = try? JSONDecoder().decode([FileEntry].self, from: data) else {
            return
        }
        fileEntries = Dictionary(uniqueKeysWithValues: entries.map { ($0.virtualPath, $0) })
        Logger.shared.debug("加载 \(fileEntries.count) 个文件索引")
    }

    private func loadSyncHistory() {
        guard let data = try? Data(contentsOf: syncHistoryURL),
              let history = try? JSONDecoder().decode([SyncHistory].self, from: data) else {
            return
        }
        syncHistory = history
        Logger.shared.debug("加载 \(syncHistory.count) 条同步历史")
    }

    private func loadSyncStatistics() {
        guard let data = try? Data(contentsOf: syncStatisticsURL),
              let stats = try? JSONDecoder().decode([SyncStatistics].self, from: data) else {
            return
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        syncStatistics = Dictionary(uniqueKeysWithValues: stats.map {
            (dateFormatter.string(from: $0.date) + "_" + $0.diskId, $0)
        })
        Logger.shared.debug("加载 \(syncStatistics.count) 条统计数据")
    }

    // MARK: - 数据保存

    private func saveFileEntries() {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let entries = Array(self.fileEntries.values)
                let data = try JSONEncoder().encode(entries)
                try data.write(to: self.fileEntriesURL)
            } catch {
                Logger.shared.error("保存文件索引失败: \(error.localizedDescription)")
            }
        }
    }

    private func saveSyncHistory() {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(self.syncHistory)
                try data.write(to: self.syncHistoryURL)
            } catch {
                Logger.shared.error("保存同步历史失败: \(error.localizedDescription)")
            }
        }
    }

    private func saveSyncStatistics() {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let stats = Array(self.syncStatistics.values)
                let data = try JSONEncoder().encode(stats)
                try data.write(to: self.syncStatisticsURL)
            } catch {
                Logger.shared.error("保存统计数据失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - FileEntry 操作

    func getFileEntry(virtualPath: String) -> FileEntry? {
        return queue.sync { fileEntries[virtualPath] }
    }

    func saveFileEntry(_ entry: FileEntry) {
        queue.async { [weak self] in
            self?.fileEntries[entry.virtualPath] = entry
            self?.saveFileEntries()
        }
    }

    func updateFileLocation(virtualPath: String, location: FileLocation, localPath: String? = nil, externalPath: String? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if var entry = self.fileEntries[virtualPath] {
                entry.location = location
                if let local = localPath { entry.localPath = local }
                if let external = externalPath { entry.externalPath = external }
                entry.modifiedAt = Date()
                self.fileEntries[virtualPath] = entry
                self.saveFileEntries()
            }
        }
    }

    func markClean(_ virtualPath: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if var entry = self.fileEntries[virtualPath] {
                entry.isDirty = false
                self.fileEntries[virtualPath] = entry
                self.saveFileEntries()
            }
        }
    }

    func updateAccessTime(_ virtualPath: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if var entry = self.fileEntries[virtualPath] {
                entry.accessedAt = Date()
                self.fileEntries[virtualPath] = entry
                // 不立即保存，减少 I/O
            }
        }
    }

    func getEvictableFiles() -> [FileEntry] {
        return queue.sync {
            fileEntries.values.filter { entry in
                !entry.isDirty && entry.location == .both && entry.localPath != nil
            }
        }
    }

    func getDirtyFiles() -> [FileEntry] {
        return queue.sync {
            fileEntries.values.filter { $0.isDirty }
        }
    }

    func getAllFileEntries() -> [FileEntry] {
        return queue.sync { Array(fileEntries.values) }
    }

    func deleteFileEntry(virtualPath: String) {
        queue.async { [weak self] in
            self?.fileEntries.removeValue(forKey: virtualPath)
            self?.saveFileEntries()
        }
    }

    // MARK: - SyncHistory 操作

    func saveSyncHistory(_ history: SyncHistory) {
        queue.async { [weak self] in
            self?.syncHistory.append(history)
            self?.saveSyncHistory()
            self?.updateStatistics(from: history)
        }
    }

    func getSyncHistory(limit: Int = 100) -> [SyncHistory] {
        return queue.sync {
            Array(syncHistory.suffix(limit).reversed())
        }
    }

    func getSyncHistory(forDiskId diskId: String, limit: Int = 50) -> [SyncHistory] {
        return queue.sync {
            syncHistory.filter { $0.diskId == diskId }
                .suffix(limit)
                .reversed() as [SyncHistory]
        }
    }

    func clearSyncHistory(olderThan date: Date) {
        queue.async { [weak self] in
            self?.syncHistory.removeAll { $0.startedAt < date }
            self?.saveSyncHistory()
        }
    }

    func getAllSyncHistory() -> [SyncHistory] {
        return queue.sync {
            Array(syncHistory.reversed())
        }
    }

    func clearAllSyncHistory() {
        queue.async { [weak self] in
            self?.syncHistory.removeAll()
            self?.saveSyncHistory()
        }
    }

    // MARK: - Statistics 操作

    private func updateStatistics(from history: SyncHistory) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateKey = dateFormatter.string(from: history.startedAt) + "_" + history.diskId

        var stats = syncStatistics[dateKey] ?? SyncStatistics(date: history.startedAt, diskId: history.diskId)

        stats.totalSyncs += 1
        if history.status == .completed {
            stats.successfulSyncs += 1
        } else if history.status == .failed {
            stats.failedSyncs += 1
        }
        stats.totalFilesTransferred += history.filesCount
        stats.totalBytesTransferred += history.totalSize

        // 更新平均耗时
        if stats.totalSyncs > 0 {
            let totalDuration = stats.averageDuration * Double(stats.totalSyncs - 1) + history.duration
            stats.averageDuration = totalDuration / Double(stats.totalSyncs)
        }

        syncStatistics[dateKey] = stats
        saveSyncStatistics()
    }

    func getStatistics(forDiskId diskId: String, days: Int = 30) -> [SyncStatistics] {
        return queue.sync {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            return syncStatistics.values
                .filter { $0.diskId == diskId && $0.date >= cutoffDate }
                .sorted { $0.date < $1.date }
        }
    }

    func getTodayStatistics(forDiskId diskId: String) -> SyncStatistics? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateKey = dateFormatter.string(from: Date()) + "_" + diskId
        return queue.sync { syncStatistics[dateKey] }
    }

    // MARK: - 清理

    func clearAllData() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.fileEntries.removeAll()
            self.syncHistory.removeAll()
            self.syncStatistics.removeAll()

            try? self.fileManager.removeItem(at: self.fileEntriesURL)
            try? self.fileManager.removeItem(at: self.syncHistoryURL)
            try? self.fileManager.removeItem(at: self.syncStatisticsURL)

            Logger.shared.info("所有数据已清除")
        }
    }
}
