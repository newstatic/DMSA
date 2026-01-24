import Foundation

/// VFS 服务 XPC 客户端
final class VFSClient: @unchecked Sendable {
    static let shared = VFSClient()

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

        let newConnection = NSXPCConnection(machServiceName: Constants.XPCService.vfs)
        newConnection.remoteObjectInterface = NSXPCInterface(with: VFSServiceProtocol.self)

        newConnection.invalidationHandler = { [weak self] in
            self?.connectionLock.lock()
            self?.connection = nil
            self?.connectionLock.unlock()
            Logger.shared.warning("VFS Service 连接已断开")
        }

        newConnection.interruptionHandler = { [weak self] in
            Logger.shared.warning("VFS Service 连接中断")
        }

        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    private func getProxy() -> VFSServiceProtocol? {
        return getConnection().remoteObjectProxyWithErrorHandler { error in
            Logger.shared.error("VFS Service 调用失败: \(error)")
        } as? VFSServiceProtocol
    }

    /// 断开连接
    func disconnect() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        connection?.invalidate()
        connection = nil
    }

    // MARK: - 挂载管理

    /// 挂载 VFS
    func mount(syncPairId: String,
                      localDir: String,
                      externalDir: String,
                      targetDir: String) async throws {

        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.mount(
                syncPairId: syncPairId,
                localDir: localDir,
                externalDir: externalDir,
                targetDir: targetDir
            ) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.vfsError(error ?? "挂载失败"))
                }
            }
        }
    }

    /// 卸载 VFS
    func unmount(syncPairId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.unmount(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.vfsError(error ?? "卸载失败"))
                }
            }
        }
    }

    /// 卸载所有 VFS
    func unmountAll() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.unmountAll { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.vfsError(error ?? "卸载失败"))
                }
            }
        }
    }

    /// 获取挂载状态
    func getMountStatus(syncPairId: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            getProxy()?.getMountStatus(syncPairId: syncPairId) { mounted, _ in
                continuation.resume(returning: mounted)
            }
        }
    }

    /// 获取所有挂载点
    func getAllMounts() async -> [MountInfo] {
        return await withCheckedContinuation { continuation in
            getProxy()?.getAllMounts { data in
                let mounts = MountInfo.arrayFrom(data: data)
                continuation.resume(returning: mounts)
            }
        }
    }

    // MARK: - 文件状态

    /// 获取文件状态
    func getFileStatus(virtualPath: String, syncPairId: String) async -> FileEntry? {
        return await withCheckedContinuation { continuation in
            getProxy()?.getFileStatus(virtualPath: virtualPath, syncPairId: syncPairId) { data in
                if let data = data,
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    continuation.resume(returning: FileEntry.from(dictionary: dict))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 获取文件位置
    func getFileLocation(virtualPath: String, syncPairId: String) async -> String {
        return await withCheckedContinuation { continuation in
            getProxy()?.getFileLocation(virtualPath: virtualPath, syncPairId: syncPairId) { location in
                continuation.resume(returning: location)
            }
        }
    }

    // MARK: - 配置更新

    /// 更新 EXTERNAL 路径
    func updateExternalPath(syncPairId: String, newPath: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.updateExternalPath(syncPairId: syncPairId, newPath: newPath) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.vfsError(error ?? "更新路径失败"))
                }
            }
        }
    }

    /// 设置 EXTERNAL 离线
    func setExternalOffline(syncPairId: String, offline: Bool) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.setExternalOffline(syncPairId: syncPairId, offline: offline) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.vfsError(error ?? "设置失败"))
                }
            }
        }
    }

    /// 设置只读模式
    func setReadOnly(syncPairId: String, readOnly: Bool) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.setReadOnly(syncPairId: syncPairId, readOnly: readOnly) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.vfsError(error ?? "设置失败"))
                }
            }
        }
    }

    /// 重新加载配置
    func reloadConfig() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.reloadConfig { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.vfsError(error ?? "重新加载失败"))
                }
            }
        }
    }

    // MARK: - 索引管理

    /// 重建索引
    func rebuildIndex(syncPairId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.rebuildIndex(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.vfsError(error ?? "重建索引失败"))
                }
            }
        }
    }

    /// 获取索引统计
    func getIndexStats(syncPairId: String) async -> IndexStats? {
        return await withCheckedContinuation { continuation in
            getProxy()?.getIndexStats(syncPairId: syncPairId) { data in
                if let data = data {
                    continuation.resume(returning: try? JSONDecoder().decode(IndexStats.self, from: data))
                } else {
                    continuation.resume(returning: nil)
                }
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
