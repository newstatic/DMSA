import Foundation
import os.log

/// 日志条目
public struct LogEntry: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let source: String
    public let file: String
    public let line: Int
    public let message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        source: String,
        file: String,
        line: Int,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.source = source
        self.file = file
        self.line = line
        self.message = message
    }

    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    public var formattedMessage: String {
        "[\(formattedTimestamp)] [\(source)] [\(level.rawValue)] [\(file):\(line)] \(message)"
    }
}

/// 日志级别
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

/// 日志管理器 (共享版本，支持多进程)
public final class Logger: @unchecked Sendable {
    public static let shared = Logger(source: "App")

    /// 创建特定来源的 Logger 实例
    public static func forService(_ service: String) -> Logger {
        return Logger(source: service)
    }

    private let source: String
    private let logFileURL: URL
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.ttttt.dmsa.logger", qos: .utility)
    private let osLog: OSLog

    private init(source: String) {
        self.source = source

        let logsDir = Constants.Paths.logs

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // 根据来源选择日志文件
        switch source.lowercased() {
        case "vfs":
            logFileURL = Constants.Paths.vfsLog
        case "sync":
            logFileURL = Constants.Paths.syncLog
        case "helper":
            logFileURL = Constants.Paths.helperLog
        default:
            logFileURL = Constants.Paths.appLog
        }

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = FileHandle(forWritingAtPath: logFileURL.path)
        fileHandle?.seekToEndOfFile()

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        osLog = OSLog(subsystem: Constants.bundleId, category: source)
    }

    public func log(_ message: String, level: LogLevel = .info, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = Date()
        let formattedTimestamp = dateFormatter.string(from: timestamp)
        let logMessage = "[\(formattedTimestamp)] [\(source)] [\(level.rawValue)] [\(fileName):\(line)] \(message)\n"

        queue.async { [weak self] in
            guard let self = self else { return }

            // 写入文件
            if let data = logMessage.data(using: .utf8) {
                self.fileHandle?.write(data)
            }

            // 写入 OS Log
            os_log("%{public}@", log: self.osLog, type: level.osLogType, message)

            // 控制台输出
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

    // MARK: - 日志文件操作

    public var logFileLocation: URL {
        logFileURL
    }

    public func clearLogFile() {
        queue.async { [weak self] in
            self?.fileHandle?.truncateFile(atOffset: 0)
            self?.fileHandle?.synchronizeFile()
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

    /// 同步刷新日志到磁盘
    public func flush() {
        queue.sync {
            fileHandle?.synchronizeFile()
        }
    }
}

// MARK: - 便捷函数

public func log(_ message: String, file: String = #file, line: Int = #line) {
    Logger.shared.info(message, file: file, line: line)
}
