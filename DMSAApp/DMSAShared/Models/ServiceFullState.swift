import Foundation

// MARK: - 服务完整状态

/// 服务完整状态结构
/// 参考文档: SERVICE_FLOW/05_状态管理器.md
public struct ServiceFullState: Codable, Sendable {

    // MARK: - 全局状态

    /// 全局服务状态
    public var globalState: ServiceState

    /// 全局状态名称
    public var globalStateName: String {
        return globalState.name
    }

    // MARK: - 组件状态

    /// 各组件状态
    public var components: [String: ComponentStateInfo]

    // MARK: - 配置状态

    /// 配置状态
    public var config: ConfigStatus

    // MARK: - 通知

    /// 待发送通知数量
    public var pendingNotifications: Int

    // MARK: - 时间信息

    /// 服务启动时间
    public var startTime: Date

    /// 运行时长 (秒)
    public var uptime: TimeInterval {
        return Date().timeIntervalSince(startTime)
    }

    // MARK: - 错误信息

    /// 最后一个错误
    public var lastError: ServiceErrorInfo?

    // MARK: - 版本信息

    /// 服务版本
    public var version: String

    /// 协议版本
    public var protocolVersion: Int

    // MARK: - 初始化

    public init(
        globalState: ServiceState = .starting,
        components: [String: ComponentStateInfo] = [:],
        config: ConfigStatus = ConfigStatus(),
        pendingNotifications: Int = 0,
        startTime: Date = Date(),
        lastError: ServiceErrorInfo? = nil,
        version: String = "4.9",
        protocolVersion: Int = 1
    ) {
        self.globalState = globalState
        self.components = components
        self.config = config
        self.pendingNotifications = pendingNotifications
        self.startTime = startTime
        self.lastError = lastError
        self.version = version
        self.protocolVersion = protocolVersion
    }

    // MARK: - 便捷方法

    /// 获取指定组件状态
    public func componentState(for component: ServiceComponent) -> ComponentStateInfo? {
        return components[component.rawValue]
    }

    /// 是否所有核心组件都就绪
    public var allCoreComponentsReady: Bool {
        let coreComponents: [ServiceComponent] = [.xpc, .config, .vfs, .index]
        return coreComponents.allSatisfy { component in
            components[component.rawValue]?.state == .ready
        }
    }

    /// 是否有任何组件处于错误状态
    public var hasComponentError: Bool {
        return components.values.contains { $0.state == .error }
    }

    /// 获取所有错误的组件
    public var errorComponents: [ComponentStateInfo] {
        return components.values.filter { $0.state == .error }
    }
}

// MARK: - 配置状态

/// 配置状态
public struct ConfigStatus: Codable, Sendable {
    /// 配置是否有效
    public var isValid: Bool

    /// 配置是否被修补 (缺失字段使用默认值)
    public var isPatched: Bool

    /// 被修补的字段列表
    public var patchedFields: [String]?

    /// 配置冲突列表
    public var conflicts: [ConfigConflict]?

    /// 配置加载时间
    public var loadedAt: Date?

    /// 配置文件路径
    public var configPath: String?

    public init(
        isValid: Bool = false,
        isPatched: Bool = false,
        patchedFields: [String]? = nil,
        conflicts: [ConfigConflict]? = nil,
        loadedAt: Date? = nil,
        configPath: String? = nil
    ) {
        self.isValid = isValid
        self.isPatched = isPatched
        self.patchedFields = patchedFields
        self.conflicts = conflicts
        self.loadedAt = loadedAt
        self.configPath = configPath
    }

    /// 是否需要用户处理冲突
    public var requiresUserAction: Bool {
        return conflicts?.contains { $0.requiresUserAction } ?? false
    }
}

// MARK: - 配置冲突

/// 配置冲突信息
public struct ConfigConflict: Codable, Sendable {
    /// 冲突类型
    public let type: ConfigConflictType

    /// 受影响的项目
    public let affectedItems: [String]

    /// 自动解决方案描述
    public let resolution: String?

    /// 是否需要用户手动处理
    public let requiresUserAction: Bool

    /// 冲突详情
    public let details: String?

    public init(
        type: ConfigConflictType,
        affectedItems: [String],
        resolution: String? = nil,
        requiresUserAction: Bool = false,
        details: String? = nil
    ) {
        self.type = type
        self.affectedItems = affectedItems
        self.resolution = resolution
        self.requiresUserAction = requiresUserAction
        self.details = details
    }
}

/// 配置冲突类型
public enum ConfigConflictType: String, Codable, Sendable {
    case multipleExternalDirs = "MULTIPLE_EXTERNAL_DIRS"  // 多个 syncPair 使用同一 EXTERNAL_DIR
    case overlappingLocal = "OVERLAPPING_LOCAL"           // LOCAL_DIR 有重叠
    case diskNotFound = "DISK_NOT_FOUND"                  // 引用的 disk 不存在
    case circularSync = "CIRCULAR_SYNC"                   // 循环同步检测
    case invalidPath = "INVALID_PATH"                     // 无效路径
    case permissionDenied = "PERMISSION_DENIED"           // 权限不足

    public var localizedDescription: String {
        switch self {
        case .multipleExternalDirs:
            return "多个同步对使用相同的外部目录"
        case .overlappingLocal:
            return "本地目录存在重叠"
        case .diskNotFound:
            return "引用的磁盘配置不存在"
        case .circularSync:
            return "检测到循环同步"
        case .invalidPath:
            return "路径无效"
        case .permissionDenied:
            return "权限不足"
        }
    }
}

// MARK: - 服务错误信息

/// 服务错误信息 (用于 ServiceFullState)
public struct ServiceErrorInfo: Codable, Sendable {
    public let code: Int
    public let message: String
    public let component: String?
    public let timestamp: Date
    public let recoverable: Bool

    public init(code: Int, message: String, component: String? = nil, recoverable: Bool = true) {
        self.code = code
        self.message = message
        self.component = component
        self.timestamp = Date()
        self.recoverable = recoverable
    }

    public init(from error: ComponentError, component: String) {
        self.code = error.code
        self.message = error.message
        self.component = component
        self.timestamp = error.timestamp
        self.recoverable = error.recoverable
    }
}

// MARK: - 索引进度

/// 索引构建进度
public struct IndexProgress: Codable, Sendable {
    public var syncPairId: String
    public var phase: IndexPhase
    public var progress: Double  // 0.0 - 1.0
    public var scannedFiles: Int
    public var totalFiles: Int?
    public var currentPath: String?
    public var errors: [String]

    public init(syncPairId: String) {
        self.syncPairId = syncPairId
        self.phase = .idle
        self.progress = 0
        self.scannedFiles = 0
        self.totalFiles = nil
        self.currentPath = nil
        self.errors = []
    }
}

/// 索引构建阶段
public enum IndexPhase: String, Codable, Sendable {
    case idle = "idle"
    case scanningLocal = "scanning_local"
    case scanningExternal = "scanning_external"
    case merging = "merging"
    case saving = "saving"
    case completed = "completed"
    case failed = "failed"

    public var localizedDescription: String {
        switch self {
        case .idle:              return "空闲"
        case .scanningLocal:     return "扫描本地目录"
        case .scanningExternal:  return "扫描外部目录"
        case .merging:           return "合并索引"
        case .saving:            return "保存索引"
        case .completed:         return "完成"
        case .failed:            return "失败"
        }
    }
}

// MARK: - XPC 连接状态

/// XPC 连接状态
public enum XPCConnectionState: String, Codable, Sendable {
    case disconnected = "disconnected"
    case connecting = "connecting"
    case connected = "connected"
    case interrupted = "interrupted"
    case failed = "failed"
}
