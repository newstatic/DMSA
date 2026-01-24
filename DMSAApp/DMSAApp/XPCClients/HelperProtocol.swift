import Foundation

/// Helper 服务 XPC 协议 (特权操作)
@objc protocol HelperProtocol {

    // MARK: - 目录锁定

    /// 锁定目录 (设置 uchg 标志)
    func lockDirectory(_ path: String,
                       withReply reply: @escaping (Bool, String?) -> Void)

    /// 解锁目录
    func unlockDirectory(_ path: String,
                         withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - ACL 管理

    /// 设置 ACL
    func setACL(_ path: String,
                deny: Bool,
                permissions: [String],
                user: String,
                withReply reply: @escaping (Bool, String?) -> Void)

    /// 移除 ACL
    func removeACL(_ path: String,
                   withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 目录可见性

    /// 隐藏目录
    func hideDirectory(_ path: String,
                       withReply reply: @escaping (Bool, String?) -> Void)

    /// 取消隐藏目录
    func unhideDirectory(_ path: String,
                         withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 复合操作

    /// 保护目录 (uchg + ACL + hidden)
    func protectDirectory(_ path: String,
                          withReply reply: @escaping (Bool, String?) -> Void)

    /// 取消保护目录
    func unprotectDirectory(_ path: String,
                            withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 文件系统操作

    /// 创建目录 (需要特权)
    func createDirectory(_ path: String,
                         withReply reply: @escaping (Bool, String?) -> Void)

    /// 移动文件/目录 (需要特权)
    func moveItem(from source: String,
                  to destination: String,
                  withReply reply: @escaping (Bool, String?) -> Void)

    /// 删除文件/目录 (需要特权)
    func removeItem(_ path: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 生命周期

    /// 获取版本
    func getVersion(withReply reply: @escaping (String) -> Void)

    /// 健康检查
    func healthCheck(withReply reply: @escaping (Bool, String?) -> Void)
}
