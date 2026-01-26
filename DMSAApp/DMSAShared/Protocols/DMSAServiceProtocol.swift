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

    // MARK: - ========== 淘汰操作 ==========

    /// 触发 LRU 淘汰
    /// - Parameters:
    ///   - syncPairId: 同步对 ID
    ///   - targetFreeSpace: 目标可用空间 (字节)
    ///   - reply: 回调 (成功, 释放空间, 错误信息)
    func evictionTrigger(syncPairId: String,
                         targetFreeSpace: Int64,
                         withReply reply: @escaping (Bool, Int64, String?) -> Void)

    /// 淘汰单个文件
    func evictionEvictFile(virtualPath: String,
                           syncPairId: String,
                           withReply reply: @escaping (Bool, String?) -> Void)

    /// 预取文件 (从 EXTERNAL 复制到 LOCAL)
    func evictionPrefetchFile(virtualPath: String,
                              syncPairId: String,
                              withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取淘汰统计
    func evictionGetStats(withReply reply: @escaping (Data) -> Void)

    /// 更新淘汰配置
    func evictionUpdateConfig(triggerThreshold: Int64,
                              targetFreeSpace: Int64,
                              autoEnabled: Bool,
                              withReply reply: @escaping (Bool) -> Void)

    // MARK: - ========== 数据查询操作 ==========

    /// 获取文件条目
    func dataGetFileEntry(virtualPath: String,
                          syncPairId: String,
                          withReply reply: @escaping (Data?) -> Void)

    /// 获取所有文件条目
    func dataGetAllFileEntries(syncPairId: String,
                               withReply reply: @escaping (Data) -> Void)

    /// 获取全部同步历史
    func dataGetSyncHistory(limit: Int,
                            withReply reply: @escaping (Data) -> Void)

    /// 获取树版本信息
    func dataGetTreeVersion(syncPairId: String,
                            source: String,
                            withReply reply: @escaping (String?) -> Void)

    /// 检查树版本 (启动时)
    func dataCheckTreeVersions(localDir: String,
                               externalDir: String?,
                               syncPairId: String,
                               withReply reply: @escaping (Data) -> Void)

    /// 重建文件树
    func dataRebuildTree(rootPath: String,
                         syncPairId: String,
                         source: String,
                         withReply reply: @escaping (Bool, String?, String?) -> Void)

    /// 使树版本失效
    func dataInvalidateTreeVersion(syncPairId: String,
                                   source: String,
                                   withReply reply: @escaping (Bool) -> Void)

    // MARK: - ========== 配置操作 ==========

    /// 获取完整配置
    func configGetAll(withReply reply: @escaping (Data) -> Void)

    /// 更新完整配置
    func configUpdate(configData: Data,
                      withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取磁盘配置列表
    func configGetDisks(withReply reply: @escaping (Data) -> Void)

    /// 添加磁盘配置
    func configAddDisk(diskData: Data,
                       withReply reply: @escaping (Bool, String?) -> Void)

    /// 移除磁盘配置
    func configRemoveDisk(diskId: String,
                          withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取同步对配置列表
    func configGetSyncPairs(withReply reply: @escaping (Data) -> Void)

    /// 添加同步对配置
    func configAddSyncPair(pairData: Data,
                           withReply reply: @escaping (Bool, String?) -> Void)

    /// 移除同步对配置
    func configRemoveSyncPair(pairId: String,
                              withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取通知配置
    func configGetNotifications(withReply reply: @escaping (Data) -> Void)

    /// 更新通知配置
    func configUpdateNotifications(configData: Data,
                                   withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - ========== 通知操作 ==========

    /// 保存通知记录
    func notificationSave(recordData: Data,
                          withReply reply: @escaping (Bool) -> Void)

    /// 获取通知记录
    func notificationGetAll(limit: Int,
                            withReply reply: @escaping (Data) -> Void)

    /// 获取未读通知数量
    func notificationGetUnreadCount(withReply reply: @escaping (Int) -> Void)

    /// 标记通知为已读
    func notificationMarkAsRead(recordId: UInt64,
                                withReply reply: @escaping (Bool) -> Void)

    /// 标记所有通知为已读
    func notificationMarkAllAsRead(withReply reply: @escaping (Bool) -> Void)

    /// 清除所有通知
    func notificationClearAll(withReply reply: @escaping (Bool) -> Void)

    // MARK: - ========== 通用操作 ==========

    /// 设置用户 Home 目录 (App 启动时调用，用于 root 服务正确解析 ~ 路径)
    func setUserHome(_ path: String,
                     withReply reply: @escaping (Bool) -> Void)

    /// 重新加载配置
    func reloadConfig(withReply reply: @escaping (Bool, String?) -> Void)

    /// 准备关闭 (等待所有操作完成)
    func prepareForShutdown(withReply reply: @escaping (Bool) -> Void)

    /// 获取版本
    func getVersion(withReply reply: @escaping (String) -> Void)

    /// 获取详细版本信息
    /// - Returns: Data (ServiceVersionInfo JSON)
    func getVersionInfo(withReply reply: @escaping (Data) -> Void)

    /// 检查版本兼容性
    /// - Parameter appVersion: 客户端 App 版本
    /// - Returns: (兼容, 错误信息, 是否需要更新服务)
    func checkCompatibility(appVersion: String,
                            withReply reply: @escaping (Bool, String?, Bool) -> Void)

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
