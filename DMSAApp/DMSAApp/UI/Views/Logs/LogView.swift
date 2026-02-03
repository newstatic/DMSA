import SwiftUI
import AppKit
import Combine

/// Real-time log view embedded in main window - uses NSTableView for efficient virtualization
struct LogView: View {
    @ObservedObject private var logger = Logger.shared
    @State private var levelFilter: Logger.Level?
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true
    @State private var showClearConfirmation: Bool = false

    var body: some View {
        SettingsContentView(title: "settings.logs".localized) {
            VStack(spacing: 0) {
                // Toolbar
                toolbarView
                    .padding(.bottom, 12)

                Divider()

                // Log entries list - virtualized table
                LogTableView(
                    entries: logger.latestEntries,
                    levelFilter: levelFilter,
                    searchText: searchText,
                    autoScroll: autoScroll
                )
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

    private var footerView: some View {
        HStack {
            // Stats
            Text("logs.count".localized(with: logger.latestEntries.count, logger.latestEntries.count))
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
                Label("logs.openAppLog".localized, systemImage: "doc.text")
            }

            Button {
                let serviceLogPath = Constants.Paths.serviceLog.path
                if FileManager.default.fileExists(atPath: serviceLogPath) {
                    NSWorkspace.shared.selectFile(serviceLogPath, inFileViewerRootedAtPath: "")
                } else {
                    let serviceLogDir = Constants.Paths.serviceLogDir
                    if FileManager.default.fileExists(atPath: serviceLogDir.path) {
                        NSWorkspace.shared.open(serviceLogDir)
                    } else {
                        NSWorkspace.shared.open(Constants.Paths.logs)
                    }
                }
            } label: {
                Label("logs.openServiceLog".localized, systemImage: "server.rack")
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
        let text = logger.latestEntries.map { $0.formattedMessage }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - NSTableView wrapper for efficient virtualization

struct LogTableView: NSViewRepresentable {
    let entries: [LogEntry]
    let levelFilter: Logger.Level?
    let searchText: String
    let autoScroll: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.headerView = nil
        tableView.backgroundColor = NSColor.textBackgroundColor

        // Single column for the entire row
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("LogColumn"))
        column.width = 1000
        column.minWidth = 400
        tableView.addTableColumn(column)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.updateData(entries: entries, levelFilter: levelFilter, searchText: searchText)

        if autoScroll && !context.coordinator.filteredEntries.isEmpty {
            DispatchQueue.main.async {
                context.coordinator.scrollToBottom()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        var filteredEntries: [LogEntry] = []
        private var lastEntryCount = 0

        func updateData(entries: [LogEntry], levelFilter: Logger.Level?, searchText: String) {
            // Filter entries
            var filtered = entries

            if let level = levelFilter {
                filtered = filtered.filter { $0.level == level }
            }

            if !searchText.isEmpty {
                let search = searchText.lowercased()
                filtered = filtered.filter {
                    $0.message.lowercased().contains(search) ||
                    $0.file.lowercased().contains(search)
                }
            }

            let needsReload = filtered.count != filteredEntries.count
            filteredEntries = filtered

            if needsReload {
                tableView?.reloadData()
            }
        }

        func scrollToBottom() {
            guard let tableView = tableView, filteredEntries.count > 0 else { return }
            tableView.scrollRowToVisible(filteredEntries.count - 1)
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            return filteredEntries.count
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < filteredEntries.count else { return nil }

            let entry = filteredEntries[row]

            let identifier = NSUserInterfaceItemIdentifier("LogRowView")
            var rowView = tableView.makeView(withIdentifier: identifier, owner: nil) as? LogRowView
            if rowView == nil {
                rowView = LogRowView()
                rowView?.identifier = identifier
            }

            rowView?.configure(with: entry)
            return rowView
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            return 22
        }
    }
}

// MARK: - Custom row view for log entry

class LogRowView: NSView {
    private let timestampLabel = NSTextField(labelWithString: "")
    private let levelLabel = NSTextField(labelWithString: "")
    private let fileLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        // Timestamp
        timestampLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        timestampLabel.textColor = NSColor.secondaryLabelColor
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false

        // Level
        levelLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        levelLabel.alignment = .center
        levelLabel.wantsLayer = true
        levelLabel.layer?.cornerRadius = 3
        levelLabel.translatesAutoresizingMaskIntoConstraints = false

        // File
        fileLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        fileLabel.textColor = NSColor.secondaryLabelColor
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.translatesAutoresizingMaskIntoConstraints = false

        // Message
        messageLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.isSelectable = true

        addSubview(timestampLabel)
        addSubview(levelLabel)
        addSubview(fileLabel)
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            timestampLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            timestampLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timestampLabel.widthAnchor.constraint(equalToConstant: 80),

            levelLabel.leadingAnchor.constraint(equalTo: timestampLabel.trailingAnchor, constant: 8),
            levelLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            levelLabel.widthAnchor.constraint(equalToConstant: 50),

            fileLabel.leadingAnchor.constraint(equalTo: levelLabel.trailingAnchor, constant: 8),
            fileLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            fileLabel.widthAnchor.constraint(equalToConstant: 120),

            messageLabel.leadingAnchor.constraint(equalTo: fileLabel.trailingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(with entry: LogEntry) {
        timestampLabel.stringValue = entry.formattedTimestamp
        levelLabel.stringValue = entry.level.rawValue
        fileLabel.stringValue = "\(entry.file):\(entry.line)"
        messageLabel.stringValue = entry.message

        // Level colors
        switch entry.level {
        case .debug:
            levelLabel.textColor = NSColor.gray
            levelLabel.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.2).cgColor
            messageLabel.textColor = NSColor.gray
        case .info:
            levelLabel.textColor = NSColor.labelColor
            levelLabel.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.2).cgColor
            messageLabel.textColor = NSColor.labelColor
        case .warn:
            levelLabel.textColor = NSColor.systemOrange
            levelLabel.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.2).cgColor
            messageLabel.textColor = NSColor.systemOrange
        case .error:
            levelLabel.textColor = NSColor.systemRed
            levelLabel.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.2).cgColor
            messageLabel.textColor = NSColor.systemRed
        }

        // Error row background
        wantsLayer = true
        layer?.backgroundColor = entry.level == .error ? NSColor.systemRed.withAlphaComponent(0.05).cgColor : nil
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
