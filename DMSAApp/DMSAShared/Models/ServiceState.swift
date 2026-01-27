import Foundation

// MARK: - 全局服务状态

/// 服务全局状态枚举
/// 参考文档: SERVICE_FLOW/01_服务状态定义.md
public enum ServiceState: Int, Codable, Sendable, CaseIterable {
    case starting       = 0   // 进程启动中
    case xpcReady       = 1   // XPC 监听就绪，可接受连接
    case vfsMounting    = 2   // FUSE 挂载进行中
    case vfsBlocked     = 3   // FUSE 已挂载，索引未就绪，拒绝访问
    case indexing       = 4   // 正在构建文件索引
    case ready          = 5   // 索引完成，VFS 可正常访问
    case running        = 6   // 完全运行，调度器已启动
    case shuttingDown   = 7   // 正在关闭
    case error          = 99  // 错误状态

    /// 状态名称 (用于日志和 UI 显示)
    public var name: String {
        switch self {
        case .starting:     return "STARTING"
        case .xpcReady:     return "XPC_READY"
        case .vfsMounting:  return "VFS_MOUNTING"
        case .vfsBlocked:   return "VFS_BLOCKED"
        case .indexing:     return "INDEXING"
        case .ready:        return "READY"
        case .running:      return "RUNNING"
        case .shuttingDown: return "SHUTTING_DOWN"
        case .error:        return "ERROR"
        }
    }

    /// 中文描述
    public var localizedDescription: String {
        switch self {
        case .starting:     return "服务启动中"
        case .xpcReady:     return "XPC 就绪"
        case .vfsMounting:  return "挂载文件系统中"
        case .vfsBlocked:   return "准备就绪中"
        case .indexing:     return "构建索引中"
        case .ready:        return "就绪"
        case .running:      return "运行中"
        case .shuttingDown: return "正在关闭"
        case .error:        return "错误"
        }
    }

    /// 是否允许 App 执行操作
    public var allowsOperations: Bool {
        switch self {
        case .ready, .running:
            return true
        default:
            return false
        }
    }

    /// 是否允许配置读写
    public var allowsConfigAccess: Bool {
        switch self {
        case .starting, .shuttingDown:
            return false
        default:
            return true
        }
    }

    /// 是否允许状态查询
    public var allowsStatusQuery: Bool {
        return self != .shuttingDown
    }

    /// 是否为启动过程中的状态
    public var isStartingPhase: Bool {
        switch self {
        case .starting, .xpcReady, .vfsMounting, .vfsBlocked, .indexing:
            return true
        default:
            return false
        }
    }

    /// 是否为正常运行状态
    public var isNormal: Bool {
        switch self {
        case .ready, .running:
            return true
        default:
            return false
        }
    }
}

// MARK: - 组件状态

/// 组件状态枚举
/// 参考文档: SERVICE_FLOW/01_服务状态定义.md
public enum ComponentState: Int, Codable, Sendable, CaseIterable {
    case notStarted = 0   // 未启动
    case starting   = 1   // 启动中
    case ready      = 2   // 就绪
    case busy       = 3   // 忙碌中 (正在执行任务)
    case paused     = 4   // 暂停
    case error      = 99  // 错误

    /// 状态名称
    public var name: String {
        switch self {
        case .notStarted: return "notStarted"
        case .starting:   return "starting"
        case .ready:      return "ready"
        case .busy:       return "busy"
        case .paused:     return "paused"
        case .error:      return "error"
        }
    }

    /// 日志格式化名称 (固定宽度)
    public var logName: String {
        switch self {
        case .notStarted: return "--     "
        case .starting:   return "starting"
        case .ready:      return "ready  "
        case .busy:       return "busy   "
        case .paused:     return "paused "
        case .error:      return "error  "
        }
    }
}

// MARK: - 组件标识

/// 服务组件标识
public enum ServiceComponent: String, Codable, Sendable, CaseIterable {
    case main       = "Main"      // 主进程
    case xpc        = "XPC"       // XPC 监听器
    case config     = "Config"    // 配置管理
    case vfs        = "VFS"       // 虚拟文件系统
    case index      = "Index"     // 索引管理
    case sync       = "Sync"      // 同步引擎
    case eviction   = "Evict"     // 淘汰管理
    case database   = "DB"        // 数据库

    /// 日志格式化名称 (固定宽度)
    public var logName: String {
        switch self {
        case .main:     return "Main  "
        case .xpc:      return "XPC   "
        case .config:   return "Config"
        case .vfs:      return "VFS   "
        case .index:    return "Index "
        case .sync:     return "Sync  "
        case .eviction: return "Evict "
        case .database: return "DB    "
        }
    }
}

// MARK: - 组件错误信息

/// 组件错误信息
public struct ComponentError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let timestamp: Date
    public let recoverable: Bool
    public let context: [String: String]?

    public init(code: Int, message: String, recoverable: Bool = true, context: [String: String]? = nil) {
        self.code = code
        self.message = message
        self.timestamp = Date()
        self.recoverable = recoverable
        self.context = context
    }
}

// MARK: - 组件状态信息

/// 组件完整状态信息
public struct ComponentStateInfo: Codable, Sendable {
    public let name: String
    public var state: ComponentState
    public var lastUpdated: Date
    public var error: ComponentError?
    public var metrics: ComponentMetrics?

    public init(name: String, state: ComponentState = .notStarted) {
        self.name = name
        self.state = state
        self.lastUpdated = Date()
        self.error = nil
        self.metrics = nil
    }

    public var stateName: String {
        return state.name
    }
}

// MARK: - 组件性能指标

/// 组件性能指标
public struct ComponentMetrics: Codable, Sendable {
    public var processedCount: Int = 0
    public var errorCount: Int = 0
    public var lastOperationDuration: TimeInterval = 0
    public var averageOperationDuration: TimeInterval = 0

    public init() {}
}

// MARK: - 服务操作类型

/// 服务操作类型 (用于权限检查)
public enum ServiceOperation: String, Sendable {
    case statusQuery        // 状态查询
    case configRead         // 配置读取
    case configWrite        // 配置写入
    case vfsMount           // VFS 挂载
    case vfsUnmount         // VFS 卸载
    case syncStart          // 启动同步
    case syncPause          // 暂停同步
    case evictionTrigger    // 触发淘汰
    case fileOperation      // 文件操作
}
