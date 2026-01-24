import Foundation

/// Sync 服务 XPC 协议
@objc public protocol SyncServiceProtocol {

    // MARK: - 同步控制

    /// 立即同步指定同步对
    func syncNow(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void)

    /// 同步所有同步对
    func syncAll(withReply reply: @escaping (Bool, String?) -> Void)

    /// 同步单个文件
    func syncFile(virtualPath: String,
                  syncPairId: String,
                  withReply reply: @escaping (Bool, String?) -> Void)

    /// 暂停同步
    func pauseSync(syncPairId: String,
                   withReply reply: @escaping (Bool, String?) -> Void)

    /// 恢复同步
    func resumeSync(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    /// 取消正在进行的同步
    func cancelSync(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 状态查询

    /// 获取同步状态
    func getSyncStatus(syncPairId: String,
                       withReply reply: @escaping (Data) -> Void)

    /// 获取所有同步对状态
    func getAllSyncStatus(withReply reply: @escaping (Data) -> Void)

    /// 获取待同步队列
    func getPendingQueue(syncPairId: String,
                         withReply reply: @escaping (Data) -> Void)

    /// 获取同步进度
    func getSyncProgress(syncPairId: String,
                         withReply reply: @escaping (Data?) -> Void)

    /// 获取同步历史
    func getSyncHistory(syncPairId: String,
                        limit: Int,
                        withReply reply: @escaping (Data) -> Void)

    /// 获取同步统计
    func getSyncStatistics(syncPairId: String,
                           withReply reply: @escaping (Data?) -> Void)

    // MARK: - 脏文件管理

    /// 获取脏文件列表
    func getDirtyFiles(syncPairId: String,
                       withReply reply: @escaping (Data) -> Void)

    /// 标记文件为脏
    func markFileDirty(virtualPath: String,
                       syncPairId: String,
                       withReply reply: @escaping (Bool) -> Void)

    /// 清除文件脏标记
    func clearFileDirty(virtualPath: String,
                        syncPairId: String,
                        withReply reply: @escaping (Bool) -> Void)

    // MARK: - 配置

    /// 更新同步配置
    func updateSyncConfig(syncPairId: String,
                          configData: Data,
                          withReply reply: @escaping (Bool, String?) -> Void)

    /// 重新加载配置
    func reloadConfig(withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 硬盘事件

    /// 通知硬盘已连接
    func diskConnected(diskName: String,
                       mountPoint: String,
                       withReply reply: @escaping (Bool) -> Void)

    /// 通知硬盘已断开
    func diskDisconnected(diskName: String,
                          withReply reply: @escaping (Bool) -> Void)

    // MARK: - 生命周期

    /// 准备关闭 (等待当前同步完成)
    func prepareForShutdown(withReply reply: @escaping (Bool) -> Void)

    /// 获取版本
    func getVersion(withReply reply: @escaping (String) -> Void)

    /// 健康检查
    func healthCheck(withReply reply: @escaping (Bool, String?) -> Void)
}

// MARK: - XPC Interface 配置

public extension SyncServiceProtocol {
    static var interfaceName: String { "com.ttttt.dmsa.sync" }

    static func createInterface() -> NSXPCInterface {
        return NSXPCInterface(with: SyncServiceProtocol.self)
    }
}
