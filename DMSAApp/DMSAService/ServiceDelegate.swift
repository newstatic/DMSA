import Foundation
import Security

/// DMSAService XPC 委托
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {

    /// 单例引用 (用于信号处理和全局访问)
    static weak var shared: ServiceDelegate?

    private let logger = Logger.forService("DMSAService")
    let implementation = ServiceImplementation()
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

        // 配置 Service -> App 接口 (exportedInterface)
        newConnection.exportedInterface = NSXPCInterface(with: DMSAServiceProtocol.self)
        newConnection.exportedObject = implementation

        // 配置 App -> Service 回调接口 (remoteObjectInterface)
        // 允许 Service 通过此接口主动通知 App
        newConnection.remoteObjectInterface = NSXPCInterface(with: DMSAClientProtocol.self)

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

    /// 获取所有活跃连接的客户端代理
    private func getClientProxies() -> [DMSAClientProtocol] {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        return activeConnections.compactMap { connection in
            connection.remoteObjectProxy as? DMSAClientProtocol
        }
    }

    // MARK: - 客户端通知

    /// 通知所有连接的客户端状态变更
    func notifyStateChanged(oldState: Int, newState: Int, data: Data?) {
        logger.debug("[XPC通知] 状态变更: \(oldState) -> \(newState)")
        for client in getClientProxies() {
            client.onStateChanged(oldState: oldState, newState: newState, data: data)
        }
    }

    /// 通知索引进度
    func notifyIndexProgress(data: Data) {
        for client in getClientProxies() {
            client.onIndexProgress(data: data)
        }
    }

    /// 通知索引就绪
    func notifyIndexReady(syncPairId: String) {
        logger.debug("[XPC通知] 索引就绪: \(syncPairId)")
        for client in getClientProxies() {
            client.onIndexReady(syncPairId: syncPairId)
        }
    }

    /// 通知同步进度
    func notifySyncProgress(data: Data) {
        for client in getClientProxies() {
            client.onSyncProgress(data: data)
        }
    }

    /// 通知同步状态变更
    func notifySyncStatusChanged(syncPairId: String, status: Int, message: String?) {
        logger.debug("[XPC通知] 同步状态变更: \(syncPairId) -> \(status)")
        for client in getClientProxies() {
            client.onSyncStatusChanged(syncPairId: syncPairId, status: status, message: message)
        }
    }

    /// 通知同步完成
    func notifySyncCompleted(syncPairId: String, filesCount: Int, bytesCount: Int64) {
        logger.debug("[XPC通知] 同步完成: \(syncPairId), \(filesCount) 文件")
        for client in getClientProxies() {
            client.onSyncCompleted(syncPairId: syncPairId, filesCount: filesCount, bytesCount: bytesCount)
        }
    }

    /// 通知淘汰进度
    func notifyEvictionProgress(data: Data) {
        for client in getClientProxies() {
            client.onEvictionProgress(data: data)
        }
    }

    /// 通知组件错误
    func notifyComponentError(component: String, code: Int, message: String, isCritical: Bool) {
        logger.debug("[XPC通知] 组件错误: \(component) - \(message)")
        for client in getClientProxies() {
            client.onComponentError(component: component, code: code, message: message, isCritical: isCritical)
        }
    }

    /// 通知配置更新
    func notifyConfigUpdated() {
        logger.debug("[XPC通知] 配置已更新")
        for client in getClientProxies() {
            client.onConfigUpdated()
        }
    }

    /// 通知服务就绪
    func notifyServiceReady() {
        logger.debug("[XPC通知] 服务就绪")
        for client in getClientProxies() {
            client.onServiceReady()
        }
    }

    /// 通知冲突检测
    func notifyConflictDetected(data: Data) {
        logger.debug("[XPC通知] 冲突检测")
        for client in getClientProxies() {
            client.onConflictDetected(data: data)
        }
    }

    /// 通知磁盘状态变更
    func notifyDiskChanged(diskName: String, isConnected: Bool) {
        logger.debug("[XPC通知] 磁盘变更: \(diskName) -> \(isConnected ? "连接" : "断开")")
        for client in getClientProxies() {
            client.onDiskChanged(diskName: diskName, isConnected: isConnected)
        }
    }

    /// 通知活动更新
    func notifyActivitiesUpdated(data: Data) {
        logger.debug("[XPC通知] 活动更新")
        for client in getClientProxies() {
            client.onActivitiesUpdated(data: data)
        }
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
