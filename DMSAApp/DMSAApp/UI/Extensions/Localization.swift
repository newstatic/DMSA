import Foundation
import SwiftUI

// MARK: - Localization Manager

/// Observable localization manager for dynamic language switching
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: String {
        didSet {
            updateBundle()
            // Post notification for non-SwiftUI code (like NSMenu)
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }

    private(set) var bundle: Bundle

    private init() {
        let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        self.currentLanguage = savedLanguage
        self.bundle = Self.getBundle(for: savedLanguage)
    }

    func setLanguage(_ language: String) {
        UserDefaults.standard.set(language, forKey: "appLanguage")
        currentLanguage = language
    }

    private func updateBundle() {
        bundle = Self.getBundle(for: currentLanguage)
    }

    private static func getBundle(for language: String) -> Bundle {
        // For Xcode projects, use Bundle.main instead of Bundle.module
        let resourceBundle = Bundle.main

        if language == "system" {
            // Use system language
            return resourceBundle
        }

        // Try to find specific language bundle
        if let path = resourceBundle.path(forResource: language, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            return languageBundle
        }

        // Fallback to resource bundle
        return resourceBundle
    }

    /// Localize a key
    func localize(_ key: String) -> String {
        let result = NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: "", comment: "")
        return result.isEmpty ? key : result
    }

    /// Localize a key with format arguments
    func localize(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localize(key)
        return String(format: format, arguments: arguments)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}

// MARK: - Localization Helper

/// Localization namespace for type-safe string access
/// All properties are computed to support dynamic language switching
enum L10n {

    // MARK: - Common
    enum Common {
        static var ok: String { "common.ok".localized }
        static var cancel: String { "common.cancel".localized }
        static var done: String { "common.done".localized }
        static var save: String { "common.save".localized }
        static var delete: String { "common.delete".localized }
        static var edit: String { "common.edit".localized }
        static var add: String { "common.add".localized }
        static var remove: String { "common.remove".localized }
        static var close: String { "common.close".localized }
        static var back: String { "common.back".localized }
        static var next: String { "common.next".localized }
        static var previous: String { "common.previous".localized }
        static var apply: String { "common.apply".localized }
        static var reset: String { "common.reset".localized }
        static var browse: String { "common.browse".localized }
        static var select: String { "common.select".localized }
        static var enabled: String { "common.enabled".localized }
        static var disabled: String { "common.disabled".localized }
        static var connected: String { "common.connected".localized }
        static var disconnected: String { "common.disconnected".localized }
        static var unknown: String { "common.unknown".localized }
        static var never: String { "common.never".localized }
        static var loading: String { "common.loading".localized }
        static var error: String { "common.error".localized }
        static var warning: String { "common.warning".localized }
        static var success: String { "common.success".localized }
        static var retry: String { "common.retry".localized }
        static var ignore: String { "common.ignore".localized }
        static var copy: String { "common.copy".localized }
        static var export: String { "common.export".localized }
        static var `import`: String { "common.import".localized }
    }

    // MARK: - App
    enum App {
        static var name: String { "app.name".localized }
        static var fullName: String { "app.fullName".localized }
        static func version(_ v: String) -> String {
            String(format: "app.version".localized, v)
        }
    }

    // MARK: - Menu
    enum Menu {
        static var title: String { "menu.title".localized }
        static var syncNow: String { "menu.syncNow".localized }
        static var openDownloads: String { "menu.openDownloads".localized }
        static var viewLogs: String { "menu.viewLogs".localized }
        static var syncHistory: String { "menu.syncHistory".localized }
        static var settings: String { "menu.settings".localized }
        static var about: String { "menu.about".localized }
        static var quit: String { "menu.quit".localized }
        static func lastSync(_ time: String) -> String {
            String(format: "menu.lastSync".localized, time)
        }
        static func lastSyncAgo(_ time: String) -> String {
            String(format: "menu.lastSync.ago".localized, time)
        }
        static var noDisksConfigured: String { "menu.noDisksConfigured".localized }
        static var noDiskConnected: String { "menu.noDiskConnected".localized }
    }

    // MARK: - Disk
    enum Disk {
        static var connected: String { "disk.status.connected".localized }
        static var disconnected: String { "disk.status.disconnected".localized }
        static var ejecting: String { "disk.status.ejecting".localized }
        static var mounting: String { "disk.status.mounting".localized }
        static func capacity(used: String, total: String, percent: Int) -> String {
            String(format: "disk.capacity".localized, used, total, percent)
        }
        static func format(_ fs: String) -> String {
            String(format: "disk.format".localized, fs)
        }
        static func priority(_ p: Int) -> String {
            String(format: "disk.priority".localized, p)
        }
        static var testConnection: String { "disk.testConnection".localized }
        static var eject: String { "disk.eject".localized }
        static var notFound: String { "disk.notFound".localized }
    }

    // MARK: - Sync
    enum Sync {
        static var idle: String { "sync.status.idle".localized }
        static var syncing: String { "sync.status.syncing".localized }
        static var pending: String { "sync.status.pending".localized }
        static var completed: String { "sync.status.completed".localized }
        static var failed: String { "sync.status.failed".localized }
        static var cancelled: String { "sync.status.cancelled".localized }
        static func progress(current: Int, total: Int) -> String {
            String(format: "sync.progress".localized, current, total)
        }
        static func progressBytes(current: String, total: String) -> String {
            String(format: "sync.progress.bytes".localized, current, total)
        }
        static func speed(_ s: String) -> String {
            String(format: "sync.speed".localized, s)
        }
        static func timeRemaining(_ t: String) -> String {
            String(format: "sync.timeRemaining".localized, t)
        }
        static func currentFile(_ f: String) -> String {
            String(format: "sync.currentFile".localized, f)
        }
        static var localToExternal: String { "sync.direction.localToExternal".localized }
        static var externalToLocal: String { "sync.direction.externalToLocal".localized }
        static var bidirectional: String { "sync.direction.bidirectional".localized }
    }

    // MARK: - Settings
    enum Settings {
        static var title: String { "settings.title".localized }
        static var general: String { "settings.general".localized }
        static var disks: String { "settings.disks".localized }
        static var syncPairs: String { "settings.syncPairs".localized }
        static var filters: String { "settings.filters".localized }
        static var cache: String { "settings.cache".localized }
        static var notifications: String { "settings.notifications".localized }
        static var advanced: String { "settings.advanced".localized }
        static var restoreDefaults: String { "settings.restoreDefaults".localized }

        enum General {
            static var title: String { "settings.general.title".localized }
            static var startup: String { "settings.general.startup".localized }
            static var launchAtLogin: String { "settings.general.launchAtLogin".localized }
            static var showInDock: String { "settings.general.showInDock".localized }
            static var updates: String { "settings.general.updates".localized }
            static var checkForUpdates: String { "settings.general.checkForUpdates".localized }
            static var checkFrequency: String { "settings.general.checkFrequency".localized }
            static var language: String { "settings.general.language".localized }
            static var languageSystem: String { "settings.general.language.system".localized }
            static var languageEn: String { "settings.general.language.en".localized }
            static var languageZhHans: String { "settings.general.language.zhHans".localized }
            static var languageZhHant: String { "settings.general.language.zhHant".localized }
            static var menuBarStyle: String { "settings.general.menuBarStyle".localized }
            static var menuBarIcon: String { "settings.general.menuBarStyle.icon".localized }
            static var menuBarIconText: String { "settings.general.menuBarStyle.iconText".localized }
            static var menuBarIconProgress: String { "settings.general.menuBarStyle.iconProgress".localized }
        }

        enum Disks {
            static var title: String { "settings.disks.title".localized }
            static var configured: String { "settings.disks.configured".localized }
            static var add: String { "settings.disks.add".localized }
            static var remove: String { "settings.disks.remove".localized }
            static var details: String { "settings.disks.details".localized }
            static var name: String { "settings.disks.name".localized }
            static var mountPath: String { "settings.disks.mountPath".localized }
            static var priority: String { "settings.disks.priority".localized }
            static var priorityHint: String { "settings.disks.priorityHint".localized }
            static var enable: String { "settings.disks.enable".localized }
            static var autoSync: String { "settings.disks.autoSync".localized }
            static var safeEject: String { "settings.disks.safeEject".localized }
        }

        enum SyncPairs {
            static var title: String { "settings.syncPairs.title".localized }
            static var configured: String { "settings.syncPairs.configured".localized }
            static var add: String { "settings.syncPairs.add".localized }
            static var remove: String { "settings.syncPairs.remove".localized }
            static var details: String { "settings.syncPairs.details".localized }
            static var localPath: String { "settings.syncPairs.localPath".localized }
            static var targetDisk: String { "settings.syncPairs.targetDisk".localized }
            static var externalPath: String { "settings.syncPairs.externalPath".localized }
            static var direction: String { "settings.syncPairs.direction".localized }
            static var enable: String { "settings.syncPairs.enable".localized }
            static var createSymlink: String { "settings.syncPairs.createSymlink".localized }
            static var symlinkHint: String { "settings.syncPairs.symlinkHint".localized }
            static var excludePatterns: String { "settings.syncPairs.excludePatterns".localized }
            static var addExcludePattern: String { "settings.syncPairs.addExcludePattern".localized }
        }

        enum Filters {
            static var title: String { "settings.filters.title".localized }
            static var presets: String { "settings.filters.presets".localized }
            static var presetDefault: String { "settings.filters.preset.default".localized }
            static var presetDefaultDesc: String { "settings.filters.preset.default.desc".localized }
            static var presetDeveloper: String { "settings.filters.preset.developer".localized }
            static var presetDeveloperDesc: String { "settings.filters.preset.developer.desc".localized }
            static var presetMedia: String { "settings.filters.preset.media".localized }
            static var presetMediaDesc: String { "settings.filters.preset.media.desc".localized }
            static var presetCustom: String { "settings.filters.preset.custom".localized }
            static var presetCustomDesc: String { "settings.filters.preset.custom.desc".localized }
            static var globalExclude: String { "settings.filters.globalExclude".localized }
            static var addPattern: String { "settings.filters.addPattern".localized }
            static var fileSize: String { "settings.filters.fileSize".localized }
            static var maxSize: String { "settings.filters.maxSize".localized }
            static var minSize: String { "settings.filters.minSize".localized }
            static var excludeHidden: String { "settings.filters.excludeHidden".localized }
        }

        enum Cache {
            static var title: String { "settings.cache.title".localized }
            static var local: String { "settings.cache.local".localized }
            static var location: String { "settings.cache.location".localized }
            static var openFolder: String { "settings.cache.openFolder".localized }
            static var currentUsage: String { "settings.cache.currentUsage".localized }
            static var maxSize: String { "settings.cache.maxSize".localized }
            static var reserveBuffer: String { "settings.cache.reserveBuffer".localized }
            static var reserveBufferHint: String { "settings.cache.reserveBufferHint".localized }
            static var evictionStrategy: String { "settings.cache.evictionStrategy".localized }
            static var evictionModifiedTime: String { "settings.cache.eviction.modifiedTime".localized }
            static var evictionModifiedTimeDesc: String { "settings.cache.eviction.modifiedTime.desc".localized }
            static var evictionAccessTime: String { "settings.cache.eviction.accessTime".localized }
            static var evictionAccessTimeDesc: String { "settings.cache.eviction.accessTime.desc".localized }
            static var evictionSizeFirst: String { "settings.cache.eviction.sizeFirst".localized }
            static var evictionSizeFirstDesc: String { "settings.cache.eviction.sizeFirst.desc".localized }
            static var autoEviction: String { "settings.cache.autoEviction".localized }
            static var checkInterval: String { "settings.cache.checkInterval".localized }
            static var clearAll: String { "settings.cache.clearAll".localized }
            static var clearAllConfirm: String { "settings.cache.clearAllConfirm".localized }
            static func fileCount(_ count: Int) -> String {
                String(format: "settings.cache.fileCount".localized, count)
            }
        }

        enum Notifications {
            static var title: String { "settings.notifications.title".localized }
            static var enable: String { "settings.notifications.enable".localized }
            static var types: String { "settings.notifications.types".localized }
            static var onDiskConnect: String { "settings.notifications.onDiskConnect".localized }
            static var onDiskDisconnect: String { "settings.notifications.onDiskDisconnect".localized }
            static var onSyncStart: String { "settings.notifications.onSyncStart".localized }
            static var onSyncComplete: String { "settings.notifications.onSyncComplete".localized }
            static var onSyncError: String { "settings.notifications.onSyncError".localized }
            static var onCacheLow: String { "settings.notifications.onCacheLow".localized }
            static var style: String { "settings.notifications.style".localized }
            static var playSound: String { "settings.notifications.playSound".localized }
            static var showDetails: String { "settings.notifications.showDetails".localized }
            static var doNotDisturb: String { "settings.notifications.doNotDisturb".localized }
            static var followSystem: String { "settings.notifications.followSystem".localized }
            static var customSchedule: String { "settings.notifications.customSchedule".localized }
            static var scheduleFrom: String { "settings.notifications.scheduleFrom".localized }
            static var scheduleTo: String { "settings.notifications.scheduleTo".localized }
            static var testNotification: String { "settings.notifications.testNotification".localized }
        }

        enum Advanced {
            static var title: String { "settings.advanced.title".localized }
            static var syncBehavior: String { "settings.advanced.syncBehavior".localized }
            static var debounceDelay: String { "settings.advanced.debounceDelay".localized }
            static var debounceDelayHint: String { "settings.advanced.debounceDelayHint".localized }
            static var batchSize: String { "settings.advanced.batchSize".localized }
            static var batchSizeUnit: String { "settings.advanced.batchSizeUnit".localized }
            static var retryCount: String { "settings.advanced.retryCount".localized }
            static var retryCountUnit: String { "settings.advanced.retryCountUnit".localized }
            static var timeout: String { "settings.advanced.timeout".localized }
            static var rsyncOptions: String { "settings.advanced.rsyncOptions".localized }
            static var rsyncArchive: String { "settings.advanced.rsync.archive".localized }
            static var rsyncDelete: String { "settings.advanced.rsync.delete".localized }
            static var rsyncChecksum: String { "settings.advanced.rsync.checksum".localized }
            static var rsyncChecksumHint: String { "settings.advanced.rsync.checksumHint".localized }
            static var rsyncPartial: String { "settings.advanced.rsync.partial".localized }
            static var rsyncCompress: String { "settings.advanced.rsync.compress".localized }
            static var rsyncCompressHint: String { "settings.advanced.rsync.compressHint".localized }
            static var logging: String { "settings.advanced.logging".localized }
            static var logLevel: String { "settings.advanced.logLevel".localized }
            static var logLevelDebug: String { "settings.advanced.logLevel.debug".localized }
            static var logLevelInfo: String { "settings.advanced.logLevel.info".localized }
            static var logLevelWarning: String { "settings.advanced.logLevel.warning".localized }
            static var logLevelError: String { "settings.advanced.logLevel.error".localized }
            static var logSize: String { "settings.advanced.logSize".localized }
            static var logCount: String { "settings.advanced.logCount".localized }
            static var openLogFolder: String { "settings.advanced.openLogFolder".localized }
            static var data: String { "settings.advanced.data".localized }
            static var exportConfig: String { "settings.advanced.exportConfig".localized }
            static var importConfig: String { "settings.advanced.importConfig".localized }
            static var resetAll: String { "settings.advanced.resetAll".localized }
            static var danger: String { "settings.advanced.danger".localized }
            static var clearAllData: String { "settings.advanced.clearAllData".localized }
            static var clearAllDataConfirm: String { "settings.advanced.clearAllDataConfirm".localized }
        }
    }

    // MARK: - Progress
    enum Progress {
        static var title: String { "progress.title".localized }
        static func multiTask(_ count: Int) -> String {
            String(format: "progress.multiTask".localized, count)
        }
        static func currentFile(_ f: String) -> String {
            String(format: "progress.currentFile".localized, f)
        }
        static func fileProgress(current: Int, total: Int) -> String {
            String(format: "progress.fileProgress".localized, current, total)
        }
        static func byteProgress(current: String, total: String) -> String {
            String(format: "progress.byteProgress".localized, current, total)
        }
        static func speed(_ s: String) -> String {
            String(format: "progress.speed".localized, s)
        }
        static func timeRemaining(_ t: String) -> String {
            String(format: "progress.timeRemaining".localized, t)
        }
        static var hideWindow: String { "progress.hideWindow".localized }
        static var cancelSync: String { "progress.cancelSync".localized }
        static var cancelAll: String { "progress.cancelAll".localized }
        static var minimize: String { "progress.minimize".localized }
        static var waiting: String { "progress.waiting".localized }
    }

    // MARK: - History
    enum History {
        static var title: String { "history.title".localized }
        static var allDisks: String { "history.filter.allDisks".localized }
        static var allStatus: String { "history.filter.allStatus".localized }
        static var last7Days: String { "history.filter.last7days".localized }
        static var last30Days: String { "history.filter.last30days".localized }
        static var allTime: String { "history.filter.allTime".localized }
        static var search: String { "history.search".localized }
        static var today: String { "history.today".localized }
        static var yesterday: String { "history.yesterday".localized }
        static var noRecords: String { "history.noRecords".localized }
        static func stats(total: Int, success: Int, failed: Int) -> String {
            String(format: "history.stats".localized, total, success, failed)
        }
        static func statsFiles(count: Int, size: String) -> String {
            String(format: "history.statsFiles".localized, count, size)
        }
        static var exportHistory: String { "history.exportHistory".localized }
        static var clearHistory: String { "history.clearHistory".localized }
        static var clearHistoryConfirm: String { "history.clearHistoryConfirm".localized }

        enum Detail {
            static var title: String { "history.detail.title".localized }
            static var status: String { "history.detail.status".localized }
            static var time: String { "history.detail.time".localized }
            static var duration: String { "history.detail.duration".localized }
            static var direction: String { "history.detail.direction".localized }
            static var disk: String { "history.detail.disk".localized }
            static var stats: String { "history.detail.stats".localized }
            static var fileCount: String { "history.detail.fileCount".localized }
            static var totalSize: String { "history.detail.totalSize".localized }
            static var added: String { "history.detail.added".localized }
            static var updated: String { "history.detail.updated".localized }
            static var deleted: String { "history.detail.deleted".localized }
            static var skipped: String { "history.detail.skipped".localized }
            static var rsyncOutput: String { "history.detail.rsyncOutput".localized }
            static var copyLog: String { "history.detail.copyLog".localized }
            static var viewDetails: String { "history.detail.viewDetails".localized }
        }
    }

    // MARK: - Wizard
    enum Wizard {
        static func step(current: Int, total: Int) -> String {
            String(format: "wizard.step".localized, current, total)
        }

        enum Welcome {
            static var title: String { "wizard.welcome.title".localized }
            static var subtitle: String { "wizard.welcome.subtitle".localized }
            static var description: String { "wizard.welcome.description".localized }
            static var feature1: String { "wizard.welcome.feature1".localized }
            static var feature2: String { "wizard.welcome.feature2".localized }
            static var feature3: String { "wizard.welcome.feature3".localized }
            static var feature4: String { "wizard.welcome.feature4".localized }
            static var startSetup: String { "wizard.welcome.startSetup".localized }
        }

        enum Disks {
            static var title: String { "wizard.disks.title".localized }
            static var subtitle: String { "wizard.disks.subtitle".localized }
            static var detected: String { "wizard.disks.detected".localized }
            static var systemDisk: String { "wizard.disks.systemDisk".localized }
            static var notFound: String { "wizard.disks.notFound".localized }
            static var addManually: String { "wizard.disks.addManually".localized }
            static var hint: String { "wizard.disks.hint".localized }
        }

        enum Directories {
            static var title: String { "wizard.directories.title".localized }
            static func subtitle(_ disk: String) -> String {
                String(format: "wizard.directories.subtitle".localized, disk)
            }
            static var recommended: String { "wizard.directories.recommended".localized }
            static func currentSize(_ size: String) -> String {
                String(format: "wizard.directories.currentSize".localized, size)
            }
            static var addCustom: String { "wizard.directories.addCustom".localized }
            static var options: String { "wizard.directories.options".localized }
            static var createSymlink: String { "wizard.directories.createSymlink".localized }
            static var autoSync: String { "wizard.directories.autoSync".localized }
        }

        enum Permissions {
            static var title: String { "wizard.permissions.title".localized }
            static var subtitle: String { "wizard.permissions.subtitle".localized }
            static var fullDiskAccess: String { "wizard.permissions.fullDiskAccess".localized }
            static var fullDiskAccessDesc: String { "wizard.permissions.fullDiskAccess.desc".localized }
            static var notifications: String { "wizard.permissions.notifications".localized }
            static var notificationsDesc: String { "wizard.permissions.notifications.desc".localized }
            static var granted: String { "wizard.permissions.status.granted".localized }
            static var notGranted: String { "wizard.permissions.status.notGranted".localized }
            static var authorize: String { "wizard.permissions.authorize".localized }
            static var instructions: String { "wizard.permissions.instructions".localized }
            static var instruction1: String { "wizard.permissions.instruction1".localized }
            static var instruction2: String { "wizard.permissions.instruction2".localized }
            static var instruction3: String { "wizard.permissions.instruction3".localized }
            static var privacy: String { "wizard.permissions.privacy".localized }
        }

        enum Complete {
            static var title: String { "wizard.complete.title".localized }
            static var subtitle: String { "wizard.complete.subtitle".localized }
            static var yourConfig: String { "wizard.complete.yourConfig".localized }
            static func disk(_ name: String) -> String {
                String(format: "wizard.complete.disk".localized, name)
            }
            static func syncDir(from: String, to: String) -> String {
                String(format: "wizard.complete.syncDir".localized, from, to)
            }
            static func autoSync(_ enabled: String) -> String {
                String(format: "wizard.complete.autoSync".localized, enabled)
            }
            static func symlink(_ enabled: String) -> String {
                String(format: "wizard.complete.symlink".localized, enabled)
            }
            static var nextSteps: String { "wizard.complete.nextSteps".localized }
            static var step1: String { "wizard.complete.step1".localized }
            static func step2(_ disk: String) -> String {
                String(format: "wizard.complete.step2".localized, disk)
            }
            static var step3: String { "wizard.complete.step3".localized }
            static var launchAtLogin: String { "wizard.complete.launchAtLogin".localized }
            static var syncNow: String { "wizard.complete.syncNow".localized }
        }
    }

    // MARK: - Error
    enum Error {
        static var title: String { "error.title".localized }
        static var syncFailed: String { "error.syncFailed".localized }
        static var diskDisconnected: String { "error.diskDisconnected".localized }
        static func diskNotFound(_ name: String) -> String {
            String(format: "error.diskNotFound".localized, name)
        }
        static func pathNotFound(_ path: String) -> String {
            String(format: "error.pathNotFound".localized, path)
        }
        static func permissionDenied(_ path: String) -> String {
            String(format: "error.permissionDenied".localized, path)
        }
        static var rsyncFailed: String { "error.rsyncFailed".localized }
        static var configLoadFailed: String { "error.configLoadFailed".localized }
        static var configSaveFailed: String { "error.configSaveFailed".localized }
        static var syncAlreadyRunning: String { "error.syncAlreadyRunning".localized }
        static var insufficientSpace: String { "error.insufficientSpace".localized }
        static var unknown: String { "error.unknown".localized }
        static var viewLog: String { "error.viewLog".localized }
        static var reconnectAndRetry: String { "error.reconnectAndRetry".localized }
    }

    // MARK: - Recovery
    enum Recovery {
        static var title: String { "recovery.title".localized }
        static var description: String { "recovery.description".localized }
        static var problem: String { "recovery.problem".localized }
        static func symlinkDiskMissing(path: String, disk: String) -> String {
            String(format: "recovery.problem.symlinkDiskMissing".localized, path, disk)
        }
        static var options: String { "recovery.options".localized }
        static var optionWait: String { "recovery.option.wait".localized }
        static var optionWaitDesc: String { "recovery.option.wait.desc".localized }
        static var optionRestoreBackup: String { "recovery.option.restoreBackup".localized }
        static func optionRestoreBackupDesc(_ backup: String) -> String {
            String(format: "recovery.option.restoreBackup.desc".localized, backup)
        }
        static var optionRestoreBackupWarning: String { "recovery.option.restoreBackup.warning".localized }
        static var optionCreateNew: String { "recovery.option.createNew".localized }
        static func optionCreateNewDesc(_ path: String) -> String {
            String(format: "recovery.option.createNew.desc".localized, path)
        }
        static var optionCreateNewWarning: String { "recovery.option.createNew.warning".localized }
        static var execute: String { "recovery.execute".localized }
    }

    // MARK: - About
    enum About {
        static var title: String { "about.title".localized }
        static func version(_ v: String) -> String {
            String(format: "about.version".localized, v)
        }
        static func copyright(_ year: String) -> String {
            String(format: "about.copyright".localized, year)
        }
        static var github: String { "about.github".localized }
        static var checkUpdates: String { "about.checkUpdates".localized }
    }

    // MARK: - Time
    enum Time {
        static func seconds(_ n: Int) -> String {
            String(format: "time.seconds".localized, n)
        }
        static func minutes(_ n: Int) -> String {
            String(format: "time.minutes".localized, n)
        }
        static func hours(_ n: Int) -> String {
            String(format: "time.hours".localized, n)
        }
        static func days(_ n: Int) -> String {
            String(format: "time.days".localized, n)
        }
        static var justNow: String { "time.justNow".localized }
        static func secondsAgo(_ n: Int) -> String {
            String(format: "time.secondsAgo".localized, n)
        }
        static func minutesAgo(_ n: Int) -> String {
            String(format: "time.minutesAgo".localized, n)
        }
        static func hoursAgo(_ n: Int) -> String {
            String(format: "time.hoursAgo".localized, n)
        }
        static func daysAgo(_ n: Int) -> String {
            String(format: "time.daysAgo".localized, n)
        }

        /// Format a relative time string from a date
        static func relative(from date: Date) -> String {
            let interval = Date().timeIntervalSince(date)

            if interval < 60 {
                return justNow
            } else if interval < 3600 {
                return minutesAgo(Int(interval / 60))
            } else if interval < 86400 {
                return hoursAgo(Int(interval / 3600))
            } else {
                return daysAgo(Int(interval / 86400))
            }
        }
    }
}

// MARK: - String Extension

extension String {
    /// Returns the localized string for the given key
    /// Uses LocalizationManager.shared.bundle for dynamic language switching
    var localized: String {
        let result = NSLocalizedString(self, tableName: "Localizable", bundle: LocalizationManager.shared.bundle, value: "", comment: "")
        // If NSLocalizedString returns the key itself (not found), return the key
        return result.isEmpty ? self : result
    }

    /// Returns the localized string with format arguments
    func localized(with arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }
}

// MARK: - LocalizedStringKey Extension

extension LocalizedStringKey {
    /// Initialize from a localization key string
    init(_ key: String) {
        self.init(stringLiteral: NSLocalizedString(key, comment: ""))
    }
}

// MARK: - Byte Formatting

extension Int64 {
    /// Format bytes to human readable string (e.g., "1.5 GB")
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Int {
    /// Format bytes to human readable string
    var formattedBytes: String {
        Int64(self).formattedBytes
    }
}
