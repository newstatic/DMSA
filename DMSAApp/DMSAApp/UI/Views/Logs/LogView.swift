import SwiftUI
import Combine

/// Real-time log view embedded in main window
struct LogView: View {
    @ObservedObject private var logger = Logger.shared
    @State private var levelFilter: Logger.Level?
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true
    @State private var showClearConfirmation: Bool = false

    /// 节流：上次滚动时间
    @State private var lastScrollTime: Date = .distantPast
    /// 节流间隔 (秒)
    private let scrollThrottleInterval: TimeInterval = 0.3

    private var filteredEntries: [LogEntry] {
        logger.filteredEntries(level: levelFilter, searchText: searchText)
    }

    var body: some View {
        SettingsContentView(title: "settings.logs".localized) {
            VStack(spacing: 0) {
                // Toolbar
                toolbarView
                    .padding(.bottom, 12)

                Divider()

                // Log entries list
                logEntriesList
                    .frame(minHeight: 300)

                Divider()

                // Footer
                footerView
                    .padding(.top, 12)
            }
        }
        .alert(isPresented: $showClearConfirmation) {
            Alert(
                title: Text("logs.clearLogs".localized),
                message: Text("logs.clearLogsConfirm".localized),
                primaryButton: .destructive(Text(L10n.Common.delete)) {
                    logger.clearLogFile()
                },
                secondaryButton: .cancel(Text(L10n.Common.cancel))
            )
        }
    }

    private var toolbarView: some View {
        HStack(spacing: 12) {
            // Level filter
            Picker("logs.level".localized, selection: $levelFilter) {
                Text("logs.allLevels".localized).tag(Optional<Logger.Level>.none)
                ForEach(Logger.Level.allCases, id: \.rawValue) { level in
                    Label(level.rawValue, systemImage: level.icon)
                        .tag(Optional<Logger.Level>.some(level))
                }
            }
            .frame(width: 120)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("logs.search".localized, text: $searchText)
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

            // Auto-scroll toggle
            Toggle(isOn: $autoScroll) {
                Label("logs.autoScroll".localized, systemImage: "arrow.down.circle")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private var logEntriesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color(.textBackgroundColor))
            .cornerRadius(6)
            .onChange(of: logger.latestEntries.count) { _ in
                // 节流：避免频繁触发滚动动画
                let now = Date()
                guard autoScroll,
                      now.timeIntervalSince(lastScrollTime) >= scrollThrottleInterval,
                      let lastEntry = filteredEntries.last else {
                    return
                }

                lastScrollTime = now

                // 使用无动画滚动提高性能
                proxy.scrollTo(lastEntry.id, anchor: .bottom)
            }
        }
    }

    private var footerView: some View {
        HStack {
            // Stats
            Text("logs.count".localized(with: filteredEntries.count, logger.latestEntries.count))
                .font(.caption)
                .foregroundColor(.secondary)

            Text("•")
                .foregroundColor(.secondary)

            Text("logs.fileSize".localized(with: logger.getLogFileSize().formattedBytes))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Actions
            Button {
                NSWorkspace.shared.selectFile(logger.logFileLocation.path, inFileViewerRootedAtPath: "")
            } label: {
                Label(L10n.Settings.Advanced.openLogFolder, systemImage: "folder")
            }

            Button {
                copyToClipboard()
            } label: {
                Label(L10n.Common.copy, systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("logs.clearLogs".localized, systemImage: "trash")
            }
            .disabled(logger.latestEntries.isEmpty)
        }
    }

    private func copyToClipboard() {
        let text = filteredEntries.map { $0.formattedMessage }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// A single log entry row
struct LogEntryRow: View {
    let entry: LogEntry

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .primary
        case .warn: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(entry.formattedTimestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            // Level badge
            Text(entry.level.rawValue)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(levelBackground)
                .cornerRadius(3)
                .frame(width: 50, alignment: .center)

            // File:line
            Text("\(entry.file):\(entry.line)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)

            // Message
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(levelColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(entry.level == .error ? Color.red.opacity(0.05) : Color.clear)
    }

    private var levelBackground: Color {
        switch entry.level {
        case .debug: return Color.gray.opacity(0.2)
        case .info: return Color.blue.opacity(0.2)
        case .warn: return Color.orange.opacity(0.2)
        case .error: return Color.red.opacity(0.2)
        }
    }
}

// MARK: - Previews

#if DEBUG
struct LogView_Previews: PreviewProvider {
    static var previews: some View {
        LogView()
            .frame(width: 700, height: 500)
    }
}
#endif
