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
    public static let version = "4.7"
    public static let appVersion = version  // 别名，兼容旧代码

    /// 服务版本信息
    public enum ServiceVersion {
        /// 服务协议版本 (用于检测 App 与 Service 兼容性)
        public static let protocolVersion = 1

        /// 服务构建号 (每次代码修改递增)
        public static let buildNumber = 20260126

        /// 最低兼容的 App 版本
        public static let minAppVersion = "4.5"

        /// 完整版本字符串
        public static var fullVersion: String {
            "\(Constants.version) (build \(buildNumber), protocol v\(protocolVersion))"
        }
    }

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
    /// 参考文档: SERVICE_FLOW/14_分布式通知.md
    public enum Notifications {
        // MARK: - 状态通知
        /// 全局状态变更
        public static let stateChanged = "com.ttttt.dmsa.notification.stateChanged"
        /// XPC 监听器启动就绪
        public static let xpcReady = "com.ttttt.dmsa.notification.xpcReady"
        /// 服务完全就绪
        public static let serviceReady = "com.ttttt.dmsa.notification.serviceReady"
        /// 服务错误
        public static let serviceError = "com.ttttt.dmsa.notification.serviceError"
        /// 组件错误
        public static let componentError = "com.ttttt.dmsa.notification.componentError"

        // MARK: - 配置通知
        /// 配置状态 (加载/修补)
        public static let configStatus = "com.ttttt.dmsa.notification.configStatus"
        /// 配置冲突
        public static let configConflict = "com.ttttt.dmsa.notification.configConflict"
        /// 配置变更 (旧版兼容)
        public static let configChanged = "com.ttttt.dmsa.notification.configChanged"
        /// 配置已更新 (Service → App)
        public static let configUpdated = "com.ttttt.dmsa.notification.configUpdated"

        // MARK: - VFS 通知
        /// VFS 挂载完成
        public static let vfsMounted = "com.ttttt.dmsa.notification.vfsMounted"
        /// VFS 卸载完成
        public static let vfsUnmounted = "com.ttttt.dmsa.notification.vfsUnmounted"

        // MARK: - 索引通知
        /// 索引进度
        public static let indexProgress = "com.ttttt.dmsa.notification.indexProgress"
        /// 索引完成
        public static let indexReady = "com.ttttt.dmsa.notification.indexReady"

        // MARK: - 同步通知
        /// 文件写入 (脏文件)
        public static let fileWritten = "com.ttttt.dmsa.notification.fileWritten"
        /// 同步进度
        public static let syncProgress = "com.ttttt.dmsa.notification.syncProgress"
        /// 同步完成
        public static let syncCompleted = "com.ttttt.dmsa.notification.syncCompleted"
        /// 同步状态变更
        public static let syncStatusChanged = "com.ttttt.dmsa.notification.syncStatusChanged"

        // MARK: - 磁盘通知
        /// 磁盘连接
        public static let diskConnected = "com.ttttt.dmsa.notification.diskConnected"
        /// 磁盘断开
        public static let diskDisconnected = "com.ttttt.dmsa.notification.diskDisconnected"
    }

    /// 路径
    public enum Paths {
        /// 当前用户的 home 目录
        /// Service 以 root 运行时，需要访问实际用户的目录
        private static var userHome: URL {
            // 检测是否以 root 身份运行
            if getuid() == 0 {
                // 尝试从环境变量获取真实用户
                if let sudoUser = ProcessInfo.processInfo.environment["SUDO_USER"],
                   let pw = getpwnam(sudoUser) {
                    return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
                }
                // 回退: 获取 UID 1000+ 的第一个用户 (通常是主用户)
                // 简化方案: 硬编码常见路径
                return URL(fileURLWithPath: "/Users/ttttt")
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }

        /// 应用支持目录
        public static var appSupport: URL {
            userHome.appendingPathComponent("Library/Application Support/DMSA")
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
            userHome.appendingPathComponent("Downloads_Local")
        }

        /// 虚拟 Downloads - FUSE 挂载点
        public static var virtualDownloads: URL {
            userHome.appendingPathComponent("Downloads")
        }

        /// 日志目录
        /// 注意: Service 以 root 运行时使用 /var/log/dmsa/
        public static var logs: URL {
            // 检测是否以 root 身份运行
            if getuid() == 0 {
                return URL(fileURLWithPath: "/var/log/dmsa")
            } else {
                return FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/DMSA")
            }
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
            userHome.appendingPathComponent("Library/LaunchAgents/com.ttttt.dmsa.plist")
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
    /// 使用计算属性确保在 root 身份下也能正确获取用户路径
    public static var allowedPathPrefixes: [String] {
        let home = UserPathManager.shared.userHome
        return [
            home + "/Downloads_Local",
            home + "/Downloads",
            home + "/Documents_Local",
            home + "/Documents",
            "/Volumes/"  // 外置硬盘
        ]
    }

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
