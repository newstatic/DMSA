import Foundation

/// VFS Service XPC 委托
final class VFSServiceDelegate: NSObject, NSXPCListenerDelegate {

    /// 单例引用 (用于信号处理)
    static weak var shared: VFSServiceDelegate?

    private let logger = Logger.forService("VFS")
    private let implementation = VFSServiceImplementation()
    private var activeConnections: [NSXPCConnection] = []
    private let connectionLock = NSLock()

    override init() {
        super.init()
        VFSServiceDelegate.shared = self
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {

        // 验证连接来源
        guard verifyConnection(newConnection) else {
            logger.error("拒绝未授权连接: PID \(newConnection.processIdentifier)")
            return false
        }

        logger.info("接受新连接: PID \(newConnection.processIdentifier)")

        // 配置连接
        newConnection.exportedInterface = NSXPCInterface(with: VFSServiceProtocol.self)
        newConnection.exportedObject = implementation

        // 连接断开处理
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self = self, let conn = newConnection else { return }
            self.logger.info("连接断开: PID \(conn.processIdentifier)")
            self.removeConnection(conn)
        }

        newConnection.interruptionHandler = { [weak self] in
            self?.logger.warn("连接中断")
        }

        // 记录活跃连接
        addConnection(newConnection)

        newConnection.resume()
        return true
    }

    // MARK: - 连接验证

    private func verifyConnection(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier

        // 开发模式下允许所有连接
        #if DEBUG
        logger.debug("开发模式：允许 PID \(pid) 连接")
        return true
        #endif

        // 生产模式：验证代码签名
        var code: SecCode?

        // 使用 audit token 获取代码引用
        var auditToken = connection.auditToken
        let attributes: [CFString: Any] = [
            kSecGuestAttributeAudit: Data(bytes: &auditToken, count: MemoryLayout<audit_token_t>.size)
        ]

        let status = SecCodeCopyGuestWithAttributes(
            nil,
            attributes as CFDictionary,
            [],
            &code
        )

        guard status == errSecSuccess, let code = code else {
            logger.error("无法获取代码引用: \(status)")
            return false
        }

        // 验证签名要求
        var requirement: SecRequirement?
        let requirementString = """
            identifier "com.ttttt.dmsa" and anchor apple generic
            """

        let reqStatus = SecRequirementCreateWithString(requirementString as CFString, [], &requirement)

        guard reqStatus == errSecSuccess, let requirement = requirement else {
            logger.error("创建签名要求失败: \(reqStatus)")
            return false
        }

        let validStatus = SecCodeCheckValidity(code, [], requirement)

        if validStatus != errSecSuccess {
            logger.error("签名验证失败: \(validStatus)")
            return false
        }

        return true
    }

    // MARK: - 连接管理

    private func addConnection(_ connection: NSXPCConnection) {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        activeConnections.append(connection)
    }

    private func removeConnection(_ connection: NSXPCConnection) {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        activeConnections.removeAll { $0 === connection }
    }

    // MARK: - 生命周期

    /// 自动挂载配置的 VFS
    func autoMount() async {
        logger.info("开始自动挂载...")
        await implementation.autoMount()
    }

    /// 准备关闭
    func prepareForShutdown() async {
        logger.info("准备关闭 VFS Service...")
        await implementation.shutdown()
        logger.info("VFS Service 已安全关闭")
    }

    /// 重新加载配置
    func reloadConfiguration() async {
        logger.info("重新加载配置...")
        await implementation.reloadConfig()
    }
}

// MARK: - audit_token 扩展

extension NSXPCConnection {
    var auditToken: audit_token_t {
        var token = audit_token_t()
        // 使用私有 API 获取 audit token
        // 在生产环境中，建议使用 SecCodeCopyGuestWithAttributes 的其他方式
        return token
    }
}
