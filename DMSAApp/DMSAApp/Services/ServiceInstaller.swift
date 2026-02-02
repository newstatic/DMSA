import Foundation

/// Service installer (pure launchctl version)
/// Uses traditional LaunchDaemon approach, no SMAppService dependency
@MainActor
final class ServiceInstaller {

    // MARK: - Singleton

    static let shared = ServiceInstaller()

    // MARK: - Properties

    private let logger = Logger.shared
    private let serviceClient = ServiceClient.shared

    /// Service identifier
    private let serviceIdentifier = "com.ttttt.dmsa.service"

    /// LaunchDaemon plist install path
    private let launchDaemonPlistPath = "/Library/LaunchDaemons/com.ttttt.dmsa.service.plist"

    /// LaunchDaemons directory
    private let launchDaemonsDir = "/Library/LaunchDaemons"

    /// Service binary path (inside App Bundle)
    /// Dynamically computed based on current App location
    private var serviceBinaryPath: String {
        let bundlePath = Bundle.main.bundlePath
        return "\(bundlePath)/Contents/Library/LaunchServices/com.ttttt.dmsa.service"
    }

    /// Embedded plist path (App Bundle Resources directory)
    private var embeddedPlistPath: String? {
        Bundle.main.path(forResource: serviceIdentifier, ofType: "plist")
    }

    /// Whether running from Xcode debug mode
    private var isRunningFromXcode: Bool {
        let bundlePath = Bundle.main.bundlePath
        return bundlePath.contains("DerivedData") || bundlePath.contains("Build/Products")
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Check and install/update service
    /// - Returns: Installation result
    func checkAndInstallService() async -> ServiceInstallResult {
        logger.info("Checking DMSAService status...")

        // Step 1: Check if binary and plist exist
        let binaryExists = FileManager.default.fileExists(atPath: serviceBinaryPath)
        let plistExists = FileManager.default.fileExists(atPath: launchDaemonPlistPath)

        if !binaryExists || !plistExists {
            logger.info("Service files missing (binary: \(binaryExists), plist: \(plistExists)), installing...")
            return await installService()
        }

        // Step 1.5: Check if Program path in plist is correct
        if !isPlistProgramPathCorrect() {
            logger.info("Plist Program path does not match current binary location, reinstalling...")
            return await reinstallService(reason: "Program path mismatch")
        }

        // Step 2: Check if service is running
        let isRunning = isServiceRunning()

        if !isRunning {
            logger.info("Service not running, attempting to start...")
            await startService()

            // Wait for service to start
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            if !isServiceRunning() {
                logger.warn("Service failed to start, attempting reinstall...")
                return await reinstallService(reason: "Service failed to start")
            }
        }

        // Step 3: Check version compatibility
        logger.info("DMSAService is running, checking version...")

        do {
            _ = try await serviceClient.connect()

            let result = try await withTimeout(seconds: 5) {
                try await self.serviceClient.checkCompatibility()
            }

            if !result.compatible {
                logger.warn("Service version incompatible: \(result.message ?? "")")
                return await updateService(reason: result.message ?? "Version incompatible")
            }

            if result.needsServiceUpdate {
                logger.info("Service update recommended: \(result.message ?? "")")
                return await updateService(reason: result.message ?? "New version available")
            }

            let versionInfo = try await serviceClient.getVersionInfo()
            logger.info("Service version OK: \(versionInfo.fullVersion)")
            return .alreadyInstalled(version: versionInfo.version)

        } catch {
            logger.error("Cannot connect to service: \(error)")
            return await reinstallService(reason: "Cannot connect to service")
        }
    }

    /// Install service
    /// Binary is already in App Bundle, just install plist and start
    func installService() async -> ServiceInstallResult {
        logger.info("Installing DMSAService...")

        // Check if service binary exists
        guard FileManager.default.fileExists(atPath: serviceBinaryPath) else {
            logger.error("Service binary not found: \(serviceBinaryPath)")
            return .failed(error: "Service binary not found")
        }

        logger.info("Service binary: \(serviceBinaryPath), Xcode mode: \(isRunningFromXcode)")

        // Determine plist source
        let plistToInstall: String

        if isRunningFromXcode {
            // Xcode mode: dynamically generate plist pointing to DerivedData binary
            let tempPlistPath = "/tmp/com.ttttt.dmsa.service.plist"
            let plistContent = generatePlistContent(programPath: serviceBinaryPath)

            do {
                try plistContent.write(toFile: tempPlistPath, atomically: true, encoding: .utf8)
                logger.info("Generated dynamic plist: \(tempPlistPath), Program=\(serviceBinaryPath)")
            } catch {
                logger.error("Failed to generate plist: \(error)")
                return .failed(error: "Failed to generate plist")
            }
            plistToInstall = tempPlistPath
        } else {
            // Production mode: use embedded plist from App Bundle Resources
            // (pre-built during release, Program points to /Applications/DMSA.app/...)
            guard let embeddedPlist = embeddedPlistPath else {
                logger.error("Embedded service plist not found in App Bundle")
                return .failed(error: "Embedded service plist not found")
            }
            logger.info("Using embedded plist: \(embeddedPlist)")
            plistToInstall = embeddedPlist
        }

        // Build installation script
        // Binary stays in App Bundle, plist points to it
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
                let errorMsg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                logger.error("Service installation failed: \(errorMsg)")
                return .failed(error: "Installation failed: \(errorMsg)")
            }

            logger.info("Service installed successfully")

            // Wait for service to start
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // Verify service is running
            if isServiceRunning() {
                return .installed(version: Constants.version)
            } else {
                logger.warn("Service failed to start after installation")
                return .failed(error: "Service installed but failed to start")
            }
        } else {
            logger.error("Failed to create AppleScript")
            return .failed(error: "Failed to create installation script")
        }
    }

    /// Update service
    func updateService(reason: String) async -> ServiceInstallResult {
        logger.info("Updating DMSAService: \(reason)")

        // Disconnect
        serviceClient.disconnect()

        // Stop service
        await stopService()

        // Wait for service to fully stop
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Reinstall
        let result = await installService()

        if case .installed = result {
            // Reconnect
            do {
                _ = try await serviceClient.connect()
                let versionInfo = try await serviceClient.getVersionInfo()
                logger.info("Service updated successfully: \(versionInfo.fullVersion)")
                return .updated(fromVersion: "", toVersion: versionInfo.version)
            } catch {
                logger.error("Failed to connect after service update: \(error)")
                return .failed(error: "Cannot connect after update: \(error.localizedDescription)")
            }
        }

        return result
    }

    /// Reinstall service
    func reinstallService(reason: String) async -> ServiceInstallResult {
        logger.info("Reinstalling DMSAService: \(reason)")

        // Disconnect
        serviceClient.disconnect()

        // Uninstall
        await uninstallService()

        // Wait
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Reinstall
        return await installService()
    }

    /// Uninstall service
    /// Only removes plist, binary stays in App Bundle
    func uninstallService() async {
        logger.info("Uninstalling DMSAService...")

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
                logger.info("Service uninstalled")
            } else {
                let errorMsg = error?[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                logger.error("Service uninstall failed: \(errorMsg)")
            }
        }
    }

    /// Stop service
    func stopService() async {
        logger.info("Stopping DMSAService...")

        let script = """
            do shell script "launchctl bootout system/\(serviceIdentifier) 2>/dev/null || true" with administrator privileges
            """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            // Ignore errors, service may not be running
        }
    }

    /// Start service
    func startService() async {
        logger.info("Starting DMSAService...")

        // Check if plist exists first
        guard FileManager.default.fileExists(atPath: launchDaemonPlistPath) else {
            logger.error("Service plist not found, cannot start")
            return
        }

        let script = """
            do shell script "launchctl bootstrap system '\(launchDaemonPlistPath)' 2>/dev/null || launchctl kickstart -k system/\(serviceIdentifier)" with administrator privileges
            """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if error == nil {
                logger.info("Service start command executed")
            } else {
                let errorMsg = error?[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                logger.warn("Warning when starting service: \(errorMsg)")
            }
        }
    }

    /// Check if service is installed
    func isServiceInstalled() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: serviceBinaryPath) &&
               fm.fileExists(atPath: launchDaemonPlistPath)
    }

    /// Check if service is running
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

    /// Get service status
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

    /// Expected Program path in the installed plist
    private var expectedProgramPath: String {
        if isRunningFromXcode {
            return serviceBinaryPath  // DerivedData path
        } else {
            return "/Applications/DMSA.app/Contents/Library/LaunchServices/\(serviceIdentifier)"
        }
    }

    /// Check if Program path in installed plist matches expected path
    private func isPlistProgramPathCorrect() -> Bool {
        guard let plistData = FileManager.default.contents(atPath: launchDaemonPlistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let programPath = plist["Program"] as? String else {
            logger.warn("Cannot read plist or get Program path")
            return false
        }

        let expected = expectedProgramPath
        let isMatch = programPath == expected

        if !isMatch {
            logger.info("Plist Program path mismatch: current=\(programPath), expected=\(expected)")
        }

        return isMatch
    }
}

// MARK: - ServiceInstallResult

/// Service installation result
enum ServiceInstallResult {
    case installed(version: String)
    case updated(fromVersion: String, toVersion: String)
    case alreadyInstalled(version: String)
    case requiresApproval  // Kept for compatibility, no longer used
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
            return "Service installed (v\(version))"
        case .updated(let from, let to):
            return "Service updated (\(from) → \(to))"
        case .alreadyInstalled(let version):
            return "Service ready (v\(version))"
        case .requiresApproval:
            return "Requires user approval"
        case .failed(let error):
            return "Installation failed: \(error)"
        }
    }
}

// MARK: - ServiceStatus

/// Service status
enum ServiceStatus {
    case running
    case stopped
    case notInstalled
    case requiresApproval  // Kept for compatibility, no longer used
    case unknown
}

// MARK: - Timeout Helper

/// Timeout error
enum TimeoutError: Error {
    case timedOut
}

/// Async operation with timeout
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
    /// Generate LaunchDaemon plist content (Xcode debug mode only)
    /// - Parameter programPath: Full path to the service binary
    /// - Returns: plist XML string
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
                <key>OBJC_DISABLE_INITIALIZE_FORK_SAFETY</key>
                <string>YES</string>
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
