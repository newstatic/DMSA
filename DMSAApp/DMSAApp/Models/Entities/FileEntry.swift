import Foundation

/// Sync lock state
enum LockState: Int, Codable {
    case unlocked = 0       // Unlocked, normal read/write
    case syncLocked = 1     // Sync locked, reads allowed but writes blocked
}

/// Sync direction (used to determine source path during lock)
enum SyncLockDirection: Int, Codable {
    case localToExternal = 0   // LOCAL -> EXTERNAL
    case externalToLocal = 1   // EXTERNAL -> LOCAL
}

/// File index entity
/// Tracks file location and state across local and external disks
class FileEntry: Identifiable, Codable {
    var id: UInt64 = 0
    var virtualPath: String = ""
    var localPath: String?
    var externalPath: String?
    var location: FileLocation = .notExists
    var size: Int64 = 0
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var accessedAt: Date = Date()
    var checksum: String?
    var isDirty: Bool = false
    var syncPairId: String?
    var diskId: String?

    /// Whether this is a directory
    var isDirectory: Bool = false

    // === Sync lock related ===

    /// Sync lock state
    var lockState: LockState = .unlocked

    /// Lock start time
    var lockTime: Date?

    /// Sync direction during lock (determines read source)
    var lockDirection: SyncLockDirection?

    /// Lock timeout (seconds)
    static let lockTimeout: TimeInterval = 30.0

    /// Write wait timeout (seconds)
    static let writeWaitTimeout: TimeInterval = 5.0

    init() {}

    init(virtualPath: String, localPath: String? = nil, externalPath: String? = nil) {
        self.virtualPath = virtualPath
        self.localPath = localPath
        self.externalPath = externalPath
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.accessedAt = Date()
    }

    /// File name
    var fileName: String {
        return (virtualPath as NSString).lastPathComponent
    }

    /// File extension
    var fileExtension: String {
        return (virtualPath as NSString).pathExtension
    }

    /// Parent directory path
    var parentPath: String {
        return (virtualPath as NSString).deletingLastPathComponent
    }

    /// Formatted file size
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// Whether sync is needed
    var needsSync: Bool {
        return isDirty || location == .localOnly || location == .externalOnly
    }

    /// Whether locked
    var isLocked: Bool {
        return lockState == .syncLocked
    }

    /// Check if lock has expired
    var isLockExpired: Bool {
        guard lockState == .syncLocked, let lockTime = lockTime else {
            return false
        }
        return Date().timeIntervalSince(lockTime) > FileEntry.lockTimeout
    }

    /// Get sync source path (for reading locked files)
    var syncSourcePath: String? {
        guard lockState == .syncLocked, let direction = lockDirection else {
            return nil
        }
        switch direction {
        case .localToExternal:
            return localPath  // Syncing LOCAL -> EXTERNAL, source is LOCAL
        case .externalToLocal:
            return externalPath  // Syncing EXTERNAL -> LOCAL, source is EXTERNAL
        }
    }

    /// Lock file (called when sync starts)
    func lock(direction: SyncLockDirection) {
        lockState = .syncLocked
        lockTime = Date()
        lockDirection = direction
    }

    /// Unlock file (called when sync completes)
    func unlock() {
        lockState = .unlocked
        lockTime = nil
        lockDirection = nil
    }
}

// MARK: - FileEntry Equatable

extension FileEntry: Equatable {
    static func == (lhs: FileEntry, rhs: FileEntry) -> Bool {
        return lhs.id == rhs.id && lhs.virtualPath == rhs.virtualPath
    }
}

// MARK: - FileEntry Hashable

extension FileEntry: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(virtualPath)
    }
}
