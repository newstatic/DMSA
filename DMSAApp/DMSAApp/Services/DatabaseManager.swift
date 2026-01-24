import Foundation

/// App 端数据管理器
/// ⚠️ 架构说明 (v4.3):
/// - App 不再持久化数据，所有数据来源于 DMSAService
/// - 通过 ServiceClient XPC 调用获取数据
/// - 仅保留内存缓存用于 UI 显示优化
///
/// 数据流向:
/// DMSAService (持久化) → XPC → App (内存缓存) → UI
final class DatabaseManager {
    static let shared = DatabaseManager()

    private let logger = Logger.shared

    // 内存缓存 (用于 UI 显示优化，非持久化)
    private var cachedFileEntries: [String: FileEntry] = [:]
    private var cachedSyncHistory: [SyncHistory] = []
    private var cachedNotifications: [NotificationRecord] = []

    private let queue = DispatchQueue(label: "com.ttttt.dmsa.database.cache")

    private init() {
        logger.info("DatabaseManager 初始化 (仅内存缓存模式)")
    }

    // MARK: - FileEntry 缓存 (UI 显示用)

    /// 缓存文件条目 (从服务获取后缓存)
    func cacheFileEntry(_ entry: FileEntry) {
        queue.async { [weak self] in
            self?.cachedFileEntries[entry.virtualPath] = entry
        }
    }

    /// 批量缓存文件条目
    func cacheFileEntries(_ entries: [FileEntry]) {
        queue.async { [weak self] in
            for entry in entries {
                self?.cachedFileEntries[entry.virtualPath] = entry
            }
        }
    }

    /// 获取缓存的文件条目
    func getCachedFileEntry(virtualPath: String) -> FileEntry? {
        return queue.sync { cachedFileEntries[virtualPath] }
    }

    /// 获取所有缓存的文件条目
    func getAllCachedFileEntries() -> [FileEntry] {
        return queue.sync { Array(cachedFileEntries.values) }
    }

    /// 清除文件缓存
    func clearFileEntryCache() {
        queue.async { [weak self] in
            self?.cachedFileEntries.removeAll()
        }
    }

    // MARK: - SyncHistory 缓存

    /// 缓存同步历史 (从服务获取后缓存)
    func cacheSyncHistory(_ history: [SyncHistory]) {
        queue.async { [weak self] in
            self?.cachedSyncHistory = history
        }
    }

    /// 获取缓存的同步历史
    func getCachedSyncHistory(limit: Int = 100) -> [SyncHistory] {
        return queue.sync {
            Array(cachedSyncHistory.prefix(limit))
        }
    }

    /// 清除同步历史缓存
    func clearSyncHistoryCache() {
        queue.async { [weak self] in
            self?.cachedSyncHistory.removeAll()
        }
    }

    // MARK: - NotificationRecord 本地管理
    // 通知记录保留在 App 端，因为这是 UI 相关的本地数据

    private var notificationRecordsURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DMSA/Data")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notifications.json")
    }

    /// 加载通知记录
    func loadNotifications() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let data = try? Data(contentsOf: self.notificationRecordsURL),
                  let records = try? JSONDecoder().decode([NotificationRecord].self, from: data) else {
                return
            }
            self.cachedNotifications = records
        }
    }

    /// 保存通知记录
    private func saveNotifications() {
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(self.cachedNotifications)
                try data.write(to: self.notificationRecordsURL, options: .atomic)
            } catch {
                self.logger.error("保存通知记录失败: \(error)")
            }
        }
    }

    /// 添加通知记录
    func saveNotificationRecord(_ record: NotificationRecord) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.cachedNotifications.insert(record, at: 0)

            // 限制最多保存 500 条
            if self.cachedNotifications.count > 500 {
                self.cachedNotifications = Array(self.cachedNotifications.prefix(500))
            }

            self.saveNotifications()
        }
    }

    /// 获取通知记录
    func getNotificationRecords(limit: Int = 100) -> [NotificationRecord] {
        return queue.sync {
            Array(cachedNotifications.prefix(limit))
        }
    }

    /// 获取所有通知记录
    func getAllNotificationRecords() -> [NotificationRecord] {
        return queue.sync { cachedNotifications }
    }

    /// 获取未读通知
    func getUnreadNotificationRecords() -> [NotificationRecord] {
        return queue.sync {
            cachedNotifications.filter { !$0.isRead }
        }
    }

    /// 获取未读数量
    func getUnreadCount() -> Int {
        return queue.sync {
            cachedNotifications.filter { !$0.isRead }.count
        }
    }

    /// 标记通知为已读
    func markNotificationAsRead(_ id: UInt64) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if let index = self.cachedNotifications.firstIndex(where: { $0.id == id }) {
                self.cachedNotifications[index].isRead = true
                self.saveNotifications()
            }
        }
    }

    /// 标记所有通知为已读
    func markAllNotificationsAsRead() {
        queue.async { [weak self] in
            guard let self = self else { return }
            for i in 0..<self.cachedNotifications.count {
                self.cachedNotifications[i].isRead = true
            }
            self.saveNotifications()
        }
    }

    /// 清除旧通知
    func clearNotificationRecords(olderThan date: Date) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.cachedNotifications.removeAll { $0.createdAt < date }
            self.saveNotifications()
        }
    }

    /// 清除所有通知
    func clearAllNotificationRecords() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.cachedNotifications.removeAll()
            self.saveNotifications()
        }
    }

    // MARK: - 已弃用方法 (兼容旧代码)

    @available(*, deprecated, message: "Use ServiceClient to get data from service")
    func getFileEntry(virtualPath: String) -> FileEntry? {
        return getCachedFileEntry(virtualPath: virtualPath)
    }

    @available(*, deprecated, message: "Use ServiceClient to save data to service")
    func saveFileEntry(_ entry: FileEntry) {
        cacheFileEntry(entry)
    }

    @available(*, deprecated, message: "Use ServiceClient to get data from service")
    func getAllFileEntries() -> [FileEntry] {
        return getAllCachedFileEntries()
    }

    @available(*, deprecated, message: "Use ServiceClient.getSyncHistory()")
    func getSyncHistory(limit: Int = 100) -> [SyncHistory] {
        return getCachedSyncHistory(limit: limit)
    }

    @available(*, deprecated, message: "Use ServiceClient.getSyncHistory()")
    func getAllSyncHistory() -> [SyncHistory] {
        return queue.sync { cachedSyncHistory }
    }

    @available(*, deprecated, message: "Use cacheFileEntries() instead")
    func updateFileLocation(virtualPath: String, location: FileLocation, localPath: String? = nil, externalPath: String? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if var entry = self.cachedFileEntries[virtualPath] {
                entry.location = location
                if let local = localPath { entry.localPath = local }
                if let external = externalPath { entry.externalPath = external }
                entry.modifiedAt = Date()
                self.cachedFileEntries[virtualPath] = entry
            }
        }
    }

    @available(*, deprecated, message: "Data managed by service")
    func markClean(_ virtualPath: String) {
        // No-op: 服务端管理脏标记
    }

    @available(*, deprecated, message: "Data managed by service")
    func updateAccessTime(_ virtualPath: String) {
        // No-op: 服务端管理访问时间
    }

    @available(*, deprecated, message: "Data managed by service")
    func getDirtyFiles() -> [FileEntry] {
        return []
    }

    @available(*, deprecated, message: "Data managed by service")
    func getEvictableFiles() -> [FileEntry] {
        return []
    }

    @available(*, deprecated, message: "Data managed by service")
    func getLockedFiles() -> [FileEntry] {
        return []
    }

    @available(*, deprecated, message: "Data managed by service")
    func saveSyncHistory(_ history: SyncHistory) {
        // No-op: 服务端管理同步历史
    }

    @available(*, deprecated, message: "Data managed by service")
    func clearSyncHistory(olderThan date: Date) {
        // No-op: 服务端管理同步历史
    }

    @available(*, deprecated, message: "Data managed by service")
    func clearAllSyncHistory() {
        // No-op: 服务端管理同步历史
    }

    @available(*, deprecated, message: "Data managed by service")
    func getStatistics(forDiskId diskId: String, days: Int = 30) -> [SyncStatistics] {
        return []
    }

    @available(*, deprecated, message: "Data managed by service")
    func getTodayStatistics(forDiskId diskId: String) -> SyncStatistics? {
        return nil
    }

    // MARK: - 清理

    func clearAllCaches() {
        queue.async { [weak self] in
            self?.cachedFileEntries.removeAll()
            self?.cachedSyncHistory.removeAll()
            self?.logger.info("所有缓存已清除")
        }
    }

    func clearAllData() {
        clearAllCaches()
        clearAllNotificationRecords()
        logger.info("所有本地数据已清除")
    }
}
