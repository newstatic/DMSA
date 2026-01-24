import Foundation

/// DMSA 特权助手工具
/// 以 root 权限运行，执行目录保护操作
class HelperTool: NSObject, NSXPCListenerDelegate, DMSAHelperProtocol {

    // MARK: - 常量

    static let version = kDMSAHelperProtocolVersion

    // MARK: - 路径白名单

    /// 允许操作的路径前缀
    private var allowedPrefixes: [String] {
        // 动态获取，因为不同用户的 home 目录不同
        var prefixes: [String] = ["/Volumes/"]

        // 添加所有用户的可能路径
        let usersDir = "/Users"
        if let users = try? FileManager.default.contentsOfDirectory(atPath: usersDir) {
            for user in users {
                guard user != ".localized" && !user.hasPrefix(".") else { continue }
                let home = "\(usersDir)/\(user)"
                prefixes.append("\(home)/Downloads_Local")
                prefixes.append("\(home)/Downloads")
                prefixes.append("\(home)/Documents_Local")
                prefixes.append("\(home)/Documents")
            }
        }

        return prefixes
    }

    /// 危险路径黑名单
    private let dangerousPaths: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/etc",
        "/private/etc",
        "/var",
        "/Library",
        "/Applications"
    ]

    // MARK: - 路径验证

    /// 验证路径是否允许操作
    private func isPathAllowed(_ path: String) -> Bool {
        // 1. 规范化路径
        let normalized = (path as NSString).standardizingPath

        // 2. 检查是否包含路径遍历
        if normalized.contains("../") || normalized.contains("/..") {
            logMessage("Path traversal blocked: \(path)")
            return false
        }

        // 3. 检查危险路径
        for dangerous in dangerousPaths {
            if normalized.hasPrefix(dangerous) {
                logMessage("Dangerous path blocked: \(path)")
                return false
            }
        }

        // 4. 检查白名单
        for allowed in allowedPrefixes {
            if normalized.hasPrefix(allowed) {
                return true
            }
        }

        logMessage("Path not in whitelist: \(path)")
        return false
    }

    /// 验证路径存在且为目录
    private func validateDirectory(_ path: String) -> (valid: Bool, error: String?) {
        guard isPathAllowed(path) else {
            return (false, "Path not allowed: \(path)")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return (false, "Path does not exist: \(path)")
        }

        guard isDirectory.boolValue else {
            return (false, "Path is not a directory: \(path)")
        }

        return (true, nil)
    }

    // MARK: - 命令执行

    /// 执行系统命令
    private func runCommand(_ executable: String, _ arguments: [String]) -> (success: Bool, output: String?, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            logMessage("Command: \(executable) \(arguments.joined(separator: " ")) -> exit \(process.terminationStatus)")

            return (
                success: process.terminationStatus == 0,
                output: output?.isEmpty == true ? nil : output,
                error: error?.isEmpty == true ? nil : error
            )
        } catch {
            logMessage("Command failed: \(error.localizedDescription)")
            return (false, nil, error.localizedDescription)
        }
    }

    // MARK: - 日志

    private func logMessage(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] DMSAHelper: \(message)\n"

        // 写入系统日志
        let logPath = "/var/log/dmsa-helper.log"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            if let data = logEntry.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            // 创建日志文件
            FileManager.default.createFile(atPath: logPath, contents: logEntry.data(using: .utf8))
        }

        // 同时输出到 stderr (会被 launchd 捕获)
        fputs(logEntry, stderr)
    }

    // MARK: - DMSAHelperProtocol 实现

    func lockDirectory(_ path: String, withReply reply: @escaping (Bool, String?) -> Void) {
        let validation = validateDirectory(path)
        guard validation.valid else {
            reply(false, validation.error)
            return
        }

        // chflags uchg (user immutable)
        let result = runCommand("/usr/bin/chflags", ["uchg", path])
        reply(result.success, result.error)
    }

    func unlockDirectory(_ path: String, withReply reply: @escaping (Bool, String?) -> Void) {
        let validation = validateDirectory(path)
        guard validation.valid else {
            reply(false, validation.error)
            return
        }

        // chflags nouchg
        let result = runCommand("/usr/bin/chflags", ["nouchg", path])
        reply(result.success, result.error)
    }

    func setACL(_ path: String, deny: Bool, permissions: [String], user: String,
                withReply reply: @escaping (Bool, String?) -> Void) {
        let validation = validateDirectory(path)
        guard validation.valid else {
            reply(false, validation.error)
            return
        }

        // 验证用户名 (防止注入)
        let safeUser = user.replacingOccurrences(of: "'", with: "")
                          .replacingOccurrences(of: "\"", with: "")
                          .replacingOccurrences(of: ";", with: "")
                          .replacingOccurrences(of: "&", with: "")

        // 验证权限列表
        let allowedPermissions = Set(["delete", "write", "append", "writeattr", "writeextattr",
                                      "read", "readattr", "readextattr", "readsecurity",
                                      "execute", "chown"])
        let safePermissions = permissions.filter { allowedPermissions.contains($0) }

        guard !safePermissions.isEmpty else {
            reply(false, "No valid permissions specified")
            return
        }

        let ruleType = deny ? "deny" : "allow"
        let perms = safePermissions.joined(separator: ",")
        let rule = "\(safeUser) \(ruleType) \(perms)"

        // chmod +a "rule" path
        let result = runCommand("/bin/chmod", ["+a", rule, path])
        reply(result.success, result.error)
    }

    func removeACL(_ path: String, withReply reply: @escaping (Bool, String?) -> Void) {
        let validation = validateDirectory(path)
        guard validation.valid else {
            reply(false, validation.error)
            return
        }

        // chmod -N (移除所有 ACL)
        let result = runCommand("/bin/chmod", ["-N", path])
        reply(result.success, result.error)
    }

    func hideDirectory(_ path: String, withReply reply: @escaping (Bool, String?) -> Void) {
        let validation = validateDirectory(path)
        guard validation.valid else {
            reply(false, validation.error)
            return
        }

        // chflags hidden
        let result = runCommand("/usr/bin/chflags", ["hidden", path])
        reply(result.success, result.error)
    }

    func unhideDirectory(_ path: String, withReply reply: @escaping (Bool, String?) -> Void) {
        let validation = validateDirectory(path)
        guard validation.valid else {
            reply(false, validation.error)
            return
        }

        // chflags nohidden
        let result = runCommand("/usr/bin/chflags", ["nohidden", path])
        reply(result.success, result.error)
    }

    func getDirectoryStatus(_ path: String,
                            withReply reply: @escaping (Bool, Bool, Bool, String?) -> Void) {
        let validation = validateDirectory(path)
        guard validation.valid else {
            reply(false, false, false, validation.error)
            return
        }

        // 使用 ls -lOd 检查标志
        let lsResult = runCommand("/bin/ls", ["-lOd", path])

        var isLocked = false
        var isHidden = false

        if let output = lsResult.output {
            isLocked = output.contains("uchg")
            isHidden = output.contains("hidden")
        }

        // 使用 ls -led 检查 ACL
        let aclResult = runCommand("/bin/ls", ["-led", path])
        let hasACL = aclResult.output?.contains(" 0: ") ?? false

        reply(isLocked, hasACL, isHidden, nil)
    }

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(Self.version)
    }

    func protectDirectory(_ path: String, withReply reply: @escaping (Bool, String?) -> Void) {
        let validation = validateDirectory(path)
        guard validation.valid else {
            reply(false, validation.error)
            return
        }

        logMessage("Protecting directory: \(path)")

        // 1. 设置 ACL 拒绝规则 (阻止普通用户修改)
        var result = runCommand("/bin/chmod", ["+a", "everyone deny delete,write,append,writeattr,writeextattr", path])
        guard result.success else {
            reply(false, "ACL setup failed: \(result.error ?? "unknown")")
            return
        }

        // 2. 设置 uchg 标志 (用户不可变)
        result = runCommand("/usr/bin/chflags", ["uchg", path])
        guard result.success else {
            // 回滚 ACL
            _ = runCommand("/bin/chmod", ["-N", path])
            reply(false, "chflags uchg failed: \(result.error ?? "unknown")")
            return
        }

        // 3. 隐藏目录
        result = runCommand("/usr/bin/chflags", ["hidden", path])
        guard result.success else {
            // 回滚
            _ = runCommand("/usr/bin/chflags", ["nouchg", path])
            _ = runCommand("/bin/chmod", ["-N", path])
            reply(false, "chflags hidden failed: \(result.error ?? "unknown")")
            return
        }

        logMessage("Directory protected successfully: \(path)")
        reply(true, nil)
    }

    func unprotectDirectory(_ path: String, withReply reply: @escaping (Bool, String?) -> Void) {
        // 先验证路径是否在白名单 (目录可能因为 uchg 无法访问)
        guard isPathAllowed(path) else {
            reply(false, "Path not allowed: \(path)")
            return
        }

        logMessage("Unprotecting directory: \(path)")

        // 1. 移除 uchg 标志 (必须先移除才能修改其他属性)
        var result = runCommand("/usr/bin/chflags", ["nouchg", path])
        guard result.success else {
            reply(false, "chflags nouchg failed: \(result.error ?? "unknown")")
            return
        }

        // 2. 移除 ACL
        result = runCommand("/bin/chmod", ["-N", path])
        guard result.success else {
            reply(false, "Remove ACL failed: \(result.error ?? "unknown")")
            return
        }

        // 3. 取消隐藏
        result = runCommand("/usr/bin/chflags", ["nohidden", path])
        guard result.success else {
            reply(false, "chflags nohidden failed: \(result.error ?? "unknown")")
            return
        }

        logMessage("Directory unprotected successfully: \(path)")
        reply(true, nil)
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {

        logMessage("New XPC connection from PID: \(newConnection.processIdentifier)")

        // 验证连接来源
        guard verifyConnection(newConnection) else {
            logMessage("Connection rejected: verification failed")
            return false
        }

        // 配置导出接口
        newConnection.exportedInterface = NSXPCInterface(with: DMSAHelperProtocol.self)
        newConnection.exportedObject = self

        // 设置连接处理器
        newConnection.invalidationHandler = { [weak self] in
            self?.logMessage("XPC connection invalidated")
        }

        newConnection.interruptionHandler = { [weak self] in
            self?.logMessage("XPC connection interrupted")
        }

        newConnection.resume()
        logMessage("Connection accepted")

        return true
    }

    /// 验证 XPC 连接的代码签名
    private func verifyConnection(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier

        // 获取进程的 SecCode
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary

        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard status == errSecSuccess, let secCode = code else {
            logMessage("Failed to get SecCode for PID \(pid): \(status)")
            return false
        }

        // 创建验证需求: 必须是 DMSA 主应用
        let requirementString = "identifier \"com.ttttt.dmsa\" and anchor apple generic"
        var requirementRef: SecRequirement?

        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirementRef) == errSecSuccess,
              let requirement = requirementRef else {
            logMessage("Failed to create requirement")
            return false
        }

        // 验证代码签名
        let verifyStatus = SecCodeCheckValidity(secCode, [], requirement)
        if verifyStatus != errSecSuccess {
            logMessage("Code signature verification failed for PID \(pid): \(verifyStatus)")
            return false
        }

        logMessage("Code signature verified for PID \(pid)")
        return true
    }
}
