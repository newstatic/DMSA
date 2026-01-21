import Cocoa

/// 硬盘管理器
final class DiskManager {
    static let shared = DiskManager()

    private let workspace = NSWorkspace.shared
    private let configManager = ConfigManager.shared
    private let fileManager = FileManager.default

    var onDiskConnected: ((DiskConfig) -> Void)?
    var onDiskDisconnected: ((DiskConfig) -> Void)?

    /// 当前已连接的硬盘
    private(set) var connectedDisks: [String: DiskConfig] = [:]

    private init() {
        registerNotifications()
    }

    private func registerNotifications() {
        let nc = workspace.notificationCenter

        nc.addObserver(
            self,
            selector: #selector(handleDiskMount(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(handleDiskWillUnmount(_:)),
            name: NSWorkspace.willUnmountNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(handleDiskUnmount(_:)),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )

        Logger.shared.info("硬盘事件监听已注册")
    }

    @objc private func handleDiskMount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        Logger.shared.info("硬盘挂载事件: \(devicePath)")

        // 查找匹配的配置硬盘
        for disk in configManager.config.disks where disk.enabled {
            if devicePath.contains(disk.name) || devicePath == disk.mountPath {
                Logger.shared.info("目标硬盘 \(disk.name) 已连接，路径: \(devicePath)")

                // 延迟执行，等待挂载稳定
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.connectedDisks[disk.id] = disk
                    self?.onDiskConnected?(disk)
                }
                return
            }
        }

        Logger.shared.debug("非目标硬盘: \(devicePath)")
    }

    @objc private func handleDiskWillUnmount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        Logger.shared.info("硬盘即将卸载: \(devicePath)")
    }

    @objc private func handleDiskUnmount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        Logger.shared.info("硬盘已卸载: \(devicePath)")

        // 查找匹配的硬盘
        for disk in configManager.config.disks {
            if devicePath.contains(disk.name) || devicePath == disk.mountPath {
                Logger.shared.info("目标硬盘 \(disk.name) 已断开")
                connectedDisks.removeValue(forKey: disk.id)
                onDiskDisconnected?(disk)
                return
            }
        }
    }

    /// 检查初始状态
    func checkInitialState() {
        Logger.shared.info("检查硬盘初始状态...")

        for disk in configManager.config.disks where disk.enabled {
            if fileManager.fileExists(atPath: disk.mountPath) {
                Logger.shared.info("硬盘 \(disk.name) 已连接: \(disk.mountPath)")
                connectedDisks[disk.id] = disk
                onDiskConnected?(disk)
            } else {
                Logger.shared.info("硬盘 \(disk.name) 未连接")
            }
        }
    }

    /// 检查硬盘是否已连接
    func isDiskConnected(_ diskId: String) -> Bool {
        return connectedDisks[diskId] != nil
    }

    /// 检查任意外置硬盘是否已连接
    var isAnyExternalConnected: Bool {
        return !connectedDisks.isEmpty
    }

    /// 获取硬盘信息
    func getDiskInfo(at path: String) -> (total: Int64, available: Int64, used: Int64)? {
        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: path)
            let total = attrs[.systemSize] as? Int64 ?? 0
            let available = attrs[.systemFreeSize] as? Int64 ?? 0
            let used = total - available
            return (total, available, used)
        } catch {
            Logger.shared.error("获取硬盘信息失败 (\(path)): \(error.localizedDescription)")
            return nil
        }
    }

    /// 获取硬盘使用率
    func getDiskUsagePercentage(at path: String) -> Double? {
        guard let info = getDiskInfo(at: path) else { return nil }
        guard info.total > 0 else { return nil }
        return Double(info.used) / Double(info.total) * 100.0
    }

    /// 检查硬盘可用空间是否充足
    func hasEnoughSpace(at path: String, requiredBytes: Int64) -> Bool {
        guard let info = getDiskInfo(at: path) else { return false }
        let reserveBuffer = configManager.config.cache.reserveBuffer
        return info.available >= (requiredBytes + reserveBuffer)
    }

    /// 获取挂载的所有卷
    func getMountedVolumes() -> [URL] {
        let volumesURL = URL(fileURLWithPath: "/Volumes")

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: volumesURL,
                includingPropertiesForKeys: [.isVolumeKey, .volumeNameKey],
                options: [.skipsHiddenFiles]
            )
            return contents.filter { url in
                (try? url.resourceValues(forKeys: [.isVolumeKey]).isVolume) == true
            }
        } catch {
            Logger.shared.error("获取卷列表失败: \(error.localizedDescription)")
            return []
        }
    }

    /// 安全弹出硬盘
    func ejectDisk(at path: String, completion: @escaping (Bool, Error?) -> Void) {
        let url = URL(fileURLWithPath: path)

        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            Logger.shared.info("硬盘已安全弹出: \(path)")
            completion(true, nil)
        } catch {
            Logger.shared.error("弹出硬盘失败: \(error.localizedDescription)")
            completion(false, error)
        }
    }

    deinit {
        workspace.notificationCenter.removeObserver(self)
    }
}
