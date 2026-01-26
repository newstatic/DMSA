import Foundation

/// 用户路径管理器 (Service 需要知道真实用户的 home 目录)
/// 当 Service 以 root 身份运行时，~ 会被扩展为 /var/root
/// 通过 App 调用 setUserHome 来设置正确的用户 home 目录
public final class UserPathManager: @unchecked Sendable {
    public static let shared = UserPathManager()

    private var _userHome: String?
    private let lock = NSLock()

    private init() {}

    /// 设置用户 home 目录 (由 App 通过 XPC 调用)
    public func setUserHome(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        _userHome = path
    }

    /// 获取用户 home 目录
    public var userHome: String {
        lock.lock()
        defer { lock.unlock() }

        if let home = _userHome {
            return home
        }

        // 回退逻辑
        if getuid() == 0 {
            // root 身份: 尝试环境变量或硬编码
            if let sudoUser = ProcessInfo.processInfo.environment["SUDO_USER"],
               let pw = getpwnam(sudoUser) {
                return String(cString: pw.pointee.pw_dir)
            }
            return "/Users/ttttt"  // 硬编码回退
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// 扩展 tilde (~) 为实际用户路径
    public func expandTilde(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return userHome + String(path.dropFirst(1))
        } else if path == "~" {
            return userHome
        }
        return path
    }
}
