import Foundation
import ServiceManagement

/// 登录启动管理器
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    /// 检查是否启用了登录启动
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // macOS 12 及以下使用旧 API
            return legacyIsEnabled
        }
    }

    /// 设置登录启动状态
    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    Logger.shared.info("已启用登录时自动启动")
                } else {
                    try SMAppService.mainApp.unregister()
                    Logger.shared.info("已禁用登录时自动启动")
                }
            } catch {
                Logger.shared.error("设置登录启动失败: \(error.localizedDescription)")
            }
        } else {
            // macOS 12 及以下使用旧 API
            legacySetEnabled(enabled)
        }
    }

    // MARK: - Legacy API (macOS 12 及以下)

    private var legacyIsEnabled: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        // 使用 deprecated API 检查状态
        // 注意: 这在 macOS 13+ 已废弃，但为了兼容性保留
        let jobDicts = SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: Any]] ?? []
        return jobDicts.contains { dict in
            (dict["Label"] as? String) == bundleIdentifier
        }
    }

    private func legacySetEnabled(_ enabled: Bool) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            Logger.shared.error("无法获取 Bundle Identifier")
            return
        }

        // 使用 LaunchAgent plist 方式
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(bundleIdentifier).plist")

        if enabled {
            // 创建 LaunchAgent plist
            let plist: [String: Any] = [
                "Label": bundleIdentifier,
                "ProgramArguments": [Bundle.main.executablePath ?? ""],
                "RunAtLoad": true,
                "KeepAlive": false
            ]

            do {
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: launchAgentPath)
                Logger.shared.info("已创建 LaunchAgent: \(launchAgentPath.path)")
            } catch {
                Logger.shared.error("创建 LaunchAgent 失败: \(error.localizedDescription)")
            }
        } else {
            // 删除 LaunchAgent plist
            do {
                if FileManager.default.fileExists(atPath: launchAgentPath.path) {
                    try FileManager.default.removeItem(at: launchAgentPath)
                    Logger.shared.info("已删除 LaunchAgent")
                }
            } catch {
                Logger.shared.error("删除 LaunchAgent 失败: \(error.localizedDescription)")
            }
        }
    }
}
