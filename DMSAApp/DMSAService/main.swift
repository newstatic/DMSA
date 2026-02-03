import Foundation

// MARK: - DMSAService Entry Point
// Unified background service, combining VFS + Sync + Helper functionality
// Runs as LaunchDaemon with root privileges

// ============================================================
// Important: macFUSE fork compatibility settings
// ============================================================
// macFUSE's mount internally calls fork() to create child processes.
// In a multi-threaded environment, if the child process attempts to
// initialize Objective-C classes, it triggers:
// "*** multi-threaded process forked ***" crash
//
// Solutions:
// 1. Set OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES (partial mitigation)
// 2. Pre-load macFUSE framework before any multi-threaded operations
// 3. Pre-initialize all potentially used Objective-C classes
// ============================================================

// Must be set before any code executes
setenv("OBJC_DISABLE_INITIALIZE_FORK_SAFETY", "YES", 1)

// Pre-load macFUSE framework (before creating any threads)
_ = {
    // Load macFUSE framework
    if let bundle = Bundle(path: "/Library/Frameworks/macFUSE.framework") {
        try? bundle.loadAndReturnError()
    }

    // Pre-initialize critical classes
    _ = NSObject.self
    _ = NSString.self
    _ = NSArray.self
    _ = NSDictionary.self
    _ = NSData.self
    _ = NSNumber.self
    _ = NSError.self
    _ = NSURL.self
    _ = NSDate.self
    _ = FileManager.default
    _ = ProcessInfo.processInfo
    _ = Thread.current
    _ = NotificationCenter.default
    _ = DistributedNotificationCenter.default()
    _ = DispatchQueue.main
    _ = DispatchQueue.global()

    // Pre-initialize GMUserFileSystem class
    if let gmClass = NSClassFromString("GMUserFileSystem") {
        _ = gmClass.description()
    }
}()

// Set up logger global state provider (before creating logger)
// Reference: SERVICE_FLOW/16_LoggingSpec.md
Logger.globalStateProvider = {
    // Use simplified synchronous retrieval
    // Note: Since ServiceStateManager is an actor, use cached value to avoid deadlocks
    return LoggerStateCache.currentState
}

// Logger state cache (to avoid actor deadlocks)
enum LoggerStateCache {
    static var currentState: String = "STARTING"

    static func update(_ state: String) {
        currentState = state
    }
}

let logger = Logger.forService("Main")

logger.info("========================================")
logger.info("DMSAService v\(Constants.appVersion) starting")
logger.info("Build: \(BuildInfo.buildTime) [\(BuildInfo.configuration)]")
logger.info("PID: \(ProcessInfo.processInfo.processIdentifier)")
logger.info("UID: \(getuid())")
logger.info("========================================")

logger.info("Waiting for App to connect and set userHome via XPC...")
logger.info("========================================")

// MARK: - Directory Setup

func setupDirectories() {
    let fm = FileManager.default
    let directories: [URL] = [
        Constants.Paths.appSupport,
        Constants.Paths.sharedData,
        Constants.Paths.database,
        Constants.Paths.logs
    ]

    for dir in directories {
        let path = dir.path
        if !fm.fileExists(atPath: path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                logger.info("Created directory: \(path)")
            } catch {
                logger.error("Failed to create directory: \(path) - \(error)")
            }
        }
    }
}

// MARK: - Signal Handling

func setupSignalHandlers() {
    // SIGTERM: Graceful shutdown
    signal(SIGTERM) { _ in
        logger.info("Received SIGTERM, preparing to shut down...")
        Task {
            await ServiceDelegate.shared?.prepareForShutdown()
            logger.info("DMSAService shut down safely")
            exit(0)
        }
    }

    // SIGHUP: Reload configuration
    signal(SIGHUP) { _ in
        logger.info("Received SIGHUP, reloading configuration...")
        Task {
            await ServiceDelegate.shared?.reloadConfiguration()
        }
    }

    // SIGINT: Interrupt (for debugging)
    signal(SIGINT) { _ in
        logger.info("Received SIGINT, preparing to shut down...")
        Task {
            await ServiceDelegate.shared?.prepareForShutdown()
            logger.info("DMSAService shut down safely")
            exit(0)
        }
    }
}

// MARK: - Main Flow

// 0. Run preflight checks (root privileges, environment variables, macFUSE, etc.)
// Reference: SERVICE_FLOW/17_Checklist.md
let preflightReport = StartupChecker.runPreflightChecks()

// Check for critical failures
if !preflightReport.criticalFailures.isEmpty {
    logger.error("Preflight check found critical errors, service cannot start")
    for failure in preflightReport.criticalFailures {
        logger.error("  - \(failure.name): \(failure.message)")
    }
    exit(1)
}

// 1. Set up signal handlers (before anything else)
setupSignalHandlers()

// 2. Create service delegate
let delegate = ServiceDelegate()

// 3. Create XPC listener (must be ready before App connects)
let listener = NSXPCListener(machServiceName: Constants.XPCService.service)
listener.delegate = delegate
listener.resume()

// Set XPC_READY state, enable notification queue flushing
Task {
    await ServiceStateManager.shared.setState(.xpcReady)
}

logger.info("XPC listener started: \(Constants.XPCService.service)")

// ============================================================
// FUSE Mount Strategy
// ============================================================
// macFUSE calls fork() during mount. In a multi-threaded environment,
// the child process may crash when initializing Objective-C classes.
//
// Mitigations:
// 1. Set OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES (already set in plist and above)
// 2. Pre-initialize critical Objective-C classes (already done above)
// 3. Delay briefly to let the process stabilize before mounting
// ============================================================

// 5. Start power monitoring (sleep/wake)
let powerMonitor = ServicePowerMonitor()
powerMonitor.onSystemWillSleep = {
    logger.info("System will sleep, pausing sync...")
    await delegate.implementation.pauseSyncForSleep()
}
powerMonitor.onSystemWake = {
    logger.info("System woke up, checking FUSE mount status...")
    await delegate.implementation.checkAndRecoverAfterWake()
}
powerMonitor.start()

// 6. Start background tasks — wait for App to set userHome first
Task {
    // Wait for App to connect and call setUserHome via XPC
    // This blocks until userHome is set (timeout 120s)
    logger.info("Waiting for setUserHome from App...")
    let gotUserHome = await Task.detached {
        UserPathManager.shared.waitForUserHome(timeout: 120)
    }.value

    if !gotUserHome {
        logger.error("Timeout waiting for setUserHome, using fallback path")
    }

    let home = UserPathManager.shared.userHome
    logger.info("userHome resolved: \(home)")
    logger.info("  logs: \(Constants.Paths.logs.path)")
    logger.info("  appSupport: \(Constants.Paths.appSupport.path)")

    // Now safe to set up directories (paths depend on userHome)
    setupDirectories()

    // Brief delay to let process initialization complete
    try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

    // Start sync scheduler first to ensure SyncManager has configuration
    // This way syncNow requests during autoMount can be handled properly
    await delegate.startScheduler()

    // Auto-mount VFS
    // Note: VFSManager.mount() internally will:
    // 1. Set INDEXING state
    // 2. Build index
    // 3. Set READY state and send stateChanged notification
    // 4. Send indexReady notification
    await delegate.autoMount()

    // After autoMount completes, VFSManager has already set READY state
    // If no sync pairs need mounting, manually set READY state
    let currentState = await ServiceStateManager.shared.getState()
    if currentState != .ready {
        logger.info("All mounts complete, manually setting READY state")
        await ServiceStateManager.shared.setState(.ready)
    } else {
        logger.info("VFSManager has already set READY state")
    }
}

// 6. Run main event loop
logger.info("DMSAService ready, awaiting connections...")
RunLoop.main.run()
