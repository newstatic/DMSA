import Foundation

/// File metadata - used for sync comparison
public struct FileMetadata: Codable, Hashable, Identifiable, Sendable {
    public var id: String { relativePath }

    /// Relative path (relative to sync root directory)
    public let relativePath: String

    /// File size (bytes)
    public let size: Int64

    /// Modification time
    public let modifiedTime: Date

    /// Creation time
    public let createdTime: Date

    /// Whether it is a directory
    public let isDirectory: Bool

    /// Whether it is a symbolic link
    public let isSymlink: Bool

    /// Symbolic link target (if it is a symbolic link)
    public let symlinkTarget: String?

    /// Checksum (MD5/SHA256)
    public var checksum: String?

    /// File permissions (POSIX)
    public let permissions: UInt16

    /// File owner UID
    public let ownerUID: UInt32

    /// File group GID
    public let ownerGID: UInt32

    // MARK: - Computed Properties

    /// File name
    public var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    /// File extension
    public var fileExtension: String {
        (relativePath as NSString).pathExtension
    }

    /// Parent directory path
    public var parentPath: String {
        (relativePath as NSString).deletingLastPathComponent
    }

    /// Formatted file size
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    // MARK: - Comparison Methods

    /// Quick comparison (only compares size and modification time)
    public func quickEquals(_ other: FileMetadata) -> Bool {
        return size == other.size &&
               abs(modifiedTime.timeIntervalSince(other.modifiedTime)) < 1.0 &&
               isDirectory == other.isDirectory
    }

    /// Full comparison (includes checksum)
    public func fullEquals(_ other: FileMetadata) -> Bool {
        guard quickEquals(other) else { return false }

        // If both have checksums, compare them
        if let myChecksum = checksum, let otherChecksum = other.checksum {
            return myChecksum == otherChecksum
        }

        // If no checksum, quick comparison pass means equal
        return true
    }

    /// Check if newer than another file
    public func isNewerThan(_ other: FileMetadata) -> Bool {
        return modifiedTime > other.modifiedTime
    }

    /// Check if content may differ
    public func contentMayDiffer(from other: FileMetadata) -> Bool {
        // Different size means definitely different
        if size != other.size {
            return true
        }

        // Different modification time may mean different
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

    public init(
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

    /// Create metadata from file URL
    public static func from(url: URL, relativeTo baseURL: URL) throws -> FileMetadata {
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
public struct DirectorySnapshot: Codable, Sendable {
    /// Snapshot creation time
    public let createdAt: Date

    /// Root directory path
    public let rootPath: String

    /// File metadata dictionary (relative path -> metadata)
    public var files: [String: FileMetadata]

    /// Total file count
    public var fileCount: Int { files.count }

    /// Total size
    public var totalSize: Int64 {
        files.values.reduce(0) { $0 + $1.size }
    }

    /// Directory count
    public var directoryCount: Int {
        files.values.filter { $0.isDirectory }.count
    }

    public init(rootPath: String, files: [String: FileMetadata] = [:]) {
        self.createdAt = Date()
        self.rootPath = rootPath
        self.files = files
    }

    /// Get metadata for specified path
    public func metadata(for relativePath: String) -> FileMetadata? {
        return files[relativePath]
    }

    /// Add or update file metadata
    public mutating func update(_ metadata: FileMetadata) {
        files[metadata.relativePath] = metadata
    }

    /// Remove file metadata
    public mutating func remove(relativePath: String) {
        files.removeValue(forKey: relativePath)
    }
}
