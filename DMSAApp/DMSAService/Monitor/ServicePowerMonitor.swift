import Foundation
import IOKit
import IOKit.pwr_mgt

// IOKit 电源消息常量
private let kIOMessageCanSystemSleepValue: UInt32 = 0xe0000270
private let kIOMessageSystemWillSleepValue: UInt32 = 0xe0000280
private let kIOMessageSystemHasPoweredOnValue: UInt32 = 0xe0000300

/// Service 端电源状态监控器
/// 监听系统休眠/唤醒事件，在唤醒后检查并恢复 FUSE 挂载
final class ServicePowerMonitor {

    private let logger = Logger.forService("Power")

    /// 唤醒后的回调
    var onSystemWake: (() async -> Void)?

    /// 即将休眠的回调
    var onSystemWillSleep: (() async -> Void)?

    // IOKit 电源通知相关
    var rootPort: io_connect_t = 0
    private var notifyPortRef: IONotificationPortRef?
    private var notifierObject: io_object_t = 0

    /// 启动电源监控
    func start() {
        logger.info("启动电源状态监控...")

        rootPort = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &notifyPortRef,
            powerCallback,
            &notifierObject
        )

        guard rootPort != 0, let notifyPortRef = notifyPortRef else {
            logger.error("IORegisterForSystemPower 失败")
            return
        }

        // 将通知端口添加到 RunLoop
        let runLoopSource = IONotificationPortGetRunLoopSource(notifyPortRef).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        logger.info("电源状态监控已启动")
    }

    /// 停止电源监控
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
        logger.info("电源状态监控已停止")
    }

    /// 处理系统即将休眠
    func handleWillSleep(messageArgument: UnsafeMutableRawPointer?) {
        logger.info("系统即将休眠")

        Task {
            await onSystemWillSleep?()
        }

        // 必须确认休眠请求，否则系统会延迟休眠
        let messageArg = Int(bitPattern: messageArgument)
        IOAllowPowerChange(rootPort, messageArg)
    }

    /// 处理系统唤醒
    func handleDidWake() {
        logger.info("系统已唤醒，将检查 FUSE 挂载状态...")

        Task {
            // 给系统一点时间恢复
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 秒
            await onSystemWake?()
        }
    }

    deinit {
        stop()
    }
}

// MARK: - IOKit 电源回调 (C 函数)

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
        // 系统询问是否可以休眠 — 允许
        IOAllowPowerChange(monitor.rootPort, Int(bitPattern: messageArgument))

    case kIOMessageSystemWillSleepValue:
        // 系统即将休眠
        monitor.handleWillSleep(messageArgument: messageArgument)

    case kIOMessageSystemHasPoweredOnValue:
        // 系统已唤醒
        monitor.handleDidWake()

    default:
        break
    }
}
