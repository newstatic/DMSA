import Foundation

/// Sync task
public struct SyncTask: Codable, Identifiable, Sendable {
    public let id: String
    public let syncPairId: String
    public let syncPair: SyncPairConfig
    public let disk: DiskConfig
    public let direction: SyncDirection
    public let plan: SyncPlan?
    public var status: SyncStatus
    public var progress: Double
    public var startTime: Date?
    public var endTime: Date?
    public var errorMessage: String?
    public var priority: Int
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        syncPair: SyncPairConfig,
        disk: DiskConfig,
        direction: SyncDirection? = nil,
        plan: SyncPlan? = nil,
        status: SyncStatus = .pending,
        progress: Double = 0,
        priority: Int = 0
    ) {
        self.id = id
        self.syncPairId = syncPair.id
        self.syncPair = syncPair
        self.disk = disk
        self.direction = direction ?? syncPair.direction
        self.plan = plan
        self.status = status
        self.progress = progress
        self.priority = priority
        self.createdAt = Date()
    }

    /// Whether completed
    public var isCompleted: Bool {
        status == .completed || status == .failed || status == .cancelled
    }

    /// Whether running
    public var isRunning: Bool {
        status == .inProgress
    }
}
