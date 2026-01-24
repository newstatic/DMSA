import SwiftUI

/// 主窗口视图 - 单窗口应用结构
struct MainView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var selectedTab: MainTab? = .dashboard

    enum MainTab: String, CaseIterable, Identifiable {
        case dashboard        // 首页
        case general          // 常规
        case disks            // 硬盘
        case syncPairs        // 同步对
        case filters          // 过滤
        case notifications    // 通知设置
        case notificationHistory  // 通知记录
        case logs             // 日志
        case history          // 同步历史
        case statistics       // 统计
        case advanced         // 高级

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: return "dashboard.title".localized
            case .general: return L10n.Settings.general
            case .disks: return L10n.Settings.disks
            case .syncPairs: return L10n.Settings.syncPairs
            case .filters: return L10n.Settings.filters
            case .notifications: return L10n.Settings.notifications
            case .notificationHistory: return "settings.notificationHistory".localized
            case .logs: return "settings.logs".localized
            case .history: return "settings.history".localized
            case .statistics: return L10n.Settings.statistics
            case .advanced: return L10n.Settings.advanced
            }
        }

        var icon: String {
            switch self {
            case .dashboard: return "house.fill"
            case .general: return "gearshape"
            case .disks: return "externaldrive"
            case .syncPairs: return "folder"
            case .filters: return "line.3.horizontal.decrease.circle"
            case .notifications: return "bell"
            case .notificationHistory: return "bell.badge"
            case .logs: return "doc.text"
            case .history: return "clock.arrow.circlepath"
            case .statistics: return "chart.bar.xaxis"
            case .advanced: return "slider.horizontal.3"
            }
        }

        var isSeparatorBefore: Bool {
            switch self {
            case .notificationHistory, .advanced: return true
            default: return false
            }
        }
    }

    var body: some View {
        NavigationView {
            // Sidebar
            List(selection: $selectedTab) {
                ForEach(MainTab.allCases) { tab in
                    if tab.isSeparatorBefore {
                        Divider()
                            .padding(.vertical, 4)
                    }

                    NavigationLink(
                        destination: destinationView(for: tab),
                        tag: tab,
                        selection: $selectedTab
                    ) {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)

            // Default content
            DashboardView(config: $configManager.config)
        }
        .frame(minWidth: 750, minHeight: 500)
        .frame(idealWidth: 850, idealHeight: 600)
        // Force view refresh when language changes
        .id(localizationManager.currentLanguage)
    }

    @ViewBuilder
    private func destinationView(for tab: MainTab) -> some View {
        switch tab {
        case .dashboard:
            DashboardView(config: $configManager.config)
        case .general:
            GeneralSettingsView(config: $configManager.config)
        case .disks:
            DiskSettingsView(config: $configManager.config)
        case .syncPairs:
            SyncPairSettingsView(config: $configManager.config)
        case .filters:
            FilterSettingsView(config: $configManager.config)
        case .notifications:
            NotificationSettingsView(config: $configManager.config)
        case .notificationHistory:
            NotificationHistoryView()
        case .logs:
            LogView()
        case .history:
            HistoryContentView()
        case .statistics:
            StatisticsView(config: $configManager.config)
        case .advanced:
            AdvancedSettingsView(config: $configManager.config, configManager: configManager)
        }
    }
}

// MARK: - Main Window Controller

class MainWindowController {
    private var window: NSWindow?
    private let configManager: ConfigManager

    init(configManager: ConfigManager) {
        self.configManager = configManager
    }

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let mainView = MainView(configManager: configManager)
        let hostingController = NSHostingController(rootView: mainView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = L10n.App.name
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 850, height: 600))
        newWindow.minSize = NSSize(width: 750, height: 500)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showTab(_ tab: MainView.MainTab) {
        showWindow()
        // 可以通过 NotificationCenter 发送选择标签页的通知
        NotificationCenter.default.post(
            name: .selectMainTab,
            object: nil,
            userInfo: ["tab": tab]
        )
    }

    func closeWindow() {
        window?.close()
        window = nil
    }
}

// MARK: - Notification Name Extension

extension Notification.Name {
    static let selectMainTab = Notification.Name("selectMainTab")
}

// MARK: - Previews

#if DEBUG
struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView(configManager: ConfigManager.shared)
            .frame(width: 850, height: 600)
    }
}
#endif
