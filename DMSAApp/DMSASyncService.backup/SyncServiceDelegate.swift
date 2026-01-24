import Foundation

/// Sync Service XPC 委托
final class SyncServiceDelegate: NSObject, NSXPCListenerDelegate {

    /// 单例引用 (用于信号处理)
    static weak var shared: SyncServiceDelegate?

    private let logger = Logger.forService("Sync")
    private let implementation = SyncServiceImplementation()
    private var activeConnections: [NSXPCConnection] = []
    private let connectionLock = NSLock()

    // VFS 写入通知监听
    private var notificationObserver: NSObjectProtocol?

    override init() {
        super.init()
        SyncServiceDelegate.shared = self
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
        newConnection.exportedInterface = NSXPCInterface(with: SyncServiceProtocol.self)
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
        #if DEBUG
        return true
        #endif

        // 生产模式：验证代码签名
        var code: SecCode?
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
            return false
        }

        var requirement: SecRequirement?
        let requirementString = "identifier \"com.ttttt.dmsa\" and anchor apple generic"

        SecRequirementCreateWithString(requirementString as CFString, [], &requirement)

        guard let requirement = requirement else {
            return false
        }

        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
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

    /// 启动服务
    func start() async {
        logger.info("启动同步服务...")

        // 注册 VFS 写入通知
        setupVFSNotificationObserver()

        // 启动定时同步调度器
        await implementation.startScheduler()

        // 恢复未完成的同步任务
        await implementation.resumePendingTasks()
    }

    /// 准备关闭
    func prepareForShutdown() async {
        logger.info("准备关闭 Sync Service...")

        // 取消通知监听
        if let observer = notificationObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            notificationObserver = nil
        }

        // 停止调度器并等待当前任务完成
        await implementation.shutdown()

        logger.info("Sync Service 已安全关闭")
    }

    /// 重新加载配置
    func reloadConfiguration() async {
        logger.info("重新加载配置...")
        await implementation.reloadConfig()
    }

    // MARK: - VFS 通知监听

    private func setupVFSNotificationObserver() {
        // 监听 VFS 文件写入通知 (使用 DistributedNotificationCenter)
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(Constants.Notifications.fileWritten),
            object: nil,
            queue: OperationQueue()
        ) { [weak self] _ in
            self?.handleFileWritten()
        }

        logger.info("已注册 VFS 写入通知监听")
    }

    private func handleFileWritten() {
        // 读取共享状态获取写入的文件信息
        let state = SharedState.load()

        guard let path = state.lastWrittenPath,
              let syncPairId = state.lastWrittenSyncPair else {
            return
        }

        logger.debug("收到文件写入通知: \(path)")

        // 调度同步任务 (带防抖)
        Task {
            await implementation.scheduleSync(file: path, syncPairId: syncPairId)
        }
    }
}

// MARK: - audit_token 扩展

extension NSXPCConnection {
    var auditToken: audit_token_t {
        var token = audit_token_t()
        return token
    }
}
