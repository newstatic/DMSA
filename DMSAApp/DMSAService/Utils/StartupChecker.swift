import Foundation

/// 启动检查器
/// 参考文档: SERVICE_FLOW/17_检查清单.md
///
/// 负责执行服务启动时的 12 项检查，确保服务正常运行。
struct StartupChecker {

    private static let logger = Logger.forService("Startup")

    // MARK: - 检查结果

    /// 单项检查结果
    struct CheckResult {
        let name: String
        let passed: Bool
        let message: String
        let recoverable: Bool

        static func success(_ name: String, _ message: String = "") -> CheckResult {
            return CheckResult(name: name, passed: true, message: message, recoverable: true)
        }

        static func failure(_ name: String, _ message: String, recoverable: Bool = true) -> CheckResult {
            return CheckResult(name: name, passed: false, message: message, recoverable: recoverable)
        }
    }

    /// 完整检查报告
    struct CheckReport {
        let results: [CheckResult]
        let timestamp: Date
        let allPassed: Bool
        let criticalFailures: [CheckResult]

        init(results: [CheckResult]) {
            self.results = results
            self.timestamp = Date()
            self.allPassed = results.allSatisfy { $0.passed }
            self.criticalFailures = results.filter { !$0.passed && !$0.recoverable }
        }
    }

    // MARK: - 预启动检查 (main.swift 启动时调用)

    /// 执行预启动检查 (1-5 项)
    /// 这些检查必须在服务启动前完成
    static func runPreflightChecks() -> CheckReport {
        logger.info("========== 预启动检查 ==========")

        var results: [CheckResult] = []

        // 1. 进程以 root 权限运行
        results.append(checkRootPrivilege())

        // 2. 环境变量已设置
        results.append(checkEnvironmentVariables())

        // 3. macFUSE 加载成功
        results.append(checkMacFUSE())

        // 4. 日志目录可写
        results.append(checkLogDirectory())

        // 5. 配置目录存在
        results.append(checkConfigDirectory())

        let report = CheckReport(results: results)
        logCheckReport(report, phase: "预启动")
        return report
    }

    // MARK: - 运行时检查 (服务启动过程中调用)

    /// 检查 XPC 监听器状态
    static func checkXPCListener(isRunning: Bool) -> CheckResult {
        if isRunning {
            return .success("XPC监听器", "监听器已启动")
        } else {
            return .failure("XPC监听器", "监听器启动失败", recoverable: false)
        }
    }

    /// 检查配置加载状态
    static func checkConfigLoaded(success: Bool, error: String? = nil) -> CheckResult {
        if success {
            return .success("配置加载", "配置文件加载成功")
        } else {
            return .failure("配置加载", error ?? "配置加载失败，将使用默认配置", recoverable: true)
        }
    }

    /// 检查 FUSE 挂载状态
    static func checkFUSEMount(success: Bool, mountPoint: String?, error: String? = nil) -> CheckResult {
        if success {
            return .success("FUSE挂载", "挂载成功: \(mountPoint ?? "未知")")
        } else {
            return .failure("FUSE挂载", error ?? "FUSE 挂载失败", recoverable: true)
        }
    }

    /// 检查后端目录保护状态
    static func checkBackendProtection(success: Bool, error: String? = nil) -> CheckResult {
        if success {
            return .success("后端保护", "目录保护设置成功")
        } else {
            return .failure("后端保护", error ?? "目录保护设置失败", recoverable: true)
        }
    }

    /// 检查索引构建状态
    static func checkIndexBuild(success: Bool, filesCount: Int = 0, error: String? = nil) -> CheckResult {
        if success {
            return .success("索引构建", "索引完成，共 \(filesCount) 个文件")
        } else {
            return .failure("索引构建", error ?? "索引构建失败", recoverable: true)
        }
    }

    /// 检查调度器状态
    static func checkScheduler(isRunning: Bool) -> CheckResult {
        if isRunning {
            return .success("调度器", "同步调度器已启动")
        } else {
            return .failure("调度器", "调度器启动失败", recoverable: true)
        }
    }

    /// 检查通知队列状态
    static func checkNotificationQueue(flushed: Bool, pendingCount: Int = 0) -> CheckResult {
        if flushed {
            return .success("通知队列", "缓存通知已发送")
        } else {
            return .failure("通知队列", "仍有 \(pendingCount) 条通知待发送", recoverable: true)
        }
    }

    // MARK: - 私有检查方法

    /// 检查 1: root 权限
    private static func checkRootPrivilege() -> CheckResult {
        let uid = getuid()
        if uid == 0 {
            return .success("root权限", "进程以 root 权限运行 (uid=0)")
        } else {
            return .failure("root权限", "进程未以 root 权限运行 (uid=\(uid))", recoverable: false)
        }
    }

    /// 检查 2: 环境变量
    private static func checkEnvironmentVariables() -> CheckResult {
        // 检查 OBJC_DISABLE_INITIALIZE_FORK_SAFETY (macFUSE 需要)
        let forkSafety = ProcessInfo.processInfo.environment["OBJC_DISABLE_INITIALIZE_FORK_SAFETY"]

        if forkSafety == "YES" {
            return .success("环境变量", "OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES")
        } else {
            // 尝试设置 (仅在进程启动时有效)
            setenv("OBJC_DISABLE_INITIALIZE_FORK_SAFETY", "YES", 1)
            return .success("环境变量", "OBJC_DISABLE_INITIALIZE_FORK_SAFETY 已设置")
        }
    }

    /// 检查 3: macFUSE
    private static func checkMacFUSE() -> CheckResult {
        let fm = FileManager.default

        // 检查 Framework
        let frameworkPath = "/Library/Frameworks/macFUSE.framework"
        guard fm.fileExists(atPath: frameworkPath) else {
            return .failure("macFUSE", "macFUSE.framework 未找到", recoverable: false)
        }

        // 检查 libfuse
        let libfusePaths = [
            "/usr/local/lib/libfuse.dylib",
            "/Library/Frameworks/macFUSE.framework/Versions/A/usr/local/lib/libfuse.2.dylib"
        ]

        let libfuseExists = libfusePaths.contains { fm.fileExists(atPath: $0) }
        guard libfuseExists else {
            return .failure("macFUSE", "libfuse.dylib 未找到", recoverable: false)
        }

        // 尝试加载
        if let handle = dlopen("/usr/local/lib/libfuse.dylib", RTLD_LAZY) {
            dlclose(handle)
            return .success("macFUSE", "macFUSE 加载成功")
        } else if let handle = dlopen(libfusePaths[1], RTLD_LAZY) {
            dlclose(handle)
            return .success("macFUSE", "macFUSE 加载成功 (备用路径)")
        } else {
            let error = String(cString: dlerror())
            return .failure("macFUSE", "加载失败: \(error)", recoverable: false)
        }
    }

    /// 检查 4: 日志目录
    private static func checkLogDirectory() -> CheckResult {
        let fm = FileManager.default
        let logDir = NSString("~/Library/Logs/DMSA").expandingTildeInPath

        // 检查目录存在
        if !fm.fileExists(atPath: logDir) {
            do {
                try fm.createDirectory(atPath: logDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return .failure("日志目录", "无法创建目录: \(error.localizedDescription)", recoverable: true)
            }
        }

        // 检查可写
        let testFile = (logDir as NSString).appendingPathComponent(".write_test")
        do {
            try "test".write(toFile: testFile, atomically: true, encoding: .utf8)
            try fm.removeItem(atPath: testFile)
            return .success("日志目录", logDir)
        } catch {
            return .failure("日志目录", "目录不可写: \(error.localizedDescription)", recoverable: true)
        }
    }

    /// 检查 5: 配置目录
    private static func checkConfigDirectory() -> CheckResult {
        let fm = FileManager.default
        let configDir = NSString("~/Library/Application Support/DMSA").expandingTildeInPath

        if fm.fileExists(atPath: configDir) {
            return .success("配置目录", configDir)
        } else {
            do {
                try fm.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
                return .success("配置目录", "目录已创建: \(configDir)")
            } catch {
                return .failure("配置目录", "无法创建目录: \(error.localizedDescription)", recoverable: true)
            }
        }
    }

    // MARK: - 日志输出

    /// 输出检查报告
    private static func logCheckReport(_ report: CheckReport, phase: String) {
        logger.info("---------- \(phase)检查结果 ----------")

        for result in report.results {
            let status = result.passed ? "✅" : "❌"
            let recoveryNote = (!result.passed && result.recoverable) ? " (可恢复)" : ""
            logger.info("\(status) [\(result.name)] \(result.message)\(recoveryNote)")
        }

        if report.allPassed {
            logger.info("---------- \(phase)检查全部通过 ----------")
        } else {
            let failedCount = report.results.filter { !$0.passed }.count
            let criticalCount = report.criticalFailures.count
            logger.warning("---------- \(phase)检查完成: \(failedCount) 项失败, \(criticalCount) 项严重 ----------")
        }
    }

    /// 输出最终检查摘要
    static func logFinalSummary(reports: [CheckReport]) {
        logger.info("========== 启动检查最终摘要 ==========")

        var totalPassed = 0
        var totalFailed = 0
        var totalCritical = 0

        for report in reports {
            for result in report.results {
                if result.passed {
                    totalPassed += 1
                } else {
                    totalFailed += 1
                    if !result.recoverable {
                        totalCritical += 1
                    }
                }
            }
        }

        logger.info("通过: \(totalPassed) | 失败: \(totalFailed) | 严重: \(totalCritical)")

        if totalCritical > 0 {
            logger.error("存在严重错误，服务可能无法正常运行!")
        } else if totalFailed > 0 {
            logger.warning("存在非严重错误，部分功能可能受影响")
        } else {
            logger.info("所有检查通过，服务准备就绪")
        }

        logger.info("==========================================")
    }
}
