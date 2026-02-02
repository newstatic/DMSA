import Foundation

/// Service-side disk monitor
/// Handles disk event notifications from the App side and executes related business logic
actor ServiceDiskMonitor {

    // MARK: - Properties

    private let logger = Logger.forService("DiskMonitor")
    private let fileManager = FileManager.default

    /// Currently connected disks [diskId: mountPath]
    private var connectedDisks: [String: String] = [:]

    /// Disk connected callback
    var onDiskConnected: ((String, String) async -> Void)?

    /// Disk disconnected callback
    var onDiskDisconnected: ((String) async -> Void)?

    // MARK: - Public Methods

    /// Handle disk connected event (notified by App via XPC)
    func handleDiskConnected(diskName: String, mountPath: String) async {
        logger.info("Disk connected: \(diskName) at \(mountPath)")

        // Verify path exists
        guard fileManager.fileExists(atPath: mountPath) else {
            logger.error("Disk path does not exist: \(mountPath)")
            return
        }

        connectedDisks[diskName] = mountPath

        // Trigger callback
        await onDiskConnected?(diskName, mountPath)
    }

    /// Handle disk disconnected event (notified by App via XPC)
    func handleDiskDisconnected(diskName: String) async {
        logger.info("Disk disconnected: \(diskName)")

        connectedDisks.removeValue(forKey: diskName)

        // Trigger callback
        await onDiskDisconnected?(diskName)
    }

    /// Check if a disk is connected
    func isDiskConnected(_ diskName: String) -> Bool {
        return connectedDisks[diskName] != nil
    }

    /// Get disk mount path
    func getDiskMountPath(_ diskName: String) -> String? {
        return connectedDisks[diskName]
    }

    /// Get all connected disks
    func getConnectedDisks() -> [String: String] {
        return connectedDisks
    }

    /// Check if any disk is connected
    var isAnyDiskConnected: Bool {
        !connectedDisks.isEmpty
    }

    // MARK: - Disk Info

    /// Get disk info
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
            logger.error("Failed to get disk info (\(path)): \(error.localizedDescription)")
            return nil
        }
    }

    /// Get disk usage percentage
    func getDiskUsagePercentage(at path: String) -> Double? {
        guard let info = getDiskInfo(at: path) else { return nil }
        guard info.totalSpace > 0 else { return nil }
        return Double(info.usedSpace) / Double(info.totalSpace) * 100.0
    }

    /// Check if disk has enough available space
    func hasEnoughSpace(at path: String, requiredBytes: Int64, reserveBuffer: Int64 = 1_073_741_824) -> Bool {
        guard let info = getDiskInfo(at: path) else { return false }
        return info.availableSpace >= (requiredBytes + reserveBuffer)
    }

    /// Health check
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
