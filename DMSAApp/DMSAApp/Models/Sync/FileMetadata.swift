import Foundation

/// File metadata - used for sync comparison
struct FileMetadata: Codable, Hashable, Identifiable {
    var id: String { relativePath }

    /// Relative path (relative to sync root directory)
    let relativePath: String

    /// File size (bytes)
    let size: Int64

    /// Modification time
    let modifiedTime: Date

    /// Creation time
    let createdTime: Date

    /// Whether this is a directory
    let isDirectory: Bool

    /// Whether this is a symbolic link
    let isSymlink: Bool

    /// Symbolic link target (if symlink)
    let symlinkTarget: String?

    /// Checksum (MD5/SHA256)
    var checksum: String?

    /// File permissions (POSIX)
    let permissions: UInt16

    /// File owner UID
    let ownerUID: UInt32

    /// File group GID
    let ownerGID: UInt32

    // MARK: - Computed Properties

    /// File name
    var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    /// File extension
    var fileExtension: String {
        (relativePath as NSString).pathExtension
    }

    /// Parent directory path
    var parentPath: String {
        (relativePath as NSString).deletingLastPathComponent
    }

    /// Formatted file size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    // MARK: - Comparison Methods

    /// Quick comparison (size and modification time only)
    func quickEquals(_ other: FileMetadata) -> Bool {
        return size == other.size &&
               abs(modifiedTime.timeIntervalSince(other.modifiedTime)) < 1.0 &&
               isDirectory == other.isDirectory
    }

    /// Full comparison (including checksum)
    func fullEquals(_ other: FileMetadata) -> Bool {
        guard quickEquals(other) else { return false }

        // If both have checksums, compare them
        if let myChecksum = checksum, let otherChecksum = other.checksum {
            return myChecksum == otherChecksum
        }

        // If no checksums available, quick comparison pass means equal
        return true
    }

    /// Check if this file is newer than another
    func isNewerThan(_ other: FileMetadata) -> Bool {
        return modifiedTime > other.modifiedTime
    }

    /// Check if content may differ from another file
    func contentMayDiffer(from other: FileMetadata) -> Bool {
        // Different size means definitely different
        if size != other.size {
            return true
        }

        // Different modification time may indicate different content
        if abs(modifiedTime.timeIntervalSince(other.modifiedTime)) >= 1.0 {
            return true
        }

        // If checksums exist and differ
        if let myChecksum = checksum, let otherChecksum = other.checksum {
            return myChecksum != otherChecksum
        }

        return false
    }

    // MARK: - Initialization

    init(
        relativePath: String,
        size: Int64,
        modifiedTime: Date,
        createdTime: Date,
        isDirectory: Bool,
        isSymlink: Bool = false,
        symlinkTarget: String? = nil,
        checksum: String? = nil,
        permissions: UInt16 = 0o644,
        ownerUID: UInt32 = 0,
        ownerGID: UInt32 = 0
    ) {
        self.relativePath = relativePath
        self.size = size
        self.modifiedTime = modifiedTime
        self.createdTime = createdTime
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.symlinkTarget = symlinkTarget
        self.checksum = checksum
        self.permissions = permissions
        self.ownerUID = ownerUID
        self.ownerGID = ownerGID
    }

    /// Create metadata from a file URL
    static func from(url: URL, relativeTo baseURL: URL) throws -> FileMetadata {
        let fileManager = FileManager.default
        let attributes = try fileManager.attributesOfItem(atPath: url.path)

        let relativePath = url.path.replacingOccurrences(
            of: baseURL.path + "/",
            with: ""
        )

        let fileType = attributes[.type] as? FileAttributeType
        let isDirectory = fileType == .typeDirectory
        let isSymlink = fileType == .typeSymbolicLink

        var symlinkTarget: String? = nil
        if isSymlink {
            symlinkTarget = try? fileManager.destinationOfSymbolicLink(atPath: url.path)
        }

        let size = (attributes[.size] as? Int64) ?? 0
        let modifiedTime = (attributes[.modificationDate] as? Date) ?? Date()
        let createdTime = (attributes[.creationDate] as? Date) ?? Date()
        let permissions = (attributes[.posixPermissions] as? UInt16) ?? 0o644
        let ownerUID = (attributes[.ownerAccountID] as? UInt32) ?? 0
        let ownerGID = (attributes[.groupOwnerAccountID] as? UInt32) ?? 0

        return FileMetadata(
            relativePath: relativePath,
            size: size,
            modifiedTime: modifiedTime,
            createdTime: createdTime,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            symlinkTarget: symlinkTarget,
            checksum: nil,
            permissions: permissions,
            ownerUID: ownerUID,
            ownerGID: ownerGID
        )
    }
}

// MARK: - File Metadata Snapshot

/// Directory snapshot - contains metadata for all files
struct DirectorySnapshot: Codable {
    /// Snapshot creation time
    let createdAt: Date

    /// Root directory path
    let rootPath: String

    /// File metadata dictionary (relative path -> metadata)
    var files: [String: FileMetadata]

    /// Total file count
    var fileCount: Int { files.count }

    /// Total size
    var totalSize: Int64 {
        files.values.reduce(0) { $0 + $1.size }
    }

    /// Directory count
    var directoryCount: Int {
        files.values.filter { $0.isDirectory }.count
    }

    init(rootPath: String, files: [String: FileMetadata] = [:]) {
        self.createdAt = Date()
        self.rootPath = rootPath
        self.files = files
    }

    /// Get metadata for a given path
    func metadata(for relativePath: String) -> FileMetadata? {
        return files[relativePath]
    }

    /// Add or update file metadata
    mutating func update(_ metadata: FileMetadata) {
        files[metadata.relativePath] = metadata
    }

    /// Remove file metadata
    mutating func remove(relativePath: String) {
        files.removeValue(forKey: relativePath)
    }
}
