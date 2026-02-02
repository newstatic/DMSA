import Foundation

/// 应用常量
enum Constants {
    /// Bundle ID
    static let bundleId = "com.ttttt.dmsa"

    /// 应用名称
    static let appName = "DMSA"
    static let appFullName = "Delt MACOS Sync App"

    /// 版本
    static let version = "4.7"

    /// 服务版本信息
    enum ServiceVersion {
        static let protocolVersion = 1
        static let buildNumber = 20260126
        static let minAppVersion = "4.5"
        static var fullVersion: String {
            "\(Constants.version) (build \(buildNumber), protocol v\(protocolVersion))"
        }
    }

    /// 路径
    enum Paths {
        static let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DMSA")

        static let config = appSupport.appendingPathComponent("config.json")
        static let configBackup = appSupport.appendingPathComponent("config.backup.json")
        static let database = appSupport.appendingPathComponent("Database")

        /// 共享数据目录
        static var sharedData: URL {
            appSupport.appendingPathComponent("SharedData")
        }

        /// 共享状态文件
        static var sharedState: URL {
            sharedData.appendingPathComponent("shared_state.json")
        }

        /// Downloads_Local - 原始 ~/Downloads 重命名后的本地存储目录
        static let downloadsLocal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads_Local")

        /// 虚拟 Downloads - FUSE 挂载点
        static let virtualDownloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")

        static let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DMSA")
        static let logFile = logs.appendingPathComponent("app.log")

        /// 服务日志 (Service 以 root 运行，日志在 /var/log/dmsa/)
        static let serviceLogDir = URL(fileURLWithPath: "/var/log/dmsa")
        static let serviceLog = serviceLogDir.appendingPathComponent("service.log")

        static let launchAgent = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.ttttt.dmsa.plist")
    }

    /// 默认配置值
    enum Defaults {
        static let debounceSeconds: Int = 5
        static let maxRetryCount: Int = 3
        static let diskMountDelay: TimeInterval = 2.0
        static let syncLockTimeout: TimeInterval = 5.0
        static let writeBackDelay: TimeInterval = 5.0
    }

    /// 排除文件模式
    static let defaultExcludePatterns: [String] = [
        ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
        ".TemporaryItems", ".Trashes", ".vol",
        "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
        "Thumbs.db", "desktop.ini",
        "*.part", "*.crdownload", "*.download", "*.partial"
    ]

    /// XPC Service Identifier (统一服务)
    enum XPCService {
        /// 统一服务 (v4.1 - VFS + Sync + Privileged)
        static let service = "com.ttttt.dmsa.service"
    }

    /// 分布式通知名称
    enum Notifications {
        static let vfsMounted = "com.ttttt.dmsa.vfs.mounted"
        static let vfsUnmounted = "com.ttttt.dmsa.vfs.unmounted"
        static let syncCompleted = "com.ttttt.dmsa.sync.completed"
        static let syncFailed = "com.ttttt.dmsa.sync.failed"
        static let fileWritten = "com.ttttt.dmsa.vfs.fileWritten"
        static let configChanged = "com.ttttt.dmsa.configChanged"
        static let diskConnected = "com.ttttt.dmsa.diskConnected"
        static let diskDisconnected = "com.ttttt.dmsa.diskDisconnected"

        /// 全局状态变更
        static let stateChanged = "com.ttttt.dmsa.notification.stateChanged"
        /// 服务启动完成，下发配置
        static let serviceReady = "com.ttttt.dmsa.notification.serviceReady"
        /// 配置已更新（Service → App）
        static let configUpdated = "com.ttttt.dmsa.notification.configUpdated"
        /// 同步进度实时更新
        static let syncProgress = "com.ttttt.dmsa.notification.syncProgress"
        /// 同步状态变更（开始/完成/失败）
        static let syncStatusChanged = "com.ttttt.dmsa.notification.syncStatusChanged"
        /// 索引构建完成
        static let indexReady = "com.ttttt.dmsa.notification.indexReady"
    }
}
