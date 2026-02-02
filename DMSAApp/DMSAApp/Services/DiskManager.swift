import Cocoa

/// Disk manager (App side)
///
/// v4.6: Pure event listener, fetches config via XPC and notifies DMSAService
/// Core business logic handled in ServiceDiskMonitor
final class DiskManager {
    static let shared = DiskManager()

    private let workspace = NSWorkspace.shared
    private let fileManager = FileManager.default

    /// UI callback (for status bar updates etc.)
    var onDiskConnected: ((DiskConfig) -> Void)?
    var onDiskDisconnected: ((DiskConfig) -> Void)?

    /// Currently connected disks (local cache)
    private(set) var connectedDisks: [String: DiskConfig] = [:]

    /// Cached disk config
    private var cachedDisks: [DiskConfig] = []
    private var lastConfigFetch: Date?
    private let configCacheTimeout: TimeInterval = 30 // 30s cache

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

        Logger.shared.info("Disk event listener registered")
    }

    // MARK: - Config Cache

    /// Get disk config (with cache)
    private func getDisks() async -> [DiskConfig] {
        // Check if cache is valid
        if let lastFetch = lastConfigFetch,
           Date().timeIntervalSince(lastFetch) < configCacheTimeout,
           !cachedDisks.isEmpty {
            return cachedDisks
        }

        // Fetch config from service
        do {
            let disks = try await ServiceClient.shared.getDisks()
            cachedDisks = disks
            lastConfigFetch = Date()
            return disks
        } catch {
            Logger.shared.error("Failed to get disk config: \(error)")
            return cachedDisks
        }
    }

    /// Invalidate config cache
    func invalidateConfigCache() {
        cachedDisks = []
        lastConfigFetch = nil
    }

    // MARK: - Event Handlers

    @objc private func handleDiskMount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        Logger.shared.info("Disk mount event: \(devicePath)")

        // Async processing
        Task {
            let disks = await getDisks()

            // Find matching configured disk (exact match)
            for disk in disks where disk.enabled {
                if matchesDisk(devicePath: devicePath, disk: disk) {
                    Logger.shared.info("Target disk \(disk.name) connected: \(devicePath)")

                    // Delay to wait for mount to stabilize
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s

                    await MainActor.run {
                        self.connectedDisks[disk.id] = disk
                        self.onDiskConnected?(disk)
                    }

                    // Notify DMSAService
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
        Logger.shared.info("Disk unmounted: \(devicePath)")

        // Async processing
        Task {
            let disks = await getDisks()

            // Find matching disk (exact match)
            for disk in disks {
                if matchesDisk(devicePath: devicePath, disk: disk) {
                    Logger.shared.info("Target disk \(disk.name) disconnected")

                    await MainActor.run {
                        self.connectedDisks.removeValue(forKey: disk.id)
                        self.onDiskDisconnected?(disk)
                    }

                    // Notify DMSAService
                    try? await ServiceClient.shared.notifyDiskDisconnected(diskName: disk.name)
                    return
                }
            }
        }
    }

    // MARK: - Disk Matching

    /// Exact disk matching
    /// Priority: 1. Full path match 2. Volume name match (/Volumes/NAME)
    private func matchesDisk(devicePath: String, disk: DiskConfig) -> Bool {
        // 1. Full path match
        if devicePath == disk.mountPath {
            return true
        }

        // 2. Volume name match: /Volumes/{name}
        let volumePath = "/Volumes/\(disk.name)"
        if devicePath == volumePath {
            return true
        }

        // 3. Path suffix match (handles /Volumes/BACKUP-1 cases)
        let pathComponents = devicePath.split(separator: "/")
        if let lastComponent = pathComponents.last {
            // Exact volume name match
            if String(lastComponent) == disk.name {
                return true
            }
            // Handle numbered volume names (e.g. BACKUP-1, BACKUP 1)
            let normalizedName = String(lastComponent)
                .replacingOccurrences(of: " ", with: "-")
            // Remove trailing numeric suffix
            if let range = normalizedName.range(of: "-\\d+$", options: .regularExpression) {
                let baseName = String(normalizedName[..<range.lowerBound])
                if baseName == disk.name {
                    return true
                }
            }
        }

        return false
    }

    /// Check initial state
    /// - Parameter silent: Whether to use silent mode (no onDiskConnected callback)
    func checkInitialState(silent: Bool = false) {
        Logger.shared.info("Checking initial disk state... (silent=\(silent))")

        Task {
            let disks = await getDisks()

            for disk in disks where disk.enabled {
                if fileManager.fileExists(atPath: disk.mountPath) {
                    Logger.shared.info("Disk \(disk.name) connected: \(disk.mountPath)")

                    await MainActor.run {
                        self.connectedDisks[disk.id] = disk
                        // Silent mode skips callback (avoid popup at startup)
                        if !silent {
                            self.onDiskConnected?(disk)
                        }
                    }

                    // Notify DMSAService
                    try? await ServiceClient.shared.notifyDiskConnected(
                        diskName: disk.name,
                        mountPoint: disk.mountPath
                    )
                } else {
                    Logger.shared.info("Disk \(disk.name) not connected")
                }
            }
        }
    }

    /// Check if a disk is connected
    /// Checks actual filesystem first, then cache
    func isDiskConnected(_ diskId: String) -> Bool {
        // Check cache first
        if connectedDisks[diskId] != nil {
            return true
        }

        // Not in cache, check actual filesystem
        // Search from cached config
        if let disk = cachedDisks.first(where: { $0.id == diskId }) {
            let exists = fileManager.fileExists(atPath: disk.mountPath)
            if exists {
                // Update cache
                Task { @MainActor in
                    self.connectedDisks[diskId] = disk
                }
            }
            return exists
        }

        return false
    }

    /// Check if any external disk is connected
    /// Checks actual filesystem first, then cache
    var isAnyExternalConnected: Bool {
        // Check cache first
        if !connectedDisks.isEmpty {
            return true
        }

        // Cache empty, check actual filesystem
        for disk in cachedDisks where disk.enabled {
            if fileManager.fileExists(atPath: disk.mountPath) {
                // Update cache
                Task { @MainActor in
                    self.connectedDisks[disk.id] = disk
                }
                return true
            }
        }

        return false
    }

    /// Check if any disk from the given list is connected
    /// For UI layer to check with config, avoiding cache issues
    func isAnyDiskConnected(from disks: [DiskConfig]) -> Bool {
        for disk in disks where disk.enabled {
            if fileManager.fileExists(atPath: disk.mountPath) {
                // Update cache
                if connectedDisks[disk.id] == nil {
                    connectedDisks[disk.id] = disk
                }
                return true
            }
        }
        return false
    }

    /// Get connected disk count
    func connectedDiskCount(from disks: [DiskConfig]) -> Int {
        var count = 0
        for disk in disks where disk.enabled {
            if fileManager.fileExists(atPath: disk.mountPath) {
                // Update cache
                if connectedDisks[disk.id] == nil {
                    connectedDisks[disk.id] = disk
                }
                count += 1
            }
        }
        return count
    }

    /// Get disk space info
    func getDiskInfo(at path: String) -> (total: Int64, available: Int64, used: Int64)? {
        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: path)
            guard let total = attrs[.systemSize] as? Int64,
                  let free = attrs[.systemFreeSize] as? Int64 else {
                return nil
            }
            return (total: total, available: free, used: total - free)
        } catch {
            Logger.shared.error("Failed to get disk info: \(error)")
            return nil
        }
    }

    deinit {
        workspace.notificationCenter.removeObserver(self)
    }
}
