import Foundation

/// 特权操作执行器
/// 注意: DMSAService 以 root 权限运行，可直接执行这些操作
struct PrivilegedOperations {

    private static let logger = Logger.forService("Privileged")

    // MARK: - 路径验证

    /// 允许操作的路径前缀白名单
    private static let allowedPrefixes = [
        "/Volumes/",
        NSHomeDirectory() + "/Downloads",
        NSHomeDirectory() + "/Documents"
    ]

    /// 禁止操作的危险路径
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

    /// 验证路径是否允许操作
    private static func validatePath(_ path: String) -> (valid: Bool, error: String?) {
        // 规范化路径
        let normalizedPath = (path as NSString).standardizingPath

        // 检查是否包含路径遍历
        if normalizedPath.contains("..") {
            return (false, "路径包含非法的路径遍历字符")
        }

        // 检查危险路径
        for dangerous in dangerousPaths {
            if normalizedPath.hasPrefix(dangerous) {
                return (false, "禁止操作系统关键目录: \(dangerous)")
            }
        }

        // 检查是否在白名单内
        var isAllowed = false
        for prefix in allowedPrefixes {
            if normalizedPath.hasPrefix(prefix) {
                isAllowed = true
                break
            }
        }

        if !isAllowed {
            return (false, "路径不在允许的操作范围内")
        }

        return (true, nil)
    }

    // MARK: - 目录锁定 (uchg flag)

    /// 锁定目录 (设置 uchg flag)
    static func lockDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let result = runCommand("/usr/bin/chflags", arguments: ["uchg", path])
        if result.success {
            logger.info("目录已锁定: \(path)")
        } else {
            logger.error("锁定目录失败: \(path) - \(result.error ?? "未知错误")")
        }
        return result
    }

    /// 解锁目录 (移除 uchg flag)
    static func unlockDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let result = runCommand("/usr/bin/chflags", arguments: ["nouchg", path])
        if result.success {
            logger.info("目录已解锁: \(path)")
        } else {
            logger.error("解锁目录失败: \(path) - \(result.error ?? "未知错误")")
        }
        return result
    }

    // MARK: - ACL 管理

    /// 设置 ACL 权限
    static func setACL(_ path: String, deny: Bool, permissions: [String], user: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        // 验证用户名
        guard isValidUsername(user) else {
            return (false, "无效的用户名")
        }

        // 验证权限名称
        let validPermissions = ["read", "write", "execute", "delete", "append", "readattr", "writeattr", "readextattr", "writeextattr", "readsecurity", "writesecurity", "chown", "list", "search", "add_file", "add_subdirectory", "delete_child"]
        for perm in permissions {
            if !validPermissions.contains(perm) {
                return (false, "无效的权限名称: \(perm)")
            }
        }

        let permString = permissions.joined(separator: ",")
        let aclType = deny ? "deny" : "allow"
        let aclEntry = "user:\(user) \(aclType) \(permString)"

        let result = runCommand("/bin/chmod", arguments: ["+a", aclEntry, path])
        if result.success {
            logger.info("ACL 已设置: \(path) - \(aclEntry)")
        } else {
            logger.error("设置 ACL 失败: \(path) - \(result.error ?? "未知错误")")
        }
        return result
    }

    /// 移除所有 ACL
    static func removeACL(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let result = runCommand("/bin/chmod", arguments: ["-N", path])
        if result.success {
            logger.info("ACL 已移除: \(path)")
        } else {
            logger.error("移除 ACL 失败: \(path) - \(result.error ?? "未知错误")")
        }
        return result
    }

    // MARK: - 目录可见性

    /// 隐藏目录 (设置 hidden flag)
    static func hideDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let result = runCommand("/usr/bin/chflags", arguments: ["hidden", path])
        if result.success {
            logger.info("目录已隐藏: \(path)")
        } else {
            logger.error("隐藏目录失败: \(path) - \(result.error ?? "未知错误")")
        }
        return result
    }

    /// 显示目录 (移除 hidden flag)
    static func unhideDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let result = runCommand("/usr/bin/chflags", arguments: ["nohidden", path])
        if result.success {
            logger.info("目录已显示: \(path)")
        } else {
            logger.error("显示目录失败: \(path) - \(result.error ?? "未知错误")")
        }
        return result
    }

    // MARK: - 复合操作

    /// 保护目录 (uchg + ACL deny delete + hidden)
    static func protectDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        // 获取当前用户
        let currentUser = NSUserName()

        // 1. 设置 uchg flag
        var result = lockDirectory(path)
        if !result.success {
            return (false, "设置 uchg 失败: \(result.error ?? "未知错误")")
        }

        // 2. 设置 ACL 禁止删除
        result = setACL(path, deny: true, permissions: ["delete"], user: currentUser)
        if !result.success {
            // 回滚 uchg
            _ = unlockDirectory(path)
            return (false, "设置 ACL 失败: \(result.error ?? "未知错误")")
        }

        // 3. 设置 hidden flag
        result = hideDirectory(path)
        if !result.success {
            // 回滚
            _ = removeACL(path)
            _ = unlockDirectory(path)
            return (false, "设置 hidden 失败: \(result.error ?? "未知错误")")
        }

        logger.info("目录保护已启用: \(path)")
        return (true, nil)
    }

    /// 取消目录保护
    static func unprotectDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        var errors: [String] = []

        // 1. 移除 hidden flag
        var result = unhideDirectory(path)
        if !result.success {
            errors.append("unhide: \(result.error ?? "未知错误")")
        }

        // 2. 移除 ACL
        result = removeACL(path)
        if !result.success {
            errors.append("removeACL: \(result.error ?? "未知错误")")
        }

        // 3. 移除 uchg flag
        result = unlockDirectory(path)
        if !result.success {
            errors.append("unlock: \(result.error ?? "未知错误")")
        }

        if errors.isEmpty {
            logger.info("目录保护已解除: \(path)")
            return (true, nil)
        } else {
            let errorMsg = errors.joined(separator: "; ")
            logger.warning("目录保护解除部分失败: \(path) - \(errorMsg)")
            return (false, errorMsg)
        }
    }

    // MARK: - 文件操作

    /// 创建目录 (含父目录)
    static func createDirectory(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            logger.info("目录已创建: \(path)")
            return (true, nil)
        } catch {
            logger.error("创建目录失败: \(path) - \(error)")
            return (false, error.localizedDescription)
        }
    }

    /// 移动文件/目录
    static func moveItem(from: String, to: String) -> (success: Bool, error: String?) {
        let fromValidation = validatePath(from)
        guard fromValidation.valid else {
            return (false, "源路径: \(fromValidation.error ?? "无效")")
        }

        let toValidation = validatePath(to)
        guard toValidation.valid else {
            return (false, "目标路径: \(toValidation.error ?? "无效")")
        }

        do {
            // 确保目标父目录存在
            let parentDir = (to as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

            try FileManager.default.moveItem(atPath: from, toPath: to)
            logger.info("已移动: \(from) -> \(to)")
            return (true, nil)
        } catch {
            logger.error("移动失败: \(from) -> \(to) - \(error)")
            return (false, error.localizedDescription)
        }
    }

    /// 删除文件/目录
    static func removeItem(_ path: String) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        do {
            try FileManager.default.removeItem(atPath: path)
            logger.info("已删除: \(path)")
            return (true, nil)
        } catch {
            logger.error("删除失败: \(path) - \(error)")
            return (false, error.localizedDescription)
        }
    }

    /// 设置文件权限
    static func setPermissions(_ path: String, mode: Int) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        let modeString = String(format: "%o", mode)
        let result = runCommand("/bin/chmod", arguments: [modeString, path])
        if result.success {
            logger.info("权限已设置: \(path) -> \(modeString)")
        } else {
            logger.error("设置权限失败: \(path) - \(result.error ?? "未知错误")")
        }
        return result
    }

    /// 设置文件所有者
    static func setOwner(_ path: String, user: String, group: String?) -> (success: Bool, error: String?) {
        let validation = validatePath(path)
        guard validation.valid else {
            return (false, validation.error)
        }

        guard isValidUsername(user) else {
            return (false, "无效的用户名")
        }

        var ownerSpec = user
        if let group = group {
            guard isValidUsername(group) else {
                return (false, "无效的组名")
            }
            ownerSpec = "\(user):\(group)"
        }

        let result = runCommand("/usr/sbin/chown", arguments: [ownerSpec, path])
        if result.success {
            logger.info("所有者已设置: \(path) -> \(ownerSpec)")
        } else {
            logger.error("设置所有者失败: \(path) - \(result.error ?? "未知错误")")
        }
        return result
    }

    // MARK: - 辅助方法

    /// 执行命令
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
                return (false, errorString ?? "命令执行失败 (退出码: \(process.terminationStatus))")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// 验证用户名是否合法 (防止命令注入)
    private static func isValidUsername(_ name: String) -> Bool {
        // 用户名只能包含字母、数字、下划线和连字符
        let regex = try? NSRegularExpression(pattern: "^[a-zA-Z0-9_-]+$")
        let range = NSRange(name.startIndex..., in: name)
        return regex?.firstMatch(in: name, range: range) != nil
    }
}
