import Foundation

/// Disk configuration persistence entity
/// Used to persist DiskConfig to the database
class DiskConfigEntity: Identifiable, Codable {
    var id: UInt64 = 0
    var diskId: String = ""
    var name: String = ""
    var mountPath: String = ""
    var priority: Int = 0
    var enabled: Bool = true
    var fileSystem: String = "auto"
    var lastConnectedAt: Date?
    var lastDisconnectedAt: Date?
    var totalSpace: Int64 = 0
    var usedSpace: Int64 = 0

    init() {}

    init(from config: DiskConfig) {
        self.diskId = config.id
        self.name = config.name
        self.mountPath = config.mountPath
        self.priority = config.priority
        self.enabled = config.enabled
        self.fileSystem = config.fileSystem
    }

    /// Convert to DiskConfig
    func toConfig() -> DiskConfig {
        var config = DiskConfig(name: name, mountPath: mountPath, priority: priority)
        config.enabled = enabled
        config.fileSystem = fileSystem
        return config
    }

    /// Available space
    var availableSpace: Int64 {
        return totalSpace - usedSpace
    }

    /// Usage percentage
    var usagePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace) * 100
    }

    /// Formatted total space
    var formattedTotalSpace: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSpace)
    }

    /// Formatted used space
    var formattedUsedSpace: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: usedSpace)
    }

    /// Formatted available space
    var formattedAvailableSpace: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: availableSpace)
    }

    /// Formatted last connected time
    var formattedLastConnected: String? {
        guard let date = lastConnectedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    /// Mark as connected
    func markConnected() {
        lastConnectedAt = Date()
    }

    /// Mark as disconnected
    func markDisconnected() {
        lastDisconnectedAt = Date()
    }

    /// Update space info
    func updateSpaceInfo(total: Int64, used: Int64) {
        totalSpace = total
        usedSpace = used
    }
}

// MARK: - DiskConfigEntity Equatable

extension DiskConfigEntity: Equatable {
    static func == (lhs: DiskConfigEntity, rhs: DiskConfigEntity) -> Bool {
        return lhs.id == rhs.id && lhs.diskId == rhs.diskId
    }
}

// MARK: - DiskConfigEntity Hashable

extension DiskConfigEntity: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(diskId)
    }
}
