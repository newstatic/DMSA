import SwiftUI

/// Main settings window with sidebar navigation
/// Note: This is kept for backward compatibility. Use MainView for the new single-window architecture.
struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var selectedTab: SettingsTab? = .dashboard

    enum SettingsTab: String, CaseIterable, Identifiable {
        case dashboard
        case general
        case disks
        case syncPairs
        case filters
        case vfs
        case notifications
        case notificationHistory
        case logs
        case history
        case statistics
        case advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: return "dashboard.title".localized
            case .general: return L10n.Settings.general
            case .disks: return L10n.Settings.disks
            case .syncPairs: return L10n.Settings.syncPairs
            case .filters: return L10n.Settings.filters
            case .vfs: return "虚拟文件系统"
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
            case .vfs: return "externaldrive.connected.to.line.below"
            case .notifications: return "bell"
            case .notificationHistory: return "bell.badge"
            case .logs: return "doc.text"
            case .history: return "clock.arrow.circlepath"
            case .statistics: return "chart.bar.xaxis"
            case .advanced: return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        NavigationView {
            // Sidebar
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
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
            GeneralSettingsView(config: $configManager.config)
        }
        .frame(minWidth: 750, minHeight: 500)
        .frame(idealWidth: 850, idealHeight: 600)
        // Force view refresh when language changes
        .id(localizationManager.currentLanguage)
    }

    @ViewBuilder
    private func destinationView(for tab: SettingsTab) -> some View {
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
        case .vfs:
            VFSSettingsView(config: $configManager.config)
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

/// A container for settings content with consistent styling
struct SettingsContentView<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.bottom, 4)

                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 400)
    }
}

// MARK: - Window Controller

class SettingsWindowController {
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

        let settingsView = SettingsView(configManager: configManager)
        let hostingController = NSHostingController(rootView: settingsView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = L10n.Settings.title
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 850, height: 600))
        newWindow.minSize = NSSize(width: 750, height: 500)
        newWindow.center()

        // Set window to release when closed
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.close()
        window = nil
    }
}

// MARK: - Previews

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(configManager: ConfigManager.shared)
            .frame(width: 850, height: 600)
    }
}
#endif
