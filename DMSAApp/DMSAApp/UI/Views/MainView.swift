import SwiftUI

// MARK: - Main View

/// 主窗口视图 - 单窗口 + 左侧导航
/// v4.8: 使用 StateManager 作为唯一状态管理器
struct MainView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @ObservedObject private var stateManager = StateManager.shared
    @State private var selectedTab: MainTab = .dashboard

    // MARK: - Navigation Tabs (6 items as per design spec)

    enum MainTab: String, CaseIterable, Identifiable {
        case dashboard    // 仪表盘
        case sync         // 同步
        case conflicts    // 冲突
        case disks        // 磁盘
        case settings     // 设置
        case logs         // 日志

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: return "nav.dashboard".localized
            case .sync: return "nav.sync".localized
            case .conflicts: return "nav.conflicts".localized
            case .disks: return "nav.disks".localized
            case .settings: return "nav.settings".localized
            case .logs: return "nav.logs".localized
            }
        }

        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.33percent"
            case .sync: return "arrow.triangle.2.circlepath"
            case .conflicts: return "exclamationmark.2"
            case .disks: return "externaldrive"
            case .settings: return "gear"
            case .logs: return "doc.text"
            }
        }

        var shortcut: KeyEquivalent? {
            switch self {
            case .dashboard: return "1"
            case .sync: return "2"
            case .conflicts: return "3"
            case .disks: return "4"
            case .settings: return ","
            case .logs: return nil
            }
        }

        /// 主导航组 (仪表盘、同步、冲突、磁盘)
        static var mainGroup: [MainTab] {
            [.dashboard, .sync, .conflicts, .disks]
        }

        /// 次要导航组 (设置、日志)
        static var secondaryGroup: [MainTab] {
            [.settings, .logs]
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            // MARK: Sidebar
            VStack(spacing: 0) {
                // Sidebar Header - Status Display
                SidebarHeaderView(stateManager: stateManager)

                Divider()
                    .padding(.horizontal, 12)

                // Navigation List
                List(selection: $selectedTab) {
                    // Main navigation group
                    Section {
                        ForEach(MainTab.mainGroup) { tab in
                            NavigationItemView(
                                tab: tab,
                                isSelected: selectedTab == tab,
                                badge: badgeForTab(tab)
                            )
                            .tag(tab)
                        }
                    }

                    // Secondary navigation group
                    Section {
                        ForEach(MainTab.secondaryGroup) { tab in
                            NavigationItemView(
                                tab: tab,
                                isSelected: selectedTab == tab,
                                badge: nil
                            )
                            .tag(tab)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
            .background(Color(NSColor.windowBackgroundColor))

        } detail: {
            // MARK: Content Area
            contentView(for: selectedTab)
        }
        .frame(minWidth: 720, minHeight: 480)
        .frame(idealWidth: 900, idealHeight: 600)
        .id(localizationManager.currentLanguage)
        .onReceive(NotificationCenter.default.publisher(for: .selectMainTab)) { notification in
            if let tab = notification.userInfo?["tab"] as? MainTab {
                selectedTab = tab
            }
        }
        // Keyboard shortcuts
        .background(keyboardShortcuts)
    }

    // MARK: - Badge for Tab

    private func badgeForTab(_ tab: MainTab) -> NavigationBadge? {
        switch tab {
        case .sync:
            if stateManager.isSyncing {
                return NavigationBadge(text: "nav.badge.syncing".localized, color: .blue)
            }
            return nil
        case .conflicts:
            if stateManager.conflictCount > 0 {
                return NavigationBadge(text: "\(stateManager.conflictCount)", color: .orange)
            }
            return nil
        default:
            return nil
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private func contentView(for tab: MainTab) -> some View {
        switch tab {
        case .dashboard:
            DashboardView(config: $configManager.config)
        case .sync:
            SyncPage(config: $configManager.config)
        case .conflicts:
            ConflictsPage(config: $configManager.config)
        case .disks:
            DisksPage(config: $configManager.config)
        case .settings:
            SettingsPage(config: $configManager.config, configManager: configManager)
        case .logs:
            LogView()
        }
    }

    // MARK: - Keyboard Shortcuts

    @ViewBuilder
    private var keyboardShortcuts: some View {
        Group {
            Button("") { selectedTab = .dashboard }
                .keyboardShortcut("1", modifiers: .command)
                .hidden()

            Button("") { selectedTab = .sync }
                .keyboardShortcut("2", modifiers: .command)
                .hidden()

            Button("") { selectedTab = .conflicts }
                .keyboardShortcut("3", modifiers: .command)
                .hidden()

            Button("") { selectedTab = .disks }
                .keyboardShortcut("4", modifiers: .command)
                .hidden()

            Button("") { selectedTab = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .hidden()
        }
    }
}

// MARK: - Navigation Badge

struct NavigationBadge: Equatable {
    let text: String
    let color: Color
}

// MARK: - Navigation Item View

struct NavigationItemView: View {
    let tab: MainView.MainTab
    let isSelected: Bool
    let badge: NavigationBadge?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tab.icon)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 20)

            Text(tab.title)
                .font(.body)
                .fontWeight(isSelected ? .medium : .regular)

            Spacer()

            if let badge = badge {
                Text(badge.text)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badge.color.opacity(0.2))
                    .foregroundColor(badge.color)
                    .cornerRadius(9)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Sidebar Header View

struct SidebarHeaderView: View {
    @ObservedObject var stateManager: StateManager

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            StatusIndicatorView(
                icon: stateManager.syncStatus.icon,
                color: stateManager.syncStatus.color,
                isAnimating: stateManager.isSyncing
            )
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("DMSA")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(stateManager.syncStatus.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Status Indicator View

struct StatusIndicatorView: View {
    let icon: String
    let color: Color
    let isAnimating: Bool

    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))

            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(color)
                .rotationEffect(.degrees(isAnimating ? rotation : 0))
        }
        .onAppear {
            if isAnimating {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
        .onChange(of: isAnimating) { newValue in
            if newValue {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else {
                rotation = 0
            }
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
        newWindow.setContentSize(NSSize(width: 900, height: 600))
        newWindow.minSize = NSSize(width: 720, height: 480)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showTab(_ tab: MainView.MainTab) {
        showWindow()
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
            .frame(width: 900, height: 600)
    }
}
#endif
