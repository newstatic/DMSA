import Cocoa
import SwiftUI

/// Menu bar delegate protocol
protocol MenuBarDelegate: AnyObject {
    func menuBarDidRequestSync()
    func menuBarDidRequestSettings()
    func menuBarDidRequestToggleAutoSync()
    func menuBarDidRequestOpenTab(_ tab: MainView.MainTab)
}

/// Sync state enumeration
enum SyncState {
    case idle
    case starting
    case indexing
    case syncing
    case reconnecting
    case error(String)
}

/// Disk connection state enumeration
enum DiskConnectionState {
    case disconnected
    case connected(diskName: String, usedSpace: Int64?, totalSpace: Int64?)
}

/// Menu bar manager
final class MenuBarManager {
    private var statusItem: NSStatusItem!
    private var diskStates: [String: DiskConnectionState] = [:]
    private var syncState: SyncState = .idle
    private var lastSyncTime: Date?
    private var configManager: ConfigManager
    private var stateManager: StateManager
    private var isAutoSyncEnabled: Bool = true

    weak var delegate: MenuBarDelegate?

    init(configManager: ConfigManager = ConfigManager.shared, stateManager: StateManager = StateManager.shared) {
        self.configManager = configManager
        self.stateManager = stateManager
        self.isAutoSyncEnabled = configManager.config.general.autoSyncEnabled
        setupStatusItem()
        setupNotifications()
    }

    private func setupNotifications() {
        // Observe language change notification to rebuild menu
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageChanged),
            name: .languageDidChange,
            object: nil
        )

        // Observe sync status change notification to update icon
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncStatusChanged),
            name: .syncStatusDidChange,
            object: nil
        )
    }

    @objc private func handleSyncStatusChanged() {
        Logger.shared.debug("Received status change notification, updating menu bar")
        syncWithAppState()
    }

    @objc private func handleLanguageChanged() {
        Logger.shared.debug("Language changed, rebuilding menu")
        updateMenu()
        updateIcon()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                                   accessibilityDescription: L10n.App.name)
            button.image?.isTemplate = true
        }

        updateMenu()
        Logger.shared.info("Menu bar initialized")
    }

    func updateMenu() {
        let menu = NSMenu()

        // Status section
        addStatusSection(to: menu)

        menu.addItem(NSMenuItem.separator())

        // Sync pairs section
        addSyncPairsSection(to: menu)

        menu.addItem(NSMenuItem.separator())

        // Actions section
        addActionsSection(to: menu)

        menu.addItem(NSMenuItem.separator())

        // Footer section
        addFooterSection(to: menu)

        statusItem.menu = menu
    }

    private func addStatusSection(to menu: NSMenu) {
        let disks = configManager.config.disks

        if disks.isEmpty {
            let noDisksItem = NSMenuItem(title: L10n.Menu.noDisksConfigured, action: nil, keyEquivalent: "")
            noDisksItem.isEnabled = false
            menu.addItem(noDisksItem)
            return
        }

        // Add disk status cards
        for disk in disks {
            let diskItem = createDiskMenuItem(for: disk)
            menu.addItem(diskItem)
        }
    }

    private func createDiskMenuItem(for disk: DiskConfig) -> NSMenuItem {
        let isConnected = disk.isConnected

        // Create attributed string for disk info
        let title: String
        if isConnected {
            // Get disk space info
            if let (used, total) = getDiskSpaceInfo(disk) {
                let usedStr = ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
                let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                let percent = Int(Double(used) / Double(total) * 100)
                title = "🟢 \(disk.name)  \(usedStr) / \(totalStr) (\(percent)%)"
            } else {
                title = "🟢 \(disk.name) \(L10n.Disk.connected)"
            }
        } else {
            title = "⚪ \(disk.name) \(L10n.Disk.disconnected)"
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false

        // Add last sync time if available
        if let lastSync = lastSyncTime {
            let subItem = NSMenuItem()
            subItem.title = "    " + L10n.Menu.lastSync(L10n.Time.relative(from: lastSync))
            subItem.isEnabled = false
            // Note: NSMenu doesn't support submenu items directly, so we just format the main title
        }

        return item
    }

    private func addSyncPairsSection(to menu: NSMenu) {
        let syncPairs = configManager.config.syncPairs

        if syncPairs.isEmpty { return }

        for pair in syncPairs {
            let disk = configManager.config.disks.first { $0.id == pair.diskId }
            let diskName = disk?.name ?? "?"
            let isConnected = disk?.isConnected ?? false

            let icon = pair.enabled ? "📁" : "📂"
            let directionIcon = pair.direction.icon
            let status = isConnected ? "✓" : "○"

            let title = "\(icon) \(pair.localPath) \(directionIcon) \(diskName)/\(pair.externalRelativePath) \(status)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    private func addActionsSection(to menu: NSMenu) {
        // Sync Now
        let syncItem = NSMenuItem(
            title: L10n.Menu.syncNow,
            action: #selector(handleSync),
            keyEquivalent: "s"
        )
        syncItem.target = self
        syncItem.isEnabled = isSyncEnabled
        menu.addItem(syncItem)

        // Auto Sync Toggle
        let autoSyncItem = NSMenuItem(
            title: "menu.autoSync".localized,
            action: #selector(handleToggleAutoSync),
            keyEquivalent: ""
        )
        autoSyncItem.target = self
        autoSyncItem.state = isAutoSyncEnabled ? .on : .off
        menu.addItem(autoSyncItem)
    }

    private func addFooterSection(to menu: NSMenu) {
        // Open Dashboard
        let dashboardItem = NSMenuItem(
            title: "menu.openDashboard".localized,
            action: #selector(handleOpenDashboard),
            keyEquivalent: "d"
        )
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        // Open Disks
        let disksItem = NSMenuItem(
            title: "menu.openDisks".localized,
            action: #selector(handleOpenDisks),
            keyEquivalent: ""
        )
        disksItem.target = self
        menu.addItem(disksItem)

        // View Conflicts (if any)
        let conflictCount = MainActor.assumeIsolated { StateManager.shared.conflictCount }
        if conflictCount > 0 {
            let conflictsItem = NSMenuItem(
                title: String(format: "menu.viewConflicts".localized, conflictCount),
                action: #selector(handleOpenConflicts),
                keyEquivalent: ""
            )
            conflictsItem.target = self
            menu.addItem(conflictsItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Settings (opens main window)
        let settingsItem = NSMenuItem(
            title: L10n.Menu.settings,
            action: #selector(handleSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Quit
        let quitItem = NSMenuItem(
            title: L10n.Menu.quit,
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - State Updates

    private var isSyncEnabled: Bool {
        // Check if service is ready (using MainActor.assumeIsolated to access MainActor-isolated properties)
        let isReady = MainActor.assumeIsolated { stateManager.isReady }
        if !isReady { return false }

        // Check if any configured disk is connected
        let hasConnectedDisk = configManager.config.disks.contains { $0.isConnected }
        if !hasConnectedDisk { return false }

        // Check if not already syncing
        if case .syncing = syncState { return false }

        return true
    }

    func updateDiskState(_ diskName: String, state: DiskConnectionState) {
        diskStates[diskName] = state
        updateIcon()
        updateMenu()
    }

    func updateSyncState(_ state: SyncState) {
        syncState = state
        if case .idle = state {
            lastSyncTime = Date()
        }
        updateIcon()
        updateMenu()
    }

    func updateAutoSyncState(isEnabled: Bool) {
        isAutoSyncEnabled = isEnabled
        updateMenu()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let hasConnectedDisk = configManager.config.disks.contains { $0.isConnected }

        let symbolName: String
        switch syncState {
        case .starting:
            symbolName = "gear"
        case .indexing:
            symbolName = "doc.text.magnifyingglass"
        case .syncing:
            symbolName = "arrow.triangle.2.circlepath.circle"
            // TODO: Add rotation animation
        case .reconnecting:
            symbolName = "arrow.triangle.2.circlepath"
        case .error:
            symbolName = "exclamationmark.triangle"
        case .idle:
            if hasConnectedDisk {
                if isAutoSyncEnabled {
                    symbolName = "arrow.triangle.2.circlepath.circle.fill"
                } else {
                    // Paused state - show different icon
                    symbolName = "pause.circle"
                }
            } else {
                symbolName = "arrow.triangle.2.circlepath"
            }
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: L10n.App.name)
        button.image?.isTemplate = true
    }

    private func getDiskSpaceInfo(_ disk: DiskConfig) -> (Int64, Int64)? {
        guard disk.isConnected else { return nil }
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: disk.mountPath)
            let totalSize = (attrs[.systemSize] as? Int64) ?? 0
            let freeSize = (attrs[.systemFreeSize] as? Int64) ?? 0
            return (totalSize - freeSize, totalSize)
        } catch {
            return nil
        }
    }

    // MARK: - Actions

    @objc private func handleToggleAutoSync() {
        Logger.shared.info("User toggled auto sync")
        delegate?.menuBarDidRequestToggleAutoSync()
    }

    @objc private func handleSync() {
        Logger.shared.info("User triggered manual sync")
        delegate?.menuBarDidRequestSync()
    }

    @objc private func handleSettings() {
        Logger.shared.info("User opened settings")
        delegate?.menuBarDidRequestSettings()
    }

    @objc private func handleQuit() {
        Logger.shared.info("User quit application")
        NSApplication.shared.terminate(nil)
    }

    @objc private func handleOpenDashboard() {
        Logger.shared.info("User opened dashboard from menu bar")
        delegate?.menuBarDidRequestOpenTab(.dashboard)
    }

    @objc private func handleOpenDisks() {
        Logger.shared.info("User opened disks from menu bar")
        delegate?.menuBarDidRequestOpenTab(.disks)
    }

    @objc private func handleOpenConflicts() {
        Logger.shared.info("User opened conflicts from menu bar")
        delegate?.menuBarDidRequestOpenTab(.conflicts)
    }

    // MARK: - Sync with StateManager

    /// Updates menu bar to reflect current app state
    func syncWithAppState() {
        MainActor.assumeIsolated {
            let stateManager = StateManager.shared

            // Update sync state based on StateManager.syncStatus
            switch stateManager.syncStatus {
            case .syncing:
                syncState = .syncing
            case .indexing:
                syncState = .indexing
            case .starting:
                syncState = .starting
            case .reconnecting:
                syncState = .reconnecting
            case .error(let message):
                syncState = .error(message)
            case .ready, .paused, .serviceUnavailable:
                syncState = .idle
            }
        }

        updateIcon()
        updateMenu()
    }
}
