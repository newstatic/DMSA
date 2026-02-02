import Foundation
import Combine

/// Configuration manager
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

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        configURL = appSupport.appendingPathComponent("config.json")
        backupURL = appSupport.appendingPathComponent("config.backup.json")

        _config = AppConfig()
        loadConfig()
    }

    private func loadConfig() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            Logger.shared.info("Config file not found, using defaults")
            saveConfig() // Create default config
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            _config = try decoder.decode(AppConfig.self, from: data)
            Logger.shared.info("Config loaded successfully")

            // Backup config
            try? data.write(to: backupURL)
        } catch {
            Logger.shared.error("Failed to load config: \(error.localizedDescription)")
            loadBackupConfig()
        }
    }

    private func loadBackupConfig() {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            Logger.shared.warn("Backup config not found, using defaults")
            return
        }

        do {
            let data = try Data(contentsOf: backupURL)
            _config = try JSONDecoder().decode(AppConfig.self, from: data)
            Logger.shared.info("Config restored from backup")
        } catch {
            Logger.shared.error("Backup config also corrupted: \(error.localizedDescription)")
        }
    }

    func saveConfig() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(_config)
            try data.write(to: configURL)
            Logger.shared.debug("Config saved successfully")
        } catch {
            Logger.shared.error("Failed to save config: \(error.localizedDescription)")
        }
    }

    // MARK: - Convenience Methods

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

    // MARK: - Config Modification Methods

    func addDisk(_ disk: DiskConfig) {
        var newConfig = _config
        newConfig.disks.append(disk)
        config = newConfig
    }

    func removeDisk(id: String) {
        var newConfig = _config
        newConfig.disks.removeAll { $0.id == id }
        // Also remove related syncPairs
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

    // MARK: - Config Reset

    func resetToDefaults() {
        _config = AppConfig()
        saveConfig()
        Logger.shared.info("Config reset to defaults")
    }
}
