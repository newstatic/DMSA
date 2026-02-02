import Foundation

// Note: SyncStatus is defined in DMSAShared/Models/Config.swift

/// Sync progress
public struct SyncProgress: Codable, Sendable {
    public var syncPairId: String
    public var status: SyncStatus
    public var totalFiles: Int
    public var processedFiles: Int
    public var totalBytes: Int64
    public var processedBytes: Int64
    public var currentFile: String?
    public var startTime: Date?
    public var endTime: Date?
    public var errorMessage: String?
    public var speed: Int64  // bytes per second

    /// Current phase
    public var phase: SyncPhase

    public init(syncPairId: String) {
        self.syncPairId = syncPairId
        self.status = .pending
        self.totalFiles = 0
        self.processedFiles = 0
        self.totalBytes = 0
        self.processedBytes = 0
        self.currentFile = nil
        self.startTime = nil
        self.endTime = nil
        self.errorMessage = nil
        self.speed = 0
        self.phase = .idle
    }

    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(processedBytes) / Double(totalBytes)
    }

    public var fileProgress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(processedFiles) / Double(totalFiles)
    }

    public var elapsedTime: TimeInterval? {
        guard let start = startTime else { return nil }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }

    public var estimatedTimeRemaining: TimeInterval? {
        guard let elapsed = elapsedTime, progress > 0, progress < 1 else { return nil }
        return elapsed * (1 - progress) / progress
    }

    public var formattedProgress: String {
        return String(format: "%.1f%%", progress * 100)
    }

    public var formattedSpeed: String {
        return formatBytes(speed) + "/s"
    }

    public var formattedETA: String? {
        guard let eta = estimatedTimeRemaining else { return nil }
        if eta < 60 {
            return String(format: "%.0f sec", eta)
        } else if eta < 3600 {
            return String(format: "%.0f min", eta / 60)
        } else {
            return String(format: "%.1f hr", eta / 3600)
        }
    }

    /// Convert to Data (for XPC transport)
    public func toData() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    /// Create from Data (for XPC transport)
    public static func from(data: Data) -> SyncProgress? {
        return try? JSONDecoder().decode(SyncProgress.self, from: data)
    }
}

/// Sync phase
public enum SyncPhase: String, Codable, Sendable {
    case idle = "idle"
    case scanning = "scanning"
    case calculating = "calculating"
    case checksumming = "checksumming"
    case resolving = "resolving"
    case diffing = "diffing"
    case syncing = "syncing"
    case verifying = "verifying"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    case paused = "paused"

    public var description: String {
        switch self {
        case .idle: return "Idle"
        case .scanning: return "Scanning Files"
        case .calculating: return "Calculating Diff"
        case .checksumming: return "Computing Checksum"
        case .resolving: return "Resolving Conflicts"
        case .diffing: return "Comparing Diff"
        case .syncing: return "Syncing Files"
        case .verifying: return "Verifying Integrity"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .paused: return "Paused"
        }
    }
}

// Note: formatBytes is defined in DMSAShared/Utils/Errors.swift
