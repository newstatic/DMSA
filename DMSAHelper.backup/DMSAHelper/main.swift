import Foundation

/// DMSA 特权助手入口点
/// 作为 LaunchDaemon 运行，监听来自主应用的 XPC 连接

// 初始化日志
let startupMessage = """
=====================================
DMSAHelper v\(kDMSAHelperProtocolVersion)
Started at: \(ISO8601DateFormatter().string(from: Date()))
PID: \(ProcessInfo.processInfo.processIdentifier)
=====================================
"""
fputs(startupMessage + "\n", stderr)

// 创建 Helper 实例
let helperTool = HelperTool()

// 创建 XPC 监听器
let listener = NSXPCListener(machServiceName: kDMSAHelperMachServiceName)
listener.delegate = helperTool

// 开始监听
listener.resume()

fputs("DMSAHelper: Listening on \(kDMSAHelperMachServiceName)\n", stderr)

// 保持运行
RunLoop.main.run()
