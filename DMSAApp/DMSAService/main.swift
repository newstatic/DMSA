import Foundation

// MARK: - DMSAService 入口点
// 统一后台服务，合并 VFS + Sync + Helper 功能
// 作为 LaunchDaemon 以 root 权限运行

let logger = Logger.forService("DMSAService")

logger.info("========================================")
logger.info("DMSAService v\(Constants.appVersion) 启动")
logger.info("PID: \(ProcessInfo.processInfo.processIdentifier)")
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

// 5. 启动后台任务
Task {
    // 自动挂载 VFS
    await delegate.autoMount()

    // 启动同步调度器
    await delegate.startScheduler()
}

// 6. 运行主事件循环
logger.info("DMSAService 就绪，等待连接...")
RunLoop.main.run()
