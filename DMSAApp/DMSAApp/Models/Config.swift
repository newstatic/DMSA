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
    var syncEngine: SyncEngineConfig = SyncEngineConfig()
}

// MARK: - General Config

struct GeneralConfig: Codable {
    var launchAtLogin: Bool = false
    var showInDock: Bool = false
    var checkForUpdates: Bool = true
    var language: String = "system"
    var autoSyncEnabled: Bool = true  // 全局自动同步开关
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

    /// 同步对名称 (用于显示)
    var name: String {
        // 从本地路径提取目录名作为名称
        return (localPath as NSString).lastPathComponent
    }

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

    // MARK: - VFS 属性 (v3.0)

    /// TARGET_DIR - VFS 挂载点 (用户访问入口)
    /// 例如: ~/Downloads
    var targetDir: String {
        return localPath  // 挂载到原始本地路径位置
    }

    /// LOCAL_DIR - 本地热数据缓存
    /// 例如: ~/Downloads_Local
    var localDir: String {
        let path = (localPath as NSString).expandingTildeInPath
        return path + "_Local"
    }

    /// EXTERNAL_DIR - 外部完整数据源
    /// 例如: /Volumes/BACKUP/Downloads
    var externalDir: String {
        // 需要从 DiskConfig 获取挂载路径，这里返回相对路径
        // 实际使用时需要与 DiskConfig 配合
        return externalRelativePath
    }

    /// 获取完整的外部路径 (需要磁盘挂载路径)
    func fullExternalDir(diskMountPath: String) -> String {
        return (diskMountPath as NSString).appendingPathComponent(externalRelativePath)
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

// MARK: - Sync Engine Config

struct SyncEngineConfig: Codable, Equatable {
    /// 是否启用校验和
    var enableChecksum: Bool = true

    /// 校验算法
    var checksumAlgorithm: ChecksumAlgorithm = .md5

    /// 复制后验证
    var verifyAfterCopy: Bool = true

    /// 冲突解决策略
    var conflictStrategy: SyncConflictStrategy = .localWinsWithBackup

    /// 是否自动解决冲突
    var autoResolveConflicts: Bool = true

    /// 备份文件后缀
    var backupSuffix: String = "_backup"

    /// 是否启用删除
    var enableDelete: Bool = true

    /// 缓冲区大小 (字节)
    var bufferSize: Int = 1024 * 1024  // 1MB

    /// 并行操作数
    var parallelOperations: Int = 4

    /// 是否包含隐藏文件
    var includeHidden: Bool = false

    /// 是否跟随符号链接
    var followSymlinks: Bool = false

    /// 启用暂停/恢复
    var enablePauseResume: Bool = true

    /// 状态检查点间隔 (文件数)
    var stateCheckpointInterval: Int = 50

    /// 校验算法枚举
    enum ChecksumAlgorithm: String, Codable, CaseIterable {
        case md5 = "md5"
        case sha256 = "sha256"
        case xxhash64 = "xxhash64"

        var displayName: String {
            switch self {
            case .md5: return "MD5 (推荐)"
            case .sha256: return "SHA-256 (更安全)"
            case .xxhash64: return "xxHash64 (最快)"
            }
        }
    }

    /// 冲突解决策略枚举
    enum SyncConflictStrategy: String, Codable, CaseIterable {
        case newerWins = "newer_wins"
        case largerWins = "larger_wins"
        case localWins = "local_wins"
        case externalWins = "external_wins"
        case localWinsWithBackup = "local_wins_backup"
        case externalWinsWithBackup = "external_wins_backup"
        case askUser = "ask_user"
        case keepBoth = "keep_both"

        var displayName: String {
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
}
