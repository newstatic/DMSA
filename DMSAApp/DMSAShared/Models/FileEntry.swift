import Foundation

/// 同步锁定状态
public enum LockState: Int, Codable, Sendable {
    case unlocked = 0
    case syncLocked = 1
}

/// 同步方向（用于锁定时确定源路径）
public enum SyncLockDirection: Int, Codable, Sendable {
    case localToExternal = 0
    case externalToLocal = 1
}

/// 文件索引实体
public final class FileEntry: Identifiable, Codable, @unchecked Sendable {
    public var id: UInt64
    public var virtualPath: String
    public var localPath: String?
    public var externalPath: String?
    public var location: FileLocation
    public var size: Int64
    public var createdAt: Date
    public var modifiedAt: Date
    public var accessedAt: Date
    public var checksum: String?
    public var isDirty: Bool
    public var syncPairId: String?
    public var diskId: String?
    public var isDirectory: Bool

    // 同步锁定相关
    public var lockState: LockState
    public var lockTime: Date?
    public var lockDirection: SyncLockDirection?

    public static let lockTimeout: TimeInterval = 30.0
    public static let writeWaitTimeout: TimeInterval = 5.0

    public init() {
        self.id = 0
        self.virtualPath = ""
        self.localPath = nil
        self.externalPath = nil
        self.location = .notExists
        self.size = 0
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.accessedAt = Date()
        self.checksum = nil
        self.isDirty = false
        self.syncPairId = nil
        self.diskId = nil
        self.isDirectory = false
        self.lockState = .unlocked
        self.lockTime = nil
        self.lockDirection = nil
    }

    public init(virtualPath: String, localPath: String? = nil, externalPath: String? = nil) {
        self.id = 0
        self.virtualPath = virtualPath
        self.localPath = localPath
        self.externalPath = externalPath
        self.location = .notExists
        self.size = 0
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.accessedAt = Date()
        self.checksum = nil
        self.isDirty = false
        self.syncPairId = nil
        self.diskId = nil
        self.isDirectory = false
        self.lockState = .unlocked
        self.lockTime = nil
        self.lockDirection = nil
    }

    public var fileName: String {
        return (virtualPath as NSString).lastPathComponent
    }

    public var fileExtension: String {
        return (virtualPath as NSString).pathExtension
    }

    public var parentPath: String {
        return (virtualPath as NSString).deletingLastPathComponent
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    public var needsSync: Bool {
        return isDirty || location == .localOnly || location == .externalOnly
    }

    public var isLocked: Bool {
        return lockState == .syncLocked
    }

    public var isLockExpired: Bool {
        guard lockState == .syncLocked, let lockTime = lockTime else {
            return false
        }
        return Date().timeIntervalSince(lockTime) > FileEntry.lockTimeout
    }

    public var syncSourcePath: String? {
        guard lockState == .syncLocked, let direction = lockDirection else {
            return nil
        }
        switch direction {
        case .localToExternal:
            return localPath
        case .externalToLocal:
            return externalPath
        }
    }

    public func lock(direction: SyncLockDirection) {
        lockState = .syncLocked
        lockTime = Date()
        lockDirection = direction
    }

    public func unlock() {
        lockState = .unlocked
        lockTime = nil
        lockDirection = nil
    }

    /// 转换为字典 (用于 XPC 传输)
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "virtualPath": virtualPath,
            "location": location.rawValue,
            "size": size,
            "createdAt": createdAt.timeIntervalSince1970,
            "modifiedAt": modifiedAt.timeIntervalSince1970,
            "accessedAt": accessedAt.timeIntervalSince1970,
            "isDirty": isDirty,
            "isDirectory": isDirectory,
            "lockState": lockState.rawValue
        ]

        if let localPath = localPath { dict["localPath"] = localPath }
        if let externalPath = externalPath { dict["externalPath"] = externalPath }
        if let checksum = checksum { dict["checksum"] = checksum }
        if let syncPairId = syncPairId { dict["syncPairId"] = syncPairId }
        if let diskId = diskId { dict["diskId"] = diskId }

        return dict
    }

    /// 从字典创建 (用于 XPC 传输)
    public static func from(dictionary dict: [String: Any]) -> FileEntry? {
        guard let virtualPath = dict["virtualPath"] as? String else { return nil }

        let entry = FileEntry(virtualPath: virtualPath)
        entry.id = dict["id"] as? UInt64 ?? 0
        entry.localPath = dict["localPath"] as? String
        entry.externalPath = dict["externalPath"] as? String
        entry.location = FileLocation(rawValue: dict["location"] as? Int ?? 0) ?? .notExists
        entry.size = dict["size"] as? Int64 ?? 0
        entry.isDirty = dict["isDirty"] as? Bool ?? false
        entry.isDirectory = dict["isDirectory"] as? Bool ?? false
        entry.checksum = dict["checksum"] as? String
        entry.syncPairId = dict["syncPairId"] as? String
        entry.diskId = dict["diskId"] as? String
        entry.lockState = LockState(rawValue: dict["lockState"] as? Int ?? 0) ?? .unlocked

        if let createdAt = dict["createdAt"] as? TimeInterval {
            entry.createdAt = Date(timeIntervalSince1970: createdAt)
        }
        if let modifiedAt = dict["modifiedAt"] as? TimeInterval {
            entry.modifiedAt = Date(timeIntervalSince1970: modifiedAt)
        }
        if let accessedAt = dict["accessedAt"] as? TimeInterval {
            entry.accessedAt = Date(timeIntervalSince1970: accessedAt)
        }

        return entry
    }
}

// MARK: - Equatable & Hashable

extension FileEntry: Equatable {
    public static func == (lhs: FileEntry, rhs: FileEntry) -> Bool {
        return lhs.id == rhs.id && lhs.virtualPath == rhs.virtualPath
    }
}

extension FileEntry: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(virtualPath)
    }
}
