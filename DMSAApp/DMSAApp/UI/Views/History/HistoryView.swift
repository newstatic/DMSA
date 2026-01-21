import SwiftUI

/// Sync history record model for UI
struct SyncHistoryRecord: Identifiable {
    let id: String
    let timestamp: Date
    let sourcePath: String
    let destinationPath: String
    let diskName: String
    let direction: SyncDirection
    let status: SyncStatus
    let fileCount: Int
    let totalBytes: Int64
    let duration: TimeInterval
    let addedFiles: Int
    let updatedFiles: Int
    let deletedFiles: Int
    let skippedFiles: Int
    let errorMessage: String?
    let rsyncOutput: String?
}

/// History window view
struct HistoryView: View {
    @State private var records: [SyncHistoryRecord] = []
    @State private var selectedRecord: SyncHistoryRecord?
    @State private var diskFilter: String = ""
    @State private var statusFilter: SyncStatus?
    @State private var dateFilter: DateFilter = .last7Days
    @State private var searchText: String = ""
    @State private var showClearConfirmation: Bool = false

    private let databaseManager: DatabaseManager

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

    init(databaseManager: DatabaseManager = DatabaseManager.shared) {
        self.databaseManager = databaseManager
    }

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
        VStack(spacing: 0) {
            // Filters
            filterBar

            Divider()

            // Content
            if filteredRecords.isEmpty {
                emptyStateView
            } else {
                recordsList
            }

            Divider()

            // Stats and actions
            footerBar
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            loadRecords()
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
        .padding()
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
            .padding()
        }
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
        .padding()
    }

    private func loadRecords() {
        // Load from database
        let historyEntries = databaseManager.getAllSyncHistory()
        records = historyEntries.map { entry in
            SyncHistoryRecord(
                id: String(entry.id),
                timestamp: entry.startedAt,
                sourcePath: entry.syncPairId, // Would need to resolve to actual path
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
                rsyncOutput: nil
            )
        }
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "dmsa-history.json"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                encoder.dateEncodingStrategy = .iso8601
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
        databaseManager.clearAllSyncHistory()
        records = []
    }
}

/// A row displaying a sync history record
struct HistoryRowView: View {
    let record: SyncHistoryRecord

    private var statusIcon: String {
        switch record.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        default: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .font(.title3)

            // Time
            Text(formatTime(record.timestamp))
                .font(.body)
                .monospacedDigit()
                .frame(width: 50, alignment: .leading)

            // Path info
            VStack(alignment: .leading, spacing: 2) {
                Text("\(record.sourcePath) → \(record.diskName)")
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if record.status == .completed {
                    Text("\(record.fileCount) \("unit.files".localized) | \(record.totalBytes.formattedBytes) | \(formatDuration(record.duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if record.status == .failed, let error = record.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions for failed records
            if record.status == .failed {
                Button(L10n.History.Detail.viewDetails) {
                    // Show details
                }
                .buttonStyle(.link)

                Button(L10n.Common.retry) {
                    // Retry sync
                }
                .buttonStyle(.link)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
        .contentShape(Rectangle())
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return L10n.Time.seconds(Int(duration))
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

/// History detail view (shown as sheet)
struct HistoryDetailView: View {
    let record: SyncHistoryRecord

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text(L10n.History.Detail.title)
                    .font(.headline)

                Spacer()

                Button(L10n.Common.close) {
                    dismiss()
                }
            }

            Divider()

            // Status
            HStack {
                Text(L10n.History.Detail.status)
                    .foregroundColor(.secondary)
                Spacer()
                statusBadge
            }

            // Time
            HStack {
                Text(L10n.History.Detail.time)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatDateTime(record.timestamp))
            }

            // Duration
            HStack {
                Text(L10n.History.Detail.duration)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatDuration(record.duration))
            }

            Divider()

            // Direction
            HStack {
                Text(L10n.History.Detail.direction)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(record.sourcePath) → \(record.diskName)/\(record.destinationPath)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Disk
            HStack {
                Text(L10n.History.Detail.disk)
                    .foregroundColor(.secondary)
                Spacer()
                Text(record.diskName)
            }

            Divider()

            // Stats
            Text(L10n.History.Detail.stats)
                .font(.subheadline)
                .fontWeight(.medium)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text(L10n.History.Detail.fileCount)
                        .foregroundColor(.secondary)
                    Text("\(record.fileCount)")
                }
                GridRow {
                    Text(L10n.History.Detail.totalSize)
                        .foregroundColor(.secondary)
                    Text(record.totalBytes.formattedBytes)
                }
                GridRow {
                    Text(L10n.History.Detail.added)
                        .foregroundColor(.secondary)
                    Text("\(record.addedFiles)")
                }
                GridRow {
                    Text(L10n.History.Detail.updated)
                        .foregroundColor(.secondary)
                    Text("\(record.updatedFiles)")
                }
                GridRow {
                    Text(L10n.History.Detail.deleted)
                        .foregroundColor(.secondary)
                    Text("\(record.deletedFiles)")
                }
                GridRow {
                    Text(L10n.History.Detail.skipped)
                        .foregroundColor(.secondary)
                    Text("\(record.skippedFiles)")
                }
            }

            // rsync output
            if let output = record.rsyncOutput {
                Divider()

                Text(L10n.History.Detail.rsyncOutput)
                    .font(.subheadline)
                    .fontWeight(.medium)

                ScrollView {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
                .frame(maxHeight: 150)

                HStack {
                    Spacer()
                    Button(L10n.History.Detail.copyLog) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output, forType: .string)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 500, height: 550)
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: record.status.icon)
            Text(record.status.displayName)
        }
        .foregroundColor(statusColor)
    }

    private var statusColor: Color {
        switch record.status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        default: return .gray
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return L10n.Time.seconds(Int(duration))
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Window Controller

class HistoryWindowController {
    private var window: NSWindow?

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = HistoryView()
        let hostingController = NSHostingController(rootView: historyView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = L10n.History.title
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 700, height: 500))
        newWindow.minSize = NSSize(width: 500, height: 300)
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
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
            .frame(width: 700, height: 500)
    }
}
#endif
