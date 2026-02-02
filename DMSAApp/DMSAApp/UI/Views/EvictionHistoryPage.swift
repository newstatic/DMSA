import SwiftUI

/// Eviction history full query page
struct EvictionHistoryPage: View {
    @ObservedObject private var stateManager = StateManager.shared
    private let serviceClient = ServiceClient.shared

    @State private var records: [SyncFileRecord] = []
    @State private var isLoading = false
    @State private var filterStatus: FilterOption = .all
    @State private var searchText = ""

    enum FilterOption: String, CaseIterable {
        case all = "all"
        case evictedSuccess = "evictedSuccess"
        case evictedFailed = "evictedFailed"

        var title: String {
            switch self {
            case .all: return "syncHistory.filter.all".localized
            case .evictedSuccess: return "eviction.status.success".localized
            case .evictedFailed: return "eviction.status.failed".localized
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarSection

            Divider()

            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredRecords.isEmpty {
                emptyView
            } else {
                recordList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { loadData() }
    }

    // MARK: - Toolbar

    private var toolbarSection: some View {
        HStack(spacing: 12) {
            // Filter
            Picker("eviction.filter".localized, selection: $filterStatus) {
                ForEach(FilterOption.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            Spacer()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("common.search".localized, text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            // Refresh
            Button(action: loadData) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Record List

    private var filteredRecords: [SyncFileRecord] {
        var result = records.filter { $0.isEviction }
        switch filterStatus {
        case .all: break
        case .evictedSuccess: result = result.filter { $0.status == 3 }
        case .evictedFailed: result = result.filter { $0.status == 4 }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.virtualPath.localizedCaseInsensitiveContains(searchText) ||
                $0.fileName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var recordList: some View {
        List {
            // Summary
            summaryRow

            ForEach(filteredRecords) { record in
                EvictionRecordRow(record: record)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var summaryRow: some View {
        HStack(spacing: 20) {
            SummaryChip(
                title: "eviction.summary.total".localized,
                value: "\(filteredRecords.count)",
                color: .blue
            )
            SummaryChip(
                title: "eviction.summary.freed".localized,
                value: ByteCountFormatter.string(fromByteCount: filteredRecords.filter { $0.isSuccess }.reduce(0) { $0 + $1.fileSize }, countStyle: .file),
                color: .green
            )
            SummaryChip(
                title: "eviction.summary.failed".localized,
                value: "\(filteredRecords.filter { !$0.isSuccess }.count)",
                color: .red
            )
        }
        .padding(.vertical, 4)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("eviction.empty".localized)
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func loadData() {
        isLoading = true
        Task {
            let data = (try? await serviceClient.getAllSyncFileRecords(limit: 500)) ?? []
            await MainActor.run {
                records = data
                isLoading = false
            }
        }
    }
}

// MARK: - Eviction Record Row

struct EvictionRecordRow: View {
    let record: SyncFileRecord

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: statusIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(statusColor)
            }

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(record.fileName)
                    .font(.body)
                    .lineLimit(1)

                Text(record.virtualPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let error = record.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.statusDescription)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(statusColor)

                Text(ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(formattedTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: record.syncedAt)
    }

    private var statusIcon: String {
        record.isSuccess ? "trash.circle.fill" : "exclamationmark.circle.fill"
    }

    private var statusColor: Color {
        record.isSuccess ? .blue : .red
    }
}

// MARK: - Summary Chip

struct SummaryChip: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 80)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}
