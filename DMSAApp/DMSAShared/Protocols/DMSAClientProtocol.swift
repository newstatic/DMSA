import Foundation

/// DMSA client XPC callback protocol
/// Service proactively notifies App of state changes via this protocol
@objc public protocol DMSAClientProtocol {

    // MARK: - State Notifications

    /// Global state changed
    /// - Parameters:
    ///   - oldState: Old state (ServiceState rawValue)
    ///   - newState: New state (ServiceState rawValue)
    ///   - data: Additional data (JSON)
    func onStateChanged(oldState: Int, newState: Int, data: Data?)

    /// Index progress update
    /// - Parameter data: IndexProgress JSON
    func onIndexProgress(data: Data)

    /// Index ready
    /// - Parameter syncPairId: Sync pair ID
    func onIndexReady(syncPairId: String)

    // MARK: - Sync Notifications

    /// Sync progress update
    /// - Parameter data: SyncProgress JSON
    func onSyncProgress(data: Data)

    /// Sync status changed
    /// - Parameters:
    ///   - syncPairId: Sync pair ID
    ///   - status: Sync status (SyncStatus rawValue)
    ///   - message: Additional message
    func onSyncStatusChanged(syncPairId: String, status: Int, message: String?)

    /// Sync completed
    /// - Parameters:
    ///   - syncPairId: Sync pair ID
    ///   - filesCount: Synced file count
    ///   - bytesCount: Synced byte count
    func onSyncCompleted(syncPairId: String, filesCount: Int, bytesCount: Int64)

    // MARK: - Eviction Notifications

    /// Eviction progress update
    /// - Parameter data: EvictionProgress JSON
    func onEvictionProgress(data: Data)

    // MARK: - Error Notifications

    /// Component error
    /// - Parameters:
    ///   - component: Component name
    ///   - code: Error code
    ///   - message: Error message
    ///   - isCritical: Whether critical error
    func onComponentError(component: String, code: Int, message: String, isCritical: Bool)

    // MARK: - Other Notifications

    /// Config updated
    func onConfigUpdated()

    /// Service ready
    func onServiceReady()

    /// Conflict detected
    /// - Parameter data: Conflict details JSON
    func onConflictDetected(data: Data)

    /// Disk status changed
    /// - Parameters:
    ///   - diskName: Disk name
    ///   - isConnected: Whether connected
    func onDiskChanged(diskName: String, isConnected: Bool)

    // MARK: - Activity Push

    /// Recent activities updated (latest 5)
    /// - Parameter data: [ActivityRecord] JSON
    func onActivitiesUpdated(data: Data)
}

// MARK: - XPC Interface Config

public extension DMSAClientProtocol {
    static var interfaceName: String { "com.ttttt.dmsa.client" }

    static func createInterface() -> NSXPCInterface {
        return NSXPCInterface(with: DMSAClientProtocol.self)
    }
}
