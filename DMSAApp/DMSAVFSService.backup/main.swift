import Foundation

/// VFS Service 入口点
/// 作为 LaunchDaemon 运行，提供虚拟文件系统服务

// 初始化日志
let vfsLogger = Logger.forService("VFS")
vfsLogger.info("========================================")
vfsLogger.info("VFS Service v\(Constants.version) 启动")
vfsLogger.info("PID: \(ProcessInfo.processInfo.processIdentifier)")
vfsLogger.info("========================================")

// 确保必要目录存在
func setupVFSDirectories() {
    let fm = FileManager.default

    // 确保应用支持目录存在
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
                vfsLogger.info("创建目录: \(dir.path)")
            } catch {
                vfsLogger.error("创建目录失败: \(dir.path) - \(error)")
            }
        }
    }
}

func setupVFSSignalHandlers(delegate: VFSServiceDelegate) {
    // SIGTERM - 优雅关闭
    signal(SIGTERM) { _ in
        Logger.forService("VFS").info("收到 SIGTERM，准备关闭...")
        Task {
            await VFSServiceDelegate.shared?.prepareForShutdown()
            exit(0)
        }
    }

    // SIGHUP - 重新加载配置
    signal(SIGHUP) { _ in
        Logger.forService("VFS").info("收到 SIGHUP，重新加载配置...")
        Task {
            await VFSServiceDelegate.shared?.reloadConfiguration()
        }
    }
}

setupVFSDirectories()

// 创建 XPC 监听器
let vfsDelegate = VFSServiceDelegate()
let vfsListener = NSXPCListener(machServiceName: Constants.XPCService.vfs)
vfsListener.delegate = vfsDelegate
vfsListener.resume()

vfsLogger.info("XPC 监听器已启动: \(Constants.XPCService.vfs)")

// 加载配置并自动挂载
Task {
    await vfsDelegate.autoMount()
}

// 设置信号处理
setupVFSSignalHandlers(delegate: vfsDelegate)

vfsLogger.info("VFS Service 已就绪，等待请求...")

// 运行主循环
RunLoop.main.run()
