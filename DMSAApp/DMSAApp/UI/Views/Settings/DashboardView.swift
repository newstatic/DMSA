import SwiftUI

/// Dashboard view - the main home page showing status and sync controls
struct DashboardView: View {
    @Binding var config: AppConfig
    @State private var selectedTimeRange: TimeRange = .last7Days
    @State private var statistics: [SyncStatistics] = []
    @State private var recentHistory: [SyncHistory] = []
    @State private var isLoading = false

    // Sync state
    @State private var isSyncing = false
    @State private var syncProgress: Double = 0
    @State private var syncStatusMessage: String = ""
    @State private var isPaused = false
    @State private var currentSyncPhaseText: String = "空闲"

    // 进度监听器
    @StateObject private var progressListener = SyncProgressListener()

    private let serviceClient = ServiceClient.shared
    private let diskManager = DiskManager.shared

    enum TimeRange: String, CaseIterable, Identifiable {
        case today = "today"
        case last7Days = "7days"
        case last30Days = "30days"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "dashboard.today".localized
            case .last7Days: return L10n.History.last7Days
            case .last30Days: return L10n.History.last30Days
            }
        }

        var days: Int {
            switch self {
            case .today: return 1
            case .last7Days: return 7
            case .last30Days: return 30
            }
        }
    }

    var body: some View {
        SettingsContentView(title: "dashboard.title".localized) {
            VStack(alignment: .leading, spacing: 24) {
                // Sync control section
                syncControlSection

                // Disk status section
                diskStatusSection

                // Quick stats section
                quickStatsSection

                // Recent activity section
                recentActivitySection
            }
        }
        .onAppear {
            loadData()
            setupProgressListener()
        }
        .onDisappear {
            // 清理监听器
        }
        .onChange(of: selectedTimeRange) { _ in loadData() }
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

    // MARK: - Sync Control Section

    private var syncControlSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "dashboard.syncControl".localized)

            HStack(spacing: 20) {
                // Sync status indicator
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(syncStatusColor)
                            .frame(width: 12, height: 12)

                        Text(syncStatusText)
                            .font(.headline)
                    }

                    if isSyncing {
                        ProgressView(value: syncProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)

                        Text(syncStatusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minWidth: 250, alignment: .leading)

                Spacer()

                // Control buttons
                HStack(spacing: 12) {
                    if isSyncing {
                        // Pause button
                        Button {
                            pauseSync()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                Text(isPaused ? "dashboard.resume".localized : "dashboard.pause".localized)
                            }
                        }
                        .buttonStyle(.bordered)

                        // Stop button
                        Button(role: .destructive) {
                            stopSync()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.fill")
                                Text("dashboard.stop".localized)
                            }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        // Start sync button
                        Button {
                            startSync()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("dashboard.startSync".localized)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canStartSync)
                    }
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .cornerRadius(12)
        }
    }

    // MARK: - Disk Status Section

    private var diskStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "dashboard.diskStatus".localized)

            if config.disks.isEmpty {
                HStack {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("dashboard.noDisksConfigured".localized)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Color(.windowBackgroundColor))
                .cornerRadius(8)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(config.disks) { disk in
                        DiskStatusCard(
                            disk: disk,
                            isConnected: diskManager.isDiskConnected(disk.id),
                            diskInfo: getDiskInfo(for: disk)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Quick Stats Section

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "dashboard.quickStats".localized)

                Spacer()

                Picker("", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: "dashboard.totalSyncs".localized,
                    value: "\(totalSyncs)",
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue
                )

                StatCard(
                    title: "dashboard.successRate".localized,
                    value: String(format: "%.0f%%", successRate),
                    icon: "checkmark.circle.fill",
                    color: successRate >= 90 ? .green : (successRate >= 70 ? .orange : .red)
                )

                StatCard(
                    title: "dashboard.filesTransferred".localized,
                    value: "\(totalFiles)",
                    icon: "doc.fill",
                    color: .purple
                )

                StatCard(
                    title: "dashboard.dataTransferred".localized,
                    value: totalBytesFormatted,
                    icon: "arrow.up.arrow.down",
                    color: .orange
                )
            }
        }
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "dashboard.recentActivity".localized)

                Spacer()

                Button {
                    loadData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
            }

            if recentHistory.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("dashboard.noRecentActivity".localized)
                            .foregroundColor(.secondary)
                    }
                    .padding(24)
                    Spacer()
                }
                .background(Color(.windowBackgroundColor))
                .cornerRadius(8)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentHistory.prefix(5)) { history in
                        RecentActivityRow(history: history)

                        if history.id != recentHistory.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(.windowBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Computed Properties

    private var canStartSync: Bool {
        diskManager.isAnyExternalConnected && !config.syncPairs.isEmpty
    }

    private var syncStatusColor: Color {
        if isSyncing {
            return isPaused ? .orange : .blue
        }
        return diskManager.isAnyExternalConnected ? .green : .gray
    }

    private var syncStatusText: String {
        if isSyncing {
            return isPaused ? "dashboard.status.paused".localized : "dashboard.status.syncing".localized
        }
        if !diskManager.isAnyExternalConnected {
            return "dashboard.status.noDisk".localized
        }
        return "dashboard.status.ready".localized
    }

    private var totalSyncs: Int {
        statistics.reduce(0) { $0 + $1.totalSyncs }
    }

    private var successfulSyncs: Int {
        statistics.reduce(0) { $0 + $1.successfulSyncs }
    }

    private var successRate: Double {
        guard totalSyncs > 0 else { return 100 }
        return Double(successfulSyncs) / Double(totalSyncs) * 100
    }

    private var totalFiles: Int {
        statistics.reduce(0) { $0 + $1.totalFilesTransferred }
    }

    private var totalBytes: Int64 {
        statistics.reduce(0) { $0 + $1.totalBytesTransferred }
    }

    private var totalBytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    // MARK: - Actions

    private func startSync() {
        guard diskManager.isAnyExternalConnected else {
            Logger.shared.warn("没有已连接的硬盘")
            return
        }

        isSyncing = true
        isPaused = false
        syncProgress = 0
        syncStatusMessage = "dashboard.status.starting".localized

        Task {
            do {
                // 1. 先上发当前配置到 Service
                try await serviceClient.updateConfig(config)
                Logger.shared.info("配置已上发到 Service")

                // 2. 开始同步（Service 会实时下发进度）
                try await serviceClient.syncAll()

                // 注意：同步完成后的 UI 更新由 progressListener 处理
            } catch {
                await MainActor.run {
                    isSyncing = false
                    Logger.shared.error("同步失败: \(error.localizedDescription)")
                }
            }
        }
    }

    private func pauseSync() {
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

    private func stopSync() {
        Task {
            try? await serviceClient.cancelSync()
            await MainActor.run {
                isSyncing = false
                isPaused = false
            }
        }
    }

    private func loadData() {
        isLoading = true

        Task {
            // 从 Service 获取同步历史
            let history = (try? await serviceClient.getSyncHistory(limit: 10)) ?? []

            await MainActor.run {
                // 清空统计（统计数据由 Service 管理）
                statistics = []
                recentHistory = history
                isLoading = false
            }
        }
    }

    private func getDiskInfo(for disk: DiskConfig) -> (total: Int64, available: Int64, used: Int64)? {
        return diskManager.getDiskInfo(at: disk.mountPath)
    }

    private func setupProgressListener() {
        // 通过 ServiceClient 设置进度监听
        serviceClient.progressDelegate = progressListener
    }

    private func updateFromProgress(_ progress: ServiceSyncProgressInfo) {
        isSyncing = progress.status == .inProgress
        syncProgress = progress.progress
        syncStatusMessage = progress.currentFile ?? progress.phaseText
        isPaused = progress.isPaused
        currentSyncPhaseText = progress.phaseText

        // 如果同步完成，刷新数据
        if progress.status == .completed || progress.status == .failed {
            loadData()
        }
    }

    private func handleStatusChange(_ change: SyncStatusChange) {
        switch change.status {
        case .inProgress:
            isSyncing = true
            isPaused = false
        case .completed:
            isSyncing = false
            isPaused = false
            loadData()  // 刷新历史记录
        case .failed:
            isSyncing = false
            isPaused = false
            if let message = change.message {
                syncStatusMessage = message
            }
            loadData()
        case .cancelled:
            isSyncing = false
            isPaused = false
        case .paused:
            isPaused = true
        default:
            break
        }
    }
}

// MARK: - 同步进度监听器

struct SyncStatusChange: Equatable {
    let syncPairId: String
    let status: SyncStatus
    let message: String?
}

/// 从服务端接收的同步进度简化数据
struct ServiceSyncProgressInfo: Equatable {
    var syncPairId: String
    var status: SyncStatus
    var totalFiles: Int
    var processedFiles: Int
    var totalBytes: Int64
    var processedBytes: Int64
    var currentFile: String?
    var phaseText: String
    var isPaused: Bool

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(processedBytes) / Double(totalBytes)
    }
}

class SyncProgressListener: ObservableObject, SyncProgressDelegate {
    @Published var currentProgress: ServiceSyncProgressInfo?
    @Published var lastStatusChange: SyncStatusChange?
    @Published var isServiceReady = false

    func syncProgressDidUpdate(_ progress: SyncProgressData) {
        DispatchQueue.main.async {
            self.currentProgress = ServiceSyncProgressInfo(
                syncPairId: progress.syncPairId,
                status: progress.status,
                totalFiles: progress.totalFiles,
                processedFiles: progress.processedFiles,
                totalBytes: progress.totalBytes,
                processedBytes: progress.processedBytes,
                currentFile: progress.currentFile,
                phaseText: progress.phase.description,
                isPaused: progress.phase == .paused
            )
        }
    }

    func syncStatusDidChange(syncPairId: String, status: SyncStatus, message: String?) {
        DispatchQueue.main.async {
            self.lastStatusChange = SyncStatusChange(syncPairId: syncPairId, status: status, message: message)
        }
    }

    func serviceDidBecomeReady() {
        DispatchQueue.main.async {
            self.isServiceReady = true
        }
    }

    func configDidUpdate() {
        // 配置更新时可以触发刷新
        Logger.shared.info("收到配置更新通知")
    }
}

// MARK: - Disk Status Card

struct DiskStatusCard: View {
    let disk: DiskConfig
    let isConnected: Bool
    let diskInfo: (total: Int64, available: Int64, used: Int64)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isConnected ? "externaldrive.fill" : "externaldrive")
                    .foregroundColor(isConnected ? .green : .gray)

                Text(disk.name)
                    .font(.headline)

                Spacer()

                Circle()
                    .fill(isConnected ? .green : .gray)
                    .frame(width: 8, height: 8)
            }

            if isConnected, let info = diskInfo {
                StorageBar(
                    used: info.used,
                    total: info.total,
                    showLabels: false
                )
                .frame(height: 8)

                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: info.available, countStyle: .file)) " + "dashboard.available".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(ByteCountFormatter.string(fromByteCount: info.total, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(isConnected ? "dashboard.loading".localized : "dashboard.notConnected".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Recent Activity Row

struct RecentActivityRow: View {
    let history: SyncHistory

    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: history.startedAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: history.status == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(history.status == .completed ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(history.syncPairId)
                    .font(.subheadline)

                Text(formattedStartTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(history.filesCount) " + "dashboard.files".localized)
                    .font(.caption)

                Text(ByteCountFormatter.string(fromByteCount: history.totalSize, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Previews

#if DEBUG
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView(config: .constant(AppConfig()))
            .frame(width: 600, height: 700)
    }
}
#endif
