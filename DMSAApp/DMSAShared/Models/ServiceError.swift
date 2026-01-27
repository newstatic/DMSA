import Foundation

// MARK: - 统一服务错误

/// 统一服务错误类型
/// 参考文档: SERVICE_FLOW/15_错误处理.md
public struct DMSAServiceError: Error, Codable, Sendable {
    public let code: Int
    public let message: String
    public let component: String?
    public let timestamp: Date
    public let recoverable: Bool
    public let context: [String: String]?

    public init(
        code: Int,
        message: String,
        component: String? = nil,
        recoverable: Bool = true,
        context: [String: String]? = nil
    ) {
        self.code = code
        self.message = message
        self.component = component
        self.timestamp = Date()
        self.recoverable = recoverable
        self.context = context
    }
}

// MARK: - 错误码定义

extension DMSAServiceError {

    // MARK: - XPC 错误 (1xxx)

    /// XPC 监听器启动失败
    public static func xpcListenFailed(reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 1001,
            message: reason ?? "XPC 监听器启动失败",
            component: "XPC",
            recoverable: false
        )
    }

    /// XPC 连接验证失败
    public static func xpcConnectionInvalid(pid: Int32? = nil) -> DMSAServiceError {
        var context: [String: String]? = nil
        if let pid = pid {
            context = ["pid": String(pid)]
        }
        return DMSAServiceError(
            code: 1002,
            message: "XPC 连接验证失败",
            component: "XPC",
            recoverable: true,
            context: context
        )
    }

    /// XPC 调用超时
    public static func xpcTimeout(method: String? = nil) -> DMSAServiceError {
        var context: [String: String]? = nil
        if let method = method {
            context = ["method": method]
        }
        return DMSAServiceError(
            code: 1003,
            message: "XPC 调用超时",
            component: "XPC",
            recoverable: true,
            context: context
        )
    }

    // MARK: - 配置错误 (2xxx)

    /// 配置文件不存在
    public static func configNotFound(path: String? = nil) -> DMSAServiceError {
        var context: [String: String]? = nil
        if let path = path {
            context = ["path": path]
        }
        return DMSAServiceError(
            code: 2001,
            message: "配置文件不存在",
            component: "Config",
            recoverable: true,
            context: context
        )
    }

    /// JSON 解析失败
    public static func configParseFailed(reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 2002,
            message: reason ?? "配置文件解析失败",
            component: "Config",
            recoverable: true
        )
    }

    /// 配置验证失败
    public static func configInvalid(field: String? = nil, reason: String? = nil) -> DMSAServiceError {
        var context: [String: String]? = nil
        if let field = field {
            context = ["field": field]
            if let reason = reason {
                context?["reason"] = reason
            }
        }
        return DMSAServiceError(
            code: 2003,
            message: reason ?? "配置验证失败",
            component: "Config",
            recoverable: true,
            context: context
        )
    }

    /// 配置冲突
    public static func configConflict(type: String, items: [String]) -> DMSAServiceError {
        DMSAServiceError(
            code: 2004,
            message: "配置冲突: \(type)",
            component: "Config",
            recoverable: true,
            context: ["type": type, "items": items.joined(separator: ", ")]
        )
    }

    // MARK: - VFS 错误 (3xxx)

    /// macFUSE 未安装
    public static func vfsFuseNotInstalled() -> DMSAServiceError {
        DMSAServiceError(
            code: 3001,
            message: "macFUSE 未安装",
            component: "VFS",
            recoverable: false
        )
    }

    /// macFUSE 版本过低
    public static func vfsFuseVersion(required: String, current: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 3002,
            message: "macFUSE 版本过低，需要 \(required)，当前 \(current)",
            component: "VFS",
            recoverable: false,
            context: ["required": required, "current": current]
        )
    }

    /// 挂载失败
    public static func vfsMountFailed(path: String, reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 3003,
            message: reason ?? "挂载失败: \(path)",
            component: "VFS",
            recoverable: true,
            context: ["path": path]
        )
    }

    /// 权限不足
    public static func vfsPermission(path: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 3004,
            message: "权限不足: \(path)",
            component: "VFS",
            recoverable: false,
            context: ["path": path]
        )
    }

    /// 挂载点被占用
    public static func vfsMountBusy(path: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 3005,
            message: "挂载点被占用: \(path)",
            component: "VFS",
            recoverable: true,
            context: ["path": path]
        )
    }

    // MARK: - 索引错误 (4xxx)

    /// 目录扫描失败
    public static func indexScanFailed(path: String, reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 4001,
            message: reason ?? "目录扫描失败: \(path)",
            component: "Index",
            recoverable: true,
            context: ["path": path]
        )
    }

    /// 目录访问权限不足
    public static func indexPermission(path: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 4002,
            message: "目录访问权限不足: \(path)",
            component: "Index",
            recoverable: false,
            context: ["path": path]
        )
    }

    /// 索引保存失败
    public static func indexSaveFailed(reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 4003,
            message: reason ?? "索引保存失败",
            component: "Index",
            recoverable: true
        )
    }

    // MARK: - 同步错误 (5xxx)

    /// 源目录不可访问
    public static func syncSourceUnavailable(path: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 5001,
            message: "源目录不可访问: \(path)",
            component: "Sync",
            recoverable: true,
            context: ["path": path]
        )
    }

    /// 目标只读
    public static func syncTargetReadonly(path: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 5002,
            message: "目标只读: \(path)",
            component: "Sync",
            recoverable: true,
            context: ["path": path]
        )
    }

    /// 文件冲突
    public static func syncConflict(file: String, localTime: Date?, externalTime: Date?) -> DMSAServiceError {
        var context: [String: String] = ["file": file]
        if let localTime = localTime {
            context["localTime"] = ISO8601DateFormatter().string(from: localTime)
        }
        if let externalTime = externalTime {
            context["externalTime"] = ISO8601DateFormatter().string(from: externalTime)
        }
        return DMSAServiceError(
            code: 5003,
            message: "文件冲突: \(file)",
            component: "Sync",
            recoverable: true,
            context: context
        )
    }

    /// 磁盘空间不足
    public static func syncDiskFull(path: String, required: Int64, available: Int64) -> DMSAServiceError {
        DMSAServiceError(
            code: 5004,
            message: "磁盘空间不足",
            component: "Sync",
            recoverable: true,
            context: [
                "path": path,
                "required": String(required),
                "available": String(available)
            ]
        )
    }

    // MARK: - 数据库错误 (6xxx)

    /// 数据库打开失败
    public static func dbOpenFailed(reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 6001,
            message: reason ?? "数据库打开失败",
            component: "Database",
            recoverable: true
        )
    }

    /// 数据库损坏
    public static func dbCorrupted() -> DMSAServiceError {
        DMSAServiceError(
            code: 6002,
            message: "数据库损坏",
            component: "Database",
            recoverable: true
        )
    }

    /// 写入失败
    public static func dbWriteFailed(reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 6003,
            message: reason ?? "数据库写入失败",
            component: "Database",
            recoverable: true
        )
    }
}

// MARK: - LocalizedError 支持

extension DMSAServiceError: LocalizedError {
    public var errorDescription: String? {
        return "[\(code)] \(message)"
    }

    public var failureReason: String? {
        if let component = component {
            return "组件: \(component)"
        }
        return nil
    }

    public var recoverySuggestion: String? {
        if recoverable {
            return "此错误可以自动恢复，请稍后重试"
        } else {
            return "此错误需要手动干预"
        }
    }
}

// MARK: - 错误分类

extension DMSAServiceError {
    /// 错误类别
    public enum Category: String {
        case xpc = "XPC"
        case config = "Config"
        case vfs = "VFS"
        case index = "Index"
        case sync = "Sync"
        case database = "Database"
        case unknown = "Unknown"
    }

    /// 获取错误类别
    public var category: Category {
        switch code {
        case 1000..<2000: return .xpc
        case 2000..<3000: return .config
        case 3000..<4000: return .vfs
        case 4000..<5000: return .index
        case 5000..<6000: return .sync
        case 6000..<7000: return .database
        default: return .unknown
        }
    }

    /// 是否为致命错误 (无法自动恢复)
    public var isFatal: Bool {
        switch code {
        case 1001,  // XPC 监听器启动失败
             3001,  // macFUSE 未安装
             3002,  // macFUSE 版本过低
             3004,  // VFS 权限不足
             4002:  // 索引目录权限不足
            return true
        default:
            return !recoverable
        }
    }
}
