import Foundation
import Combine

/// 配置管理器
final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    private let configURL: URL
    private let backupURL: URL
    @Published private var _config: AppConfig

    var config: AppConfig {
        get { _config }
        set {
            _config = newValue
            saveConfig()
        }
    }

    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DMSA")

        // 确保目录存在
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        configURL = appSupport.appendingPathComponent("config.json")
        backupURL = appSupport.appendingPathComponent("config.backup.json")

        _config = AppConfig()
        loadConfig()
    }

    private func loadConfig() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            Logger.shared.info("配置文件不存在，使用默认配置")
            saveConfig() // 创建默认配置
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            _config = try decoder.decode(AppConfig.self, from: data)
            Logger.shared.info("配置加载成功")

            // 备份配置
            try? data.write(to: backupURL)
        } catch {
            Logger.shared.error("配置加载失败: \(error.localizedDescription)")
            loadBackupConfig()
        }
    }

    private func loadBackupConfig() {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            Logger.shared.warn("备份配置不存在，使用默认配置")
            return
        }

        do {
            let data = try Data(contentsOf: backupURL)
            _config = try JSONDecoder().decode(AppConfig.self, from: data)
            Logger.shared.info("从备份恢复配置成功")
        } catch {
            Logger.shared.error("备份配置也损坏: \(error.localizedDescription)")
        }
    }

    func saveConfig() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(_config)
            try data.write(to: configURL)
            Logger.shared.debug("配置保存成功")
        } catch {
            Logger.shared.error("配置保存失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 便捷方法

    func getDisk(byId id: String) -> DiskConfig? {
        return config.disks.first { $0.id == id }
    }

    func getConnectedDisks() -> [DiskConfig] {
        return config.disks.filter { $0.enabled && $0.isConnected }
    }

    func getSyncPairs(forDiskId diskId: String) -> [SyncPairConfig] {
        return config.syncPairs.filter { $0.diskId == diskId && $0.enabled }
    }

    func getHighestPriorityConnectedDisk() -> DiskConfig? {
        return getConnectedDisks().sorted { $0.priority < $1.priority }.first
    }

    // MARK: - 配置修改方法

    func addDisk(_ disk: DiskConfig) {
        var newConfig = _config
        newConfig.disks.append(disk)
        config = newConfig
    }

    func removeDisk(id: String) {
        var newConfig = _config
        newConfig.disks.removeAll { $0.id == id }
        // 同时移除相关的 syncPairs
        newConfig.syncPairs.removeAll { $0.diskId == id }
        config = newConfig
    }

    func addSyncPair(_ pair: SyncPairConfig) {
        var newConfig = _config
        newConfig.syncPairs.append(pair)
        config = newConfig
    }

    func removeSyncPair(id: String) {
        var newConfig = _config
        newConfig.syncPairs.removeAll { $0.id == id }
        config = newConfig
    }

    func updateGeneralConfig(_ general: GeneralConfig) {
        var newConfig = _config
        newConfig.general = general
        config = newConfig
    }

    func updateFilterConfig(_ filters: FilterConfig) {
        var newConfig = _config
        newConfig.filters = filters
        config = newConfig
    }

    func updateCacheConfig(_ cache: CacheConfig) {
        var newConfig = _config
        newConfig.cache = cache
        config = newConfig
    }

    func updateNotificationConfig(_ notifications: NotificationConfig) {
        var newConfig = _config
        newConfig.notifications = notifications
        config = newConfig
    }

    // MARK: - 配置重置

    func resetToDefaults() {
        _config = AppConfig()
        saveConfig()
        Logger.shared.info("配置已重置为默认值")
    }
}
