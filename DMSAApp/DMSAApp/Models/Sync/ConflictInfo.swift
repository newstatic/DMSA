import Foundation

/// Conflict information
struct ConflictInfo: Codable, Identifiable {
    let id: UUID

    /// File relative path
    let relativePath: String

    /// Local file full path
    let localPath: String

    /// External file full path
    let externalPath: String

    /// Local file metadata (if exists)
    let localMetadata: FileMetadata?

    /// External file metadata (if exists)
    let externalMetadata: FileMetadata?

    /// Conflict type
    let conflictType: ConflictType

    /// Detection time
    let detectedAt: Date

    /// User-selected resolution
    var resolution: ConflictResolution?

    /// Resolution time
    var resolvedAt: Date?

    // MARK: - Computed Properties

    /// File name
    var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    /// Local file size
    var localSize: Int64 {
        localMetadata?.size ?? 0
    }

    /// External file size
    var externalSize: Int64 {
        externalMetadata?.size ?? 0
    }

    /// Local modification time
    var localModifiedTime: Date? {
        localMetadata?.modifiedTime
    }

    /// External modification time
    var externalModifiedTime: Date? {
        externalMetadata?.modifiedTime
    }

    /// Whether resolved
    var isResolved: Bool {
        resolution != nil
    }

    /// Conflict description
    var description: String {
        switch conflictType {
        case .bothModified:
            return "Both sides modified \(fileName)"
        case .deletedOnLocal:
            return "\(fileName) deleted locally but modified on external"
        case .deletedOnExternal:
            return "\(fileName) deleted on external but modified locally"
        case .typeChanged:
            return "\(fileName) type changed"
        case .permissionConflict:
            return "\(fileName) has permission mismatch"
        }
    }

    // MARK: - Initialization

    init(
        relativePath: String,
        localPath: String,
        externalPath: String,
        localMetadata: FileMetadata?,
        externalMetadata: FileMetadata?,
        conflictType: ConflictType
    ) {
        self.id = UUID()
        self.relativePath = relativePath
        self.localPath = localPath
        self.externalPath = externalPath
        self.localMetadata = localMetadata
        self.externalMetadata = externalMetadata
        self.conflictType = conflictType
        self.detectedAt = Date()
    }

    // MARK: - Methods

    /// Apply resolution
    mutating func resolve(with resolution: ConflictResolution) {
        self.resolution = resolution
        self.resolvedAt = Date()
    }

    /// Get recommended resolution
    func recommendedResolution() -> ConflictResolution {
        switch conflictType {
        case .bothModified:
            // Compare modification time, newer wins
            if let localTime = localModifiedTime, let externalTime = externalModifiedTime {
                return localTime > externalTime ? .localWinsWithBackup : .externalWinsWithBackup
            }
            return .localWinsWithBackup

        case .deletedOnLocal:
            // Deleted locally, keep external version
            return .keepExternal

        case .deletedOnExternal:
            // Deleted on external, keep local version
            return .keepLocal

        case .typeChanged:
            // Type changed, keep local
            return .localWinsWithBackup

        case .permissionConflict:
            // Permission conflict, keep local
            return .keepLocal
        }
    }
}

// MARK: - Conflict Type

/// Conflict type enum
enum ConflictType: String, Codable {
    /// Both sides modified the same file
    case bothModified = "both_modified"

    /// Deleted locally but modified on external
    case deletedOnLocal = "deleted_on_local"

    /// Deleted on external but modified locally
    case deletedOnExternal = "deleted_on_external"

    /// File type changed (e.g. file became directory)
    case typeChanged = "type_changed"

    /// Permission conflict
    case permissionConflict = "permission_conflict"

    var description: String {
        switch self {
        case .bothModified: return "Both modified"
        case .deletedOnLocal: return "Deleted locally"
        case .deletedOnExternal: return "Deleted on external"
        case .typeChanged: return "Type changed"
        case .permissionConflict: return "Permission conflict"
        }
    }

    var icon: String {
        switch self {
        case .bothModified: return "arrow.triangle.2.circlepath"
        case .deletedOnLocal, .deletedOnExternal: return "trash"
        case .typeChanged: return "doc.badge.gearshape"
        case .permissionConflict: return "lock.trianglebadge.exclamationmark"
        }
    }
}

// MARK: - Conflict Resolution

/// Conflict resolution enum
enum ConflictResolution: String, Codable {
    /// Keep local version
    case keepLocal = "keep_local"

    /// Keep external version
    case keepExternal = "keep_external"

    /// Local version overwrites external, backup external file
    case localWinsWithBackup = "local_wins_backup"

    /// External version overwrites local, backup local file
    case externalWinsWithBackup = "external_wins_backup"

    /// Keep both versions (rename)
    case keepBoth = "keep_both"

    /// Skip, do not process
    case skip = "skip"

    var description: String {
        switch self {
        case .keepLocal: return "Keep local"
        case .keepExternal: return "Keep external"
        case .localWinsWithBackup: return "Local wins (backup)"
        case .externalWinsWithBackup: return "External wins (backup)"
        case .keepBoth: return "Keep both"
        case .skip: return "Skip"
        }
    }

    var icon: String {
        switch self {
        case .keepLocal: return "internaldrive"
        case .keepExternal: return "externaldrive"
        case .localWinsWithBackup: return "internaldrive.badge.checkmark"
        case .externalWinsWithBackup: return "externaldrive.badge.checkmark"
        case .keepBoth: return "doc.on.doc"
        case .skip: return "forward"
        }
    }
}

// MARK: - Conflict Resolution Strategy

/// Automatic conflict resolution strategy
enum ConflictStrategy: String, Codable, CaseIterable {
    /// Newer file overwrites older
    case newerWins = "newer_wins"

    /// Larger file overwrites smaller
    case largerWins = "larger_wins"

    /// Local file always wins
    case localWins = "local_wins"

    /// External file always wins
    case externalWins = "external_wins"

    /// Local wins with target backup (default)
    case localWinsWithBackup = "local_wins_backup"

    /// External wins with local backup
    case externalWinsWithBackup = "external_wins_backup"

    /// Always ask user
    case askUser = "ask_user"

    /// Keep both versions
    case keepBoth = "keep_both"

    var description: String {
        switch self {
        case .newerWins: return "Newer overwrites older"
        case .largerWins: return "Larger overwrites smaller"
        case .localWins: return "Local wins"
        case .externalWins: return "External wins"
        case .localWinsWithBackup: return "Local wins (backup target)"
        case .externalWinsWithBackup: return "External wins (backup local)"
        case .askUser: return "Always ask"
        case .keepBoth: return "Keep both versions"
        }
    }

    /// Convert strategy to resolution
    func toResolution(for conflict: ConflictInfo) -> ConflictResolution? {
        switch self {
        case .newerWins:
            guard let localTime = conflict.localModifiedTime,
                  let externalTime = conflict.externalModifiedTime else {
                return nil
            }
            return localTime > externalTime ? .keepLocal : .keepExternal

        case .largerWins:
            return conflict.localSize >= conflict.externalSize ? .keepLocal : .keepExternal

        case .localWins:
            return .keepLocal

        case .externalWins:
            return .keepExternal

        case .localWinsWithBackup:
            return .localWinsWithBackup

        case .externalWinsWithBackup:
            return .externalWinsWithBackup

        case .askUser:
            return nil  // Requires user decision

        case .keepBoth:
            return .keepBoth
        }
    }
}
