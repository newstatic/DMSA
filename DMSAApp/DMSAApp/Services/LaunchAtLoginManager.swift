import Foundation
import ServiceManagement

/// Launch at login manager
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    /// Check if launch at login is enabled
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // macOS 12 and below use legacy API
            return legacyIsEnabled
        }
    }

    /// Set launch at login state
    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    Logger.shared.info("Launch at login enabled")
                } else {
                    try SMAppService.mainApp.unregister()
                    Logger.shared.info("Launch at login disabled")
                }
            } catch {
                Logger.shared.error("Failed to set launch at login: \(error.localizedDescription)")
            }
        } else {
            // macOS 12 and below use legacy API
            legacySetEnabled(enabled)
        }
    }

    // MARK: - Legacy API (macOS 12 and below)

    private var legacyIsEnabled: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        // Using deprecated API to check status
        // Note: deprecated in macOS 13+, kept for compatibility
        let jobDicts = SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: Any]] ?? []
        return jobDicts.contains { dict in
            (dict["Label"] as? String) == bundleIdentifier
        }
    }

    private func legacySetEnabled(_ enabled: Bool) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            Logger.shared.error("Unable to get Bundle Identifier")
            return
        }

        // Use LaunchAgent plist approach
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(bundleIdentifier).plist")

        if enabled {
            // Create LaunchAgent plist
            let plist: [String: Any] = [
                "Label": bundleIdentifier,
                "ProgramArguments": [Bundle.main.executablePath ?? ""],
                "RunAtLoad": true,
                "KeepAlive": false
            ]

            do {
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: launchAgentPath)
                Logger.shared.info("Created LaunchAgent: \(launchAgentPath.path)")
            } catch {
                Logger.shared.error("Failed to create LaunchAgent: \(error.localizedDescription)")
            }
        } else {
            // Delete LaunchAgent plist
            do {
                if FileManager.default.fileExists(atPath: launchAgentPath.path) {
                    try FileManager.default.removeItem(at: launchAgentPath)
                    Logger.shared.info("Deleted LaunchAgent")
                }
            } catch {
                Logger.shared.error("Failed to delete LaunchAgent: \(error.localizedDescription)")
            }
        }
    }
}
