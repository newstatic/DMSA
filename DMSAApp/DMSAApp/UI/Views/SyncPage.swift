import SwiftUI

// MARK: - Sync Page

/// 同步页面 - 显示同步状态、进度和历史
struct SyncPage: View {
    @Binding var config: AppConfig
    @StateObject private var progressListener = SyncProgressListener()

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
            setupProgressListener()
        }
        .onChange(of: progressListener.currentProgress) { progress in
            if let progress = progress {
                updateFromProgress(progress)
            }
        }
        .onChange(of: progressListener.lastStatusChange) { change in
            if let change = change {
                handleStatusChange(change)
            }
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
        if isSyncing {
            return isPaused ? .orange : .blue
        }
        return .gray
    }

    private var statusTitle: String {
        if isSyncing {
            return isPaused
                ? "sync.status.paused".localized
                : "sync.status.syncing".localized
        }
        return "sync.status.idle".localized
    }

    private var statusSubtitle: String {
        if isSyncing {
            if isPaused {
                return "sync.status.tapToResume".localized
            }
            return String(format: "sync.status.progress".localized, processedFiles, totalFiles)
        }
        return "sync.status.clickToStart".localized
    }

    private var canStartSync: Bool {
        diskManager.isAnyExternalConnected && !config.syncPairs.isEmpty
    }

    // MARK: - Actions

    private func startSync() {
        guard canStartSync else { return }

        isSyncing = true
        isPaused = false
        syncProgress = 0
        processedFiles = 0
        totalFiles = 0
        failedFiles = []

        Task {
            do {
                try await serviceClient.updateConfig(config)
                try await serviceClient.syncAll()
            } catch {
                await MainActor.run {
                    isSyncing = false
                }
                Logger.shared.error("Sync failed: \(error.localizedDescription)")
            }
        }
    }

    private func togglePause() {
        Task {
            if isPaused {
                try? await serviceClient.resumeSync()
                await MainActor.run { isPaused = false }
            } else {
                try? await serviceClient.pauseSync()
                await MainActor.run { isPaused = true }
            }
        }
    }

    private func cancelSync() {
        Task {
            try? await serviceClient.cancelSync()
            await MainActor.run {
                isSyncing = false
                isPaused = false
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

    private func setupProgressListener() {
        serviceClient.progressDelegate = progressListener
    }

    private func updateFromProgress(_ progress: ServiceSyncProgressInfo) {
        isSyncing = progress.status == .inProgress
        syncProgress = progress.progress
        processedFiles = progress.processedFiles
        totalFiles = progress.totalFiles
        processedBytes = progress.processedBytes
        totalBytes = progress.totalBytes
        currentFile = progress.currentFile
        isPaused = progress.isPaused

        // Calculate speed (simplified)
        if progress.processedBytes > 0 {
            syncSpeed = progress.processedBytes / max(1, Int64(Date().timeIntervalSince1970) % 60)
        }

        if progress.status == .completed || progress.status == .failed {
            loadData()
        }
    }

    private func handleStatusChange(_ change: SyncStatusChange) {
        switch change.status {
        case .inProgress:
            isSyncing = true
            isPaused = false
        case .completed, .failed, .cancelled:
            isSyncing = false
            isPaused = false
            loadData()
        case .paused:
            isPaused = true
        default:
            break
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
