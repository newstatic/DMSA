import Foundation
import os.log
import Combine

/// Log entry
struct LogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let level: Logger.Level
    let file: String
    let line: Int
    let message: String

    init(timestamp: Date = Date(), level: Logger.Level, file: String, line: Int, message: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.level = level
        self.file = file
        self.line = line
        self.message = message
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var formattedMessage: String {
        "[\(formattedTimestamp)] [\(level.rawValue)] [\(file):\(line)] \(message)"
    }
}

/// Logger
final class Logger: ObservableObject {
    static let shared = Logger()

    private let subsystem = "com.ttttt.dmsa"
    private var logFileURL: URL
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let logDateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.ttttt.dmsa.logger")
    private var currentLogDate: String = ""
    private let logsDir: URL
    private static let maxLogRetentionDays = 7

    enum Level: String, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"

        var color: String {
            switch self {
            case .debug: return "gray"
            case .info: return "primary"
            case .warn: return "orange"
            case .error: return "red"
            }
        }

        var icon: String {
            switch self {
            case .debug: return "ant"
            case .info: return "info.circle"
            case .warn: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            }
        }
    }

    // MARK: - Live Log Subscription

    /// Recent log entries (max 1000)
    @Published private(set) var latestEntries: [LogEntry] = []

    /// Log update publisher
    let logPublisher = PassthroughSubject<LogEntry, Never>()

    /// Max retained entries
    private let maxEntries = 1000

    /// Throttle: pending log entry buffer
    private var pendingEntries: [LogEntry] = []
    private var isFlushScheduled = false
    private let flushInterval: TimeInterval = 0.1  // Batch update every 100ms

    private init() {
        logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DMSA")

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyy-MM-dd"

        // Open today's log file
        let today = logDateFormatter.string(from: Date())
        currentLogDate = today
        logFileURL = logsDir.appendingPathComponent("app-\(today).log")

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = FileHandle(forWritingAtPath: logFileURL.path)
        fileHandle?.seekToEndOfFile()

        // Clean up old logs
        cleanupOldLogs()

        // Load recent logs from file
        loadRecentLogs(lines: 200)
    }

    /// Load recent log lines from file on startup
    private func loadRecentLogs(lines: Int = 200) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let url = self.logFileURL
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8) else { return }

            let allLines = content.components(separatedBy: .newlines)
            let recentLines = Array(allLines.suffix(lines))

            var entries: [LogEntry] = []
            for line in recentLines {
                if let entry = self.parseLogLine(line) {
                    entries.append(entry)
                }
            }

            DispatchQueue.main.async {
                self.latestEntries = entries
            }
        }
    }

    /// Parse a log line into LogEntry
    /// Format: [yyyy-MM-dd HH:mm:ss.SSS] [LEVEL] [File:Line] Message
    private func parseLogLine(_ line: String) -> LogEntry? {
        guard !line.isEmpty, line.hasPrefix("[") else { return nil }

        // Find timestamp end
        guard let timestampEndIdx = line.firstIndex(of: "]") else { return nil }
        let timestampStr = String(line[line.index(after: line.startIndex)..<timestampEndIdx])

        // Parse remaining: " [LEVEL] [File:Line] Message"
        let afterTimestamp = line[line.index(after: timestampEndIdx)...]
        guard afterTimestamp.hasPrefix(" [") else { return nil }

        // Find level
        let levelStart = afterTimestamp.index(afterTimestamp.startIndex, offsetBy: 2)
        guard let levelEnd = afterTimestamp[levelStart...].firstIndex(of: "]") else { return nil }
        let levelStr = String(afterTimestamp[levelStart..<levelEnd]).trimmingCharacters(in: .whitespaces)

        // Find file:line
        let afterLevel = afterTimestamp[afterTimestamp.index(after: levelEnd)...]
        guard afterLevel.hasPrefix(" [") else { return nil }

        let fileStart = afterLevel.index(afterLevel.startIndex, offsetBy: 2)
        guard let fileEnd = afterLevel[fileStart...].firstIndex(of: "]") else { return nil }
        let fileLineStr = String(afterLevel[fileStart..<fileEnd])

        // Parse file and line number
        let fileComponents = fileLineStr.split(separator: ":", maxSplits: 1)
        let fileName = fileComponents.first.map(String.init) ?? ""
        let lineNum = fileComponents.count > 1 ? Int(fileComponents[1]) ?? 0 : 0

        // Message is everything after
        let messageStart = afterLevel.index(after: fileEnd)
        let message = String(afterLevel[messageStart...]).trimmingCharacters(in: .whitespaces)

        // Parse level
        let level: Level
        switch levelStr.uppercased() {
        case "DEBUG": level = .debug
        case "INFO": level = .info
        case "WARN", "WARNING": level = .warn
        case "ERROR": level = .error
        default: level = .info
        }

        // Parse timestamp
        let timestamp = dateFormatter.date(from: timestampStr) ?? Date()

        return LogEntry(
            timestamp: timestamp,
            level: level,
            file: fileName,
            line: lineNum,
            message: message
        )
    }

    /// Rotate log file daily (called within queue)
    private func rotateLogFileIfNeeded() {
        let today = logDateFormatter.string(from: Date())
        guard today != currentLogDate else { return }

        fileHandle?.closeFile()
        currentLogDate = today
        logFileURL = logsDir.appendingPathComponent("app-\(today).log")

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = FileHandle(forWritingAtPath: logFileURL.path)
        fileHandle?.seekToEndOfFile()
    }

    /// Clean up logs older than retention period
    private func cleanupOldLogs() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: logsDir.path) else { return }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -Logger.maxLogRetentionDays, to: Date()) ?? Date()
        let cutoffStr = logDateFormatter.string(from: cutoffDate)

        for file in files {
            guard file.hasPrefix("app-"), file.hasSuffix(".log") else { continue }
            let dateStr = String(file.dropFirst(4).dropLast(4))
            if dateStr < cutoffStr {
                try? fm.removeItem(at: logsDir.appendingPathComponent(file))
            }
        }

        // Clean up legacy log files without date suffix
        let oldLog = logsDir.appendingPathComponent("app.log")
        if fm.fileExists(atPath: oldLog.path) {
            try? fm.removeItem(at: oldLog)
        }
    }

    func log(_ message: String, level: Level = .info, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = Date()
        let formattedTimestamp = self.dateFormatter.string(from: timestamp)
        let logMessage = "[\(formattedTimestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(message)\n"

        // Create log entry
        let entry = LogEntry(
            timestamp: timestamp,
            level: level,
            file: fileName,
            line: line,
            message: message
        )

        // Use throttle mechanism for batch UI updates
        queue.async { [weak self] in
            guard let self = self else { return }

            // Check if daily rotation is needed
            self.rotateLogFileIfNeeded()

            // Add to pending buffer
            self.pendingEntries.append(entry)

            // Schedule batch flush
            if !self.isFlushScheduled {
                self.isFlushScheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + self.flushInterval) { [weak self] in
                    self?.flushPendingEntries()
                }
            }

            // Write to console and file synchronously
            print(logMessage, terminator: "")

            if let data = logMessage.data(using: .utf8) {
                self.fileHandle?.write(data)
            }
        }
    }

    /// Batch flush pending log entries to main thread
    private func flushPendingEntries() {
        queue.async { [weak self] in
            guard let self = self else { return }

            let entriesToFlush = self.pendingEntries
            self.pendingEntries = []
            self.isFlushScheduled = false

            guard !entriesToFlush.isEmpty else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.latestEntries.append(contentsOf: entriesToFlush)

                // Keep within max entry count
                if self.latestEntries.count > self.maxEntries {
                    self.latestEntries.removeFirst(self.latestEntries.count - self.maxEntries)
                }

                // Only send notification for last entry to reduce subscriber processing
                if let lastEntry = entriesToFlush.last {
                    self.logPublisher.send(lastEntry)
                }
            }
        }
    }

    func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .debug, file: file, line: line)
    }

    func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .info, file: file, line: line)
    }

    func warn(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .warn, file: file, line: line)
    }

    /// warning is an alias for warn, for compatibility
    func warning(_ message: String, file: String = #file, line: Int = #line) {
        warn(message, file: file, line: line)
    }

    func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }

    // MARK: - Log File Operations

    /// Get log file URL
    var logFileLocation: URL {
        logFileURL
    }

    /// Clear log file
    func clearLogFile() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.fileHandle?.truncateFile(atOffset: 0)
            self.fileHandle?.synchronizeFile()
        }
        DispatchQueue.main.async { [weak self] in
            self?.latestEntries.removeAll()
        }
    }

    /// Read log file contents
    func readLogFile() -> String? {
        try? String(contentsOf: logFileURL, encoding: .utf8)
    }

    /// Get log file size
    func getLogFileSize() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// Filter log entries
    func filteredEntries(level: Level? = nil, searchText: String = "") -> [LogEntry] {
        var entries = latestEntries

        if let level = level {
            entries = entries.filter { $0.level == level }
        }

        if !searchText.isEmpty {
            let search = searchText.lowercased()
            entries = entries.filter {
                $0.message.lowercased().contains(search) ||
                $0.file.lowercased().contains(search)
            }
        }

        return entries
    }
}

func log(_ message: String) {
    Logger.shared.info(message)
}
