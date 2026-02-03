import Foundation

/// User path manager (Service needs to know the real user's home directory)
/// When Service runs as root, ~ expands to /var/root
/// App calls setUserHome to set the correct user home directory
public final class UserPathManager: @unchecked Sendable {
    public static let shared = UserPathManager()

    private var _userHome: String?
    private let lock = NSLock()
    private let continuation = DispatchSemaphore(value: 0)
    private var isSet = false

    /// Persistence file path (root-accessible location)
    private let persistPath = "/var/root/Library/Application Support/DMSA/user_home.txt"

    private init() {
        // Try to load persisted userHome on init
        loadPersistedUserHome()
    }

    // MARK: - Persistence

    /// Load persisted userHome from file
    private func loadPersistedUserHome() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: persistPath),
              let content = try? String(contentsOfFile: persistPath, encoding: .utf8) else {
            return
        }
        let home = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !home.isEmpty, fm.fileExists(atPath: home) else {
            return
        }

        lock.lock()
        _userHome = home
        isSet = true
        lock.unlock()

        // Signal waiters since we already have userHome
        continuation.signal()

        #if DEBUG
        print("[UserPathManager] Loaded persisted userHome: \(home)")
        #endif
    }

    /// Persist userHome to file
    private func persistUserHome(_ path: String) {
        let fm = FileManager.default
        let dir = (persistPath as NSString).deletingLastPathComponent

        // Create directory if needed
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        do {
            try path.write(toFile: persistPath, atomically: true, encoding: .utf8)
            #if DEBUG
            print("[UserPathManager] Persisted userHome to: \(persistPath)")
            #endif
        } catch {
            #if DEBUG
            print("[UserPathManager] Failed to persist userHome: \(error)")
            #endif
        }
    }

    /// Set user home directory (called by App via XPC)
    public func setUserHome(_ path: String) {
        lock.lock()
        let wasSet = isSet
        _userHome = path
        isSet = true
        lock.unlock()

        // Persist to file for next startup
        persistUserHome(path)

        // Signal all waiters (only first time)
        if !wasSet {
            continuation.signal()
        }
    }

    /// Whether userHome has been set via XPC
    public var isUserHomeSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSet
    }

    /// Wait until userHome is set (for Service startup gating)
    /// Call from background thread only, blocks until setUserHome is called
    public func waitForUserHome(timeout: TimeInterval = 60) -> Bool {
        lock.lock()
        if isSet {
            lock.unlock()
            return true
        }
        lock.unlock()

        let result = continuation.wait(timeout: .now() + timeout)
        return result == .success
    }

    /// Get user home directory
    public var userHome: String {
        lock.lock()
        defer { lock.unlock() }

        if let home = _userHome {
            return home
        }

        // Fallback logic (before XPC setUserHome is called)
        if getuid() == 0 {
            // Running as root: try SUDO_USER
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
