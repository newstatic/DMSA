import Foundation

/// Shared state (inter-service state synchronization)
public struct SharedState: Codable, Sendable {
    public var lastWrittenPath: String?
    public var lastWrittenSyncPair: String?
    public var lastWrittenTime: Date?
    public var vfsMountedPairs: [String]
    public var syncRunningPairs: [String]
    public var connectedDisks: [String]
    public var lastConfigUpdate: Date?

    public init() {
        self.lastWrittenPath = nil
        self.lastWrittenSyncPair = nil
        self.lastWrittenTime = nil
        self.vfsMountedPairs = []
        self.syncRunningPairs = []
        self.connectedDisks = []
        self.lastConfigUpdate = nil
    }

    /// Load from file
    public static func load() -> SharedState {
        let url = Constants.Paths.sharedState

        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SharedState.self, from: data) else {
            return SharedState()
        }

        return state
    }

    /// Save to file
    public func save() {
        let url = Constants.Paths.sharedState

        // Ensure directory exists
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url)
        }
    }

    /// Atomic update
    public static func update(_ block: (inout SharedState) -> Void) {
        var state = load()
        block(&state)
        state.save()
    }
}

/// Mount information
public struct MountInfo: Codable, Identifiable, Sendable {
    public var id: String  // syncPairId
    public var syncPairId: String
    public var targetDir: String
    public var localDir: String
    public var externalDir: String?
    public var isMounted: Bool
    public var isExternalOnline: Bool
    public var mountedAt: Date?
    public var fileCount: Int
    public var totalSize: Int64

    public init(syncPairId: String, targetDir: String, localDir: String) {
        self.id = syncPairId
        self.syncPairId = syncPairId
        self.targetDir = targetDir
        self.localDir = localDir
        self.externalDir = nil
        self.isMounted = false
        self.isExternalOnline = false
        self.mountedAt = nil
        self.fileCount = 0
        self.totalSize = 0
    }

    /// Convert to dictionary (for XPC transport)
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "syncPairId": syncPairId,
            "targetDir": targetDir,
            "localDir": localDir,
            "isMounted": isMounted,
            "isExternalOnline": isExternalOnline,
            "fileCount": fileCount,
            "totalSize": totalSize
        ]

        if let externalDir = externalDir { dict["externalDir"] = externalDir }
        if let mountedAt = mountedAt { dict["mountedAt"] = mountedAt.timeIntervalSince1970 }

        return dict
    }

    /// Create from dictionary
    public static func from(dictionary dict: [String: Any]) -> MountInfo? {
        guard let syncPairId = dict["syncPairId"] as? String,
              let targetDir = dict["targetDir"] as? String,
              let localDir = dict["localDir"] as? String else {
            return nil
        }

        var info = MountInfo(syncPairId: syncPairId, targetDir: targetDir, localDir: localDir)
        info.externalDir = dict["externalDir"] as? String
        info.isMounted = dict["isMounted"] as? Bool ?? false
        info.isExternalOnline = dict["isExternalOnline"] as? Bool ?? false
        info.fileCount = dict["fileCount"] as? Int ?? 0
        info.totalSize = dict["totalSize"] as? Int64 ?? 0

        if let mountedAtTs = dict["mountedAt"] as? TimeInterval {
            info.mountedAt = Date(timeIntervalSince1970: mountedAtTs)
        }

        return info
    }

    /// Convert to Data
    public func toData() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    /// Create from Data
    public static func from(data: Data) -> MountInfo? {
        return try? JSONDecoder().decode(MountInfo.self, from: data)
    }

    /// Create array from Data
    public static func arrayFrom(data: Data) -> [MountInfo] {
        return (try? JSONDecoder().decode([MountInfo].self, from: data)) ?? []
    }
}

/// Service version information
public struct ServiceVersionInfo: Codable, Sendable {
    public var version: String
    public var buildNumber: Int
    public var protocolVersion: Int
    public var minAppVersion: String
    public var startedAt: Date
    public var uptime: TimeInterval

    /// Default initialization (empty values, filled by Service)
    public init() {
        self.version = ""
        self.buildNumber = 0
        self.protocolVersion = 0
        self.minAppVersion = ""
        self.startedAt = Date()
        self.uptime = 0
    }

    /// Full initialization (used by Service)
    public init(version: String, buildNumber: Int, protocolVersion: Int, minAppVersion: String, startedAt: Date) {
        self.version = version
        self.buildNumber = buildNumber
        self.protocolVersion = protocolVersion
        self.minAppVersion = minAppVersion
        self.startedAt = startedAt
        self.uptime = Date().timeIntervalSince(startedAt)
    }

    /// Full version string
    public var fullVersion: String {
        "\(version) (build \(buildNumber), protocol v\(protocolVersion))"
    }

    /// Convert to Data
    public func toData() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    /// Create from Data
    public static func from(data: Data) -> ServiceVersionInfo? {
        return try? JSONDecoder().decode(ServiceVersionInfo.self, from: data)
    }
}

/// Sync status information
public struct SyncStatusInfo: Codable, Identifiable, Sendable {
    public var id: String  // syncPairId
    public var syncPairId: String
    public var status: SyncStatus
    public var isPaused: Bool
    public var lastSyncTime: Date?
    public var nextSyncTime: Date?
    public var pendingFiles: Int
    public var dirtyFiles: Int
    // Note: currentProgress is fetched separately via getSyncProgress API

    public init(syncPairId: String) {
        self.id = syncPairId
        self.syncPairId = syncPairId
        self.status = .pending
        self.isPaused = false
        self.lastSyncTime = nil
        self.nextSyncTime = nil
        self.pendingFiles = 0
        self.dirtyFiles = 0
    }

    /// Convert to Data
    public func toData() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    /// Create from Data
    public static func from(data: Data) -> SyncStatusInfo? {
        return try? JSONDecoder().decode(SyncStatusInfo.self, from: data)
    }

    /// Create array from Data
    public static func arrayFrom(data: Data) -> [SyncStatusInfo] {
        return (try? JSONDecoder().decode([SyncStatusInfo].self, from: data)) ?? []
    }
}
