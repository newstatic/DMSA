import Foundation
import AppKit

/// macFUSE 管理器
/// 负责检测 macFUSE 安装状态、版本验证和安装引导
///
/// 使用方式:
/// 1. 启动时调用 checkFUSEAvailability()
/// 2. 若未安装则调用 showInstallationGuide()
/// 3. 若版本不匹配则调用 showUpdateGuide()
final class FUSEManager {

    // MARK: - 单例

    static let shared = FUSEManager()

    // MARK: - 常量

    /// macFUSE Framework 路径
    private let macFUSEFrameworkPath = "/Library/Frameworks/macFUSE.framework"

    /// macFUSE 最低支持版本
    private let minimumVersion = "4.0.0"

    /// 推荐版本
    private let recommendedVersion = "5.1.3"

    /// macFUSE 下载地址
    private let downloadURL = URL(string: "https://macfuse.github.io/")!

    /// macFUSE GitHub Releases
    private let releasesURL = URL(string: "https://github.com/macfuse/macfuse/releases")!

    // MARK: - 状态

    /// FUSE 可用性状态
    enum FUSEStatus {
        case available(version: String)
        case notInstalled
        case versionTooOld(installed: String, required: String)
        case frameworkMissing
        case loadError(Error)
    }

    private(set) var currentStatus: FUSEStatus = .notInstalled

    // MARK: - 初始化

    private init() {}

    // MARK: - 检测方法

    /// 检查 macFUSE 可用性
    /// - Returns: 当前 FUSE 状态
    @discardableResult
    func checkFUSEAvailability() -> FUSEStatus {
        Logger.shared.info("FUSEManager: 检查 macFUSE 可用性")

        // 1. 检查 Framework 是否存在
        let fm = FileManager.default
        guard fm.fileExists(atPath: macFUSEFrameworkPath) else {
            Logger.shared.warning("FUSEManager: macFUSE.framework 不存在")
            currentStatus = .notInstalled
            return currentStatus
        }

        // 2. 检查 Framework 结构完整性
        let requiredFiles = [
            "\(macFUSEFrameworkPath)/Versions/A/macFUSE",
            "\(macFUSEFrameworkPath)/Headers/fuse.h"
        ]

        for file in requiredFiles {
            if !fm.fileExists(atPath: file) {
                Logger.shared.warning("FUSEManager: 缺少必要文件: \(file)")
                currentStatus = .frameworkMissing
                return currentStatus
            }
        }

        // 3. 读取版本信息
        guard let version = getInstalledVersion() else {
            Logger.shared.warning("FUSEManager: 无法读取 macFUSE 版本")
            currentStatus = .frameworkMissing
            return currentStatus
        }

        // 4. 版本比较
        if compareVersions(version, minimumVersion) < 0 {
            Logger.shared.warning("FUSEManager: macFUSE 版本过旧 (\(version) < \(minimumVersion))")
            currentStatus = .versionTooOld(installed: version, required: minimumVersion)
            return currentStatus
        }

        // 5. 检查 API 可用性
        if !checkAPIAvailability() {
            Logger.shared.error("FUSEManager: macFUSE API 不可用")
            currentStatus = .frameworkMissing
            return currentStatus
        }

        Logger.shared.info("FUSEManager: macFUSE 可用 (版本: \(version))")
        currentStatus = .available(version: version)
        return currentStatus
    }

    /// 获取已安装的 macFUSE 版本
    private func getInstalledVersion() -> String? {
        let infoPlistPath = "\(macFUSEFrameworkPath)/Versions/A/Resources/Info.plist"

        guard let plist = NSDictionary(contentsOfFile: infoPlistPath) else {
            return nil
        }

        return plist["CFBundleShortVersionString"] as? String
            ?? plist["CFBundleVersion"] as? String
    }

    /// 检查 macFUSE API 可用性
    private func checkAPIAvailability() -> Bool {
        // 检查 GMUserFileSystem 类是否可加载
        let bundlePath = "\(macFUSEFrameworkPath)/Versions/A/macFUSE"

        // 尝试动态加载 Framework
        guard let bundle = Bundle(path: macFUSEFrameworkPath) else {
            return false
        }

        // 检查是否已加载或可加载
        if !bundle.isLoaded {
            do {
                try bundle.loadAndReturnError()
            } catch {
                Logger.shared.error("FUSEManager: 加载 macFUSE 失败: \(error)")
                return false
            }
        }

        // 检查核心类是否存在
        guard NSClassFromString("GMUserFileSystem") != nil else {
            Logger.shared.warning("FUSEManager: GMUserFileSystem 类不存在")
            return false
        }

        return true
    }

    /// 版本比较
    /// - Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2
    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(parts1.count, parts2.count)

        for i in 0..<maxLength {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0

            if p1 < p2 { return -1 }
            if p1 > p2 { return 1 }
        }

        return 0
    }

    // MARK: - 安装引导

    /// 显示安装引导对话框
    func showInstallationGuide() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("fuse.install.title", comment: "")
            alert.informativeText = NSLocalizedString("fuse.install.message", comment: "")
            alert.alertStyle = .warning

            alert.addButton(withTitle: NSLocalizedString("fuse.install.download", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("common.later", comment: ""))

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(self.downloadURL)
            }
        }
    }

    /// 显示更新引导对话框
    func showUpdateGuide(installedVersion: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("fuse.update.title", comment: "")
            alert.informativeText = String(
                format: NSLocalizedString("fuse.update.message", comment: ""),
                installedVersion,
                self.recommendedVersion
            )
            alert.alertStyle = .warning

            alert.addButton(withTitle: NSLocalizedString("fuse.update.download", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("common.ignore", comment: ""))

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(self.releasesURL)
            }
        }
    }

    /// 显示 Framework 缺失警告
    func showFrameworkMissingAlert() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("fuse.missing.title", comment: "")
            alert.informativeText = NSLocalizedString("fuse.missing.message", comment: "")
            alert.alertStyle = .critical

            alert.addButton(withTitle: NSLocalizedString("fuse.install.download", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("common.quit", comment: ""))

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(self.downloadURL)
            } else {
                // 用户选择退出
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - 便捷方法

    /// 是否可用
    var isAvailable: Bool {
        if case .available = currentStatus {
            return true
        }
        return false
    }

    /// 获取当前版本 (如果已安装)
    var installedVersion: String? {
        if case .available(let version) = currentStatus {
            return version
        }
        return getInstalledVersion()
    }

    /// 处理启动时的 FUSE 检查
    /// - Returns: 是否可以继续启动 VFS
    func handleStartupCheck() -> Bool {
        let status = checkFUSEAvailability()

        switch status {
        case .available:
            Logger.shared.info("FUSEManager: macFUSE 检查通过")
            return true

        case .notInstalled:
            Logger.shared.warning("FUSEManager: macFUSE 未安装，显示安装引导")
            showInstallationGuide()
            return false

        case .versionTooOld(let installed, _):
            Logger.shared.warning("FUSEManager: macFUSE 版本过旧，显示更新引导")
            showUpdateGuide(installedVersion: installed)
            return false

        case .frameworkMissing:
            Logger.shared.error("FUSEManager: macFUSE Framework 不完整")
            showFrameworkMissingAlert()
            return false

        case .loadError(let error):
            Logger.shared.error("FUSEManager: 加载 macFUSE 失败: \(error)")
            showFrameworkMissingAlert()
            return false
        }
    }
}

// MARK: - 本地化字符串扩展

extension FUSEManager {
    /// 获取状态描述
    var statusDescription: String {
        switch currentStatus {
        case .available(let version):
            return String(format: NSLocalizedString("fuse.status.available", comment: ""), version)
        case .notInstalled:
            return NSLocalizedString("fuse.status.notInstalled", comment: "")
        case .versionTooOld(let installed, let required):
            return String(format: NSLocalizedString("fuse.status.versionTooOld", comment: ""), installed, required)
        case .frameworkMissing:
            return NSLocalizedString("fuse.status.frameworkMissing", comment: "")
        case .loadError:
            return NSLocalizedString("fuse.status.loadError", comment: "")
        }
    }
}
