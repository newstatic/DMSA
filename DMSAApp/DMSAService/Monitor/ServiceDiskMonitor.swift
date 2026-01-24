import Foundation

/// Service 端磁盘监控器
/// 处理来自 App 端的磁盘事件通知，执行相关业务逻辑
actor ServiceDiskMonitor {

    // MARK: - Properties

    private let logger = Logger.forService("DiskMonitor")
    private let fileManager = FileManager.default

    /// 当前已连接的磁盘 [diskId: mountPath]
    private var connectedDisks: [String: String] = [:]

    /// 磁盘连接回调
    var onDiskConnected: ((String, String) async -> Void)?

    /// 磁盘断开回调
    var onDiskDisconnected: ((String) async -> Void)?

    // MARK: - Public Methods

    /// 处理磁盘连接事件 (由 App 通过 XPC 通知)
    func handleDiskConnected(diskName: String, mountPath: String) async {
        logger.info("磁盘已连接: \(diskName) at \(mountPath)")

        // 验证路径存在
        guard fileManager.fileExists(atPath: mountPath) else {
            logger.error("磁盘路径不存在: \(mountPath)")
            return
        }

        connectedDisks[diskName] = mountPath

        // 触发回调
        await onDiskConnected?(diskName, mountPath)
    }

    /// 处理磁盘断开事件 (由 App 通过 XPC 通知)
    func handleDiskDisconnected(diskName: String) async {
        logger.info("磁盘已断开: \(diskName)")

        connectedDisks.removeValue(forKey: diskName)

        // 触发回调
        await onDiskDisconnected?(diskName)
    }

    /// 检查磁盘是否已连接
    func isDiskConnected(_ diskName: String) -> Bool {
        return connectedDisks[diskName] != nil
    }

    /// 获取磁盘挂载路径
    func getDiskMountPath(_ diskName: String) -> String? {
        return connectedDisks[diskName]
    }

    /// 获取所有已连接磁盘
    func getConnectedDisks() -> [String: String] {
        return connectedDisks
    }

    /// 检查任意磁盘是否已连接
    var isAnyDiskConnected: Bool {
        !connectedDisks.isEmpty
    }

    // MARK: - Disk Info

    /// 获取磁盘信息
    func getDiskInfo(at path: String) -> DiskInfo? {
        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: path)
            let total = attrs[.systemSize] as? Int64 ?? 0
            let available = attrs[.systemFreeSize] as? Int64 ?? 0
            let used = total - available

            return DiskInfo(
                totalSpace: total,
                availableSpace: available,
                usedSpace: used,
                path: path
            )
        } catch {
            logger.error("获取磁盘信息失败 (\(path)): \(error.localizedDescription)")
            return nil
        }
    }

    /// 获取磁盘使用率
    func getDiskUsagePercentage(at path: String) -> Double? {
        guard let info = getDiskInfo(at: path) else { return nil }
        guard info.totalSpace > 0 else { return nil }
        return Double(info.usedSpace) / Double(info.totalSpace) * 100.0
    }

    /// 检查磁盘可用空间是否充足
    func hasEnoughSpace(at path: String, requiredBytes: Int64, reserveBuffer: Int64 = 1_073_741_824) -> Bool {
        guard let info = getDiskInfo(at: path) else { return false }
        return info.availableSpace >= (requiredBytes + reserveBuffer)
    }

    /// 健康检查
    func healthCheck() -> Bool {
        return true
    }
}

// MARK: - DiskInfo

struct DiskInfo: Codable, Sendable {
    let totalSpace: Int64
    let availableSpace: Int64
    let usedSpace: Int64
    let path: String

    var usagePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace) * 100.0
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalSpace, countStyle: .file)
    }

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedSpace, countStyle: .file)
    }
}
