import Foundation
import ObjectBox

// MARK: - Service 数据库管理器
// 使用 ObjectBox 存储大量数据 (FileEntry, SyncHistory, SyncStatistics)
// 数据目录: /Library/Application Support/DMSA/ServiceData/

// MARK: - ObjectBox 实体定义

// objectbox: entity
/// 文件索引实体 - 存储文件在 LOCAL/EXTERNAL 的位置和状态
class ServiceFileEntry: Entity, Identifiable, Codable {
    var id: Id = 0

    /// 虚拟路径 (VFS 中的路径)
    // objectbox: index
    var virtualPath: String = ""

    /// 本地路径 (Downloads_Local 中的实际路径)
    var localPath: String?

    /// 外部路径 (外置硬盘中的实际路径)
    var externalPath: String?

    /// 文件位置 (FileLocation.rawValue)
    var location: Int = 0

    /// 文件大小 (字节)
    var size: Int64 = 0

    /// 创建时间
    var createdAt: Date = Date()

    /// 修改时间
    var modifiedAt: Date = Date()

    /// 访问时间 (用于 LRU 淘汰)
    var accessedAt: Date = Date()

    /// 文件校验和
    var checksum: String?

    /// 是否为脏数据
    var isDirty: Bool = false

    /// 是否为目录
    var isDirectory: Bool = false

    /// 关联的同步对 ID
    // objectbox: index
    var syncPairId: String = ""

    /// 锁定状态
    var lockState: Int = 0

    /// 锁定时间
    var lockTime: Date?

    /// 锁定方向
    var lockDirection: Int?

    required init() {}

    convenience init(virtualPath: String, syncPairId: String) {
        self.init()
        self.virtualPath = virtualPath
        self.syncPairId = syncPairId
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.accessedAt = Date()
    }

    // MARK: - 便捷属性

    var fileLocation: FileLocation {
        get { FileLocation(rawValue: location) ?? .notExists }
        set { location = newValue.rawValue }
    }

    var fileName: String {
        (virtualPath as NSString).lastPathComponent
    }

    var parentPath: String {
        (virtualPath as NSString).deletingLastPathComponent
    }

    var isLocked: Bool {
        lockState == LockState.syncLocked.rawValue
    }

    var needsSync: Bool {
        isDirty || location == FileLocation.localOnly.rawValue
    }
}

// objectbox: entity
/// 同步历史实体
class ServiceSyncHistory: Entity, Identifiable, Codable {
    var id: Id = 0

    // objectbox: index
    var syncPairId: String = ""
    var diskId: String = ""

    // objectbox: index
    var startTime: Date = Date()
    var endTime: Date?

    var status: Int = 0
    var direction: Int = 0
    var totalFiles: Int = 0
    var filesUpdated: Int = 0
    var filesDeleted: Int = 0
    var filesSkipped: Int = 0
    var bytesTransferred: Int64 = 0
    var errorMessage: String?

    required init() {}

    convenience init(syncPairId: String, diskId: String) {
        self.init()
        self.syncPairId = syncPairId
        self.diskId = diskId
        self.startTime = Date()
    }

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
}

// objectbox: entity
/// 同步统计实体 (按天聚合)
class ServiceSyncStatistics: Entity, Identifiable, Codable {
    var id: Id = 0

    // objectbox: index
    var date: Date = Date()

    // objectbox: index
    var syncPairId: String = ""
    var diskId: String = ""

    var totalSyncs: Int = 0
    var successfulSyncs: Int = 0
    var failedSyncs: Int = 0
    var totalFilesProcessed: Int = 0
    var totalBytesTransferred: Int64 = 0
    var averageDuration: Double = 0

    required init() {}

    convenience init(date: Date, syncPairId: String, diskId: String) {
        self.init()
        self.date = date
        self.syncPairId = syncPairId
        self.diskId = diskId
    }

    var successRate: Double {
        guard totalSyncs > 0 else { return 0 }
        return Double(successfulSyncs) / Double(totalSyncs) * 100
    }
}

/// 索引统计
public struct IndexStats: Codable, Sendable {
    public var totalFiles: Int
    public var totalDirectories: Int
    public var totalSize: Int64
    public var localOnlyCount: Int
    public var externalOnlyCount: Int
    public var bothCount: Int
    public var dirtyCount: Int
    public var lastUpdated: Date

    public init(
        totalFiles: Int = 0,
        totalDirectories: Int = 0,
        totalSize: Int64 = 0,
        localOnlyCount: Int = 0,
        externalOnlyCount: Int = 0,
        bothCount: Int = 0,
        dirtyCount: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.totalFiles = totalFiles
        self.totalDirectories = totalDirectories
        self.totalSize = totalSize
        self.localOnlyCount = localOnlyCount
        self.externalOnlyCount = externalOnlyCount
        self.bothCount = bothCount
        self.dirtyCount = dirtyCount
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Service 数据库管理器

/// DMSAService 专用数据库管理器
/// - 使用 ObjectBox 进行高性能存储
/// - 存储位置: /Library/Application Support/DMSA/ServiceData/
actor ServiceDatabaseManager {

    static let shared = ServiceDatabaseManager()

    private let logger = Logger.forService("Database")
    private let fileManager = FileManager.default

    // 数据目录
    private let dataDirectory: URL

    // ObjectBox Store
    private var store: Store?

    // ObjectBox Boxes
    private var fileEntryBox: Box<ServiceFileEntry>?
    private var syncHistoryBox: Box<ServiceSyncHistory>?
    private var syncStatisticsBox: Box<ServiceSyncStatistics>?

    // 内存缓存 (用于频繁访问)
    private var fileEntryCache: [String: [String: ServiceFileEntry]] = [:]  // [syncPairId: [virtualPath: Entry]]
    private var cacheLoaded: Set<String> = []

    // 配置
    private let maxHistoryPerPair = 500
    private let maxStatisticsDays = 90

    private init() {
        dataDirectory = URL(fileURLWithPath: "/Library/Application Support/DMSA/ServiceData")

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
            return
        }

        // 初始化 ObjectBox Store
        do {
            let storeDirectory = dataDirectory.appendingPathComponent("objectbox")
            try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

            store = try Store(directoryPath: storeDirectory.path)

            // 获取 Boxes
            fileEntryBox = store?.box(for: ServiceFileEntry.self)
            syncHistoryBox = store?.box(for: ServiceSyncHistory.self)
            syncStatisticsBox = store?.box(for: ServiceSyncStatistics.self)

            logger.info("ObjectBox Store 初始化成功")

            // 输出统计信息
            let fileCount = try fileEntryBox?.count() ?? 0
            let historyCount = try syncHistoryBox?.count() ?? 0
            let statsCount = try syncStatisticsBox?.count() ?? 0
            logger.info("数据库统计: \(fileCount) 文件索引, \(historyCount) 同步历史, \(statsCount) 统计记录")

            // 检查是否需要从 JSON 迁移
            await migrateFromJSONIfNeeded()

        } catch {
            logger.error("ObjectBox 初始化失败: \(error)")
        }

        logger.info("ServiceDatabaseManager 初始化完成")
    }

    // MARK: - FileEntry 操作

    /// 加载指定 syncPairId 的所有文件到缓存
    private func loadCacheForSyncPair(_ syncPairId: String) {
        guard !cacheLoaded.contains(syncPairId) else { return }

        do {
            let query = try fileEntryBox?.query { ServiceFileEntry.syncPairId.isEqual(to: syncPairId) }.build()
            let entries = try query?.find() ?? []

            fileEntryCache[syncPairId] = [:]
            for entry in entries {
                fileEntryCache[syncPairId]?[entry.virtualPath] = entry
            }

            cacheLoaded.insert(syncPairId)
            logger.debug("加载缓存: \(syncPairId), \(entries.count) 个文件")
        } catch {
            logger.error("加载缓存失败: \(error)")
        }
    }

    func getFileEntry(virtualPath: String, syncPairId: String) -> ServiceFileEntry? {
        loadCacheForSyncPair(syncPairId)
        return fileEntryCache[syncPairId]?[virtualPath]
    }

    func getAllFileEntries(syncPairId: String) -> [ServiceFileEntry] {
        loadCacheForSyncPair(syncPairId)
        return Array(fileEntryCache[syncPairId]?.values ?? [:].values)
    }

    func saveFileEntry(_ entry: ServiceFileEntry) {
        do {
            try fileEntryBox?.put(entry)

            // 更新缓存
            if fileEntryCache[entry.syncPairId] == nil {
                fileEntryCache[entry.syncPairId] = [:]
            }
            fileEntryCache[entry.syncPairId]?[entry.virtualPath] = entry
        } catch {
            logger.error("保存文件索引失败: \(error)")
        }
    }

    func saveFileEntries(_ entries: [ServiceFileEntry]) {
        guard !entries.isEmpty else { return }

        do {
            try fileEntryBox?.put(entries)

            // 更新缓存
            for entry in entries {
                if fileEntryCache[entry.syncPairId] == nil {
                    fileEntryCache[entry.syncPairId] = [:]
                }
                fileEntryCache[entry.syncPairId]?[entry.virtualPath] = entry
            }

            logger.debug("批量保存 \(entries.count) 个文件索引")
        } catch {
            logger.error("批量保存文件索引失败: \(error)")
        }
    }

    func deleteFileEntry(virtualPath: String, syncPairId: String) {
        guard let entry = getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) else { return }

        do {
            try fileEntryBox?.remove(entry)
            fileEntryCache[syncPairId]?.removeValue(forKey: virtualPath)
        } catch {
            logger.error("删除文件索引失败: \(error)")
        }
    }

    func updateFileLocation(virtualPath: String, syncPairId: String, location: FileLocation, localPath: String? = nil, externalPath: String? = nil) {
        guard let entry = getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) else { return }

        entry.location = location.rawValue
        if let local = localPath { entry.localPath = local }
        if let external = externalPath { entry.externalPath = external }
        entry.modifiedAt = Date()

        saveFileEntry(entry)
    }

    func markFileDirty(virtualPath: String, syncPairId: String, dirty: Bool = true) {
        guard let entry = getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) else { return }

        entry.isDirty = dirty
        entry.modifiedAt = Date()

        saveFileEntry(entry)
    }

    func updateAccessTime(virtualPath: String, syncPairId: String) {
        guard let entry = getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) else { return }

        entry.accessedAt = Date()

        // 只更新缓存，批量写入时再保存到数据库
        fileEntryCache[syncPairId]?[virtualPath] = entry
    }

    func getDirtyFiles(syncPairId: String) -> [ServiceFileEntry] {
        loadCacheForSyncPair(syncPairId)
        return fileEntryCache[syncPairId]?.values.filter { $0.isDirty } ?? []
    }

    /// 获取需要同步的文件（脏文件 + 仅本地存在的文件）
    func getFilesToSync(syncPairId: String) -> [ServiceFileEntry] {
        loadCacheForSyncPair(syncPairId)
        return fileEntryCache[syncPairId]?.values.filter { $0.needsSync && !$0.isDirectory } ?? []
    }

    func getEvictableFiles(syncPairId: String) -> [ServiceFileEntry] {
        loadCacheForSyncPair(syncPairId)
        return fileEntryCache[syncPairId]?.values.filter { entry in
            !entry.isDirty &&
            entry.location == FileLocation.both.rawValue &&
            entry.localPath != nil &&
            entry.lockState == LockState.unlocked.rawValue
        }.sorted { $0.accessedAt < $1.accessedAt } ?? []
    }

    func clearFileEntries(syncPairId: String) {
        do {
            let query = try fileEntryBox?.query { ServiceFileEntry.syncPairId.isEqual(to: syncPairId) }.build()
            let entries = try query?.find() ?? []
            try fileEntryBox?.remove(entries)

            fileEntryCache.removeValue(forKey: syncPairId)
            cacheLoaded.remove(syncPairId)

            logger.info("清除 \(entries.count) 个文件索引: \(syncPairId)")
        } catch {
            logger.error("清除文件索引失败: \(error)")
        }
    }

    // MARK: - SyncHistory 操作

    func saveSyncHistory(_ history: ServiceSyncHistory) {
        do {
            try syncHistoryBox?.put(history)
            logger.debug("保存同步历史: \(history.syncPairId)")

            updateStatistics(from: history)
            cleanupOldHistory(syncPairId: history.syncPairId)
        } catch {
            logger.error("保存同步历史失败: \(error)")
        }
    }

    func getSyncHistory(syncPairId: String, limit: Int = 50) -> [ServiceSyncHistory] {
        do {
            let query = try syncHistoryBox?.query {
                ServiceSyncHistory.syncPairId.isEqual(to: syncPairId)
            }
            .ordered(by: ServiceSyncHistory.startTime, flags: .descending)
            .build()

            return Array((try query?.find() ?? []).prefix(limit))
        } catch {
            logger.error("查询同步历史失败: \(error)")
            return []
        }
    }

    func getAllSyncHistory(limit: Int = 200) -> [ServiceSyncHistory] {
        do {
            let query = try syncHistoryBox?.query()
                .ordered(by: ServiceSyncHistory.startTime, flags: .descending)
                .build()

            return Array((try query?.find() ?? []).prefix(limit))
        } catch {
            logger.error("查询所有同步历史失败: \(error)")
            return []
        }
    }

    func clearSyncHistory(syncPairId: String) {
        do {
            let query = try syncHistoryBox?.query { ServiceSyncHistory.syncPairId.isEqual(to: syncPairId) }.build()
            let histories = try query?.find() ?? []
            try syncHistoryBox?.remove(histories)
            logger.info("清除 \(histories.count) 条同步历史: \(syncPairId)")
        } catch {
            logger.error("清除同步历史失败: \(error)")
        }
    }

    func clearOldHistory(olderThan date: Date) {
        do {
            let query = try syncHistoryBox?.query { ServiceSyncHistory.startTime < date }.build()
            let histories = try query?.find() ?? []
            try syncHistoryBox?.remove(histories)
            logger.info("清除 \(histories.count) 条旧同步历史")
        } catch {
            logger.error("清除旧同步历史失败: \(error)")
        }
    }

    private func cleanupOldHistory(syncPairId: String) {
        do {
            let query = try syncHistoryBox?.query { ServiceSyncHistory.syncPairId.isEqual(to: syncPairId) }
                .ordered(by: ServiceSyncHistory.startTime, flags: .descending)
                .build()

            let allHistory = try query?.find() ?? []

            if allHistory.count > maxHistoryPerPair {
                let toRemove = Array(allHistory.dropFirst(maxHistoryPerPair))
                try syncHistoryBox?.remove(toRemove)
                logger.debug("清理 \(toRemove.count) 条旧历史记录")
            }
        } catch {
            logger.error("清理旧历史失败: \(error)")
        }
    }

    // MARK: - SyncStatistics 操作

    private func updateStatistics(from history: ServiceSyncHistory) {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: history.startTime)
        guard let startDate = calendar.date(from: dateComponents) else { return }

        do {
            let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
            let query = try syncStatisticsBox?.query {
                ServiceSyncStatistics.syncPairId.isEqual(to: history.syncPairId) &&
                ServiceSyncStatistics.date.isBetween(startDate, and: endDate)
            }.build()

            var stats: ServiceSyncStatistics
            if let existing = try query?.findFirst() {
                stats = existing
            } else {
                stats = ServiceSyncStatistics(date: startDate, syncPairId: history.syncPairId, diskId: history.diskId)
            }

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

            try syncStatisticsBox?.put(stats)
        } catch {
            logger.error("更新统计失败: \(error)")
        }
    }

    func getStatistics(syncPairId: String, days: Int = 30) -> [ServiceSyncStatistics] {
        let cutoffDateValue = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        do {
            let query = try syncStatisticsBox?.query {
                ServiceSyncStatistics.syncPairId.isEqual(to: syncPairId) &&
                ServiceSyncStatistics.date.isAfter(cutoffDateValue)
            }
            .ordered(by: ServiceSyncStatistics.date)
            .build()

            return try query?.find() ?? []
        } catch {
            logger.error("查询统计失败: \(error)")
            return []
        }
    }

    func getTodayStatistics(syncPairId: String) -> ServiceSyncStatistics? {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        do {
            let query = try syncStatisticsBox?.query {
                ServiceSyncStatistics.syncPairId.isEqual(to: syncPairId) &&
                ServiceSyncStatistics.date.isAfter(todayStart)
            }.build()

            return try query?.findFirst()
        } catch {
            logger.error("查询今日统计失败: \(error)")
            return nil
        }
    }

    // MARK: - 索引统计

    func getIndexStats(syncPairId: String) -> IndexStats {
        loadCacheForSyncPair(syncPairId)
        let entries = fileEntryCache[syncPairId]?.values.map { $0 } ?? []

        var stats = IndexStats()

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

        stats.lastUpdated = Date()
        return stats
    }

    // MARK: - 强制保存 (刷新缓存到数据库)

    func forceSave() async {
        // 将缓存中的更改写入数据库
        for (_, entries) in fileEntryCache {
            saveFileEntries(Array(entries.values))
        }
        logger.info("强制保存完成")
    }

    // MARK: - 清理

    func clearAllData() async {
        do {
            try fileEntryBox?.removeAll()
            try syncHistoryBox?.removeAll()
            try syncStatisticsBox?.removeAll()

            fileEntryCache.removeAll()
            cacheLoaded.removeAll()

            logger.info("所有服务数据已清除")
        } catch {
            logger.error("清除数据失败: \(error)")
        }
    }

    // MARK: - 健康检查

    func healthCheck() -> Bool {
        return store != nil && fileEntryBox != nil
    }

    // MARK: - JSON 迁移

    /// 从旧的 JSON 文件迁移数据到 ObjectBox
    private func migrateFromJSONIfNeeded() async {
        let oldFileEntriesURL = dataDirectory.appendingPathComponent("file_entries.json")

        guard fileManager.fileExists(atPath: oldFileEntriesURL.path) else {
            return
        }

        logger.info("发现旧 JSON 数据文件，开始迁移...")

        // 迁移文件索引
        if let data = try? Data(contentsOf: oldFileEntriesURL) {
            do {
                struct LegacyEntry: Codable {
                    var id: UInt64
                    var virtualPath: String
                    var localPath: String?
                    var externalPath: String?
                    var location: Int
                    var size: Int64
                    var createdAt: Date
                    var modifiedAt: Date
                    var accessedAt: Date
                    var checksum: String?
                    var isDirty: Bool
                    var isDirectory: Bool
                    var syncPairId: String
                    var lockState: Int
                    var lockTime: Date?
                    var lockDirection: Int?
                }

                let legacyEntries = try JSONDecoder().decode([LegacyEntry].self, from: data)

                let newEntries = legacyEntries.map { legacy -> ServiceFileEntry in
                    let entry = ServiceFileEntry()
                    entry.virtualPath = legacy.virtualPath
                    entry.localPath = legacy.localPath
                    entry.externalPath = legacy.externalPath
                    entry.location = legacy.location
                    entry.size = legacy.size
                    entry.createdAt = legacy.createdAt
                    entry.modifiedAt = legacy.modifiedAt
                    entry.accessedAt = legacy.accessedAt
                    entry.checksum = legacy.checksum
                    entry.isDirty = legacy.isDirty
                    entry.isDirectory = legacy.isDirectory
                    entry.syncPairId = legacy.syncPairId
                    entry.lockState = legacy.lockState
                    entry.lockTime = legacy.lockTime
                    entry.lockDirection = legacy.lockDirection
                    return entry
                }

                try fileEntryBox?.put(newEntries)

                // 备份并删除旧文件
                let backupURL = oldFileEntriesURL.deletingPathExtension().appendingPathExtension("json.bak")
                try? fileManager.moveItem(at: oldFileEntriesURL, to: backupURL)

                logger.info("迁移 \(newEntries.count) 个文件索引到 ObjectBox")
            } catch {
                logger.error("迁移文件索引失败: \(error)")
            }
        }

        // 迁移同步历史
        let oldSyncHistoryURL = dataDirectory.appendingPathComponent("sync_history.json")
        if let data = try? Data(contentsOf: oldSyncHistoryURL) {
            do {
                struct LegacyHistory: Codable {
                    var id: UInt64
                    var syncPairId: String
                    var diskId: String
                    var startTime: Date
                    var endTime: Date?
                    var status: Int
                    var direction: Int
                    var totalFiles: Int
                    var filesUpdated: Int
                    var filesDeleted: Int
                    var filesSkipped: Int
                    var bytesTransferred: Int64
                    var errorMessage: String?
                }

                let legacyHistories = try JSONDecoder().decode([LegacyHistory].self, from: data)

                let newHistories = legacyHistories.map { legacy -> ServiceSyncHistory in
                    let history = ServiceSyncHistory()
                    history.syncPairId = legacy.syncPairId
                    history.diskId = legacy.diskId
                    history.startTime = legacy.startTime
                    history.endTime = legacy.endTime
                    history.status = legacy.status
                    history.direction = legacy.direction
                    history.totalFiles = legacy.totalFiles
                    history.filesUpdated = legacy.filesUpdated
                    history.filesDeleted = legacy.filesDeleted
                    history.filesSkipped = legacy.filesSkipped
                    history.bytesTransferred = legacy.bytesTransferred
                    history.errorMessage = legacy.errorMessage
                    return history
                }

                try syncHistoryBox?.put(newHistories)

                let backupURL = oldSyncHistoryURL.deletingPathExtension().appendingPathExtension("json.bak")
                try? fileManager.moveItem(at: oldSyncHistoryURL, to: backupURL)

                logger.info("迁移 \(newHistories.count) 条同步历史到 ObjectBox")
            } catch {
                logger.error("迁移同步历史失败: \(error)")
            }
        }

        // 迁移统计数据
        let oldStatsURL = dataDirectory.appendingPathComponent("sync_statistics.json")
        if let data = try? Data(contentsOf: oldStatsURL) {
            do {
                struct LegacyStats: Codable {
                    var id: UInt64
                    var date: Date
                    var syncPairId: String
                    var diskId: String
                    var totalSyncs: Int
                    var successfulSyncs: Int
                    var failedSyncs: Int
                    var totalFilesProcessed: Int
                    var totalBytesTransferred: Int64
                    var averageDuration: Double
                }

                let legacyStats = try JSONDecoder().decode([LegacyStats].self, from: data)

                let newStats = legacyStats.map { legacy -> ServiceSyncStatistics in
                    let stats = ServiceSyncStatistics()
                    stats.date = legacy.date
                    stats.syncPairId = legacy.syncPairId
                    stats.diskId = legacy.diskId
                    stats.totalSyncs = legacy.totalSyncs
                    stats.successfulSyncs = legacy.successfulSyncs
                    stats.failedSyncs = legacy.failedSyncs
                    stats.totalFilesProcessed = legacy.totalFilesProcessed
                    stats.totalBytesTransferred = legacy.totalBytesTransferred
                    stats.averageDuration = legacy.averageDuration
                    return stats
                }

                try syncStatisticsBox?.put(newStats)

                let backupURL = oldStatsURL.deletingPathExtension().appendingPathExtension("json.bak")
                try? fileManager.moveItem(at: oldStatsURL, to: backupURL)

                logger.info("迁移 \(newStats.count) 条统计数据到 ObjectBox")
            } catch {
                logger.error("迁移统计数据失败: \(error)")
            }
        }

        logger.info("数据迁移完成")
    }
}
