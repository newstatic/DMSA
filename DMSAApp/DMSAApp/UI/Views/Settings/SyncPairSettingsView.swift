import SwiftUI

/// Sync pair management settings view
struct SyncPairSettingsView: View {
    @Binding var config: AppConfig
    @State private var selectedPairId: String?
    @State private var showAddPairSheet: Bool = false

    private var selectedPair: SyncPairConfig? {
        config.syncPairs.first { $0.id == selectedPairId }
    }

    private var selectedPairIndex: Int? {
        config.syncPairs.firstIndex { $0.id == selectedPairId }
    }

    var body: some View {
        SettingsContentView(title: L10n.Settings.SyncPairs.title) {
            // Sync pair list section
            SectionHeader(
                title: L10n.Settings.SyncPairs.configured,
                actionTitle: L10n.Common.add,
                action: { showAddPairSheet = true }
            )

            // Sync pair list
            VStack(spacing: 8) {
                if config.syncPairs.isEmpty {
                    emptyStateView
                } else {
                    ForEach(config.syncPairs) { pair in
                        SyncPairRow(
                            pair: pair,
                            disk: diskFor(pair),
                            isSelected: pair.id == selectedPairId,
                            onSelect: { selectedPairId = pair.id }
                        )
                    }
                }
            }

            // Sync pair details section
            if let pair = selectedPair, let index = selectedPairIndex {
                SectionDivider(title: L10n.Settings.SyncPairs.details)

                SyncPairDetailEditor(
                    pair: Binding(
                        get: { config.syncPairs[index] },
                        set: { config.syncPairs[index] = $0 }
                    ),
                    disks: config.disks,
                    onDelete: {
                        deletePair(at: index)
                    }
                )
            }
        }
        .sheet(isPresented: $showAddPairSheet) {
            AddSyncPairSheet(
                disks: config.disks,
                onAdd: { newPair in
                    config.syncPairs.append(newPair)
                    selectedPairId = newPair.id
                }
            )
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text(L10n.Menu.noDisksConfigured)
                .font(.headline)
                .foregroundColor(.secondary)

            if config.disks.isEmpty {
                Text("Please add a disk first")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button(L10n.Settings.SyncPairs.add) {
                    showAddPairSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func diskFor(_ pair: SyncPairConfig) -> DiskConfig? {
        config.disks.first { $0.id == pair.diskId }
    }

    private func deletePair(at index: Int) {
        let pairId = config.syncPairs[index].id
        config.syncPairs.remove(at: index)

        if selectedPairId == pairId {
            selectedPairId = config.syncPairs.first?.id
        }
    }
}

/// A row displaying a sync pair
struct SyncPairRow: View {
    let pair: SyncPairConfig
    let disk: DiskConfig?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Toggle("", isOn: .constant(pair.enabled))
                .labelsHidden()
                .toggleStyle(.checkbox)

            // Icon
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)

            // Path info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(pair.localPath)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: pair.direction.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(disk?.name ?? "?")/\(pair.externalRelativePath)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.body)

                HStack(spacing: 8) {
                    Text(pair.direction.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if pair.createSymlink {
                        Label("Symlink", systemImage: "link")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let disk = disk, !disk.isConnected {
                        Text("(\(L10n.Disk.disconnected))")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // Status indicator
            if pair.enabled {
                Circle()
                    .fill(disk?.isConnected == true ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

/// Sync pair detail editor
struct SyncPairDetailEditor: View {
    @Binding var pair: SyncPairConfig
    let disks: [DiskConfig]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Local path
            SettingRow(title: L10n.Settings.SyncPairs.localPath) {
                HStack(spacing: 8) {
                    TextField("", text: $pair.localPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                    Button(L10n.Common.browse) {
                        selectLocalPath()
                    }
                }
            }

            // Target disk
            PickerRow(
                title: L10n.Settings.SyncPairs.targetDisk,
                selection: $pair.diskId
            ) {
                ForEach(disks) { disk in
                    Text(disk.name).tag(disk.id)
                }
            }

            // External path
            SettingRow(title: L10n.Settings.SyncPairs.externalPath) {
                TextField("", text: $pair.externalRelativePath)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            // Direction
            PickerRow(
                title: L10n.Settings.SyncPairs.direction,
                selection: $pair.direction
            ) {
                ForEach(SyncDirection.allCases, id: \.rawValue) { direction in
                    Text(direction.displayName).tag(direction)
                }
            }

            Divider()

            // Options
            CheckboxRow(
                title: L10n.Settings.SyncPairs.enable,
                isChecked: $pair.enabled
            )

            CheckboxRow(
                title: L10n.Settings.SyncPairs.createSymlink,
                description: L10n.Settings.SyncPairs.symlinkHint,
                isChecked: $pair.createSymlink
            )

            // Exclude patterns
            SectionDivider(title: L10n.Settings.SyncPairs.excludePatterns)

            PatternListEditor(
                patterns: $pair.excludePatterns,
                placeholder: "node_modules"
            )

            // Actions
            HStack {
                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Text(L10n.Settings.SyncPairs.remove)
                }
            }
            .padding(.top, 8)
        }
    }

    private func selectLocalPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        // Start from home directory
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url {
            // Convert to tilde path if in home directory
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            if url.path.hasPrefix(homePath) {
                pair.localPath = "~" + url.path.dropFirst(homePath.count)
            } else {
                pair.localPath = url.path
            }
        }
    }
}

/// Sheet for adding a new sync pair
struct AddSyncPairSheet: View {
    let disks: [DiskConfig]
    let onAdd: (SyncPairConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var localPath: String = "~/Downloads"
    @State private var selectedDiskId: String = ""
    @State private var externalPath: String = "Downloads"
    @State private var direction: SyncDirection = .localToExternal
    @State private var createSymlink: Bool = true
    @State private var enabled: Bool = true

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.Settings.SyncPairs.add)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                // Local path
                SettingRow(title: L10n.Settings.SyncPairs.localPath) {
                    HStack {
                        TextField("~/Downloads", text: $localPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)

                        Button(L10n.Common.browse) {
                            browseForLocalPath()
                        }
                    }
                }

                // Target disk
                PickerRow(
                    title: L10n.Settings.SyncPairs.targetDisk,
                    selection: $selectedDiskId
                ) {
                    ForEach(disks) { disk in
                        Text(disk.name).tag(disk.id)
                    }
                }

                // External path
                SettingRow(title: L10n.Settings.SyncPairs.externalPath) {
                    TextField("Downloads", text: $externalPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }

                // Direction
                PickerRow(
                    title: L10n.Settings.SyncPairs.direction,
                    selection: $direction
                ) {
                    ForEach(SyncDirection.allCases, id: \.rawValue) { dir in
                        Text(dir.displayName).tag(dir)
                    }
                }

                Divider()

                CheckboxRow(
                    title: L10n.Settings.SyncPairs.createSymlink,
                    description: L10n.Settings.SyncPairs.symlinkHint,
                    isChecked: $createSymlink
                )

                CheckboxRow(
                    title: L10n.Settings.SyncPairs.enable,
                    isChecked: $enabled
                )
            }

            Spacer()

            // Actions
            HStack {
                Button(L10n.Common.cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(L10n.Common.add) {
                    let newPair = SyncPairConfig(
                        id: UUID().uuidString,
                        diskId: selectedDiskId,
                        localPath: localPath,
                        externalRelativePath: externalPath,
                        direction: direction,
                        createSymlink: createSymlink,
                        enabled: enabled
                    )
                    onAdd(newPair)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(localPath.isEmpty || selectedDiskId.isEmpty || externalPath.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 450, height: 450)
        .onAppear {
            if selectedDiskId.isEmpty, let firstDisk = disks.first {
                selectedDiskId = firstDisk.id
            }
        }
    }

    private func browseForLocalPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url {
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            if url.path.hasPrefix(homePath) {
                localPath = "~" + url.path.dropFirst(homePath.count)
            } else {
                localPath = url.path
            }

            // Auto-fill external path
            if externalPath.isEmpty || externalPath == "Downloads" {
                externalPath = url.lastPathComponent
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
struct SyncPairSettingsView_Previews: PreviewProvider {
    static var config: AppConfig = {
        var config = AppConfig()
        config.disks = [
            DiskConfig(name: "BACKUP", mountPath: "/Volumes/BACKUP"),
            DiskConfig(name: "PORTABLE", mountPath: "/Volumes/PORTABLE")
        ]
        config.syncPairs = [
            SyncPairConfig(diskId: "1", localPath: "~/Downloads", externalRelativePath: "Downloads"),
            SyncPairConfig(diskId: "1", localPath: "~/Documents", externalRelativePath: "Documents")
        ]
        return config
    }()

    static var previews: some View {
        SyncPairSettingsView(config: .constant(config))
        .frame(width: 450, height: 600)
    }
}
#endif
