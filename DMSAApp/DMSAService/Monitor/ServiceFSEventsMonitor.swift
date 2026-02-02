import Foundation
import CoreServices

/// Service-side FSEvents file system monitor
/// Monitors file changes in specified directories to trigger sync
final class ServiceFSEventsMonitor {

    // MARK: - Types

    /// File change event
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

    /// Monitor configuration
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

    /// Event callback
    var onEvents: (([FileEvent]) -> Void)?

    /// Whether monitoring is active
    private(set) var isMonitoring: Bool = false

    /// Event buffer
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

    /// Update monitored paths
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

    /// Add a monitored path
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

    /// Remove a monitored path
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

    /// Start monitoring
    func start() -> Bool {
        guard !isMonitoring else {
            logger.warn("FSEventsMonitor is already running")
            return true
        }

        guard !paths.isEmpty else {
            logger.debug("FSEventsMonitor: no monitored paths specified")
            return false
        }

        // Verify paths exist
        let validPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !validPaths.isEmpty else {
            logger.error("FSEventsMonitor: all monitored paths do not exist")
            return false
        }

        // Create stream context
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Set flags
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

        // Create event stream
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
            logger.error("FSEventsMonitor: failed to create event stream")
            return false
        }

        FSEventStreamSetDispatchQueue(stream, queue)

        if !FSEventStreamStart(stream) {
            logger.error("FSEventsMonitor: failed to start event stream")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return false
        }

        isMonitoring = true
        logger.info("FSEventsMonitor started monitoring \(validPaths.count) paths")
        return true
    }

    /// Stop monitoring
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

        logger.info("FSEventsMonitor stopped")
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

        // Merge duplicate events
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

        // Trigger callback
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
