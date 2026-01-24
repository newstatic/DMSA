import Foundation

/// VFS 服务 XPC 协议
@objc public protocol VFSServiceProtocol {

    // MARK: - 挂载管理

    /// 挂载 VFS
    /// - Parameters:
    ///   - syncPairId: 同步对 ID
    ///   - localDir: 本地目录路径 (LOCAL_DIR)
    ///   - externalDir: 外部目录路径 (EXTERNAL_DIR)
    ///   - targetDir: 挂载点路径 (TARGET_DIR)
    func mount(syncPairId: String,
               localDir: String,
               externalDir: String,
               targetDir: String,
               withReply reply: @escaping (Bool, String?) -> Void)

    /// 卸载 VFS
    func unmount(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void)

    /// 卸载所有 VFS
    func unmountAll(withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取挂载状态
    func getMountStatus(syncPairId: String,
                        withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取所有挂载点状态
    func getAllMounts(withReply reply: @escaping (Data) -> Void)

    // MARK: - 文件状态

    /// 获取文件状态
    func getFileStatus(virtualPath: String,
                       syncPairId: String,
                       withReply reply: @escaping (Data?) -> Void)

    /// 获取文件位置
    func getFileLocation(virtualPath: String,
                         syncPairId: String,
                         withReply reply: @escaping (String) -> Void)

    // MARK: - 配置更新

    /// 更新 EXTERNAL 路径 (硬盘重新连接时)
    func updateExternalPath(syncPairId: String,
                            newPath: String,
                            withReply reply: @escaping (Bool, String?) -> Void)

    /// 设置 EXTERNAL 离线状态
    func setExternalOffline(syncPairId: String,
                            offline: Bool,
                            withReply reply: @escaping (Bool, String?) -> Void)

    /// 设置只读模式
    func setReadOnly(syncPairId: String,
                     readOnly: Bool,
                     withReply reply: @escaping (Bool, String?) -> Void)

    /// 重新加载配置
    func reloadConfig(withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 索引管理

    /// 重建文件索引
    func rebuildIndex(syncPairId: String,
                      withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取索引统计
    func getIndexStats(syncPairId: String,
                       withReply reply: @escaping (Data?) -> Void)

    // MARK: - 生命周期

    /// 准备关闭 (等待写入完成)
    func prepareForShutdown(withReply reply: @escaping (Bool) -> Void)

    /// 获取版本
    func getVersion(withReply reply: @escaping (String) -> Void)

    /// 健康检查
    func healthCheck(withReply reply: @escaping (Bool, String?) -> Void)
}

// MARK: - XPC Interface 配置

public extension VFSServiceProtocol {
    static var interfaceName: String { "com.ttttt.dmsa.vfs" }

    static func createInterface() -> NSXPCInterface {
        return NSXPCInterface(with: VFSServiceProtocol.self)
    }
}
