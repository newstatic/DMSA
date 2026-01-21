import SwiftUI

/// Disk management settings view
struct DiskSettingsView: View {
    @Binding var config: AppConfig
    @State private var selectedDiskId: String?
    @State private var showAddDiskSheet: Bool = false

    private var selectedDisk: DiskConfig? {
        config.disks.first { $0.id == selectedDiskId }
    }

    private var selectedDiskIndex: Int? {
        config.disks.firstIndex { $0.id == selectedDiskId }
    }

    var body: some View {
        SettingsContentView(title: L10n.Settings.Disks.title) {
            // Disk list section
            SectionHeader(
                title: L10n.Settings.Disks.configured,
                actionTitle: L10n.Common.add,
                action: { showAddDiskSheet = true }
            )

            // Disk list
            VStack(spacing: 8) {
                if config.disks.isEmpty {
                    emptyStateView
                } else {
                    ForEach(config.disks) { disk in
                        DiskCard(
                            disk: disk,
                            usedSpace: getDiskUsedSpace(disk),
                            totalSpace: getDiskTotalSpace(disk),
                            isSelected: disk.id == selectedDiskId,
                            onSelect: { selectedDiskId = disk.id }
                        )
                    }
                }
            }

            // Disk details section
            if let disk = selectedDisk, let index = selectedDiskIndex {
                SectionDivider(title: L10n.Settings.Disks.details)

                DiskDetailEditor(
                    disk: Binding(
                        get: { config.disks[index] },
                        set: { config.disks[index] = $0 }
                    ),
                    onDelete: {
                        deleteDisk(at: index)
                    }
                )
            }
        }
        .sheet(isPresented: $showAddDiskSheet) {
            AddDiskSheet(
                onAdd: { newDisk in
                    config.disks.append(newDisk)
                    selectedDiskId = newDisk.id
                },
                existingDiskNames: Set(config.disks.map { $0.name })
            )
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text(L10n.Menu.noDisksConfigured)
                .font(.headline)
                .foregroundColor(.secondary)

            Button(L10n.Settings.Disks.add) {
                showAddDiskSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func deleteDisk(at index: Int) {
        let diskId = config.disks[index].id
        config.disks.remove(at: index)

        // Also remove sync pairs referencing this disk
        config.syncPairs.removeAll { $0.diskId == diskId }

        // Clear selection if deleted
        if selectedDiskId == diskId {
            selectedDiskId = config.disks.first?.id
        }
    }

    private func getDiskUsedSpace(_ disk: DiskConfig) -> Int64? {
        guard disk.isConnected else { return nil }
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: disk.mountPath)
            let totalSize = (attrs[.systemSize] as? Int64) ?? 0
            let freeSize = (attrs[.systemFreeSize] as? Int64) ?? 0
            return totalSize - freeSize
        } catch {
            return nil
        }
    }

    private func getDiskTotalSpace(_ disk: DiskConfig) -> Int64? {
        guard disk.isConnected else { return nil }
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: disk.mountPath)
            return (attrs[.systemSize] as? Int64)
        } catch {
            return nil
        }
    }
}

/// Disk detail editor
struct DiskDetailEditor: View {
    @Binding var disk: DiskConfig
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name
            SettingRow(title: L10n.Settings.Disks.name) {
                TextField("", text: $disk.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            // Mount path
            SettingRow(title: L10n.Settings.Disks.mountPath) {
                HStack(spacing: 8) {
                    TextField("", text: $disk.mountPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                    Button(L10n.Common.browse) {
                        selectMountPath()
                    }
                }
            }

            // Priority
            SettingRow(title: L10n.Settings.Disks.priority, description: L10n.Settings.Disks.priorityHint) {
                Stepper(value: $disk.priority, in: 0...10) {
                    Text("\(disk.priority)")
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }

            // Status
            if disk.isConnected {
                SettingLabelRow(
                    title: "Status",
                    value: L10n.Disk.connected
                )
            } else {
                SettingLabelRow(
                    title: "Status",
                    value: L10n.Disk.disconnected
                )
            }

            Divider()

            // Options
            CheckboxRow(
                title: L10n.Settings.Disks.enable,
                isChecked: $disk.enabled
            )

            // Actions
            HStack {
                Spacer()

                Button(L10n.Disk.testConnection) {
                    testConnection()
                }
                .disabled(!disk.isConnected)

                Button(role: .destructive, action: onDelete) {
                    Text(L10n.Settings.Disks.remove)
                }
            }
            .padding(.top, 8)
        }
    }

    private func selectMountPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")

        if panel.runModal() == .OK, let url = panel.url {
            disk.mountPath = url.path
        }
    }

    private func testConnection() {
        // Test connection logic
        let exists = FileManager.default.fileExists(atPath: disk.mountPath)
        if exists {
            // Show success
        } else {
            // Show error
        }
    }
}

/// Sheet for adding a new disk
struct AddDiskSheet: View {
    let onAdd: (DiskConfig) -> Void
    let existingDiskNames: Set<String>

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var mountPath: String = "/Volumes/"
    @State private var priority: Int = 0
    @State private var detectedVolumes: [URL] = []

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.Settings.Disks.add)
                .font(.headline)

            // Detected volumes
            if !detectedVolumes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Wizard.Disks.detected)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ForEach(detectedVolumes, id: \.path) { volume in
                        Button {
                            selectVolume(volume)
                        } label: {
                            HStack {
                                Image(systemName: "externaldrive.fill")
                                Text(volume.lastPathComponent)
                                Spacer()
                                if name == volume.lastPathComponent {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(8)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Manual entry
            VStack(alignment: .leading, spacing: 12) {
                SettingRow(title: L10n.Settings.Disks.name) {
                    TextField("BACKUP", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }

                SettingRow(title: L10n.Settings.Disks.mountPath) {
                    HStack {
                        TextField("/Volumes/BACKUP", text: $mountPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)

                        Button(L10n.Common.browse) {
                            browseForVolume()
                        }
                    }
                }

                SettingRow(title: L10n.Settings.Disks.priority, description: L10n.Settings.Disks.priorityHint) {
                    Stepper(value: $priority, in: 0...10) {
                        Text("\(priority)")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
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
                    let newDisk = DiskConfig(
                        id: UUID().uuidString,
                        name: name,
                        mountPath: mountPath,
                        priority: priority
                    )
                    onAdd(newDisk)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || existingDiskNames.contains(name))
            }
        }
        .padding(20)
        .frame(width: 450, height: 400)
        .onAppear {
            detectVolumes()
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
            detectedVolumes = contents.filter { url in
                // Exclude system volume
                url.lastPathComponent != "Macintosh HD" &&
                !existingDiskNames.contains(url.lastPathComponent)
            }
        } catch {
            detectedVolumes = []
        }
    }

    private func selectVolume(_ volume: URL) {
        name = volume.lastPathComponent
        mountPath = volume.path
    }

    private func browseForVolume() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")

        if panel.runModal() == .OK, let url = panel.url {
            mountPath = url.path
            if name.isEmpty {
                name = url.lastPathComponent
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
struct DiskSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        DiskSettingsView(config: .constant(AppConfig(
            disks: [
                DiskConfig(name: "BACKUP", mountPath: "/Volumes/BACKUP", priority: 0),
                DiskConfig(name: "PORTABLE", mountPath: "/Volumes/PORTABLE", priority: 1)
            ]
        )))
        .frame(width: 450, height: 600)
    }
}
#endif
