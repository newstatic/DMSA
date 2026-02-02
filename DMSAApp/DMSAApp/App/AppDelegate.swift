import Cocoa
import SwiftUI
import ServiceManagement

/// App delegate
/// v4.6: Pure UI client, config and business logic fully handled by DMSAService
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - UI Managers

    private var menuBarManager: MenuBarManager!
    private let diskManager = DiskManager.shared
    private let alertManager = AlertManager.shared
    private let serviceClient = ServiceClient.shared
    private let serviceInstaller = ServiceInstaller.shared

    // MARK: - State Management

    private let stateManager = StateManager.shared
    private let notificationHandler = NotificationHandler.shared

    // MARK: - Window Controllers

    private var mainWindowController: MainWindowController?

    // MARK: - Refresh Timer

    private var stateRefreshTimer: Timer?
    private let stateRefreshInterval: TimeInterval = 30 // Refresh every 30 seconds

    // MARK: - Config Cache

    private var cachedConfig: AppConfig?
    private var lastConfigFetch: Date?
    private let configCacheTimeout: TimeInterval = 30 // 30-second cache
    private let configLock = NSLock() // Config cache lock to prevent race conditions
    private var isConfigFetching = false // Prevent concurrent fetching

    // MARK: - Sync Control Properties

    var isAutoSyncEnabled: Bool {
        get {
            configLock.lock()
            defer { configLock.unlock() }
            return cachedConfig?.general.autoSyncEnabled ?? true
        }
        set {
            Task {
                do {
                    var config = try await getConfig()
                    config.general.autoSyncEnabled = newValue
                    try await serviceClient.updateConfig(config)

                    configLock.lock()
                    cachedConfig = config
                    lastConfigFetch = Date()
                    configLock.unlock()

                    Logger.shared.info("Auto sync toggle: \(newValue ? "enabled" : "disabled")")
                } catch {
                    Logger.shared.error("Failed to update auto sync config: \(error)")
                }
            }
        }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("============================================")
        Logger.shared.info("DMSA v4.6 starting")
        Logger.shared.info("============================================")

        setupUI()
        setupServiceClientCallbacks()
        setupDiskCallbacks()

        // Check and install/update Service
        Task {
            await checkAndInstallService()
        }

        // Check macFUSE
        checkMacFUSE()

        Logger.shared.info("App initialization complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("App is about to quit")

        // Clean up timer
        stateRefreshTimer?.invalidate()
        stateRefreshTimer = nil

        // Notify Service to prepare for shutdown (Service itself won't exit, just cleanup)
        Task {
            try? await serviceClient.prepareForShutdown()
        }

        Logger.shared.info("============================================")
        Logger.shared.info("DMSA has quit")
        Logger.shared.info("============================================")
    }

    deinit {
        // Ensure timer is cleaned up
        stateRefreshTimer?.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Menu bar app
    }

    func applicationDidResignActive(_ notification: Notification) {
        Logger.shared.debug("App entered background")

        // Save state to cache
        stateManager.saveToCache()

        // Pause state refresh timer
        stateRefreshTimer?.invalidate()
        stateRefreshTimer = nil
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Logger.shared.debug("App entered foreground")

        // Restore state
        stateManager.restoreFromCache()

        // Sync latest state
        Task {
            await stateManager.syncFullState()
        }

        // Resume state refresh timer
        startStateRefreshTimer()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            mainWindowController?.showWindow()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check if there are in-progress sync operations
        if stateManager.isSyncing {
            showTerminationConfirmation()
            return .terminateCancel
        }

        return .terminateNow
    }

    // MARK: - Quit Confirmation

    private func showTerminationConfirmation() {
        let alert = NSAlert()
        alert.messageText = "alert.sync.inprogress.title".localized
        alert.informativeText = "alert.sync.inprogress.message".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "alert.sync.inprogress.wait".localized)
        alert.addButton(withTitle: "alert.sync.inprogress.force".localized)
        alert.addButton(withTitle: "alert.cancel".localized)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            // Wait for completion then quit
            waitForSyncAndQuit()
        case .alertSecondButtonReturn:
            // Force quit
            forceQuit()
        default:
            // Cancel
            break
        }
    }

    private func waitForSyncAndQuit() {
        Logger.shared.info("Waiting for sync to complete before quitting...")

        // Set observer to wait for sync completion
        Task { @MainActor in
            // Simple polling to wait for sync completion
            while stateManager.isSyncing {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }

            // Quit after sync completes
            NSApplication.shared.terminate(nil)
        }
    }

    private func forceQuit() {
        Logger.shared.warn("User chose force quit, cancelling in-progress sync")

        Task {
            try? await serviceClient.cancelSync()
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

            await MainActor.run {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - State Refresh Timer

    private func startStateRefreshTimer() {
        stateRefreshTimer?.invalidate()
        stateRefreshTimer = Timer.scheduledTimer(withTimeInterval: stateRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.stateManager.syncFullState()
            }
        }
    }

    // MARK: - Initialization

    private func setupUI() {
        menuBarManager = MenuBarManager()
        menuBarManager.delegate = self
        mainWindowController = MainWindowController(configManager: ConfigManager.shared)
        Logger.shared.info("UI managers initialized")
    }

    private func setupServiceClientCallbacks() {
        // Set connection state change callback (must be set on MainActor)
        Task { @MainActor in
            serviceClient.onConnectionStateChanged = { [weak self] isConnected in
                Task { @MainActor in
                    if isConnected {
                        self?.stateManager.updateConnectionState(.connected)
                        Logger.shared.info("XPC connection restored")
                    } else {
                        self?.stateManager.updateConnectionState(.interrupted)
                        Logger.shared.warning("XPC connection lost")
                    }
                }
            }
            Logger.shared.info("ServiceClient callbacks configured")
        }
    }

    private func setupDiskCallbacks() {
        diskManager.onDiskConnected = { [weak self] disk in
            self?.handleDiskConnected(disk, isInitialCheck: false)
        }

        diskManager.onDiskDisconnected = { [weak self] disk in
            self?.handleDiskDisconnected(disk)
        }

        Logger.shared.info("Disk event callbacks configured")
    }

    private func checkInitialState() {
        Task {
            do {
                let disks = try await serviceClient.getDisks()
                if disks.isEmpty {
                    Logger.shared.info("No disks configured, waiting for user configuration")
                    await setupDefaultConfig()
                } else {
                    Logger.shared.info("\(disks.count) disk(s) configured")
                    // Use silent mode for initial check to avoid popups at startup
                    diskManager.checkInitialState(silent: true)
                }
            } catch {
                Logger.shared.error("Failed to get config: \(error)")
            }
        }
    }

    private func setupDefaultConfig() async {
        let defaultDisk = DiskConfig(
            id: "default_backup",
            name: "BACKUP",
            mountPath: "/Volumes/BACKUP",
            priority: 0,
            enabled: true
        )

        let defaultPair = SyncPairConfig(
            id: "default_downloads",
            diskId: defaultDisk.id,
            localPath: "~/Downloads",
            externalRelativePath: "Downloads",
            direction: .localToExternal,
            createSymlink: true,
            enabled: true
        )

        do {
            try await serviceClient.addDisk(defaultDisk)
            try await serviceClient.addSyncPair(defaultPair)
            Logger.shared.info("Default config created")
        } catch {
            Logger.shared.error("Failed to create default config: \(error)")
        }
    }

    // MARK: - Config Cache

    private func getConfig() async -> AppConfig {
        // Use lock to check cache state
        configLock.lock()

        // Check if cache is valid
        if let cached = cachedConfig,
           let lastFetch = lastConfigFetch,
           Date().timeIntervalSince(lastFetch) < configCacheTimeout {
            configLock.unlock()
            return cached
        }

        // Check if a fetch is already in progress
        if isConfigFetching {
            let cached = cachedConfig
            configLock.unlock()
            // Wait for other task to complete fetch
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if let cached = cached {
                return cached
            }
            return await getConfig()
        }

        isConfigFetching = true
        configLock.unlock()

        // Fetch config from service
        defer {
            configLock.lock()
            isConfigFetching = false
            configLock.unlock()
        }

        do {
            let config = try await serviceClient.getConfig()

            configLock.lock()
            cachedConfig = config
            lastConfigFetch = Date()
            configLock.unlock()

            return config
        } catch {
            Logger.shared.error("Failed to get config: \(error)")

            configLock.lock()
            let cached = cachedConfig
            configLock.unlock()

            return cached ?? AppConfig()
        }
    }

    // MARK: - Service Management

    private func checkAndInstallService() async {
        Logger.shared.info("Checking DMSAService status...")

        let result = await serviceInstaller.checkAndInstallService()

        switch result {
        case .installed(let version):
            Logger.shared.info("DMSAService installed: v\(version)")
            await connectToService()

        case .updated(let from, let to):
            Logger.shared.info("DMSAService updated: \(from) -> \(to)")
            await connectToService()

        case .alreadyInstalled(let version):
            Logger.shared.info("DMSAService ready: v\(version)")
            await connectToService()

        case .requiresApproval:
            Logger.shared.warn("DMSAService requires user approval")
            showServiceApprovalAlert()

        case .failed(let error):
            Logger.shared.error("DMSAService installation failed: \(error)")
            showServiceInstallFailedAlert(errorMessage: error)
        }
    }

    private func connectToService() async {
        do {
            _ = try await serviceClient.connect()
            let versionInfo = try await serviceClient.getVersionInfo()
            Logger.shared.info("Connected to DMSAService \(versionInfo.fullVersion)")
            Logger.shared.info("Service uptime: \(formatUptime(versionInfo.uptime))")

            // Connect StateManager to sync service state
            // StateManager.connect() automatically calls syncFullState() and starts timer
            await stateManager.connect()
            Logger.shared.info("StateManager connected, state sync started")

            // Apply appearance settings (e.g. Dock icon visibility)
            let config = await getConfig()
            AppearanceManager.shared.applySettings(from: config.general)
            Logger.shared.info("Appearance settings applied: showInDock=\(config.general.showInDock)")

            // Check initial state after successful connection
            checkInitialState()
        } catch {
            Logger.shared.error("Failed to connect to DMSAService: \(error)")
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    private func showServiceApprovalAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "DMSA Service Approval Required"
            alert.informativeText = "Please go to System Settings > Privacy & Security > Login Items & Extensions to approve DMSA Service."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func showServiceInstallFailedAlert(errorMessage: String) {
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = "DMSA Service Installation Failed"
            alert.informativeText = "Unable to install background service: \(errorMessage)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Retry")
            alert.addButton(withTitle: "Quit")

            if alert.runModal() == .alertFirstButtonReturn {
                // Retry
                Task {
                    await self?.checkAndInstallService()
                }
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - macFUSE Check

    private func checkMacFUSE() {
        Logger.shared.info("Checking macFUSE status...")

        let availability = FUSEManager.shared.checkFUSEAvailability()

        switch availability {
        case .available(let version):
            Logger.shared.info("macFUSE version: \(version)")
        case .notInstalled, .frameworkMissing:
            showMacFUSENotInstalledAlert()
        case .versionTooOld(let current, let required):
            showMacFUSEUpdateAlert(current: current, required: required)
        case .loadError:
            showMacFUSENotInstalledAlert()
        }
    }

    private func showMacFUSENotInstalledAlert() {
        let alert = NSAlert()
        alert.messageText = "macFUSE Not Installed"
        alert.informativeText = "Please download and install macFUSE from the official website."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Download macFUSE")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "https://macfuse.github.io/") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showMacFUSEUpdateAlert(current: String, required: String) {
        let alert = NSAlert()
        alert.messageText = "macFUSE Update Required"
        alert.informativeText = "Current version \(current), requires \(required) or higher."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "https://macfuse.github.io/") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Disk Event Handling (UI Updates)

    private func handleDiskConnected(_ disk: DiskConfig, isInitialCheck: Bool = false) {
        Logger.shared.info("Disk connected: \(disk.name) (isInitialCheck=\(isInitialCheck))")

        Task { @MainActor in
            menuBarManager.updateDiskState(disk.name, state: .connected(diskName: disk.name, usedSpace: nil, totalSpace: nil))

            // Don't show popup during initial check
            if !isInitialCheck {
                alertManager.alertDiskConnected(diskName: disk.name)
            }

            // Check if service is ready
            guard stateManager.isReady else {
                Logger.shared.info("Service not ready, skipping auto sync")
                return
            }

            // Auto sync is handled by Service, we just trigger it here
            let config = await getConfig()
            guard config.general.autoSyncEnabled else { return }

            // Find all sync pairs associated with this disk and trigger sync
            let syncPairsForDisk = config.syncPairs.filter { $0.diskId == disk.id && $0.enabled }
            for syncPair in syncPairsForDisk {
                Logger.shared.info("Triggering sync: syncPairId=\(syncPair.id), disk=\(disk.name)")
                try? await serviceClient.syncNow(syncPairId: syncPair.id)
            }
        }
    }

    private func handleDiskDisconnected(_ disk: DiskConfig) {
        Logger.shared.info("Disk disconnected: \(disk.name)")

        Task { @MainActor in
            if diskManager.connectedDisks.isEmpty {
                menuBarManager.updateDiskState(disk.name, state: .disconnected)
            }

            alertManager.alertDiskDisconnected(diskName: disk.name)
        }
    }

    // MARK: - Public Methods

    func toggleAutoSync() {
        Task {
            let config = await getConfig()
            isAutoSyncEnabled = !config.general.autoSyncEnabled
            menuBarManager.updateAutoSyncState(isEnabled: !config.general.autoSyncEnabled)
        }
    }
}

// MARK: - MenuBarDelegate

extension AppDelegate: MenuBarDelegate {
    func menuBarDidRequestSync() {
        Logger.shared.info("User requested manual sync")

        Task { @MainActor in
            // Check if service is ready
            guard stateManager.isReady else {
                Logger.shared.warning("Service not ready, cannot perform sync")
                alertManager.alertInfo(
                    title: "Cannot Sync",
                    message: "Service is starting up, please try again later."
                )
                return
            }

            try? await serviceClient.syncAll()
        }
    }

    func menuBarDidRequestSettings() {
        mainWindowController?.showWindow()
    }

    func menuBarDidRequestToggleAutoSync() {
        toggleAutoSync()
    }

    func menuBarDidRequestOpenTab(_ tab: MainView.MainTab) {
        Logger.shared.info("User requested open tab: \(tab.rawValue)")
        mainWindowController?.showTab(tab)
    }
}
