import Cocoa

/// 硬盘管理器 (App 端)
///
/// v4.6: 纯事件监听器，通过 XPC 获取配置和通知 DMSAService
/// 核心业务逻辑在 ServiceDiskMonitor 中处理
final class DiskManager {
    static let shared = DiskManager()

    private let workspace = NSWorkspace.shared
    private let fileManager = FileManager.default

    /// UI 回调 (用于状态栏更新等)
    var onDiskConnected: ((DiskConfig) -> Void)?
    var onDiskDisconnected: ((DiskConfig) -> Void)?

    /// 当前已连接的硬盘 (本地缓存)
    private(set) var connectedDisks: [String: DiskConfig] = [:]

    /// 缓存的磁盘配置
    private var cachedDisks: [DiskConfig] = []
    private var lastConfigFetch: Date?
    private let configCacheTimeout: TimeInterval = 30 // 30秒缓存

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

    // MARK: - Config Cache

    /// 获取磁盘配置 (带缓存)
    private func getDisks() async -> [DiskConfig] {
        // 检查缓存是否有效
        if let lastFetch = lastConfigFetch,
           Date().timeIntervalSince(lastFetch) < configCacheTimeout,
           !cachedDisks.isEmpty {
            return cachedDisks
        }

        // 从服务获取配置
        do {
            let disks = try await ServiceClient.shared.getDisks()
            cachedDisks = disks
            lastConfigFetch = Date()
            return disks
        } catch {
            Logger.shared.error("获取磁盘配置失败: \(error)")
            return cachedDisks
        }
    }

    /// 使配置缓存失效
    func invalidateConfigCache() {
        cachedDisks = []
        lastConfigFetch = nil
    }

    // MARK: - Event Handlers

    @objc private func handleDiskMount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        Logger.shared.info("硬盘挂载事件: \(devicePath)")

        // 异步处理
        Task {
            let disks = await getDisks()

            // 查找匹配的配置硬盘 (使用精确匹配)
            for disk in disks where disk.enabled {
                if matchesDisk(devicePath: devicePath, disk: disk) {
                    Logger.shared.info("目标硬盘 \(disk.name) 已连接: \(devicePath)")

                    // 延迟执行，等待挂载稳定
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒

                    await MainActor.run {
                        self.connectedDisks[disk.id] = disk
                        self.onDiskConnected?(disk)
                    }

                    // 通知 DMSAService
                    try? await ServiceClient.shared.notifyDiskConnected(
                        diskName: disk.name,
                        mountPoint: devicePath
                    )
                    return
                }
            }
        }
    }

    @objc private func handleDiskUnmount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        Logger.shared.info("硬盘已卸载: \(devicePath)")

        // 异步处理
        Task {
            let disks = await getDisks()

            // 查找匹配的硬盘 (使用精确匹配)
            for disk in disks {
                if matchesDisk(devicePath: devicePath, disk: disk) {
                    Logger.shared.info("目标硬盘 \(disk.name) 已断开")

                    await MainActor.run {
                        self.connectedDisks.removeValue(forKey: disk.id)
                        self.onDiskDisconnected?(disk)
                    }

                    // 通知 DMSAService
                    try? await ServiceClient.shared.notifyDiskDisconnected(diskName: disk.name)
                    return
                }
            }
        }
    }

    // MARK: - 磁盘匹配

    /// 精确匹配磁盘
    /// 优先级: 1. 完全路径匹配 2. 卷名匹配 (/Volumes/NAME)
    private func matchesDisk(devicePath: String, disk: DiskConfig) -> Bool {
        // 1. 完全路径匹配
        if devicePath == disk.mountPath {
            return true
        }

        // 2. 卷名匹配: /Volumes/{name}
        let volumePath = "/Volumes/\(disk.name)"
        if devicePath == volumePath {
            return true
        }

        // 3. 路径末尾匹配 (处理 /Volumes/BACKUP-1 这种情况)
        let pathComponents = devicePath.split(separator: "/")
        if let lastComponent = pathComponents.last {
            // 精确匹配卷名
            if String(lastComponent) == disk.name {
                return true
            }
            // 处理带序号的卷名 (如 BACKUP-1, BACKUP 1)
            let normalizedName = String(lastComponent)
                .replacingOccurrences(of: " ", with: "-")
            // 移除末尾数字后缀
            if let range = normalizedName.range(of: "-\\d+$", options: .regularExpression) {
                let baseName = String(normalizedName[..<range.lowerBound])
                if baseName == disk.name {
                    return true
                }
            }
        }

        return false
    }

    /// 检查初始状态
    func checkInitialState() {
        Logger.shared.info("检查硬盘初始状态...")

        Task {
            let disks = await getDisks()

            for disk in disks where disk.enabled {
                if fileManager.fileExists(atPath: disk.mountPath) {
                    Logger.shared.info("硬盘 \(disk.name) 已连接: \(disk.mountPath)")

                    await MainActor.run {
                        self.connectedDisks[disk.id] = disk
                        self.onDiskConnected?(disk)
                    }

                    // 通知 DMSAService
                    try? await ServiceClient.shared.notifyDiskConnected(
                        diskName: disk.name,
                        mountPoint: disk.mountPath
                    )
                } else {
                    Logger.shared.info("硬盘 \(disk.name) 未连接")
                }
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

    /// 获取磁盘空间信息
    func getDiskInfo(at path: String) -> (total: Int64, available: Int64, used: Int64)? {
        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: path)
            guard let total = attrs[.systemSize] as? Int64,
                  let free = attrs[.systemFreeSize] as? Int64 else {
                return nil
            }
            return (total: total, available: free, used: total - free)
        } catch {
            Logger.shared.error("获取磁盘信息失败: \(error)")
            return nil
        }
    }

    deinit {
        workspace.notificationCenter.removeObserver(self)
    }
}
