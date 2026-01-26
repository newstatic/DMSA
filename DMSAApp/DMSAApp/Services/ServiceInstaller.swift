import Foundation

/// 服务安装管理器 (纯 launchctl 版本)
/// 使用传统 LaunchDaemon 方式安装服务，不依赖 SMAppService
@MainActor
final class ServiceInstaller {

    // MARK: - Singleton

    static let shared = ServiceInstaller()

    // MARK: - Properties

    private let logger = Logger.shared
    private let serviceClient = ServiceClient.shared

    /// 服务标识符
    private let serviceIdentifier = "com.ttttt.dmsa.service"

    /// LaunchDaemon plist 安装路径
    private let launchDaemonPlistPath = "/Library/LaunchDaemons/com.ttttt.dmsa.service.plist"

    /// LaunchDaemons 目录
    private let launchDaemonsDir = "/Library/LaunchDaemons"

    /// 服务二进制路径 (App Bundle 内)
    /// 根据当前 App 位置动态计算
    private var serviceBinaryPath: String {
        let bundlePath = Bundle.main.bundlePath
        return "\(bundlePath)/Contents/Library/LaunchServices/com.ttttt.dmsa.service"
    }

    /// 内嵌 plist 路径 (App Bundle Resources 目录)
    private var embeddedPlistPath: String? {
        Bundle.main.path(forResource: serviceIdentifier, ofType: "plist")
    }

    /// 是否在 Xcode 调试模式运行
    private var isRunningFromXcode: Bool {
        let bundlePath = Bundle.main.bundlePath
        return bundlePath.contains("DerivedData") || bundlePath.contains("Build/Products")
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// 检查并安装/更新服务
    /// - Returns: 安装结果
    func checkAndInstallService() async -> ServiceInstallResult {
        logger.info("检查 DMSAService 状态...")

        // 步骤 1: 检查二进制和 plist 是否都存在
        let binaryExists = FileManager.default.fileExists(atPath: serviceBinaryPath)
        let plistExists = FileManager.default.fileExists(atPath: launchDaemonPlistPath)

        if !binaryExists || !plistExists {
            logger.info("服务文件缺失 (binary: \(binaryExists), plist: \(plistExists))，需要安装...")
            return await installService()
        }

        // 步骤 1.5: 检查 plist 中的 Program 路径是否正确
        if !isPlistProgramPathCorrect() {
            logger.info("plist 中的 Program 路径不匹配当前二进制位置，需要重新安装...")
            return await reinstallService(reason: "Program 路径不匹配")
        }

        // 步骤 2: 检查服务是否在运行
        let isRunning = isServiceRunning()

        if !isRunning {
            logger.info("服务未运行，尝试启动...")
            await startService()

            // 等待服务启动
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            if !isServiceRunning() {
                logger.warn("服务启动失败，尝试重新安装...")
                return await reinstallService(reason: "服务无法启动")
            }
        }

        // 步骤 3: 检查版本兼容性
        logger.info("DMSAService 正在运行，检查版本...")

        do {
            _ = try await serviceClient.connect()

            let result = try await withTimeout(seconds: 5) {
                try await self.serviceClient.checkCompatibility()
            }

            if !result.compatible {
                logger.warn("服务版本不兼容: \(result.message ?? "")")
                return await updateService(reason: result.message ?? "版本不兼容")
            }

            if result.needsServiceUpdate {
                logger.info("建议更新服务: \(result.message ?? "")")
                return await updateService(reason: result.message ?? "有新版本可用")
            }

            let versionInfo = try await serviceClient.getVersionInfo()
            logger.info("服务版本正常: \(versionInfo.fullVersion)")
            return .alreadyInstalled(version: versionInfo.version)

        } catch {
            logger.error("无法连接到服务: \(error)")
            return await reinstallService(reason: "无法连接到服务")
        }
    }

    /// 安装服务
    /// 服务二进制已在 App Bundle 内，只需安装 plist 并启动
    func installService() async -> ServiceInstallResult {
        logger.info("开始安装 DMSAService...")

        // 检查服务二进制是否存在
        guard FileManager.default.fileExists(atPath: serviceBinaryPath) else {
            logger.error("找不到服务二进制: \(serviceBinaryPath)")
            return .failed(error: "找不到服务二进制文件")
        }

        logger.info("服务二进制: \(serviceBinaryPath), Xcode模式: \(isRunningFromXcode)")

        // 准备 plist 文件路径
        let plistToInstall: String

        if isRunningFromXcode {
            // Xcode 调试模式：动态生成 plist，指向当前 DerivedData 中的二进制
            let tempPlistPath = "/tmp/com.ttttt.dmsa.service.plist"
            let plistContent = generatePlistContent(programPath: serviceBinaryPath)

            do {
                try plistContent.write(toFile: tempPlistPath, atomically: true, encoding: .utf8)
                logger.info("已生成临时 plist: \(tempPlistPath)")
            } catch {
                logger.error("生成临时 plist 失败: \(error)")
                return .failed(error: "生成临时 plist 失败")
            }
            plistToInstall = tempPlistPath
        } else {
            // 正式安装模式：使用内嵌的 plist
            guard let embeddedPlist = embeddedPlistPath else {
                logger.error("找不到内嵌的服务 plist")
                return .failed(error: "找不到内嵌的服务 plist 文件")
            }
            plistToInstall = embeddedPlist
        }

        // 构建安装脚本
        let script = """
            do shell script "\\
            mkdir -p '\(launchDaemonsDir)' && \\
            cp -f '\(plistToInstall)' '\(launchDaemonPlistPath)' && \\
            chmod 644 '\(launchDaemonPlistPath)' && \\
            chown root:wheel '\(launchDaemonPlistPath)' && \\
            launchctl bootout system/\(serviceIdentifier) 2>/dev/null || true && \\
            launchctl bootstrap system '\(launchDaemonPlistPath)'\\
            " with administrator privileges
            """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "未知错误"
                logger.error("安装服务失败: \(errorMsg)")
                return .failed(error: "安装失败: \(errorMsg)")
            }

            logger.info("服务安装成功")

            // 等待服务启动
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // 验证服务是否在运行
            if isServiceRunning() {
                return .installed(version: Constants.version)
            } else {
                logger.warn("服务安装后未能启动")
                return .failed(error: "服务安装成功但未能启动")
            }
        } else {
            logger.error("创建 AppleScript 失败")
            return .failed(error: "创建安装脚本失败")
        }
    }

    /// 更新服务
    func updateService(reason: String) async -> ServiceInstallResult {
        logger.info("更新 DMSAService: \(reason)")

        // 断开连接
        serviceClient.disconnect()

        // 停止服务
        await stopService()

        // 等待服务完全停止
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // 重新安装
        let result = await installService()

        if case .installed = result {
            // 重新连接
            do {
                _ = try await serviceClient.connect()
                let versionInfo = try await serviceClient.getVersionInfo()
                logger.info("服务更新成功: \(versionInfo.fullVersion)")
                return .updated(fromVersion: "", toVersion: versionInfo.version)
            } catch {
                logger.error("服务更新后连接失败: \(error)")
                return .failed(error: "更新后无法连接: \(error.localizedDescription)")
            }
        }

        return result
    }

    /// 重新安装服务
    func reinstallService(reason: String) async -> ServiceInstallResult {
        logger.info("重新安装 DMSAService: \(reason)")

        // 断开连接
        serviceClient.disconnect()

        // 卸载
        await uninstallService()

        // 等待
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // 重新安装
        return await installService()
    }

    /// 卸载服务
    /// 只移除 plist，二进制保留在 App Bundle 内
    func uninstallService() async {
        logger.info("卸载 DMSAService...")

        let script = """
            do shell script "\\
            launchctl bootout system/\(serviceIdentifier) 2>/dev/null || true && \\
            rm -f '\(launchDaemonPlistPath)'\\
            " with administrator privileges
            """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if error == nil {
                logger.info("服务已卸载")
            } else {
                let errorMsg = error?[NSAppleScript.errorMessage] as? String ?? "未知错误"
                logger.error("卸载服务失败: \(errorMsg)")
            }
        }
    }

    /// 停止服务
    func stopService() async {
        logger.info("停止 DMSAService...")

        let script = """
            do shell script "launchctl bootout system/\(serviceIdentifier) 2>/dev/null || true" with administrator privileges
            """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            // 忽略错误，服务可能本来就没运行
        }
    }

    /// 启动服务
    func startService() async {
        logger.info("启动 DMSAService...")

        // 先检查 plist 是否存在
        guard FileManager.default.fileExists(atPath: launchDaemonPlistPath) else {
            logger.error("服务 plist 不存在，无法启动")
            return
        }

        let script = """
            do shell script "launchctl bootstrap system '\(launchDaemonPlistPath)' 2>/dev/null || launchctl kickstart -k system/\(serviceIdentifier)" with administrator privileges
            """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if error == nil {
                logger.info("服务启动命令已执行")
            } else {
                let errorMsg = error?[NSAppleScript.errorMessage] as? String ?? "未知错误"
                logger.warn("启动服务时出现警告: \(errorMsg)")
            }
        }
    }

    /// 检查服务是否已安装
    func isServiceInstalled() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: serviceBinaryPath) &&
               fm.fileExists(atPath: launchDaemonPlistPath)
    }

    /// 检查服务是否在运行
    func isServiceRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(serviceIdentifier)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 获取服务状态
    func getServiceStatus() -> ServiceStatus {
        if !isServiceInstalled() {
            return .notInstalled
        }

        if isServiceRunning() {
            return .running
        } else {
            return .stopped
        }
    }

    /// 检查已安装的 plist 中的 Program 路径是否匹配当前二进制路径
    private func isPlistProgramPathCorrect() -> Bool {
        guard let plistData = FileManager.default.contents(atPath: launchDaemonPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let programPath = plist["Program"] as? String else {
            logger.warn("无法读取 plist 或获取 Program 路径")
            return false
        }

        let expected = serviceBinaryPath
        let isMatch = programPath == expected

        if !isMatch {
            logger.info("plist Program 路径不匹配: 当前=\(programPath), 期望=\(expected)")
        }

        return isMatch
    }
}

// MARK: - ServiceInstallResult

/// 服务安装结果
enum ServiceInstallResult {
    case installed(version: String)
    case updated(fromVersion: String, toVersion: String)
    case alreadyInstalled(version: String)
    case requiresApproval  // 保留兼容性，但不再使用
    case failed(error: String)

    var isSuccess: Bool {
        switch self {
        case .installed, .updated, .alreadyInstalled:
            return true
        case .requiresApproval, .failed:
            return false
        }
    }

    var message: String {
        switch self {
        case .installed(let version):
            return "服务已安装 (v\(version))"
        case .updated(let from, let to):
            return "服务已更新 (\(from) → \(to))"
        case .alreadyInstalled(let version):
            return "服务已就绪 (v\(version))"
        case .requiresApproval:
            return "需要用户批准"
        case .failed(let error):
            return "安装失败: \(error)"
        }
    }
}

// MARK: - ServiceStatus

/// 服务状态
enum ServiceStatus {
    case running
    case stopped
    case notInstalled
    case requiresApproval  // 保留兼容性，但不再使用
    case unknown
}

// MARK: - Timeout Helper

/// 超时错误
enum TimeoutError: Error {
    case timedOut
}

/// 带超时的异步操作
private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timedOut
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Plist Generation

extension ServiceInstaller {
    /// 生成 LaunchDaemon plist 内容
    /// - Parameter programPath: 服务二进制的完整路径
    /// - Returns: plist XML 字符串
    private func generatePlistContent(programPath: String) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(serviceIdentifier)</string>

            <key>MachServices</key>
            <dict>
                <key>\(serviceIdentifier)</key>
                <true/>
            </dict>

            <key>Program</key>
            <string>\(programPath)</string>

            <key>UserName</key>
            <string>root</string>

            <key>KeepAlive</key>
            <true/>

            <key>ThrottleInterval</key>
            <integer>5</integer>

            <key>ProcessType</key>
            <string>Interactive</string>

            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>/usr/bin:/bin:/usr/sbin:/sbin:/Library/Frameworks</string>
            </dict>

            <key>StandardOutPath</key>
            <string>/var/log/dmsa-service.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/dmsa-service.error.log</string>

            <key>ExitTimeOut</key>
            <integer>30</integer>
        </dict>
        </plist>
        """
    }
}
