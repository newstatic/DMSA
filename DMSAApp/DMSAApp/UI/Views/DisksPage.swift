import SwiftUI

// MARK: - Disks Page

/// Disk management page - Master-Detail layout
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
                    allSyncPairs: $config.syncPairs,
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
    @Binding var allSyncPairs: [SyncPairConfig]
    let diskManager: DiskManager
    let onDelete: () -> Void

    private var syncPairs: [SyncPairConfig] {
        allSyncPairs.filter { $0.diskId == disk.id }
    }

    @State private var showTestResult = false
    @State private var testSuccess = false
    @State private var showAddSyncPairSheet = false
    @State private var syncPairToDelete: SyncPairConfig?
    @State private var showDeleteSyncPairConfirmation = false

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
        .sheet(isPresented: $showAddSyncPairSheet) {
            AddSyncPairSheet(
                diskId: disk.id,
                diskMountPath: disk.mountPath,
                onAdd: { newPair in
                    allSyncPairs.append(newPair)
                }
            )
        }
        .alert("disks.syncPair.delete.title".localized, isPresented: $showDeleteSyncPairConfirmation) {
            Button("common.cancel".localized, role: .cancel) { }
            Button("common.delete".localized, role: .destructive) {
                if let pair = syncPairToDelete {
                    allSyncPairs.removeAll { $0.id == pair.id }
                }
            }
        } message: {
            if let pair = syncPairToDelete {
                Text(String(format: "disks.syncPair.delete.message".localized, pair.name))
            }
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

                    if disk.fileSystem != "auto" {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(disk.fileSystem)
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

                Button {
                    showAddSyncPairSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("disks.syncPair.add".localized)
            }

            if syncPairs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text("disks.syncPairs.empty".localized)
                        .font(.body)
                        .foregroundColor(.secondary)

                    Button {
                        showAddSyncPairSheet = true
                    } label: {
                        Label("disks.syncPair.add".localized, systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(syncPairs) { pair in
                        if let index = allSyncPairs.firstIndex(where: { $0.id == pair.id }) {
                            SyncPairEditableRow(
                                pair: $allSyncPairs[index],
                                onDelete: {
                                    syncPairToDelete = pair
                                    showDeleteSyncPairConfirmation = true
                                }
                            )
                        }
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

// MARK: - Sync Pair Editable Row

struct SyncPairEditableRow: View {
    @Binding var pair: SyncPairConfig
    var onDelete: (() -> Void)? = nil
    @State private var isExpanded = false

    // Preset cache size options
    private let cacheSizeOptions: [(label: String, value: Int64)] = [
        ("1 GB", 1 * 1024 * 1024 * 1024),
        ("5 GB", 5 * 1024 * 1024 * 1024),
        ("10 GB", 10 * 1024 * 1024 * 1024),
        ("20 GB", 20 * 1024 * 1024 * 1024),
        ("50 GB", 50 * 1024 * 1024 * 1024),
        ("100 GB", 100 * 1024 * 1024 * 1024),
        ("settings.eviction.unlimited".localized, Int64.max)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Main row (always visible)
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.name)
                        .font(.body)

                    Text("\(pair.localPath) → \(pair.externalRelativePath)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Cache size badge
                if pair.maxLocalCacheSize < Int64.max {
                    Text(ByteCountFormatter.string(fromByteCount: pair.maxLocalCacheSize, countStyle: .file))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }

                // Expand button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            // Expanded content (eviction settings)
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 12) {
                    // Auto eviction toggle
                    Toggle("settings.eviction.autoEnabled".localized, isOn: $pair.autoEvictionEnabled)
                        .toggleStyle(.switch)

                    // Max local cache size
                    VStack(alignment: .leading, spacing: 4) {
                        Text("settings.eviction.maxCacheSize".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: $pair.maxLocalCacheSize) {
                            ForEach(cacheSizeOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    // Target free space (only shown if auto eviction is enabled)
                    if pair.autoEvictionEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings.eviction.targetFreeSpace".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                Slider(
                                    value: Binding(
                                        get: { Double(pair.targetFreeSpace) / Double(1024 * 1024 * 1024) },
                                        set: { pair.targetFreeSpace = Int64($0) * 1024 * 1024 * 1024 }
                                    ),
                                    in: 1...50,
                                    step: 1
                                )

                                Text(ByteCountFormatter.string(fromByteCount: pair.targetFreeSpace, countStyle: .file))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 60)
                            }
                        }

                        // Explanation
                        Text("settings.eviction.hint".localized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    // Delete button
                    if let onDelete = onDelete {
                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("disks.syncPair.delete".localized, systemImage: "trash")
                                    .font(.caption)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Sync Pair Row (Legacy, for display only)

struct SyncPairRow: View {
    let pair: SyncPairConfig

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(pair.name)
                    .font(.body)

                Text("\(pair.localPath) → \(pair.externalRelativePath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Sync direction badge
            Text(pair.direction.rawValue)
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

// MARK: - Add Sync Pair Sheet

struct AddSyncPairSheet: View {
    let diskId: String
    let diskMountPath: String
    let onAdd: (SyncPairConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var localPath: String = ""
    @State private var externalRelativePath: String = ""
    @State private var maxLocalCacheSize: Int64 = 10 * 1024 * 1024 * 1024
    @State private var autoEvictionEnabled: Bool = true

    private var isValid: Bool {
        !localPath.isEmpty && !externalRelativePath.isEmpty
    }

    private var suggestedExternalPath: String {
        let name = (localPath as NSString).lastPathComponent
        return name.isEmpty ? "" : name
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("disks.syncPair.add.title".localized)
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Local path
                    VStack(alignment: .leading, spacing: 6) {
                        Text("disks.syncPair.localPath".localized)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack {
                            TextField("~/Downloads", text: $localPath)
                                .textFieldStyle(.roundedBorder)

                            Button("common.browse".localized) {
                                selectLocalPath()
                            }
                        }

                        Text("disks.syncPair.localPath.hint".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // External relative path
                    VStack(alignment: .leading, spacing: 6) {
                        Text("disks.syncPair.externalPath".localized)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack {
                            Text(diskMountPath + "/")
                                .foregroundColor(.secondary)
                            TextField("Downloads", text: $externalRelativePath)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text("disks.syncPair.externalPath.hint".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Cache settings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("disks.syncPair.cacheSettings".localized)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Toggle("settings.eviction.autoEnabled".localized, isOn: $autoEvictionEnabled)
                            .toggleStyle(.switch)

                        HStack {
                            Text("settings.eviction.maxCacheSize".localized)
                            Spacer()
                            Picker("", selection: $maxLocalCacheSize) {
                                Text("5 GB").tag(Int64(5 * 1024 * 1024 * 1024))
                                Text("10 GB").tag(Int64(10 * 1024 * 1024 * 1024))
                                Text("20 GB").tag(Int64(20 * 1024 * 1024 * 1024))
                                Text("50 GB").tag(Int64(50 * 1024 * 1024 * 1024))
                                Text("settings.eviction.unlimited".localized).tag(Int64.max)
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("common.cancel".localized) {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("common.add".localized) {
                    addSyncPair()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
        .onChange(of: localPath) { _ in
            if externalRelativePath.isEmpty {
                externalRelativePath = suggestedExternalPath
            }
        }
    }

    private func selectLocalPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url {
            localPath = url.path
        }
    }

    private func addSyncPair() {
        var newPair = SyncPairConfig(
            diskId: diskId,
            localPath: localPath,
            externalRelativePath: externalRelativePath
        )
        newPair.maxLocalCacheSize = maxLocalCacheSize
        newPair.autoEvictionEnabled = autoEvictionEnabled

        // Save new sync pair ID for subsequent index trigger
        let syncPairId = newPair.id

        onAdd(newPair)
        dismiss()

        // Trigger index building asynchronously
        Task {
            do {
                // First add sync pair to the service
                try await ServiceClient.shared.addSyncPair(newPair)
                // Then trigger index building
                try await ServiceClient.shared.rebuildIndex(syncPairId: syncPairId)
                Logger.shared.info("[DisksPage] Sync pair \(syncPairId) added and indexing started")
            } catch {
                Logger.shared.error("[DisksPage] Failed to add sync pair or build index: \(error.localizedDescription)")
            }
        }
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
            SyncPairConfig(
                diskId: config.disks[0].id,
                localPath: "~/Documents",
                externalRelativePath: "Documents"
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
