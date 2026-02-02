import Foundation

/// DMSA 客户端 XPC 回调协议
/// Service 通过此协议主动通知 App 状态变更
@objc public protocol DMSAClientProtocol {

    // MARK: - 状态通知

    /// 全局状态变更
    /// - Parameters:
    ///   - oldState: 旧状态 (ServiceState rawValue)
    ///   - newState: 新状态 (ServiceState rawValue)
    ///   - data: 附加数据 (JSON)
    func onStateChanged(oldState: Int, newState: Int, data: Data?)

    /// 索引进度更新
    /// - Parameter data: IndexProgress JSON
    func onIndexProgress(data: Data)

    /// 索引就绪
    /// - Parameter syncPairId: 同步对 ID
    func onIndexReady(syncPairId: String)

    // MARK: - 同步通知

    /// 同步进度更新
    /// - Parameter data: SyncProgress JSON
    func onSyncProgress(data: Data)

    /// 同步状态变更
    /// - Parameters:
    ///   - syncPairId: 同步对 ID
    ///   - status: 同步状态 (SyncStatus rawValue)
    ///   - message: 附加消息
    func onSyncStatusChanged(syncPairId: String, status: Int, message: String?)

    /// 同步完成
    /// - Parameters:
    ///   - syncPairId: 同步对 ID
    ///   - filesCount: 同步文件数
    ///   - bytesCount: 同步字节数
    func onSyncCompleted(syncPairId: String, filesCount: Int, bytesCount: Int64)

    // MARK: - 淘汰通知

    /// 淘汰进度更新
    /// - Parameter data: EvictionProgress JSON
    func onEvictionProgress(data: Data)

    // MARK: - 错误通知

    /// 组件错误
    /// - Parameters:
    ///   - component: 组件名称
    ///   - code: 错误码
    ///   - message: 错误消息
    ///   - isCritical: 是否严重错误
    func onComponentError(component: String, code: Int, message: String, isCritical: Bool)

    // MARK: - 其他通知

    /// 配置已更新
    func onConfigUpdated()

    /// 服务就绪
    func onServiceReady()

    /// 冲突检测
    /// - Parameter data: 冲突详情 JSON
    func onConflictDetected(data: Data)

    /// 磁盘状态变更
    /// - Parameters:
    ///   - diskName: 磁盘名称
    ///   - isConnected: 是否已连接
    func onDiskChanged(diskName: String, isConnected: Bool)

    // MARK: - 活动推送

    /// 最近活动更新 (最新5条)
    /// - Parameter data: [ActivityRecord] JSON
    func onActivitiesUpdated(data: Data)
}

// MARK: - XPC Interface 配置

public extension DMSAClientProtocol {
    static var interfaceName: String { "com.ttttt.dmsa.client" }

    static func createInterface() -> NSXPCInterface {
        return NSXPCInterface(with: DMSAClientProtocol.self)
    }
}
