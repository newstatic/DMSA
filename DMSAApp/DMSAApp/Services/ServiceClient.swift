import Foundation

/// Version check result
struct VersionCheckResult: Sendable {
    var externalConnected: Bool = false
    var needRebuildLocal: Bool = false
    var needRebuildExternal: Bool = false

    var needsAnyRebuild: Bool {
        return needRebuildLocal || needRebuildExternal
    }
}

/// Sync progress data (for JSON data received from service)
struct SyncProgressData: Codable {
    var syncPairId: String
    var status: SyncStatus
    var totalFiles: Int
    var processedFiles: Int
    var totalBytes: Int64
    var processedBytes: Int64
    var currentFile: String?
    var startTime: Date?
    var endTime: Date?
    var errorMessage: String?
    var speed: Int64
    var phase: SyncPhaseData

    // Full initializer
    init(syncPairId: String, status: SyncStatus, totalFiles: Int, processedFiles: Int,
         totalBytes: Int64, processedBytes: Int64, currentFile: String?,
         startTime: Date?, endTime: Date?, errorMessage: String?,
         speed: Int64, phase: SyncPhaseData) {
        self.syncPairId = syncPairId
        self.status = status
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.totalBytes = totalBytes
        self.processedBytes = processedBytes
        self.currentFile = currentFile
        self.startTime = startTime
        self.endTime = endTime
        self.errorMessage = errorMessage
        self.speed = speed
        self.phase = phase
    }

    struct SyncPhaseData: Codable, Equatable {
        var rawValue: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            rawValue = try container.decode(String.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        var description: String {
            switch rawValue {
            case "idle": return "Idle"
            case "scanning": return "Scanning files"
            case "calculating": return "Calculating diff"
            case "checksumming": return "Computing checksum"
            case "resolving": return "Resolving conflicts"
            case "diffing": return "Comparing diff"
            case "syncing": return "Syncing files"
            case "verifying": return "Verifying integrity"
            case "completed": return "Completed"
            case "failed": return "Failed"
            case "cancelled": return "Cancelled"
            case "paused": return "Paused"
            default: return rawValue
            }
        }

        static let idle = SyncPhaseData(rawValue: "idle")
        static let paused = SyncPhaseData(rawValue: "paused")

        init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

/// Sync progress callback
protocol SyncProgressDelegate: AnyObject {
    func syncProgressDidUpdate(_ progress: SyncProgressData)
    func syncStatusDidChange(syncPairId: String, status: SyncStatus, message: String?)
    func serviceDidBecomeReady()
    func configDidUpdate()
}

// MARK: - XPC Callback Handler

/// XPC callback handler
/// Implements DMSAClientProtocol to receive proactive notifications from Service
final class XPCCallbackHandler: NSObject, DMSAClientProtocol {

    private let logger = Logger.shared

    // Notification callback closures
    var stateChangedHandler: ((Int, Int, Data?) -> Void)?
    var indexProgressHandler: ((Data) -> Void)?
    var indexReadyHandler: ((String) -> Void)?
    var syncProgressHandler: ((Data) -> Void)?
    var syncStatusChangedHandler: ((String, Int, String?) -> Void)?
    var syncCompletedHandler: ((String, Int, Int64) -> Void)?
    var evictionProgressHandler: ((Data) -> Void)?
    var componentErrorHandler: ((String, Int, String, Bool) -> Void)?
    var configUpdatedHandler: (() -> Void)?
    var serviceReadyHandler: (() -> Void)?
    var conflictDetectedHandler: ((Data) -> Void)?
    var diskChangedHandler: ((String, Bool) -> Void)?
    var activitiesUpdatedHandler: ((Data) -> Void)?

    // MARK: - DMSAClientProtocol Implementation

    func onStateChanged(oldState: Int, newState: Int, data: Data?) {
        logger.info("[XPC Callback] State changed: \(oldState) -> \(newState)")
        DispatchQueue.main.async {
            self.stateChangedHandler?(oldState, newState, data)
        }
    }

    func onIndexProgress(data: Data) {
        DispatchQueue.main.async {
            self.indexProgressHandler?(data)
        }
    }

    func onIndexReady(syncPairId: String) {
        logger.info("[XPC Callback] Index ready: \(syncPairId)")
        DispatchQueue.main.async {
            self.indexReadyHandler?(syncPairId)
        }
    }

    func onSyncProgress(data: Data) {
        DispatchQueue.main.async {
            self.syncProgressHandler?(data)
        }
    }

    func onSyncStatusChanged(syncPairId: String, status: Int, message: String?) {
        logger.info("[XPC Callback] Sync status changed: \(syncPairId) -> \(status)")
        DispatchQueue.main.async {
            self.syncStatusChangedHandler?(syncPairId, status, message)
        }
    }

    func onSyncCompleted(syncPairId: String, filesCount: Int, bytesCount: Int64) {
        logger.info("[XPC Callback] Sync completed: \(syncPairId), \(filesCount) files")
        DispatchQueue.main.async {
            self.syncCompletedHandler?(syncPairId, filesCount, bytesCount)
        }
    }

    func onEvictionProgress(data: Data) {
        DispatchQueue.main.async {
            self.evictionProgressHandler?(data)
        }
    }

    func onComponentError(component: String, code: Int, message: String, isCritical: Bool) {
        logger.warning("[XPC Callback] Component error: \(component) - \(message)")
        DispatchQueue.main.async {
            self.componentErrorHandler?(component, code, message, isCritical)
        }
    }

    func onConfigUpdated() {
        logger.info("[XPC Callback] Config updated")
        DispatchQueue.main.async {
            self.configUpdatedHandler?()
        }
    }

    func onServiceReady() {
        logger.info("[XPC Callback] Service ready")
        DispatchQueue.main.async {
            self.serviceReadyHandler?()
        }
    }

    func onConflictDetected(data: Data) {
        logger.warning("[XPC Callback] Conflict detected")
        DispatchQueue.main.async {
            self.conflictDetectedHandler?(data)
        }
    }

    func onDiskChanged(diskName: String, isConnected: Bool) {
        logger.info("[XPC Callback] Disk changed: \(diskName) -> \(isConnected ? "connected" : "disconnected")")
        DispatchQueue.main.async {
            self.diskChangedHandler?(diskName, isConnected)
        }
    }

    func onActivitiesUpdated(data: Data) {
        logger.debug("[XPC Callback] Activities updated")
        DispatchQueue.main.async {
            self.activitiesUpdatedHandler?(data)
        }
    }
}

/// DMSAService XPC client
/// Unified communication manager for DMSAService
@MainActor
final class ServiceClient {

    // MARK: - Singleton

    static let shared = ServiceClient()

    // MARK: - Properties

    private let logger = Logger.shared
    private var connection: NSXPCConnection?
    private var proxy: DMSAServiceProtocol?
    private let connectionLock = NSLock()

    /// XPC callback handler
    private let callbackHandler = XPCCallbackHandler()

    /// XPC debug logging toggle
    private let xpcDebugEnabled = true

    // MARK: - XPC Log Helpers

    private func logXPCRequest(_ method: String, params: [String: Any] = [:]) {
        guard xpcDebugEnabled else { return }
        let paramsStr = params.isEmpty ? "" : " params=\(params)"
        logger.debug("[XPC→] \(method)\(paramsStr)")
    }

    private func logXPCResponse(_ method: String, success: Bool, result: Any? = nil, error: String? = nil) {
        guard xpcDebugEnabled else { return }
        if success {
            let resultStr = result.map { " result=\($0)" } ?? ""
            logger.debug("[XPC←] \(method) ✓\(resultStr)")
        } else {
            logger.debug("[XPC←] \(method) ✗ error=\(error ?? "unknown")")
        }
    }

    private func logXPCResponseData(_ method: String, data: Data?) {
        guard xpcDebugEnabled else { return }
        if let data = data, let str = String(data: data, encoding: .utf8) {
            let preview = str.count > 200 ? String(str.prefix(200)) + "..." : str
            logger.debug("[XPC←] \(method) data=\(preview)")
        } else {
            logger.debug("[XPC←] \(method) data=(nil or non-utf8)")
        }
    }

    private var isConnecting = false
    private var connectionRetryCount = 0
    private let maxRetryCount = 3

    /// XPC call default timeout (10s)
    private let defaultTimeout: TimeInterval = 10

    /// Connection state change callback (for UI notification)
    var onConnectionStateChanged: ((Bool) -> Void)?

    /// Sync progress delegate
    weak var progressDelegate: SyncProgressDelegate?

    var isConnected: Bool {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return connection != nil && proxy != nil
    }

    // MARK: - Initialization

    private init() {
        setupXPCCallbacks()
    }

    // MARK: - XPC Callback Setup

    /// Set up XPC callback handler
    /// Service proactively notifies App of state changes via bidirectional XPC
    private func setupXPCCallbacks() {
        // State changes
        callbackHandler.stateChangedHandler = { [weak self] oldState, newState, data in
            self?.handleXPCStateChanged(oldState: oldState, newState: newState, data: data)
        }

        // Service ready
        callbackHandler.serviceReadyHandler = { [weak self] in
            self?.logger.info("[XPC] Received service ready notification")
            self?.progressDelegate?.serviceDidBecomeReady()
        }

        // Sync progress
        callbackHandler.syncProgressHandler = { [weak self] data in
            self?.handleXPCSyncProgress(data: data)
        }

        // Sync status change
        callbackHandler.syncStatusChangedHandler = { [weak self] syncPairId, status, message in
            self?.handleXPCSyncStatusChanged(syncPairId: syncPairId, status: status, message: message)
        }

        // Sync completed
        callbackHandler.syncCompletedHandler = { [weak self] syncPairId, filesCount, bytesCount in
            self?.logger.info("[XPC] Sync completed: \(syncPairId), \(filesCount) files")
        }

        // Config updated
        callbackHandler.configUpdatedHandler = { [weak self] in
            self?.logger.info("[XPC] Received config update notification")
            self?.progressDelegate?.configDidUpdate()
        }

        // Index progress
        callbackHandler.indexProgressHandler = { [weak self] data in
            self?.handleXPCIndexProgress(data: data)
        }

        // Index ready
        callbackHandler.indexReadyHandler = { [weak self] syncPairId in
            self?.logger.info("[XPC] Index ready: \(syncPairId)")
        }

        // Eviction progress
        callbackHandler.evictionProgressHandler = { [weak self] data in
            self?.handleXPCEvictionProgress(data: data)
        }

        // Component error
        callbackHandler.componentErrorHandler = { [weak self] component, code, message, isCritical in
            self?.handleXPCComponentError(component: component, code: code, message: message, isCritical: isCritical)
        }

        // Conflict detected
        callbackHandler.conflictDetectedHandler = { [weak self] data in
            self?.handleXPCConflictDetected(data: data)
        }

        // Disk changed
        callbackHandler.diskChangedHandler = { [weak self] diskName, isConnected in
            self?.handleXPCDiskChanged(diskName: diskName, isConnected: isConnected)
        }

        // Activities updated
        callbackHandler.activitiesUpdatedHandler = { [weak self] data in
            self?.handleXPCActivitiesUpdated(data: data)
        }

        logger.info("XPC callback handler configured")
    }

    // MARK: - XPC Callback Processing

    private func handleXPCStateChanged(oldState: Int, newState: Int, data: Data?) {
        logger.info("[XPC] State changed: \(oldState) -> \(newState)")

        // Convert to ServiceState
        guard let newServiceState = ServiceState(rawValue: newState) else {
            logger.warning("Unknown service state: \(newState)")
            return
        }

        // Notify StateManager
        NotificationCenter.default.post(
            name: NSNotification.Name("DMSAServiceStateChanged"),
            object: nil,
            userInfo: [
                "oldState": oldState,
                "newState": newState,
                "serviceState": newServiceState
            ]
        )
    }

    private func handleXPCSyncProgress(data: Data) {
        // Decode using shared SyncProgress type
        do {
            let progress = try JSONDecoder().decode(SyncProgress.self, from: data)
            logger.debug("[XPC] Received sync progress: \(progress.processedFiles)/\(progress.totalFiles)")

            // Convert to SyncProgressData for delegate
            var progressData = SyncProgressData(
                syncPairId: progress.syncPairId,
                status: progress.status,
                totalFiles: progress.totalFiles,
                processedFiles: progress.processedFiles,
                totalBytes: progress.totalBytes,
                processedBytes: progress.processedBytes,
                currentFile: progress.currentFile,
                startTime: progress.startTime,
                endTime: progress.endTime,
                errorMessage: progress.errorMessage,
                speed: progress.speed,
                phase: SyncProgressData.SyncPhaseData(rawValue: progress.phase.rawValue)
            )
            progressDelegate?.syncProgressDidUpdate(progressData)
        } catch {
            logger.warning("Failed to decode sync progress data: \(error)")
            if let str = String(data: data, encoding: .utf8) {
                logger.debug("Raw data: \(str.prefix(200))")
            }
        }
    }

    private func handleXPCSyncStatusChanged(syncPairId: String, status: Int, message: String?) {
        guard let syncStatus = SyncStatus(rawValue: status) else {
            logger.warning("Unknown sync status: \(status)")
            return
        }
        progressDelegate?.syncStatusDidChange(syncPairId: syncPairId, status: syncStatus, message: message)
    }

    private func handleXPCIndexProgress(data: Data) {
        // Post local notification to update UI
        NotificationCenter.default.post(
            name: NSNotification.Name("DMSAIndexProgressUpdated"),
            object: nil,
            userInfo: ["data": data]
        )
    }

    private func handleXPCEvictionProgress(data: Data) {
        // Post local notification to update UI
        NotificationCenter.default.post(
            name: NSNotification.Name("DMSAEvictionProgressUpdated"),
            object: nil,
            userInfo: ["data": data]
        )
    }

    private func handleXPCComponentError(component: String, code: Int, message: String, isCritical: Bool) {
        logger.warning("[XPC] Component error: \(component) (\(code)) - \(message), critical=\(isCritical)")

        // Post local notification
        NotificationCenter.default.post(
            name: NSNotification.Name("DMSAComponentError"),
            object: nil,
            userInfo: [
                "component": component,
                "code": code,
                "message": message,
                "isCritical": isCritical
            ]
        )
    }

    private func handleXPCConflictDetected(data: Data) {
        logger.warning("[XPC] Conflict detected")

        // Post local notification
        NotificationCenter.default.post(
            name: NSNotification.Name("DMSAConflictDetected"),
            object: nil,
            userInfo: ["data": data]
        )
    }

    private func handleXPCDiskChanged(diskName: String, isConnected: Bool) {
        logger.info("[XPC] Disk changed: \(diskName) -> \(isConnected ? "connected" : "disconnected")")

        // Post local notification
        NotificationCenter.default.post(
            name: NSNotification.Name("DMSADiskChanged"),
            object: nil,
            userInfo: [
                "diskName": diskName,
                "isConnected": isConnected
            ]
        )
    }

    private func handleXPCActivitiesUpdated(data: Data) {
        guard let activities = try? JSONDecoder().decode([ActivityRecord].self, from: data) else {
            logger.warning("[XPC] Failed to decode activity data")
            return
        }

        // Post local notification
        NotificationCenter.default.post(
            name: NSNotification.Name("DMSAActivitiesUpdated"),
            object: nil,
            userInfo: ["activities": activities]
        )
    }

    // MARK: - Activity Queries

    /// Get recent activity records
    func getRecentActivities() async throws -> [ActivityRecord] {
        let proxy = try await getProxy()
        return try await withCheckedThrowingContinuation { continuation in
            proxy.getRecentActivities { data in
                let activities = (try? JSONDecoder().decode([ActivityRecord].self, from: data)) ?? []
                continuation.resume(returning: activities)
            }
        }
    }

    // MARK: - Connection Management

    /// Get service proxy
    func getProxy() async throws -> DMSAServiceProtocol {
        connectionLock.lock()
        if let existingProxy = proxy {
            connectionLock.unlock()
            return existingProxy
        }
        connectionLock.unlock()

        return try await connect()
    }

    /// Connect to service
    @discardableResult
    func connect() async throws -> DMSAServiceProtocol {
        connectionLock.lock()

        // Already connected
        if let existingProxy = proxy {
            connectionLock.unlock()
            return existingProxy
        }

        // Currently connecting
        if isConnecting {
            connectionLock.unlock()
            // Wait for connection to complete
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            return try await connect()
        }

        isConnecting = true
        connectionLock.unlock()

        defer {
            connectionLock.lock()
            isConnecting = false
            connectionLock.unlock()
        }

        logger.info("Connecting to DMSAService...")

        // Create XPC connection
        let newConnection = NSXPCConnection(machServiceName: Constants.XPCService.service, options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: DMSAServiceProtocol.self)

        // Set up App-side callback interface to receive proactive notifications from Service
        newConnection.exportedInterface = NSXPCInterface(with: DMSAClientProtocol.self)
        newConnection.exportedObject = callbackHandler

        // Connection interruption handler
        newConnection.interruptionHandler = { [weak self] in
            self?.logger.warning("XPC connection interrupted")
            self?.handleConnectionInterrupted()
        }

        // Connection invalidation handler
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.error("XPC connection invalidated")
            self?.handleConnectionInvalidated()
        }

        newConnection.resume()

        // Get proxy
        guard let remoteProxy = newConnection.remoteObjectProxyWithErrorHandler({ [weak self] (error: Error) in
            self?.logger.error("XPC proxy error: \(error)")
            self?.handleConnectionError(error)
        }) as? DMSAServiceProtocol else {
            throw ServiceError.connectionFailed("Unable to get service proxy")
        }

        connectionLock.lock()
        connection = newConnection
        proxy = remoteProxy
        connectionRetryCount = 0
        connectionLock.unlock()

        logger.info("Connected to DMSAService")

        // Inform Service of current user Home directory
        let userHome = FileManager.default.homeDirectoryForCurrentUser.path
        await sendUserHome(userHome, proxy: remoteProxy)

        return remoteProxy
    }

    /// Send user Home directory to Service
    private func sendUserHome(_ path: String, proxy: DMSAServiceProtocol) async {
        await withCheckedContinuation { continuation in
            proxy.setUserHome(path) { success in
                if success {
                    self.logger.info("Sent user Home directory: \(path)")
                } else {
                    self.logger.warning("Failed to send user Home directory")
                }
                continuation.resume()
            }
        }
    }

    /// Disconnect
    func disconnect() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        connection?.invalidate()
        connection = nil
        proxy = nil

        logger.info("Disconnected from DMSAService")
    }

    // MARK: - Connection Error Handling

    private func handleConnectionInterrupted() {
        connectionLock.lock()
        proxy = nil
        connectionLock.unlock()

        // Notify UI of connection interruption
        Task { @MainActor in
            onConnectionStateChanged?(false)
            progressDelegate?.syncStatusDidChange(syncPairId: "", status: .failed, message: "XPC connection interrupted")
        }

        // Attempt reconnection
        Task { @MainActor in
            if connectionRetryCount < maxRetryCount {
                connectionRetryCount += 1
                logger.info("Attempting reconnect (attempt \(connectionRetryCount) )...")
                try? await Task.sleep(nanoseconds: UInt64(connectionRetryCount) * 1_000_000_000)

                do {
                    try await connect()
                    // Reconnect successful, notify UI
                    onConnectionStateChanged?(true)
                    progressDelegate?.serviceDidBecomeReady()
                    logger.info("XPC reconnect successful")
                } catch {
                    logger.error("XPC reconnect failed: \(error)")
                }
            } else {
                logger.error("Max reconnect attempts reached (\(maxRetryCount))，stopping reconnection")
            }
        }
    }

    private func handleConnectionInvalidated() {
        connectionLock.lock()
        connection = nil
        proxy = nil
        connectionLock.unlock()

        // Notify UI of connection invalidation
        Task { @MainActor in
            onConnectionStateChanged?(false)
            progressDelegate?.syncStatusDidChange(syncPairId: "", status: .failed, message: "XPC connection invalidated")
        }
    }

    private func handleConnectionError(_ error: Error) {
        logger.error("Connection error: \(error)")

        // Notify UI of connection error
        Task { @MainActor in
            onConnectionStateChanged?(false)
        }
    }

    // MARK: - XPC Timeout Wrapper

    /// XPC call wrapper with timeout
    private func withTimeout<T>(
        _ operation: String,
        timeout: TimeInterval? = nil,
        task: @escaping () async throws -> T
    ) async throws -> T {
        let timeoutDuration = timeout ?? defaultTimeout

        return try await withThrowingTaskGroup(of: T.self) { group in
            // Actual operation task
            group.addTask {
                try await task()
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutDuration * 1_000_000_000))
                throw ServiceError.timeout
            }

            // Return result of first completed task
            guard let result = try await group.next() else {
                throw ServiceError.timeout
            }

            // Cancel remaining tasks
            group.cancelAll()

            self.logger.debug("[XPC] \(operation) completed")
            return result
        }
    }

    /// XPC call wrapper with timeout (void version)
    private func withTimeoutVoid(
        _ operation: String,
        timeout: TimeInterval? = nil,
        task: @escaping () async throws -> Void
    ) async throws {
        let _: Void = try await withTimeout(operation, timeout: timeout, task: task)
    }

    // MARK: - VFS Operations

    /// Mount VFS
    func mountVFS(syncPairId: String, localDir: String, externalDir: String?, targetDir: String) async throws {
        logXPCRequest("vfsMount", params: ["syncPairId": syncPairId, "localDir": localDir, "externalDir": externalDir ?? "nil", "targetDir": targetDir])

        try await withTimeoutVoid("vfsMount", timeout: 30) { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.vfsMount(syncPairId: syncPairId, localDir: localDir, externalDir: externalDir, targetDir: targetDir) { [weak self] success, error in
                    self?.logXPCResponse("vfsMount", success: success, error: error)
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "Mount failed"))
                    }
                }
            }
        }
    }

    /// Unmount VFS
    func unmountVFS(syncPairId: String) async throws {
        logXPCRequest("vfsUnmount", params: ["syncPairId": syncPairId])

        try await withTimeoutVoid("vfsUnmount", timeout: 30) { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.vfsUnmount(syncPairId: syncPairId) { [weak self] success, error in
                    self?.logXPCResponse("vfsUnmount", success: success, error: error)
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "Unmount failed"))
                    }
                }
            }
        }
    }

    /// Get VFS mount info
    func getVFSMounts() async throws -> [MountInfo] {
        logXPCRequest("vfsGetAllMounts")

        return try await withTimeout("vfsGetAllMounts") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.vfsGetAllMounts { [weak self] data in
                    self?.logXPCResponseData("vfsGetAllMounts", data: data)
                    continuation.resume(returning: MountInfo.arrayFrom(data: data))
                }
            }
        }
    }

    /// Update external path
    func updateExternalPath(syncPairId: String, newPath: String) async throws {
        logXPCRequest("vfsUpdateExternalPath", params: ["syncPairId": syncPairId, "newPath": newPath])

        try await withTimeoutVoid("vfsUpdateExternalPath") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.vfsUpdateExternalPath(syncPairId: syncPairId, newPath: newPath) { [weak self] success, error in
                    self?.logXPCResponse("vfsUpdateExternalPath", success: success, error: error)
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "Update failed"))
                    }
                }
            }
        }
    }

    /// Get index stats
    func getIndexStats(syncPairId: String) async throws -> IndexStats {
        logXPCRequest("vfsGetIndexStats", params: ["syncPairId": syncPairId])

        return try await withTimeout("vfsGetIndexStats", timeout: 30) { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.vfsGetIndexStats(syncPairId: syncPairId) { [weak self] data in
                    self?.logXPCResponseData("vfsGetIndexStats", data: data)
                    if let data = data,
                       let stats = try? JSONDecoder().decode(IndexStats.self, from: data) {
                        continuation.resume(returning: stats)
                    } else {
                        continuation.resume(returning: IndexStats())
                    }
                }
            }
        }
    }

    /// Set external storage offline state
    func setExternalOffline(syncPairId: String, offline: Bool) async throws {
        logXPCRequest("vfsSetExternalOffline", params: ["syncPairId": syncPairId, "offline": offline])

        try await withTimeoutVoid("vfsSetExternalOffline") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.vfsSetExternalOffline(syncPairId: syncPairId, offline: offline) { [weak self] success, _ in
                    self?.logXPCResponse("vfsSetExternalOffline", success: success)
                    continuation.resume()
                }
            }
        }
    }

    /// Rebuild file index
    func rebuildIndex(syncPairId: String) async throws {
        logXPCRequest("vfsRebuildIndex", params: ["syncPairId": syncPairId])

        try await withTimeoutVoid("vfsRebuildIndex", timeout: 60) { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.vfsRebuildIndex(syncPairId: syncPairId) { [weak self] success, error in
                    self?.logXPCResponse("vfsRebuildIndex", success: success, error: error)
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "Index build failed"))
                    }
                }
            }
        }
    }

    // MARK: - Eviction Operations

    /// Get eviction config
    func getEvictionConfig() async throws -> EvictionConfig {
        logXPCRequest("evictionGetConfig")

        return try await withTimeout("evictionGetConfig") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.evictionGetStats { data in
                    // evictionGetStats returns EvictionStats; need another way to get config
                    // Return defaults for now; need dedicated XPC method later
                    continuation.resume(returning: EvictionConfig())
                }
            }
        }
    }

    /// Update eviction config
    func updateEvictionConfig(triggerThreshold: Int64, targetFreeSpace: Int64, autoEnabled: Bool) async throws {
        logXPCRequest("evictionUpdateConfig", params: [
            "triggerThreshold": triggerThreshold,
            "targetFreeSpace": targetFreeSpace,
            "autoEnabled": autoEnabled
        ])

        try await withTimeoutVoid("evictionUpdateConfig") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.evictionUpdateConfig(
                    triggerThreshold: triggerThreshold,
                    targetFreeSpace: targetFreeSpace,
                    autoEnabled: autoEnabled
                ) { [weak self] success in
                    self?.logXPCResponse("evictionUpdateConfig", success: success)
                    continuation.resume()
                }
            }
        }
    }

    /// Get eviction stats
    func getEvictionStats() async throws -> EvictionStats {
        logXPCRequest("evictionGetStats")

        return try await withTimeout("evictionGetStats") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.evictionGetStats { data in
                    if let stats = try? JSONDecoder().decode(EvictionStats.self, from: data) {
                        continuation.resume(returning: stats)
                    } else {
                        continuation.resume(returning: EvictionStats(evictedCount: 0, evictedSize: 0, lastEvictionTime: nil, skippedDirty: 0, skippedLocked: 0, failedSync: 0))
                    }
                }
            }
        }
    }

    /// Manually trigger eviction
    func triggerEviction(syncPairId: String, targetFreeSpace: Int64? = nil) async throws -> EvictionResult {
        logXPCRequest("evictionTrigger", params: ["syncPairId": syncPairId, "targetFreeSpace": targetFreeSpace ?? 0])

        return try await withTimeout("evictionTrigger") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.evictionTrigger(syncPairId: syncPairId, targetFreeSpace: targetFreeSpace ?? 0) { success, freedSpace, errorMessage in
                    let result = EvictionResult(
                        evictedFiles: [],
                        freedSpace: freedSpace,
                        errors: errorMessage != nil ? [errorMessage!] : []
                    )
                    continuation.resume(returning: result)
                }
            }
        }
    }

    // MARK: - Sync Operations

    /// Sync immediately
    func syncNow(syncPairId: String) async throws {
        logXPCRequest("syncNow", params: ["syncPairId": syncPairId])

        try await withTimeoutVoid("syncNow") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.syncNow(syncPairId: syncPairId) { [weak self] success, error in
                    self?.logXPCResponse("syncNow", success: success, error: error)
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "Sync start failed"))
                    }
                }
            }
        }
    }

    /// Sync all
    func syncAll() async throws {
        logXPCRequest("syncAll")

        try await withTimeoutVoid("syncAll") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.syncAll { [weak self] success, error in
                    self?.logXPCResponse("syncAll", success: success, error: error)
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "Sync failed"))
                    }
                }
            }
        }
    }

    /// Pause sync (specific syncPairId)
    func pauseSync(syncPairId: String) async throws {
        logXPCRequest("syncPause", params: ["syncPairId": syncPairId])

        try await withTimeoutVoid("syncPause") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.syncPause(syncPairId: syncPairId) { [weak self] success, _ in
                    self?.logXPCResponse("syncPause", success: success)
                    continuation.resume()
                }
            }
        }
    }

    /// Pause sync (all)
    func pauseSync() async throws {
        try await pauseSync(syncPairId: "")
    }

    /// Resume sync (specific syncPairId)
    func resumeSync(syncPairId: String) async throws {
        logXPCRequest("syncResume", params: ["syncPairId": syncPairId])

        try await withTimeoutVoid("syncResume") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.syncResume(syncPairId: syncPairId) { [weak self] success, _ in
                    self?.logXPCResponse("syncResume", success: success)
                    continuation.resume()
                }
            }
        }
    }

    /// Resume sync (all)
    func resumeSync() async throws {
        try await resumeSync(syncPairId: "")
    }

    /// Cancel sync (specific syncPairId)
    func cancelSync(syncPairId: String) async throws {
        logXPCRequest("syncCancel", params: ["syncPairId": syncPairId])

        try await withTimeoutVoid("syncCancel") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.syncCancel(syncPairId: syncPairId) { [weak self] success, _ in
                    self?.logXPCResponse("syncCancel", success: success)
                    continuation.resume()
                }
            }
        }
    }

    /// Cancel sync (all)
    func cancelSync() async throws {
        try await cancelSync(syncPairId: "")
    }

    /// Get sync status
    func getSyncStatus(syncPairId: String) async throws -> SyncStatusInfo {
        logXPCRequest("syncGetStatus", params: ["syncPairId": syncPairId])

        return try await withTimeout("syncGetStatus") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.syncGetStatus(syncPairId: syncPairId) { [weak self] data in
                    self?.logXPCResponseData("syncGetStatus", data: data)
                    continuation.resume(returning: SyncStatusInfo.from(data: data) ?? SyncStatusInfo(syncPairId: syncPairId))
                }
            }
        }
    }

    /// Get all sync statuses
    func getAllSyncStatus() async throws -> [SyncStatusInfo] {
        logXPCRequest("syncGetAllStatus")

        return try await withTimeout("syncGetAllStatus") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.syncGetAllStatus { [weak self] data in
                    self?.logXPCResponseData("syncGetAllStatus", data: data)
                    continuation.resume(returning: SyncStatusInfo.arrayFrom(data: data))
                }
            }
        }
    }

    /// Get sync progress (returns SyncProgressResponse with decodable progress info)
    func getSyncProgress(syncPairId: String) async throws -> SyncProgressResponse? {
        logXPCRequest("syncGetProgress", params: ["syncPairId": syncPairId])

        return try await withTimeout("syncGetProgress") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.syncGetProgress(syncPairId: syncPairId) { [weak self] data in
                    self?.logXPCResponseData("syncGetProgress", data: data)
                    if let data = data {
                        continuation.resume(returning: SyncProgressResponse.from(data: data))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    /// Get sync history (specific syncPairId)
    func getSyncHistory(syncPairId: String, limit: Int = 50) async throws -> [SyncHistory] {
        logXPCRequest("syncGetHistory", params: ["syncPairId": syncPairId, "limit": limit])

        return try await withTimeout("syncGetHistory") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.syncGetHistory(syncPairId: syncPairId, limit: limit) { [weak self] data in
                    self?.logXPCResponseData("syncGetHistory", data: data)
                    continuation.resume(returning: SyncHistory.arrayFrom(data: data))
                }
            }
        }
    }

    /// Get sync history (all)
    func getSyncHistory(limit: Int = 50) async throws -> [SyncHistory] {
        return try await getAllSyncHistory(limit: limit)
    }

    // MARK: - Privileged Operations

    /// Lock directory
    func lockDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedLockDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Lock failed"))
                }
            }
        }
    }

    /// Unlock directory
    func unlockDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedUnlockDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Unlock failed"))
                }
            }
        }
    }

    /// Protect directory
    func protectDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedProtectDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Protection failed"))
                }
            }
        }
    }

    /// Unprotect directory
    func unprotectDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedUnprotectDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Unprotect failed"))
                }
            }
        }
    }

    /// Hide directory
    func hideDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedHideDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Hide failed"))
                }
            }
        }
    }

    /// Show directory
    func unhideDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedUnhideDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Show failed"))
                }
            }
        }
    }

    // MARK: - Common Operations

    /// Reload config
    func reloadConfig() async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.reloadConfig { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Config reload failed"))
                }
            }
        }
    }

    /// Prepare for shutdown
    func prepareForShutdown() async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.prepareForShutdown { _ in
                continuation.resume()
            }
        }
    }

    /// Get service version
    func getVersion() async throws -> String {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.getVersion { version in
                continuation.resume(returning: version)
            }
        }
    }

    /// Get detailed version info
    func getVersionInfo() async throws -> ServiceVersionInfo {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.getVersionInfo { data in
                if let info = ServiceVersionInfo.from(data: data) {
                    continuation.resume(returning: info)
                } else {
                    continuation.resume(returning: ServiceVersionInfo())
                }
            }
        }
    }

    /// Check version compatibility
    /// - Returns: (compatible, error message, needs service update)
    func checkCompatibility() async throws -> (compatible: Bool, message: String?, needsServiceUpdate: Bool) {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.checkCompatibility(appVersion: Constants.version) { compatible, message, needsUpdate in
                continuation.resume(returning: (compatible, message, needsUpdate))
            }
        }
    }

    /// Health check
    func healthCheck() async throws -> Bool {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.healthCheck { isHealthy, _ in
                continuation.resume(returning: isHealthy)
            }
        }
    }

    /// Notify disk connected
    func notifyDiskConnected(diskName: String, mountPoint: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.diskConnected(diskName: diskName, mountPoint: mountPoint) { _ in
                continuation.resume()
            }
        }
    }

    /// Notify disk disconnected
    func notifyDiskDisconnected(diskName: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.diskDisconnected(diskName: diskName) { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - Data Query Operations

    /// Get file entries
    func getFileEntry(virtualPath: String, syncPairId: String) async throws -> FileEntry? {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataGetFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) { data in
                if let data = data,
                   let entry = try? JSONDecoder().decode(FileEntry.self, from: data) {
                    continuation.resume(returning: entry)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Get all file entries
    func getAllFileEntries(syncPairId: String) async throws -> [FileEntry] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataGetAllFileEntries(syncPairId: syncPairId) { data in
                let entries = (try? JSONDecoder().decode([FileEntry].self, from: data)) ?? []
                continuation.resume(returning: entries)
            }
        }
    }

    /// Get all sync history
    func getAllSyncHistory(limit: Int = 200) async throws -> [SyncHistory] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataGetSyncHistory(limit: limit) { data in
                continuation.resume(returning: SyncHistory.arrayFrom(data: data))
            }
        }
    }

    /// Get file sync records (specific syncPairId)
    func getSyncFileRecords(syncPairId: String, limit: Int = 200) async throws -> [SyncFileRecord] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataGetSyncFileRecords(syncPairId: syncPairId, limit: limit) { data in
                continuation.resume(returning: SyncFileRecord.arrayFrom(data: data))
            }
        }
    }

    /// Get all file sync records (with pagination)
    func getAllSyncFileRecords(limit: Int = 200, offset: Int = 0) async throws -> [SyncFileRecord] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataGetAllSyncFileRecords(limit: limit, offset: offset) { data in
                continuation.resume(returning: SyncFileRecord.arrayFrom(data: data))
            }
        }
    }

    /// Get tree version
    func getTreeVersion(syncPairId: String, source: String) async throws -> String? {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataGetTreeVersion(syncPairId: syncPairId, source: source) { version in
                continuation.resume(returning: version)
            }
        }
    }

    /// Check tree version
    func checkTreeVersions(localDir: String, externalDir: String?, syncPairId: String) async throws -> VersionCheckResult {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataCheckTreeVersions(localDir: localDir, externalDir: externalDir, syncPairId: syncPairId) { data in
                var result = VersionCheckResult()
                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    result.externalConnected = dict["externalConnected"] as? Bool ?? false
                    result.needRebuildLocal = dict["needRebuildLocal"] as? Bool ?? true
                    result.needRebuildExternal = dict["needRebuildExternal"] as? Bool ?? false
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// Rebuild file tree
    func rebuildTree(rootPath: String, syncPairId: String, source: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataRebuildTree(rootPath: rootPath, syncPairId: syncPairId, source: source) { success, _, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Rebuild failed"))
                }
            }
        }
    }

    /// Invalidate tree version
    func invalidateTreeVersion(syncPairId: String, source: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataInvalidateTreeVersion(syncPairId: syncPairId, source: source) { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - Config Operations

    /// Get full config
    func getConfig() async throws -> AppConfig {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configGetAll { data in
                if let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
                    continuation.resume(returning: config)
                } else {
                    continuation.resume(returning: AppConfig())
                }
            }
        }
    }

    /// Update full config
    func updateConfig(_ config: AppConfig) async throws {
        let proxy = try await getProxy()
        let data = try JSONEncoder().encode(config)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configUpdate(configData: data) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Config update failed"))
                }
            }
        }
    }

    /// Get disk config list
    func getDisks() async throws -> [DiskConfig] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configGetDisks { data in
                let disks = (try? JSONDecoder().decode([DiskConfig].self, from: data)) ?? []
                continuation.resume(returning: disks)
            }
        }
    }

    /// Add disk config
    func addDisk(_ disk: DiskConfig) async throws {
        let proxy = try await getProxy()
        let data = try JSONEncoder().encode(disk)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configAddDisk(diskData: data) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Failed to add disk"))
                }
            }
        }
    }

    /// Remove disk config
    func removeDisk(id: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configRemoveDisk(diskId: id) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Failed to remove disk"))
                }
            }
        }
    }

    /// Get sync pair config list
    func getSyncPairs() async throws -> [SyncPairConfig] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configGetSyncPairs { data in
                let pairs = (try? JSONDecoder().decode([SyncPairConfig].self, from: data)) ?? []
                continuation.resume(returning: pairs)
            }
        }
    }

    /// Add sync pair config
    func addSyncPair(_ pair: SyncPairConfig) async throws {
        let proxy = try await getProxy()
        let data = try JSONEncoder().encode(pair)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configAddSyncPair(pairData: data) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Failed to add sync pair"))
                }
            }
        }
    }

    /// Remove sync pair config
    func removeSyncPair(id: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configRemoveSyncPair(pairId: id) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Failed to remove sync pair"))
                }
            }
        }
    }

    /// Get notification config
    func getNotificationConfig() async throws -> NotificationConfig {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configGetNotifications { data in
                if let config = try? JSONDecoder().decode(NotificationConfig.self, from: data) {
                    continuation.resume(returning: config)
                } else {
                    continuation.resume(returning: NotificationConfig())
                }
            }
        }
    }

    /// Update notification config
    func updateNotificationConfig(_ config: NotificationConfig) async throws {
        let proxy = try await getProxy()
        let data = try JSONEncoder().encode(config)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configUpdateNotifications(configData: data) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "Failed to update notification config"))
                }
            }
        }
    }

    // MARK: - Notification Operations

    /// Save notification record
    func saveNotificationRecord(_ record: NotificationRecord) async throws {
        let proxy = try await getProxy()
        let data = try JSONEncoder().encode(record)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationSave(recordData: data) { _ in
                continuation.resume()
            }
        }
    }

    /// Get notification records
    func getNotificationRecords(limit: Int = 100) async throws -> [NotificationRecord] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationGetAll(limit: limit) { data in
                let records = (try? JSONDecoder().decode([NotificationRecord].self, from: data)) ?? []
                continuation.resume(returning: records)
            }
        }
    }

    /// Get unread notification count
    func getUnreadNotificationCount() async throws -> Int {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationGetUnreadCount { count in
                continuation.resume(returning: count)
            }
        }
    }

    /// Mark notification as read
    func markNotificationAsRead(_ id: UInt64) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationMarkAsRead(recordId: id) { _ in
                continuation.resume()
            }
        }
    }

    /// Mark all notifications as read
    func markAllNotificationsAsRead() async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationMarkAllAsRead { _ in
                continuation.resume()
            }
        }
    }

    /// Clear all notifications
    func clearAllNotifications() async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationClearAll { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - State Query Operations

    /// Get full service state
    /// Returns ServiceFullState including globalState, component status, config state, etc.
    func getFullState() async throws -> ServiceFullState? {
        logXPCRequest("getFullState")

        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            proxy.getFullState { data in
                self?.logXPCResponseData("getFullState", data: data)
                if let state = try? JSONDecoder().decode(ServiceFullState.self, from: data) {
                    continuation.resume(returning: state)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

}

// MARK: - ServiceError

enum ServiceError: LocalizedError {
    case connectionFailed(String)
    case operationFailed(String)
    case timeout
    case notConnected

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Service connection failed: \(message)"
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        case .timeout:
            return "Operation timeout"
        case .notConnected:
            return "Not connected to service"
        }
    }
}

