import Foundation
import Security

/// DMSAService XPC 委托
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {

    /// 单例引用 (用于信号处理)
    static weak var shared: ServiceDelegate?

    private let logger = Logger.forService("DMSAService")
    private let implementation = ServiceImplementation()
    private var activeConnections: [NSXPCConnection] = []
    private let connectionLock = NSLock()

    override init() {
        super.init()
        ServiceDelegate.shared = self
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
        newConnection.exportedInterface = NSXPCInterface(with: DMSAServiceProtocol.self)
        newConnection.exportedObject = implementation

        // 连接断开处理
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self = self, let conn = newConnection else { return }
            self.logger.info("连接断开: PID \(conn.processIdentifier)")
            self.removeConnection(conn)
        }

        newConnection.interruptionHandler = { [weak self] in
            self?.logger.warning("连接中断")
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

        // 通过 PID 获取代码引用
        let attributes: [CFString: Any] = [
            kSecGuestAttributePid: pid
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

    /// 启动同步调度器
    func startScheduler() async {
        logger.info("启动同步调度器...")
        await implementation.startScheduler()
    }

    /// 准备关闭
    func prepareForShutdown() async {
        logger.info("准备关闭 DMSAService...")

        // 停止调度器
        await implementation.stopScheduler()

        // 卸载所有 VFS
        await implementation.unmountAllVFS()

        // 等待同步完成
        await implementation.waitForSyncCompletion()

        logger.info("DMSAService 已安全关闭")
    }

    /// 重新加载配置
    func reloadConfiguration() async {
        logger.info("重新加载配置...")
        await implementation.reloadConfig()
    }
}
