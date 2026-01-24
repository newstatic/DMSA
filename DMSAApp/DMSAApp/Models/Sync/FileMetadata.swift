import Foundation

/// 文件元数据 - 用于同步比较
struct FileMetadata: Codable, Hashable, Identifiable {
    var id: String { relativePath }

    /// 相对路径 (相对于同步根目录)
    let relativePath: String

    /// 文件大小 (字节)
    let size: Int64

    /// 修改时间
    let modifiedTime: Date

    /// 创建时间
    let createdTime: Date

    /// 是否为目录
    let isDirectory: Bool

    /// 是否为符号链接
    let isSymlink: Bool

    /// 符号链接目标 (如果是符号链接)
    let symlinkTarget: String?

    /// 校验和 (MD5/SHA256)
    var checksum: String?

    /// 文件权限 (POSIX)
    let permissions: UInt16

    /// 文件所有者 UID
    let ownerUID: UInt32

    /// 文件所属组 GID
    let ownerGID: UInt32

    // MARK: - 计算属性

    /// 文件名
    var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    /// 文件扩展名
    var fileExtension: String {
        (relativePath as NSString).pathExtension
    }

    /// 父目录路径
    var parentPath: String {
        (relativePath as NSString).deletingLastPathComponent
    }

    /// 格式化的文件大小
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    // MARK: - 比较方法

    /// 快速比较 (仅比较大小和修改时间)
    func quickEquals(_ other: FileMetadata) -> Bool {
        return size == other.size &&
               abs(modifiedTime.timeIntervalSince(other.modifiedTime)) < 1.0 &&
               isDirectory == other.isDirectory
    }

    /// 完整比较 (包含校验和)
    func fullEquals(_ other: FileMetadata) -> Bool {
        guard quickEquals(other) else { return false }

        // 如果都有校验和，比较校验和
        if let myChecksum = checksum, let otherChecksum = other.checksum {
            return myChecksum == otherChecksum
        }

        // 如果没有校验和，认为快速比较通过即相等
        return true
    }

    /// 判断是否比另一个文件新
    func isNewerThan(_ other: FileMetadata) -> Bool {
        return modifiedTime > other.modifiedTime
    }

    /// 判断内容是否可能不同
    func contentMayDiffer(from other: FileMetadata) -> Bool {
        // 大小不同肯定不同
        if size != other.size {
            return true
        }

        // 修改时间不同可能不同
        if abs(modifiedTime.timeIntervalSince(other.modifiedTime)) >= 1.0 {
            return true
        }

        // 如果有校验和且不同
        if let myChecksum = checksum, let otherChecksum = other.checksum {
            return myChecksum != otherChecksum
        }

        return false
    }

    // MARK: - 初始化

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

    /// 从文件 URL 创建元数据
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

// MARK: - 文件元数据快照

/// 目录快照 - 包含所有文件的元数据
struct DirectorySnapshot: Codable {
    /// 快照创建时间
    let createdAt: Date

    /// 根目录路径
    let rootPath: String

    /// 文件元数据字典 (相对路径 -> 元数据)
    var files: [String: FileMetadata]

    /// 文件总数
    var fileCount: Int { files.count }

    /// 总大小
    var totalSize: Int64 {
        files.values.reduce(0) { $0 + $1.size }
    }

    /// 目录数量
    var directoryCount: Int {
        files.values.filter { $0.isDirectory }.count
    }

    init(rootPath: String, files: [String: FileMetadata] = [:]) {
        self.createdAt = Date()
        self.rootPath = rootPath
        self.files = files
    }

    /// 获取指定路径的元数据
    func metadata(for relativePath: String) -> FileMetadata? {
        return files[relativePath]
    }

    /// 添加或更新文件元数据
    mutating func update(_ metadata: FileMetadata) {
        files[metadata.relativePath] = metadata
    }

    /// 移除文件元数据
    mutating func remove(relativePath: String) {
        files.removeValue(forKey: relativePath)
    }
}
