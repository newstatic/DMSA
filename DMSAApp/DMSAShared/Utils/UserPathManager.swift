import Foundation

/// User path manager (Service needs to know the real user's home directory)
/// When Service runs as root, ~ expands to /var/root
/// App calls setUserHome to set the correct user home directory
public final class UserPathManager: @unchecked Sendable {
    public static let shared = UserPathManager()

    private var _userHome: String?
    private let lock = NSLock()

    private init() {}

    /// Set user home directory (called by App via XPC)
    public func setUserHome(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        _userHome = path
    }

    /// Get user home directory
    public var userHome: String {
        lock.lock()
        defer { lock.unlock() }

        if let home = _userHome {
            return home
        }

        // Fallback logic
        if getuid() == 0 {
            // Running as root: try environment variables or hardcoded path
            if let sudoUser = ProcessInfo.processInfo.environment["SUDO_USER"],
               let pw = getpwnam(sudoUser) {
                return String(cString: pw.pointee.pw_dir)
            }
            return "/Users/ttttt"  // Hardcoded fallback
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Expand tilde (~) to actual user path
    public func expandTilde(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return userHome + String(path.dropFirst(1))
        } else if path == "~" {
            return userHome
        }
        return path
    }
}
