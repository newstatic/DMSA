import Foundation

/// 应用常量
public enum Constants {
    /// Bundle IDs
    public static let bundleId = "com.ttttt.dmsa"
    public static let serviceId = "com.ttttt.dmsa.service"  // 统一服务 ID

    /// 旧版服务 ID (已废弃，仅供迁移参考)
    @available(*, deprecated, message: "使用 serviceId 替代")
    public static let vfsServiceId = "com.ttttt.dmsa.vfs"
    @available(*, deprecated, message: "使用 serviceId 替代")
    public static let syncServiceId = "com.ttttt.dmsa.sync"
    @available(*, deprecated, message: "使用 serviceId 替代")
    public static let helperServiceId = "com.ttttt.dmsa.helper"

    /// 应用名称
    public static let appName = "DMSA"
    public static let appFullName = "Delt MACOS Sync App"

    /// 版本
    public static let version = "4.0"

    /// XPC 服务名称
    public enum XPCService {
        /// 统一服务 (VFS + Sync + Privileged)
        public static let service = "com.ttttt.dmsa.service"

        /// 旧版服务名称 (已废弃)
        @available(*, deprecated, message: "使用 service 替代")
        public static let vfs = "com.ttttt.dmsa.vfs"
        @available(*, deprecated, message: "使用 service 替代")
        public static let sync = "com.ttttt.dmsa.sync"
        @available(*, deprecated, message: "使用 service 替代")
        public static let helper = "com.ttttt.dmsa.helper"
    }

    /// 通知名称 (服务间通信)
    public enum Notifications {
        public static let fileWritten = "com.ttttt.dmsa.notification.fileWritten"
        public static let syncCompleted = "com.ttttt.dmsa.notification.syncCompleted"
        public static let syncProgress = "com.ttttt.dmsa.notification.syncProgress"
        public static let diskConnected = "com.ttttt.dmsa.notification.diskConnected"
        public static let diskDisconnected = "com.ttttt.dmsa.notification.diskDisconnected"
        public static let configChanged = "com.ttttt.dmsa.notification.configChanged"
        public static let vfsMounted = "com.ttttt.dmsa.notification.vfsMounted"
        public static let vfsUnmounted = "com.ttttt.dmsa.notification.vfsUnmounted"
    }

    /// 路径
    public enum Paths {
        /// 应用支持目录
        public static var appSupport: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/DMSA")
        }

        /// 共享数据目录 (服务间共享)
        public static var sharedData: URL {
            appSupport.appendingPathComponent("SharedData")
        }

        /// 配置文件
        public static var config: URL {
            appSupport.appendingPathComponent("config.json")
        }

        /// 配置备份
        public static var configBackup: URL {
            appSupport.appendingPathComponent("config.backup.json")
        }

        /// 数据库目录
        public static var database: URL {
            appSupport.appendingPathComponent("Database")
        }

        /// 共享状态文件 (服务间状态同步)
        public static var sharedState: URL {
            sharedData.appendingPathComponent("shared_state.json")
        }

        /// Downloads_Local - 原始 ~/Downloads 重命名后的本地存储目录
        public static var downloadsLocal: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads_Local")
        }

        /// 虚拟 Downloads - FUSE 挂载点
        public static var virtualDownloads: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")
        }

        /// 日志目录
        public static var logs: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DMSA")
        }

        /// 统一服务日志
        public static var serviceLog: URL {
            logs.appendingPathComponent("service.log")
        }

        /// VFS 服务日志 (已废弃)
        @available(*, deprecated, message: "使用 serviceLog 替代")
        public static var vfsLog: URL {
            logs.appendingPathComponent("vfs.log")
        }

        /// Sync 服务日志 (已废弃)
        @available(*, deprecated, message: "使用 serviceLog 替代")
        public static var syncLog: URL {
            logs.appendingPathComponent("sync.log")
        }

        /// Helper 服务日志 (已废弃)
        @available(*, deprecated, message: "使用 serviceLog 替代")
        public static var helperLog: URL {
            logs.appendingPathComponent("helper.log")
        }

        /// 应用日志
        public static var appLog: URL {
            logs.appendingPathComponent("app.log")
        }

        /// LaunchAgent plist
        public static var launchAgent: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/com.ttttt.dmsa.plist")
        }

        /// 版本文件目录名
        public static let versionFileName = ".FUSE"

        /// 版本数据库文件名
        public static let versionDBFileName = "db.json"
    }

    /// 默认配置值
    public enum Defaults {
        public static let debounceSeconds: Int = 5
        public static let maxRetryCount: Int = 3
        public static let diskMountDelay: TimeInterval = 2.0
        public static let syncLockTimeout: TimeInterval = 5.0
        public static let writeBackDelay: TimeInterval = 5.0
        public static let xpcConnectionTimeout: TimeInterval = 30.0
        public static let healthCheckInterval: TimeInterval = 60.0
    }

    /// 排除文件模式
    public static let defaultExcludePatterns: [String] = [
        ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
        ".TemporaryItems", ".Trashes", ".vol",
        "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
        "Thumbs.db", "desktop.ini",
        "*.part", "*.crdownload", "*.download", "*.partial",
        ".FUSE"  // 版本文件目录
    ]

    /// 路径安全白名单
    public static let allowedPathPrefixes: [String] = [
        NSHomeDirectory() + "/Downloads_Local",
        NSHomeDirectory() + "/Downloads",
        NSHomeDirectory() + "/Documents_Local",
        NSHomeDirectory() + "/Documents",
        "/Volumes/"  // 外置硬盘
    ]

    /// 危险路径黑名单
    public static let forbiddenPaths: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/etc",
        "/var",
        "/Library/System",
        "/private"
    ]
}
