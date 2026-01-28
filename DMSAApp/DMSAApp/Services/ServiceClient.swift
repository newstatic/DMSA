import Foundation

/// 版本检查结果
struct VersionCheckResult: Sendable {
    var externalConnected: Bool = false
    var needRebuildLocal: Bool = false
    var needRebuildExternal: Bool = false

    var needsAnyRebuild: Bool {
        return needRebuildLocal || needRebuildExternal
    }
}

/// 同步进度数据 (用于从服务端接收的 JSON 数据)
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

    // 完整初始化器
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
            case "idle": return "空闲"
            case "scanning": return "扫描文件"
            case "calculating": return "计算差异"
            case "checksumming": return "计算校验和"
            case "resolving": return "解决冲突"
            case "diffing": return "比较差异"
            case "syncing": return "同步文件"
            case "verifying": return "验证完整性"
            case "completed": return "已完成"
            case "failed": return "失败"
            case "cancelled": return "已取消"
            case "paused": return "已暂停"
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

/// 同步进度回调
protocol SyncProgressDelegate: AnyObject {
    func syncProgressDidUpdate(_ progress: SyncProgressData)
    func syncStatusDidChange(syncPairId: String, status: SyncStatus, message: String?)
    func serviceDidBecomeReady()
    func configDidUpdate()
}

// MARK: - XPC 回调处理器

/// XPC 回调处理器
/// 实现 DMSAClientProtocol，接收 Service 的主动通知
final class XPCCallbackHandler: NSObject, DMSAClientProtocol {

    private let logger = Logger.shared

    // 通知回调闭包
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

    // MARK: - DMSAClientProtocol 实现

    func onStateChanged(oldState: Int, newState: Int, data: Data?) {
        logger.info("[XPC回调] 状态变更: \(oldState) -> \(newState)")
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
        logger.info("[XPC回调] 索引就绪: \(syncPairId)")
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
        logger.info("[XPC回调] 同步状态变更: \(syncPairId) -> \(status)")
        DispatchQueue.main.async {
            self.syncStatusChangedHandler?(syncPairId, status, message)
        }
    }

    func onSyncCompleted(syncPairId: String, filesCount: Int, bytesCount: Int64) {
        logger.info("[XPC回调] 同步完成: \(syncPairId), \(filesCount) 文件")
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
        logger.warning("[XPC回调] 组件错误: \(component) - \(message)")
        DispatchQueue.main.async {
            self.componentErrorHandler?(component, code, message, isCritical)
        }
    }

    func onConfigUpdated() {
        logger.info("[XPC回调] 配置已更新")
        DispatchQueue.main.async {
            self.configUpdatedHandler?()
        }
    }

    func onServiceReady() {
        logger.info("[XPC回调] 服务就绪")
        DispatchQueue.main.async {
            self.serviceReadyHandler?()
        }
    }

    func onConflictDetected(data: Data) {
        logger.warning("[XPC回调] 冲突检测")
        DispatchQueue.main.async {
            self.conflictDetectedHandler?(data)
        }
    }

    func onDiskChanged(diskName: String, isConnected: Bool) {
        logger.info("[XPC回调] 磁盘变更: \(diskName) -> \(isConnected ? "连接" : "断开")")
        DispatchQueue.main.async {
            self.diskChangedHandler?(diskName, isConnected)
        }
    }
}

/// DMSAService XPC 客户端
/// 统一管理与 DMSAService 的通信
@MainActor
final class ServiceClient {

    // MARK: - Singleton

    static let shared = ServiceClient()

    // MARK: - Properties

    private let logger = Logger.shared
    private var connection: NSXPCConnection?
    private var proxy: DMSAServiceProtocol?
    private let connectionLock = NSLock()

    /// XPC 回调处理器
    private let callbackHandler = XPCCallbackHandler()

    /// XPC 调试日志开关
    private let xpcDebugEnabled = true

    // MARK: - XPC 日志辅助方法

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

    /// XPC 调用默认超时时间 (10秒)
    private let defaultTimeout: TimeInterval = 10

    /// 连接状态变更回调 (用于通知 UI)
    var onConnectionStateChanged: ((Bool) -> Void)?

    /// 同步进度代理
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

    // MARK: - XPC 回调设置

    /// 设置 XPC 回调处理器
    /// Service 通过双向 XPC 主动通知 App 状态变更
    private func setupXPCCallbacks() {
        // 状态变更
        callbackHandler.stateChangedHandler = { [weak self] oldState, newState, data in
            self?.handleXPCStateChanged(oldState: oldState, newState: newState, data: data)
        }

        // 服务就绪
        callbackHandler.serviceReadyHandler = { [weak self] in
            self?.logger.info("[XPC] 收到服务就绪通知")
            self?.progressDelegate?.serviceDidBecomeReady()
        }

        // 同步进度
        callbackHandler.syncProgressHandler = { [weak self] data in
            self?.handleXPCSyncProgress(data: data)
        }

        // 同步状态变更
        callbackHandler.syncStatusChangedHandler = { [weak self] syncPairId, status, message in
            self?.handleXPCSyncStatusChanged(syncPairId: syncPairId, status: status, message: message)
        }

        // 同步完成
        callbackHandler.syncCompletedHandler = { [weak self] syncPairId, filesCount, bytesCount in
            self?.logger.info("[XPC] 同步完成: \(syncPairId), \(filesCount) 文件")
        }

        // 配置更新
        callbackHandler.configUpdatedHandler = { [weak self] in
            self?.logger.info("[XPC] 收到配置更新通知")
            self?.progressDelegate?.configDidUpdate()
        }

        // 索引进度
        callbackHandler.indexProgressHandler = { [weak self] data in
            self?.handleXPCIndexProgress(data: data)
        }

        // 索引就绪
        callbackHandler.indexReadyHandler = { [weak self] syncPairId in
            self?.logger.info("[XPC] 索引就绪: \(syncPairId)")
        }

        // 淘汰进度
        callbackHandler.evictionProgressHandler = { [weak self] data in
            self?.handleXPCEvictionProgress(data: data)
        }

        // 组件错误
        callbackHandler.componentErrorHandler = { [weak self] component, code, message, isCritical in
            self?.handleXPCComponentError(component: component, code: code, message: message, isCritical: isCritical)
        }

        // 冲突检测
        callbackHandler.conflictDetectedHandler = { [weak self] data in
            self?.handleXPCConflictDetected(data: data)
        }

        // 磁盘变更
        callbackHandler.diskChangedHandler = { [weak self] diskName, isConnected in
            self?.handleXPCDiskChanged(diskName: diskName, isConnected: isConnected)
        }

        logger.info("已设置 XPC 回调处理器")
    }

    // MARK: - XPC 回调处理

    private func handleXPCStateChanged(oldState: Int, newState: Int, data: Data?) {
        logger.info("[XPC] 状态变更: \(oldState) -> \(newState)")

        // 转换为 ServiceState
        guard let newServiceState = ServiceState(rawValue: newState) else {
            logger.warning("未知的服务状态: \(newState)")
            return
        }

        // 通知 StateManager
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
        // 使用共享的 SyncProgress 类型解码
        do {
            let progress = try JSONDecoder().decode(SyncProgress.self, from: data)
            logger.debug("[XPC] 收到同步进度: \(progress.processedFiles)/\(progress.totalFiles)")

            // 转换为 SyncProgressData 供 delegate 使用
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
            logger.warning("无法解析同步进度数据: \(error)")
            if let str = String(data: data, encoding: .utf8) {
                logger.debug("原始数据: \(str.prefix(200))")
            }
        }
    }

    private func handleXPCSyncStatusChanged(syncPairId: String, status: Int, message: String?) {
        guard let syncStatus = SyncStatus(rawValue: status) else {
            logger.warning("未知的同步状态: \(status)")
            return
        }
        progressDelegate?.syncStatusDidChange(syncPairId: syncPairId, status: syncStatus, message: message)
    }

    private func handleXPCIndexProgress(data: Data) {
        // 发送本地通知更新 UI
        NotificationCenter.default.post(
            name: NSNotification.Name("DMSAIndexProgressUpdated"),
            object: nil,
            userInfo: ["data": data]
        )
    }

    private func handleXPCEvictionProgress(data: Data) {
        // 发送本地通知更新 UI
        NotificationCenter.default.post(
            name: NSNotification.Name("DMSAEvictionProgressUpdated"),
            object: nil,
            userInfo: ["data": data]
        )
    }

    private func handleXPCComponentError(component: String, code: Int, message: String, isCritical: Bool) {
        logger.warning("[XPC] 组件错误: \(component) (\(code)) - \(message), 严重=\(isCritical)")

        // 发送本地通知
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
        logger.warning("[XPC] 检测到冲突")

        // 发送本地通知
        NotificationCenter.default.post(
            name: NSNotification.Name("DMSAConflictDetected"),
            object: nil,
            userInfo: ["data": data]
        )
    }

    private func handleXPCDiskChanged(diskName: String, isConnected: Bool) {
        logger.info("[XPC] 磁盘变更: \(diskName) -> \(isConnected ? "连接" : "断开")")

        // 发送本地通知
        NotificationCenter.default.post(
            name: NSNotification.Name("DMSADiskChanged"),
            object: nil,
            userInfo: [
                "diskName": diskName,
                "isConnected": isConnected
            ]
        )
    }

    // MARK: - Connection Management

    /// 获取服务代理
    func getProxy() async throws -> DMSAServiceProtocol {
        connectionLock.lock()
        if let existingProxy = proxy {
            connectionLock.unlock()
            return existingProxy
        }
        connectionLock.unlock()

        return try await connect()
    }

    /// 连接到服务
    @discardableResult
    func connect() async throws -> DMSAServiceProtocol {
        connectionLock.lock()

        // 已连接
        if let existingProxy = proxy {
            connectionLock.unlock()
            return existingProxy
        }

        // 正在连接
        if isConnecting {
            connectionLock.unlock()
            // 等待连接完成
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

        logger.info("正在连接到 DMSAService...")

        // 创建 XPC 连接
        let newConnection = NSXPCConnection(machServiceName: Constants.XPCService.service, options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: DMSAServiceProtocol.self)

        // 设置 App 端回调接口，用于接收 Service 的主动通知
        newConnection.exportedInterface = NSXPCInterface(with: DMSAClientProtocol.self)
        newConnection.exportedObject = callbackHandler

        // 连接中断处理
        newConnection.interruptionHandler = { [weak self] in
            self?.logger.warning("XPC 连接中断")
            self?.handleConnectionInterrupted()
        }

        // 连接失效处理
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.error("XPC 连接失效")
            self?.handleConnectionInvalidated()
        }

        newConnection.resume()

        // 获取代理
        guard let remoteProxy = newConnection.remoteObjectProxyWithErrorHandler({ [weak self] (error: Error) in
            self?.logger.error("XPC 代理错误: \(error)")
            self?.handleConnectionError(error)
        }) as? DMSAServiceProtocol else {
            throw ServiceError.connectionFailed("无法获取服务代理")
        }

        connectionLock.lock()
        connection = newConnection
        proxy = remoteProxy
        connectionRetryCount = 0
        connectionLock.unlock()

        logger.info("已连接到 DMSAService")

        // 告知 Service 当前用户的 Home 目录
        let userHome = FileManager.default.homeDirectoryForCurrentUser.path
        await sendUserHome(userHome, proxy: remoteProxy)

        return remoteProxy
    }

    /// 发送用户 Home 目录到 Service
    private func sendUserHome(_ path: String, proxy: DMSAServiceProtocol) async {
        await withCheckedContinuation { continuation in
            proxy.setUserHome(path) { success in
                if success {
                    self.logger.info("已发送用户 Home 目录: \(path)")
                } else {
                    self.logger.warning("发送用户 Home 目录失败")
                }
                continuation.resume()
            }
        }
    }

    /// 断开连接
    func disconnect() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        connection?.invalidate()
        connection = nil
        proxy = nil

        logger.info("已断开 DMSAService 连接")
    }

    // MARK: - Connection Error Handling

    private func handleConnectionInterrupted() {
        connectionLock.lock()
        proxy = nil
        connectionLock.unlock()

        // 通知 UI 连接中断
        Task { @MainActor in
            onConnectionStateChanged?(false)
            progressDelegate?.syncStatusDidChange(syncPairId: "", status: .failed, message: "XPC 连接中断")
        }

        // 尝试重连
        Task { @MainActor in
            if connectionRetryCount < maxRetryCount {
                connectionRetryCount += 1
                logger.info("尝试重连 (第 \(connectionRetryCount) 次)...")
                try? await Task.sleep(nanoseconds: UInt64(connectionRetryCount) * 1_000_000_000)

                do {
                    try await connect()
                    // 重连成功，通知 UI
                    onConnectionStateChanged?(true)
                    progressDelegate?.serviceDidBecomeReady()
                    logger.info("XPC 重连成功")
                } catch {
                    logger.error("XPC 重连失败: \(error)")
                }
            } else {
                logger.error("已达到最大重连次数 (\(maxRetryCount))，停止重连")
            }
        }
    }

    private func handleConnectionInvalidated() {
        connectionLock.lock()
        connection = nil
        proxy = nil
        connectionLock.unlock()

        // 通知 UI 连接失效
        Task { @MainActor in
            onConnectionStateChanged?(false)
            progressDelegate?.syncStatusDidChange(syncPairId: "", status: .failed, message: "XPC 连接失效")
        }
    }

    private func handleConnectionError(_ error: Error) {
        logger.error("连接错误: \(error)")

        // 通知 UI 连接错误
        Task { @MainActor in
            onConnectionStateChanged?(false)
        }
    }

    // MARK: - XPC 超时包装

    /// 带超时的 XPC 调用包装
    private func withTimeout<T>(
        _ operation: String,
        timeout: TimeInterval? = nil,
        task: @escaping () async throws -> T
    ) async throws -> T {
        let timeoutDuration = timeout ?? defaultTimeout

        return try await withThrowingTaskGroup(of: T.self) { group in
            // 实际操作任务
            group.addTask {
                try await task()
            }

            // 超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutDuration * 1_000_000_000))
                throw ServiceError.timeout
            }

            // 返回先完成的任务结果
            guard let result = try await group.next() else {
                throw ServiceError.timeout
            }

            // 取消剩余任务
            group.cancelAll()

            self.logger.debug("[XPC] \(operation) 完成")
            return result
        }
    }

    /// 带超时的 XPC 调用包装 (无返回值版本)
    private func withTimeoutVoid(
        _ operation: String,
        timeout: TimeInterval? = nil,
        task: @escaping () async throws -> Void
    ) async throws {
        let _: Void = try await withTimeout(operation, timeout: timeout, task: task)
    }

    // MARK: - VFS Operations

    /// 挂载 VFS
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
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "挂载失败"))
                    }
                }
            }
        }
    }

    /// 卸载 VFS
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
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "卸载失败"))
                    }
                }
            }
        }
    }

    /// 获取 VFS 挂载信息
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

    /// 更新外部路径
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
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "更新失败"))
                    }
                }
            }
        }
    }

    /// 获取索引统计
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

    /// 设置外部存储离线状态
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

    /// 重建文件索引
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
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "索引构建失败"))
                    }
                }
            }
        }
    }

    // MARK: - Eviction Operations

    /// 获取淘汰配置
    func getEvictionConfig() async throws -> EvictionConfig {
        logXPCRequest("evictionGetConfig")

        return try await withTimeout("evictionGetConfig") { [self] in
            let proxy = try await getProxy()
            return try await withCheckedThrowingContinuation { continuation in
                proxy.evictionGetStats { data in
                    // 目前 evictionGetStats 返回的是 EvictionStats，这里需要用其他方式获取 config
                    // 暂时返回默认值，后续需要添加单独的 XPC 方法
                    continuation.resume(returning: EvictionConfig())
                }
            }
        }
    }

    /// 更新淘汰配置
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

    /// 获取淘汰统计
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

    /// 手动触发淘汰
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

    /// 立即同步
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
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "同步启动失败"))
                    }
                }
            }
        }
    }

    /// 同步所有
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
                        continuation.resume(throwing: ServiceError.operationFailed(error ?? "同步失败"))
                    }
                }
            }
        }
    }

    /// 暂停同步 (指定 syncPairId)
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

    /// 暂停同步 (所有)
    func pauseSync() async throws {
        try await pauseSync(syncPairId: "")
    }

    /// 恢复同步 (指定 syncPairId)
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

    /// 恢复同步 (所有)
    func resumeSync() async throws {
        try await resumeSync(syncPairId: "")
    }

    /// 取消同步 (指定 syncPairId)
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

    /// 取消同步 (所有)
    func cancelSync() async throws {
        try await cancelSync(syncPairId: "")
    }

    /// 获取同步状态
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

    /// 获取所有同步状态
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

    /// 获取同步进度 (返回的是 SyncProgressResponse，可解码的进度信息)
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

    /// 获取同步历史 (指定 syncPairId)
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

    /// 获取同步历史 (所有)
    func getSyncHistory(limit: Int = 50) async throws -> [SyncHistory] {
        return try await getAllSyncHistory(limit: limit)
    }

    // MARK: - Privileged Operations

    /// 锁定目录
    func lockDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedLockDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "锁定失败"))
                }
            }
        }
    }

    /// 解锁目录
    func unlockDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedUnlockDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "解锁失败"))
                }
            }
        }
    }

    /// 保护目录
    func protectDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedProtectDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "保护失败"))
                }
            }
        }
    }

    /// 取消保护目录
    func unprotectDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedUnprotectDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "取消保护失败"))
                }
            }
        }
    }

    /// 隐藏目录
    func hideDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedHideDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "隐藏失败"))
                }
            }
        }
    }

    /// 显示目录
    func unhideDirectory(_ path: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.privilegedUnhideDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "显示失败"))
                }
            }
        }
    }

    // MARK: - Common Operations

    /// 重新加载配置
    func reloadConfig() async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.reloadConfig { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "重载配置失败"))
                }
            }
        }
    }

    /// 准备关闭
    func prepareForShutdown() async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.prepareForShutdown { _ in
                continuation.resume()
            }
        }
    }

    /// 获取服务版本
    func getVersion() async throws -> String {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.getVersion { version in
                continuation.resume(returning: version)
            }
        }
    }

    /// 获取详细版本信息
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

    /// 检查版本兼容性
    /// - Returns: (兼容, 错误信息, 需要更新服务)
    func checkCompatibility() async throws -> (compatible: Bool, message: String?, needsServiceUpdate: Bool) {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.checkCompatibility(appVersion: Constants.version) { compatible, message, needsUpdate in
                continuation.resume(returning: (compatible, message, needsUpdate))
            }
        }
    }

    /// 健康检查
    func healthCheck() async throws -> Bool {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.healthCheck { isHealthy, _ in
                continuation.resume(returning: isHealthy)
            }
        }
    }

    /// 通知硬盘已连接
    func notifyDiskConnected(diskName: String, mountPoint: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.diskConnected(diskName: diskName, mountPoint: mountPoint) { _ in
                continuation.resume()
            }
        }
    }

    /// 通知硬盘已断开
    func notifyDiskDisconnected(diskName: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.diskDisconnected(diskName: diskName) { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - Data Query Operations

    /// 获取文件条目
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

    /// 获取所有文件条目
    func getAllFileEntries(syncPairId: String) async throws -> [FileEntry] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataGetAllFileEntries(syncPairId: syncPairId) { data in
                let entries = (try? JSONDecoder().decode([FileEntry].self, from: data)) ?? []
                continuation.resume(returning: entries)
            }
        }
    }

    /// 获取全部同步历史
    func getAllSyncHistory(limit: Int = 200) async throws -> [SyncHistory] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataGetSyncHistory(limit: limit) { data in
                continuation.resume(returning: SyncHistory.arrayFrom(data: data))
            }
        }
    }

    /// 获取文件同步记录 (指定 syncPairId)
    func getSyncFileRecords(syncPairId: String, limit: Int = 200) async throws -> [SyncFileRecord] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataGetSyncFileRecords(syncPairId: syncPairId, limit: limit) { data in
                continuation.resume(returning: SyncFileRecord.arrayFrom(data: data))
            }
        }
    }

    /// 获取所有文件同步记录
    func getAllSyncFileRecords(limit: Int = 200) async throws -> [SyncFileRecord] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataGetAllSyncFileRecords(limit: limit) { data in
                continuation.resume(returning: SyncFileRecord.arrayFrom(data: data))
            }
        }
    }

    /// 获取树版本
    func getTreeVersion(syncPairId: String, source: String) async throws -> String? {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataGetTreeVersion(syncPairId: syncPairId, source: source) { version in
                continuation.resume(returning: version)
            }
        }
    }

    /// 检查树版本
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

    /// 重建文件树
    func rebuildTree(rootPath: String, syncPairId: String, source: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataRebuildTree(rootPath: rootPath, syncPairId: syncPairId, source: source) { success, _, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "重建失败"))
                }
            }
        }
    }

    /// 使树版本失效
    func invalidateTreeVersion(syncPairId: String, source: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.dataInvalidateTreeVersion(syncPairId: syncPairId, source: source) { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - Config Operations

    /// 获取完整配置
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

    /// 更新完整配置
    func updateConfig(_ config: AppConfig) async throws {
        let proxy = try await getProxy()
        let data = try JSONEncoder().encode(config)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configUpdate(configData: data) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "配置更新失败"))
                }
            }
        }
    }

    /// 获取磁盘配置列表
    func getDisks() async throws -> [DiskConfig] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configGetDisks { data in
                let disks = (try? JSONDecoder().decode([DiskConfig].self, from: data)) ?? []
                continuation.resume(returning: disks)
            }
        }
    }

    /// 添加磁盘配置
    func addDisk(_ disk: DiskConfig) async throws {
        let proxy = try await getProxy()
        let data = try JSONEncoder().encode(disk)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configAddDisk(diskData: data) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "添加磁盘失败"))
                }
            }
        }
    }

    /// 移除磁盘配置
    func removeDisk(id: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configRemoveDisk(diskId: id) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "移除磁盘失败"))
                }
            }
        }
    }

    /// 获取同步对配置列表
    func getSyncPairs() async throws -> [SyncPairConfig] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configGetSyncPairs { data in
                let pairs = (try? JSONDecoder().decode([SyncPairConfig].self, from: data)) ?? []
                continuation.resume(returning: pairs)
            }
        }
    }

    /// 添加同步对配置
    func addSyncPair(_ pair: SyncPairConfig) async throws {
        let proxy = try await getProxy()
        let data = try JSONEncoder().encode(pair)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configAddSyncPair(pairData: data) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "添加同步对失败"))
                }
            }
        }
    }

    /// 移除同步对配置
    func removeSyncPair(id: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configRemoveSyncPair(pairId: id) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "移除同步对失败"))
                }
            }
        }
    }

    /// 获取通知配置
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

    /// 更新通知配置
    func updateNotificationConfig(_ config: NotificationConfig) async throws {
        let proxy = try await getProxy()
        let data = try JSONEncoder().encode(config)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.configUpdateNotifications(configData: data) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "更新通知配置失败"))
                }
            }
        }
    }

    // MARK: - Notification Operations

    /// 保存通知记录
    func saveNotificationRecord(_ record: NotificationRecord) async throws {
        let proxy = try await getProxy()
        let data = try JSONEncoder().encode(record)

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationSave(recordData: data) { _ in
                continuation.resume()
            }
        }
    }

    /// 获取通知记录
    func getNotificationRecords(limit: Int = 100) async throws -> [NotificationRecord] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationGetAll(limit: limit) { data in
                let records = (try? JSONDecoder().decode([NotificationRecord].self, from: data)) ?? []
                continuation.resume(returning: records)
            }
        }
    }

    /// 获取未读通知数量
    func getUnreadNotificationCount() async throws -> Int {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationGetUnreadCount { count in
                continuation.resume(returning: count)
            }
        }
    }

    /// 标记通知为已读
    func markNotificationAsRead(_ id: UInt64) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationMarkAsRead(recordId: id) { _ in
                continuation.resume()
            }
        }
    }

    /// 标记所有通知为已读
    func markAllNotificationsAsRead() async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationMarkAllAsRead { _ in
                continuation.resume()
            }
        }
    }

    /// 清除所有通知
    func clearAllNotifications() async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.notificationClearAll { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - State Query Operations

    /// 获取服务完整状态
    /// 返回 ServiceFullState，包含 globalState, 组件状态, 配置状态等
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
            return "服务连接失败: \(message)"
        case .operationFailed(let message):
            return "操作失败: \(message)"
        case .timeout:
            return "操作超时"
        case .notConnected:
            return "未连接到服务"
        }
    }
}

