import Cocoa

/// Appearance manager - manages Dock icon display etc.
final class AppearanceManager {
    static let shared = AppearanceManager()

    private init() {}

    /// Check if Dock icon is shown
    var showInDock: Bool {
        return NSApp.activationPolicy() == .regular
    }

    /// Set whether to show Dock icon
    func setShowInDock(_ show: Bool) {
        if show {
            // Show Dock icon
            NSApp.setActivationPolicy(.regular)
            Logger.shared.info("Dock icon display enabled")
        } else {
            // Hide Dock icon (menu bar app only)
            NSApp.setActivationPolicy(.accessory)
            Logger.shared.info("Dock icon display disabled")
        }
    }

    /// Apply appearance settings from config
    func applySettings(from config: GeneralConfig) {
        setShowInDock(config.showInDock)
    }
}
