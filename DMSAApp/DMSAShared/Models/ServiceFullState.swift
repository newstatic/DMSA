import Foundation

// MARK: - Service Full State

/// Service full state structure
/// Reference: SERVICE_FLOW/05_StateManager.md
public struct ServiceFullState: Codable, Sendable {

    // MARK: - Global State

    /// Global service state
    public var globalState: ServiceState

    /// Global state name
    public var globalStateName: String {
        return globalState.name
    }

    // MARK: - Component State

    /// Component states
    public var components: [String: ComponentStateInfo]

    // MARK: - Config Status

    /// Config status
    public var config: ConfigStatus

    // MARK: - Notifications

    /// Pending notification count
    public var pendingNotifications: Int

    // MARK: - Time Info

    /// Service start time
    public var startTime: Date

    /// Uptime (seconds)
    public var uptime: TimeInterval {
        return Date().timeIntervalSince(startTime)
    }

    // MARK: - Error Info

    /// Last error
    public var lastError: ServiceErrorInfo?

    // MARK: - Version Info

    /// Service version
    public var version: String

    /// Protocol version
    public var protocolVersion: Int

    // MARK: - Initialization

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

    // MARK: - Convenience Methods

    /// Get state for specified component
    public func componentState(for component: ServiceComponent) -> ComponentStateInfo? {
        return components[component.rawValue]
    }

    /// Whether all core components are ready
    public var allCoreComponentsReady: Bool {
        let coreComponents: [ServiceComponent] = [.xpc, .config, .vfs, .index]
        return coreComponents.allSatisfy { component in
            components[component.rawValue]?.state == .ready
        }
    }

    /// Whether any component is in error state
    public var hasComponentError: Bool {
        return components.values.contains { $0.state == .error }
    }

    /// Get all errored components
    public var errorComponents: [ComponentStateInfo] {
        return components.values.filter { $0.state == .error }
    }
}

// MARK: - Config Status

/// Config status
public struct ConfigStatus: Codable, Sendable {
    /// Whether config is valid
    public var isValid: Bool

    /// Whether config was patched (missing fields filled with defaults)
    public var isPatched: Bool

    /// List of patched fields
    public var patchedFields: [String]?

    /// Config conflict list
    public var conflicts: [ConfigConflict]?

    /// Config load time
    public var loadedAt: Date?

    /// Config file path
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

    /// Whether user action is required for conflicts
    public var requiresUserAction: Bool {
        return conflicts?.contains { $0.requiresUserAction } ?? false
    }
}

// MARK: - Config Conflict

/// Config conflict information
public struct ConfigConflict: Codable, Sendable {
    /// Conflict type
    public let type: ConfigConflictType

    /// Affected items
    public let affectedItems: [String]

    /// Auto-resolution description
    public let resolution: String?

    /// Whether manual user action is required
    public let requiresUserAction: Bool

    /// Conflict details
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

/// Config conflict type
public enum ConfigConflictType: String, Codable, Sendable {
    case multipleExternalDirs = "MULTIPLE_EXTERNAL_DIRS"  // Multiple syncPairs use same EXTERNAL_DIR
    case overlappingLocal = "OVERLAPPING_LOCAL"           // LOCAL_DIR overlap
    case diskNotFound = "DISK_NOT_FOUND"                  // Referenced disk doesn't exist
    case circularSync = "CIRCULAR_SYNC"                   // Circular sync detected
    case invalidPath = "INVALID_PATH"                     // Invalid path
    case permissionDenied = "PERMISSION_DENIED"           // Insufficient permissions

    public var localizedDescription: String {
        switch self {
        case .multipleExternalDirs:
            return "Multiple sync pairs use the same external directory"
        case .overlappingLocal:
            return "Local directories overlap"
        case .diskNotFound:
            return "Referenced disk config does not exist"
        case .circularSync:
            return "Circular sync detected"
        case .invalidPath:
            return "Invalid path"
        case .permissionDenied:
            return "Insufficient permissions"
        }
    }
}

// MARK: - Service Error Info

/// Service error info (for ServiceFullState)
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

// MARK: - Index Progress

/// Index build progress
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

/// Index build phase
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
        case .idle:              return "Idle"
        case .scanningLocal:     return "Scanning Local Directory"
        case .scanningExternal:  return "Scanning External Directory"
        case .merging:           return "Merging Index"
        case .saving:            return "Saving Index"
        case .completed:         return "Completed"
        case .failed:            return "Failed"
        }
    }
}

// MARK: - XPC Connection State

/// XPC connection state
public enum XPCConnectionState: String, Codable, Sendable {
    case disconnected = "disconnected"
    case connecting = "connecting"
    case connected = "connected"
    case interrupted = "interrupted"
    case failed = "failed"
}
