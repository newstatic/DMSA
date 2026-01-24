import Foundation

/// DMSA 统一服务 XPC 协议
/// 合并 VFS + Sync + Helper 功能
@objc public protocol DMSAServiceProtocol {

    // MARK: - ========== VFS 操作 ==========

    // MARK: 挂载管理

    /// 挂载 VFS
    /// - Parameters:
    ///   - syncPairId: 同步对 ID
    ///   - localDir: 本地目录路径 (LOCAL_DIR)
    ///   - externalDir: 外部目录路径 (EXTERNAL_DIR)，可为空字符串表示离线
    ///   - targetDir: 挂载点路径 (TARGET_DIR)
    func vfsMount(syncPairId: String,
                  localDir: String,
                  externalDir: String?,
                  targetDir: String,
                  withReply reply: @escaping (Bool, String?) -> Void)

    /// 卸载 VFS
    func vfsUnmount(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    /// 卸载所有 VFS
    func vfsUnmountAll(withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取挂载状态
    func vfsGetMountStatus(syncPairId: String,
                           withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取所有挂载点状态
    func vfsGetAllMounts(withReply reply: @escaping (Data) -> Void)

    // MARK: 文件状态

    /// 获取文件状态
    func vfsGetFileStatus(virtualPath: String,
                          syncPairId: String,
                          withReply reply: @escaping (Data?) -> Void)

    /// 获取文件位置
    func vfsGetFileLocation(virtualPath: String,
                            syncPairId: String,
                            withReply reply: @escaping (String) -> Void)

    // MARK: VFS 配置

    /// 更新 EXTERNAL 路径 (硬盘重新连接时)
    func vfsUpdateExternalPath(syncPairId: String,
                               newPath: String,
                               withReply reply: @escaping (Bool, String?) -> Void)

    /// 设置 EXTERNAL 离线状态
    func vfsSetExternalOffline(syncPairId: String,
                               offline: Bool,
                               withReply reply: @escaping (Bool, String?) -> Void)

    /// 设置只读模式
    func vfsSetReadOnly(syncPairId: String,
                        readOnly: Bool,
                        withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: 索引管理

    /// 重建文件索引
    func vfsRebuildIndex(syncPairId: String,
                         withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取索引统计
    func vfsGetIndexStats(syncPairId: String,
                          withReply reply: @escaping (Data?) -> Void)

    // MARK: - ========== 同步操作 ==========

    // MARK: 同步控制

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
    func syncPause(syncPairId: String,
                   withReply reply: @escaping (Bool, String?) -> Void)

    /// 恢复同步
    func syncResume(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    /// 取消正在进行的同步
    func syncCancel(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: 状态查询

    /// 获取同步状态
    func syncGetStatus(syncPairId: String,
                       withReply reply: @escaping (Data) -> Void)

    /// 获取所有同步对状态
    func syncGetAllStatus(withReply reply: @escaping (Data) -> Void)

    /// 获取待同步队列
    func syncGetPendingQueue(syncPairId: String,
                             withReply reply: @escaping (Data) -> Void)

    /// 获取同步进度
    func syncGetProgress(syncPairId: String,
                         withReply reply: @escaping (Data?) -> Void)

    /// 获取同步历史
    func syncGetHistory(syncPairId: String,
                        limit: Int,
                        withReply reply: @escaping (Data) -> Void)

    /// 获取同步统计
    func syncGetStatistics(syncPairId: String,
                           withReply reply: @escaping (Data?) -> Void)

    // MARK: 脏文件管理

    /// 获取脏文件列表
    func syncGetDirtyFiles(syncPairId: String,
                           withReply reply: @escaping (Data) -> Void)

    /// 标记文件为脏
    func syncMarkFileDirty(virtualPath: String,
                           syncPairId: String,
                           withReply reply: @escaping (Bool) -> Void)

    /// 清除文件脏标记
    func syncClearFileDirty(virtualPath: String,
                            syncPairId: String,
                            withReply reply: @escaping (Bool) -> Void)

    // MARK: 同步配置

    /// 更新同步配置
    func syncUpdateConfig(syncPairId: String,
                          configData: Data,
                          withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: 硬盘事件

    /// 通知硬盘已连接
    func diskConnected(diskName: String,
                       mountPoint: String,
                       withReply reply: @escaping (Bool) -> Void)

    /// 通知硬盘已断开
    func diskDisconnected(diskName: String,
                          withReply reply: @escaping (Bool) -> Void)

    // MARK: - ========== 特权操作 ==========

    // MARK: 目录锁定

    /// 锁定目录 (设置 uchg 标志)
    func privilegedLockDirectory(_ path: String,
                                 withReply reply: @escaping (Bool, String?) -> Void)

    /// 解锁目录
    func privilegedUnlockDirectory(_ path: String,
                                   withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: ACL 管理

    /// 设置 ACL
    func privilegedSetACL(_ path: String,
                          deny: Bool,
                          permissions: [String],
                          user: String,
                          withReply reply: @escaping (Bool, String?) -> Void)

    /// 移除 ACL
    func privilegedRemoveACL(_ path: String,
                             withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: 目录可见性

    /// 隐藏目录
    func privilegedHideDirectory(_ path: String,
                                 withReply reply: @escaping (Bool, String?) -> Void)

    /// 取消隐藏目录
    func privilegedUnhideDirectory(_ path: String,
                                   withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: 复合操作

    /// 保护目录 (uchg + ACL + hidden)
    func privilegedProtectDirectory(_ path: String,
                                    withReply reply: @escaping (Bool, String?) -> Void)

    /// 取消保护目录
    func privilegedUnprotectDirectory(_ path: String,
                                      withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: 文件系统操作

    /// 创建目录 (需要特权)
    func privilegedCreateDirectory(_ path: String,
                                   withReply reply: @escaping (Bool, String?) -> Void)

    /// 移动文件/目录 (需要特权)
    func privilegedMoveItem(from source: String,
                            to destination: String,
                            withReply reply: @escaping (Bool, String?) -> Void)

    /// 删除文件/目录 (需要特权)
    func privilegedRemoveItem(_ path: String,
                              withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - ========== 通用操作 ==========

    /// 重新加载配置
    func reloadConfig(withReply reply: @escaping (Bool, String?) -> Void)

    /// 准备关闭 (等待所有操作完成)
    func prepareForShutdown(withReply reply: @escaping (Bool) -> Void)

    /// 获取版本
    func getVersion(withReply reply: @escaping (String) -> Void)

    /// 健康检查
    func healthCheck(withReply reply: @escaping (Bool, String?) -> Void)
}

// MARK: - XPC Interface 配置

public extension DMSAServiceProtocol {
    static var interfaceName: String { "com.ttttt.dmsa.service" }

    static func createInterface() -> NSXPCInterface {
        return NSXPCInterface(with: DMSAServiceProtocol.self)
    }
}
