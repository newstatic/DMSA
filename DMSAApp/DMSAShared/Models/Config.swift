import Foundation

/// 应用配置
public struct AppConfig: Codable, Sendable {
    public var version: String = "4.0"
    public var general: GeneralConfig = GeneralConfig()
    public var disks: [DiskConfig] = []
    public var syncPairs: [SyncPairConfig] = []
    public var filters: FilterConfig = FilterConfig()
    public var cache: CacheConfig = CacheConfig()
    public var monitoring: MonitoringConfig = MonitoringConfig()
    public var notifications: NotificationConfig = NotificationConfig()
    public var logging: LoggingConfig = LoggingConfig()
    public var ui: UIConfig = UIConfig()
    public var syncEngine: SyncEngineConfig = SyncEngineConfig()
    public var vfs: VFSConfig = VFSConfig()

    public init() {}
}

// MARK: - General Config

public struct GeneralConfig: Codable, Equatable, Sendable {
    public var launchAtLogin: Bool = false
    public var showInDock: Bool = false
    public var checkForUpdates: Bool = true
    public var language: String = "system"
    public var autoSyncEnabled: Bool = true

    public init() {}
}

// MARK: - Disk Config

public struct DiskConfig: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var mountPath: String
    public var priority: Int
    public var enabled: Bool
    public var fileSystem: String

    public var isConnected: Bool {
        FileManager.default.fileExists(atPath: mountPath)
    }

    public init(name: String, mountPath: String? = nil, priority: Int = 0) {
        self.id = UUID().uuidString
        self.name = name
        self.mountPath = mountPath ?? "/Volumes/\(name)"
        self.priority = priority
        self.enabled = true
        self.fileSystem = "auto"
    }

    public init(id: String, name: String, mountPath: String, priority: Int = 0, enabled: Bool = true, fileSystem: String = "auto") {
        self.id = id
        self.name = name
        self.mountPath = mountPath
        self.priority = priority
        self.enabled = enabled
        self.fileSystem = fileSystem
    }
}

// MARK: - Sync Pair Config

public struct SyncPairConfig: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var diskId: String
    public var localPath: String
    public var externalRelativePath: String
    public var direction: SyncDirection
    public var createSymlink: Bool
    public var enabled: Bool
    public var excludePatterns: [String]

    public var name: String {
        return (localPath as NSString).lastPathComponent
    }

    public init(diskId: String, localPath: String, externalRelativePath: String) {
        self.id = UUID().uuidString
        self.diskId = diskId
        self.localPath = localPath
        self.externalRelativePath = externalRelativePath
        self.direction = .localToExternal
        self.createSymlink = true
        self.enabled = true
        self.excludePatterns = []
    }

    public init(id: String, diskId: String, localPath: String, externalRelativePath: String,
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

    public func externalFullPath(diskMountPath: String) -> String {
        return (diskMountPath as NSString).appendingPathComponent(externalRelativePath)
    }

    public var expandedLocalPath: String {
        return SyncPairConfig.expandTilde(localPath)
    }

    // MARK: - VFS 属性 (v4.0)

    /// TARGET_DIR - VFS 挂载点 (用户访问入口)
    /// 使用 UserPathManager 确保在 root 身份下也能正确解析
    public var targetDir: String {
        return SyncPairConfig.expandTilde(localPath)
    }

    /// LOCAL_DIR - 本地热数据缓存
    /// 在 localPath 基础上添加 _Local 后缀
    public var localDir: String {
        let path = SyncPairConfig.expandTilde(localPath)
        return path + "_Local"
    }

    /// 扩展 tilde (~) 为实际用户路径
    /// 使用 UserPathManager (如果可用) 或回退到系统方法
    private static func expandTilde(_ path: String) -> String {
        // 尝试使用 UserPathManager (在 Service 中设置了正确的用户路径)
        return UserPathManager.shared.expandTilde(path)
    }

    /// EXTERNAL_DIR - 外部完整数据源
    public var externalDir: String {
        return externalRelativePath
    }

    public func fullExternalDir(diskMountPath: String) -> String {
        return (diskMountPath as NSString).appendingPathComponent(externalRelativePath)
    }
}

// MARK: - Sync Direction

public enum SyncDirection: String, Codable, CaseIterable, Sendable {
    case localToExternal = "local_to_external"
    case externalToLocal = "external_to_local"
    case bidirectional = "bidirectional"

    public var displayName: String {
        switch self {
        case .localToExternal: return "本地 → 外置"
        case .externalToLocal: return "外置 → 本地"
        case .bidirectional: return "双向同步"
        }
    }

    public var icon: String {
        switch self {
        case .localToExternal: return "arrow.right"
        case .externalToLocal: return "arrow.left"
        case .bidirectional: return "arrow.left.arrow.right"
        }
    }
}

// MARK: - Filter Config

public struct FilterConfig: Codable, Equatable, Sendable {
    public var excludePatterns: [String] = [
        ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
        "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
        "Thumbs.db", "desktop.ini",
        "*.part", "*.crdownload", "*.download",
        ".FUSE"
    ]
    public var includePatterns: [String] = ["*"]
    public var maxFileSize: Int64? = nil
    public var minFileSize: Int64? = nil
    public var excludeHidden: Bool = false

    public init() {}
}

// MARK: - Cache Config

public struct CacheConfig: Codable, Equatable, Sendable {
    public var maxCacheSize: Int64 = 10 * 1024 * 1024 * 1024  // 10 GB
    public var reserveBuffer: Int64 = 500 * 1024 * 1024       // 500 MB
    public var evictionCheckInterval: Int = 300               // 5 分钟
    public var autoEvictionEnabled: Bool = true
    public var evictionStrategy: EvictionStrategy = .accessTime

    public enum EvictionStrategy: String, Codable, CaseIterable, Sendable {
        case modifiedTime = "modified_time"
        case accessTime = "access_time"
        case sizeFirst = "size_first"

        public var displayName: String {
            switch self {
            case .modifiedTime: return "按修改时间"
            case .accessTime: return "按访问时间 (LRU)"
            case .sizeFirst: return "大文件优先"
            }
        }
    }

    public init() {}
}

// MARK: - Monitoring Config

public struct MonitoringConfig: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    public var debounceSeconds: Int = 5
    public var batchSize: Int = 100
    public var watchSubdirectories: Bool = true

    public init() {}
}

// MARK: - Notification Config

public struct NotificationConfig: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    public var showOnDiskConnect: Bool = true
    public var showOnDiskDisconnect: Bool = true
    public var showOnSyncStart: Bool = false
    public var showOnSyncComplete: Bool = true
    public var showOnSyncError: Bool = true
    public var soundEnabled: Bool = true

    public init() {}
}

// MARK: - Logging Config

public struct LoggingConfig: Codable, Equatable, Sendable {
    public var level: LogLevel = .info
    public var maxFileSize: Int = 10 * 1024 * 1024  // 10 MB
    public var maxFiles: Int = 5
    public var logPath: String = "~/Library/Logs/DMSA/"

    public enum LogLevel: String, Codable, CaseIterable, Sendable {
        case debug
        case info
        case warn
        case error

        public var displayName: String {
            rawValue.capitalized
        }
    }

    public init() {}
}

// MARK: - UI Config

public struct UIConfig: Codable, Equatable, Sendable {
    public var showProgressWindow: Bool = true
    public var menuBarStyle: MenuBarStyle = .icon
    public var theme: Theme = .system

    public enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
        case icon
        case iconText = "icon_text"
        case text

        public var displayName: String {
            switch self {
            case .icon: return "仅图标"
            case .iconText: return "图标 + 文字"
            case .text: return "仅文字"
            }
        }
    }

    public enum Theme: String, Codable, CaseIterable, Sendable {
        case system
        case light
        case dark

        public var displayName: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }
    }

    public init() {}
}

// MARK: - Sync Engine Config

public struct SyncEngineConfig: Codable, Equatable, Sendable {
    public var enableChecksum: Bool = true
    public var checksumAlgorithm: ChecksumAlgorithm = .md5
    public var verifyAfterCopy: Bool = true
    public var conflictStrategy: SyncConflictStrategy = .localWinsWithBackup
    public var autoResolveConflicts: Bool = true
    public var backupSuffix: String = "_backup"
    public var enableDelete: Bool = true
    public var bufferSize: Int = 1024 * 1024  // 1MB
    public var parallelOperations: Int = 4
    public var includeHidden: Bool = false
    public var followSymlinks: Bool = false
    public var enablePauseResume: Bool = true
    public var stateCheckpointInterval: Int = 50

    public enum ChecksumAlgorithm: String, Codable, CaseIterable, Sendable {
        case md5 = "md5"
        case sha256 = "sha256"
        case xxhash64 = "xxhash64"

        public var displayName: String {
            switch self {
            case .md5: return "MD5 (推荐)"
            case .sha256: return "SHA-256 (更安全)"
            case .xxhash64: return "xxHash64 (最快)"
            }
        }
    }

    public enum SyncConflictStrategy: String, Codable, CaseIterable, Sendable {
        case newerWins = "newer_wins"
        case largerWins = "larger_wins"
        case localWins = "local_wins"
        case externalWins = "external_wins"
        case localWinsWithBackup = "local_wins_backup"
        case externalWinsWithBackup = "external_wins_backup"
        case askUser = "ask_user"
        case keepBoth = "keep_both"

        public var displayName: String {
            switch self {
            case .newerWins: return "新文件覆盖"
            case .largerWins: return "大文件覆盖"
            case .localWins: return "本地优先"
            case .externalWins: return "外置优先"
            case .localWinsWithBackup: return "本地优先 (备份)"
            case .externalWinsWithBackup: return "外置优先 (备份)"
            case .askUser: return "每次询问"
            case .keepBoth: return "保留两者"
            }
        }
    }

    public init() {}
}

// MARK: - VFS Config

public struct VFSConfig: Codable, Equatable, Sendable {
    public var autoMount: Bool = true
    public var volumeName: String = "DMSA"
    public var allowOther: Bool = false
    public var readOnly: Bool = false
    public var cacheAttributes: Bool = true
    public var attributeCacheTTL: Int = 60  // 秒

    public init() {}
}

// MARK: - 状态枚举

/// 同步状态
public enum SyncStatus: Int, Codable, Sendable {
    case pending = 0
    case inProgress = 1
    case completed = 2
    case failed = 3
    case cancelled = 4
    case paused = 5

    public var displayName: String {
        switch self {
        case .pending: return "等待中"
        case .inProgress: return "同步中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        case .paused: return "已暂停"
        }
    }

    public var icon: String {
        switch self {
        case .pending: return "clock"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        case .paused: return "pause.circle"
        }
    }
}

/// 文件位置
public enum FileLocation: Int, Codable, Sendable {
    case notExists = 0
    case localOnly = 1
    case externalOnly = 2
    case both = 3
    case deleted = 4

    public var displayName: String {
        switch self {
        case .notExists: return "不存在"
        case .localOnly: return "仅本地"
        case .externalOnly: return "仅外置"
        case .both: return "两端都有"
        case .deleted: return "已删除"
        }
    }
}
