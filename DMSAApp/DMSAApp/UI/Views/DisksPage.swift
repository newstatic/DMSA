import SwiftUI

// MARK: - Disks Page

/// 磁盘管理页面 - Master-Detail 布局
struct DisksPage: View {
    @Binding var config: AppConfig

    // Services
    private let diskManager = DiskManager.shared

    // State
    @State private var selectedDiskId: String?
    @State private var showAddDiskSheet = false
    @State private var showDeleteConfirmation = false
    @State private var diskToDelete: DiskConfig?

    // MARK: - Computed Properties

    private var selectedDisk: DiskConfig? {
        config.disks.first { $0.id == selectedDiskId }
    }

    private var selectedDiskIndex: Int? {
        config.disks.firstIndex { $0.id == selectedDiskId }
    }

    private var connectedDisks: [DiskConfig] {
        config.disks.filter { diskManager.isDiskConnected($0.id) }
    }

    private var disconnectedDisks: [DiskConfig] {
        config.disks.filter { !diskManager.isDiskConnected($0.id) }
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            // Master: Disk list
            diskListPanel
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

            // Detail: Disk details
            diskDetailPanel
                .frame(minWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showAddDiskSheet) {
            AddDiskSheet(
                onAdd: { newDisk in
                    config.disks.append(newDisk)
                    selectedDiskId = newDisk.id
                },
                existingDiskNames: Set(config.disks.map { $0.name })
            )
        }
        .alert("disks.delete.confirm.title".localized, isPresented: $showDeleteConfirmation) {
            Button("common.cancel".localized, role: .cancel) { }
            Button("common.delete".localized, role: .destructive) {
                if let disk = diskToDelete {
                    deleteDisk(disk)
                }
            }
        } message: {
            if let disk = diskToDelete {
                Text(String(format: "disks.delete.confirm.message".localized, disk.name))
            }
        }
        .onAppear {
            // Select first disk if none selected
            if selectedDiskId == nil {
                selectedDiskId = config.disks.first?.id
            }
        }
    }

    // MARK: - Disk List Panel (Master)

    private var diskListPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("disks.title".localized)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    showAddDiskSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("disks.add".localized)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            // Disk list
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Connected disks section
                    if !connectedDisks.isEmpty {
                        DiskListSection(
                            title: "disks.section.connected".localized,
                            disks: connectedDisks,
                            selectedDiskId: selectedDiskId,
                            diskManager: diskManager,
                            onSelect: { selectedDiskId = $0 }
                        )
                    }

                    // Disconnected disks section
                    if !disconnectedDisks.isEmpty {
                        DiskListSection(
                            title: "disks.section.disconnected".localized,
                            disks: disconnectedDisks,
                            selectedDiskId: selectedDiskId,
                            diskManager: diskManager,
                            onSelect: { selectedDiskId = $0 }
                        )
                    }

                    // Empty state
                    if config.disks.isEmpty {
                        EmptyDisksView(onAddDisk: { showAddDiskSheet = true })
                            .padding(.top, 40)
                    }
                }
                .padding(16)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Disk Detail Panel (Detail)

    private var diskDetailPanel: some View {
        Group {
            if let disk = selectedDisk, let index = selectedDiskIndex {
                DiskDetailView(
                    disk: Binding(
                        get: { config.disks[index] },
                        set: { config.disks[index] = $0 }
                    ),
                    syncPairs: config.syncPairs.filter { $0.diskId == disk.id },
                    diskManager: diskManager,
                    onDelete: {
                        diskToDelete = disk
                        showDeleteConfirmation = true
                    }
                )
            } else {
                // No selection placeholder
                VStack(spacing: 16) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("disks.select.prompt".localized)
                        .font(.title3)
                        .foregroundColor(.secondary)

                    if config.disks.isEmpty {
                        Button {
                            showAddDiskSheet = true
                        } label: {
                            Label("disks.add".localized, systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Actions

    private func deleteDisk(_ disk: DiskConfig) {
        let diskId = disk.id

        // Remove sync pairs referencing this disk
        config.syncPairs.removeAll { $0.diskId == diskId }

        // Remove disk
        config.disks.removeAll { $0.id == diskId }

        // Clear selection
        if selectedDiskId == diskId {
            selectedDiskId = config.disks.first?.id
        }
    }
}

// MARK: - Disk List Section

struct DiskListSection: View {
    let title: String
    let disks: [DiskConfig]
    let selectedDiskId: String?
    let diskManager: DiskManager
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            // Disk items
            ForEach(disks) { disk in
                DiskListItem(
                    disk: disk,
                    isSelected: disk.id == selectedDiskId,
                    diskInfo: diskManager.getDiskInfo(at: disk.mountPath),
                    onSelect: { onSelect(disk.id) }
                )
            }
        }
    }
}

// MARK: - Disk List Item

struct DiskListItem: View {
    let disk: DiskConfig
    let isSelected: Bool
    let diskInfo: (total: Int64, available: Int64, used: Int64)?
    let onSelect: () -> Void

    private var isConnected: Bool {
        diskInfo != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isConnected ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: isConnected ? "externaldrive.fill" : "externaldrive")
                    .font(.system(size: 18))
                    .foregroundColor(isConnected ? .green : .gray)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(disk.name)
                    .font(.body)
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)

                if let info = diskInfo {
                    Text("\(info.available.formattedBytes) available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("disks.status.disconnected".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status indicator
            Circle()
                .fill(isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Disk Detail View

struct DiskDetailView: View {
    @Binding var disk: DiskConfig
    let syncPairs: [SyncPair]
    let diskManager: DiskManager
    let onDelete: () -> Void

    @State private var showTestResult = false
    @State private var testSuccess = false

    private var diskInfo: (total: Int64, available: Int64, used: Int64)? {
        diskManager.getDiskInfo(at: disk.mountPath)
    }

    private var isConnected: Bool {
        diskInfo != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with disk info
                diskHeader

                Divider()

                // Storage section
                if isConnected {
                    storageSection
                    Divider()
                }

                // Configuration section
                configurationSection

                Divider()

                // Sync pairs section
                syncPairsSection

                Divider()

                // Actions section
                actionsSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(testSuccess ? "disks.test.success.title".localized : "disks.test.failed.title".localized,
               isPresented: $showTestResult) {
            Button("common.ok".localized, role: .cancel) { }
        } message: {
            Text(testSuccess ? "disks.test.success.message".localized : "disks.test.failed.message".localized)
        }
    }

    // MARK: - Header

    private var diskHeader: some View {
        HStack(spacing: 16) {
            // Large disk icon
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isConnected ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                    .frame(width: 72, height: 72)

                Image(systemName: isConnected ? "externaldrive.fill" : "externaldrive")
                    .font(.system(size: 32))
                    .foregroundColor(isConnected ? .green : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Editable name
                TextField("disks.name".localized, text: $disk.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textFieldStyle(.plain)

                Text(disk.mountPath)
                    .font(.body)
                    .foregroundColor(.secondary)

                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(isConnected ? "disks.status.connected".localized : "disks.status.disconnected".localized)
                        .font(.caption)
                        .foregroundColor(isConnected ? .green : .gray)

                    if let info = diskInfo, let fs = disk.fileSystem, fs != "auto" {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(fs)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Enable toggle
            Toggle("", isOn: $disk.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("disks.storage".localized)
                .font(.headline)

            if let info = diskInfo {
                // Storage bar
                StorageBar(used: info.used, total: info.total)

                // Storage details grid
                HStack(spacing: 24) {
                    StorageDetailItem(
                        label: "disks.storage.used".localized,
                        value: info.used.formattedBytes,
                        color: .blue
                    )

                    StorageDetailItem(
                        label: "disks.storage.available".localized,
                        value: info.available.formattedBytes,
                        color: .green
                    )

                    StorageDetailItem(
                        label: "disks.storage.total".localized,
                        value: info.total.formattedBytes,
                        color: .secondary
                    )
                }
            }
        }
    }

    // MARK: - Configuration Section

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("disks.configuration".localized)
                .font(.headline)

            // Mount path
            VStack(alignment: .leading, spacing: 4) {
                Text("disks.mountPath".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    TextField("", text: $disk.mountPath)
                        .textFieldStyle(.roundedBorder)

                    Button("common.browse".localized) {
                        selectMountPath()
                    }
                }
            }

            // Priority
            VStack(alignment: .leading, spacing: 4) {
                Text("disks.priority".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Stepper(value: $disk.priority, in: 0...10) {
                        HStack {
                            Text("\(disk.priority)")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 24)
                        }
                    }

                    Text("disks.priority.hint".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Sync Pairs Section

    private var syncPairsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("disks.syncPairs".localized)
                    .font(.headline)

                Spacer()

                Text("\(syncPairs.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }

            if syncPairs.isEmpty {
                HStack {
                    Image(systemName: "folder.badge.questionmark")
                        .foregroundColor(.secondary)
                    Text("disks.syncPairs.empty".localized)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(syncPairs) { pair in
                        SyncPairRow(pair: pair)
                    }
                }
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        HStack {
            Button {
                testConnection()
            } label: {
                Label("disks.test".localized, systemImage: "network")
            }
            .disabled(!isConnected)

            Button {
                openInFinder()
            } label: {
                Label("disks.openInFinder".localized, systemImage: "folder")
            }
            .disabled(!isConnected)

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("disks.delete".localized, systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

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
        let exists = FileManager.default.fileExists(atPath: disk.mountPath)
        testSuccess = exists
        showTestResult = true
    }

    private func openInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: disk.mountPath)
    }
}

// MARK: - Storage Detail Item

struct StorageDetailItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)

                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
            }
        }
    }
}

// MARK: - Sync Pair Row

struct SyncPairRow: View {
    let pair: SyncPair

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(pair.name)
                    .font(.body)

                Text("\(pair.localPath) → \(pair.externalPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Sync mode badge
            Text(pair.syncMode.rawValue)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Empty Disks View

struct EmptyDisksView: View {
    let onAddDisk: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("disks.empty.title".localized)
                .font(.title3)
                .fontWeight(.medium)

            Text("disks.empty.message".localized)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                onAddDisk()
            } label: {
                Label("disks.add".localized, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 300)
    }
}

// MARK: - Previews

#if DEBUG
struct DisksPage_Previews: PreviewProvider {
    static var sampleConfig: AppConfig = {
        var config = AppConfig()
        config.disks = [
            DiskConfig(name: "BACKUP", mountPath: "/Volumes/BACKUP", priority: 0),
            DiskConfig(name: "PORTABLE", mountPath: "/Volumes/PORTABLE", priority: 1)
        ]
        config.syncPairs = [
            SyncPair(
                name: "Documents",
                diskId: config.disks[0].id,
                localPath: "~/Documents",
                externalPath: "Documents"
            )
        ]
        return config
    }()

    static var previews: some View {
        DisksPage(config: .constant(sampleConfig))
            .frame(width: 900, height: 600)
    }
}
#endif
