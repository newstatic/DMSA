import Foundation

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

    private var isConnecting = false
    private var connectionRetryCount = 0
    private let maxRetryCount = 3

    var isConnected: Bool {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return connection != nil && proxy != nil
    }

    // MARK: - Initialization

    private init() {}

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
        return remoteProxy
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

        // 尝试重连
        Task { @MainActor in
            if connectionRetryCount < maxRetryCount {
                connectionRetryCount += 1
                logger.info("尝试重连 (第 \(connectionRetryCount) 次)...")
                try? await Task.sleep(nanoseconds: UInt64(connectionRetryCount) * 1_000_000_000)
                try? await connect()
            }
        }
    }

    private func handleConnectionInvalidated() {
        connectionLock.lock()
        connection = nil
        proxy = nil
        connectionLock.unlock()
    }

    private func handleConnectionError(_ error: Error) {
        logger.error("连接错误: \(error)")
    }

    // MARK: - VFS Operations

    /// 挂载 VFS
    func mountVFS(syncPairId: String, localDir: String, externalDir: String?, targetDir: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.vfsMount(syncPairId: syncPairId, localDir: localDir, externalDir: externalDir, targetDir: targetDir) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "挂载失败"))
                }
            }
        }
    }

    /// 卸载 VFS
    func unmountVFS(syncPairId: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.vfsUnmount(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "卸载失败"))
                }
            }
        }
    }

    /// 获取 VFS 挂载信息
    func getVFSMounts() async throws -> [MountInfo] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.vfsGetAllMounts { data in
                continuation.resume(returning: MountInfo.arrayFrom(data: data))
            }
        }
    }

    /// 更新外部路径
    func updateExternalPath(syncPairId: String, newPath: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.vfsUpdateExternalPath(syncPairId: syncPairId, newPath: newPath) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "更新失败"))
                }
            }
        }
    }

    /// 设置外部存储离线状态
    func setExternalOffline(syncPairId: String, offline: Bool) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.vfsSetExternalOffline(syncPairId: syncPairId, offline: offline) { success, _ in
                continuation.resume()
            }
        }
    }

    // MARK: - Sync Operations

    /// 立即同步
    func syncNow(syncPairId: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.syncNow(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "同步启动失败"))
                }
            }
        }
    }

    /// 同步所有
    func syncAll() async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.syncAll { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.operationFailed(error ?? "同步失败"))
                }
            }
        }
    }

    /// 暂停同步
    func pauseSync(syncPairId: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.syncPause(syncPairId: syncPairId) { success, _ in
                continuation.resume()
            }
        }
    }

    /// 恢复同步
    func resumeSync(syncPairId: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.syncResume(syncPairId: syncPairId) { success, _ in
                continuation.resume()
            }
        }
    }

    /// 取消同步
    func cancelSync(syncPairId: String) async throws {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.syncCancel(syncPairId: syncPairId) { success, _ in
                continuation.resume()
            }
        }
    }

    /// 获取同步状态
    func getSyncStatus(syncPairId: String) async throws -> SyncStatusInfo {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.syncGetStatus(syncPairId: syncPairId) { data in
                continuation.resume(returning: SyncStatusInfo.from(data: data) ?? SyncStatusInfo(syncPairId: syncPairId))
            }
        }
    }

    /// 获取所有同步状态
    func getAllSyncStatus() async throws -> [SyncStatusInfo] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.syncGetAllStatus { data in
                continuation.resume(returning: SyncStatusInfo.arrayFrom(data: data))
            }
        }
    }

    /// 获取同步进度 (返回的是 SyncProgressResponse，可解码的进度信息)
    func getSyncProgress(syncPairId: String) async throws -> SyncProgressResponse? {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.syncGetProgress(syncPairId: syncPairId) { data in
                if let data = data {
                    continuation.resume(returning: SyncProgressResponse.from(data: data))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 获取同步历史
    func getSyncHistory(syncPairId: String, limit: Int = 50) async throws -> [SyncHistory] {
        let proxy = try await getProxy()

        return try await withCheckedThrowingContinuation { continuation in
            proxy.syncGetHistory(syncPairId: syncPairId, limit: limit) { data in
                continuation.resume(returning: SyncHistory.arrayFrom(data: data))
            }
        }
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

