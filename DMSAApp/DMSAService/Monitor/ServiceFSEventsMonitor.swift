import Foundation
import CoreServices

/// Service 端 FSEvents 文件系统监控器
/// 监控指定目录的文件变化，触发同步
final class ServiceFSEventsMonitor {

    // MARK: - Types

    /// 文件变化事件
    struct FileEvent: Sendable {
        let path: String
        let flags: FSEventStreamEventFlags
        let eventId: FSEventStreamEventId
        let timestamp: Date

        var isFile: Bool { !isDirectory }
        var isDirectory: Bool { flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 }
        var isCreated: Bool { flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 }
        var isRemoved: Bool { flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 }
        var isRenamed: Bool { flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 }
        var isModified: Bool {
            flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 ||
            flags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0
        }

        var description: String {
            var types: [String] = []
            if isCreated { types.append("created") }
            if isRemoved { types.append("removed") }
            if isRenamed { types.append("renamed") }
            if isModified { types.append("modified") }
            let typeStr = types.isEmpty ? "unknown" : types.joined(separator: ",")
            let kind = isDirectory ? "dir" : "file"
            return "[\(kind)] \(path) (\(typeStr))"
        }
    }

    /// 监控配置
    struct Config: Sendable {
        var latency: TimeInterval = 1.0
        var watchSubdirectories: Bool = true
        var ignoreSelf: Bool = true
        var fileEvents: Bool = true
        var excludePatterns: [String] = [
            ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
            "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
            "*.part", "*.crdownload", "*.download", ".FUSE"
        ]
    }

    // MARK: - Properties

    private var stream: FSEventStreamRef?
    private var paths: [String]
    private var config: Config
    private let queue: DispatchQueue
    private let logger = Logger.forService("FSEvents")

    /// 事件回调
    var onEvents: (([FileEvent]) -> Void)?

    /// 是否正在监控
    private(set) var isMonitoring: Bool = false

    /// 事件缓冲区
    private var eventBuffer: [FileEvent] = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval

    // MARK: - Initialization

    init(paths: [String] = [], config: Config = Config(), debounceInterval: TimeInterval = 2.0) {
        self.paths = paths.map { ($0 as NSString).expandingTildeInPath }
        self.config = config
        self.debounceInterval = debounceInterval
        self.queue = DispatchQueue(label: "com.ttttt.dmsa.service.fsevents", qos: .utility)
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// 更新监控路径
    func updatePaths(_ newPaths: [String]) {
        let wasMonitoring = isMonitoring
        if wasMonitoring {
            stop()
        }

        paths = newPaths.map { ($0 as NSString).expandingTildeInPath }

        if wasMonitoring && !paths.isEmpty {
            _ = start()
        }
    }

    /// 添加监控路径
    func addPath(_ path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard !paths.contains(expandedPath) else { return }

        let wasMonitoring = isMonitoring
        if wasMonitoring {
            stop()
        }

        paths.append(expandedPath)

        if wasMonitoring {
            _ = start()
        }
    }

    /// 移除监控路径
    func removePath(_ path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard let index = paths.firstIndex(of: expandedPath) else { return }

        let wasMonitoring = isMonitoring
        if wasMonitoring {
            stop()
        }

        paths.remove(at: index)

        if wasMonitoring && !paths.isEmpty {
            _ = start()
        }
    }

    /// 开始监控
    func start() -> Bool {
        guard !isMonitoring else {
            logger.warn("FSEventsMonitor 已在运行")
            return true
        }

        guard !paths.isEmpty else {
            logger.debug("FSEventsMonitor: 没有指定监控路径")
            return false
        }

        // 验证路径存在
        let validPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !validPaths.isEmpty else {
            logger.error("FSEventsMonitor: 所有监控路径都不存在")
            return false
        }

        // 创建流上下文
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // 设置标志
        var flags: FSEventStreamCreateFlags = UInt32(kFSEventStreamCreateFlagUseCFTypes)
        if config.fileEvents {
            flags |= UInt32(kFSEventStreamCreateFlagFileEvents)
        }
        if config.ignoreSelf {
            flags |= UInt32(kFSEventStreamCreateFlagIgnoreSelf)
        }
        if !config.watchSubdirectories {
            flags |= UInt32(kFSEventStreamCreateFlagWatchRoot)
        }

        // 创建事件流
        stream = FSEventStreamCreate(
            nil,
            serviceFSEventsCallback,
            &context,
            validPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            config.latency,
            flags
        )

        guard let stream = stream else {
            logger.error("FSEventsMonitor: 创建事件流失败")
            return false
        }

        FSEventStreamSetDispatchQueue(stream, queue)

        if !FSEventStreamStart(stream) {
            logger.error("FSEventsMonitor: 启动事件流失败")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return false
        }

        isMonitoring = true
        logger.info("FSEventsMonitor 开始监控 \(validPaths.count) 个路径")
        return true
    }

    /// 停止监控
    func stop() {
        guard isMonitoring, let stream = stream else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)

        self.stream = nil
        isMonitoring = false

        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        eventBuffer.removeAll()

        logger.info("FSEventsMonitor 已停止")
    }

    // MARK: - Internal Methods

    fileprivate func handleEvents(numEvents: Int, eventPaths: [String], eventFlags: [FSEventStreamEventFlags], eventIds: [FSEventStreamEventId]) {
        var events: [FileEvent] = []
        let now = Date()

        for i in 0..<numEvents {
            let path = eventPaths[i]
            let flags = eventFlags[i]
            let eventId = eventIds[i]

            if shouldExclude(path: path) {
                continue
            }

            let event = FileEvent(
                path: path,
                flags: flags,
                eventId: eventId,
                timestamp: now
            )

            events.append(event)
            logger.debug("FSEvent: \(event.description)")
        }

        guard !events.isEmpty else { return }

        queue.async { [weak self] in
            self?.bufferEvents(events)
        }
    }

    private func bufferEvents(_ events: [FileEvent]) {
        eventBuffer.append(contentsOf: events)

        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushEventBuffer()
        }
        debounceWorkItem = workItem

        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func flushEventBuffer() {
        guard !eventBuffer.isEmpty else { return }

        // 合并重复事件
        var mergedEvents: [String: FileEvent] = [:]
        for event in eventBuffer {
            if let existing = mergedEvents[event.path] {
                let mergedFlags = existing.flags | event.flags
                mergedEvents[event.path] = FileEvent(
                    path: event.path,
                    flags: mergedFlags,
                    eventId: event.eventId,
                    timestamp: event.timestamp
                )
            } else {
                mergedEvents[event.path] = event
            }
        }

        let events = Array(mergedEvents.values)
        eventBuffer.removeAll()

        // 触发回调
        onEvents?(events)
    }

    private func shouldExclude(path: String) -> Bool {
        let filename = (path as NSString).lastPathComponent

        for pattern in config.excludePatterns {
            if matchesPattern(filename: filename, pattern: pattern) {
                return true
            }
        }

        return false
    }

    private func matchesPattern(filename: String, pattern: String) -> Bool {
        if filename == pattern {
            return true
        }
        if pattern.hasPrefix("*") {
            return filename.hasSuffix(String(pattern.dropFirst()))
        }
        if pattern.hasSuffix("*") {
            return filename.hasPrefix(String(pattern.dropLast()))
        }
        return false
    }
}

// MARK: - FSEvents Callback

private func serviceFSEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo = clientCallBackInfo else { return }

    let monitor = Unmanaged<ServiceFSEventsMonitor>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
    let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
    let ids = Array(UnsafeBufferPointer(start: eventIds, count: numEvents))

    monitor.handleEvents(numEvents: numEvents, eventPaths: paths, eventFlags: flags, eventIds: ids)
}
