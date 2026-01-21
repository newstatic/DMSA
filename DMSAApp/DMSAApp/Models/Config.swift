import Foundation

/// 应用配置
struct AppConfig: Codable {
    var version: String = "2.0"
    var general: GeneralConfig = GeneralConfig()
    var disks: [DiskConfig] = []
    var syncPairs: [SyncPairConfig] = []
    var filters: FilterConfig = FilterConfig()
    var cache: CacheConfig = CacheConfig()
    var monitoring: MonitoringConfig = MonitoringConfig()
    var notifications: NotificationConfig = NotificationConfig()
    var logging: LoggingConfig = LoggingConfig()
    var ui: UIConfig = UIConfig()
}

// MARK: - General Config

struct GeneralConfig: Codable {
    var launchAtLogin: Bool = false
    var showInDock: Bool = false
    var checkForUpdates: Bool = true
    var language: String = "system"
}

// MARK: - Disk Config

struct DiskConfig: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var mountPath: String
    var priority: Int = 0
    var enabled: Bool = true
    var fileSystem: String = "auto"

    var isConnected: Bool {
        FileManager.default.fileExists(atPath: mountPath)
    }

    init(name: String, mountPath: String? = nil, priority: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.mountPath = mountPath ?? "/Volumes/\(name)"
        self.priority = priority
    }

    init(id: String, name: String, mountPath: String, priority: Int = 0, enabled: Bool = true, fileSystem: String = "auto") {
        self.id = id
        self.name = name
        self.mountPath = mountPath
        self.priority = priority
        self.enabled = enabled
        self.fileSystem = fileSystem
    }
}

// MARK: - Sync Pair Config

struct SyncPairConfig: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var diskId: String
    var localPath: String
    var externalRelativePath: String
    var direction: SyncDirection = .localToExternal
    var createSymlink: Bool = true
    var enabled: Bool = true
    var excludePatterns: [String] = []

    init(diskId: String, localPath: String, externalRelativePath: String) {
        self.id = UUID().uuidString
        self.diskId = diskId
        self.localPath = localPath
        self.externalRelativePath = externalRelativePath
    }

    init(id: String, diskId: String, localPath: String, externalRelativePath: String,
         direction: SyncDirection = .localToExternal, createSymlink: Bool = true,
         enabled: Bool = true, excludePatterns: [String] = []) {
        self.id = id
        self.diskId = diskId
        self.localPath = localPath
        self.externalRelativePath = externalRelativePath
        self.direction = direction
        self.createSymlink = createSymlink
        self.enabled = enabled
        self.excludePatterns = excludePatterns
    }

    /// 计算外置硬盘完整路径
    func externalFullPath(diskMountPath: String) -> String {
        return (diskMountPath as NSString).appendingPathComponent(externalRelativePath)
    }

    /// 展开本地路径
    var expandedLocalPath: String {
        return (localPath as NSString).expandingTildeInPath
    }
}

// MARK: - Sync Direction

enum SyncDirection: String, Codable, CaseIterable {
    case localToExternal = "local_to_external"
    case externalToLocal = "external_to_local"
    case bidirectional = "bidirectional"

    var displayName: String {
        switch self {
        case .localToExternal: return "本地 → 外置"
        case .externalToLocal: return "外置 → 本地"
        case .bidirectional: return "双向同步"
        }
    }

    var icon: String {
        switch self {
        case .localToExternal: return "arrow.right"
        case .externalToLocal: return "arrow.left"
        case .bidirectional: return "arrow.left.arrow.right"
        }
    }
}

// MARK: - Filter Config

struct FilterConfig: Codable, Equatable {
    var excludePatterns: [String] = [
        ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
        "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
        "Thumbs.db", "desktop.ini",
        "*.part", "*.crdownload", "*.download"
    ]
    var includePatterns: [String] = ["*"]
    var maxFileSize: Int64? = nil
    var minFileSize: Int64? = nil
    var excludeHidden: Bool = false
}

// MARK: - Cache Config

struct CacheConfig: Codable, Equatable {
    var maxCacheSize: Int64 = 10 * 1024 * 1024 * 1024  // 10 GB
    var reserveBuffer: Int64 = 500 * 1024 * 1024       // 500 MB
    var evictionCheckInterval: Int = 300               // 5 分钟
    var autoEvictionEnabled: Bool = true
    var evictionStrategy: EvictionStrategy = .modifiedTime

    enum EvictionStrategy: String, Codable, CaseIterable {
        case modifiedTime = "modified_time"
        case accessTime = "access_time"
        case sizeFirst = "size_first"

        var displayName: String {
            switch self {
            case .modifiedTime: return "按修改时间"
            case .accessTime: return "按访问时间 (LRU)"
            case .sizeFirst: return "大文件优先"
            }
        }
    }
}

// MARK: - Monitoring Config

struct MonitoringConfig: Codable, Equatable {
    var enabled: Bool = true
    var debounceSeconds: Int = 5
    var batchSize: Int = 100
    var watchSubdirectories: Bool = true
}

// MARK: - Notification Config

struct NotificationConfig: Codable, Equatable {
    var enabled: Bool = true
    var showOnDiskConnect: Bool = true
    var showOnDiskDisconnect: Bool = true
    var showOnSyncStart: Bool = false
    var showOnSyncComplete: Bool = true
    var showOnSyncError: Bool = true
    var soundEnabled: Bool = true
}

// MARK: - Logging Config

struct LoggingConfig: Codable, Equatable {
    var level: LogLevel = .info
    var maxFileSize: Int = 10 * 1024 * 1024  // 10 MB
    var maxFiles: Int = 5
    var logPath: String = "~/Library/Logs/DMSA/app.log"

    enum LogLevel: String, Codable, CaseIterable {
        case debug
        case info
        case warn
        case error

        var displayName: String {
            rawValue.capitalized
        }
    }
}

// MARK: - UI Config

struct UIConfig: Codable, Equatable {
    var showProgressWindow: Bool = true
    var menuBarStyle: MenuBarStyle = .icon
    var theme: Theme = .system

    enum MenuBarStyle: String, Codable, CaseIterable {
        case icon
        case iconText = "icon_text"
        case text

        var displayName: String {
            switch self {
            case .icon: return "仅图标"
            case .iconText: return "图标 + 文字"
            case .text: return "仅文字"
            }
        }
    }

    enum Theme: String, Codable, CaseIterable {
        case system
        case light
        case dark

        var displayName: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }
    }
}

// MARK: - Sync Status

enum SyncStatus: Int, Codable {
    case pending = 0
    case inProgress = 1
    case completed = 2
    case failed = 3
    case cancelled = 4

    var displayName: String {
        switch self {
        case .pending: return "等待中"
        case .inProgress: return "同步中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        }
    }
}

// MARK: - File Location

enum FileLocation: Int, Codable {
    case notExists = 0
    case localOnly = 1
    case externalOnly = 2
    case both = 3

    var displayName: String {
        switch self {
        case .notExists: return "不存在"
        case .localOnly: return "仅本地"
        case .externalOnly: return "仅外置"
        case .both: return "两端都有"
        }
    }
}
