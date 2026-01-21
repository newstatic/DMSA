import Foundation

/// 文件索引实体
/// 用于追踪文件在本地和外置硬盘上的位置和状态
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

    init() {}

    init(virtualPath: String, localPath: String? = nil, externalPath: String? = nil) {
        self.virtualPath = virtualPath
        self.localPath = localPath
        self.externalPath = externalPath
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.accessedAt = Date()
    }

    /// 文件名
    var fileName: String {
        return (virtualPath as NSString).lastPathComponent
    }

    /// 文件扩展名
    var fileExtension: String {
        return (virtualPath as NSString).pathExtension
    }

    /// 父目录路径
    var parentPath: String {
        return (virtualPath as NSString).deletingLastPathComponent
    }

    /// 格式化文件大小
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// 是否需要同步
    var needsSync: Bool {
        return isDirty || location == .localOnly || location == .externalOnly
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
