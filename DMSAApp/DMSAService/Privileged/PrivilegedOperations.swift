import Foundation

/// Privileged operations executor
/// Note: DMSAService runs with root privileges and can execute these operations directly
struct PrivilegedOperations {

    private static let logger = Logger.forService("Privileged")

    // MARK: - Path Validation

    /// Allowed path prefix whitelist
    private static let allowedPrefixes = [
        "/Volumes/",
        NSHomeDirectory() + "/Downloads",
        NSHomeDirectory() + "/Documents"
    ]

    /// Dangerous paths that must not be operated on
    private static let dangerousPaths = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/etc",
        "/Library",
        "/private",
        "/var",
        "/tmp",
        "/dev",
        "/cores"
    ]

    /// Validate whether a path is allowed for operations
    private static func validatePath(_ path: String) -> (valid: Bool, error: String?) {
        // Normalize path
        let normalizedPath = (path as NSString).standardizingPath

        // Check for path traversal
        if normalizedPath.contains("..") {
            return (false, "Path contains illegal traversal characters")
        }

        // Check dangerous paths
        for dangerous in dangerousPaths {
            if normalizedPath.hasPrefix(dangerous) {
                return (false, "Operation on critical system directory forbidden: \(dangerous)")
            }
        }

        // Check if within whitelist
        var isAllowed = false
        for prefix in allowedPrefixes {
            if normalizedPath.hasPrefix(prefix) {
                isAllowed = true
                break
            }
        }

        if !isAllowed {
            return (false, "Path is not within the allowed operation scope")
        }

        return (true, nil)
    }

    // MARK: - Directory Locking (uchg flag)

    /// Lock directory (set uchg flag)
    static func lockDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let result = runCommand("/usr/bin/chflags", arguments: ["uchg", path])
        if result.success {
            logger.info("Directory locked: \(path)")
        } else {
            logger.error("Failed to lock directory: \(path) - \(result.error ?? "unknown error")")
        }
        return result
    }

    /// Unlock directory (remove uchg flag)
    static func unlockDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let result = runCommand("/usr/bin/chflags", arguments: ["nouchg", path])
        if result.success {
            logger.info("Directory unlocked: \(path)")
        } else {
            logger.error("Failed to unlock directory: \(path) - \(result.error ?? "unknown error")")
        }
        return result
    }

    // MARK: - ACL Management

    /// Set ACL permissions
    static func setACL(_ path: String, deny: Bool, permissions: [String], user: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        // Validate username
        guard isValidUsername(user) else {
            return (false, "Invalid username")
        }

        // Validate permission names
        let validPermissions = ["read", "write", "execute", "delete", "append", "readattr", "writeattr", "readextattr", "writeextattr", "readsecurity", "writesecurity", "chown", "list", "search", "add_file", "add_subdirectory", "delete_child"]
        for perm in permissions {
            if !validPermissions.contains(perm) {
                return (false, "Invalid permission name: \(perm)")
            }
        }

        let permString = permissions.joined(separator: ",")
        let aclType = deny ? "deny" : "allow"
        let aclEntry = "user:\(user) \(aclType) \(permString)"

        let result = runCommand("/bin/chmod", arguments: ["+a", aclEntry, path])
        if result.success {
            logger.info("ACL set: \(path) - \(aclEntry)")
        } else {
            logger.error("Failed to set ACL: \(path) - \(result.error ?? "unknown error")")
        }
        return result
    }

    /// Remove all ACLs
    static func removeACL(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let result = runCommand("/bin/chmod", arguments: ["-N", path])
        if result.success {
            logger.info("ACL removed: \(path)")
        } else {
            logger.error("Failed to remove ACL: \(path) - \(result.error ?? "unknown error")")
        }
        return result
    }

    // MARK: - Directory Visibility

    /// Hide directory (set hidden flag)
    static func hideDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let result = runCommand("/usr/bin/chflags", arguments: ["hidden", path])
        if result.success {
            logger.info("Directory hidden: \(path)")
        } else {
            logger.error("Failed to hide directory: \(path) - \(result.error ?? "unknown error")")
        }
        return result
    }

    /// Unhide directory (remove hidden flag)
    static func unhideDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let result = runCommand("/usr/bin/chflags", arguments: ["nohidden", path])
        if result.success {
            logger.info("Directory unhidden: \(path)")
        } else {
            logger.error("Failed to unhide directory: \(path) - \(result.error ?? "unknown error")")
        }
        return result
    }

    // MARK: - Compound Operations

    /// Protect directory (uchg + ACL deny delete + hidden)
    static func protectDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        // Get current user
        let currentUser = NSUserName()

        // 1. Set uchg flag
        var result = lockDirectory(path)
        if !result.success {
            return (false, "Failed to set uchg: \(result.error ?? "unknown error")")
        }

        // 2. Set ACL deny delete
        result = setACL(path, deny: true, permissions: ["delete"], user: currentUser)
        if !result.success {
            // Rollback uchg
            _ = unlockDirectory(path)
            return (false, "Failed to set ACL: \(result.error ?? "unknown error")")
        }

        // 3. Set hidden flag
        result = hideDirectory(path)
        if !result.success {
            // Rollback
            _ = removeACL(path)
            _ = unlockDirectory(path)
            return (false, "Failed to set hidden: \(result.error ?? "unknown error")")
        }

        logger.info("Directory protection enabled: \(path)")
        return (true, nil)
    }

    /// Remove directory protection
    static func unprotectDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        var errors: [String] = []

        // 1. Remove hidden flag
        var result = unhideDirectory(path)
        if !result.success {
            errors.append("unhide: \(result.error ?? "unknown error")")
        }

        // 2. Remove ACL
        result = removeACL(path)
        if !result.success {
            errors.append("removeACL: \(result.error ?? "unknown error")")
        }

        // 3. Remove uchg flag
        result = unlockDirectory(path)
        if !result.success {
            errors.append("unlock: \(result.error ?? "unknown error")")
        }

        if errors.isEmpty {
            logger.info("Directory protection removed: \(path)")
            return (true, nil)
        } else {
            let errorMsg = errors.joined(separator: "; ")
            logger.warning("Directory protection partially failed to remove: \(path) - \(errorMsg)")
            return (false, errorMsg)
        }
    }

    // MARK: - File Operations

    /// Create directory (including parents)
    static func createDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            logger.info("Directory created: \(path)")
            return (true, nil)
        } catch {
            logger.error("Failed to create directory: \(path) - \(error)")
            return (false, error.localizedDescription)
        }
    }

    /// Move file/directory
    static func moveItem(from: String, to: String) -> (success: Bool, error: String?) {
        let fromValidation = validatePath(from)
        guard fromValidation.valid else {
            return (false, "Source path: \(fromValidation.error ?? "invalid")")
        }

        let toValidation = validatePath(to)
        guard toValidation.valid else {
            return (false, "Destination path: \(toValidation.error ?? "invalid")")
        }

        do {
            // Ensure destination parent directory exists
            let parentDir = (to as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

            try FileManager.default.moveItem(atPath: from, toPath: to)
            logger.info("Moved: \(from) -> \(to)")
            return (true, nil)
        } catch {
            logger.error("Move failed: \(from) -> \(to) - \(error)")
            return (false, error.localizedDescription)
        }
    }

    /// Delete file/directory
    static func removeItem(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        do {
            try FileManager.default.removeItem(atPath: path)
            logger.info("Deleted: \(path)")
            return (true, nil)
        } catch {
            logger.error("Delete failed: \(path) - \(error)")
            return (false, error.localizedDescription)
        }
    }

    /// Set file permissions
    static func setPermissions(_ path: String, mode: Int) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let modeString = String(format: "%o", mode)
        let result = runCommand("/bin/chmod", arguments: [modeString, path])
        if result.success {
            logger.info("Permissions set: \(path) -> \(modeString)")
        } else {
            logger.error("Failed to set permissions: \(path) - \(result.error ?? "unknown error")")
        }
        return result
    }

    /// Set file owner
    static func setOwner(_ path: String, user: String, group: String?) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        guard isValidUsername(user) else {
            return (false, "Invalid username")
        }

        var ownerSpec = user
        if let group = group {
            guard isValidUsername(group) else {
                return (false, "Invalid group name")
            }
            ownerSpec = "\(user):\(group)"
        }

        let result = runCommand("/usr/sbin/chown", arguments: [ownerSpec, path])
        if result.success {
            logger.info("Owner set: \(path) -> \(ownerSpec)")
        } else {
            logger.error("Failed to set owner: \(path) - \(result.error ?? "unknown error")")
        }
        return result
    }

    // MARK: - Helper Methods

    /// Execute command
    private static func runCommand(_ command: String, arguments: [String]) -> (success: Bool, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return (true, nil)
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (false, errorString ?? "Command failed (exit code: \(process.terminationStatus))")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Validate username (prevent command injection)
    private static func isValidUsername(_ name: String) -> Bool {
        // Username can only contain letters, numbers, underscores, and hyphens
        let regex = try? NSRegularExpression(pattern: "^[a-zA-Z0-9_-]+$")
        let range = NSRange(name.startIndex..., in: name)
        return regex?.firstMatch(in: name, range: range) != nil
    }
}
