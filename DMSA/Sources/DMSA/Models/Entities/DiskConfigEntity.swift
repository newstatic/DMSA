import Foundation

/// 硬盘配置持久化实体
/// 用于将 DiskConfig 保存到数据库
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

    /// 转换为 DiskConfig
    func toConfig() -> DiskConfig {
        var config = DiskConfig(name: name, mountPath: mountPath, priority: priority)
        config.enabled = enabled
        config.fileSystem = fileSystem
        return config
    }

    /// 可用空间
    var availableSpace: Int64 {
        return totalSpace - usedSpace
    }

    /// 使用率
    var usagePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace) * 100
    }

    /// 格式化总空间
    var formattedTotalSpace: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSpace)
    }

    /// 格式化已用空间
    var formattedUsedSpace: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: usedSpace)
    }

    /// 格式化可用空间
    var formattedAvailableSpace: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: availableSpace)
    }

    /// 格式化最后连接时间
    var formattedLastConnected: String? {
        guard let date = lastConnectedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    /// 标记连接
    func markConnected() {
        lastConnectedAt = Date()
    }

    /// 标记断开
    func markDisconnected() {
        lastDisconnectedAt = Date()
    }

    /// 更新空间信息
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
