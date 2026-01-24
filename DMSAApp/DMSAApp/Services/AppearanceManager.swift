import Cocoa

/// 外观管理器 - 管理 Dock 图标显示等
final class AppearanceManager {
    static let shared = AppearanceManager()

    private init() {}

    /// 检查是否在 Dock 中显示图标
    var showInDock: Bool {
        return NSApp.activationPolicy() == .regular
    }

    /// 设置是否在 Dock 中显示图标
    func setShowInDock(_ show: Bool) {
        if show {
            // 显示 Dock 图标
            NSApp.setActivationPolicy(.regular)
            Logger.shared.info("已启用 Dock 图标显示")
        } else {
            // 隐藏 Dock 图标 (仅菜单栏应用)
            NSApp.setActivationPolicy(.accessory)
            Logger.shared.info("已禁用 Dock 图标显示")
        }
    }

    /// 根据配置应用外观设置
    func applySettings(from config: GeneralConfig) {
        setShowInDock(config.showInDock)
    }
}
