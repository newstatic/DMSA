import Cocoa
import SwiftUI
import ServiceManagement

/// 应用代理
/// v4.3: 仅负责生命周期管理和 UI 交互，业务逻辑由 DMSAService 处理
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - UI 管理器

    private var menuBarManager: MenuBarManager!
    private let configManager = ConfigManager.shared
    private let diskManager = DiskManager.shared
    private let alertManager = AlertManager.shared
    private let serviceClient = ServiceClient.shared

    // MARK: - 窗口控制器

    private var mainWindowController: MainWindowController?

    // MARK: - 同步控制属性

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
        Logger.shared.info("DMSA v4.3 启动")
        Logger.shared.info("============================================")

        setupUI()
        setupDiskCallbacks()
        checkInitialState()

        // 检查并安装 Service
        checkAndInstallService()

        // 检查 macFUSE
        checkMacFUSE()

        Logger.shared.info("应用初始化完成")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("应用即将退出")

        // 通知 Service 准备关闭 (Service 本身不会退出，只是做清理)
        Task {
            try? await serviceClient.prepareForShutdown()
        }

        Logger.shared.info("============================================")
        Logger.shared.info("DMSA 已退出")
        Logger.shared.info("============================================")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // 菜单栏应用
    }

    // MARK: - 初始化

    private func setupUI() {
        menuBarManager = MenuBarManager()
        menuBarManager.delegate = self
        mainWindowController = MainWindowController(configManager: configManager)
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
        Logger.shared.info("已创建默认配置")
    }

    // MARK: - Service 管理

    private func checkAndInstallService() {
        Logger.shared.info("检查 DMSAService 状态...")

        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "com.ttttt.dmsa.service.plist")

            switch service.status {
            case .notRegistered, .notFound:
                Logger.shared.info("DMSAService 未安装，尝试安装...")
                installService()
            case .requiresApproval:
                Logger.shared.warn("DMSAService 需要用户批准")
                showServiceApprovalAlert()
            case .enabled:
                Logger.shared.info("DMSAService 已安装")
                connectToService()
            @unknown default:
                Logger.shared.warn("DMSAService 状态未知")
            }
        } else {
            let helperPath = "/Library/PrivilegedHelperTools/com.ttttt.dmsa.service"
            if FileManager.default.fileExists(atPath: helperPath) {
                Logger.shared.info("DMSAService 已安装")
                connectToService()
            } else {
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
            connectToService()
        } catch {
            Logger.shared.error("DMSAService 安装失败: \(error)")
            showServiceInstallFailedAlert(error: error)
        }
    }

    private func installServiceLegacy() {
        var authRef: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authRef) == errAuthorizationSuccess,
              let auth = authRef else {
            Logger.shared.error("DMSAService 授权失败")
            return
        }

        defer { AuthorizationFree(auth, []) }

        var error: Unmanaged<CFError>?
        if SMJobBless(kSMDomainSystemLaunchd, "com.ttttt.dmsa.service" as CFString, auth, &error) {
            Logger.shared.info("DMSAService 安装成功")
            connectToService()
        } else {
            Logger.shared.error("DMSAService 安装失败: \(error?.takeRetainedValue().localizedDescription ?? "未知错误")")
        }
    }

    private func connectToService() {
        Task {
            do {
                _ = try await serviceClient.connect()
                let version = try await serviceClient.getVersion()
                Logger.shared.info("已连接到 DMSAService v\(version)")
            } catch {
                Logger.shared.error("连接 DMSAService 失败: \(error)")
            }
        }
    }

    private func showServiceApprovalAlert() {
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

    private func showServiceInstallFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "DMSA 服务安装失败"
        alert.informativeText = "无法安装后台服务: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
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
        menuBarManager.updateDiskState(disk.name, state: .connected(diskName: disk.name, usedSpace: nil, totalSpace: nil))
        alertManager.alertDiskConnected(diskName: disk.name)

        // 自动同步由 Service 处理，这里只触发
        guard isAutoSyncEnabled else { return }

        Task {
            try? await serviceClient.syncNow(syncPairId: "default_downloads")
        }
    }

    private func handleDiskDisconnected(_ disk: DiskConfig) {
        Logger.shared.info("硬盘已断开: \(disk.name)")

        if diskManager.connectedDisks.isEmpty {
            menuBarManager.updateDiskState(disk.name, state: .disconnected)
        }

        alertManager.alertDiskDisconnected(diskName: disk.name)
    }

    // MARK: - 公共方法

    func toggleAutoSync() {
        isAutoSyncEnabled = !isAutoSyncEnabled
        menuBarManager.updateAutoSyncState(isEnabled: isAutoSyncEnabled)
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
}
