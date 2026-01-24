import Foundation
import ServiceManagement

/// Helper 服务 XPC 客户端
final class HelperClient: @unchecked Sendable {
    static let shared = HelperClient()

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

        let newConnection = NSXPCConnection(machServiceName: Constants.XPCService.helper)
        newConnection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        newConnection.invalidationHandler = { [weak self] in
            self?.connectionLock.lock()
            self?.connection = nil
            self?.connectionLock.unlock()
            Logger.shared.warning("Helper Service 连接已断开")
        }

        newConnection.interruptionHandler = {
            Logger.shared.warning("Helper Service 连接中断")
        }

        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    private func getProxy() -> HelperProtocol? {
        return getConnection().remoteObjectProxyWithErrorHandler { error in
            Logger.shared.error("Helper Service 调用失败: \(error)")
        } as? HelperProtocol
    }

    /// 断开连接
    func disconnect() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        connection?.invalidate()
        connection = nil
    }

    // MARK: - 目录锁定

    /// 锁定目录
    func lockDirectory(_ path: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.lockDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.helperError(error ?? "锁定失败"))
                }
            }
        }
    }

    /// 解锁目录
    func unlockDirectory(_ path: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.unlockDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.helperError(error ?? "解锁失败"))
                }
            }
        }
    }

    // MARK: - ACL 管理

    /// 设置 ACL
    func setACL(_ path: String, deny: Bool, permissions: [String], user: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.setACL(path, deny: deny, permissions: permissions, user: user) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.helperError(error ?? "设置 ACL 失败"))
                }
            }
        }
    }

    /// 移除 ACL
    func removeACL(_ path: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.removeACL(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.helperError(error ?? "移除 ACL 失败"))
                }
            }
        }
    }

    // MARK: - 目录可见性

    /// 隐藏目录
    func hideDirectory(_ path: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.hideDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.helperError(error ?? "隐藏失败"))
                }
            }
        }
    }

    /// 取消隐藏目录
    func unhideDirectory(_ path: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.unhideDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.helperError(error ?? "取消隐藏失败"))
                }
            }
        }
    }

    // MARK: - 复合操作

    /// 保护目录 (uchg + ACL + hidden)
    func protectDirectory(_ path: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.protectDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.helperError(error ?? "保护失败"))
                }
            }
        }
    }

    /// 取消保护目录
    func unprotectDirectory(_ path: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.unprotectDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.helperError(error ?? "取消保护失败"))
                }
            }
        }
    }

    // MARK: - 文件系统操作

    /// 创建目录 (需要特权)
    func createDirectory(_ path: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.createDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.helperError(error ?? "创建失败"))
                }
            }
        }
    }

    /// 移动文件/目录 (需要特权)
    func moveItem(from source: String, to destination: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.moveItem(from: source, to: destination) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.helperError(error ?? "移动失败"))
                }
            }
        }
    }

    /// 删除文件/目录 (需要特权)
    func removeItem(_ path: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.removeItem(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.helperError(error ?? "删除失败"))
                }
            }
        }
    }

    // MARK: - 生命周期

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

    // MARK: - 服务安装

    /// 检查 Helper 是否已安装
    func isInstalled() -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "com.ttttt.dmsa.helper.plist")
            return service.status == .enabled
        } else {
            // 旧版本检查文件是否存在
            return FileManager.default.fileExists(
                atPath: "/Library/PrivilegedHelperTools/com.ttttt.dmsa.helper"
            )
        }
    }

    /// 安装所有服务
    func installServices() async throws {
        if #available(macOS 13.0, *) {
            try await installWithSMAppService()
        } else {
            try installWithSMJobBless()
        }
    }

    @available(macOS 13.0, *)
    private func installWithSMAppService() async throws {
        // VFS Service
        let vfsService = SMAppService.daemon(plistName: "com.ttttt.dmsa.vfs.plist")
        try vfsService.register()

        // Sync Service
        let syncService = SMAppService.daemon(plistName: "com.ttttt.dmsa.sync.plist")
        try syncService.register()

        // Helper Service
        let helperService = SMAppService.daemon(plistName: "com.ttttt.dmsa.helper.plist")
        try helperService.register()

        logger.info("服务安装成功 (SMAppService)")
    }

    private func installWithSMJobBless() throws {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authRef)

        guard status == errSecSuccess, let auth = authRef else {
            throw HelperError.authorizationFailed
        }

        defer { AuthorizationFree(auth, []) }

        var error: Unmanaged<CFError>?

        // 安装各个服务
        for service in [Constants.XPCService.vfs, Constants.XPCService.sync, Constants.XPCService.helper] {
            let success = SMJobBless(
                kSMDomainSystemLaunchd,
                service as CFString,
                auth,
                &error
            )

            if !success {
                throw HelperError.installFailed(error?.takeRetainedValue().localizedDescription ?? "未知错误")
            }
        }

        logger.info("服务安装成功 (SMJobBless)")
    }

    /// 卸载服务
    @available(macOS 13.0, *)
    func uninstallServices() async throws {
        let vfsService = SMAppService.daemon(plistName: "com.ttttt.dmsa.vfs.plist")
        try await vfsService.unregister()

        let syncService = SMAppService.daemon(plistName: "com.ttttt.dmsa.sync.plist")
        try await syncService.unregister()

        let helperService = SMAppService.daemon(plistName: "com.ttttt.dmsa.helper.plist")
        try await helperService.unregister()

        logger.info("服务卸载成功")
    }
}
