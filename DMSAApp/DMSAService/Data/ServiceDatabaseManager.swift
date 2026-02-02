import Foundation
import ObjectBox

// MARK: - Service Database Manager
// Uses ObjectBox for high-volume data storage (FileEntry, SyncHistory, SyncStatistics)
// Data directory: /Library/Application Support/DMSA/ServiceData/

// MARK: - ObjectBox Entity Definitions

// objectbox: entity
/// File index entity - stores file location and state in LOCAL/EXTERNAL
class ServiceFileEntry: Entity, Identifiable, Codable {
    var id: Id = 0

    /// Virtual path (path in VFS)
    // objectbox: index
    var virtualPath: String = ""

    /// Local path (actual path in Downloads_Local)
    var localPath: String?

    /// External path (actual path on external drive)
    var externalPath: String?

    /// File location (FileLocation.rawValue)
    var location: Int = 0

    /// File size (bytes)
    var size: Int64 = 0

    /// Creation time
    var createdAt: Date = Date()

    /// Modification time
    var modifiedAt: Date = Date()

    /// Access time (used for LRU eviction)
    var accessedAt: Date = Date()

    /// File checksum
    var checksum: String?

    /// Whether file has dirty data
    var isDirty: Bool = false

    /// Whether entry is a directory
    var isDirectory: Bool = false

    /// Associated sync pair ID
    // objectbox: index
    var syncPairId: String = ""

    /// Lock state
    var lockState: Int = 0

    /// Lock time
    var lockTime: Date?

    /// Lock direction
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

    // MARK: - Convenience Properties

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
/// Sync history entity
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

    // MARK: - Codable
    // App-side SyncHistory (class) CodingKeys:
    //   startedAt -> "startTime", completedAt -> "endTime",
    //   filesCount -> "totalFiles", totalSize -> "bytesTransferred"
    // So Service encodes with keys: startTime, endTime, totalFiles, bytesTransferred
    // These match ServiceSyncHistory property names, so no remapping needed

    enum CodingKeys: String, CodingKey {
        case id
        case syncPairId
        case diskId
        case startTime
        case endTime
        case status
        case direction
        case totalFiles
        case filesUpdated
        case filesDeleted
        case filesSkipped
        case bytesTransferred
        case errorMessage
    }
}

// objectbox: entity
/// Sync statistics entity (aggregated by day)
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

// objectbox: entity
/// Sync file record entity - records each synced file individually
class ServiceSyncFileRecord: Entity, Identifiable, Codable {
    var id: Id = 0

    // objectbox: index
    var syncPairId: String = ""

    // objectbox: index
    var diskId: String = ""

    /// File virtual path
    // objectbox: index
    var virtualPath: String = ""

    /// File size (bytes)
    var fileSize: Int64 = 0

    /// Sync time
    // objectbox: index
    var syncedAt: Date = Date()

    /// Operation status: 0=sync success, 1=sync failed, 2=skipped, 3=eviction success, 4=eviction failed
    var status: Int = 0

    /// Error message (on failure)
    var errorMessage: String?

    /// Parent sync task ID (references ServiceSyncHistory)
    var syncTaskId: UInt64 = 0

    required init() {}

    convenience init(syncPairId: String, diskId: String, virtualPath: String, fileSize: Int64) {
        self.init()
        self.syncPairId = syncPairId
        self.diskId = diskId
        self.virtualPath = virtualPath
        self.fileSize = fileSize
        self.syncedAt = Date()
    }

    // MARK: - Codable (maps to App-side SyncFileRecord field names)

    enum CodingKeys: String, CodingKey {
        case id
        case syncPairId
        case diskId
        case virtualPath
        case fileSize
        case syncedAt
        case status
        case errorMessage
        case syncTaskId
    }
}

// objectbox: entity
/// Activity record entity - persists recent activities (shown on Dashboard)
class ServiceActivityRecord: Entity, Identifiable, Codable {
    var id: Id = 0

    /// Activity type (ActivityType.rawValue)
    var type: Int = 0

    /// Title
    var title: String = ""

    /// Detail info
    var detail: String?

    /// Timestamp
    // objectbox: index
    var timestamp: Date = Date()

    /// Associated sync pair ID
    var syncPairId: String?

    /// Associated disk ID
    var diskId: String?

    /// File count
    var filesCount: Int?

    /// Byte count
    var bytesCount: Int64?

    required init() {}

    convenience init(from record: ActivityRecord) {
        self.init()
        self.type = record.type.rawValue
        self.title = record.title
        self.detail = record.detail
        self.timestamp = record.timestamp
        self.syncPairId = record.syncPairId
        self.diskId = record.diskId
        self.filesCount = record.filesCount
        self.bytesCount = record.bytesCount
    }

    /// Convert to shared ActivityRecord
    func toActivityRecord() -> ActivityRecord {
        var record = ActivityRecord(
            type: ActivityType(rawValue: type) ?? .error,
            title: title,
            detail: detail,
            syncPairId: syncPairId,
            diskId: diskId,
            filesCount: filesCount,
            bytesCount: bytesCount
        )
        // Restore original timestamp (ActivityRecord.init sets it to Date())
        record.timestamp = timestamp
        return record
    }
}

/// Index statistics
public struct IndexStats: Codable, Sendable {
    public var totalFiles: Int
    public var totalDirectories: Int
    public var totalSize: Int64
    public var localSize: Int64       // localOnly + both file size (actual LOCAL_DIR usage)
    public var localOnlyCount: Int
    public var externalOnlyCount: Int
    public var bothCount: Int
    public var dirtyCount: Int
    public var lastUpdated: Date

    public init(
        totalFiles: Int = 0,
        totalDirectories: Int = 0,
        totalSize: Int64 = 0,
        localSize: Int64 = 0,
        localOnlyCount: Int = 0,
        externalOnlyCount: Int = 0,
        bothCount: Int = 0,
        dirtyCount: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.totalFiles = totalFiles
        self.totalDirectories = totalDirectories
        self.totalSize = totalSize
        self.localSize = localSize
        self.localOnlyCount = localOnlyCount
        self.externalOnlyCount = externalOnlyCount
        self.bothCount = bothCount
        self.dirtyCount = dirtyCount
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Service Database Manager

/// DMSAService database manager
/// - Uses ObjectBox for high-performance storage
/// - Storage location: /Library/Application Support/DMSA/ServiceData/
actor ServiceDatabaseManager {

    static let shared = ServiceDatabaseManager()

    private let logger = Logger.forService("Database")
    private let fileManager = FileManager.default

    // Data directory
    private let dataDirectory: URL

    // ObjectBox Store
    private var store: Store?

    // ObjectBox Boxes
    private var fileEntryBox: Box<ServiceFileEntry>?
    private var syncHistoryBox: Box<ServiceSyncHistory>?
    private var syncStatisticsBox: Box<ServiceSyncStatistics>?
    private var syncFileRecordBox: Box<ServiceSyncFileRecord>?
    private var activityRecordBox: Box<ServiceActivityRecord>?

    // In-memory cache (for frequent access)
    private var fileEntryCache: [String: [String: ServiceFileEntry]] = [:]  // [syncPairId: [virtualPath: Entry]]
    private var cacheLoaded: Set<String> = []

    // Configuration
    private let maxHistoryPerPair = 500
    private let maxStatisticsDays = 90

    private init() {
        dataDirectory = Constants.Paths.appSupport.appendingPathComponent("ServiceData")

        Task {
            await initialize()
        }
    }

    // MARK: - Initialization

    private func initialize() async {
        // Ensure data directory exists
        do {
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            logger.info("Data directory: \(dataDirectory.path)")
        } catch {
            logger.error("Failed to create data directory: \(error)")
            return
        }

        // Initialize ObjectBox Store
        do {
            let storeDirectory = dataDirectory.appendingPathComponent("objectbox")
            try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

            store = try Store(directoryPath: storeDirectory.path)

            // Get Boxes
            fileEntryBox = store?.box(for: ServiceFileEntry.self)
            syncHistoryBox = store?.box(for: ServiceSyncHistory.self)
            syncStatisticsBox = store?.box(for: ServiceSyncStatistics.self)
            syncFileRecordBox = store?.box(for: ServiceSyncFileRecord.self)
            activityRecordBox = store?.box(for: ServiceActivityRecord.self)

            logger.info("ObjectBox Store initialized successfully")

            // Print statistics
            let fileCount = try fileEntryBox?.count() ?? 0
            let historyCount = try syncHistoryBox?.count() ?? 0
            let statsCount = try syncStatisticsBox?.count() ?? 0
            logger.info("Database stats: \(fileCount) file entries, \(historyCount) sync histories, \(statsCount) statistics records")

            // Check if migration from JSON is needed
            await migrateFromJSONIfNeeded()

        } catch {
            logger.error("ObjectBox initialization failed: \(error)")
        }

        logger.info("ServiceDatabaseManager initialized")
    }

    // MARK: - FileEntry Operations

    /// Load all files for a given syncPairId into cache
    private func loadCacheForSyncPair(_ syncPairId: String) {
        // Check if already loaded from memory cache
        if cacheLoaded.contains(syncPairId) {
            let cacheCount = fileEntryCache[syncPairId]?.count ?? 0
            logger.debug("Cache already loaded, skipping: \(syncPairId), cache entries: \(cacheCount)")
            return
        }

        do {
            let query = try fileEntryBox?.query { ServiceFileEntry.syncPairId.isEqual(to: syncPairId) }.build()
            let entries = try query?.find() ?? []

            fileEntryCache[syncPairId] = [:]
            for entry in entries {
                fileEntryCache[syncPairId]?[entry.virtualPath] = entry
            }

            cacheLoaded.insert(syncPairId)
            logger.info("Loaded cache from database: \(syncPairId), \(entries.count) entries")
        } catch {
            logger.error("Failed to load cache: \(error)")
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

            // Update cache
            if fileEntryCache[entry.syncPairId] == nil {
                fileEntryCache[entry.syncPairId] = [:]
            }
            fileEntryCache[entry.syncPairId]?[entry.virtualPath] = entry
        } catch {
            logger.error("Failed to save file entry: \(error)")
        }
    }

    /// Batch write file entries (one transaction per batchSize)
    func saveFileEntries(_ entries: [ServiceFileEntry], batchSize: Int = 10000) {
        guard !entries.isEmpty else { return }

        var savedCount = 0
        var failedCount = 0
        var failedBatches = 0

        let totalBatches = (entries.count + batchSize - 1) / batchSize

        for batchIndex in 0..<totalBatches {
            let start = batchIndex * batchSize
            let end = min(start + batchSize, entries.count)
            let batch = Array(entries[start..<end])

            do {
                try fileEntryBox?.put(batch)
                savedCount += batch.count

                // Update cache
                for entry in batch {
                    if fileEntryCache[entry.syncPairId] == nil {
                        fileEntryCache[entry.syncPairId] = [:]
                    }
                    fileEntryCache[entry.syncPairId]?[entry.virtualPath] = entry
                }
            } catch {
                failedCount += batch.count
                failedBatches += 1
                if failedBatches <= 3 {
                    logger.error("Batch write failed [\(batchIndex + 1)/\(totalBatches)]: \(batch.count) entries - \(error)")
                }
            }

            if (batchIndex + 1) % 5 == 0 || batchIndex == totalBatches - 1 {
                logger.info("Index write progress: \(savedCount)/\(entries.count) (\(batchIndex + 1)/\(totalBatches) batches)")
            }
        }

        logger.info("Save file entries complete: total=\(entries.count), succeeded=\(savedCount), failed=\(failedCount), failedBatches=\(failedBatches)")
    }

    func deleteFileEntry(virtualPath: String, syncPairId: String) {
        guard let entry = getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) else { return }

        do {
            try fileEntryBox?.remove(entry)
            fileEntryCache[syncPairId]?.removeValue(forKey: virtualPath)
        } catch {
            logger.error("Failed to delete file entry: \(error)")
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

        // Only update cache; will save to database during batch write
        fileEntryCache[syncPairId]?[virtualPath] = entry
    }

    func getDirtyFiles(syncPairId: String) -> [ServiceFileEntry] {
        loadCacheForSyncPair(syncPairId)
        return fileEntryCache[syncPairId]?.values.filter { $0.isDirty } ?? []
    }

    /// Get files that need syncing (dirty files + local-only files)
    func getFilesToSync(syncPairId: String) -> [ServiceFileEntry] {
        loadCacheForSyncPair(syncPairId)

        let allEntriesArray: [ServiceFileEntry] = fileEntryCache[syncPairId].map { Array($0.values) } ?? []

        // Detailed statistics
        var localOnlyCount = 0
        var externalOnlyCount = 0
        var bothCount = 0
        var dirtyCount = 0
        var needsSyncCount = 0
        var directoriesCount = 0

        for entry in allEntriesArray {
            if entry.isDirectory { directoriesCount += 1 }
            if entry.isDirty { dirtyCount += 1 }
            if entry.needsSync { needsSyncCount += 1 }

            switch entry.location {
            case FileLocation.localOnly.rawValue: localOnlyCount += 1
            case FileLocation.externalOnly.rawValue: externalOnlyCount += 1
            case FileLocation.both.rawValue: bothCount += 1
            default: break
            }
        }

        logger.info("getFilesToSync stats: syncPairId=\(syncPairId)")
        logger.info("  - total entries: \(allEntriesArray.count), directories: \(directoriesCount)")
        logger.info("  - localOnly: \(localOnlyCount), externalOnly: \(externalOnlyCount), both: \(bothCount)")
        logger.info("  - dirty: \(dirtyCount), needsSync: \(needsSyncCount)")

        let result = allEntriesArray.filter { $0.needsSync && !$0.isDirectory }
        logger.info("  - returning files to sync: \(result.count)")

        return result
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

    func removeFileEntry(_ entry: ServiceFileEntry) {
        do {
            try fileEntryBox?.remove(entry)
            fileEntryCache[entry.syncPairId]?.removeValue(forKey: entry.virtualPath)
        } catch {
            logger.error("Failed to delete file entry: \(error)")
        }
    }

    func removeFileEntries(_ entries: [ServiceFileEntry]) {
        guard !entries.isEmpty else { return }
        do {
            try fileEntryBox?.remove(entries)
            for entry in entries {
                fileEntryCache[entry.syncPairId]?.removeValue(forKey: entry.virtualPath)
            }
        } catch {
            logger.error("Failed to batch delete file entries: \(error)")
        }
    }

    func clearFileEntries(syncPairId: String) {
        do {
            // Record current cache state
            let cacheCount = fileEntryCache[syncPairId]?.count ?? 0
            let wasLoaded = cacheLoaded.contains(syncPairId)

            let query = try fileEntryBox?.query { ServiceFileEntry.syncPairId.isEqual(to: syncPairId) }.build()
            let entries = try query?.find() ?? []
            try fileEntryBox?.remove(entries)

            fileEntryCache.removeValue(forKey: syncPairId)
            cacheLoaded.remove(syncPairId)

            logger.info("========== Clear File Entries ==========")
            logger.info("  syncPairId: \(syncPairId)")
            logger.info("  database entries: \(entries.count)")
            logger.info("  cache entries: \(cacheCount)")
            logger.info("  cache was loaded: \(wasLoaded)")
            logger.info("  cacheLoaded after clear: \(cacheLoaded.contains(syncPairId))")
            logger.info("===================================")
        } catch {
            logger.error("Failed to clear file entries: \(error)")
        }
    }

    // MARK: - SyncHistory Operations

    func saveSyncHistory(_ history: ServiceSyncHistory) {
        do {
            try syncHistoryBox?.put(history)
            logger.debug("Saved sync history: \(history.syncPairId)")

            updateStatistics(from: history)
            cleanupOldHistory(syncPairId: history.syncPairId)
        } catch {
            logger.error("Failed to save sync history: \(error)")
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
            logger.error("Failed to query sync history: \(error)")
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
            logger.error("Failed to query all sync history: \(error)")
            return []
        }
    }

    func clearSyncHistory(syncPairId: String) {
        do {
            let query = try syncHistoryBox?.query { ServiceSyncHistory.syncPairId.isEqual(to: syncPairId) }.build()
            let histories = try query?.find() ?? []
            try syncHistoryBox?.remove(histories)
            logger.info("Cleared \(histories.count) sync history entries: \(syncPairId)")
        } catch {
            logger.error("Failed to clear sync history: \(error)")
        }
    }

    func clearOldHistory(olderThan date: Date) {
        do {
            let query = try syncHistoryBox?.query { ServiceSyncHistory.startTime < date }.build()
            let histories = try query?.find() ?? []
            try syncHistoryBox?.remove(histories)
            logger.info("Cleared \(histories.count) old sync history entries")
        } catch {
            logger.error("Failed to clear old sync history: \(error)")
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
                logger.debug("Cleaned up \(toRemove.count) old history records")
            }
        } catch {
            logger.error("Failed to clean up old history: \(error)")
        }
    }

    // MARK: - SyncFileRecord Operations

    /// Save a single file sync record
    func saveSyncFileRecord(_ record: ServiceSyncFileRecord) {
        do {
            try syncFileRecordBox?.put(record)
        } catch {
            logger.error("Failed to save file sync record: \(error)")
        }
    }

    /// Batch save file sync records
    func saveSyncFileRecords(_ records: [ServiceSyncFileRecord]) {
        guard !records.isEmpty else { return }
        do {
            try syncFileRecordBox?.put(records)
            logger.debug("Batch saved \(records.count) file sync records")
        } catch {
            logger.error("Failed to batch save file sync records: \(error)")
        }
    }

    /// Query file sync history (ordered by time descending)
    func getSyncFileRecords(syncPairId: String, limit: Int = 200) -> [ServiceSyncFileRecord] {
        do {
            let query = try syncFileRecordBox?.query {
                ServiceSyncFileRecord.syncPairId.isEqual(to: syncPairId)
            }
            .ordered(by: ServiceSyncFileRecord.syncedAt, flags: .descending)
            .build()

            return Array((try query?.find() ?? []).prefix(limit))
        } catch {
            logger.error("Failed to query file sync records: \(error)")
            return []
        }
    }

    /// Query all file sync history (ordered by time descending, with pagination)
    func getAllSyncFileRecords(limit: Int = 200, offset: Int = 0) -> [ServiceSyncFileRecord] {
        do {
            let query = try syncFileRecordBox?.query()
                .ordered(by: ServiceSyncFileRecord.syncedAt, flags: .descending)
                .build()

            let all = try query?.find() ?? []
            let start = min(offset, all.count)
            let end = min(start + limit, all.count)
            return Array(all[start..<end])
        } catch {
            logger.error("Failed to query all file sync records: \(error)")
            return []
        }
    }

    /// Clean up old file sync records (keep most recent N)
    func cleanupOldSyncFileRecords(syncPairId: String, keepCount: Int = 5000) {
        do {
            let query = try syncFileRecordBox?.query {
                ServiceSyncFileRecord.syncPairId.isEqual(to: syncPairId)
            }
            .ordered(by: ServiceSyncFileRecord.syncedAt, flags: .descending)
            .build()

            let all = try query?.find() ?? []
            if all.count > keepCount {
                let toRemove = Array(all.dropFirst(keepCount))
                try syncFileRecordBox?.remove(toRemove)
                logger.debug("Cleaned up \(toRemove.count) old file sync records")
            }
        } catch {
            logger.error("Failed to clean up old file sync records: \(error)")
        }
    }

    // MARK: - SyncStatistics Operations

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
            logger.error("Failed to update statistics: \(error)")
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
            logger.error("Failed to query statistics: \(error)")
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
            logger.error("Failed to query today's statistics: \(error)")
            return nil
        }
    }

    // MARK: - ActivityRecord Operations

    /// Save activity record (keep most recent maxCount)
    func saveActivityRecord(_ record: ActivityRecord, maxCount: Int = 20) {
        do {
            let entity = ServiceActivityRecord(from: record)
            try activityRecordBox?.put(entity)

            // Clean up records exceeding limit
            let query = try activityRecordBox?.query()
                .ordered(by: ServiceActivityRecord.timestamp, flags: .descending)
                .build()
            let all = try query?.find() ?? []
            if all.count > maxCount {
                let toRemove = Array(all.dropFirst(maxCount))
                try activityRecordBox?.remove(toRemove)
            }
        } catch {
            logger.error("Failed to save activity record: \(error)")
        }
    }

    /// Get recent activity records
    func getRecentActivities(limit: Int = 5) -> [ActivityRecord] {
        do {
            let query = try activityRecordBox?.query()
                .ordered(by: ServiceActivityRecord.timestamp, flags: .descending)
                .build()
            let entities = Array((try query?.find() ?? []).prefix(limit))
            return entities.map { $0.toActivityRecord() }
        } catch {
            logger.error("Failed to query activity records: \(error)")
            return []
        }
    }

    // MARK: - Index Statistics

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

            let location = FileLocation(rawValue: entry.location)
            switch location {
            case .localOnly: stats.localOnlyCount += 1
            case .externalOnly: stats.externalOnlyCount += 1
            case .both: stats.bothCount += 1
            default: break
            }

            // LOCAL actual usage = localOnly + both file sizes
            if !entry.isDirectory && (location == .localOnly || location == .both) {
                stats.localSize += entry.size
            }

            if entry.isDirty {
                stats.dirtyCount += 1
            }
        }

        stats.lastUpdated = Date()
        return stats
    }

    // MARK: - Force Save (flush cache to database)

    func forceSave() async {
        // Write cached changes to database
        for (_, entries) in fileEntryCache {
            saveFileEntries(Array(entries.values))
        }
        logger.info("Force save complete")
    }

    // MARK: - Cleanup

    func clearAllData() async {
        do {
            try fileEntryBox?.removeAll()
            try syncHistoryBox?.removeAll()
            try syncStatisticsBox?.removeAll()

            fileEntryCache.removeAll()
            cacheLoaded.removeAll()

            logger.info("All service data cleared")
        } catch {
            logger.error("Failed to clear data: \(error)")
        }
    }

    // MARK: - Health Check

    func healthCheck() -> Bool {
        return store != nil && fileEntryBox != nil
    }

    // MARK: - JSON Migration

    /// Migrate data from old JSON files to ObjectBox
    private func migrateFromJSONIfNeeded() async {
        let oldFileEntriesURL = dataDirectory.appendingPathComponent("file_entries.json")

        guard fileManager.fileExists(atPath: oldFileEntriesURL.path) else {
            return
        }

        logger.info("Found old JSON data files, starting migration...")

        // Migrate file entries
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

                // Backup and delete old file
                let backupURL = oldFileEntriesURL.deletingPathExtension().appendingPathExtension("json.bak")
                try? fileManager.moveItem(at: oldFileEntriesURL, to: backupURL)

                logger.info("Migrated \(newEntries.count) file entries to ObjectBox")
            } catch {
                logger.error("Failed to migrate file entries: \(error)")
            }
        }

        // Migrate sync history
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

                logger.info("Migrated \(newHistories.count) sync history entries to ObjectBox")
            } catch {
                logger.error("Failed to migrate sync history: \(error)")
            }
        }

        // Migrate statistics
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

                logger.info("Migrated \(newStats.count) statistics entries to ObjectBox")
            } catch {
                logger.error("Failed to migrate statistics: \(error)")
            }
        }

        logger.info("Data migration complete")
    }
}
