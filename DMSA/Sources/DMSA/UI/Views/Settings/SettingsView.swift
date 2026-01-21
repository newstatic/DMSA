import SwiftUI

/// Main settings window with sidebar navigation
struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var selectedTab: SettingsTab? = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case disks
        case syncPairs
        case filters
        case cache
        case notifications
        case advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return L10n.Settings.general
            case .disks: return L10n.Settings.disks
            case .syncPairs: return L10n.Settings.syncPairs
            case .filters: return L10n.Settings.filters
            case .cache: return L10n.Settings.cache
            case .notifications: return L10n.Settings.notifications
            case .advanced: return L10n.Settings.advanced
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .disks: return "externaldrive"
            case .syncPairs: return "folder"
            case .filters: return "line.3.horizontal.decrease.circle"
            case .cache: return "internaldrive"
            case .notifications: return "bell"
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
        .frame(minWidth: 600, minHeight: 450)
        .frame(idealWidth: 700, idealHeight: 500)
        // Force view refresh when language changes
        .id(localizationManager.currentLanguage)
    }

    @ViewBuilder
    private func destinationView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView(config: $configManager.config)
        case .disks:
            DiskSettingsView(config: $configManager.config)
        case .syncPairs:
            SyncPairSettingsView(config: $configManager.config)
        case .filters:
            FilterSettingsView(config: $configManager.config)
        case .cache:
            CacheSettingsView(config: $configManager.config)
        case .notifications:
            NotificationSettingsView(config: $configManager.config)
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
        newWindow.setContentSize(NSSize(width: 700, height: 500))
        newWindow.minSize = NSSize(width: 600, height: 450)
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
            .frame(width: 700, height: 500)
    }
}
#endif
