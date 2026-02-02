import Foundation
import os.log

/// Log entry
/// Reference: SERVICE_FLOW/16_LogSpec.md
public struct LogEntry: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let source: String
    public let file: String
    public let line: Int
    public let message: String
    public let globalState: String?
    public let componentState: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        source: String,
        file: String,
        line: Int,
        message: String,
        globalState: String? = nil,
        componentState: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.source = source
        self.file = file
        self.line = line
        self.message = message
        self.globalState = globalState
        self.componentState = componentState
    }

    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    /// Legacy format (backward compatible)
    public var formattedMessage: String {
        "[\(formattedTimestamp)] [\(source)] [\(level.rawValue)] [\(file):\(line)] \(message)"
    }

    /// Standard format (per SERVICE_FLOW/16_LogSpec.md)
    /// Format: [timestamp] [level] [globalState] [component] [componentState] message
    public var standardFormattedMessage: String {
        let levelStr = level.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0)
        let stateStr = (globalState ?? "--").padding(toLength: 11, withPad: " ", startingAt: 0)
        let sourceStr = source.padding(toLength: 6, withPad: " ", startingAt: 0)
        let compStateStr = (componentState ?? "--").padding(toLength: 7, withPad: " ", startingAt: 0)
        return "[\(formattedTimestamp)] [\(levelStr)] [\(stateStr)] [\(sourceStr)] [\(compStateStr)] \(message)"
    }
}

/// Log level
public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    public var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warn: return .default
        case .error: return .error
        }
    }
}

/// Logger (shared version, supports multi-process)
/// Reference: SERVICE_FLOW/16_LogSpec.md
public final class Logger: @unchecked Sendable {
    public static let shared = Logger(source: "App")

    /// Create a Logger instance for a specific source
    public static func forService(_ service: String) -> Logger {
        return Logger(source: service)
    }

    /// Global state provider (for standard format logging)
    /// Service side sets this to ServiceStateManager.shared.getState
    public static var globalStateProvider: (() -> String)? = nil

    // MARK: - Static Shared Resources (shared by all Logger instances for serialized writes)

    /// Global write queue - shared by all Logger instances
    private static let sharedQueue = DispatchQueue(label: "com.ttttt.dmsa.logger.shared", qos: .utility)

    /// Shared file handle (distinguished by process type)
    private static var sharedFileHandle: FileHandle?
    private static var sharedLogFileURL: URL?
    private static var sharedUseStandardFormat: Bool = false
    private static var isInitialized = false
    private static var isRunningAsRootCached: Bool = false

    /// Date corresponding to current log file (for daily rotation)
    private static var currentLogDate: String = ""

    /// Date formatter (for generating log file names)
    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Log retention days
    private static let maxLogRetentionDays = 7

    /// Initialize shared resources (executed once)
    private static func initializeSharedResources() {
        guard !isInitialized else { return }
        isInitialized = true

        let logsDir = Constants.Paths.logs
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        isRunningAsRootCached = getuid() == 0
        sharedUseStandardFormat = isRunningAsRootCached

        // Open today's log file
        rotateLogFileIfNeeded()

        // Clean up old logs
        cleanupOldLogs()
    }

    /// Rotate log file daily
    /// Caller must hold sharedQueue or call during initialization
    private static func rotateLogFileIfNeeded() {
        let today = logDateFormatter.string(from: Date())
        guard today != currentLogDate else { return }

        // Close old file handle
        sharedFileHandle?.closeFile()
        sharedFileHandle = nil

        currentLogDate = today

        let logsDir = Constants.Paths.logs
        let prefix = isRunningAsRootCached ? "service" : "app"
        let logFile = logsDir.appendingPathComponent("\(prefix)-\(today).log")
        sharedLogFileURL = logFile

        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        sharedFileHandle = FileHandle(forWritingAtPath: logFile.path)
        sharedFileHandle?.seekToEndOfFile()
    }

    /// Clean up logs older than retention period
    private static func cleanupOldLogs() {
        let logsDir = Constants.Paths.logs
        let prefix = isRunningAsRootCached ? "service" : "app"
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(atPath: logsDir.path) else { return }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -maxLogRetentionDays, to: Date()) ?? Date()
        let cutoffStr = logDateFormatter.string(from: cutoffDate)

        for file in files {
            // Match service-2026-01-25.log or app-2026-01-25.log
            guard file.hasPrefix("\(prefix)-"), file.hasSuffix(".log") else { continue }
            let dateStr = String(file.dropFirst(prefix.count + 1).dropLast(4))  // Extract date part
            if dateStr < cutoffStr {
                try? fm.removeItem(at: logsDir.appendingPathComponent(file))
            }
        }

        // Clean up legacy log files without date suffix (migration)
        let oldLogFile = logsDir.appendingPathComponent("\(prefix).log")
        if fm.fileExists(atPath: oldLogFile.path) {
            try? fm.removeItem(at: oldLogFile)
        }
    }

    private let source: String
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let osLog: OSLog

    /// Component state (dynamically updatable)
    public var componentState: String = "--"

    private init(source: String) {
        self.source = source

        // Ensure shared resources are initialized
        Logger.initializeSharedResources()

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss.SSS"

        osLog = OSLog(subsystem: Constants.bundleId, category: source)
    }

    /// Whether to use standard format
    private var useStandardFormat: Bool {
        Logger.sharedUseStandardFormat
    }

    /// Log file URL
    private var logFileURL: URL {
        Logger.sharedLogFileURL ?? Constants.Paths.appLog
    }

    /// Format log message
    /// Standard format: [timestamp] [level] [globalState] [component] [componentState] message
    /// Legacy format:   [timestamp] [source] [level] [file:line] message
    private func formatMessage(_ message: String, level: LogLevel, timestamp: Date, fileName: String, line: Int) -> String {
        if useStandardFormat {
            let timeStr = timeFormatter.string(from: timestamp)
            let levelStr = level.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0)
            let globalState = Logger.globalStateProvider?() ?? "STARTING"
            let stateStr = globalState.padding(toLength: 11, withPad: " ", startingAt: 0)
            let sourceStr = source.padding(toLength: 7, withPad: " ", startingAt: 0)
            let compStateStr = componentState.padding(toLength: 7, withPad: " ", startingAt: 0)
            return "[\(timeStr)] [\(levelStr)] [\(stateStr)] [\(sourceStr)] [\(compStateStr)] \(message)\n"
        } else {
            let fullTimestamp = dateFormatter.string(from: timestamp)
            return "[\(fullTimestamp)] [\(source)] [\(level.rawValue)] [\(fileName):\(line)] \(message)\n"
        }
    }

    public func log(_ message: String, level: LogLevel = .info, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = Date()
        let logMessage = formatMessage(message, level: level, timestamp: timestamp, fileName: fileName, line: line)
        let osLogRef = self.osLog

        // Use shared queue for synchronized writes, ensuring correct log order across all Logger instances
        Logger.sharedQueue.sync {
            // Check if daily rotation is needed
            Logger.rotateLogFileIfNeeded()

            // Write to file
            if let data = logMessage.data(using: .utf8) {
                Logger.sharedFileHandle?.write(data)
                // Flush immediately to ensure write completion
                Logger.sharedFileHandle?.synchronizeFile()
            }

            // Write to OS Log
            os_log("%{public}@", log: osLogRef, type: level.osLogType, message)

            // Console output
            #if DEBUG
            print(logMessage, terminator: "")
            #endif
        }
    }

    public func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .debug, file: file, line: line)
    }

    public func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .info, file: file, line: line)
    }

    public func warn(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .warn, file: file, line: line)
    }

    public func warning(_ message: String, file: String = #file, line: Int = #line) {
        warn(message, file: file, line: line)
    }

    public func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }

    /// Set component state (for standard format logging)
    public func setComponentState(_ state: String) {
        componentState = state
    }

    // MARK: - Log File Operations

    public var logFileLocation: URL {
        logFileURL
    }

    public func clearLogFile() {
        Logger.sharedQueue.async {
            Logger.sharedFileHandle?.truncateFile(atOffset: 0)
            Logger.sharedFileHandle?.synchronizeFile()
        }
    }

    public func readLogFile() -> String? {
        try? String(contentsOf: logFileURL, encoding: .utf8)
    }

    public func getLogFileSize() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// Synchronously flush log to disk
    public func flush() {
        Logger.sharedQueue.sync {
            Logger.sharedFileHandle?.synchronizeFile()
        }
    }
}

// MARK: - Convenience Functions

public func log(_ message: String, file: String = #file, line: Int = #line) {
    Logger.shared.info(message, file: file, line: line)
}
