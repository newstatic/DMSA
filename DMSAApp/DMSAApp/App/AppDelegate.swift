import Cocoa
import SwiftUI
import ServiceManagement

/// 应用代理
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - 管理器

    private var menuBarManager: MenuBarManager!
    private let configManager = ConfigManager.shared
    private let diskManager = DiskManager.shared
    private let syncEngine = SyncEngine.shared
    private let alertManager = AlertManager.shared
    private let appearanceManager = AppearanceManager.shared
    private let serviceClient = ServiceClient.shared

    // MARK: - 窗口控制器

    private var mainWindowController: MainWindowController?

    // MARK: - 同步控制属性

    /// 是否自动同步已启用
    var isAutoSyncEnabled: Bool {
        get { configManager.config.general.autoSyncEnabled }
        set {
            configManager.config.general.autoSyncEnabled = newValue
            configManager.saveConfig()
            Logger.shared.info("自动同步开关: \(newValue ? "开启" : "关闭")")
        }
    }

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("============================================")
        Logger.shared.info("DMSA v2.0 启动")
        Logger.shared.info("============================================")

        setupManagers()
        setupDiskCallbacks()
        checkInitialState()
        applyAppearanceSettings()

        // 检查权限
        checkPermissionsOnStartup()

        // 检查并安装 Helper
        checkAndInstallHelper()

        // 检查 macFUSE
        checkMacFUSE()

        // 启动时打开主窗口
        mainWindowController?.showWindow()

        Logger.shared.info("应用初始化完成")
        Logger.shared.info("自动同步状态: \(isAutoSyncEnabled ? "已启用" : "已禁用")")
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

        // 初始化主窗口控制器
        mainWindowController = MainWindowController(configManager: configManager)

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

    private func applyAppearanceSettings() {
        // 应用 Dock 图标显示设置
        appearanceManager.applySettings(from: configManager.config.general)
        Logger.shared.info("外观设置已应用")
    }

    private func checkPermissionsOnStartup() {
        Task { @MainActor in
            let permissionManager = PermissionManager.shared
            await permissionManager.checkAllPermissions()

            // 记录权限状态
            Logger.shared.info("权限状态检查:")
            Logger.shared.info("  - 完全磁盘访问: \(permissionManager.hasFullDiskAccess ? "已授权" : "未授权")")
            Logger.shared.info("  - 通知权限: \(permissionManager.hasNotificationPermission ? "已授权" : "未授权")")

            // 如果缺少关键权限，提醒用户
            if !permissionManager.hasFullDiskAccess {
                Logger.shared.warn("警告: 未获得完全磁盘访问权限，某些目录可能无法同步")
            }

            // 如果没有通知权限，请求
            if !permissionManager.hasNotificationPermission {
                _ = await permissionManager.requestNotificationPermission()
            }
        }
    }

    private func checkAndInstallHelper() {
        Logger.shared.info("检查 DMSAService 状态...")

        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "com.ttttt.dmsa.service.plist")
            let status = service.status

            Logger.shared.info("DMSAService 状态: \(status)")

            switch status {
            case .notRegistered, .notFound:
                Logger.shared.info("DMSAService 未安装，尝试安装...")
                installService()
            case .requiresApproval:
                Logger.shared.warn("DMSAService 需要用户批准")
                showServiceApprovalAlert()
            case .enabled:
                Logger.shared.info("DMSAService 已安装")
                verifyServiceVersion()
            @unknown default:
                Logger.shared.warn("DMSAService 状态未知")
            }
        } else {
            // macOS 12 及以下版本使用文件检测
            let helperPath = "/Library/PrivilegedHelperTools/com.ttttt.dmsa.service"
            if FileManager.default.fileExists(atPath: helperPath) {
                Logger.shared.info("DMSAService 已安装 (legacy check)")
                verifyServiceVersion()
            } else {
                Logger.shared.info("DMSAService 未安装")
                installServiceLegacy()
            }
        }
    }

    @available(macOS 13.0, *)
    private func installService() {
        do {
            let service = SMAppService.daemon(plistName: "com.ttttt.dmsa.service.plist")
            try service.register()
            Logger.shared.info("DMSAService 安装成功")
        } catch {
            Logger.shared.error("DMSAService 安装失败: \(error.localizedDescription)")
            showServiceInstallFailedAlert(error: error)
        }
    }

    private func installServiceLegacy() {
        // macOS 12 及以下版本使用 SMJobBless
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authRef)

        guard status == errAuthorizationSuccess, let auth = authRef else {
            Logger.shared.error("DMSAService 授权失败")
            return
        }

        defer { AuthorizationFree(auth, []) }

        var error: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            "com.ttttt.dmsa.service" as CFString,
            auth,
            &error
        )

        if success {
            Logger.shared.info("DMSAService 安装成功 (legacy)")
        } else {
            let errorDesc = error?.takeRetainedValue().localizedDescription ?? "未知错误"
            Logger.shared.error("DMSAService 安装失败: \(errorDesc)")
        }
    }

    private func verifyServiceVersion() {
        Task {
            do {
                let version = try await serviceClient.getVersion()
                Logger.shared.info("DMSAService 版本: \(version)")

                if version != Constants.version {
                    Logger.shared.warn("DMSAService 版本不匹配 (期望 \(Constants.version), 实际 \(version))")
                }
            } catch {
                Logger.shared.warn("无法获取 DMSAService 版本: \(error.localizedDescription)")
            }
        }
    }

    private func showServiceApprovalAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "需要批准 DMSA 服务"
            alert.informativeText = "DMSA 需要安装后台服务来管理虚拟文件系统和同步功能。\n\n请前往 系统设置 > 隐私与安全性 > 登录项与扩展 中批准 DMSA Service。"
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

    private func showServiceInstallFailedAlert(error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "DMSA 服务安装失败"
            alert.informativeText = "无法安装后台服务: \(error.localizedDescription)\n\n虚拟文件系统和同步功能可能无法正常工作。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    private func checkMacFUSE() {
        Logger.shared.info("检查 macFUSE 状态...")

        let availability = FUSEManager.shared.checkFUSEAvailability()

        switch availability {
        case .available(let version):
            Logger.shared.info("macFUSE 已安装，版本: \(version)")
        case .notInstalled, .frameworkMissing:
            Logger.shared.warn("macFUSE 未安装")
            showMacFUSENotInstalledAlert()
        case .versionTooOld(let current, let required):
            Logger.shared.warn("macFUSE 版本过旧: \(current)，需要 \(required)")
            showMacFUSEUpdateAlert(current: current, required: required)
        case .loadError(let error):
            Logger.shared.error("macFUSE 加载失败: \(error.localizedDescription)")
            showMacFUSENotInstalledAlert()
        }
    }

    private func showMacFUSENotInstalledAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "macFUSE 未安装"
            alert.informativeText = "DMSA 需要 macFUSE 来创建虚拟文件系统。\n\n请从官方网站下载并安装 macFUSE。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "下载 macFUSE")
            alert.addButton(withTitle: "稍后")

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "https://macfuse.github.io/") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func showMacFUSEUpdateAlert(current: String, required: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "macFUSE 需要更新"
            alert.informativeText = "当前版本 \(current) 过旧，需要 \(required) 或更高版本。\n\n请从官方网站下载最新版本。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "下载更新")
            alert.addButton(withTitle: "稍后")

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "https://macfuse.github.io/") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - 硬盘事件处理

    private func handleDiskConnected(_ disk: DiskConfig) {
        Logger.shared.info("处理硬盘连接: \(disk.name)")

        // 更新菜单栏状态
        menuBarManager.updateDiskState(disk.name, state: .connected(diskName: disk.name, usedSpace: nil, totalSpace: nil))

        // 发送弹窗通知
        alertManager.alertDiskConnected(diskName: disk.name)

        // 检查自动同步开关
        guard isAutoSyncEnabled else {
            Logger.shared.info("自动同步已禁用，跳过自动同步")
            return
        }

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

        // 发送弹窗通知
        alertManager.alertDiskDisconnected(diskName: disk.name)
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
            alertManager.alertSyncFailed(error: error.localizedDescription)
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

    private func showSettings() {
        Logger.shared.info("打开设置窗口")
        mainWindowController?.showWindow()
    }

    // MARK: - 公共方法

    /// 切换自动同步开关
    func toggleAutoSync() {
        isAutoSyncEnabled = !isAutoSyncEnabled
        menuBarManager.updateAutoSyncState(isEnabled: isAutoSyncEnabled)
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

    func menuBarDidRequestToggleAutoSync() {
        toggleAutoSync()
    }
}

// MARK: - SyncEngineDelegate

extension AppDelegate: SyncEngineDelegate {
    func syncEngine(_ engine: SyncEngine, didStartTask task: SyncTask) {
        Logger.shared.info("同步任务开始: \(task.syncPair.localPath)")
        // 同步开始时不弹窗，避免打扰用户
    }

    func syncEngine(_ engine: SyncEngine, didUpdateProgress task: SyncTask, progress: Double, message: String) {
        // 进度更新 (可以用于 UI 显示)
        Logger.shared.debug("同步进度: \(Int(progress * 100))%")
    }

    func syncEngine(_ engine: SyncEngine, didCompleteTask task: SyncTask, result: SyncResult) {
        Logger.shared.info("同步任务完成: \(task.syncPair.localPath), 文件数: \(result.filesTransferred)")
        alertManager.alertSyncCompleted(
            filesCount: result.filesTransferred,
            totalSize: result.bytesTransferred,
            duration: result.duration
        )
    }

    func syncEngine(_ engine: SyncEngine, didFailTask task: SyncTask, error: Error) {
        Logger.shared.error("同步任务失败: \(task.syncPair.localPath), 错误: \(error.localizedDescription)")
        alertManager.alertSyncFailed(error: error.localizedDescription)
    }
}
