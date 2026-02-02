import SwiftUI

// MARK: - Dashboard View

/// 仪表盘视图 - 主页面，显示状态概览和快速操作
struct DashboardView: View {
    @Binding var config: AppConfig
    @ObservedObject private var stateManager = StateManager.shared

    // Services
    private let serviceClient = ServiceClient.shared
    private let diskManager = DiskManager.shared

    // Local state
    @State private var recentHistory: [SyncHistory] = []
    @State private var isLoading = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Status Banner
                statusBannerSection

                // Quick Actions
                quickActionsSection

                // Storage Overview
                storageOverviewSection

                // Recent Activity
                recentActivitySection

                // (文件同步记录已移至同步历史页面)
            }
            .padding(32)
            .frame(maxWidth: 800)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadData()
        }
        .onChange(of: stateManager.syncStatus) { _ in
            // 同步完成时刷新历史
            if stateManager.syncStatus == .ready {
                loadData()
            }
        }
    }

    // MARK: - Status Banner Section

    private var isSyncing: Bool {
        stateManager.syncStatus == .syncing
    }

    private var isPaused: Bool {
        stateManager.syncStatus == .paused
    }

    private var syncProgress: Double {
        stateManager.syncProgressValue
    }

    private var statusBannerSection: some View {
        HStack(spacing: 20) {
            // Status Ring
            StatusRing(
                size: 80,
                icon: statusIcon,
                color: statusColor,
                progress: isSyncing ? syncProgress : 1.0,
                isAnimating: isSyncing && !isPaused
            )

            // Status Text
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.title)
                    .fontWeight(.semibold)

                Text(statusSubtitle)
                    .font(.body)
                    .foregroundColor(.secondary)

                Spacer()
                    .frame(height: 8)

                // Stat chips
                HStack(spacing: 16) {
                    StatChip(
                        icon: "doc",
                        value: "\(stateManager.statistics.totalFiles)",
                        label: "dashboard.chip.files".localized
                    )

                    StatChip(
                        icon: "externaldrive",
                        value: "\(connectedDiskCount)/\(config.disks.count)",
                        label: "dashboard.chip.disks".localized
                    )

                    if let lastSync = lastSyncTime {
                        StatChip(
                            icon: "clock",
                            value: formatRelativeTime(lastSync),
                            label: "dashboard.chip.lastSync".localized
                        )
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "dashboard.quickActions".localized)

            HStack(spacing: 12) {
                ActionCard(
                    icon: "arrow.clockwise",
                    title: "dashboard.action.syncNow".localized,
                    shortcut: "⌘S",
                    isEnabled: canStartSync,
                    action: startSync
                )

                ActionCard(
                    icon: "externaldrive.badge.plus",
                    title: "dashboard.action.addDisk".localized,
                    action: navigateToDisks
                )

                ActionCard(
                    icon: "folder",
                    title: "dashboard.action.openDownloads".localized,
                    action: openDownloadsFolder
                )
            }
        }
    }

    // MARK: - Storage Overview Section

    private var storageOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "dashboard.storage".localized)

            HStack(spacing: 16) {
                // Local cache storage
                if let localInfo = getLocalStorageInfo() {
                    StorageCard(
                        title: "dashboard.storage.localCache".localized,
                        icon: "internaldrive",
                        used: localInfo.used,
                        total: localInfo.total,
                        color: .blue
                    )
                }

                // External disk storage (show first connected disk)
                if let disk = firstConnectedDisk,
                   let diskInfo = diskManager.getDiskInfo(at: disk.mountPath) {
                    StorageCard(
                        title: disk.name,
                        icon: "externaldrive",
                        used: diskInfo.used,
                        total: diskInfo.total,
                        color: .green
                    )
                }
            }
        }
    }

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "dashboard.recentActivity".localized,
                actionTitle: "dashboard.viewAll".localized,
                action: navigateToSyncHistory
            )

            if stateManager.recentActivities.isEmpty {
                EmptyActivityView()
            } else {
                VStack(spacing: 0) {
                    ForEach(stateManager.recentActivities) { activity in
                        ActivityRecordRow(activity: activity)

                        if activity.id != stateManager.recentActivities.last?.id {
                            Divider()
                                .padding(.leading, 52)
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
        // 优先检查服务状态
        if !stateManager.isReady {
            switch stateManager.syncStatus {
            case .starting:
                return "gear"
            case .indexing:
                return "doc.text.magnifyingglass"
            case .reconnecting:
                return "arrow.triangle.2.circlepath"
            case .serviceUnavailable:
                return "xmark.circle.fill"
            default:
                return "ellipsis.circle"
            }
        }
        if isSyncing {
            return isPaused ? "pause.circle.fill" : "arrow.clockwise"
        }
        if stateManager.conflictCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if !hasConnectedDisk {
            return "xmark.circle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        // 优先检查服务状态
        if !stateManager.isReady {
            switch stateManager.syncStatus {
            case .starting:
                return .yellow
            case .indexing:
                return .orange
            case .reconnecting:
                return .orange
            case .serviceUnavailable:
                return .gray
            default:
                return .gray
            }
        }
        if isSyncing {
            return isPaused ? .orange : .blue
        }
        if stateManager.conflictCount > 0 {
            return .orange
        }
        if !hasConnectedDisk {
            return .gray
        }
        return .green
    }

    /// 是否有磁盘连接 - 使用直接文件系统检查避免缓存问题
    private var hasConnectedDisk: Bool {
        diskManager.isAnyDiskConnected(from: config.disks)
    }

    private var statusTitle: String {
        // 优先检查服务状态
        if !stateManager.isReady {
            switch stateManager.syncStatus {
            case .starting:
                return "dashboard.status.starting".localized
            case .indexing:
                return "dashboard.status.indexing".localized
            case .reconnecting:
                return "dashboard.status.reconnecting".localized
            case .serviceUnavailable:
                return "dashboard.status.serviceUnavailable".localized
            default:
                return "dashboard.status.preparing".localized
            }
        }
        if isSyncing {
            return isPaused
                ? "dashboard.status.paused".localized
                : "dashboard.status.syncing".localized
        }
        if stateManager.conflictCount > 0 {
            return "dashboard.status.hasConflicts".localized
        }
        if !hasConnectedDisk {
            return "dashboard.status.noDisk".localized
        }
        return "dashboard.status.allGood".localized
    }

    private var statusSubtitle: String {
        // 优先检查服务状态
        if !stateManager.isReady {
            switch stateManager.syncStatus {
            case .starting:
                return "dashboard.status.startingDesc".localized
            case .indexing:
                return "dashboard.status.indexingDesc".localized
            case .reconnecting:
                return "dashboard.status.reconnectingDesc".localized
            case .serviceUnavailable:
                return "dashboard.status.serviceUnavailableDesc".localized
            default:
                return "dashboard.status.preparingDesc".localized
            }
        }
        if isSyncing {
            let progress = Int(syncProgress * 100)
            return String(format: "dashboard.status.progress".localized, progress)
        }
        if stateManager.conflictCount > 0 {
            return String(format: "dashboard.status.conflictsCount".localized, stateManager.conflictCount)
        }
        if !hasConnectedDisk {
            return "dashboard.status.connectDisk".localized
        }
        return "dashboard.status.allSynced".localized
    }

    private var canStartSync: Bool {
        let ready = stateManager.isReady
        let hasDisk = hasConnectedDisk
        let hasPairs = !config.syncPairs.isEmpty
        let notSyncing = !isSyncing
        let result = ready && hasDisk && hasPairs && notSyncing

        Logger.shared.debug("[DashboardView] canStartSync: \(result) (isReady=\(ready), hasDisk=\(hasDisk), hasPairs=\(hasPairs), notSyncing=\(notSyncing))")
        return result
    }

    private var firstConnectedDisk: DiskConfig? {
        config.disks.first { diskManager.isDiskConnected($0.id) }
    }

    private var connectedDiskCount: Int {
        diskManager.connectedDiskCount(from: config.disks)
    }

    private var lastSyncTime: Date? {
        stateManager.recentActivities.first(where: { $0.type == .syncCompleted })?.timestamp ?? recentHistory.first?.startedAt
    }

    // MARK: - Actions

    private func startSync() {
        guard canStartSync else { return }

        Task {
            do {
                try await serviceClient.updateConfig(config)
                try await serviceClient.syncAll()
            } catch {
                Logger.shared.error("Sync failed: \(error.localizedDescription)")
            }
        }
    }

    private func navigateToDisks() {
        NotificationCenter.default.post(
            name: .selectMainTab,
            object: nil,
            userInfo: ["tab": MainView.MainTab.disks]
        )
    }

    private func navigateToLogs() {
        NotificationCenter.default.post(
            name: .selectMainTab,
            object: nil,
            userInfo: ["tab": MainView.MainTab.logs]
        )
    }

    private func navigateToSyncHistory() {
        NotificationCenter.default.post(
            name: .selectMainTab,
            object: nil,
            userInfo: ["tab": MainView.MainTab.syncHistory]
        )
    }

    private func openDownloadsFolder() {
        let downloadsPath = NSString(string: "~/Downloads").expandingTildeInPath
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: downloadsPath)
    }

    private func loadData() {
        isLoading = true

        Task {
            let history = (try? await serviceClient.getSyncHistory(limit: 10)) ?? []

            await MainActor.run {
                recentHistory = history
                isLoading = false
            }
        }
    }

    // MARK: - Helper Methods

    private func getLocalStorageInfo() -> (used: Int64, total: Int64)? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: homeDir.path)
            let total = (attrs[.systemSize] as? Int64) ?? 0
            let free = (attrs[.systemFreeSize] as? Int64) ?? 0
            return (total - free, total)
        } catch {
            return nil
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "dashboard.time.now".localized
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}

// MARK: - Sync Progress Listener

struct SyncStatusChange: Equatable {
    let syncPairId: String
    let status: SyncStatus
    let message: String?
}

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
    var speed: Int64

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
                isPaused: progress.phase == .paused,
                speed: progress.speed
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
        Logger.shared.info("Config update notification received")
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
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(history.syncPairId)
                    .font(.body)
                    .lineLimit(1)

                Text(formattedStartTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(history.filesCount) files")
                    .font(.caption)

                Text(ByteCountFormatter.string(fromByteCount: history.totalSize, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statusIcon: String {
        history.status == .completed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var statusColor: Color {
        history.status == .completed ? .green : .red
    }
}

// MARK: - Activity Record Row

struct ActivityRecordRow: View {
    let activity: ActivityRecord

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: activity.timestamp)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(activityColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: activity.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(activityColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.body)
                    .lineLimit(1)

                if let detail = activity.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedTime)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let count = activity.filesCount {
                    Text("\(count) \("common.files".localized)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var activityColor: Color {
        switch activity.colorName {
        case "green": return .green
        case "red": return .red
        case "blue": return .blue
        case "orange": return .orange
        case "gray": return .gray
        default: return .secondary
        }
    }
}

// MARK: - Settings Content View Wrapper

struct SettingsContentView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle(title)
    }
}

// MARK: - Disk Status Card (Legacy support)

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

                StatusDot(color: isConnected ? .green : .gray)
            }

            if isConnected, let info = diskInfo {
                StorageBar(
                    used: info.used,
                    total: info.total,
                    showLabels: false
                )
                .frame(height: 8)

                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: info.available, countStyle: .file)) available")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(ByteCountFormatter.string(fromByteCount: info.total, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(isConnected ? "Loading..." : "Not connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Previews

#if DEBUG
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView(config: .constant(AppConfig()))
            .frame(width: 700, height: 700)
    }
}
#endif
