import Cocoa

/// 应用代理
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - 管理器

    private var menuBarManager: MenuBarManager!
    private let configManager = ConfigManager.shared
    private let diskManager = DiskManager.shared
    private let syncEngine = SyncEngine.shared
    private let notificationManager = NotificationManager.shared

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("============================================")
        Logger.shared.info("DMSA v2.0 启动")
        Logger.shared.info("============================================")

        setupManagers()
        setupDiskCallbacks()
        checkInitialState()

        Logger.shared.info("应用初始化完成")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("应用即将退出")

        // 取消正在进行的同步
        if syncEngine.isRunning {
            syncEngine.cancel()
        }

        Logger.shared.info("============================================")
        Logger.shared.info("DMSA 已退出")
        Logger.shared.info("============================================")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 菜单栏应用，关闭窗口不退出
        return false
    }

    // MARK: - 初始化

    private func setupManagers() {
        // 初始化菜单栏
        menuBarManager = MenuBarManager()
        menuBarManager.delegate = self

        // 设置同步引擎代理
        syncEngine.delegate = self

        Logger.shared.info("管理器初始化完成")
    }

    private func setupDiskCallbacks() {
        // 硬盘连接回调
        diskManager.onDiskConnected = { [weak self] disk in
            self?.handleDiskConnected(disk)
        }

        // 硬盘断开回调
        diskManager.onDiskDisconnected = { [weak self] disk in
            self?.handleDiskDisconnected(disk)
        }

        Logger.shared.info("硬盘事件回调已设置")
    }

    private func checkInitialState() {
        // 检查配置中的硬盘
        let configuredDisks = configManager.config.disks

        if configuredDisks.isEmpty {
            Logger.shared.info("未配置任何硬盘，等待用户配置")
            setupDefaultConfig()
        } else {
            Logger.shared.info("已配置 \(configuredDisks.count) 个硬盘")
            diskManager.checkInitialState()
        }
    }

    private func setupDefaultConfig() {
        // 创建默认配置 (BACKUP 硬盘)
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

        configManager.addDisk(defaultDisk)
        configManager.addSyncPair(defaultPair)

        Logger.shared.info("已创建默认配置: BACKUP 硬盘 + Downloads 同步对")
    }

    // MARK: - 硬盘事件处理

    private func handleDiskConnected(_ disk: DiskConfig) {
        Logger.shared.info("处理硬盘连接: \(disk.name)")

        // 更新菜单栏状态
        menuBarManager.updateDiskState(disk.name, state: .connected(diskName: disk.name, usedSpace: nil, totalSpace: nil))

        // 发送通知
        notificationManager.notifyDiskConnected(diskName: disk.name)

        // 自动开始同步
        Task {
            await performSyncForDisk(disk)
        }
    }

    private func handleDiskDisconnected(_ disk: DiskConfig) {
        Logger.shared.info("处理硬盘断开: \(disk.name)")

        // 取消正在进行的同步
        if syncEngine.isRunning {
            syncEngine.cancel()
        }

        // 恢复符号链接
        restoreSymlinksForDisk(disk)

        // 更新菜单栏状态
        if diskManager.connectedDisks.isEmpty {
            menuBarManager.updateDiskState(disk.name, state: .disconnected)
        } else if let firstDisk = diskManager.connectedDisks.values.first {
            menuBarManager.updateDiskState(firstDisk.name, state: .connected(diskName: firstDisk.name, usedSpace: nil, totalSpace: nil))
        }

        // 发送通知
        notificationManager.notifyDiskDisconnected(diskName: disk.name)
    }

    private func restoreSymlinksForDisk(_ disk: DiskConfig) {
        let pairs = configManager.getSyncPairs(forDiskId: disk.id)

        for pair in pairs where pair.createSymlink {
            let localPath = (pair.localPath as NSString).expandingTildeInPath

            do {
                try syncEngine.removeSymlinkAndRestore(localPath: localPath)
            } catch {
                Logger.shared.error("恢复符号链接失败 (\(localPath)): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 同步操作

    private func performSyncForDisk(_ disk: DiskConfig) async {
        menuBarManager.updateSyncState(.syncing)

        do {
            try await syncEngine.syncAllPairs(for: disk)
            menuBarManager.updateSyncState(.idle)
        } catch {
            Logger.shared.error("同步失败: \(error.localizedDescription)")
            menuBarManager.updateSyncState(.error(error.localizedDescription))
            notificationManager.notifySyncFailed(error: error.localizedDescription)
        }
    }

    private func performManualSync() {
        guard let disk = diskManager.connectedDisks.values.first else {
            Logger.shared.warn("没有已连接的硬盘，无法同步")
            return
        }

        Task {
            await performSyncForDisk(disk)
        }
    }

    // MARK: - 设置窗口

    private var settingsWindowController: NSWindowController?

    private func showSettings() {
        // TODO: 实现设置窗口
        Logger.shared.info("打开设置窗口 (待实现)")

        // 临时：显示简单的提示
        let alert = NSAlert()
        alert.messageText = "设置"
        alert.informativeText = "设置界面开发中...\n\n配置文件位置:\n\(configManager.config)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}

// MARK: - MenuBarDelegate

extension AppDelegate: MenuBarDelegate {
    func menuBarDidRequestSync() {
        Logger.shared.info("用户请求手动同步")
        performManualSync()
    }

    func menuBarDidRequestSettings() {
        showSettings()
    }

    func menuBarDidRequestHistory() {
        Logger.shared.info("用户打开同步历史")
        // History window is handled by MenuBarManager
    }
}

// MARK: - SyncEngineDelegate

extension AppDelegate: SyncEngineDelegate {
    func syncEngine(_ engine: SyncEngine, didStartTask task: SyncTask) {
        Logger.shared.info("同步任务开始: \(task.syncPair.localPath)")
        notificationManager.notifySyncStarted(pairName: task.syncPair.localPath)
    }

    func syncEngine(_ engine: SyncEngine, didUpdateProgress task: SyncTask, progress: Double, message: String) {
        // 进度更新 (可以用于 UI 显示)
        Logger.shared.debug("同步进度: \(Int(progress * 100))%")
    }

    func syncEngine(_ engine: SyncEngine, didCompleteTask task: SyncTask, result: RsyncResult) {
        Logger.shared.info("同步任务完成: \(task.syncPair.localPath), 文件数: \(result.filesTransferred)")
        notificationManager.notifySyncCompleted(
            filesCount: result.filesTransferred,
            totalSize: result.bytesTransferred,
            duration: result.duration
        )
    }

    func syncEngine(_ engine: SyncEngine, didFailTask task: SyncTask, error: Error) {
        Logger.shared.error("同步任务失败: \(task.syncPair.localPath), 错误: \(error.localizedDescription)")
        notificationManager.notifySyncFailed(error: error.localizedDescription)
    }
}
