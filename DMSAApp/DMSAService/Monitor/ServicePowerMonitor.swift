import Foundation
import IOKit
import IOKit.pwr_mgt

// IOKit power message constants
private let kIOMessageCanSystemSleepValue: UInt32 = 0xe0000270
private let kIOMessageSystemWillSleepValue: UInt32 = 0xe0000280
private let kIOMessageSystemHasPoweredOnValue: UInt32 = 0xe0000300

/// Service-side power state monitor
/// Listens for system sleep/wake events; checks and restores FUSE mounts after wake
final class ServicePowerMonitor {

    private let logger = Logger.forService("Power")

    /// Callback after system wake
    var onSystemWake: (() async -> Void)?

    /// Callback before system sleep
    var onSystemWillSleep: (() async -> Void)?

    // IOKit power notification related
    var rootPort: io_connect_t = 0
    private var notifyPortRef: IONotificationPortRef?
    private var notifierObject: io_object_t = 0

    /// Start power monitoring
    func start() {
        logger.info("Starting power state monitoring...")

        rootPort = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &notifyPortRef,
            powerCallback,
            &notifierObject
        )

        guard rootPort != 0, let notifyPortRef = notifyPortRef else {
            logger.error("IORegisterForSystemPower failed")
            return
        }

        // Add notification port to RunLoop
        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPortRef).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        logger.info("Power state monitoring started")
    }

    /// Stop power monitoring
    func stop() {
        if notifierObject != 0 {
            IODeregisterForSystemPower(&notifierObject)
            notifierObject = 0
        }
        if let port = notifyPortRef {
            IONotificationPortDestroy(port)
            notifyPortRef = nil
        }
        rootPort = 0
        logger.info("Power state monitoring stopped")
    }

    /// Handle system will sleep
    func handleWillSleep(messageArgument: UnsafeMutableRawPointer?) {
        logger.info("System will sleep")

        Task {
            await onSystemWillSleep?()
        }

        // Must acknowledge the sleep request, otherwise the system delays sleep
        let messageArg = Int(bitPattern: messageArgument)
        IOAllowPowerChange(rootPort, messageArg)
    }

    /// Handle system did wake
    func handleDidWake() {
        logger.info("System woke up, will check FUSE mount status...")

        Task {
            // Give the system a moment to recover
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
            await onSystemWake?()
        }
    }

    deinit {
        stop()
    }
}

// MARK: - IOKit Power Callback (C function)

private func powerCallback(
    refCon: UnsafeMutableRawPointer?,
    service: io_service_t,
    messageType: UInt32,
    messageArgument: UnsafeMutableRawPointer?
) {
    guard let refCon = refCon else { return }
    let monitor = Unmanaged<ServicePowerMonitor>.fromOpaque(refCon).takeUnretainedValue()

    switch messageType {
    case kIOMessageCanSystemSleepValue:
        // System asks if it can sleep — allow
        IOAllowPowerChange(monitor.rootPort, Int(bitPattern: messageArgument))

    case kIOMessageSystemWillSleepValue:
        // System will sleep
        monitor.handleWillSleep(messageArgument: messageArgument)

    case kIOMessageSystemHasPoweredOnValue:
        // System has woken up
        monitor.handleDidWake()

    default:
        break
    }
}
