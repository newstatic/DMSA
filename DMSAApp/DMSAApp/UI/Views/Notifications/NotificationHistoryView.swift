import SwiftUI

/// Notification history view embedded in main window
struct NotificationHistoryView: View {
    @State private var records: [NotificationRecord] = []
    @State private var typeFilter: String = ""
    @State private var searchText: String = ""
    @State private var showClearConfirmation: Bool = false
    @State private var selectedRecord: NotificationRecord?

    private let databaseManager = DatabaseManager.shared

    private var filteredRecords: [NotificationRecord] {
        records.filter { record in
            // Type filter
            if !typeFilter.isEmpty && record.type != typeFilter {
                return false
            }

            // Search filter
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                return record.title.lowercased().contains(searchLower) ||
                       record.body.lowercased().contains(searchLower)
            }

            return true
        }
    }

    private var groupedRecords: [(String, [NotificationRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredRecords) { record -> String in
            if calendar.isDateInToday(record.createdAt) {
                return L10n.History.today
            } else if calendar.isDateInYesterday(record.createdAt) {
                return L10n.History.yesterday
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.string(from: record.createdAt)
            }
        }
        return grouped.sorted { ($0.value.first?.createdAt ?? Date()) > ($1.value.first?.createdAt ?? Date()) }
    }

    private var uniqueTypes: [String] {
        Array(Set(records.map { $0.type })).sorted()
    }

    private var unreadCount: Int {
        records.filter { !$0.isRead }.count
    }

    var body: some View {
        SettingsContentView(title: "settings.notificationHistory".localized) {
            VStack(spacing: 0) {
                // Toolbar
                toolbarView
                    .padding(.bottom, 12)

                Divider()

                // Content
                if filteredRecords.isEmpty {
                    emptyStateView
                        .frame(minHeight: 200)
                } else {
                    recordsList
                }

                Divider()

                // Footer
                footerView
                    .padding(.top, 12)
            }
        }
        .onAppear {
            loadRecords()
        }
        .sheet(item: $selectedRecord) { record in
            NotificationDetailView(record: record) {
                // Mark as read when detail view is dismissed
                databaseManager.markNotificationAsRead(record.id)
                loadRecords()
            }
        }
        .alert(isPresented: $showClearConfirmation) {
            Alert(
                title: Text("notifications.clearHistory".localized),
                message: Text("notifications.clearHistoryConfirm".localized),
                primaryButton: .destructive(Text(L10n.Common.delete)) {
                    databaseManager.clearAllNotificationRecords()
                    records = []
                },
                secondaryButton: .cancel(Text(L10n.Common.cancel))
            )
        }
    }

    private var toolbarView: some View {
        HStack(spacing: 12) {
            // Type filter
            Picker("notifications.allTypes".localized, selection: $typeFilter) {
                Text("notifications.allTypes".localized).tag("")
                ForEach(uniqueTypes, id: \.self) { type in
                    Text(notificationTypeDisplayName(type)).tag(type)
                }
            }
            .frame(width: 150)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(L10n.History.search, text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(.textBackgroundColor))
            .cornerRadius(6)

            Spacer()

            // Unread badge
            if unreadCount > 0 {
                Text("notifications.unread".localized(with: unreadCount))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            // Mark all read button
            Button {
                databaseManager.markAllNotificationsAsRead()
                loadRecords()
            } label: {
                Label("notifications.markAllRead".localized, systemImage: "checkmark.circle")
            }
            .disabled(unreadCount == 0)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("notifications.noRecords".localized)
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
                            NotificationRecordRow(record: record)
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

    private var footerView: some View {
        HStack {
            // Stats
            Text("notifications.totalCount".localized(with: records.count))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Actions
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("notifications.clearHistory".localized, systemImage: "trash")
            }
            .disabled(records.isEmpty)
        }
    }

    private func loadRecords() {
        records = databaseManager.getAllNotificationRecords()
    }

    private func notificationTypeDisplayName(_ type: String) -> String {
        switch type {
        case "sync_completed": return L10n.Sync.completed
        case "sync_failed": return L10n.Sync.failed
        case "disk_connected": return L10n.Disk.connected
        case "disk_disconnected": return L10n.Disk.disconnected
        case "cache_warning": return "notification.type.cacheWarning".localized
        case "error": return L10n.Common.error
        case "sync_started": return "notification.type.syncStarted".localized
        default: return type
        }
    }
}

/// A single notification record row
struct NotificationRecordRow: View {
    let record: NotificationRecord

    private var typeColor: Color {
        switch record.type {
        case "sync_completed": return .green
        case "sync_failed", "error": return .red
        case "disk_connected": return .blue
        case "disk_disconnected": return .gray
        case "cache_warning": return .orange
        case "sync_started": return .blue
        default: return .primary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Unread indicator
            Circle()
                .fill(record.isRead ? Color.clear : Color.blue)
                .frame(width: 8, height: 8)

            // Type icon
            Image(systemName: record.typeIcon)
                .foregroundColor(typeColor)
                .font(.title3)
                .frame(width: 24)

            // Time
            Text(formatTime(record.createdAt))
                .font(.body)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.body)
                    .fontWeight(record.isRead ? .regular : .medium)
                    .lineLimit(1)

                Text(record.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Action indicator
            if record.actionType != .none {
                Image(systemName: record.actionType.icon)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(10)
        .background(record.isRead ? Color(.controlBackgroundColor) : Color.blue.opacity(0.05))
        .cornerRadius(6)
        .contentShape(Rectangle())
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

/// Notification detail view shown as sheet
struct NotificationDetailView: View {
    let record: NotificationRecord
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: record.typeIcon)
                    .foregroundColor(typeColor)
                    .font(.title2)

                Text("notifications.detail.title".localized)
                    .font(.headline)

                Spacer()

                Button(L10n.Common.close) {
                    onDismiss()
                    dismiss()
                }
            }

            Divider()

            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("notifications.detail.notificationTitle".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(record.title)
                    .font(.body)
                    .fontWeight(.medium)
            }

            // Body
            VStack(alignment: .leading, spacing: 4) {
                Text("notifications.detail.content".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(record.body)
                    .font(.body)
            }

            // Time
            HStack {
                Text("notifications.detail.time".localized)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatDateTime(record.createdAt))
            }

            // Type
            HStack {
                Text("notifications.detail.type".localized)
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: record.typeIcon)
                    Text(notificationTypeDisplayName(record.type))
                }
                .foregroundColor(typeColor)
            }

            // User info
            if !record.userInfo.isEmpty {
                Divider()

                Text("notifications.detail.additionalInfo".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                ForEach(Array(record.userInfo.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(record.userInfo[key] ?? "")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption)
                }
            }

            Spacer()

            // Action button
            if record.actionType != .none {
                Divider()

                Button {
                    performAction()
                    onDismiss()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: record.actionType.icon)
                        Text(record.actionType.displayName)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400, height: 450)
    }

    private var typeColor: Color {
        switch record.type {
        case "sync_completed": return .green
        case "sync_failed", "error": return .red
        case "disk_connected": return .blue
        case "disk_disconnected": return .gray
        case "cache_warning": return .orange
        case "sync_started": return .blue
        default: return .primary
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func notificationTypeDisplayName(_ type: String) -> String {
        switch type {
        case "sync_completed": return L10n.Sync.completed
        case "sync_failed": return L10n.Sync.failed
        case "disk_connected": return L10n.Disk.connected
        case "disk_disconnected": return L10n.Disk.disconnected
        case "cache_warning": return "notification.type.cacheWarning".localized
        case "error": return L10n.Common.error
        case "sync_started": return "notification.type.syncStarted".localized
        default: return type
        }
    }

    private func performAction() {
        // Post notification to navigate to the appropriate tab
        switch record.actionType {
        case .openSettings:
            NotificationCenter.default.post(name: .selectMainTab, object: nil, userInfo: ["tab": MainView.MainTab.general])
        case .openDiskSettings:
            NotificationCenter.default.post(name: .selectMainTab, object: nil, userInfo: ["tab": MainView.MainTab.disks])
        case .openSyncPairSettings:
            NotificationCenter.default.post(name: .selectMainTab, object: nil, userInfo: ["tab": MainView.MainTab.syncPairs])
        case .openLogs:
            NotificationCenter.default.post(name: .selectMainTab, object: nil, userInfo: ["tab": MainView.MainTab.logs])
        case .openHistory:
            NotificationCenter.default.post(name: .selectMainTab, object: nil, userInfo: ["tab": MainView.MainTab.history])
        case .none:
            break
        }
    }
}

// MARK: - Previews

#if DEBUG
struct NotificationHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationHistoryView()
            .frame(width: 700, height: 500)
    }
}
#endif
