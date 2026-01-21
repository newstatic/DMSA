import Foundation

/// 同步错误
enum SyncError: Error, LocalizedError {
    case diskNotConnected(String)
    case sourceNotFound(String)
    case fileNotFound(path: String)
    case permissionDenied(path: String)
    case insufficientSpace(required: Int64, available: Int64)
    case rsyncNotFound
    case rsyncFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case symlinkCreationFailed(path: String, error: String)
    case configurationError(String)
    case databaseError(String)
    case timeout
    case cancelled
    case alreadyInProgress

    var errorDescription: String? {
        switch self {
        case .diskNotConnected(let name):
            return "外置硬盘 \(name) 未连接"
        case .sourceNotFound(let path):
            return "源目录不存在: \(path)"
        case .fileNotFound(let path):
            return "文件不存在: \(path)"
        case .permissionDenied(let path):
            return "权限不足: \(path)"
        case .insufficientSpace(let required, let available):
            return "空间不足: 需要 \(formatBytes(required)), 可用 \(formatBytes(available))"
        case .rsyncNotFound:
            return "rsync 未找到"
        case .rsyncFailed(let msg):
            return "同步失败: \(msg)"
        case .checksumMismatch(let expected, let actual):
            return "文件校验失败: 期望 \(expected), 实际 \(actual)"
        case .symlinkCreationFailed(let path, let error):
            return "创建符号链接失败 \(path): \(error)"
        case .configurationError(let msg):
            return "配置错误: \(msg)"
        case .databaseError(let msg):
            return "数据库错误: \(msg)"
        case .timeout:
            return "操作超时"
        case .cancelled:
            return "操作已取消"
        case .alreadyInProgress:
            return "同步任务已在进行中"
        }
    }
}

/// 配置错误
enum ConfigError: Error, LocalizedError {
    case fileNotFound
    case parseError(String)
    case validationError(String)
    case writeError(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "配置文件不存在"
        case .parseError(let msg):
            return "配置解析错误: \(msg)"
        case .validationError(let msg):
            return "配置校验错误: \(msg)"
        case .writeError(let msg):
            return "配置写入错误: \(msg)"
        }
    }
}

/// 字节格式化
func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
