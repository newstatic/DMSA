import Cocoa

/// 硬盘管理器 (App 端)
///
/// v4.3: 仅负责监听硬盘事件并通过 XPC 通知 DMSAService
/// 核心业务逻辑在 ServiceDiskMonitor 中处理
final class DiskManager {
    static let shared = DiskManager()

    private let workspace = NSWorkspace.shared
    private let configManager = ConfigManager.shared
    private let fileManager = FileManager.default

    /// UI 回调 (用于状态栏更新等)
    var onDiskConnected: ((DiskConfig) -> Void)?
    var onDiskDisconnected: ((DiskConfig) -> Void)?

    /// 当前已连接的硬盘 (本地缓存)
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
                Logger.shared.info("目标硬盘 \(disk.name) 已连接: \(devicePath)")

                // 延迟执行，等待挂载稳定
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.connectedDisks[disk.id] = disk
                    self?.onDiskConnected?(disk)

                    // 通知 DMSAService
                    Task {
                        try? await ServiceClient.shared.notifyDiskConnected(
                            diskName: disk.name,
                            mountPoint: devicePath
                        )
                    }
                }
                return
            }
        }
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

                // 通知 DMSAService
                Task {
                    try? await ServiceClient.shared.notifyDiskDisconnected(diskName: disk.name)
                }
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

                // 通知 DMSAService
                Task {
                    try? await ServiceClient.shared.notifyDiskConnected(
                        diskName: disk.name,
                        mountPoint: disk.mountPath
                    )
                }
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

    deinit {
        workspace.notificationCenter.removeObserver(self)
    }
}
