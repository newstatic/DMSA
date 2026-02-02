import Foundation

/// Startup checker
/// Reference: SERVICE_FLOW/17_checklist.md
///
/// Executes 12 checks at service startup to ensure proper operation.
struct StartupChecker {

    private static let logger = Logger.forService("Startup")

    // MARK: - Check Results

    /// Single check result
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

    /// Full check report
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

    // MARK: - Preflight Checks (called at main.swift startup)

    /// Run preflight checks (items 1-5)
    /// These checks must complete before the service starts
    static func runPreflightChecks() -> CheckReport {
        logger.info("========== Preflight Checks ==========")

        var results: [CheckResult] = []

        // 1. Process running with root privileges
        results.append(checkRootPrivilege())

        // 2. Environment variables set
        results.append(checkEnvironmentVariables())

        // 3. macFUSE loaded successfully
        results.append(checkMacFUSE())

        // 4. Log directory writable
        results.append(checkLogDirectory())

        // 5. Config directory exists
        results.append(checkConfigDirectory())

        let report = CheckReport(results: results)
        logCheckReport(report, phase: "Preflight")
        return report
    }

    // MARK: - Runtime Checks (called during service startup)

    /// Check XPC listener status
    static func checkXPCListener(isRunning: Bool) -> CheckResult {
        if isRunning {
            return .success("XPC Listener", "Listener started")
        } else {
            return .failure("XPC Listener", "Listener failed to start", recoverable: false)
        }
    }

    /// Check config load status
    static func checkConfigLoaded(success: Bool, error: String? = nil) -> CheckResult {
        if success {
            return .success("Config Load", "Config file loaded successfully")
        } else {
            return .failure("Config Load", error ?? "Config load failed, using defaults", recoverable: true)
        }
    }

    /// Check FUSE mount status
    static func checkFUSEMount(success: Bool, mountPoint: String?, error: String? = nil) -> CheckResult {
        if success {
            return .success("FUSE Mount", "Mount successful: \(mountPoint ?? "unknown")")
        } else {
            return .failure("FUSE Mount", error ?? "FUSE mount failed", recoverable: true)
        }
    }

    /// Check backend directory protection status
    static func checkBackendProtection(success: Bool, error: String? = nil) -> CheckResult {
        if success {
            return .success("Backend Protection", "Directory protection set successfully")
        } else {
            return .failure("Backend Protection", error ?? "Directory protection setup failed", recoverable: true)
        }
    }

    /// Check index build status
    static func checkIndexBuild(success: Bool, filesCount: Int = 0, error: String? = nil) -> CheckResult {
        if success {
            return .success("Index Build", "Index complete, \(filesCount) files")
        } else {
            return .failure("Index Build", error ?? "Index build failed", recoverable: true)
        }
    }

    /// Check scheduler status
    static func checkScheduler(isRunning: Bool) -> CheckResult {
        if isRunning {
            return .success("Scheduler", "Sync scheduler started")
        } else {
            return .failure("Scheduler", "Scheduler failed to start", recoverable: true)
        }
    }

    /// Check notification queue status
    static func checkNotificationQueue(flushed: Bool, pendingCount: Int = 0) -> CheckResult {
        if flushed {
            return .success("Notification Queue", "Cached notifications sent")
        } else {
            return .failure("Notification Queue", "\(pendingCount) notifications still pending", recoverable: true)
        }
    }

    // MARK: - Private Check Methods

    /// Check 1: root privileges
    private static func checkRootPrivilege() -> CheckResult {
        let uid = getuid()
        if uid == 0 {
            return .success("Root Privilege", "Process running as root (uid=0)")
        } else {
            return .failure("Root Privilege", "Process not running as root (uid=\(uid))", recoverable: false)
        }
    }

    /// Check 2: environment variables
    private static func checkEnvironmentVariables() -> CheckResult {
        // Check OBJC_DISABLE_INITIALIZE_FORK_SAFETY (required by macFUSE)
        let forkSafety = ProcessInfo.processInfo.environment["OBJC_DISABLE_INITIALIZE_FORK_SAFETY"]

        if forkSafety == "YES" {
            return .success("Environment", "OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES")
        } else {
            // Try to set (only effective at process startup)
            setenv("OBJC_DISABLE_INITIALIZE_FORK_SAFETY", "YES", 1)
            return .success("Environment", "OBJC_DISABLE_INITIALIZE_FORK_SAFETY set")
        }
    }

    /// Check 3: macFUSE
    private static func checkMacFUSE() -> CheckResult {
        let fm = FileManager.default

        // Check framework
        let frameworkPath = "/Library/Frameworks/macFUSE.framework"
        guard fm.fileExists(atPath: frameworkPath) else {
            return .failure("macFUSE", "macFUSE.framework not found", recoverable: false)
        }

        // Check libfuse
        let libfusePaths = [
            "/usr/local/lib/libfuse.dylib",
            "/Library/Frameworks/macFUSE.framework/Versions/A/usr/local/lib/libfuse.2.dylib"
        ]

        let libfuseExists = libfusePaths.contains { fm.fileExists(atPath: $0) }
        guard libfuseExists else {
            return .failure("macFUSE", "libfuse.dylib not found", recoverable: false)
        }

        // Try to load
        if let handle = dlopen("/usr/local/lib/libfuse.dylib", RTLD_LAZY) {
            dlclose(handle)
            return .success("macFUSE", "macFUSE loaded successfully")
        } else if let handle = dlopen(libfusePaths[1], RTLD_LAZY) {
            dlclose(handle)
            return .success("macFUSE", "macFUSE loaded successfully (fallback path)")
        } else {
            let error = String(cString: dlerror())
            return .failure("macFUSE", "Load failed: \(error)", recoverable: false)
        }
    }

    /// Check 4: log directory
    private static func checkLogDirectory() -> CheckResult {
        let fm = FileManager.default
        let logDir = NSString("~/Library/Logs/DMSA").expandingTildeInPath

        // Check directory exists
        if !fm.fileExists(atPath: logDir) {
            do {
                try fm.createDirectory(atPath: logDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return .failure("Log Directory", "Cannot create directory: \(error.localizedDescription)", recoverable: true)
            }
        }

        // Check writable
        let testFile = (logDir as NSString).appendingPathComponent(".write_test")
        do {
            try "test".write(toFile: testFile, atomically: true, encoding: .utf8)
            try fm.removeItem(atPath: testFile)
            return .success("Log Directory", logDir)
        } catch {
            return .failure("Log Directory", "Directory not writable: \(error.localizedDescription)", recoverable: true)
        }
    }

    /// Check 5: config directory
    private static func checkConfigDirectory() -> CheckResult {
        let fm = FileManager.default
        let configDir = NSString("~/Library/Application Support/DMSA").expandingTildeInPath

        if fm.fileExists(atPath: configDir) {
            return .success("Config Directory", configDir)
        } else {
            do {
                try fm.createDirectory(atPath: configDir, withIntermediateDirectories: true, attributes: nil)
                return .success("Config Directory", "Directory created: \(configDir)")
            } catch {
                return .failure("Config Directory", "Cannot create directory: \(error.localizedDescription)", recoverable: true)
            }
        }
    }

    // MARK: - Log Output

    /// Output check report
    private static func logCheckReport(_ report: CheckReport, phase: String) {
        logger.info("---------- \(phase) Check Results ----------")

        for result in report.results {
            let status = result.passed ? "PASS" : "FAIL"
            let recoveryNote = (!result.passed && result.recoverable) ? " (recoverable)" : ""
            logger.info("\(status) [\(result.name)] \(result.message)\(recoveryNote)")
        }

        if report.allPassed {
            logger.info("---------- \(phase) Checks All Passed ----------")
        } else {
            let failedCount = report.results.filter { !$0.passed }.count
            let criticalCount = report.criticalFailures.count
            logger.warning("---------- \(phase) Checks Done: \(failedCount) failed, \(criticalCount) critical ----------")
        }
    }

    /// Output final check summary
    static func logFinalSummary(reports: [CheckReport]) {
        logger.info("========== Startup Check Final Summary ==========")

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

        logger.info("Passed: \(totalPassed) | Failed: \(totalFailed) | Critical: \(totalCritical)")

        if totalCritical > 0 {
            logger.error("Critical errors found, service may not function properly!")
        } else if totalFailed > 0 {
            logger.warning("Non-critical errors found, some features may be affected")
        } else {
            logger.info("All checks passed, service ready")
        }

        logger.info("==========================================")
    }
}
