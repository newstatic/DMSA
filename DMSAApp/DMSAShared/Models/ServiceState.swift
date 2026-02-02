import Foundation

// MARK: - Global Service State

/// Service global state enum
/// Reference: SERVICE_FLOW/01_ServiceStateDefinition.md
public enum ServiceState: Int, Codable, Sendable, CaseIterable {
    case starting       = 0   // Process starting
    case xpcReady       = 1   // XPC listener ready, accepting connections
    case vfsMounting    = 2   // FUSE mounting in progress
    case vfsBlocked     = 3   // FUSE mounted, index not ready, access denied
    case indexing       = 4   // Building file index
    case ready          = 5   // Index complete, VFS accessible
    case running        = 6   // Fully running, scheduler started
    case shuttingDown   = 7   // Shutting down
    case error          = 99  // Error state

    /// State name (for logs and UI display)
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

    /// Localized description
    public var localizedDescription: String {
        switch self {
        case .starting:     return "Service Starting"
        case .xpcReady:     return "XPC Ready"
        case .vfsMounting:  return "Mounting File System"
        case .vfsBlocked:   return "Preparing"
        case .indexing:     return "Building Index"
        case .ready:        return "Ready"
        case .running:      return "Running"
        case .shuttingDown: return "Shutting Down"
        case .error:        return "Error"
        }
    }

    /// Whether App operations are allowed
    public var allowsOperations: Bool {
        switch self {
        case .ready, .running:
            return true
        default:
            return false
        }
    }

    /// Whether config read/write is allowed
    public var allowsConfigAccess: Bool {
        switch self {
        case .starting, .shuttingDown:
            return false
        default:
            return true
        }
    }

    /// Whether status queries are allowed
    public var allowsStatusQuery: Bool {
        return self != .shuttingDown
    }

    /// Whether in startup phase
    public var isStartingPhase: Bool {
        switch self {
        case .starting, .xpcReady, .vfsMounting, .vfsBlocked, .indexing:
            return true
        default:
            return false
        }
    }

    /// Whether in normal running state
    public var isNormal: Bool {
        switch self {
        case .ready, .running:
            return true
        default:
            return false
        }
    }
}

// MARK: - Component State

/// Component state enum
/// Reference: SERVICE_FLOW/01_ServiceStateDefinition.md
public enum ComponentState: Int, Codable, Sendable, CaseIterable {
    case notStarted = 0   // Not started
    case starting   = 1   // Starting
    case ready      = 2   // Ready
    case busy       = 3   // Busy (executing task)
    case paused     = 4   // Paused
    case error      = 99  // Error

    /// State name
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

    /// Log formatted name (fixed width)
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

// MARK: - Component Identifier

/// Service component identifier
public enum ServiceComponent: String, Codable, Sendable, CaseIterable {
    case main       = "Main"      // Main process
    case xpc        = "XPC"       // XPC listener
    case config     = "Config"    // Config manager
    case vfs        = "VFS"       // Virtual file system
    case index      = "Index"     // Index manager
    case sync       = "Sync"      // Sync engine
    case eviction   = "Evict"     // Eviction manager
    case database   = "DB"        // Database

    /// Log formatted name (fixed width)
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

// MARK: - Component Error Info

/// Component error information
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

// MARK: - Component State Info

/// Component full state information
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

// MARK: - Component Metrics

/// Component performance metrics
public struct ComponentMetrics: Codable, Sendable {
    public var processedCount: Int = 0
    public var errorCount: Int = 0
    public var lastOperationDuration: TimeInterval = 0
    public var averageOperationDuration: TimeInterval = 0

    public init() {}
}

// MARK: - Service Operation Type

/// Service operation type (for permission checks)
public enum ServiceOperation: String, Sendable {
    case statusQuery        // Status query
    case configRead         // Config read
    case configWrite        // Config write
    case vfsMount           // VFS mount
    case vfsUnmount         // VFS unmount
    case syncStart          // Start sync
    case syncPause          // Pause sync
    case evictionTrigger    // Trigger eviction
    case fileOperation      // File operation
}
