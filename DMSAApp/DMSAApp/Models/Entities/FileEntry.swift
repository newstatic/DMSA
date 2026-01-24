import Foundation

/// 同步锁定状态
enum LockState: Int, Codable {
    case unlocked = 0       // 未锁定，可正常读写
    case syncLocked = 1     // 同步锁定中，读取允许但写入阻塞
}

/// 同步方向（用于锁定时确定源路径）
enum SyncLockDirection: Int, Codable {
    case localToExternal = 0   // LOCAL -> EXTERNAL
    case externalToLocal = 1   // EXTERNAL -> LOCAL
}

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

    /// 是否为目录
    var isDirectory: Bool = false

    // === 同步锁定相关 ===

    /// 同步锁定状态
    var lockState: LockState = .unlocked

    /// 锁定开始时间
    var lockTime: Date?

    /// 锁定时的同步方向（用于确定读取源）
    var lockDirection: SyncLockDirection?

    /// 锁定超时时间（秒）
    static let lockTimeout: TimeInterval = 30.0

    /// 写入等待超时时间（秒）
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

    /// 是否被锁定
    var isLocked: Bool {
        return lockState == .syncLocked
    }

    /// 检查锁定是否已超时
    var isLockExpired: Bool {
        guard lockState == .syncLocked, let lockTime = lockTime else {
            return false
        }
        return Date().timeIntervalSince(lockTime) > FileEntry.lockTimeout
    }

    /// 获取同步时的源路径（用于读取锁定文件）
    var syncSourcePath: String? {
        guard lockState == .syncLocked, let direction = lockDirection else {
            return nil
        }
        switch direction {
        case .localToExternal:
            return localPath  // 从 LOCAL 同步到 EXTERNAL，源是 LOCAL
        case .externalToLocal:
            return externalPath  // 从 EXTERNAL 同步到 LOCAL，源是 EXTERNAL
        }
    }

    /// 锁定文件（同步开始时调用）
    func lock(direction: SyncLockDirection) {
        lockState = .syncLocked
        lockTime = Date()
        lockDirection = direction
    }

    /// 解锁文件（同步完成时调用）
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
