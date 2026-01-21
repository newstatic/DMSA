import SwiftUI

/// Setup wizard main view
struct WizardView: View {
    @ObservedObject var configManager: ConfigManager
    let onComplete: () -> Void

    @State private var currentStep: WizardStep = .welcome
    @State private var selectedDisks: [DiskConfig] = []
    @State private var selectedDirectories: [WizardDirectory] = []
    @State private var createSymlinks: Bool = true
    @State private var autoSync: Bool = true
    @State private var launchAtLogin: Bool = true
    @State private var syncNow: Bool = false

    enum WizardStep: Int, CaseIterable {
        case welcome = 1
        case disks = 2
        case directories = 3
        case permissions = 4
        case complete = 5

        var title: String {
            switch self {
            case .welcome: return L10n.Wizard.Welcome.title
            case .disks: return L10n.Wizard.Disks.title
            case .directories: return L10n.Wizard.Directories.title
            case .permissions: return L10n.Wizard.Permissions.title
            case .complete: return L10n.Wizard.Complete.title
            }
        }
    }

    struct WizardDirectory: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let path: String
        var isSelected: Bool
        var size: Int64?

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: WizardDirectory, rhs: WizardDirectory) -> Bool {
            lhs.id == rhs.id
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            stepIndicator

            Divider()

            // Content
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStepView(onNext: { currentStep = .disks })
                case .disks:
                    DiskStepView(
                        selectedDisks: $selectedDisks,
                        onBack: { currentStep = .welcome },
                        onNext: { currentStep = .directories }
                    )
                case .directories:
                    DirectoryStepView(
                        selectedDisks: selectedDisks,
                        selectedDirectories: $selectedDirectories,
                        createSymlinks: $createSymlinks,
                        autoSync: $autoSync,
                        onBack: { currentStep = .disks },
                        onNext: { currentStep = .permissions }
                    )
                case .permissions:
                    PermissionStepView(
                        onBack: { currentStep = .directories },
                        onNext: { currentStep = .complete }
                    )
                case .complete:
                    CompleteStepView(
                        selectedDisks: selectedDisks,
                        selectedDirectories: selectedDirectories,
                        createSymlinks: createSymlinks,
                        autoSync: autoSync,
                        launchAtLogin: $launchAtLogin,
                        syncNow: $syncNow,
                        onComplete: completeWizard
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 450)
    }

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(WizardStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 8) {
                    // Step number
                    ZStack {
                        Circle()
                            .fill(stepColor(for: step))
                            .frame(width: 24, height: 24)

                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        } else {
                            Text("\(step.rawValue)")
                                .font(.caption.bold())
                                .foregroundColor(step == currentStep ? .white : .secondary)
                        }
                    }

                    // Step title (only show for current and completed)
                    if step.rawValue <= currentStep.rawValue {
                        Text(stepTitle(for: step))
                            .font(.caption)
                            .foregroundColor(step == currentStep ? .primary : .secondary)
                    }
                }

                // Connector line
                if step.rawValue < WizardStep.allCases.count {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.accentColor : Color(.separatorColor))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func stepColor(for step: WizardStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .accentColor
        } else if step == currentStep {
            return .accentColor
        } else {
            return Color(.separatorColor)
        }
    }

    private func stepTitle(for step: WizardStep) -> String {
        switch step {
        case .welcome: return "Welcome".localized
        case .disks: return L10n.Settings.disks
        case .directories: return "Directories".localized
        case .permissions: return "Permissions".localized
        case .complete: return L10n.Common.done
        }
    }

    private func completeWizard() {
        // Save configuration
        for disk in selectedDisks {
            configManager.config.disks.append(disk)
        }

        for dir in selectedDirectories.filter({ $0.isSelected }) {
            guard let disk = selectedDisks.first else { continue }
            let syncPair = SyncPairConfig(
                id: UUID().uuidString,
                diskId: disk.id,
                localPath: dir.path,
                externalRelativePath: dir.name,
                direction: .localToExternal,
                createSymlink: createSymlinks,
                enabled: true
            )
            configManager.config.syncPairs.append(syncPair)
        }

        configManager.config.general.launchAtLogin = launchAtLogin
        configManager.saveConfig()

        onComplete()
    }
}

/// Welcome step
struct WelcomeStepView: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            // Title
            Text(L10n.Wizard.Welcome.title)
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(L10n.Wizard.Welcome.subtitle)
                .font(.title3)
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 40)

            // Description
            Text(L10n.Wizard.Welcome.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Features
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "externaldrive.connected.to.line.below", text: L10n.Wizard.Welcome.feature1)
                FeatureRow(icon: "folder.badge.gearshape", text: L10n.Wizard.Welcome.feature2)
                FeatureRow(icon: "arrow.triangle.2.circlepath", text: L10n.Wizard.Welcome.feature3)
                FeatureRow(icon: "icloud.and.arrow.down", text: L10n.Wizard.Welcome.feature4)
            }
            .padding(.horizontal, 60)

            Spacer()

            // Next button
            Button(action: onNext) {
                HStack {
                    Text(L10n.Wizard.Welcome.startSetup)
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
    }
}

/// Feature row for welcome screen
private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.body)
        }
    }
}

/// Disk selection step
struct DiskStepView: View {
    @Binding var selectedDisks: [DiskConfig]
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var detectedVolumes: [URL] = []
    @State private var showManualAdd: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text(L10n.Wizard.Disks.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(L10n.Wizard.Disks.subtitle)
                .font(.body)
                .foregroundColor(.secondary)

            // Detected disks
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Wizard.Disks.detected)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(detectedVolumes, id: \.path) { volume in
                            DiskSelectionRow(
                                name: volume.lastPathComponent,
                                path: volume.path,
                                isSelected: selectedDisks.contains { $0.mountPath == volume.path },
                                isSystemDisk: volume.lastPathComponent == "Macintosh HD",
                                onToggle: { toggleDisk(volume) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
            .padding(.horizontal, 40)

            // Manual add
            HStack {
                Text(L10n.Wizard.Disks.notFound)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(L10n.Wizard.Disks.addManually) {
                    showManualAdd = true
                }
                .buttonStyle(.link)
            }

            Text(L10n.Wizard.Disks.hint)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Navigation
            HStack {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text(L10n.Common.back)
                    }
                }

                Spacer()

                Button(action: onNext) {
                    HStack {
                        Text(L10n.Common.next)
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDisks.isEmpty)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
        .onAppear {
            detectVolumes()
        }
        .sheet(isPresented: $showManualAdd) {
            ManualDiskAddSheet(onAdd: { disk in
                selectedDisks.append(disk)
            })
        }
    }

    private func detectVolumes() {
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: volumesURL,
                includingPropertiesForKeys: [.isVolumeKey],
                options: [.skipsHiddenFiles]
            )
            detectedVolumes = contents
        } catch {
            detectedVolumes = []
        }
    }

    private func toggleDisk(_ volume: URL) {
        if let index = selectedDisks.firstIndex(where: { $0.mountPath == volume.path }) {
            selectedDisks.remove(at: index)
        } else {
            let disk = DiskConfig(name: volume.lastPathComponent, mountPath: volume.path)
            selectedDisks.append(disk)
        }
    }
}

/// Disk selection row
private struct DiskSelectionRow: View {
    let name: String
    let path: String
    let isSelected: Bool
    let isSystemDisk: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .disabled(isSystemDisk)

            Image(systemName: "externaldrive.fill")
                .foregroundColor(isSystemDisk ? .secondary : .accentColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.body)

                    if isSystemDisk {
                        Text(L10n.Wizard.Disks.systemDisk)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text(path)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
        .opacity(isSystemDisk ? 0.6 : 1)
    }
}

/// Manual disk add sheet
private struct ManualDiskAddSheet: View {
    let onAdd: (DiskConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var path: String = "/Volumes/"

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.Wizard.Disks.addManually)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                SettingRow(title: L10n.Settings.Disks.name) {
                    TextField("BACKUP", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }

                SettingRow(title: L10n.Settings.Disks.mountPath) {
                    HStack {
                        TextField("/Volumes/BACKUP", text: $path)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)

                        Button(L10n.Common.browse) {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.directoryURL = URL(fileURLWithPath: "/Volumes")
                            if panel.runModal() == .OK, let url = panel.url {
                                path = url.path
                                if name.isEmpty {
                                    name = url.lastPathComponent
                                }
                            }
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Button(L10n.Common.cancel) {
                    dismiss()
                }

                Spacer()

                Button(L10n.Common.add) {
                    let disk = DiskConfig(name: name, mountPath: path)
                    onAdd(disk)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || path.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 250)
    }
}

/// Directory selection step
struct DirectoryStepView: View {
    let selectedDisks: [DiskConfig]
    @Binding var selectedDirectories: [WizardView.WizardDirectory]
    @Binding var createSymlinks: Bool
    @Binding var autoSync: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    private var diskName: String {
        selectedDisks.first?.name ?? "BACKUP"
    }

    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text(L10n.Wizard.Directories.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(L10n.Wizard.Directories.subtitle(diskName))
                .font(.body)
                .foregroundColor(.secondary)

            // Recommended directories
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Wizard.Directories.recommended)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($selectedDirectories) { $dir in
                            DirectorySelectionRow(
                                directory: $dir
                            )
                        }
                    }
                }
                .frame(maxHeight: 180)

                Button(L10n.Wizard.Directories.addCustom) {
                    addCustomDirectory()
                }
                .buttonStyle(.link)
            }
            .padding(.horizontal, 40)

            // Options
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Wizard.Directories.options)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                CheckboxRow(
                    title: L10n.Wizard.Directories.createSymlink,
                    isChecked: $createSymlinks
                )

                CheckboxRow(
                    title: L10n.Wizard.Directories.autoSync,
                    isChecked: $autoSync
                )
            }
            .padding(.horizontal, 40)

            Spacer()

            // Navigation
            HStack {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text(L10n.Common.back)
                    }
                }

                Spacer()

                Button(action: onNext) {
                    HStack {
                        Text(L10n.Common.next)
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!selectedDirectories.contains { $0.isSelected })
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
        .onAppear {
            if selectedDirectories.isEmpty {
                loadDefaultDirectories()
            }
        }
    }

    private func loadDefaultDirectories() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser

        let defaults = [
            ("Downloads", homeDir.appendingPathComponent("Downloads")),
            ("Documents", homeDir.appendingPathComponent("Documents")),
            ("Desktop", homeDir.appendingPathComponent("Desktop"))
        ]

        selectedDirectories = defaults.map { name, url in
            let size = directorySize(at: url)
            return WizardView.WizardDirectory(
                name: name,
                path: "~/\(name)",
                isSelected: name == "Downloads",
                size: size
            )
        }
    }

    private func directorySize(at url: URL) -> Int64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return attrs[.size] as? Int64
        } catch {
            return nil
        }
    }

    private func addCustomDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url {
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            let path: String
            if url.path.hasPrefix(homePath) {
                path = "~" + url.path.dropFirst(homePath.count)
            } else {
                path = url.path
            }

            let dir = WizardView.WizardDirectory(
                name: url.lastPathComponent,
                path: path,
                isSelected: true,
                size: directorySize(at: url)
            )
            selectedDirectories.append(dir)
        }
    }
}

/// Directory selection row
private struct DirectorySelectionRow: View {
    @Binding var directory: WizardView.WizardDirectory

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $directory.isSelected)
                .labelsHidden()

            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(directory.name)
                    .font(.body)

                HStack {
                    Text(directory.path)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let size = directory.size {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(L10n.Wizard.Directories.currentSize(size.formattedBytes))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}

/// Permission step
struct PermissionStepView: View {
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var fullDiskAccessGranted: Bool = false
    @State private var notificationGranted: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text(L10n.Wizard.Permissions.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(L10n.Wizard.Permissions.subtitle)
                .font(.body)
                .foregroundColor(.secondary)

            // Permission cards
            VStack(spacing: 12) {
                PermissionCard(
                    icon: "lock.shield",
                    title: L10n.Wizard.Permissions.fullDiskAccess,
                    description: L10n.Wizard.Permissions.fullDiskAccessDesc,
                    isGranted: fullDiskAccessGranted,
                    onAuthorize: openFullDiskAccessSettings
                )

                PermissionCard(
                    icon: "bell.badge",
                    title: L10n.Wizard.Permissions.notifications,
                    description: L10n.Wizard.Permissions.notificationsDesc,
                    isGranted: notificationGranted,
                    onAuthorize: requestNotificationPermission
                )
            }
            .padding(.horizontal, 40)

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Wizard.Permissions.instructions)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(L10n.Wizard.Permissions.instruction1)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(L10n.Wizard.Permissions.instruction2)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(L10n.Wizard.Permissions.instruction3)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)

            Text(L10n.Wizard.Permissions.privacy)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            Spacer()

            // Navigation
            HStack {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text(L10n.Common.back)
                    }
                }

                Spacer()

                Button(action: onNext) {
                    HStack {
                        Text(L10n.Common.next)
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .padding(.top, 24)
        .onAppear {
            checkPermissions()
        }
    }

    private func checkPermissions() {
        // Check notification permission
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationGranted = settings.authorizationStatus == .authorized
            }
        }

        // Full disk access check would need to try accessing a protected directory
        // This is a simplified check
        fullDiskAccessGranted = FileManager.default.isReadableFile(
            atPath: NSHomeDirectory() + "/Library/Mail"
        )
    }

    private func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                notificationGranted = granted
            }
        }
    }
}

/// Permission card
private struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let onAuthorize: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isGranted ? .green : .orange)
                    Text(isGranted ? L10n.Wizard.Permissions.granted : L10n.Wizard.Permissions.notGranted)
                        .font(.caption)
                        .foregroundColor(isGranted ? .green : .orange)
                }
            }

            Spacer()

            if !isGranted {
                Button(L10n.Wizard.Permissions.authorize) {
                    onAuthorize()
                }
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

import UserNotifications

/// Complete step
struct CompleteStepView: View {
    let selectedDisks: [DiskConfig]
    let selectedDirectories: [WizardView.WizardDirectory]
    let createSymlinks: Bool
    let autoSync: Bool
    @Binding var launchAtLogin: Bool
    @Binding var syncNow: Bool
    let onComplete: () -> Void

    private var diskName: String {
        selectedDisks.first?.name ?? "BACKUP"
    }

    private var syncDirs: [WizardView.WizardDirectory] {
        selectedDirectories.filter { $0.isSelected }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text(L10n.Wizard.Complete.title)
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(L10n.Wizard.Complete.subtitle)
                .font(.title3)
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 60)

            // Configuration summary
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Wizard.Complete.yourConfig)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Wizard.Complete.disk(diskName))
                        .font(.body)

                    ForEach(syncDirs) { dir in
                        Text(L10n.Wizard.Complete.syncDir(from: dir.path, to: "\(diskName)/\(dir.name)"))
                            .font(.body)
                    }

                    Text(L10n.Wizard.Complete.autoSync(autoSync ? L10n.Common.enabled : L10n.Common.disabled))
                        .font(.body)

                    Text(L10n.Wizard.Complete.symlink(createSymlinks ? L10n.Common.enabled : L10n.Common.disabled))
                        .font(.body)
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 60)

            Divider()
                .padding(.horizontal, 60)

            // Next steps
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Wizard.Complete.nextSteps)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    Text("• " + L10n.Wizard.Complete.step1)
                    Text("• " + L10n.Wizard.Complete.step2(diskName))
                    Text("• " + L10n.Wizard.Complete.step3)
                }
                .font(.body)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 60)

            // Options
            VStack(alignment: .leading, spacing: 8) {
                CheckboxRow(
                    title: L10n.Wizard.Complete.launchAtLogin,
                    isChecked: $launchAtLogin
                )

                CheckboxRow(
                    title: L10n.Wizard.Complete.syncNow,
                    isChecked: $syncNow
                )
            }
            .padding(.horizontal, 60)

            Spacer()

            // Complete button
            Button(action: onComplete) {
                Text(L10n.Common.done)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Window Controller

class WizardWindowController {
    private var window: NSWindow?
    private let configManager: ConfigManager
    private let onComplete: () -> Void

    init(configManager: ConfigManager, onComplete: @escaping () -> Void) {
        self.configManager = configManager
        self.onComplete = onComplete
    }

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let wizardView = WizardView(
            configManager: configManager,
            onComplete: { [weak self] in
                self?.closeWindow()
                self?.onComplete()
            }
        )

        let hostingController = NSHostingController(rootView: wizardView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = L10n.App.name
        newWindow.styleMask = [.titled, .closable]
        newWindow.setContentSize(NSSize(width: 600, height: 450))
        newWindow.center()
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
struct WizardView_Previews: PreviewProvider {
    static var previews: some View {
        WizardView(
            configManager: ConfigManager.shared,
            onComplete: { }
        )
    }
}
#endif
