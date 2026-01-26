import Foundation

// MARK: - DMSAService 入口点
// 统一后台服务，合并 VFS + Sync + Helper 功能
// 作为 LaunchDaemon 以 root 权限运行

// ============================================================
// 重要: macFUSE fork 兼容性设置
// ============================================================
// macFUSE 的 mount 内部会调用 fork() 创建子进程
// 在多线程环境下，如果子进程尝试初始化 Objective-C 类，会触发:
// "*** multi-threaded process forked ***" 崩溃
//
// 解决方案:
// 1. 设置 OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES (部分缓解)
// 2. 在任何多线程操作之前，预先加载 macFUSE framework
// 3. 预初始化所有可能用到的 Objective-C 类
// ============================================================

// 必须在任何代码执行之前设置
setenv("OBJC_DISABLE_INITIALIZE_FORK_SAFETY", "YES", 1)

// 预加载 macFUSE framework (在创建任何线程之前)
_ = {
    // 加载 macFUSE framework
    if let bundle = Bundle(path: "/Library/Frameworks/macFUSE.framework") {
        try? bundle.loadAndReturnError()
    }

    // 预初始化关键类
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

    // 预初始化 GMUserFileSystem 类
    if let gmClass = NSClassFromString("GMUserFileSystem") {
        _ = gmClass.description()
    }
}()

let logger = Logger.forService("DMSAService")

logger.info("========================================")
logger.info("DMSAService v\(Constants.appVersion) 启动")
logger.info("PID: \(ProcessInfo.processInfo.processIdentifier)")
logger.info("构建时间: \(Date())")  // 编译时记录启动时间，用于验证版本
logger.info("========================================")

// MARK: - 目录设置

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
                logger.info("创建目录: \(path)")
            } catch {
                logger.error("创建目录失败: \(path) - \(error)")
            }
        }
    }
}

// MARK: - 信号处理

func setupSignalHandlers() {
    // SIGTERM: 优雅关闭
    signal(SIGTERM) { _ in
        logger.info("收到 SIGTERM，准备关闭...")
        Task {
            await ServiceDelegate.shared?.prepareForShutdown()
            logger.info("DMSAService 已安全关闭")
            exit(0)
        }
    }

    // SIGHUP: 重新加载配置
    signal(SIGHUP) { _ in
        logger.info("收到 SIGHUP，重新加载配置...")
        Task {
            await ServiceDelegate.shared?.reloadConfiguration()
        }
    }

    // SIGINT: 中断 (调试用)
    signal(SIGINT) { _ in
        logger.info("收到 SIGINT，准备关闭...")
        Task {
            await ServiceDelegate.shared?.prepareForShutdown()
            logger.info("DMSAService 已安全关闭")
            exit(0)
        }
    }
}

// MARK: - 主流程

// 1. 设置目录
setupDirectories()

// 2. 设置信号处理
setupSignalHandlers()

// 3. 创建服务委托
let delegate = ServiceDelegate()

// 4. 创建 XPC 监听器
let listener = NSXPCListener(machServiceName: Constants.XPCService.service)
listener.delegate = delegate
listener.resume()

logger.info("XPC 监听器已启动: \(Constants.XPCService.service)")

// ============================================================
// FUSE 挂载策略
// ============================================================
// macFUSE 在 mount 时会调用 fork()。在多线程环境下 fork 后的
// 子进程初始化 Objective-C 类时可能崩溃。
//
// 缓解措施:
// 1. 设置 OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES (已在 plist 和上面设置)
// 2. 预初始化关键的 Objective-C 类 (已在上面完成)
// 3. 延迟一小段时间让进程稳定后再挂载
// ============================================================

// 5. 启动后台任务
Task {
    // 短暂延迟，让进程初始化完成
    try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 秒

    // 自动挂载 VFS
    await delegate.autoMount()

    // 启动同步调度器
    await delegate.startScheduler()
}

// 6. 运行主事件循环
logger.info("DMSAService 就绪，等待连接...")
RunLoop.main.run()
