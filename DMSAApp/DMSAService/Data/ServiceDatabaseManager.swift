import Foundation

// MARK: - Service 数据库管理器
// 使用 ObjectBox 存储大量数据 (FileEntry, SyncHistory, SyncStatistics)
// 数据目录: /Library/Application Support/DMSA/ServiceData/

/// ObjectBox 实体: 文件索引
/// 存储文件在 LOCAL/EXTERNAL 的位置和状态
public final class ServiceFileEntry: Codable, Identifiable, Sendable {
    public var id: UInt64 = 0
    public var virtualPath: String = ""
    public var localPath: String?
    public var externalPath: String?
    public var location: Int = 0  // FileLocation.rawValue
    public var size: Int64 = 0
    public var createdAt: Date = Date()
    public var modifiedAt: Date = Date()
    public var accessedAt: Date = Date()
    public var checksum: String?
    public var isDirty: Bool = false
    public var isDirectory: Bool = false
    public var syncPairId: String = ""

    // 锁定状态
    public var lockState: Int = 0  // LockState.rawValue
    public var lockTime: Date?
    public var lockDirection: Int?  // SyncLockDirection.rawValue

    public init() {}

    public init(virtualPath: String, syncPairId: String) {
        self.virtualPath = virtualPath
        self.syncPairId = syncPairId
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.accessedAt = Date()
    }

    // MARK: - 便捷属性

    public var fileLocation: FileLocation {
        get { FileLocation(rawValue: location) ?? .notExists }
        set { location = newValue.rawValue }
    }

    public var fileName: String {
        (virtualPath as NSString).lastPathComponent
    }

    public var parentPath: String {
        (virtualPath as NSString).deletingLastPathComponent
    }

    public var isLocked: Bool {
        lockState == LockState.syncLocked.rawValue
    }

    public var needsSync: Bool {
        isDirty || location == FileLocation.localOnly.rawValue
    }
}

/// ObjectBox 实体: 同步历史
public final class ServiceSyncHistory: Codable, Identifiable, Sendable {
    public var id: UInt64 = 0
    public var syncPairId: String = ""
    public var diskId: String = ""
    public var startTime: Date = Date()
    public var endTime: Date?
    public var status: Int = 0  // SyncStatus.rawValue
    public var direction: Int = 0  // SyncDirection.rawValue
    public var totalFiles: Int = 0
    public var filesUpdated: Int = 0
    public var filesDeleted: Int = 0
    public var filesSkipped: Int = 0
    public var bytesTransferred: Int64 = 0
    public var errorMessage: String?

    public init() {}

    public init(syncPairId: String, diskId: String) {
        self.syncPairId = syncPairId
        self.diskId = diskId
        self.startTime = Date()
    }

    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
}

/// ObjectBox 实体: 同步统计 (按天聚合)
public final class ServiceSyncStatistics: Codable, Identifiable, Sendable {
    public var id: UInt64 = 0
    public var date: Date = Date()
    public var syncPairId: String = ""
    public var diskId: String = ""
    public var totalSyncs: Int = 0
    public var successfulSyncs: Int = 0
    public var failedSyncs: Int = 0
    public var totalFilesProcessed: Int = 0
    public var totalBytesTransferred: Int64 = 0
    public var averageDuration: TimeInterval = 0

    public init() {}

    public init(date: Date, syncPairId: String, diskId: String) {
        self.date = date
        self.syncPairId = syncPairId
        self.diskId = diskId
    }

    public var successRate: Double {
        guard totalSyncs > 0 else { return 0 }
        return Double(successfulSyncs) / Double(totalSyncs) * 100
    }
}

// MARK: - Service 数据库管理器

/// DMSAService 专用数据库管理器
/// - 存储位置: /Library/Application Support/DMSA/ServiceData/
/// - 大量数据使用 ObjectBox (或 JSON 作为过渡)
/// - 小配置使用 JSON
actor ServiceDatabaseManager {

    static let shared = ServiceDatabaseManager()

    private let logger = Logger.forService("Database")
    private let fileManager = FileManager.default

    // 数据目录 (Service 专用，与 App 隔离)
    private let dataDirectory: URL

    // ObjectBox Store (TODO: 集成 ObjectBox)
    // private var store: Store?

    // 过渡期使用 JSON 文件存储
    private let fileEntriesURL: URL
    private let syncHistoryURL: URL
    private let syncStatisticsURL: URL

    // 内存索引 (快速查询)
    private var fileEntries: [String: [String: ServiceFileEntry]] = [:]  // [syncPairId: [virtualPath: Entry]]
    private var syncHistory: [String: [ServiceSyncHistory]] = [:]  // [syncPairId: [History]]
    private var syncStatistics: [String: ServiceSyncStatistics] = [:]  // [dateKey: Statistics]

    // 写入队列 (批量写入优化)
    private var pendingWrites: Set<String> = []
    private var writeTask: Task<Void, Never>?
    private let writeDebounce: TimeInterval = 2.0

    // 配置
    private let maxHistoryPerPair = 500
    private let maxStatisticsDays = 90

    private init() {
        // Service 数据目录 (root 权限)
        dataDirectory = URL(fileURLWithPath: "/Library/Application Support/DMSA/ServiceData")

        fileEntriesURL = dataDirectory.appendingPathComponent("file_entries.json")
        syncHistoryURL = dataDirectory.appendingPathComponent("sync_history.json")
        syncStatisticsURL = dataDirectory.appendingPathComponent("sync_statistics.json")

        Task {
            await initialize()
        }
    }

    // MARK: - 初始化

    private func initialize() async {
        // 确保数据目录存在
        do {
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            logger.info("数据目录: \(dataDirectory.path)")
        } catch {
            logger.error("创建数据目录失败: \(error)")
        }

        // 加载数据
        await loadAllData()

        logger.info("ServiceDatabaseManager 初始化完成")
    }

    private func loadAllData() async {
        await loadFileEntries()
        await loadSyncHistory()
        await loadSyncStatistics()
    }

    // MARK: - FileEntry 操作

    private func loadFileEntries() async {
        guard let data = try? Data(contentsOf: fileEntriesURL) else { return }

        do {
            let allEntries = try JSONDecoder().decode([ServiceFileEntry].self, from: data)

            // 按 syncPairId 分组
            for entry in allEntries {
                if fileEntries[entry.syncPairId] == nil {
                    fileEntries[entry.syncPairId] = [:]
                }
                fileEntries[entry.syncPairId]?[entry.virtualPath] = entry
            }

            let total = allEntries.count
            logger.info("加载 \(total) 个文件索引")
        } catch {
            logger.error("加载文件索引失败: \(error)")
        }
    }

    func getFileEntry(virtualPath: String, syncPairId: String) -> ServiceFileEntry? {
        return fileEntries[syncPairId]?[virtualPath]
    }

    func getAllFileEntries(syncPairId: String) -> [ServiceFileEntry] {
        return Array(fileEntries[syncPairId]?.values ?? [])
    }

    func saveFileEntry(_ entry: ServiceFileEntry) {
        if fileEntries[entry.syncPairId] == nil {
            fileEntries[entry.syncPairId] = [:]
        }
        fileEntries[entry.syncPairId]?[entry.virtualPath] = entry
        scheduleSave("fileEntries")
    }

    func saveFileEntries(_ entries: [ServiceFileEntry]) {
        for entry in entries {
            if fileEntries[entry.syncPairId] == nil {
                fileEntries[entry.syncPairId] = [:]
            }
            fileEntries[entry.syncPairId]?[entry.virtualPath] = entry
        }
        scheduleSave("fileEntries")
    }

    func deleteFileEntry(virtualPath: String, syncPairId: String) {
        fileEntries[syncPairId]?.removeValue(forKey: virtualPath)
        scheduleSave("fileEntries")
    }

    func updateFileLocation(virtualPath: String, syncPairId: String, location: FileLocation, localPath: String? = nil, externalPath: String? = nil) {
        guard var entry = fileEntries[syncPairId]?[virtualPath] else { return }

        entry.location = location.rawValue
        if let local = localPath { entry.localPath = local }
        if let external = externalPath { entry.externalPath = external }
        entry.modifiedAt = Date()

        fileEntries[syncPairId]?[virtualPath] = entry
        scheduleSave("fileEntries")
    }

    func markFileDirty(virtualPath: String, syncPairId: String, dirty: Bool = true) {
        guard var entry = fileEntries[syncPairId]?[virtualPath] else { return }
        entry.isDirty = dirty
        entry.modifiedAt = Date()
        fileEntries[syncPairId]?[virtualPath] = entry
        scheduleSave("fileEntries")
    }

    func updateAccessTime(virtualPath: String, syncPairId: String) {
        guard var entry = fileEntries[syncPairId]?[virtualPath] else { return }
        entry.accessedAt = Date()
        fileEntries[syncPairId]?[virtualPath] = entry
        // 不立即保存，减少 I/O
    }

    func getDirtyFiles(syncPairId: String) -> [ServiceFileEntry] {
        return fileEntries[syncPairId]?.values.filter { $0.isDirty } ?? []
    }

    func getEvictableFiles(syncPairId: String) -> [ServiceFileEntry] {
        return fileEntries[syncPairId]?.values.filter { entry in
            !entry.isDirty &&
            entry.location == FileLocation.both.rawValue &&
            entry.localPath != nil &&
            entry.lockState == LockState.unlocked.rawValue
        }.sorted { $0.accessedAt < $1.accessedAt } ?? []
    }

    func clearFileEntries(syncPairId: String) {
        fileEntries.removeValue(forKey: syncPairId)
        scheduleSave("fileEntries")
    }

    // MARK: - SyncHistory 操作

    private func loadSyncHistory() async {
        guard let data = try? Data(contentsOf: syncHistoryURL) else { return }

        do {
            let allHistory = try JSONDecoder().decode([ServiceSyncHistory].self, from: data)

            // 按 syncPairId 分组
            for history in allHistory {
                if syncHistory[history.syncPairId] == nil {
                    syncHistory[history.syncPairId] = []
                }
                syncHistory[history.syncPairId]?.append(history)
            }

            logger.info("加载 \(allHistory.count) 条同步历史")
        } catch {
            logger.error("加载同步历史失败: \(error)")
        }
    }

    func saveSyncHistory(_ history: ServiceSyncHistory) {
        if syncHistory[history.syncPairId] == nil {
            syncHistory[history.syncPairId] = []
        }

        // 插入到开头
        syncHistory[history.syncPairId]?.insert(history, at: 0)

        // 限制数量
        if let count = syncHistory[history.syncPairId]?.count, count > maxHistoryPerPair {
            syncHistory[history.syncPairId]?.removeLast(count - maxHistoryPerPair)
        }

        scheduleSave("syncHistory")

        // 更新统计
        updateStatistics(from: history)
    }

    func getSyncHistory(syncPairId: String, limit: Int = 50) -> [ServiceSyncHistory] {
        return Array((syncHistory[syncPairId] ?? []).prefix(limit))
    }

    func getAllSyncHistory(limit: Int = 200) -> [ServiceSyncHistory] {
        var all: [ServiceSyncHistory] = []
        for histories in syncHistory.values {
            all.append(contentsOf: histories)
        }
        return all.sorted { $0.startTime > $1.startTime }.prefix(limit).map { $0 }
    }

    func clearSyncHistory(syncPairId: String) {
        syncHistory.removeValue(forKey: syncPairId)
        scheduleSave("syncHistory")
    }

    func clearOldHistory(olderThan date: Date) {
        for (syncPairId, histories) in syncHistory {
            syncHistory[syncPairId] = histories.filter { $0.startTime >= date }
        }
        scheduleSave("syncHistory")
    }

    // MARK: - SyncStatistics 操作

    private func loadSyncStatistics() async {
        guard let data = try? Data(contentsOf: syncStatisticsURL) else { return }

        do {
            let allStats = try JSONDecoder().decode([ServiceSyncStatistics].self, from: data)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            for stats in allStats {
                let key = "\(stats.syncPairId)_\(dateFormatter.string(from: stats.date))"
                syncStatistics[key] = stats
            }

            logger.info("加载 \(allStats.count) 条统计数据")
        } catch {
            logger.error("加载统计数据失败: \(error)")
        }
    }

    private func updateStatistics(from history: ServiceSyncHistory) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let key = "\(history.syncPairId)_\(dateFormatter.string(from: history.startTime))"

        var stats = syncStatistics[key] ?? ServiceSyncStatistics(
            date: history.startTime,
            syncPairId: history.syncPairId,
            diskId: history.diskId
        )

        stats.totalSyncs += 1

        if history.status == SyncStatus.completed.rawValue {
            stats.successfulSyncs += 1
        } else if history.status == SyncStatus.failed.rawValue {
            stats.failedSyncs += 1
        }

        stats.totalFilesProcessed += history.totalFiles
        stats.totalBytesTransferred += history.bytesTransferred

        if let duration = history.duration, stats.totalSyncs > 0 {
            let totalDuration = stats.averageDuration * Double(stats.totalSyncs - 1) + duration
            stats.averageDuration = totalDuration / Double(stats.totalSyncs)
        }

        syncStatistics[key] = stats
        scheduleSave("syncStatistics")
    }

    func getStatistics(syncPairId: String, days: Int = 30) -> [ServiceSyncStatistics] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        return syncStatistics.values
            .filter { $0.syncPairId == syncPairId && $0.date >= cutoffDate }
            .sorted { $0.date < $1.date }
    }

    func getTodayStatistics(syncPairId: String) -> ServiceSyncStatistics? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let key = "\(syncPairId)_\(dateFormatter.string(from: Date()))"
        return syncStatistics[key]
    }

    // MARK: - 索引统计

    func getIndexStats(syncPairId: String) -> IndexStats {
        let entries = fileEntries[syncPairId]?.values ?? []

        var stats = IndexStats(
            totalFiles: 0,
            totalDirectories: 0,
            totalSize: 0,
            localOnlyCount: 0,
            externalOnlyCount: 0,
            bothCount: 0,
            dirtyCount: 0,
            lastUpdated: Date()
        )

        for entry in entries {
            if entry.isDirectory {
                stats.totalDirectories += 1
            } else {
                stats.totalFiles += 1
                stats.totalSize += entry.size
            }

            switch FileLocation(rawValue: entry.location) {
            case .localOnly: stats.localOnlyCount += 1
            case .externalOnly: stats.externalOnlyCount += 1
            case .both: stats.bothCount += 1
            default: break
            }

            if entry.isDirty {
                stats.dirtyCount += 1
            }
        }

        return stats
    }

    // MARK: - 批量写入优化

    private func scheduleSave(_ type: String) {
        pendingWrites.insert(type)

        writeTask?.cancel()
        writeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(writeDebounce * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await flushWrites()
        }
    }

    private func flushWrites() async {
        let pending = pendingWrites
        pendingWrites.removeAll()

        for type in pending {
            switch type {
            case "fileEntries":
                await saveFileEntriesToDisk()
            case "syncHistory":
                await saveSyncHistoryToDisk()
            case "syncStatistics":
                await saveSyncStatisticsToDisk()
            default:
                break
            }
        }
    }

    private func saveFileEntriesToDisk() async {
        var allEntries: [ServiceFileEntry] = []
        for entries in fileEntries.values {
            allEntries.append(contentsOf: entries.values)
        }

        do {
            let data = try JSONEncoder().encode(allEntries)
            try data.write(to: fileEntriesURL, options: .atomic)
            logger.debug("保存 \(allEntries.count) 个文件索引")
        } catch {
            logger.error("保存文件索引失败: \(error)")
        }
    }

    private func saveSyncHistoryToDisk() async {
        var allHistory: [ServiceSyncHistory] = []
        for histories in syncHistory.values {
            allHistory.append(contentsOf: histories)
        }

        do {
            let data = try JSONEncoder().encode(allHistory)
            try data.write(to: syncHistoryURL, options: .atomic)
            logger.debug("保存 \(allHistory.count) 条同步历史")
        } catch {
            logger.error("保存同步历史失败: \(error)")
        }
    }

    private func saveSyncStatisticsToDisk() async {
        let allStats = Array(syncStatistics.values)

        do {
            let data = try JSONEncoder().encode(allStats)
            try data.write(to: syncStatisticsURL, options: .atomic)
            logger.debug("保存 \(allStats.count) 条统计数据")
        } catch {
            logger.error("保存统计数据失败: \(error)")
        }
    }

    // MARK: - 强制保存

    func forceSave() async {
        pendingWrites = ["fileEntries", "syncHistory", "syncStatistics"]
        await flushWrites()
    }

    // MARK: - 清理

    func clearAllData() async {
        fileEntries.removeAll()
        syncHistory.removeAll()
        syncStatistics.removeAll()

        try? fileManager.removeItem(at: fileEntriesURL)
        try? fileManager.removeItem(at: syncHistoryURL)
        try? fileManager.removeItem(at: syncStatisticsURL)

        logger.info("所有服务数据已清除")
    }

    // MARK: - 健康检查

    func healthCheck() -> Bool {
        return fileManager.fileExists(atPath: dataDirectory.path)
    }
}
