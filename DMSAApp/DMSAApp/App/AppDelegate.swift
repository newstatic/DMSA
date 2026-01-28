import Cocoa
import SwiftUI
import ServiceManagement

/// 应用代理
/// v4.6: 纯 UI 客户端，配置和业务逻辑完全由 DMSAService 处理
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - UI 管理器

    private var menuBarManager: MenuBarManager!
    private let diskManager = DiskManager.shared
    private let alertManager = AlertManager.shared
    private let serviceClient = ServiceClient.shared
    private let serviceInstaller = ServiceInstaller.shared

    // MARK: - 状态管理

    private let stateManager = StateManager.shared
    private let notificationHandler = NotificationHandler.shared

    // MARK: - 窗口控制器

    private var mainWindowController: MainWindowController?

    // MARK: - 刷新定时器

    private var stateRefreshTimer: Timer?
    private let stateRefreshInterval: TimeInterval = 30 // 30秒刷新一次

    // MARK: - 配置缓存

    private var cachedConfig: AppConfig?
    private var lastConfigFetch: Date?
    private let configCacheTimeout: TimeInterval = 30 // 30秒缓存
    private let configLock = NSLock() // 配置缓存锁，防止竞态条件
    private var isConfigFetching = false // 防止并发获取

    // MARK: - 同步控制属性

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

                    Logger.shared.info("自动同步开关: \(newValue ? "开启" : "关闭")")
                } catch {
                    Logger.shared.error("更新自动同步配置失败: \(error)")
                }
            }
        }
    }

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("============================================")
        Logger.shared.info("DMSA v4.6 启动")
        Logger.shared.info("============================================")

        setupUI()
        setupDiskCallbacks()

        // 检查并安装/更新 Service
        Task {
            await checkAndInstallService()
        }

        // 检查 macFUSE
        checkMacFUSE()

        Logger.shared.info("应用初始化完成")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("应用即将退出")

        // 清理定时器
        stateRefreshTimer?.invalidate()
        stateRefreshTimer = nil

        // 通知 Service 准备关闭 (Service 本身不会退出，只是做清理)
        Task {
            try? await serviceClient.prepareForShutdown()
        }

        Logger.shared.info("============================================")
        Logger.shared.info("DMSA 已退出")
        Logger.shared.info("============================================")
    }

    deinit {
        // 确保定时器被清理
        stateRefreshTimer?.invalidate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // 菜单栏应用
    }

    func applicationDidResignActive(_ notification: Notification) {
        Logger.shared.debug("App 进入后台")

        // 保存状态到缓存
        stateManager.saveToCache()

        // 暂停状态刷新定时器
        stateRefreshTimer?.invalidate()
        stateRefreshTimer = nil
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Logger.shared.debug("App 进入前台")

        // 恢复状态
        stateManager.restoreFromCache()

        // 同步最新状态
        Task {
            await stateManager.syncFullState()
        }

        // 恢复状态刷新定时器
        startStateRefreshTimer()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            mainWindowController?.showWindow()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 检查是否有进行中的同步操作
        if stateManager.isSyncing {
            showTerminationConfirmation()
            return .terminateCancel
        }

        return .terminateNow
    }

    // MARK: - 退出确认

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
            // 等待完成后退出
            waitForSyncAndQuit()
        case .alertSecondButtonReturn:
            // 强制退出
            forceQuit()
        default:
            // 取消
            break
        }
    }

    private func waitForSyncAndQuit() {
        Logger.shared.info("等待同步完成后退出...")

        // 设置观察者，等待同步完成
        Task { @MainActor in
            // 简单轮询等待同步完成
            while stateManager.isSyncing {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            }

            // 同步完成后退出
            NSApplication.shared.terminate(nil)
        }
    }

    private func forceQuit() {
        Logger.shared.warn("用户选择强制退出，取消进行中的同步")

        Task {
            try? await serviceClient.cancelSync()
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

            await MainActor.run {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - 状态刷新定时器

    private func startStateRefreshTimer() {
        stateRefreshTimer?.invalidate()
        stateRefreshTimer = Timer.scheduledTimer(withTimeInterval: stateRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.stateManager.syncFullState()
            }
        }
    }

    // MARK: - 初始化

    private func setupUI() {
        menuBarManager = MenuBarManager()
        menuBarManager.delegate = self
        mainWindowController = MainWindowController(configManager: ConfigManager.shared)
        Logger.shared.info("UI 管理器初始化完成")
    }

    private func setupDiskCallbacks() {
        diskManager.onDiskConnected = { [weak self] disk in
            self?.handleDiskConnected(disk)
        }

        diskManager.onDiskDisconnected = { [weak self] disk in
            self?.handleDiskDisconnected(disk)
        }

        Logger.shared.info("硬盘事件回调已设置")
    }

    private func checkInitialState() {
        Task {
            do {
                let disks = try await serviceClient.getDisks()
                if disks.isEmpty {
                    Logger.shared.info("未配置任何硬盘，等待用户配置")
                    await setupDefaultConfig()
                } else {
                    Logger.shared.info("已配置 \(disks.count) 个硬盘")
                    diskManager.checkInitialState()
                }
            } catch {
                Logger.shared.error("获取配置失败: \(error)")
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
            Logger.shared.info("已创建默认配置")
        } catch {
            Logger.shared.error("创建默认配置失败: \(error)")
        }
    }

    // MARK: - Config Cache

    private func getConfig() async -> AppConfig {
        // 使用锁检查缓存状态
        configLock.lock()

        // 检查缓存是否有效
        if let cached = cachedConfig,
           let lastFetch = lastConfigFetch,
           Date().timeIntervalSince(lastFetch) < configCacheTimeout {
            configLock.unlock()
            return cached
        }

        // 检查是否已有正在进行的获取操作
        if isConfigFetching {
            let cached = cachedConfig
            configLock.unlock()
            // 等待其他任务完成获取
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if let cached = cached {
                return cached
            }
            return await getConfig()
        }

        isConfigFetching = true
        configLock.unlock()

        // 从服务获取配置
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
            Logger.shared.error("获取配置失败: \(error)")

            configLock.lock()
            let cached = cachedConfig
            configLock.unlock()

            return cached ?? AppConfig()
        }
    }

    // MARK: - Service 管理

    private func checkAndInstallService() async {
        Logger.shared.info("检查 DMSAService 状态...")

        let result = await serviceInstaller.checkAndInstallService()

        switch result {
        case .installed(let version):
            Logger.shared.info("DMSAService 已安装: v\(version)")
            await connectToService()

        case .updated(let from, let to):
            Logger.shared.info("DMSAService 已更新: \(from) → \(to)")
            await connectToService()

        case .alreadyInstalled(let version):
            Logger.shared.info("DMSAService 已就绪: v\(version)")
            await connectToService()

        case .requiresApproval:
            Logger.shared.warn("DMSAService 需要用户批准")
            showServiceApprovalAlert()

        case .failed(let error):
            Logger.shared.error("DMSAService 安装失败: \(error)")
            showServiceInstallFailedAlert(errorMessage: error)
        }
    }

    private func connectToService() async {
        do {
            _ = try await serviceClient.connect()
            let versionInfo = try await serviceClient.getVersionInfo()
            Logger.shared.info("已连接到 DMSAService \(versionInfo.fullVersion)")
            Logger.shared.info("服务运行时间: \(formatUptime(versionInfo.uptime))")

            // 连接成功后检查初始状态
            checkInitialState()
        } catch {
            Logger.shared.error("连接 DMSAService 失败: \(error)")
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        } else if minutes > 0 {
            return "\(minutes)分钟\(secs)秒"
        } else {
            return "\(secs)秒"
        }
    }

    private func showServiceApprovalAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "需要批准 DMSA 服务"
            alert.informativeText = "请前往 系统设置 > 隐私与安全性 > 登录项与扩展 中批准 DMSA Service。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")

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
            alert.messageText = "DMSA 服务安装失败"
            alert.informativeText = "无法安装后台服务: \(errorMessage)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "重试")
            alert.addButton(withTitle: "退出")

            if alert.runModal() == .alertFirstButtonReturn {
                // 重试
                Task {
                    await self?.checkAndInstallService()
                }
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - macFUSE 检查

    private func checkMacFUSE() {
        Logger.shared.info("检查 macFUSE 状态...")

        let availability = FUSEManager.shared.checkFUSEAvailability()

        switch availability {
        case .available(let version):
            Logger.shared.info("macFUSE 版本: \(version)")
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
        alert.messageText = "macFUSE 未安装"
        alert.informativeText = "请从官方网站下载并安装 macFUSE。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "下载 macFUSE")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "https://macfuse.github.io/") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showMacFUSEUpdateAlert(current: String, required: String) {
        let alert = NSAlert()
        alert.messageText = "macFUSE 需要更新"
        alert.informativeText = "当前版本 \(current)，需要 \(required) 或更高版本。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "下载更新")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "https://macfuse.github.io/") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - 硬盘事件处理 (UI 更新)

    private func handleDiskConnected(_ disk: DiskConfig) {
        Logger.shared.info("硬盘已连接: \(disk.name)")

        Task { @MainActor in
            menuBarManager.updateDiskState(disk.name, state: .connected(diskName: disk.name, usedSpace: nil, totalSpace: nil))
            alertManager.alertDiskConnected(diskName: disk.name)

            // 自动同步由 Service 处理，这里只触发
            let config = await getConfig()
            guard config.general.autoSyncEnabled else { return }
            try? await serviceClient.syncNow(syncPairId: "default_downloads")
        }
    }

    private func handleDiskDisconnected(_ disk: DiskConfig) {
        Logger.shared.info("硬盘已断开: \(disk.name)")

        Task { @MainActor in
            if diskManager.connectedDisks.isEmpty {
                menuBarManager.updateDiskState(disk.name, state: .disconnected)
            }

            alertManager.alertDiskDisconnected(diskName: disk.name)
        }
    }

    // MARK: - 公共方法

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
        Logger.shared.info("用户请求手动同步")
        Task {
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
        Logger.shared.info("用户请求打开标签: \(tab.rawValue)")
        mainWindowController?.showTab(tab)
    }
}
