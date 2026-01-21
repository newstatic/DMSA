import Foundation

/// 同步对持久化实体
/// 用于将 SyncPairConfig 保存到数据库
class SyncPairEntity: Identifiable, Codable {
    var id: UInt64 = 0
    var pairId: String = ""
    var diskId: String = ""
    var localPath: String = ""
    var externalRelativePath: String = ""
    var direction: SyncDirection = .localToExternal
    var createSymlink: Bool = true
    var enabled: Bool = true
    var lastSyncAt: Date?
    var syncCount: Int = 0
    var totalBytesTransferred: Int64 = 0

    init() {}

    init(from config: SyncPairConfig) {
        self.pairId = config.id
        self.diskId = config.diskId
        self.localPath = config.localPath
        self.externalRelativePath = config.externalRelativePath
        self.direction = config.direction
        self.createSymlink = config.createSymlink
        self.enabled = config.enabled
    }

    /// 转换为 SyncPairConfig
    func toConfig() -> SyncPairConfig {
        var config = SyncPairConfig(
            diskId: diskId,
            localPath: localPath,
            externalRelativePath: externalRelativePath
        )
        config.direction = direction
        config.createSymlink = createSymlink
        config.enabled = enabled
        return config
    }

    /// 展开本地路径
    var expandedLocalPath: String {
        return (localPath as NSString).expandingTildeInPath
    }

    /// 计算外置硬盘完整路径
    func externalFullPath(diskMountPath: String) -> String {
        return (diskMountPath as NSString).appendingPathComponent(externalRelativePath)
    }

    /// 格式化传输大小
    var formattedBytesTransferred: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytesTransferred)
    }

    /// 格式化最后同步时间
    var formattedLastSync: String? {
        guard let date = lastSyncAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    /// 更新同步统计
    func updateSyncStats(bytesTransferred: Int64) {
        syncCount += 1
        totalBytesTransferred += bytesTransferred
        lastSyncAt = Date()
    }

    /// 本地路径显示名称
    var localPathDisplayName: String {
        return (localPath as NSString).lastPathComponent
    }

    /// 外置路径显示名称
    var externalPathDisplayName: String {
        return (externalRelativePath as NSString).lastPathComponent
    }
}

// MARK: - SyncPairEntity Equatable

extension SyncPairEntity: Equatable {
    static func == (lhs: SyncPairEntity, rhs: SyncPairEntity) -> Bool {
        return lhs.id == rhs.id && lhs.pairId == rhs.pairId
    }
}

// MARK: - SyncPairEntity Hashable

extension SyncPairEntity: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(pairId)
    }
}
