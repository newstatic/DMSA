import SwiftUI

/// 同步历史全量查询页面
struct SyncHistoryPage: View {
    @ObservedObject private var stateManager = StateManager.shared
    private let serviceClient = ServiceClient.shared

    @State private var histories: [SyncHistory] = []
    @State private var isLoading = false
    @State private var selectedSyncPairId: String? = nil
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarSection

            Divider()

            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredHistories.isEmpty {
                emptyView
            } else {
                historyList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { loadData() }
    }

    // MARK: - Toolbar

    private var toolbarSection: some View {
        HStack(spacing: 12) {
            // SyncPair filter
            Picker("syncHistory.filter.syncPair".localized, selection: $selectedSyncPairId) {
                Text("syncHistory.filter.all".localized).tag(nil as String?)
                ForEach(stateManager.syncPairs, id: \.id) { pair in
                    Text(pair.name).tag(pair.id as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)

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

    // MARK: - History List

    private var filteredHistories: [SyncHistory] {
        var result = histories
        if let pairId = selectedSyncPairId {
            result = result.filter { $0.syncPairId == pairId }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.syncPairId.localizedCaseInsensitiveContains(searchText) ||
                ($0.errorMessage?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return result
    }

    private var historyList: some View {
        List {
            ForEach(filteredHistories) { history in
                SyncHistoryDetailRow(history: history)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("syncHistory.empty".localized)
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func loadData() {
        isLoading = true
        Task {
            let data = (try? await serviceClient.getSyncHistory(limit: 500)) ?? []
            await MainActor.run {
                histories = data
                isLoading = false
            }
        }
    }
}

// MARK: - Sync History Row

struct SyncHistoryDetailRow: View {
    let history: SyncHistory

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

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(history.syncPairId)
                        .font(.body)
                        .fontWeight(.medium)

                    if !history.diskId.isEmpty {
                        Text("(\(history.diskId))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(formattedStartTime)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)
                    Text(history.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = history.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: 2) {
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(statusColor)

                Text("\(history.filesCount) \("common.files".localized)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(history.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: history.startedAt)
    }

    private var statusText: String {
        switch history.status {
        case .completed: return "common.success".localized
        case .failed: return "common.error".localized
        case .cancelled: return "sync.status.cancelled".localized
        case .inProgress: return "sync.status.syncing".localized
        default: return "common.unknown".localized
        }
    }

    private var statusIcon: String {
        switch history.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        case .inProgress: return "arrow.clockwise"
        default: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch history.status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .inProgress: return .blue
        default: return .gray
        }
    }
}
