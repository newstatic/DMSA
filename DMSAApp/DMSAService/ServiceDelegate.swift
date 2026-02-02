import Foundation
import Security

/// DMSAService XPC Delegate
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {

    /// Singleton reference (for signal handling and global access)
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

        // Verify connection source
        guard verifyConnection(newConnection) else {
            logger.error("Rejected unauthorized connection: PID \(newConnection.processIdentifier)")
            return false
        }

        logger.info("Accepted new connection: PID \(newConnection.processIdentifier)")

        // Configure Service -> App interface (exportedInterface)
        newConnection.exportedInterface = NSXPCInterface(with: DMSAServiceProtocol.self)
        newConnection.exportedObject = implementation

        // Configure App -> Service callback interface (remoteObjectInterface)
        // Allows Service to proactively notify App via this interface
        newConnection.remoteObjectInterface = NSXPCInterface(with: DMSAClientProtocol.self)

        // Connection invalidation handler
        newConnection.invalidationHandler = { [weak self, weak newConnection] in
            guard let self = self, let conn = newConnection else { return }
            self.logger.info("Connection invalidated: PID \(conn.processIdentifier)")
            self.removeConnection(conn)
        }

        newConnection.interruptionHandler = { [weak self] in
            self?.logger.warning("Connection interrupted")
        }

        // Track active connections
        addConnection(newConnection)

        newConnection.resume()
        return true
    }

    // MARK: - Connection Verification

    private func verifyConnection(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier

        // Allow all connections in debug mode
        #if DEBUG
        logger.debug("Debug mode: allowing PID \(pid) to connect")
        return true
        #endif

        // Production mode: verify code signature
        var code: SecCode?

        // Get code reference via PID
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
            logger.error("Failed to get code reference: \(status)")
            return false
        }

        // Verify signature requirements
        var requirement: SecRequirement?
        let requirementString = """
            identifier "com.ttttt.dmsa" and anchor apple generic
            """

        let reqStatus = SecRequirementCreateWithString(requirementString as CFString, [], &requirement)

        guard reqStatus == errSecSuccess, let requirement = requirement else {
            logger.error("Failed to create signature requirement: \(reqStatus)")
            return false
        }

        let validStatus = SecCodeCheckValidity(code, [], requirement)

        if validStatus != errSecSuccess {
            logger.error("Signature verification failed: \(validStatus)")
            return false
        }

        return true
    }

    // MARK: - Connection Management

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

    /// Get client proxies for all active connections
    private func getClientProxies() -> [DMSAClientProtocol] {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        return activeConnections.compactMap { connection in
            connection.remoteObjectProxy as? DMSAClientProtocol
        }
    }

    // MARK: - Client Notifications

    /// Notify all connected clients of state change
    func notifyStateChanged(oldState: Int, newState: Int, data: Data?) {
        logger.debug("[XPC Notify] State changed: \(oldState) -> \(newState)")
        for client in getClientProxies() {
            client.onStateChanged(oldState: oldState, newState: newState, data: data)
        }
    }

    /// Notify index progress
    func notifyIndexProgress(data: Data) {
        for client in getClientProxies() {
            client.onIndexProgress(data: data)
        }
    }

    /// Notify index ready
    func notifyIndexReady(syncPairId: String) {
        logger.debug("[XPC Notify] Index ready: \(syncPairId)")
        for client in getClientProxies() {
            client.onIndexReady(syncPairId: syncPairId)
        }
    }

    /// Notify sync progress
    func notifySyncProgress(data: Data) {
        for client in getClientProxies() {
            client.onSyncProgress(data: data)
        }
    }

    /// Notify sync status change
    func notifySyncStatusChanged(syncPairId: String, status: Int, message: String?) {
        logger.debug("[XPC Notify] Sync status changed: \(syncPairId) -> \(status)")
        for client in getClientProxies() {
            client.onSyncStatusChanged(syncPairId: syncPairId, status: status, message: message)
        }
    }

    /// Notify sync completed
    func notifySyncCompleted(syncPairId: String, filesCount: Int, bytesCount: Int64) {
        logger.debug("[XPC Notify] Sync completed: \(syncPairId), \(filesCount) files")
        for client in getClientProxies() {
            client.onSyncCompleted(syncPairId: syncPairId, filesCount: filesCount, bytesCount: bytesCount)
        }
    }

    /// Notify eviction progress
    func notifyEvictionProgress(data: Data) {
        for client in getClientProxies() {
            client.onEvictionProgress(data: data)
        }
    }

    /// Notify component error
    func notifyComponentError(component: String, code: Int, message: String, isCritical: Bool) {
        logger.debug("[XPC Notify] Component error: \(component) - \(message)")
        for client in getClientProxies() {
            client.onComponentError(component: component, code: code, message: message, isCritical: isCritical)
        }
    }

    /// Notify configuration updated
    func notifyConfigUpdated() {
        logger.debug("[XPC Notify] Configuration updated")
        for client in getClientProxies() {
            client.onConfigUpdated()
        }
    }

    /// Notify service ready
    func notifyServiceReady() {
        logger.debug("[XPC Notify] Service ready")
        for client in getClientProxies() {
            client.onServiceReady()
        }
    }

    /// Notify conflict detected
    func notifyConflictDetected(data: Data) {
        logger.debug("[XPC Notify] Conflict detected")
        for client in getClientProxies() {
            client.onConflictDetected(data: data)
        }
    }

    /// Notify disk status change
    func notifyDiskChanged(diskName: String, isConnected: Bool) {
        logger.debug("[XPC Notify] Disk changed: \(diskName) -> \(isConnected ? "connected" : "disconnected")")
        for client in getClientProxies() {
            client.onDiskChanged(diskName: diskName, isConnected: isConnected)
        }
    }

    /// Notify activities updated
    func notifyActivitiesUpdated(data: Data) {
        logger.debug("[XPC Notify] Activities updated")
        for client in getClientProxies() {
            client.onActivitiesUpdated(data: data)
        }
    }

    // MARK: - Lifecycle

    /// Auto-mount configured VFS
    func autoMount() async {
        logger.info("Starting auto-mount...")
        await implementation.autoMount()
    }

    /// Start sync scheduler
    func startScheduler() async {
        logger.info("Starting sync scheduler...")
        await implementation.startScheduler()
    }

    /// Prepare for shutdown
    func prepareForShutdown() async {
        logger.info("Preparing to shut down DMSAService...")

        // Stop scheduler
        await implementation.stopScheduler()

        // Unmount all VFS
        await implementation.unmountAllVFS()

        // Wait for sync completion
        await implementation.waitForSyncCompletion()

        logger.info("DMSAService shut down safely")
    }

    /// Reload configuration
    func reloadConfiguration() async {
        logger.info("Reloading configuration...")
        await implementation.reloadConfig()
    }
}
