import Foundation

/// Sync pair persistence entity
/// Used to persist SyncPairConfig to the database
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

    /// Convert to SyncPairConfig
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

    /// Expanded local path
    var expandedLocalPath: String {
        return (localPath as NSString).expandingTildeInPath
    }

    /// Compute full path on external disk
    func externalFullPath(diskMountPath: String) -> String {
        return (diskMountPath as NSString).appendingPathComponent(externalRelativePath)
    }

    /// Formatted bytes transferred
    var formattedBytesTransferred: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytesTransferred)
    }

    /// Formatted last sync time
    var formattedLastSync: String? {
        guard let date = lastSyncAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    /// Update sync statistics
    func updateSyncStats(bytesTransferred: Int64) {
        syncCount += 1
        totalBytesTransferred += bytesTransferred
        lastSyncAt = Date()
    }

    /// Local path display name
    var localPathDisplayName: String {
        return (localPath as NSString).lastPathComponent
    }

    /// External path display name
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
