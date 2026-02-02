import Foundation

// MARK: - Sync Action

/// Sync action type
enum SyncAction: Codable, Identifiable {
    case copy(source: String, destination: String, metadata: FileMetadata)
    case update(source: String, destination: String, metadata: FileMetadata)
    case delete(path: String, metadata: FileMetadata)
    case createDirectory(path: String)
    case createSymlink(path: String, target: String)
    case resolveConflict(conflict: ConflictInfo)
    case skip(path: String, reason: SkipReason)

    var id: String {
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
    var description: String {
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
    var bytes: Int64 {
        switch self {
        case .copy(_, _, let meta), .update(_, _, let meta):
            return meta.size
        default:
            return 0
        }
    }

    /// Target path
    var targetPath: String {
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
enum SkipReason: String, Codable {
    case identical = "identical"          // Files are identical
    case excluded = "excluded"            // Filtered by exclusion rules
    case permissionDenied = "permission"  // Insufficient permissions
    case tooLarge = "too_large"           // File too large
    case inUse = "in_use"                 // File in use
    case notSupported = "not_supported"   // Unsupported file type

    var description: String {
        switch self {
        case .identical: return "Identical"
        case .excluded: return "Excluded"
        case .permissionDenied: return "Permission denied"
        case .tooLarge: return "Too large"
        case .inUse: return "In use"
        case .notSupported: return "Not supported"
        }
    }
}

// MARK: - Sync Plan

/// Sync plan - contains all pending sync actions
struct SyncPlan: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let syncPairId: String
    let direction: SyncDirection

    /// Source directory path
    let sourcePath: String

    /// Destination directory path
    let destinationPath: String

    /// List of actions to execute
    var actions: [SyncAction]

    /// Conflict list
    var conflicts: [ConflictInfo]

    /// Source directory snapshot
    var sourceSnapshot: DirectorySnapshot?

    /// Destination directory snapshot
    var destinationSnapshot: DirectorySnapshot?

    // MARK: - Statistics

    /// Total file count
    var totalFiles: Int {
        actions.filter { action in
            switch action {
            case .copy, .update: return true
            default: return false
            }
        }.count
    }

    /// Total bytes
    var totalBytes: Int64 {
        actions.reduce(0) { $0 + $1.bytes }
    }

    /// Files to copy
    var filesToCopy: Int {
        actions.filter { if case .copy = $0 { return true }; return false }.count
    }

    /// Files to update
    var filesToUpdate: Int {
        actions.filter { if case .update = $0 { return true }; return false }.count
    }

    /// Files to delete
    var filesToDelete: Int {
        actions.filter { if case .delete = $0 { return true }; return false }.count
    }

    /// Directories to create
    var directoriesToCreate: Int {
        actions.filter { if case .createDirectory = $0 { return true }; return false }.count
    }

    /// Skipped files
    var skippedFiles: Int {
        actions.filter { if case .skip = $0 { return true }; return false }.count
    }

    /// Conflict count
    var conflictCount: Int {
        conflicts.count
    }

    /// Whether there are unresolved conflicts
    var hasUnresolvedConflicts: Bool {
        conflicts.contains { $0.resolution == nil }
    }

    // MARK: - Initialization

    init(
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
    var summary: SyncPlanSummary {
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
    mutating func addAction(_ action: SyncAction) {
        actions.append(action)
    }

    /// Add conflict
    mutating func addConflict(_ conflict: ConflictInfo) {
        conflicts.append(conflict)
    }

    /// Remove actions for resolved conflicts and apply resolutions
    mutating func applyConflictResolutions() {
        for conflict in conflicts where conflict.resolution != nil {
            // Remove original conflict action
            actions.removeAll { action in
                if case .resolveConflict(let c) = action {
                    return c.id == conflict.id
                }
                return false
            }

            // Add new action based on resolution
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
                    // Backup handling occurs during execution
                    break
                }
            }
        }
    }
}

/// Sync plan summary
struct SyncPlanSummary: Codable {
    let totalFiles: Int
    let totalBytes: Int64
    let filesToCopy: Int
    let filesToUpdate: Int
    let filesToDelete: Int
    let directoriesToCreate: Int
    let skippedFiles: Int
    let conflictCount: Int

    var formattedTotalBytes: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var isEmpty: Bool {
        filesToCopy == 0 && filesToUpdate == 0 && filesToDelete == 0 && directoriesToCreate == 0
    }

    var description: String {
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
struct SyncResult: Codable {
    let planId: UUID
    let startTime: Date
    let endTime: Date
    let success: Bool

    /// Succeeded action count
    let succeededActions: Int

    /// Failed actions
    let failedActions: [FailedAction]

    /// Files transferred
    let filesTransferred: Int

    /// Bytes transferred
    let bytesTransferred: Int64

    /// Files verified
    let filesVerified: Int

    /// Verification failures
    let verificationFailures: Int

    /// Error message
    let errorMessage: String?

    /// Whether cancelled
    let wasCancelled: Bool

    /// Whether resumed from pause
    let wasResumed: Bool

    /// Execution duration
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// Formatted duration
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "\(Int(duration))s"
    }

    /// Average transfer speed (bytes/s)
    var averageSpeed: Int64 {
        guard duration > 0 else { return 0 }
        return Int64(Double(bytesTransferred) / duration)
    }

    /// Formatted transfer speed
    var formattedSpeed: String {
        ByteCountFormatter.string(fromByteCount: averageSpeed, countStyle: .file) + "/s"
    }
}

/// Failed action record
struct FailedAction: Codable {
    let action: SyncAction
    let error: String
    let timestamp: Date
}
