import Foundation

// MARK: - Unified Service Error

/// Unified service error type
/// Reference: SERVICE_FLOW/15_ErrorHandling.md
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

// MARK: - Error Code Definitions

extension DMSAServiceError {

    // MARK: - XPC Errors (1xxx)

    /// XPC listener start failed
    public static func xpcListenFailed(reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 1001,
            message: reason ?? "XPC listener start failed",
            component: "XPC",
            recoverable: false
        )
    }

    /// XPC connection validation failed
    public static func xpcConnectionInvalid(pid: Int32? = nil) -> DMSAServiceError {
        var context: [String: String]? = nil
        if let pid = pid {
            context = ["pid": String(pid)]
        }
        return DMSAServiceError(
            code: 1002,
            message: "XPC connection validation failed",
            component: "XPC",
            recoverable: true,
            context: context
        )
    }

    /// XPC call timeout
    public static func xpcTimeout(method: String? = nil) -> DMSAServiceError {
        var context: [String: String]? = nil
        if let method = method {
            context = ["method": method]
        }
        return DMSAServiceError(
            code: 1003,
            message: "XPC call timeout",
            component: "XPC",
            recoverable: true,
            context: context
        )
    }

    // MARK: - Config Errors (2xxx)

    /// Config file not found
    public static func configNotFound(path: String? = nil) -> DMSAServiceError {
        var context: [String: String]? = nil
        if let path = path {
            context = ["path": path]
        }
        return DMSAServiceError(
            code: 2001,
            message: "Config file not found",
            component: "Config",
            recoverable: true,
            context: context
        )
    }

    /// JSON parse failed
    public static func configParseFailed(reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 2002,
            message: reason ?? "Config file parse failed",
            component: "Config",
            recoverable: true
        )
    }

    /// Config validation failed
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
            message: reason ?? "Config validation failed",
            component: "Config",
            recoverable: true,
            context: context
        )
    }

    /// Config conflict
    public static func configConflict(type: String, items: [String]) -> DMSAServiceError {
        DMSAServiceError(
            code: 2004,
            message: "Config conflict: \(type)",
            component: "Config",
            recoverable: true,
            context: ["type": type, "items": items.joined(separator: ", ")]
        )
    }

    // MARK: - VFS Errors (3xxx)

    /// macFUSE not installed
    public static func vfsFuseNotInstalled() -> DMSAServiceError {
        DMSAServiceError(
            code: 3001,
            message: "macFUSE not installed",
            component: "VFS",
            recoverable: false
        )
    }

    /// macFUSE version too old
    public static func vfsFuseVersion(required: String, current: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 3002,
            message: "macFUSE version too old, requires \(required), current \(current)",
            component: "VFS",
            recoverable: false,
            context: ["required": required, "current": current]
        )
    }

    /// Mount failed
    public static func vfsMountFailed(path: String, reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 3003,
            message: reason ?? "Mount failed: \(path)",
            component: "VFS",
            recoverable: true,
            context: ["path": path]
        )
    }

    /// Insufficient permissions
    public static func vfsPermission(path: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 3004,
            message: "Insufficient permissions: \(path)",
            component: "VFS",
            recoverable: false,
            context: ["path": path]
        )
    }

    /// Mount point busy
    public static func vfsMountBusy(path: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 3005,
            message: "Mount point busy: \(path)",
            component: "VFS",
            recoverable: true,
            context: ["path": path]
        )
    }

    // MARK: - Index Errors (4xxx)

    /// Directory scan failed
    public static func indexScanFailed(path: String, reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 4001,
            message: reason ?? "Directory scan failed: \(path)",
            component: "Index",
            recoverable: true,
            context: ["path": path]
        )
    }

    /// Directory access permission denied
    public static func indexPermission(path: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 4002,
            message: "Directory access permission denied: \(path)",
            component: "Index",
            recoverable: false,
            context: ["path": path]
        )
    }

    /// Index save failed
    public static func indexSaveFailed(reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 4003,
            message: reason ?? "Index save failed",
            component: "Index",
            recoverable: true
        )
    }

    // MARK: - Sync Errors (5xxx)

    /// Source directory unavailable
    public static func syncSourceUnavailable(path: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 5001,
            message: "Source directory unavailable: \(path)",
            component: "Sync",
            recoverable: true,
            context: ["path": path]
        )
    }

    /// Target read-only
    public static func syncTargetReadonly(path: String) -> DMSAServiceError {
        DMSAServiceError(
            code: 5002,
            message: "Target read-only: \(path)",
            component: "Sync",
            recoverable: true,
            context: ["path": path]
        )
    }

    /// File conflict
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
            message: "File conflict: \(file)",
            component: "Sync",
            recoverable: true,
            context: context
        )
    }

    /// Disk space insufficient
    public static func syncDiskFull(path: String, required: Int64, available: Int64) -> DMSAServiceError {
        DMSAServiceError(
            code: 5004,
            message: "Insufficient disk space",
            component: "Sync",
            recoverable: true,
            context: [
                "path": path,
                "required": String(required),
                "available": String(available)
            ]
        )
    }

    // MARK: - Database Errors (6xxx)

    /// Database open failed
    public static func dbOpenFailed(reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 6001,
            message: reason ?? "Database open failed",
            component: "Database",
            recoverable: true
        )
    }

    /// Database corrupted
    public static func dbCorrupted() -> DMSAServiceError {
        DMSAServiceError(
            code: 6002,
            message: "Database corrupted",
            component: "Database",
            recoverable: true
        )
    }

    /// Write failed
    public static func dbWriteFailed(reason: String? = nil) -> DMSAServiceError {
        DMSAServiceError(
            code: 6003,
            message: reason ?? "Database write failed",
            component: "Database",
            recoverable: true
        )
    }
}

// MARK: - LocalizedError Support

extension DMSAServiceError: LocalizedError {
    public var errorDescription: String? {
        return "[\(code)] \(message)"
    }

    public var failureReason: String? {
        if let component = component {
            return "Component: \(component)"
        }
        return nil
    }

    public var recoverySuggestion: String? {
        if recoverable {
            return "This error can be auto-recovered, please retry later"
        } else {
            return "This error requires manual intervention"
        }
    }
}

// MARK: - Error Classification

extension DMSAServiceError {
    /// Error category
    public enum Category: String {
        case xpc = "XPC"
        case config = "Config"
        case vfs = "VFS"
        case index = "Index"
        case sync = "Sync"
        case database = "Database"
        case unknown = "Unknown"
    }

    /// Get error category
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

    /// Whether fatal error (cannot auto-recover)
    public var isFatal: Bool {
        switch code {
        case 1001,  // XPC listener start failed
             3001,  // macFUSE not installed
             3002,  // macFUSE version too old
             3004,  // VFS permission denied
             4002:  // Index directory permission denied
            return true
        default:
            return !recoverable
        }
    }
}
