import Foundation

// Note: SyncDirection is defined in DMSAShared/Models/Config.swift

// MARK: - Sync Action

/// Sync action type
public enum SyncAction: Codable, Identifiable, Sendable {
    case copy(source: String, destination: String, metadata: FileMetadata)
    case update(source: String, destination: String, metadata: FileMetadata)
    case delete(path: String, metadata: FileMetadata)
    case createDirectory(path: String)
    case createSymlink(path: String, target: String)
    case resolveConflict(conflict: ConflictInfo)
    case skip(path: String, reason: SkipReason)

    public var id: String {
        switch self {
        case .copy(_, let dest, _): return "copy:\(dest)"
        case .update(_, let dest, _): return "update:\(dest)"
        case .delete(let path, _): return "delete:\(path)"
        case .createDirectory(let path): return "mkdir:\(path)"
        case .createSymlink(let path, _): return "symlink:\(path)"
        case .resolveConflict(let conflict): return "conflict:\(conflict.relativePath)"
        case .skip(let path, _): return "skip:\(path)"
        }
    }

    /// Action description
    public var description: String {
        switch self {
        case .copy(_, let dest, let meta):
            return "Copy: \(meta.fileName) -> \(dest)"
        case .update(_, let dest, let meta):
            return "Update: \(meta.fileName) -> \(dest)"
        case .delete(let path, _):
            return "Delete: \(path)"
        case .createDirectory(let path):
            return "Create directory: \(path)"
        case .createSymlink(let path, let target):
            return "Create symlink: \(path) -> \(target)"
        case .resolveConflict(let conflict):
            return "Resolve conflict: \(conflict.relativePath)"
        case .skip(let path, let reason):
            return "Skip: \(path) (\(reason.description))"
        }
    }

    /// Bytes involved
    public var bytes: Int64 {
        switch self {
        case .copy(_, _, let meta), .update(_, _, let meta):
            return meta.size
        default:
            return 0
        }
    }

    /// Target path
    public var targetPath: String {
        switch self {
        case .copy(_, let dest, _), .update(_, let dest, _):
            return dest
        case .delete(let path, _), .createDirectory(let path), .createSymlink(let path, _):
            return path
        case .resolveConflict(let conflict):
            return conflict.relativePath
        case .skip(let path, _):
            return path
        }
    }
}

/// Skip reason
public enum SkipReason: String, Codable, Sendable {
    case identical = "identical"          // Files are identical
    case excluded = "excluded"            // Filtered by exclusion rules
    case permissionDenied = "permission"  // Insufficient permissions
    case tooLarge = "too_large"           // File too large
    case inUse = "in_use"                 // File is in use
    case notSupported = "not_supported"   // Unsupported file type

    public var description: String {
        switch self {
        case .identical: return "Identical"
        case .excluded: return "Excluded"
        case .permissionDenied: return "Permission Denied"
        case .tooLarge: return "Too Large"
        case .inUse: return "In Use"
        case .notSupported: return "Not Supported"
        }
    }
}

// MARK: - Sync Plan

/// Sync plan - contains all pending sync actions
public struct SyncPlan: Codable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let syncPairId: String
    public let direction: SyncDirection

    /// Source directory path
    public let sourcePath: String

    /// Destination directory path
    public let destinationPath: String

    /// Pending action list
    public var actions: [SyncAction]

    /// Conflict list
    public var conflicts: [ConflictInfo]

    /// Source directory snapshot
    public var sourceSnapshot: DirectorySnapshot?

    /// Destination directory snapshot
    public var destinationSnapshot: DirectorySnapshot?

    // MARK: - Statistics

    /// Total file count
    public var totalFiles: Int {
        actions.filter { action in
            switch action {
            case .copy, .update: return true
            default: return false
            }
        }.count
    }

    /// Total bytes
    public var totalBytes: Int64 {
        actions.reduce(0) { $0 + $1.bytes }
    }

    /// Files to copy
    public var filesToCopy: Int {
        actions.filter { if case .copy = $0 { return true }; return false }.count
    }

    /// Files to update
    public var filesToUpdate: Int {
        actions.filter { if case .update = $0 { return true }; return false }.count
    }

    /// Files to delete
    public var filesToDelete: Int {
        actions.filter { if case .delete = $0 { return true }; return false }.count
    }

    /// Directories to create
    public var directoriesToCreate: Int {
        actions.filter { if case .createDirectory = $0 { return true }; return false }.count
    }

    /// Skipped files
    public var skippedFiles: Int {
        actions.filter { if case .skip = $0 { return true }; return false }.count
    }

    /// Conflict count
    public var conflictCount: Int {
        conflicts.count
    }

    /// Whether there are unresolved conflicts
    public var hasUnresolvedConflicts: Bool {
        conflicts.contains { $0.resolution == nil }
    }

    // MARK: - Initialization

    public init(
        syncPairId: String,
        direction: SyncDirection,
        sourcePath: String,
        destinationPath: String,
        actions: [SyncAction] = [],
        conflicts: [ConflictInfo] = []
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.syncPairId = syncPairId
        self.direction = direction
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.actions = actions
        self.conflicts = conflicts
    }

    // MARK: - Methods

    /// Get plan summary
    public var summary: SyncPlanSummary {
        SyncPlanSummary(
            totalFiles: totalFiles,
            totalBytes: totalBytes,
            filesToCopy: filesToCopy,
            filesToUpdate: filesToUpdate,
            filesToDelete: filesToDelete,
            directoriesToCreate: directoriesToCreate,
            skippedFiles: skippedFiles,
            conflictCount: conflictCount
        )
    }

    /// Add action
    public mutating func addAction(_ action: SyncAction) {
        actions.append(action)
    }

    /// Add conflict
    public mutating func addConflict(_ conflict: ConflictInfo) {
        conflicts.append(conflict)
    }

    /// Remove actions for resolved conflicts
    public mutating func applyConflictResolutions() {
        for conflict in conflicts where conflict.resolution != nil {
            // Remove original conflict actions
            actions.removeAll { action in
                if case .resolveConflict(let c) = action {
                    return c.id == conflict.id
                }
                return false
            }

            // Add new actions based on resolution
            if let resolution = conflict.resolution {
                switch resolution {
                case .keepLocal:
                    if let localMeta = conflict.localMetadata {
                        actions.append(.update(
                            source: conflict.localPath,
                            destination: conflict.externalPath,
                            metadata: localMeta
                        ))
                    }
                case .keepExternal:
                    if let externalMeta = conflict.externalMetadata {
                        actions.append(.update(
                            source: conflict.externalPath,
                            destination: conflict.localPath,
                            metadata: externalMeta
                        ))
                    }
                case .keepBoth:
                    // Keep both, handle with rename
                    break
                case .skip:
                    actions.append(.skip(path: conflict.relativePath, reason: .identical))
                case .localWinsWithBackup, .externalWinsWithBackup:
                    // Backup handling done during execution
                    break
                }
            }
        }
    }
}

/// Sync plan summary
public struct SyncPlanSummary: Codable, Sendable {
    public let totalFiles: Int
    public let totalBytes: Int64
    public let filesToCopy: Int
    public let filesToUpdate: Int
    public let filesToDelete: Int
    public let directoriesToCreate: Int
    public let skippedFiles: Int
    public let conflictCount: Int

    public init(
        totalFiles: Int,
        totalBytes: Int64,
        filesToCopy: Int,
        filesToUpdate: Int,
        filesToDelete: Int,
        directoriesToCreate: Int,
        skippedFiles: Int,
        conflictCount: Int
    ) {
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.filesToCopy = filesToCopy
        self.filesToUpdate = filesToUpdate
        self.filesToDelete = filesToDelete
        self.directoriesToCreate = directoriesToCreate
        self.skippedFiles = skippedFiles
        self.conflictCount = conflictCount
    }

    public var formattedTotalBytes: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    public var isEmpty: Bool {
        filesToCopy == 0 && filesToUpdate == 0 && filesToDelete == 0 && directoriesToCreate == 0
    }

    public var description: String {
        var parts: [String] = []
        if filesToCopy > 0 { parts.append("Copy \(filesToCopy)") }
        if filesToUpdate > 0 { parts.append("Update \(filesToUpdate)") }
        if filesToDelete > 0 { parts.append("Delete \(filesToDelete)") }
        if directoriesToCreate > 0 { parts.append("Create \(directoriesToCreate) dirs") }
        if conflictCount > 0 { parts.append("\(conflictCount) conflicts") }

        if parts.isEmpty {
            return "Nothing to sync"
        }

        return parts.joined(separator: ", ") + " (\(formattedTotalBytes))"
    }
}

// MARK: - Sync Result

/// Sync execution result
public struct SyncResult: Codable, Sendable {
    public let planId: UUID
    public let startTime: Date
    public let endTime: Date
    public let success: Bool

    /// Succeeded action count
    public let succeededActions: Int

    /// Failed actions
    public let failedActions: [FailedAction]

    /// Transferred file count
    public let filesTransferred: Int

    /// Transferred bytes
    public let bytesTransferred: Int64

    /// Verified file count
    public let filesVerified: Int

    /// Verification failure count
    public let verificationFailures: Int

    /// Error message
    public let errorMessage: String?

    /// Whether cancelled
    public let wasCancelled: Bool

    /// Whether resumed from pause
    public let wasResumed: Bool

    public init(
        planId: UUID,
        startTime: Date,
        endTime: Date,
        success: Bool,
        succeededActions: Int,
        failedActions: [FailedAction],
        filesTransferred: Int,
        bytesTransferred: Int64,
        filesVerified: Int,
        verificationFailures: Int,
        errorMessage: String?,
        wasCancelled: Bool,
        wasResumed: Bool
    ) {
        self.planId = planId
        self.startTime = startTime
        self.endTime = endTime
        self.success = success
        self.succeededActions = succeededActions
        self.failedActions = failedActions
        self.filesTransferred = filesTransferred
        self.bytesTransferred = bytesTransferred
        self.filesVerified = filesVerified
        self.verificationFailures = verificationFailures
        self.errorMessage = errorMessage
        self.wasCancelled = wasCancelled
        self.wasResumed = wasResumed
    }

    /// Execution duration
    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// Formatted duration
    public var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "\(Int(duration))s"
    }

    /// Average transfer speed (bytes/s)
    public var averageSpeed: Int64 {
        guard duration > 0 else { return 0 }
        return Int64(Double(bytesTransferred) / duration)
    }

    /// Formatted transfer speed
    public var formattedSpeed: String {
        ByteCountFormatter.string(fromByteCount: averageSpeed, countStyle: .file) + "/s"
    }
}

/// Failed action record
public struct FailedAction: Codable, Sendable {
    public let action: SyncAction
    public let error: String
    public let timestamp: Date

    public init(action: SyncAction, error: String, timestamp: Date = Date()) {
        self.action = action
        self.error = error
        self.timestamp = timestamp
    }
}
