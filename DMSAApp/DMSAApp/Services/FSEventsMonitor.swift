import Foundation
import CoreServices

/// FSEvents 文件系统监控器
/// 监控指定目录的文件变化，触发透明同步
final class FSEventsMonitor {

    // MARK: - Types

    /// 文件变化事件
    struct FileEvent {
        let path: String
        let flags: FSEventStreamEventFlags
        let eventId: FSEventStreamEventId
        let timestamp: Date

        var isFile: Bool {
            !isDirectory
        }

        var isDirectory: Bool {
            flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
        }

        var isCreated: Bool {
            flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
        }

        var isRemoved: Bool {
            flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
        }

        var isRenamed: Bool {
            flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
        }

        var isModified: Bool {
            flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 ||
            flags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod) != 0
        }

        var isOwnerChanged: Bool {
            flags & UInt32(kFSEventStreamEventFlagItemChangeOwner) != 0
        }

        var isXattrModified: Bool {
            flags & UInt32(kFSEventStreamEventFlagItemXattrMod) != 0
        }

        var description: String {
            var types: [String] = []
            if isCreated { types.append("created") }
            if isRemoved { types.append("removed") }
            if isRenamed { types.append("renamed") }
            if isModified { types.append("modified") }
            if isOwnerChanged { types.append("owner_changed") }
            if isXattrModified { types.append("xattr_modified") }
            let typeStr = types.isEmpty ? "unknown" : types.joined(separator: ",")
            let kind = isDirectory ? "dir" : "file"
            return "[\(kind)] \(path) (\(typeStr))"
        }
    }

    /// 监控配置
    struct Config {
        /// 监控延迟（秒）- 合并短时间内的多个事件
        var latency: TimeInterval = 1.0

        /// 是否监控子目录
        var watchSubdirectories: Bool = true

        /// 是否忽略自身进程的变化
        var ignoreSelf: Bool = true

        /// 是否使用文件级事件（而非目录级）
        var fileEvents: Bool = true

        /// 排除的文件模式
        var excludePatterns: [String] = [
            ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
            "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
            "*.part", "*.crdownload", "*.download"
        ]
    }

    /// 监控代理协议
    protocol Delegate: AnyObject {
        func fsEventsMonitor(_ monitor: FSEventsMonitor, didReceiveEvents events: [FileEvent])
        func fsEventsMonitor(_ monitor: FSEventsMonitor, didFailWithError error: Error)
    }

    // MARK: - Properties

    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let config: Config
    private let queue: DispatchQueue

    weak var delegate: Delegate?

    /// 是否正在监控
    private(set) var isMonitoring: Bool = false

    /// 事件缓冲区（用于防抖）
    private var eventBuffer: [FileEvent] = []
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval

    // MARK: - Initialization

    init(paths: [String], config: Config = Config(), debounceInterval: TimeInterval = 2.0) {
        self.paths = paths.map { ($0 as NSString).expandingTildeInPath }
        self.config = config
        self.debounceInterval = debounceInterval
        self.queue = DispatchQueue(label: "com.ttttt.dmsa.fsevents", qos: .utility)
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// 开始监控
    func start() -> Bool {
        guard !isMonitoring else {
            Logger.shared.warn("FSEventsMonitor 已在运行")
            return true
        }

        guard !paths.isEmpty else {
            Logger.shared.error("FSEventsMonitor: 没有指定监控路径")
            return false
        }

        // 验证路径存在
        let validPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !validPaths.isEmpty else {
            Logger.shared.error("FSEventsMonitor: 所有监控路径都不存在")
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

        // 如果需要监控子目录
        if !config.watchSubdirectories {
            flags |= UInt32(kFSEventStreamCreateFlagWatchRoot)
        }

        // 创建事件流
        let pathsToWatch = validPaths as CFArray
        stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            config.latency,
            flags
        )

        guard let stream = stream else {
            Logger.shared.error("FSEventsMonitor: 创建事件流失败")
            return false
        }

        // 设置调度队列
        FSEventStreamSetDispatchQueue(stream, queue)

        // 启动流
        if !FSEventStreamStart(stream) {
            Logger.shared.error("FSEventsMonitor: 启动事件流失败")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return false
        }

        isMonitoring = true
        Logger.shared.info("FSEventsMonitor 开始监控: \(validPaths)")
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

        // 取消待处理的防抖任务
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        eventBuffer.removeAll()

        Logger.shared.info("FSEventsMonitor 已停止")
    }

    /// 刷新监控（重新启动以应用新配置）
    func refresh() {
        stop()
        _ = start()
    }

    // MARK: - Private Methods

    /// 处理 FSEvents 回调
    fileprivate func handleEvents(numEvents: Int, eventPaths: [String], eventFlags: [FSEventStreamEventFlags], eventIds: [FSEventStreamEventId]) {
        var events: [FileEvent] = []
        let now = Date()

        for i in 0..<numEvents {
            let path = eventPaths[i]
            let flags = eventFlags[i]
            let eventId = eventIds[i]

            // 检查是否应该排除
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
            Logger.shared.debug("FSEvent: \(event.description)")
        }

        guard !events.isEmpty else { return }

        // 添加到缓冲区并设置防抖
        queue.async { [weak self] in
            self?.bufferEvents(events)
        }
    }

    /// 缓冲事件（防抖处理）
    private func bufferEvents(_ events: [FileEvent]) {
        eventBuffer.append(contentsOf: events)

        // 取消之前的防抖任务
        debounceWorkItem?.cancel()

        // 创建新的防抖任务
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushEventBuffer()
        }
        debounceWorkItem = workItem

        // 延迟执行
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    /// 刷新事件缓冲区
    private func flushEventBuffer() {
        guard !eventBuffer.isEmpty else { return }

        // 合并重复事件（同一路径的多个事件合并为一个）
        var mergedEvents: [String: FileEvent] = [:]
        for event in eventBuffer {
            if let existing = mergedEvents[event.path] {
                // 合并标志
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

        // 通知代理
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.fsEventsMonitor(self, didReceiveEvents: events)
        }
    }

    /// 检查路径是否应该排除
    private func shouldExclude(path: String) -> Bool {
        let filename = (path as NSString).lastPathComponent

        for pattern in config.excludePatterns {
            if matchesPattern(filename: filename, pattern: pattern) {
                return true
            }
        }

        return false
    }

    /// 简单的通配符匹配
    private func matchesPattern(filename: String, pattern: String) -> Bool {
        // 精确匹配
        if filename == pattern {
            return true
        }

        // 前缀通配符 (*.tmp)
        if pattern.hasPrefix("*") {
            let suffix = String(pattern.dropFirst())
            return filename.hasSuffix(suffix)
        }

        // 后缀通配符 (temp*)
        if pattern.hasSuffix("*") {
            let prefix = String(pattern.dropLast())
            return filename.hasPrefix(prefix)
        }

        return false
    }
}

// MARK: - FSEvents Callback

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo = clientCallBackInfo else { return }

    let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

    // 转换路径数组
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

    // 转换标志数组
    let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

    // 转换事件 ID 数组
    let ids = Array(UnsafeBufferPointer(start: eventIds, count: numEvents))

    monitor.handleEvents(numEvents: numEvents, eventPaths: paths, eventFlags: flags, eventIds: ids)
}

// MARK: - Delegate Extension for Default Implementation

extension FSEventsMonitor.Delegate {
    func fsEventsMonitor(_ monitor: FSEventsMonitor, didFailWithError error: Error) {
        Logger.shared.error("FSEventsMonitor 错误: \(error.localizedDescription)")
    }
}
