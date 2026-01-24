import Foundation

/// Sync Service 入口点
/// 作为 LaunchDaemon 运行，提供文件同步服务

// 初始化日志
let syncLogger = Logger.forService("Sync")
syncLogger.info("========================================")
syncLogger.info("Sync Service v\(Constants.version) 启动")
syncLogger.info("PID: \(ProcessInfo.processInfo.processIdentifier)")
syncLogger.info("========================================")

// 确保必要目录存在
func setupSyncDirectories() {
    let fm = FileManager.default

    let dirs = [
        Constants.Paths.appSupport,
        Constants.Paths.sharedData,
        Constants.Paths.database,
        Constants.Paths.logs
    ]

    for dir in dirs {
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                syncLogger.info("创建目录: \(dir.path)")
            } catch {
                syncLogger.error("创建目录失败: \(dir.path) - \(error)")
            }
        }
    }
}

func setupSyncSignalHandlers(delegate: SyncServiceDelegate) {
    // SIGTERM - 优雅关闭
    signal(SIGTERM) { _ in
        Logger.forService("Sync").info("收到 SIGTERM，准备关闭...")
        Task {
            await SyncServiceDelegate.shared?.prepareForShutdown()
            exit(0)
        }
    }

    // SIGHUP - 重新加载配置
    signal(SIGHUP) { _ in
        Logger.forService("Sync").info("收到 SIGHUP，重新加载配置...")
        Task {
            await SyncServiceDelegate.shared?.reloadConfiguration()
        }
    }
}

setupSyncDirectories()

// 创建服务委托
let syncDelegate = SyncServiceDelegate()

// 创建 XPC 监听器
let syncListener = NSXPCListener(machServiceName: Constants.XPCService.sync)
syncListener.delegate = syncDelegate
syncListener.resume()

syncLogger.info("XPC 监听器已启动: \(Constants.XPCService.sync)")

// 启动服务
Task {
    await syncDelegate.start()
}

// 设置信号处理
setupSyncSignalHandlers(delegate: syncDelegate)

syncLogger.info("Sync Service 已就绪，等待请求...")

// 运行主循环
RunLoop.main.run()
