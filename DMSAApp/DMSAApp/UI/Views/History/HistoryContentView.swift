import SwiftUI

/// History content view for embedding in main window
/// This is a simplified version of HistoryView without window wrapper
/// v4.6: Uses ServiceClient XPC for all data operations
struct HistoryContentView: View {
    @State private var records: [SyncHistoryRecord] = []
    @State private var selectedRecord: SyncHistoryRecord?
    @State private var diskFilter: String = ""
    @State private var statusFilter: SyncStatus?
    @State private var dateFilter: DateFilter = .last7Days
    @State private var searchText: String = ""
    @State private var showClearConfirmation: Bool = false
    @State private var isLoading: Bool = false

    enum DateFilter: String, CaseIterable {
        case last7Days
        case last30Days
        case allTime

        var title: String {
            switch self {
            case .last7Days: return L10n.History.last7Days
            case .last30Days: return L10n.History.last30Days
            case .allTime: return L10n.History.allTime
            }
        }

        var startDate: Date? {
            switch self {
            case .last7Days: return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .last30Days: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
            case .allTime: return nil
            }
        }
    }

    init() {}

    private var filteredRecords: [SyncHistoryRecord] {
        records.filter { record in
            // Disk filter
            if !diskFilter.isEmpty && record.diskName != diskFilter {
                return false
            }

            // Status filter
            if let status = statusFilter, record.status != status {
                return false
            }

            // Date filter
            if let startDate = dateFilter.startDate, record.timestamp < startDate {
                return false
            }

            // Search filter
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                return record.sourcePath.lowercased().contains(searchLower) ||
                       record.diskName.lowercased().contains(searchLower)
            }

            return true
        }
    }

    private var groupedRecords: [(String, [SyncHistoryRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredRecords) { record -> String in
            if calendar.isDateInToday(record.timestamp) {
                return L10n.History.today
            } else if calendar.isDateInYesterday(record.timestamp) {
                return L10n.History.yesterday
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: record.timestamp)
            }
        }
        return grouped.sorted { $0.value.first?.timestamp ?? Date() > $1.value.first?.timestamp ?? Date() }
    }

    private var stats: (total: Int, success: Int, failed: Int, files: Int, bytes: Int64) {
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekRecords = records.filter { $0.timestamp >= weekStart }
        let success = weekRecords.filter { $0.status == .completed }.count
        let failed = weekRecords.filter { $0.status == .failed }.count
        let files = weekRecords.reduce(0) { $0 + $1.fileCount }
        let bytes = weekRecords.reduce(Int64(0)) { $0 + $1.totalBytes }
        return (weekRecords.count, success, failed, files, bytes)
    }

    private var uniqueDisks: [String] {
        Array(Set(records.map { $0.diskName })).sorted()
    }

    var body: some View {
        SettingsContentView(title: "settings.history".localized) {
            VStack(spacing: 0) {
                // Filters
                filterBar
                    .padding(.bottom, 12)

                Divider()

                // Content
                if isLoading {
                    ProgressView()
                        .frame(minHeight: 200)
                } else if filteredRecords.isEmpty {
                    emptyStateView
                        .frame(minHeight: 200)
                } else {
                    recordsList
                }

                Divider()

                // Stats and actions
                footerBar
                    .padding(.top, 12)
            }
        }
        .task {
            await loadRecords()
        }
        .sheet(item: $selectedRecord) { record in
            HistoryDetailView(record: record)
        }
        .alert(isPresented: $showClearConfirmation) {
            Alert(
                title: Text(L10n.History.clearHistory),
                message: Text(L10n.History.clearHistoryConfirm),
                primaryButton: .destructive(Text(L10n.Common.delete)) {
                    clearHistory()
                },
                secondaryButton: .cancel(Text(L10n.Common.cancel))
            )
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Disk filter
            Picker(L10n.History.allDisks, selection: $diskFilter) {
                Text(L10n.History.allDisks).tag("")
                ForEach(uniqueDisks, id: \.self) { disk in
                    Text(disk).tag(disk)
                }
            }
            .frame(width: 150)

            // Status filter
            Picker(L10n.History.allStatus, selection: $statusFilter) {
                Text(L10n.History.allStatus).tag(Optional<SyncStatus>.none)
                Text(L10n.Sync.completed).tag(Optional<SyncStatus>.some(.completed))
                Text(L10n.Sync.failed).tag(Optional<SyncStatus>.some(.failed))
                Text(L10n.Sync.cancelled).tag(Optional<SyncStatus>.some(.cancelled))
            }
            .frame(width: 120)

            // Date filter
            Picker(dateFilter.title, selection: $dateFilter) {
                ForEach(DateFilter.allCases, id: \.rawValue) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .frame(width: 120)

            Spacer()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L10n.History.search, text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
            }
            .padding(6)
            .background(Color(.textBackgroundColor))
            .cornerRadius(6)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(L10n.History.noRecords)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groupedRecords, id: \.0) { group, records in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group)
                            .font(.headline)
                            .foregroundColor(.secondary)

                        ForEach(records) { record in
                            HistoryRowView(record: record)
                                .onTapGesture {
                                    selectedRecord = record
                                }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .frame(minHeight: 200)
    }

    private var footerBar: some View {
        HStack {
            // Stats
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.History.stats(total: stats.total, success: stats.success, failed: stats.failed))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(L10n.History.statsFiles(count: stats.files, size: stats.bytes.formattedBytes))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Actions
            Button(L10n.History.exportHistory) {
                exportHistory()
            }

            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Text(L10n.History.clearHistory)
            }
            .disabled(records.isEmpty)
        }
    }

    private func loadRecords() async {
        isLoading = true
        do {
            // Load from service via XPC
            let historyEntries = try await ServiceClient.shared.getSyncHistory(limit: 500)
            records = historyEntries.map { entry in
                SyncHistoryRecord(
                    id: String(entry.id),
                    timestamp: entry.startedAt,
                    sourcePath: entry.syncPairId,
                    destinationPath: "",
                    diskName: entry.diskId,
                    direction: entry.direction,
                    status: entry.status,
                    fileCount: entry.filesCount,
                    totalBytes: entry.totalSize,
                    duration: entry.duration,
                    addedFiles: 0,
                    updatedFiles: 0,
                    deletedFiles: 0,
                    skippedFiles: 0,
                    errorMessage: entry.errorMessage,
                    syncLog: nil
                )
            }
        } catch {
            Logger.shared.error("加载同步历史失败: \(error)")
            records = []
        }
        isLoading = false
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "dmsa-history.json"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let exportData = filteredRecords.map { record in
                    [
                        "timestamp": ISO8601DateFormatter().string(from: record.timestamp),
                        "source": record.sourcePath,
                        "disk": record.diskName,
                        "status": record.status.displayName,
                        "files": record.fileCount,
                        "bytes": record.totalBytes,
                        "duration": record.duration
                    ] as [String : Any]
                }
                let data = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
                try data.write(to: url)
            } catch {
                // Handle error
            }
        }
    }

    private func clearHistory() {
        // Clear history is now handled by Service
        // For now just clear local state
        records = []
    }
}

// MARK: - Previews

#if DEBUG
struct HistoryContentView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryContentView()
            .frame(width: 600, height: 500)
    }
}
#endif
