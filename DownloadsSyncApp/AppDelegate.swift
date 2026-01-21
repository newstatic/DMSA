import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    private var statusItem: NSStatusItem!
    private var syncManager: SyncManager!
    
    // MARK: - Configuration
    private let config = SyncConfig(
        externalDiskName: "BACKUP",
        externalDownloadsPath: "/Volumes/BACKUP/Downloads",
        localDownloadsPath: NSHomeDirectory() + "/Downloads",
        localBackupPath: NSHomeDirectory() + "/Local_Downloads"
    )
    
    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupSyncManager()
        registerForDiskNotifications()
        
        // 启动时检查硬盘状态
        syncManager.checkInitialState()
        
        log("App started, monitoring disk: \(config.externalDiskName)")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        log("App terminating")
    }
    
    // MARK: - Status Bar
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Downloads Sync")
        }
        
        updateMenu()
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        
        // 状态显示
        let statusTitle = syncManager?.isExternalConnected == true ? "✅ 外置硬盘已连接" : "⚪ 外置硬盘未连接"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        // 当前模式
        let modeTitle = syncManager?.isLinked == true ? "📁 Downloads → 外置硬盘" : "📁 Downloads → 本地"
        let modeItem = NSMenuItem(title: modeTitle, action: nil, keyEquivalent: "")
        modeItem.isEnabled = false
        menu.addItem(modeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 手动同步
        let syncItem = NSMenuItem(title: "手动同步", action: #selector(manualSync), keyEquivalent: "s")
        syncItem.target = self
        syncItem.isEnabled = syncManager?.isExternalConnected == true
        menu.addItem(syncItem)
        
        // 查看日志
        let logItem = NSMenuItem(title: "查看日志", action: #selector(openLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)
        
        // 打开 Downloads
        let openItem = NSMenuItem(title: "打开 Downloads", action: #selector(openDownloads), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 退出
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem.menu = menu
    }
    
    // MARK: - Sync Manager
    private func setupSyncManager() {
        syncManager = SyncManager(config: config)
        syncManager.onStatusChange = { [weak self] in
            DispatchQueue.main.async {
                self?.updateMenu()
                self?.updateStatusIcon()
            }
        }
    }
    
    private func updateStatusIcon() {
        if let button = statusItem.button {
            let symbolName = syncManager.isExternalConnected ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Downloads Sync")
        }
    }
    
    // MARK: - Disk Notifications
    private func registerForDiskNotifications() {
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter
        
        // 硬盘挂载
        notificationCenter.addObserver(
            self,
            selector: #selector(diskDidMount(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
        
        // 硬盘卸载
        notificationCenter.addObserver(
            self,
            selector: #selector(diskWillUnmount(_:)),
            name: NSWorkspace.willUnmountNotification,
            object: nil
        )
        
        notificationCenter.addObserver(
            self,
            selector: #selector(diskDidUnmount(_:)),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
    }
    
    @objc private func diskDidMount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        log("Disk mounted: \(devicePath)")
        
        if devicePath.contains(config.externalDiskName) {
            log("Target disk \(config.externalDiskName) connected!")
            
            // 延迟执行，等待挂载稳定
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.syncManager.handleDiskConnected()
            }
        }
    }
    
    @objc private func diskWillUnmount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        log("Disk will unmount: \(devicePath)")
        
        if devicePath.contains(config.externalDiskName) {
            log("Target disk \(config.externalDiskName) will disconnect!")
            syncManager.handleDiskWillDisconnect()
        }
    }
    
    @objc private func diskDidUnmount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        log("Disk unmounted: \(devicePath)")
        
        if devicePath.contains(config.externalDiskName) {
            syncManager.handleDiskDisconnected()
        }
    }
    
    // MARK: - Actions
    @objc private func manualSync() {
        log("Manual sync triggered")
        syncManager.performSync()
    }
    
    @objc private func openLog() {
        let logPath = NSHomeDirectory() + "/.downloads_sync.log"
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }
    
    @objc private func openDownloads() {
        let downloadsPath = config.localDownloadsPath
        NSWorkspace.shared.open(URL(fileURLWithPath: downloadsPath))
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Configuration
struct SyncConfig {
    let externalDiskName: String
    let externalDownloadsPath: String
    let localDownloadsPath: String
    let localBackupPath: String
}

// MARK: - Sync Manager
class SyncManager {
    
    private let config: SyncConfig
    private let fileManager = FileManager.default
    private var isSyncing = false
    
    var onStatusChange: (() -> Void)?
    
    var isExternalConnected: Bool {
        fileManager.fileExists(atPath: "/Volumes/\(config.externalDiskName)")
    }
    
    var isLinked: Bool {
        guard let attrs = try? fileManager.attributesOfItem(atPath: config.localDownloadsPath) else {
            return false
        }
        return attrs[.type] as? FileAttributeType == .typeSymbolicLink
    }
    
    init(config: SyncConfig) {
        self.config = config
    }
    
    // MARK: - Initial State Check
    func checkInitialState() {
        log("Checking initial state...")
        log("  External connected: \(isExternalConnected)")
        log("  Is linked: \(isLinked)")
        
        if isExternalConnected {
            // 硬盘已连接，确保链接正确
            if !isLinked {
                handleDiskConnected()
            }
        } else {
            // 硬盘未连接，确保使用本地目录
            if isLinked {
                handleDiskDisconnected()
            }
        }
        
        onStatusChange?()
    }
    
    // MARK: - Disk Events
    func handleDiskConnected() {
        guard !isSyncing else {
            log("Already syncing, skipping")
            return
        }
        
        isSyncing = true
        log("=== Disk connected, starting sync process ===")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            defer {
                self.isSyncing = false
                DispatchQueue.main.async {
                    self.onStatusChange?()
                }
            }
            
            // 1. 确保外置硬盘 Downloads 目录存在
            self.ensureExternalDirectory()
            
            // 2. 如果已经是链接状态，跳过
            if self.isLinked {
                log("Already linked, skipping sync")
                return
            }
            
            // 3. 同步本地到外置
            let syncSuccess = self.performSync()
            
            guard syncSuccess else {
                log("Sync failed, aborting link creation")
                return
            }
            
            // 4. 重命名本地目录
            self.renameLocalToBackup()
            
            // 5. 创建符号链接
            self.createSymlink()
            
            log("=== Sync and link completed ===")
            self.showNotification(title: "Downloads 已切换", body: "现在保存到外置硬盘 BACKUP")
        }
    }
    
    func handleDiskWillDisconnect() {
        log("Preparing for disk disconnect...")
    }
    
    func handleDiskDisconnected() {
        log("=== Disk disconnected ===")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 1. 删除符号链接
            self.removeSymlink()
            
            // 2. 恢复本地目录
            self.restoreLocalFromBackup()
            
            log("=== Restore completed ===")
            self.showNotification(title: "Downloads 已恢复", body: "现在保存到本地")
            
            DispatchQueue.main.async {
                self.onStatusChange?()
            }
        }
    }
    
    // MARK: - Sync Operations
    func performSync() -> Bool {
        log("Starting rsync: Local -> External")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = [
            "-av",
            "--delete",
            config.localDownloadsPath + "/",
            config.externalDownloadsPath + "/"
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                log("rsync output:\n\(output)")
            }
            
            if process.terminationStatus == 0 {
                log("✓ Sync completed successfully")
                return true
            } else {
                log("✗ Sync failed with exit code: \(process.terminationStatus)")
                return false
            }
        } catch {
            log("✗ Sync error: \(error)")
            return false
        }
    }
    
    // MARK: - Directory Operations
    private func ensureExternalDirectory() {
        if !fileManager.fileExists(atPath: config.externalDownloadsPath) {
            do {
                try fileManager.createDirectory(atPath: config.externalDownloadsPath, withIntermediateDirectories: true)
                log("Created external Downloads directory")
            } catch {
                log("Failed to create external directory: \(error)")
            }
        }
    }
    
    private func renameLocalToBackup() {
        // 如果已经是链接，先删除
        if isLinked {
            removeSymlink()
        }
        
        // 如果备份目录已存在，删除它
        if fileManager.fileExists(atPath: config.localBackupPath) {
            do {
                try fileManager.removeItem(atPath: config.localBackupPath)
                log("Removed existing backup directory")
            } catch {
                log("Failed to remove existing backup: \(error)")
            }
        }
        
        // 重命名 Downloads -> Local_Downloads
        if fileManager.fileExists(atPath: config.localDownloadsPath) {
            do {
                try fileManager.moveItem(atPath: config.localDownloadsPath, toPath: config.localBackupPath)
                log("Renamed Downloads -> Local_Downloads")
            } catch {
                log("Failed to rename: \(error)")
            }
        }
    }
    
    private func createSymlink() {
        do {
            try fileManager.createSymbolicLink(
                atPath: config.localDownloadsPath,
                withDestinationPath: config.externalDownloadsPath
            )
            log("Created symlink: Downloads -> \(config.externalDownloadsPath)")
        } catch {
            log("Failed to create symlink: \(error)")
        }
    }
    
    private func removeSymlink() {
        if isLinked {
            do {
                try fileManager.removeItem(atPath: config.localDownloadsPath)
                log("Removed symlink")
            } catch {
                log("Failed to remove symlink: \(error)")
            }
        }
    }
    
    private func restoreLocalFromBackup() {
        // 如果符号链接还存在（可能是悬空的），删除它
        if fileManager.fileExists(atPath: config.localDownloadsPath) || isLinked {
            do {
                try fileManager.removeItem(atPath: config.localDownloadsPath)
            } catch {
                log("Failed to remove existing item: \(error)")
            }
        }
        
        // 恢复备份目录
        if fileManager.fileExists(atPath: config.localBackupPath) {
            do {
                try fileManager.moveItem(atPath: config.localBackupPath, toPath: config.localDownloadsPath)
                log("Restored Local_Downloads -> Downloads")
            } catch {
                log("Failed to restore: \(error)")
            }
        } else {
            // 如果备份不存在，创建新的 Downloads 目录
            do {
                try fileManager.createDirectory(atPath: config.localDownloadsPath, withIntermediateDirectories: true)
                log("Created new Downloads directory")
            } catch {
                log("Failed to create Downloads: \(error)")
            }
        }
    }
    
    // MARK: - Notification
    private func showNotification(title: String, body: String) {
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = title
            notification.informativeText = body
            notification.soundName = NSUserNotificationDefaultSoundName
            NSUserNotificationCenter.default.deliver(notification)
        }
    }
}

// MARK: - Logging
private let logPath = NSHomeDirectory() + "/.downloads_sync.log"

func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"
    
    print(logMessage, terminator: "")
    
    if let data = logMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }
}
