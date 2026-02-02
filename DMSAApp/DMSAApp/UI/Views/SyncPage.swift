import SwiftUI

// MARK: - Sync Page

/// Sync page - displays sync status, progress, and history
struct SyncPage: View {
    @Binding var config: AppConfig
    @ObservedObject private var stateManager = StateManager.shared

    // Services
    private let serviceClient = ServiceClient.shared
    private let diskManager = DiskManager.shared

    // State
    @State private var isSyncing = false
    @State private var isPaused = false
    @State private var syncProgress: Double = 0
    @State private var processedFiles: Int = 0
    @State private var totalFiles: Int = 0
    @State private var processedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var currentFile: String?
    @State private var syncSpeed: Int64 = 0
    @State private var estimatedTimeRemaining: TimeInterval?
    @State private var failedFiles: [SyncErrorItem] = []
    @State private var syncHistory: [SyncHistory] = []
    @State private var isLoading = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Sync Status Header
                syncStatusHeader

                // Stats Grid (when syncing)
                if isSyncing {
                    statsGridSection
                }

                // Current File (when syncing)
                if isSyncing, let file = currentFile {
                    currentFileSection(file)
                }

                // Failed Files (if any)
                if !failedFiles.isEmpty {
                    failedFilesSection
                }

                // Sync Pairs List
                syncPairsSection

                // Sync History
                syncHistorySection
            }
            .padding(32)
            .frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadData()
            updateFromStateManager()
        }
        .onChange(of: stateManager.syncStatus) { _ in
            updateFromStateManager()
        }
        .onChange(of: stateManager.processedFiles) { _ in
            updateFromStateManager()
        }
    }

    // MARK: - Sync Status Header

    private var syncStatusHeader: some View {
        HStack(spacing: 20) {
            // Status Ring
            StatusRing(
                size: 100,
                icon: statusIcon,
                color: statusColor,
                progress: isSyncing ? syncProgress : (isPaused ? syncProgress : 1.0),
                isAnimating: isSyncing && !isPaused
            )

            // Status Info
            VStack(alignment: .leading, spacing: 8) {
                Text(statusTitle)
                    .font(.title)
                    .fontWeight(.semibold)

                Text(statusSubtitle)
                    .font(.body)
                    .foregroundColor(.secondary)

                Spacer()
                    .frame(height: 12)

                // Control Buttons
                HStack(spacing: 12) {
                    if isSyncing {
                        // Pause/Resume button
                        CompactActionButton(
                            icon: isPaused ? "play.fill" : "pause.fill",
                            title: isPaused ? "sync.resume".localized : "sync.pause".localized,
                            style: .secondary,
                            action: togglePause
                        )

                        // Cancel button
                        CompactActionButton(
                            icon: "xmark",
                            title: "sync.cancel".localized,
                            style: .destructive,
                            action: cancelSync
                        )
                    } else {
                        // Start Sync button
                        CompactActionButton(
                            icon: "arrow.clockwise",
                            title: "sync.start".localized,
                            style: .primary,
                            isEnabled: canStartSync,
                            action: startSync
                        )
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Stats Grid Section

    private var statsGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatCardGrid(cards: [
                StatCardItem(
                    icon: "doc.fill",
                    label: "sync.stats.processed".localized,
                    value: "\(processedFiles)",
                    subtitle: "/ \(totalFiles)",
                    color: .blue
                ),
                StatCardItem(
                    icon: "arrow.up.arrow.down",
                    label: "sync.stats.transferred".localized,
                    value: formatBytes(processedBytes),
                    color: .green
                ),
                StatCardItem(
                    icon: "speedometer",
                    label: "sync.stats.speed".localized,
                    value: "\(formatBytes(syncSpeed))/s",
                    color: .orange
                ),
                StatCardItem(
                    icon: "clock",
                    label: "sync.stats.remaining".localized,
                    value: formatTimeRemaining(estimatedTimeRemaining),
                    color: .purple
                )
            ])
        }
    }

    // MARK: - Current File Section

    private func currentFileSection(_ fileName: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "sync.currentFile".localized)

            FileRow(
                fileName: (fileName as NSString).lastPathComponent,
                filePath: (fileName as NSString).deletingLastPathComponent,
                fileSize: nil,
                progress: syncProgress
            )
        }
    }

    // MARK: - Failed Files Section

    private var failedFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "sync.failedFiles".localized)

                Spacer()

                Text("\(failedFiles.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.2))
                    .foregroundColor(.red)
                    .cornerRadius(10)

                Button("sync.retryAll".localized) {
                    retryAllFailed()
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 8) {
                ForEach(failedFiles.prefix(5)) { error in
                    SyncErrorRow(error: error, onRetry: {
                        retryFile(error)
                    })
                }
            }
        }
    }

    // MARK: - Sync Pairs Section

    private var syncPairsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "sync.pairs".localized)

            if config.syncPairs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("sync.pairs.empty".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(config.syncPairs, id: \.id) { pair in
                        SyncPairCard(
                            pair: pair,
                            disk: config.disks.first(where: { $0.id == pair.diskId }),
                            isDiskConnected: diskManager.isDiskConnected(pair.diskId),
                            isSyncing: isSyncing,
                            onSync: { syncPair(pair) }
                        )
                    }
                }
            }
        }
    }

    private func syncPair(_ pair: SyncPairConfig) {
        guard stateManager.isReady else { return }
        Task {
            do {
                try await serviceClient.syncNow(syncPairId: pair.id)
            } catch {
                Logger.shared.error("Sync failed: \(pair.name) - \(error)")
            }
        }
    }

    // MARK: - Sync History Section

    private var syncHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "sync.history".localized)

            if syncHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)

                    Text("sync.history.empty".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                VStack(spacing: 0) {
                    ForEach(syncHistory.prefix(10)) { history in
                        SyncHistoryRow(history: history)

                        if history.id != syncHistory.prefix(10).last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Computed Properties

    private var statusIcon: String {
        if isSyncing {
            return isPaused ? "pause.circle.fill" : "arrow.clockwise"
        }
        return "arrow.clockwise"
    }

    private var statusColor: Color {
        // Check service status first
        if !stateManager.isReady {
            switch stateManager.syncStatus {
            case .indexing:
                return .orange
            case .starting:
                return .yellow
            case .reconnecting:
                return .orange
            default:
                return .gray
            }
        }
        if isSyncing {
            return isPaused ? .orange : .blue
        }
        return .gray
    }

    private var statusTitle: String {
        // Check service status first
        if !stateManager.isReady {
            switch stateManager.syncStatus {
            case .starting:
                return "sync.status.starting".localized
            case .indexing:
                return "sync.status.indexing".localized
            case .reconnecting:
                return "sync.status.reconnecting".localized
            case .serviceUnavailable:
                return "sync.status.serviceUnavailable".localized
            default:
                return "sync.status.preparing".localized
            }
        }
        if isSyncing {
            return isPaused
                ? "sync.status.paused".localized
                : "sync.status.syncing".localized
        }
        return "sync.status.idle".localized
    }

    private var statusSubtitle: String {
        // Check service status first
        if !stateManager.isReady {
            switch stateManager.syncStatus {
            case .starting:
                return "sync.status.startingDesc".localized
            case .indexing:
                return "sync.status.indexingDesc".localized
            case .reconnecting:
                return "sync.status.reconnectingDesc".localized
            case .serviceUnavailable:
                return "sync.status.serviceUnavailableDesc".localized
            default:
                return "sync.status.preparingDesc".localized
            }
        }
        if isSyncing {
            if isPaused {
                return "sync.status.tapToResume".localized
            }
            return String(format: "sync.status.progress".localized, processedFiles, totalFiles)
        }
        return "sync.status.clickToStart".localized
    }

    private var canStartSync: Bool {
        stateManager.isReady && diskManager.isAnyExternalConnected && !config.syncPairs.isEmpty
    }

    // MARK: - Actions

    private func startSync() {
        guard canStartSync else { return }

        // Clear failed files list
        failedFiles = []

        Task {
            do {
                try await serviceClient.updateConfig(config)
                try await serviceClient.syncAll()
                // Sync status updated by StateManager via XPC callback
            } catch {
                Logger.shared.error("Sync failed: \(error.localizedDescription)")
            }
        }
    }

    private func togglePause() {
        Task {
            do {
                if isPaused {
                    try await serviceClient.resumeSync()
                    Logger.shared.info("Resume sync request sent")
                } else {
                    try await serviceClient.pauseSync()
                    Logger.shared.info("Pause sync request sent")
                }
                // Status will be updated by StateManager via XPC callback
            } catch {
                Logger.shared.error("Pause/resume sync failed: \(error)")
            }
        }
    }

    private func cancelSync() {
        Task {
            do {
                try await serviceClient.cancelSync()
                Logger.shared.info("Cancel sync request sent")
                // Status will be updated by StateManager via XPC callback
            } catch {
                Logger.shared.error("Cancel sync failed: \(error)")
            }
        }
    }

    private func retryAllFailed() {
        // Retry all failed files
        Task {
            for error in failedFiles {
                // Retry logic
            }
        }
    }

    private func retryFile(_ error: SyncErrorItem) {
        // Retry single file
    }

    private func loadData() {
        isLoading = true

        Task {
            let history = (try? await serviceClient.getSyncHistory(limit: 10)) ?? []

            await MainActor.run {
                syncHistory = history
                isLoading = false
            }
        }
    }

    /// Update local state from StateManager
    private func updateFromStateManager() {
        isSyncing = stateManager.syncStatus == .syncing
        isPaused = stateManager.syncStatus == .paused
        syncProgress = stateManager.syncProgressValue
        processedFiles = stateManager.processedFiles
        totalFiles = stateManager.totalFilesCount
        processedBytes = stateManager.processedBytes
        totalBytes = stateManager.totalBytes
        currentFile = stateManager.currentSyncFile
        syncSpeed = stateManager.syncSpeed

        // Calculate remaining time
        if syncSpeed > 0 && totalBytes > processedBytes {
            let remainingBytes = totalBytes - processedBytes
            estimatedTimeRemaining = TimeInterval(remainingBytes) / TimeInterval(syncSpeed)
        } else {
            estimatedTimeRemaining = nil
        }

        // Refresh history when sync completes
        if stateManager.syncStatus == .ready && isSyncing {
            loadData()
        }
    }

    // MARK: - Helper Methods

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatTimeRemaining(_ interval: TimeInterval?) -> String {
        guard let interval = interval, interval > 0 else {
            return "--"
        }

        if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else {
            let hours = Int(interval / 3600)
            let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Sync Error Item

struct SyncErrorItem: Identifiable {
    let id = UUID()
    let fileName: String
    let filePath: String
    let errorMessage: String
    let timestamp: Date
}

// MARK: - Sync Error Row

struct SyncErrorRow: View {
    let error: SyncErrorItem
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.fileName)
                    .font(.body)
                    .lineLimit(1)

                Text(error.errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button("Retry") {
                onRetry()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Sync Pair Card

struct SyncPairCard: View {
    let pair: SyncPairConfig
    let disk: DiskConfig?
    let isDiskConnected: Bool
    let isSyncing: Bool
    let onSync: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Connection status
            ZStack {
                Circle()
                    .fill(isDiskConnected ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: isDiskConnected ? "link.circle.fill" : "link.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isDiskConnected ? .green : .gray)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pair.name)
                        .font(.body)
                        .fontWeight(.medium)

                    if !pair.enabled {
                        Text("sync.pairs.disabled".localized)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 4) {
                    // Direction
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(disk?.name ?? pair.diskId)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text(pair.externalRelativePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status + action
            if isDiskConnected {
                Button(action: onSync) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSyncing || !pair.enabled)
            } else {
                Text("sync.pairs.diskOffline".localized)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Sync History Row

struct SyncHistoryRow: View {
    let history: SyncHistory

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: history.startedAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: statusIcon)
                .font(.system(size: 18))
                .foregroundColor(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(history.syncPairId)
                    .font(.body)

                Text(formattedTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(history.filesCount) files")
                    .font(.callout)

                Text(ByteCountFormatter.string(fromByteCount: history.totalSize, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var statusIcon: String {
        history.status == .completed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        history.status == .completed ? .green : .red
    }
}

// MARK: - Previews

#if DEBUG
struct SyncPage_Previews: PreviewProvider {
    static var previews: some View {
        SyncPage(config: .constant(AppConfig()))
            .frame(width: 700, height: 800)
    }
}
#endif
