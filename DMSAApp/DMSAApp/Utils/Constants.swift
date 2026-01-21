import Foundation

/// 应用常量
enum Constants {
    /// Bundle ID
    static let bundleId = "com.ttttt.dmsa"

    /// 应用名称
    static let appName = "DMSA"
    static let appFullName = "Delt MACOS Sync App"

    /// 版本
    static let version = "2.0"

    /// 路径
    enum Paths {
        static let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DMSA")

        static let config = appSupport.appendingPathComponent("config.json")
        static let configBackup = appSupport.appendingPathComponent("config.backup.json")
        static let localCache = appSupport.appendingPathComponent("LocalCache")
        static let database = appSupport.appendingPathComponent("Database")

        static let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DMSA")
        static let logFile = logs.appendingPathComponent("app.log")

        static let launchAgent = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.ttttt.dmsa.plist")
    }

    /// 默认配置值
    enum Defaults {
        static let maxCacheSize: Int64 = 10 * 1024 * 1024 * 1024  // 10 GB
        static let reserveBuffer: Int64 = 500 * 1024 * 1024       // 500 MB
        static let evictionCheckInterval: Int = 300               // 5 分钟
        static let debounceSeconds: Int = 5
        static let maxRetryCount: Int = 3
        static let diskMountDelay: TimeInterval = 2.0
    }

    /// 排除文件模式
    static let defaultExcludePatterns: [String] = [
        ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
        ".TemporaryItems", ".Trashes", ".vol",
        "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
        "Thumbs.db", "desktop.ini",
        "*.part", "*.crdownload", "*.download", "*.partial"
    ]
}
