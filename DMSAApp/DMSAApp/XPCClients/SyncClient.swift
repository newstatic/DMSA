import Foundation

/// Sync 服务 XPC 客户端
final class SyncClient: @unchecked Sendable {
    static let shared = SyncClient()

    private var connection: NSXPCConnection?
    private let connectionLock = NSLock()
    private let logger = Logger.shared

    private init() {}

    // MARK: - 连接管理

    private func getConnection() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let existing = connection {
            return existing
        }

        let newConnection = NSXPCConnection(machServiceName: Constants.XPCService.sync)
        newConnection.remoteObjectInterface = NSXPCInterface(with: SyncServiceProtocol.self)

        newConnection.invalidationHandler = { [weak self] in
            self?.connectionLock.lock()
            self?.connection = nil
            self?.connectionLock.unlock()
            Logger.shared.warning("Sync Service 连接已断开")
        }

        newConnection.interruptionHandler = {
            Logger.shared.warning("Sync Service 连接中断")
        }

        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    private func getProxy() -> SyncServiceProtocol? {
        return getConnection().remoteObjectProxyWithErrorHandler { error in
            Logger.shared.error("Sync Service 调用失败: \(error)")
        } as? SyncServiceProtocol
    }

    /// 断开连接
    func disconnect() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        connection?.invalidate()
        connection = nil
    }

    // MARK: - 同步控制

    /// 立即同步
    func syncNow(syncPairId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.syncNow(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.syncError(error ?? "同步失败"))
                }
            }
        }
    }

    /// 同步所有
    func syncAll() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.syncAll { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.syncError(error ?? "同步失败"))
                }
            }
        }
    }

    /// 同步单个文件
    func syncFile(virtualPath: String, syncPairId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.syncFile(virtualPath: virtualPath, syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.syncError(error ?? "同步失败"))
                }
            }
        }
    }

    /// 暂停同步
    func pauseSync(syncPairId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.pauseSync(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.syncError(error ?? "暂停失败"))
                }
            }
        }
    }

    /// 恢复同步
    func resumeSync(syncPairId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.resumeSync(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.syncError(error ?? "恢复失败"))
                }
            }
        }
    }

    /// 取消同步
    func cancelSync(syncPairId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.cancelSync(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.syncError(error ?? "取消失败"))
                }
            }
        }
    }

    // MARK: - 状态查询

    /// 获取同步状态
    func getSyncStatus(syncPairId: String) async -> SyncStatusInfo {
        return await withCheckedContinuation { continuation in
            getProxy()?.getSyncStatus(syncPairId: syncPairId) { data in
                if let status = SyncStatusInfo.from(data: data) {
                    continuation.resume(returning: status)
                } else {
                    continuation.resume(returning: SyncStatusInfo(syncPairId: syncPairId))
                }
            }
        }
    }

    /// 获取所有同步状态
    func getAllSyncStatus() async -> [SyncStatusInfo] {
        return await withCheckedContinuation { continuation in
            getProxy()?.getAllSyncStatus { data in
                let statuses = (try? JSONDecoder().decode([SyncStatusInfo].self, from: data)) ?? []
                continuation.resume(returning: statuses)
            }
        }
    }

    /// 获取待同步队列
    func getPendingQueue(syncPairId: String) async -> [String] {
        return await withCheckedContinuation { continuation in
            getProxy()?.getPendingQueue(syncPairId: syncPairId) { data in
                let queue = (try? JSONDecoder().decode([String].self, from: data)) ?? []
                continuation.resume(returning: queue)
            }
        }
    }

    /// 获取同步进度
    func getSyncProgress(syncPairId: String) async -> SyncProgressResponse? {
        return await withCheckedContinuation { continuation in
            getProxy()?.getSyncProgress(syncPairId: syncPairId) { data in
                if let data = data {
                    continuation.resume(returning: SyncProgressResponse.from(data: data))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 获取同步历史
    func getSyncHistory(syncPairId: String, limit: Int = 50) async -> [SyncHistory] {
        return await withCheckedContinuation { continuation in
            getProxy()?.getSyncHistory(syncPairId: syncPairId, limit: limit) { data in
                let history = SyncHistory.arrayFrom(data: data)
                continuation.resume(returning: history)
            }
        }
    }

    /// 获取同步统计
    func getSyncStatistics(syncPairId: String) async -> SyncStatisticsResponse? {
        return await withCheckedContinuation { continuation in
            getProxy()?.getSyncStatistics(syncPairId: syncPairId) { data in
                if let data = data {
                    continuation.resume(returning: SyncStatisticsResponse.from(data: data))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - 脏文件管理

    /// 获取脏文件列表
    func getDirtyFiles(syncPairId: String) async -> [String] {
        return await withCheckedContinuation { continuation in
            getProxy()?.getDirtyFiles(syncPairId: syncPairId) { data in
                let files = (try? JSONDecoder().decode([String].self, from: data)) ?? []
                continuation.resume(returning: files)
            }
        }
    }

    /// 标记文件为脏
    func markFileDirty(virtualPath: String, syncPairId: String) async {
        await withCheckedContinuation { continuation in
            getProxy()?.markFileDirty(virtualPath: virtualPath, syncPairId: syncPairId) { _ in
                continuation.resume()
            }
        }
    }

    /// 清除文件脏标记
    func clearFileDirty(virtualPath: String, syncPairId: String) async {
        await withCheckedContinuation { continuation in
            getProxy()?.clearFileDirty(virtualPath: virtualPath, syncPairId: syncPairId) { _ in
                continuation.resume()
            }
        }
    }

    // MARK: - 配置

    /// 重新加载配置
    func reloadConfig() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.reloadConfig { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.syncError(error ?? "重新加载失败"))
                }
            }
        }
    }

    // MARK: - 硬盘事件

    /// 通知硬盘已连接
    func diskConnected(diskName: String, mountPoint: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            getProxy()?.diskConnected(diskName: diskName, mountPoint: mountPoint) { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// 通知硬盘已断开
    func diskDisconnected(diskName: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            getProxy()?.diskDisconnected(diskName: diskName) { success in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - 生命周期

    /// 准备关闭
    func prepareForShutdown() async -> Bool {
        return await withCheckedContinuation { continuation in
            getProxy()?.prepareForShutdown { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// 获取版本
    func getVersion() async -> String? {
        return await withCheckedContinuation { continuation in
            guard let proxy = getProxy() else {
                continuation.resume(returning: nil)
                return
            }
            proxy.getVersion { version in
                continuation.resume(returning: version)
            }
        }
    }

    /// 健康检查
    func healthCheck() async -> (Bool, String?) {
        return await withCheckedContinuation { continuation in
            getProxy()?.healthCheck { healthy, message in
                continuation.resume(returning: (healthy, message))
            }
        }
    }

    /// 检查服务是否可用
    func isAvailable() async -> Bool {
        let version = await getVersion()
        return version != nil
    }
}
