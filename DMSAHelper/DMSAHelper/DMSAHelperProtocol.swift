import Foundation

// MARK: - 常量

/// 特权助手协议版本
public let kDMSAHelperProtocolVersion = "1.0.0"

/// 特权助手 Mach 服务名
public let kDMSAHelperMachServiceName = "com.ttttt.dmsa.helper"

// MARK: - 协议定义

/// 特权助手协议
/// 定义主应用与 LaunchDaemon Helper 之间的 XPC 通信接口
@objc public protocol DMSAHelperProtocol {

    // MARK: - 目录锁定

    /// 锁定目录 (chflags uchg)
    /// - Parameters:
    ///   - path: 目录绝对路径
    ///   - reply: (成功, 错误消息)
    func lockDirectory(_ path: String,
                       withReply reply: @escaping (Bool, String?) -> Void)

    /// 解锁目录 (chflags nouchg)
    func unlockDirectory(_ path: String,
                         withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - ACL 管理

    /// 设置 ACL 拒绝规则
    /// - Parameters:
    ///   - path: 目录路径
    ///   - deny: 是否为拒绝规则
    ///   - permissions: 权限列表 ["delete", "write", "append", "writeattr", "writeextattr"]
    ///   - user: 用户 "everyone" 或特定用户名
    func setACL(_ path: String,
                deny: Bool,
                permissions: [String],
                user: String,
                withReply reply: @escaping (Bool, String?) -> Void)

    /// 移除所有 ACL 规则
    func removeACL(_ path: String,
                   withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 目录可见性

    /// 隐藏目录 (chflags hidden)
    func hideDirectory(_ path: String,
                       withReply reply: @escaping (Bool, String?) -> Void)

    /// 取消隐藏目录 (chflags nohidden)
    func unhideDirectory(_ path: String,
                         withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 状态查询

    /// 获取目录保护状态
    /// - Returns: (isLocked, hasACL, isHidden, errorMessage)
    func getDirectoryStatus(_ path: String,
                            withReply reply: @escaping (Bool, Bool, Bool, String?) -> Void)

    /// 获取 Helper 版本
    func getVersion(withReply reply: @escaping (String) -> Void)

    // MARK: - 复合操作

    /// 完全保护目录 (uchg + ACL deny + hidden)
    /// - Parameters:
    ///   - path: 目录路径
    ///   - reply: (成功, 错误消息)
    func protectDirectory(_ path: String,
                          withReply reply: @escaping (Bool, String?) -> Void)

    /// 解除目录保护
    func unprotectDirectory(_ path: String,
                            withReply reply: @escaping (Bool, String?) -> Void)
}

// MARK: - 协议扩展

extension DMSAHelperProtocol {
    /// 默认 ACL 权限列表 (阻止用户直接修改 LOCAL_DIR)
    static var defaultDenyPermissions: [String] {
        ["delete", "write", "append", "writeattr", "writeextattr"]
    }
}
