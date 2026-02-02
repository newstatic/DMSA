import Foundation

/// App constants
enum Constants {
    /// Bundle ID
    static let bundleId = "com.ttttt.dmsa"

    /// App name
    static let appName = "DMSA"
    static let appFullName = "Delt MACOS Sync App"

    /// Version
    static let version = "4.7"

    /// Service version info
    enum ServiceVersion {
        static let protocolVersion = 1
        static let buildNumber = 20260126
        static let minAppVersion = "4.5"
        static var fullVersion: String {
            "\(Constants.version) (build \(buildNumber), protocol v\(protocolVersion))"
        }
    }

    /// Paths
    enum Paths {
        static let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DMSA")

        static let config = appSupport.appendingPathComponent("config.json")
        static let configBackup = appSupport.appendingPathComponent("config.backup.json")
        static let database = appSupport.appendingPathComponent("Database")

        /// Shared data directory
        static var sharedData: URL {
            appSupport.appendingPathComponent("SharedData")
        }

        /// Shared state file
        static var sharedState: URL {
            sharedData.appendingPathComponent("shared_state.json")
        }

        /// Downloads_Local - local storage directory after renaming ~/Downloads
        static let downloadsLocal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads_Local")

        /// Virtual Downloads - FUSE mount point
        static let virtualDownloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")

        static let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DMSA")
        static let logFile = logs.appendingPathComponent("app.log")

        /// Service log (Service runs as root, logs in /var/log/dmsa/)
        static let serviceLogDir = URL(fileURLWithPath: "/var/log/dmsa")
        static let serviceLog = serviceLogDir.appendingPathComponent("service.log")

        static let launchAgent = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.ttttt.dmsa.plist")
    }

    /// Default config values
    enum Defaults {
        static let debounceSeconds: Int = 5
        static let maxRetryCount: Int = 3
        static let diskMountDelay: TimeInterval = 2.0
        static let syncLockTimeout: TimeInterval = 5.0
        static let writeBackDelay: TimeInterval = 5.0
    }

    /// Exclude file patterns
    static let defaultExcludePatterns: [String] = [
        ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
        ".TemporaryItems", ".Trashes", ".vol",
        "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
        "Thumbs.db", "desktop.ini",
        "*.part", "*.crdownload", "*.download", "*.partial"
    ]

    /// XPC Service Identifier (unified service)
    enum XPCService {
        /// Unified service (v4.1 - VFS + Sync + Privileged)
        static let service = "com.ttttt.dmsa.service"
    }

    /// Distributed notification names
    enum Notifications {
        static let vfsMounted = "com.ttttt.dmsa.vfs.mounted"
        static let vfsUnmounted = "com.ttttt.dmsa.vfs.unmounted"
        static let syncCompleted = "com.ttttt.dmsa.sync.completed"
        static let syncFailed = "com.ttttt.dmsa.sync.failed"
        static let fileWritten = "com.ttttt.dmsa.vfs.fileWritten"
        static let configChanged = "com.ttttt.dmsa.configChanged"
        static let diskConnected = "com.ttttt.dmsa.diskConnected"
        static let diskDisconnected = "com.ttttt.dmsa.diskDisconnected"

        /// Global state changed
        static let stateChanged = "com.ttttt.dmsa.notification.stateChanged"
        /// Service startup complete, push config
        static let serviceReady = "com.ttttt.dmsa.notification.serviceReady"
        /// Config updated (Service -> App)
        static let configUpdated = "com.ttttt.dmsa.notification.configUpdated"
        /// Sync progress real-time update
        static let syncProgress = "com.ttttt.dmsa.notification.syncProgress"
        /// Sync status changed (start/complete/fail)
        static let syncStatusChanged = "com.ttttt.dmsa.notification.syncStatusChanged"
        /// Index build complete
        static let indexReady = "com.ttttt.dmsa.notification.indexReady"
    }
}
