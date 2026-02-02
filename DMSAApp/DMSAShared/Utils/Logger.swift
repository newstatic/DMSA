import Foundation
import os.log

/// 日志条目
/// 参考文档: SERVICE_FLOW/16_日志规范.md
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

    /// 旧格式 (兼容)
    public var formattedMessage: String {
        "[\(formattedTimestamp)] [\(source)] [\(level.rawValue)] [\(file):\(line)] \(message)"
    }

    /// 新格式 (符合 SERVICE_FLOW/16_日志规范.md)
    /// 格式: [时间戳] [级别] [全局状态] [组件] [组件状态] 消息
    public var standardFormattedMessage: String {
        let levelStr = level.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0)
        let stateStr = (globalState ?? "--").padding(toLength: 11, withPad: " ", startingAt: 0)
        let sourceStr = source.padding(toLength: 6, withPad: " ", startingAt: 0)
        let compStateStr = (componentState ?? "--").padding(toLength: 7, withPad: " ", startingAt: 0)
        return "[\(formattedTimestamp)] [\(levelStr)] [\(stateStr)] [\(sourceStr)] [\(compStateStr)] \(message)"
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
/// 参考文档: SERVICE_FLOW/16_日志规范.md
public final class Logger: @unchecked Sendable {
    public static let shared = Logger(source: "App")

    /// 创建特定来源的 Logger 实例
    public static func forService(_ service: String) -> Logger {
        return Logger(source: service)
    }

    /// 全局状态提供者 (用于标准格式日志)
    /// Service 端设置为 ServiceStateManager.shared.getState
    public static var globalStateProvider: (() -> String)? = nil

    // MARK: - 静态共享资源 (所有 Logger 实例共用，确保写入串行化)

    /// 全局写入队列 - 所有 Logger 实例共用
    private static let sharedQueue = DispatchQueue(label: "com.ttttt.dmsa.logger.shared", qos: .utility)

    /// 共享的文件句柄 (按进程类型区分)
    private static var sharedFileHandle: FileHandle?
    private static var sharedLogFileURL: URL?
    private static var sharedUseStandardFormat: Bool = false
    private static var isInitialized = false

    /// 初始化共享资源 (只执行一次)
    private static func initializeSharedResources() {
        guard !isInitialized else { return }
        isInitialized = true

        let logsDir = Constants.Paths.logs
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // 根据运行身份选择日志文件
        let isRunningAsRoot = getuid() == 0
        if isRunningAsRoot {
            sharedLogFileURL = Constants.Paths.serviceLog
            sharedUseStandardFormat = true
        } else {
            sharedLogFileURL = Constants.Paths.appLog
            sharedUseStandardFormat = false
        }

        if let url = sharedLogFileURL {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            sharedFileHandle = FileHandle(forWritingAtPath: url.path)
            sharedFileHandle?.seekToEndOfFile()
        }
    }

    private let source: String
    private let dateFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let osLog: OSLog

    /// 组件状态 (可动态更新)
    public var componentState: String = "--"

    private init(source: String) {
        self.source = source

        // 确保共享资源已初始化
        Logger.initializeSharedResources()

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss.SSS"

        osLog = OSLog(subsystem: Constants.bundleId, category: source)
    }

    /// 是否使用标准格式
    private var useStandardFormat: Bool {
        Logger.sharedUseStandardFormat
    }

    /// 日志文件 URL
    private var logFileURL: URL {
        Logger.sharedLogFileURL ?? Constants.Paths.appLog
    }

    /// 格式化日志消息
    /// 标准格式: [时间戳] [级别] [全局状态] [组件] [组件状态] 消息
    /// 旧格式:   [时间戳] [source] [级别] [文件:行] 消息
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

        // 使用共享队列同步写入，确保所有 Logger 实例的日志顺序正确
        Logger.sharedQueue.sync {
            // 写入文件
            if let data = logMessage.data(using: .utf8) {
                Logger.sharedFileHandle?.write(data)
                // 立即刷新确保写入完成
                Logger.sharedFileHandle?.synchronizeFile()
            }

            // 写入 OS Log
            os_log("%{public}@", log: osLogRef, type: level.osLogType, message)

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

    /// 设置组件状态 (用于标准格式日志)
    public func setComponentState(_ state: String) {
        componentState = state
    }

    // MARK: - 日志文件操作

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

    /// 同步刷新日志到磁盘
    public func flush() {
        Logger.sharedQueue.sync {
            Logger.sharedFileHandle?.synchronizeFile()
        }
    }
}

// MARK: - 便捷函数

public func log(_ message: String, file: String = #file, line: Int = #line) {
    Logger.shared.info(message, file: file, line: line)
}
