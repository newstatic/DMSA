import Foundation

/// Conflict information
public struct ConflictInfo: Codable, Identifiable, Sendable {
    public let id: UUID

    /// File relative path
    public let relativePath: String

    /// Local file full path
    public let localPath: String

    /// External file full path
    public let externalPath: String

    /// Local file metadata (if exists)
    public let localMetadata: FileMetadata?

    /// External file metadata (if exists)
    public let externalMetadata: FileMetadata?

    /// Conflict type
    public let conflictType: ConflictType

    /// Detection time
    public let detectedAt: Date

    /// User-selected resolution
    public var resolution: ConflictResolution?

    /// Resolution time
    public var resolvedAt: Date?

    // MARK: - Computed Properties

    /// File name
    public var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    /// Local file size
    public var localSize: Int64 {
        localMetadata?.size ?? 0
    }

    /// External file size
    public var externalSize: Int64 {
        externalMetadata?.size ?? 0
    }

    /// Local modification time
    public var localModifiedTime: Date? {
        localMetadata?.modifiedTime
    }

    /// External modification time
    public var externalModifiedTime: Date? {
        externalMetadata?.modifiedTime
    }

    /// Whether resolved
    public var isResolved: Bool {
        resolution != nil
    }

    /// Conflict description
    public var description: String {
        switch conflictType {
        case .bothModified:
            return "Both sides modified \(fileName)"
        case .deletedOnLocal:
            return "\(fileName) deleted locally but modified on external"
        case .deletedOnExternal:
            return "\(fileName) deleted on external but modified locally"
        case .typeChanged:
            return "\(fileName) type has changed"
        case .permissionConflict:
            return "\(fileName) permissions are inconsistent"
        }
    }

    // MARK: - Initialization

    public init(
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
    public mutating func resolve(with resolution: ConflictResolution) {
        self.resolution = resolution
        self.resolvedAt = Date()
    }

    /// Get recommended resolution
    public func recommendedResolution() -> ConflictResolution {
        switch conflictType {
        case .bothModified:
            // Compare modification times, newer takes priority
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
public enum ConflictType: String, Codable, Sendable {
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

    public var description: String {
        switch self {
        case .bothModified: return "Both Modified"
        case .deletedOnLocal: return "Deleted Locally"
        case .deletedOnExternal: return "Deleted on External"
        case .typeChanged: return "Type Changed"
        case .permissionConflict: return "Permission Conflict"
        }
    }

    public var icon: String {
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
public enum ConflictResolution: String, Codable, Sendable {
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

    public var description: String {
        switch self {
        case .keepLocal: return "Keep Local"
        case .keepExternal: return "Keep External"
        case .localWinsWithBackup: return "Local Wins (Backup)"
        case .externalWinsWithBackup: return "External Wins (Backup)"
        case .keepBoth: return "Keep Both"
        case .skip: return "Skip"
        }
    }

    public var icon: String {
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
public enum ConflictStrategy: String, Codable, CaseIterable, Sendable {
    /// Newer file overwrites older
    case newerWins = "newer_wins"

    /// Larger file overwrites smaller
    case largerWins = "larger_wins"

    /// Local file always takes priority
    case localWins = "local_wins"

    /// External file always takes priority
    case externalWins = "external_wins"

    /// Local takes priority with target file backup (default)
    case localWinsWithBackup = "local_wins_backup"

    /// External takes priority with local file backup
    case externalWinsWithBackup = "external_wins_backup"

    /// Always ask user
    case askUser = "ask_user"

    /// Keep both versions
    case keepBoth = "keep_both"

    public var description: String {
        switch self {
        case .newerWins: return "Newer Overwrites Older"
        case .largerWins: return "Larger Overwrites Smaller"
        case .localWins: return "Local Priority"
        case .externalWins: return "External Priority"
        case .localWinsWithBackup: return "Local Priority (Backup Target)"
        case .externalWinsWithBackup: return "External Priority (Backup Local)"
        case .askUser: return "Always Ask"
        case .keepBoth: return "Keep Both Versions"
        }
    }

    /// Convert strategy to resolution
    public func toResolution(for conflict: ConflictInfo) -> ConflictResolution? {
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
