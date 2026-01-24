import Foundation
import ServiceManagement
import Security

/// 特权操作客户端
/// 通过 XPC 与 SMJobBless 安装的 LaunchDaemon Helper 通信
class PrivilegedClient {

    // MARK: - 单例

    static let shared = PrivilegedClient()

    // MARK: - 属性

    private var connection: NSXPCConnection?
    private let connectionLock = NSLock()
    private let queue = DispatchQueue(label: "com.ttttt.dmsa.privileged-client")

    // MARK: - 初始化

    private init() {}

    // MARK: - Helper 管理

    /// 检查 Helper 是否已安装
    func isHelperInstalled() -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(kDMSAHelperMachServiceName).plist")
            return service.status == .enabled
        } else {
            // 旧版 macOS: 检查 LaunchDaemon plist 是否存在
            let plistPath = "/Library/LaunchDaemons/\(kDMSAHelperMachServiceName).plist"
            return FileManager.default.fileExists(atPath: plistPath)
        }
    }

    /// 获取 Helper 状态
    func getHelperStatus() -> HelperStatus {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(kDMSAHelperMachServiceName).plist")
            switch service.status {
            case .notRegistered:
                return .notInstalled
            case .enabled:
                return .installed
            case .requiresApproval:
                return .requiresApproval
            case .notFound:
                return .notFound
            @unknown default:
                return .unknown
            }
        } else {
            return isHelperInstalled() ? .installed : .notInstalled
        }
    }

    /// 安装 Helper
    func installHelper() throws {
        Logger.shared.info("PrivilegedClient: 开始安装 Helper")

        if #available(macOS 13.0, *) {
            try installHelperModern()
        } else {
            try installHelperLegacy()
        }

        Logger.shared.info("PrivilegedClient: Helper 安装成功")
    }

    @available(macOS 13.0, *)
    private func installHelperModern() throws {
        let service = SMAppService.daemon(plistName: "\(kDMSAHelperMachServiceName).plist")
        try service.register()
    }

    private func installHelperLegacy() throws {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authRef)

        guard status == errAuthorizationSuccess, let auth = authRef else {
            throw PrivilegedClientError.authorizationFailed
        }

        defer { AuthorizationFree(auth, []) }

        var error: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            kDMSAHelperMachServiceName as CFString,
            auth,
            &error
        )

        if !success {
            if let cfError = error?.takeRetainedValue() {
                throw cfError as Error
            }
            throw PrivilegedClientError.helperInstallFailed
        }
    }

    /// 卸载 Helper
    @available(macOS 13.0, *)
    func uninstallHelper() throws {
        let service = SMAppService.daemon(plistName: "\(kDMSAHelperMachServiceName).plist")
        try service.unregister()
        Logger.shared.info("PrivilegedClient: Helper 已卸载")
    }

    // MARK: - XPC 连接

    private func getHelper() throws -> DMSAHelperProtocol {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if connection == nil {
            connection = NSXPCConnection(machServiceName: kDMSAHelperMachServiceName, options: .privileged)
            connection?.remoteObjectInterface = NSXPCInterface(with: DMSAHelperProtocol.self)

            connection?.invalidationHandler = { [weak self] in
                self?.connectionLock.lock()
                self?.connection = nil
                self?.connectionLock.unlock()
                Logger.shared.warning("PrivilegedClient: XPC 连接已失效")
            }

            connection?.interruptionHandler = { [weak self] in
                Logger.shared.warning("PrivilegedClient: XPC 连接中断")
                self?.connectionLock.lock()
                self?.connection = nil
                self?.connectionLock.unlock()
            }

            connection?.resume()
            Logger.shared.debug("PrivilegedClient: XPC 连接已建立")
        }

        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
            Logger.shared.error("PrivilegedClient XPC 错误: \(error.localizedDescription)")
        }) as? DMSAHelperProtocol else {
            throw PrivilegedClientError.xpcConnectionFailed
        }

        return proxy
    }

    /// 断开 XPC 连接
    func disconnect() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        connection?.invalidate()
        connection = nil
        Logger.shared.debug("PrivilegedClient: XPC 连接已断开")
    }

    // MARK: - 公开接口 (async/await)

    /// 保护目录 (uchg + ACL deny + hidden)
    func protectDirectory(_ path: String) async throws {
        // 验证路径安全性
        guard PathValidator.isAllowedDMSAPath(path) else {
            throw PrivilegedClientError.invalidPath(path)
        }

        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.protectDirectory(path) { success, error in
                if success {
                    Logger.shared.info("PrivilegedClient: 目录已保护: \(path)")
                    continuation.resume()
                } else {
                    let err = PrivilegedClientError.operationFailed(error ?? "Unknown error")
                    Logger.shared.error("PrivilegedClient: 保护目录失败: \(path) - \(error ?? "Unknown")")
                    continuation.resume(throwing: err)
                }
            }
        }
    }

    /// 解除目录保护
    func unprotectDirectory(_ path: String) async throws {
        guard PathValidator.isAllowedDMSAPath(path) else {
            throw PrivilegedClientError.invalidPath(path)
        }

        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.unprotectDirectory(path) { success, error in
                if success {
                    Logger.shared.info("PrivilegedClient: 目录保护已解除: \(path)")
                    continuation.resume()
                } else {
                    let err = PrivilegedClientError.operationFailed(error ?? "Unknown error")
                    Logger.shared.error("PrivilegedClient: 解除保护失败: \(path) - \(error ?? "Unknown")")
                    continuation.resume(throwing: err)
                }
            }
        }
    }

    /// 锁定目录 (chflags uchg)
    func lockDirectory(_ path: String) async throws {
        guard PathValidator.isAllowedDMSAPath(path) else {
            throw PrivilegedClientError.invalidPath(path)
        }

        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.lockDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PrivilegedClientError.operationFailed(error ?? "Unknown"))
                }
            }
        }
    }

    /// 解锁目录 (chflags nouchg)
    func unlockDirectory(_ path: String) async throws {
        guard PathValidator.isAllowedDMSAPath(path) else {
            throw PrivilegedClientError.invalidPath(path)
        }

        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.unlockDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PrivilegedClientError.operationFailed(error ?? "Unknown"))
                }
            }
        }
    }

    /// 设置 ACL
    func setACL(_ path: String, deny: Bool, permissions: [String], user: String) async throws {
        guard PathValidator.isAllowedDMSAPath(path) else {
            throw PrivilegedClientError.invalidPath(path)
        }

        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.setACL(path, deny: deny, permissions: permissions, user: user) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PrivilegedClientError.operationFailed(error ?? "Unknown"))
                }
            }
        }
    }

    /// 移除 ACL
    func removeACL(_ path: String) async throws {
        guard PathValidator.isAllowedDMSAPath(path) else {
            throw PrivilegedClientError.invalidPath(path)
        }

        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.removeACL(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PrivilegedClientError.operationFailed(error ?? "Unknown"))
                }
            }
        }
    }

    /// 隐藏目录
    func hideDirectory(_ path: String) async throws {
        guard PathValidator.isAllowedDMSAPath(path) else {
            throw PrivilegedClientError.invalidPath(path)
        }

        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.hideDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PrivilegedClientError.operationFailed(error ?? "Unknown"))
                }
            }
        }
    }

    /// 取消隐藏目录
    func unhideDirectory(_ path: String) async throws {
        guard PathValidator.isAllowedDMSAPath(path) else {
            throw PrivilegedClientError.invalidPath(path)
        }

        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.unhideDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PrivilegedClientError.operationFailed(error ?? "Unknown"))
                }
            }
        }
    }

    /// 获取目录状态
    func getDirectoryStatus(_ path: String) async throws -> DirectoryProtectionStatus {
        guard PathValidator.isAllowedDMSAPath(path) else {
            throw PrivilegedClientError.invalidPath(path)
        }

        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.getDirectoryStatus(path) { isLocked, hasACL, isHidden, error in
                if let error = error {
                    continuation.resume(throwing: PrivilegedClientError.operationFailed(error))
                } else {
                    let status = DirectoryProtectionStatus(
                        isLocked: isLocked,
                        hasACL: hasACL,
                        isHidden: isHidden
                    )
                    continuation.resume(returning: status)
                }
            }
        }
    }

    /// 获取 Helper 版本
    func getHelperVersion() async throws -> String {
        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.getVersion { version in
                continuation.resume(returning: version)
            }
        }
    }

    // MARK: - 便捷方法

    /// 确保 Helper 已安装
    func ensureHelperInstalled() async throws {
        if !isHelperInstalled() {
            try installHelper()
        }

        // 验证版本
        do {
            let version = try await getHelperVersion()
            if version != kDMSAHelperProtocolVersion {
                Logger.shared.warning("PrivilegedClient: Helper 版本不匹配 (期望 \(kDMSAHelperProtocolVersion), 实际 \(version))")
                // 可能需要重新安装
            }
        } catch {
            Logger.shared.warning("PrivilegedClient: 无法获取 Helper 版本: \(error.localizedDescription)")
        }
    }
}

// MARK: - 类型定义

/// Helper 状态
enum HelperStatus {
    case notInstalled
    case installed
    case requiresApproval
    case notFound
    case unknown
}

/// 目录保护状态
struct DirectoryProtectionStatus {
    let isLocked: Bool      // chflags uchg
    let hasACL: Bool        // ACL deny 规则
    let isHidden: Bool      // chflags hidden

    var isFullyProtected: Bool {
        return isLocked && hasACL && isHidden
    }
}

// MARK: - 错误类型

enum PrivilegedClientError: Error, LocalizedError {
    case authorizationFailed
    case helperInstallFailed
    case xpcConnectionFailed
    case invalidPath(String)
    case operationFailed(String)
    case helperNotInstalled
    case versionMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .authorizationFailed:
            return "授权失败"
        case .helperInstallFailed:
            return "Helper 安装失败"
        case .xpcConnectionFailed:
            return "XPC 连接失败"
        case .invalidPath(let path):
            return "无效路径: \(path)"
        case .operationFailed(let message):
            return "操作失败: \(message)"
        case .helperNotInstalled:
            return "Helper 未安装"
        case .versionMismatch(let expected, let actual):
            return "Helper 版本不匹配 (期望 \(expected), 实际 \(actual))"
        }
    }
}
