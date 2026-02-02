import Foundation
import os.log
import Combine

/// 日志条目
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

/// 日志管理器
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

    // MARK: - 实时日志订阅

    /// 最近的日志条目 (最多 1000 条)
    @Published private(set) var latestEntries: [LogEntry] = []

    /// 日志更新发布者
    let logPublisher = PassthroughSubject<LogEntry, Never>()

    /// 最大保留条目数
    private let maxEntries = 1000

    /// 节流机制：待发布的日志条目缓冲
    private var pendingEntries: [LogEntry] = []
    private var isFlushScheduled = false
    private let flushInterval: TimeInterval = 0.1  // 100ms 批量更新一次

    private init() {
        logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DMSA")

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyy-MM-dd"

        // 打开今日日志文件
        let today = logDateFormatter.string(from: Date())
        currentLogDate = today
        logFileURL = logsDir.appendingPathComponent("app-\(today).log")

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = FileHandle(forWritingAtPath: logFileURL.path)
        fileHandle?.seekToEndOfFile()

        // 清理旧日志
        cleanupOldLogs()
    }

    /// 按天轮转日志文件 (在 queue 中调用)
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

    /// 清理超过保留天数的旧日志
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

        // 清理旧的不带日期的日志文件
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

        // 创建日志条目
        let entry = LogEntry(
            timestamp: timestamp,
            level: level,
            file: fileName,
            line: line,
            message: message
        )

        // 使用节流机制批量更新 UI
        queue.async { [weak self] in
            guard let self = self else { return }

            // 检查是否需要按天轮转
            self.rotateLogFileIfNeeded()

            // 添加到待发布缓冲
            self.pendingEntries.append(entry)

            // 调度批量刷新
            if !self.isFlushScheduled {
                self.isFlushScheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + self.flushInterval) { [weak self] in
                    self?.flushPendingEntries()
                }
            }

            // 同步写入控制台和文件
            print(logMessage, terminator: "")

            if let data = logMessage.data(using: .utf8) {
                self.fileHandle?.write(data)
            }
        }
    }

    /// 批量刷新待发布的日志条目到主线程
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

                // 保持在最大条目数以内
                if self.latestEntries.count > self.maxEntries {
                    self.latestEntries.removeFirst(self.latestEntries.count - self.maxEntries)
                }

                // 只发送最后一个条目的通知，减少订阅者处理次数
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

    /// warning 是 warn 的别名，为了兼容性
    func warning(_ message: String, file: String = #file, line: Int = #line) {
        warn(message, file: file, line: line)
    }

    func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }

    // MARK: - 日志文件操作

    /// 获取日志文件 URL
    var logFileLocation: URL {
        logFileURL
    }

    /// 清空日志文件
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

    /// 读取日志文件内容
    func readLogFile() -> String? {
        try? String(contentsOf: logFileURL, encoding: .utf8)
    }

    /// 获取日志文件大小
    func getLogFileSize() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// 过滤日志条目
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
