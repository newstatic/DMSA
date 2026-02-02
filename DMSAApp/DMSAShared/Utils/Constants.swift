import Foundation

/// App constants
public enum Constants {
    /// Bundle IDs
    public static let bundleId = "com.ttttt.dmsa"
    public static let serviceId = "com.ttttt.dmsa.service"  // Unified service ID

    /// Legacy service IDs (deprecated, for migration reference only)
    @available(*, deprecated, message: "Use serviceId instead")
    public static let vfsServiceId = "com.ttttt.dmsa.vfs"
    @available(*, deprecated, message: "Use serviceId instead")
    public static let syncServiceId = "com.ttttt.dmsa.sync"
    @available(*, deprecated, message: "Use serviceId instead")
    public static let helperServiceId = "com.ttttt.dmsa.helper"

    /// App name
    public static let appName = "DMSA"
    public static let appFullName = "Delt MACOS Sync App"

    /// Version
    public static let version = "4.7"
    public static let appVersion = version  // Alias for backward compatibility

    /// Service version info
    public enum ServiceVersion {
        /// Service protocol version (for App-Service compatibility check)
        public static let protocolVersion = 1

        /// Service build number (incremented on each code change)
        public static let buildNumber = 20260126

        /// Minimum compatible App version
        public static let minAppVersion = "4.5"

        /// Full version string
        public static var fullVersion: String {
            "\(Constants.version) (build \(buildNumber), protocol v\(protocolVersion))"
        }
    }

    /// XPC service names
    public enum XPCService {
        /// Unified service (VFS + Sync + Privileged)
        public static let service = "com.ttttt.dmsa.service"

        /// Legacy service names (deprecated)
        @available(*, deprecated, message: "Use service instead")
        public static let vfs = "com.ttttt.dmsa.vfs"
        @available(*, deprecated, message: "Use service instead")
        public static let sync = "com.ttttt.dmsa.sync"
        @available(*, deprecated, message: "Use service instead")
        public static let helper = "com.ttttt.dmsa.helper"
    }

    /// Notification names (inter-service communication)
    /// Reference: SERVICE_FLOW/14_DistributedNotifications.md
    public enum Notifications {
        // MARK: - State Notifications
        /// Global state changed
        public static let stateChanged = "com.ttttt.dmsa.notification.stateChanged"
        /// XPC listener started and ready
        public static let xpcReady = "com.ttttt.dmsa.notification.xpcReady"
        /// Service fully ready
        public static let serviceReady = "com.ttttt.dmsa.notification.serviceReady"
        /// Service error
        public static let serviceError = "com.ttttt.dmsa.notification.serviceError"
        /// Component error
        public static let componentError = "com.ttttt.dmsa.notification.componentError"

        // MARK: - Config Notifications
        /// Config status (load/patch)
        public static let configStatus = "com.ttttt.dmsa.notification.configStatus"
        /// Config conflict
        public static let configConflict = "com.ttttt.dmsa.notification.configConflict"
        /// Config changed (legacy compatible)
        public static let configChanged = "com.ttttt.dmsa.notification.configChanged"
        /// Config updated (Service -> App)
        public static let configUpdated = "com.ttttt.dmsa.notification.configUpdated"

        // MARK: - VFS Notifications
        /// VFS mount completed
        public static let vfsMounted = "com.ttttt.dmsa.notification.vfsMounted"
        /// VFS unmount completed
        public static let vfsUnmounted = "com.ttttt.dmsa.notification.vfsUnmounted"

        // MARK: - Index Notifications
        /// Index progress
        public static let indexProgress = "com.ttttt.dmsa.notification.indexProgress"
        /// Index ready
        public static let indexReady = "com.ttttt.dmsa.notification.indexReady"

        // MARK: - Sync Notifications
        /// File written (dirty file)
        public static let fileWritten = "com.ttttt.dmsa.notification.fileWritten"
        /// Sync progress
        public static let syncProgress = "com.ttttt.dmsa.notification.syncProgress"
        /// Sync completed
        public static let syncCompleted = "com.ttttt.dmsa.notification.syncCompleted"
        /// Sync status changed
        public static let syncStatusChanged = "com.ttttt.dmsa.notification.syncStatusChanged"

        // MARK: - Disk Notifications
        /// Disk connected
        public static let diskConnected = "com.ttttt.dmsa.notification.diskConnected"
        /// Disk disconnected
        public static let diskDisconnected = "com.ttttt.dmsa.notification.diskDisconnected"
    }

    /// Paths
    public enum Paths {
        /// Current user's home directory
        /// When Service runs as root, it needs to access the actual user's directory
        private static var userHome: URL {
            // Detect if running as root (Service)
            if getuid() == 0 {
                // Prefer user Home from plist-injected environment variable
                if let userHome = ProcessInfo.processInfo.environment["DMSA_USER_HOME"] {
                    return URL(fileURLWithPath: userHome)
                }
                // Fallback: try from SUDO_USER
                if let sudoUser = ProcessInfo.processInfo.environment["SUDO_USER"],
                   let pw = getpwnam(sudoUser) {
                    return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
                }
                // Last resort: hardcoded
                return URL(fileURLWithPath: "/Users/ttttt")
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }

        /// App support directory
        public static var appSupport: URL {
            userHome.appendingPathComponent("Library/Application Support/DMSA")
        }

        /// Shared data directory (shared between services)
        public static var sharedData: URL {
            appSupport.appendingPathComponent("SharedData")
        }

        /// Config file
        public static var config: URL {
            appSupport.appendingPathComponent("config.json")
        }

        /// Config backup
        public static var configBackup: URL {
            appSupport.appendingPathComponent("config.backup.json")
        }

        /// Database directory
        public static var database: URL {
            appSupport.appendingPathComponent("Database")
        }

        /// Shared state file (inter-service state sync)
        public static var sharedState: URL {
            sharedData.appendingPathComponent("shared_state.json")
        }

        /// Downloads_Local - local storage directory after renaming ~/Downloads
        public static var downloadsLocal: URL {
            userHome.appendingPathComponent("Downloads_Local")
        }

        /// Virtual Downloads - FUSE mount point
        public static var virtualDownloads: URL {
            userHome.appendingPathComponent("Downloads")
        }

        /// Logs directory
        /// When Service runs as root, uses plist-injected user directory
        public static var logs: URL {
            // Detect if running as root (Service)
            if getuid() == 0 {
                // Prefer logs directory from plist-injected environment variable
                if let logsDir = ProcessInfo.processInfo.environment["DMSA_LOGS_DIR"] {
                    return URL(fileURLWithPath: logsDir)
                }
                // Fallback: use userHome
                return userHome.appendingPathComponent("Library/Logs/DMSA")
            }
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DMSA")
        }

        /// Date formatter (log file names)
        private static let logDateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()

        /// Unified service log (today)
        public static var serviceLog: URL {
            let today = logDateFormatter.string(from: Date())
            return logs.appendingPathComponent("service-\(today).log")
        }

        /// App log (today)
        public static var appLog: URL {
            let today = logDateFormatter.string(from: Date())
            return logs.appendingPathComponent("app-\(today).log")
        }

        /// LaunchAgent plist
        public static var launchAgent: URL {
            userHome.appendingPathComponent("Library/LaunchAgents/com.ttttt.dmsa.plist")
        }

        /// Version file directory name
        public static let versionFileName = ".FUSE"

        /// Version database file name
        public static let versionDBFileName = "db.json"
    }

    /// Default config values
    public enum Defaults {
        public static let debounceSeconds: Int = 5
        public static let maxRetryCount: Int = 3
        public static let diskMountDelay: TimeInterval = 2.0
        public static let syncLockTimeout: TimeInterval = 5.0
        public static let writeBackDelay: TimeInterval = 5.0
        public static let xpcConnectionTimeout: TimeInterval = 30.0
        public static let healthCheckInterval: TimeInterval = 60.0
    }

    /// Exclude file patterns
    public static let defaultExcludePatterns: [String] = [
        ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
        ".TemporaryItems", ".Trashes", ".vol",
        "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
        "Thumbs.db", "desktop.ini",
        "*.part", "*.crdownload", "*.download", "*.partial",
        ".FUSE"  // Version file directory
    ]

    /// Path safety whitelist
    /// Uses computed property to correctly resolve user path under root
    public static var allowedPathPrefixes: [String] {
        let home = UserPathManager.shared.userHome
        return [
            home + "/Downloads_Local",
            home + "/Downloads",
            home + "/Documents_Local",
            home + "/Documents",
            "/Volumes/"  // External drives
        ]
    }

    /// Dangerous path blacklist
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
