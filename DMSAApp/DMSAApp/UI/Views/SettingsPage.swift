import SwiftUI
import UserNotifications
import ServiceManagement

// MARK: - Settings Page

/// Settings page - unified entry point for all settings
struct SettingsPage: View {
    @Binding var config: AppConfig
    let configManager: ConfigManager

    @State private var selectedSection: SettingsSection = .general

    // MARK: - Settings Sections

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general      // General
        case sync         // Sync
        case filters      // Filters
        case notifications // Notifications
        case vfs          // Virtual File System
        case advanced     // Advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "settings.section.general".localized
            case .sync: return "settings.section.sync".localized
            case .filters: return "settings.section.filters".localized
            case .notifications: return "settings.section.notifications".localized
            case .vfs: return "settings.section.vfs".localized
            case .advanced: return "settings.section.advanced".localized
            }
        }

        var icon: String {
            switch self {
            case .general: return "gear"
            case .sync: return "arrow.triangle.2.circlepath"
            case .filters: return "line.3.horizontal.decrease.circle"
            case .notifications: return "bell"
            case .vfs: return "externaldrive.connected.to.line.below"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            // Settings navigation
            settingsNavigation
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)

            // Settings content
            settingsContent
                .frame(minWidth: 450)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Settings Navigation

    private var settingsNavigation: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("settings.title".localized)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            // Section list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(SettingsSection.allCases) { section in
                        SettingsSectionRow(
                            section: section,
                            isSelected: selectedSection == section,
                            onSelect: { selectedSection = section }
                        )
                    }
                }
                .padding(12)
            }

            Spacer()

            // Version info
            VStack(spacing: 4) {
                Text("DMSA")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 16)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Settings Content

    @ViewBuilder
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section title
                Text(selectedSection.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                // Section content
                switch selectedSection {
                case .general:
                    GeneralSettingsContent(config: $config)
                case .sync:
                    SyncSettingsContent(config: $config)
                case .filters:
                    FilterSettingsContent(config: $config)
                case .notifications:
                    NotificationSettingsContent(config: $config)
                case .vfs:
                    VFSSettingsContent(config: $config)
                case .advanced:
                    AdvancedSettingsContent(config: $config, configManager: configManager)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Settings Section Row

struct SettingsSectionRow: View {
    let section: SettingsPage.SettingsSection
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.icon)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 24)

            Text(section.title)
                .font(.body)
                .fontWeight(isSelected ? .medium : .regular)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - General Settings Content

struct GeneralSettingsContent: View {
    @Binding var config: AppConfig
    @ObservedObject private var localizationManager = LocalizationManager.shared

    private let launchAtLoginManager = LaunchAtLoginManager.shared
    private let appearanceManager = AppearanceManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Startup
            SettingsCard(title: "settings.general.startup".localized) {
                VStack(alignment: .leading, spacing: 8) {
                    CheckboxRow(
                        title: L10n.Settings.General.launchAtLogin,
                        isChecked: Binding(
                            get: { config.general.launchAtLogin },
                            set: { newValue in
                                config.general.launchAtLogin = newValue
                                launchAtLoginManager.setEnabled(newValue)
                            }
                        )
                    )

                    CheckboxRow(
                        title: L10n.Settings.General.showInDock,
                        isChecked: Binding(
                            get: { config.general.showInDock },
                            set: { newValue in
                                config.general.showInDock = newValue
                                appearanceManager.setShowInDock(newValue)
                            }
                        )
                    )

                    CheckboxRow(
                        title: L10n.Settings.General.checkForUpdates,
                        isChecked: $config.general.checkForUpdates
                    )
                }
            }

            // Language
            SettingsCard(title: "settings.general.language".localized) {
                Picker("", selection: $config.general.language) {
                    Text(L10n.Settings.General.languageSystem).tag("system")
                    Text(L10n.Settings.General.languageEn).tag("en")
                    Text(L10n.Settings.General.languageZhHans).tag("zh-Hans")
                    Text(L10n.Settings.General.languageZhHant).tag("zh-Hant")
                }
                .pickerStyle(.segmented)
                .onChange(of: config.general.language) { newLanguage in
                    localizationManager.setLanguage(newLanguage)
                }
            }

            // Menu bar style
            SettingsCard(title: "settings.general.menuBarStyle".localized) {
                Picker("", selection: $config.ui.menuBarStyle) {
                    Text(L10n.Settings.General.menuBarIcon).tag(UIConfig.MenuBarStyle.icon)
                    Text(L10n.Settings.General.menuBarIconText).tag(UIConfig.MenuBarStyle.iconText)
                    Text(L10n.Settings.General.menuBarIconProgress).tag(UIConfig.MenuBarStyle.text)
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

// MARK: - Sync Settings Content

struct SyncSettingsContent: View {
    @Binding var config: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Sync behavior
            SettingsCard(title: "settings.sync.behavior".localized) {
                VStack(alignment: .leading, spacing: 12) {
                    NumberInputRow(
                        title: L10n.Settings.Advanced.debounceDelay,
                        description: L10n.Settings.Advanced.debounceDelayHint,
                        value: $config.monitoring.debounceSeconds,
                        range: 1...60,
                        unit: "s"
                    )

                    NumberInputRow(
                        title: L10n.Settings.Advanced.batchSize,
                        value: $config.monitoring.batchSize,
                        range: 10...1000,
                        unit: L10n.Settings.Advanced.batchSizeUnit
                    )
                }
            }

            // Sync options
            SettingsCard(title: "settings.sync.options".localized) {
                VStack(alignment: .leading, spacing: 8) {
                    CheckboxRow(
                        title: L10n.Settings.Advanced.enableChecksum,
                        description: L10n.Settings.Advanced.enableChecksumHint,
                        isChecked: $config.syncEngine.enableChecksum
                    )

                    if config.syncEngine.enableChecksum {
                        HStack {
                            Text(L10n.Settings.Advanced.checksumAlgorithm)
                                .foregroundColor(.secondary)
                            Picker("", selection: $config.syncEngine.checksumAlgorithm) {
                                ForEach(SyncEngineConfig.ChecksumAlgorithm.allCases, id: \.self) { algo in
                                    Text(algo.displayName).tag(algo)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                        .padding(.leading, 24)
                    }

                    CheckboxRow(
                        title: L10n.Settings.Advanced.verifyAfterCopy,
                        description: L10n.Settings.Advanced.verifyAfterCopyHint,
                        isChecked: $config.syncEngine.verifyAfterCopy
                    )

                    CheckboxRow(
                        title: L10n.Settings.Advanced.enableDelete,
                        description: L10n.Settings.Advanced.enableDeleteHint,
                        isChecked: $config.syncEngine.enableDelete
                    )

                    CheckboxRow(
                        title: L10n.Settings.Advanced.enablePauseResume,
                        description: L10n.Settings.Advanced.enablePauseResumeHint,
                        isChecked: $config.syncEngine.enablePauseResume
                    )
                }
            }

            // Conflict resolution
            SettingsCard(title: "settings.sync.conflict".localized) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.Settings.Advanced.conflictStrategy)
                        Spacer()
                        Picker("", selection: $config.syncEngine.conflictStrategy) {
                            ForEach(SyncEngineConfig.SyncConflictStrategy.allCases, id: \.self) { strategy in
                                Text(strategy.displayName).tag(strategy)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    CheckboxRow(
                        title: L10n.Settings.Advanced.autoResolveConflicts,
                        description: L10n.Settings.Advanced.autoResolveConflictsHint,
                        isChecked: $config.syncEngine.autoResolveConflicts
                    )

                    HStack {
                        Text(L10n.Settings.Advanced.backupSuffix)
                        Spacer()
                        TextField("_backup", text: $config.syncEngine.backupSuffix)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                }
            }
        }
    }
}

// MARK: - Filter Settings Content

struct FilterSettingsContent: View {
    @Binding var config: AppConfig

    @State private var selectedPreset: FilterPreset = .default

    enum FilterPreset: String, CaseIterable, Identifiable {
        case `default`, developer, media, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .default: return L10n.Settings.Filters.presetDefault
            case .developer: return L10n.Settings.Filters.presetDeveloper
            case .media: return L10n.Settings.Filters.presetMedia
            case .custom: return L10n.Settings.Filters.presetCustom
            }
        }

        var patterns: [String] {
            switch self {
            case .default:
                return [".DS_Store", ".Trash", "*.tmp", "*.temp", "Thumbs.db"]
            case .developer:
                return [".DS_Store", "node_modules", ".git", "build", "*.o", "__pycache__"]
            case .media, .custom:
                return []
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Presets
            SettingsCard(title: "settings.filters.presets".localized) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $selectedPreset) {
                        ForEach(FilterPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPreset) { newValue in
                        if newValue != .custom {
                            config.filters.excludePatterns = newValue.patterns
                        }
                    }

                    HStack {
                        Button(L10n.Common.export) { exportFilters() }
                        Button(L10n.Common.import) { importFilters() }
                        Spacer()
                    }
                }
            }

            // Exclude patterns
            SettingsCard(title: "settings.filters.excludePatterns".localized) {
                PatternListEditor(
                    patterns: $config.filters.excludePatterns,
                    placeholder: "*.tmp"
                )
            }

            // Size filters
            SettingsCard(title: "settings.filters.sizeFilters".localized) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        CheckboxRow(
                            title: L10n.Settings.Filters.maxSize,
                            isChecked: Binding(
                                get: { config.filters.maxFileSize != nil },
                                set: { enabled in
                                    config.filters.maxFileSize = enabled ? 1024 * 1024 * 1024 : nil
                                }
                            )
                        )

                        if config.filters.maxFileSize != nil {
                            Picker("", selection: Binding(
                                get: { config.filters.maxFileSize ?? 0 },
                                set: { config.filters.maxFileSize = $0 }
                            )) {
                                Text("100 MB").tag(Int64(100 * 1024 * 1024))
                                Text("1 GB").tag(Int64(1024 * 1024 * 1024))
                                Text("5 GB").tag(Int64(5 * 1024 * 1024 * 1024))
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                    }

                    CheckboxRow(
                        title: L10n.Settings.Filters.excludeHidden,
                        isChecked: $config.filters.excludeHidden
                    )
                }
            }
        }
        .onAppear { detectPreset() }
    }

    private func detectPreset() {
        if config.filters.excludePatterns == FilterPreset.default.patterns {
            selectedPreset = .default
        } else if config.filters.excludePatterns == FilterPreset.developer.patterns {
            selectedPreset = .developer
        } else {
            selectedPreset = .custom
        }
    }

    private func exportFilters() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "dmsa-filters.json"

        if panel.runModal() == .OK, let url = panel.url {
            try? JSONEncoder().encode(config.filters).write(to: url)
        }
    }

    private func importFilters() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url),
               let filters = try? JSONDecoder().decode(FilterConfig.self, from: data) {
                config.filters = filters
                detectPreset()
            }
        }
    }
}

// MARK: - Notification Settings Content

struct NotificationSettingsContent: View {
    @Binding var config: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Enable notifications
            SettingsCard(title: "settings.notifications.enable".localized) {
                Toggle(L10n.Settings.Notifications.enable, isOn: $config.notifications.enabled)
                    .toggleStyle(.switch)
            }

            if config.notifications.enabled {
                // Notification types
                SettingsCard(title: "settings.notifications.types".localized) {
                    VStack(alignment: .leading, spacing: 8) {
                        CheckboxRow(
                            title: L10n.Settings.Notifications.onDiskConnect,
                            isChecked: $config.notifications.showOnDiskConnect
                        )

                        CheckboxRow(
                            title: L10n.Settings.Notifications.onDiskDisconnect,
                            isChecked: $config.notifications.showOnDiskDisconnect
                        )

                        CheckboxRow(
                            title: L10n.Settings.Notifications.onSyncStart,
                            isChecked: $config.notifications.showOnSyncStart
                        )

                        CheckboxRow(
                            title: L10n.Settings.Notifications.onSyncComplete,
                            isChecked: $config.notifications.showOnSyncComplete
                        )

                        CheckboxRow(
                            title: L10n.Settings.Notifications.onSyncError,
                            isChecked: $config.notifications.showOnSyncError
                        )
                    }
                }

                // Sound
                SettingsCard(title: "settings.notifications.sound".localized) {
                    VStack(alignment: .leading, spacing: 8) {
                        CheckboxRow(
                            title: L10n.Settings.Notifications.playSound,
                            isChecked: $config.notifications.soundEnabled
                        )

                        HStack {
                            Spacer()
                            Button(L10n.Settings.Notifications.testNotification) {
                                sendTestNotification()
                            }
                        }
                    }
                }
            }
        }
    }

    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = L10n.App.name
        content.body = "settings.notifications.testMessage".localized
        if config.notifications.soundEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - VFS Settings Content

struct VFSSettingsContent: View {
    @Binding var config: AppConfig
    @StateObject private var viewModel = VFSSettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // macFUSE status
            SettingsCard(title: "macFUSE") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(viewModel.macFUSEStatusColor)
                                .frame(width: 8, height: 8)
                            Text(viewModel.macFUSEStatusText)
                                .fontWeight(.medium)
                        }

                        if let version = viewModel.macFUSEVersion {
                            Text("Version \(version)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if !viewModel.isMacFUSEInstalled {
                        Button("settings.vfs.downloadMacFUSE".localized) {
                            viewModel.openMacFUSEDownload()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            // Service status
            SettingsCard(title: "settings.vfs.service".localized) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(viewModel.helperStatusColor)
                                .frame(width: 8, height: 8)
                            Text(viewModel.helperStatusText)
                                .fontWeight(.medium)
                        }

                        if let version = viewModel.helperVersion {
                            Text("Version \(version)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if !viewModel.isHelperInstalled {
                        Button("settings.vfs.installService".localized) {
                            viewModel.installHelper()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("settings.vfs.reinstallService".localized) {
                            viewModel.reinstallHelper()
                        }
                    }
                }
            }

            // VFS mounts
            SettingsCard(title: "settings.vfs.mounts".localized) {
                if viewModel.mountedVFS.isEmpty {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("settings.vfs.noMounts".localized)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.mountedVFS, id: \.targetDir) { mount in
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(mount.targetDir)
                                        .fontWeight(.medium)
                                    Text("\(mount.localDir) + \(mount.externalDir)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .onAppear { viewModel.refresh() }
    }
}

// MARK: - Advanced Settings Content

struct AdvancedSettingsContent: View {
    @Binding var config: AppConfig
    let configManager: ConfigManager

    @StateObject private var permissionManager = PermissionManager.shared
    @State private var showResetConfirmation = false
    @State private var showClearAllConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Logging
            SettingsCard(title: "settings.advanced.logging".localized) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.Settings.Advanced.logLevel)
                        Spacer()
                        Picker("", selection: $config.logging.level) {
                            Text(L10n.Settings.Advanced.logLevelDebug).tag(LoggingConfig.LogLevel.debug)
                            Text(L10n.Settings.Advanced.logLevelInfo).tag(LoggingConfig.LogLevel.info)
                            Text(L10n.Settings.Advanced.logLevelWarning).tag(LoggingConfig.LogLevel.warn)
                            Text(L10n.Settings.Advanced.logLevelError).tag(LoggingConfig.LogLevel.error)
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }

                    NumberInputRow(
                        title: L10n.Settings.Advanced.logSize,
                        value: Binding(
                            get: { config.logging.maxFileSize / (1024 * 1024) },
                            set: { config.logging.maxFileSize = $0 * 1024 * 1024 }
                        ),
                        range: 1...100,
                        unit: "MB"
                    )

                    HStack {
                        Spacer()
                        Button(L10n.Settings.Advanced.openLogFolder) {
                            let logDir = (config.logging.logPath as NSString).expandingTildeInPath
                            NSWorkspace.shared.open(URL(fileURLWithPath: (logDir as NSString).deletingLastPathComponent))
                        }
                    }
                }
            }

            // Permissions
            SettingsCard(title: "settings.advanced.permissions".localized) {
                VStack(alignment: .leading, spacing: 12) {
                    PermissionStatusRow(
                        title: "settings.advanced.fullDiskAccess".localized,
                        isGranted: permissionManager.hasFullDiskAccess,
                        onAuthorize: { Task { await permissionManager.authorize(.fullDiskAccess) } }
                    )

                    PermissionStatusRow(
                        title: "settings.advanced.notificationPermission".localized,
                        isGranted: permissionManager.hasNotificationPermission,
                        onAuthorize: { Task { await permissionManager.authorize(.notifications) } }
                    )

                    HStack {
                        Spacer()
                        Button {
                            Task { await permissionManager.refreshPermissions() }
                        } label: {
                            Label("settings.advanced.refreshPermissions".localized, systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                    }
                }
            }
            .task { await permissionManager.checkAllPermissions() }

            // Data management
            SettingsCard(title: "settings.advanced.data".localized) {
                HStack(spacing: 12) {
                    Button(L10n.Settings.Advanced.exportConfig) { exportConfig() }
                    Button(L10n.Settings.Advanced.importConfig) { importConfig() }
                    Button(L10n.Settings.Advanced.resetAll) { showResetConfirmation = true }
                }
            }

            // Danger zone
            SettingsCard(title: "settings.advanced.danger".localized, color: .red.opacity(0.1)) {
                Button(role: .destructive) {
                    showClearAllConfirmation = true
                } label: {
                    Label(L10n.Settings.Advanced.clearAllData, systemImage: "exclamationmark.triangle.fill")
                }
            }
        }
        .alert(L10n.Settings.Advanced.resetAll, isPresented: $showResetConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) { }
            Button(L10n.Common.reset, role: .destructive) { resetSettings() }
        }
        .alert(L10n.Settings.Advanced.clearAllData, isPresented: $showClearAllConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) { }
            Button(L10n.Common.delete, role: .destructive) { clearAllData() }
        } message: {
            Text(L10n.Settings.Advanced.clearAllDataConfirm)
        }
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "dmsa-config.json"

        if panel.runModal() == .OK, let url = panel.url {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            try? encoder.encode(config).write(to: url)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url),
               let imported = try? JSONDecoder().decode(AppConfig.self, from: data) {
                config = imported
            }
        }
    }

    private func resetSettings() {
        config = AppConfig()
        configManager.saveConfig()
    }

    private func clearAllData() {
        config = AppConfig()
        try? FileManager.default.removeItem(atPath: Constants.Paths.database.path)
        try? FileManager.default.removeItem(atPath: Constants.Paths.logs.path)
        configManager.saveConfig()
    }
}

// MARK: - Settings Card

struct SettingsCard<Content: View>: View {
    let title: String
    var color: Color = Color(NSColor.controlBackgroundColor)
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color)
        .cornerRadius(8)
    }
}

// MARK: - Permission Status Row

struct PermissionStatusRow: View {
    let title: String
    let isGranted: Bool
    let onAuthorize: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)

                HStack(spacing: 4) {
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isGranted ? .green : .red)
                    Text(isGranted ? "common.granted".localized : "common.notGranted".localized)
                        .font(.caption)
                        .foregroundColor(isGranted ? .green : .red)
                }
            }

            Spacer()

            if !isGranted {
                Button("common.authorize".localized, action: onAuthorize)
            }
        }
    }
}

// MARK: - VFS Settings View Model

class VFSSettingsViewModel: ObservableObject {
    @Published var isMacFUSEInstalled = false
    @Published var macFUSEVersion: String?
    @Published var macFUSEStatusText = "Checking..."
    @Published var macFUSEStatusColor: Color = .secondary

    @Published var isHelperInstalled = false
    @Published var helperVersion: String?
    @Published var helperStatusText = "Checking..."
    @Published var helperStatusColor: Color = .secondary

    @Published var mountedVFS: [VFSMountInfo] = []

    private let serviceClient = ServiceClient.shared

    func refresh() {
        checkMacFUSE()
        checkService()
        checkMountedVFS()
    }

    // MARK: - macFUSE

    private func checkMacFUSE() {
        let availability = FUSEManager.shared.checkFUSEAvailability()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch availability {
            case .available(let version):
                self.isMacFUSEInstalled = true
                self.macFUSEVersion = version
                self.macFUSEStatusText = "Installed"
                self.macFUSEStatusColor = .green
            case .notInstalled, .frameworkMissing:
                self.isMacFUSEInstalled = false
                self.macFUSEVersion = nil
                self.macFUSEStatusText = "Not Installed"
                self.macFUSEStatusColor = .red
            case .versionTooOld(let current, _):
                self.isMacFUSEInstalled = true
                self.macFUSEVersion = current
                self.macFUSEStatusText = "Version Too Old"
                self.macFUSEStatusColor = .orange
            case .loadError(let error):
                self.isMacFUSEInstalled = false
                self.macFUSEVersion = nil
                self.macFUSEStatusText = "Load failed: \(error.localizedDescription)"
                self.macFUSEStatusColor = .red
            }
        }
    }

    func openMacFUSEDownload() {
        if let url = URL(string: "https://macfuse.github.io/") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Service (DMSAService)

    private func checkService() {
        Task {
            do {
                let isHealthy = try await serviceClient.healthCheck()
                let version = try? await serviceClient.getVersion()

                await MainActor.run {
                    self.isHelperInstalled = isHealthy
                    self.helperVersion = version
                    self.helperStatusText = isHealthy ? "Running" : "Not Responding"
                    self.helperStatusColor = isHealthy ? .green : .red
                }
            } catch {
                await MainActor.run {
                    self.isHelperInstalled = false
                    self.helperVersion = nil
                    self.helperStatusText = "Not Connected"
                    self.helperStatusColor = .red
                }
            }
        }
    }

    func installHelper() {
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.daemon(plistName: "com.ttttt.dmsa.service.plist")
                try service.register()
                checkService()
            } catch {
                Logger.shared.error("Failed to install service: \(error.localizedDescription)")
            }
        } else {
            Logger.shared.warn("macOS versions below 13.0 require manual service installation")
        }
    }

    func reinstallHelper() {
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.daemon(plistName: "com.ttttt.dmsa.service.plist")
                try service.unregister()
            } catch {
                Logger.shared.warn("Failed to uninstall service: \(error.localizedDescription)")
            }
        }
        installHelper()
    }

    @available(macOS 13.0, *)
    func uninstallHelper() {
        do {
            let service = SMAppService.daemon(plistName: "com.ttttt.dmsa.service.plist")
            try service.unregister()
            checkService()
        } catch {
            Logger.shared.error("Failed to uninstall service: \(error.localizedDescription)")
        }
    }

    // MARK: - VFS Mounts

    private func checkMountedVFS() {
        Task {
            do {
                let mounts = try await ServiceClient.shared.getVFSMounts()
                await MainActor.run {
                    self.mountedVFS = mounts.map { mount in
                        VFSMountInfo(
                            targetDir: mount.targetDir,
                            localDir: mount.localDir,
                            externalDir: mount.externalDir ?? ""
                        )
                    }
                }
            } catch {
                Logger.shared.error("Failed to get mount info: \(error)")
            }
        }
    }
}

// MARK: - VFS Mount Info

struct VFSMountInfo {
    let targetDir: String
    let localDir: String
    let externalDir: String
}

// MARK: - Previews

#if DEBUG
struct SettingsPage_Previews: PreviewProvider {
    static var previews: some View {
        SettingsPage(config: .constant(AppConfig()), configManager: ConfigManager.shared)
            .frame(width: 800, height: 600)
    }
}
#endif
