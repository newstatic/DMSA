import SwiftUI

/// 同步历史全量查询页面
struct SyncHistoryPage: View {
    @ObservedObject private var stateManager = StateManager.shared
    private let serviceClient = ServiceClient.shared

    enum HistoryTab: String, CaseIterable {
        case syncHistory
        case fileRecords

        var title: String {
            switch self {
            case .syncHistory: return "syncHistory.tab.tasks".localized
            case .fileRecords: return "syncHistory.tab.files".localized
            }
        }

        var icon: String {
            switch self {
            case .syncHistory: return "clock.arrow.circlepath"
            case .fileRecords: return "doc.text"
            }
        }
    }

    @State private var histories: [SyncHistory] = []
    @State private var fileRecords: [SyncFileRecord] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasMoreFileRecords = true
    @State private var selectedSyncPairId: String? = nil
    @State private var searchText = ""
    @State private var selectedTab: HistoryTab = .fileRecords

    private let pageSize = 50

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarSection

            Divider()

            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch selectedTab {
                case .syncHistory:
                    if filteredHistories.isEmpty {
                        emptyView(icon: "clock.arrow.circlepath", text: "syncHistory.empty".localized)
                    } else {
                        historyList
                    }
                case .fileRecords:
                    if filteredFileRecords.isEmpty {
                        emptyView(icon: "doc.text", text: "dashboard.fileHistory.empty".localized)
                    } else {
                        fileRecordsList
                    }
                }
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { loadData() }
    }

    // MARK: - Toolbar

    private var toolbarSection: some View {
        HStack(spacing: 12) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(HistoryTab.allCases, id: \.self) { tab in
                    Label(tab.title, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            // SyncPair filter
            Picker("syncHistory.filter.syncPair".localized, selection: $selectedSyncPairId) {
                Text("syncHistory.filter.all".localized).tag(nil as String?)
                ForEach(stateManager.syncPairs, id: \.id) { pair in
                    Text(pair.name).tag(pair.id as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)

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

    private var filteredFileRecords: [SyncFileRecord] {
        // 排除淘汰记录 (status 3=淘汰成功, 4=淘汰失败)
        var result = fileRecords.filter { $0.status != 3 && $0.status != 4 }
        if let pairId = selectedSyncPairId {
            result = result.filter { $0.syncPairId == pairId }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.virtualPath.localizedCaseInsensitiveContains(searchText) ||
                $0.fileName.localizedCaseInsensitiveContains(searchText)
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

    private var fileRecordsList: some View {
        List {
            ForEach(filteredFileRecords) { record in
                FileRecordRow(record: record)
                    .onAppear {
                        // 滚动到倒数第5条时加载更多
                        if record.id == filteredFileRecords.dropLast(min(5, filteredFileRecords.count)).last?.id {
                            loadMoreFileRecords()
                        }
                    }
            }

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("syncHistory.loadingMore".localized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func emptyView(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text(text)
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func loadData() {
        isLoading = true
        Task {
            let historyData = (try? await serviceClient.getSyncHistory(limit: 500)) ?? []
            let fileData = (try? await serviceClient.getAllSyncFileRecords(limit: pageSize, offset: 0)) ?? []
            await MainActor.run {
                histories = historyData
                fileRecords = fileData
                hasMoreFileRecords = fileData.count >= pageSize
                isLoading = false
            }
        }
    }

    private func loadMoreFileRecords() {
        guard !isLoadingMore, hasMoreFileRecords else { return }
        isLoadingMore = true
        let currentOffset = fileRecords.count

        Task {
            let moreData = (try? await serviceClient.getAllSyncFileRecords(limit: pageSize, offset: currentOffset)) ?? []
            await MainActor.run {
                fileRecords.append(contentsOf: moreData)
                hasMoreFileRecords = moreData.count >= pageSize
                isLoadingMore = false
            }
        }
    }
}

// MARK: - File Record Row

struct FileRecordRow: View {
    let record: SyncFileRecord

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: record.syncedAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.fileName)
                    .font(.body)
                    .lineLimit(1)

                Text(record.virtualPath)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.statusDescription)
                    .font(.caption)
                    .foregroundColor(statusColor)

                HStack(spacing: 4) {
                    Text(ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file))
                    Text("·")
                    Text(formattedTime)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch record.status {
        case 0: return "checkmark.circle.fill"
        case 1: return "xmark.circle.fill"
        case 2: return "arrow.right.circle.fill"
        case 3: return "trash.circle.fill"
        case 4: return "exclamationmark.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case 0: return .green
        case 1: return .red
        case 2: return .orange
        case 3: return .blue
        case 4: return .red
        default: return .gray
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
