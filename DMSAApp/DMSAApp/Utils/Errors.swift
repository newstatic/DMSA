import Foundation

/// 同步错误
enum SyncError: Error, LocalizedError {
    case diskNotConnected(String)
    case sourceNotFound(String)
    case fileNotFound(path: String)
    case permissionDenied(path: String)
    case insufficientSpace(required: Int64, available: Int64)
    case syncFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case verificationFailed(path: String)
    case symlinkCreationFailed(String, String)
    case configurationError(String)
    case databaseError(String)
    case timeout
    case cancelled
    case alreadyInProgress
    case renameLocalFailed(String, String)
    case localBackupExists(String)
    case fullDiskAccessRequired
    case localDirectoryNotMigrated(String)
    case symlinkNotCreated(String)

    var errorDescription: String? {
        switch self {
        case .diskNotConnected(let name):
            return "error.diskNotConnected".localized(with: name)
        case .sourceNotFound(let path):
            return "error.sourceNotFound".localized(with: path)
        case .fileNotFound(let path):
            return "error.fileNotFound".localized(with: path)
        case .permissionDenied(let path):
            return "error.permissionDenied".localized(with: path)
        case .insufficientSpace(let required, let available):
            return "error.insufficientSpace".localized(with: formatBytes(required), formatBytes(available))
        case .syncFailed(let msg):
            return "error.syncFailed".localized(with: msg)
        case .checksumMismatch(let expected, let actual):
            return "error.checksumMismatch".localized(with: expected, actual)
        case .verificationFailed(let path):
            return "error.verificationFailed".localized(with: path)
        case .symlinkCreationFailed(let path, let error):
            return "error.symlinkCreationFailed".localized(with: path, error)
        case .configurationError(let msg):
            return "error.configurationError".localized(with: msg)
        case .databaseError(let msg):
            return "error.databaseError".localized(with: msg)
        case .timeout:
            return "error.timeout".localized
        case .cancelled:
            return "error.cancelled".localized
        case .alreadyInProgress:
            return "error.alreadyInProgress".localized
        case .renameLocalFailed(let path, let error):
            return "error.renameLocalFailed".localized(with: path, error)
        case .localBackupExists(let path):
            return "error.localBackupExists".localized(with: path)
        case .fullDiskAccessRequired:
            return "error.fullDiskAccessRequired".localized
        case .localDirectoryNotMigrated(let path):
            return "error.localDirectoryNotMigrated".localized(with: path)
        case .symlinkNotCreated(let path):
            return "error.symlinkNotCreated".localized(with: path)
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

/// 通用 DMSA 错误
enum DMSAError: Error, LocalizedError {
    case xpcConnectionFailed(String)
    case xpcCallFailed(String)
    case operationFailed(String)
    case invalidResponse
    case timeout
    case notFound(String)
    case permissionDenied
    case serviceNotAvailable(String)
    case vfsError(String)
    case syncError(String)

    var errorDescription: String? {
        switch self {
        case .xpcConnectionFailed(let service):
            return "XPC 连接失败: \(service)"
        case .xpcCallFailed(let message):
            return "XPC 调用失败: \(message)"
        case .operationFailed(let message):
            return "操作失败: \(message)"
        case .invalidResponse:
            return "无效响应"
        case .timeout:
            return "操作超时"
        case .notFound(let item):
            return "未找到: \(item)"
        case .permissionDenied:
            return "权限被拒绝"
        case .serviceNotAvailable(let service):
            return "服务不可用: \(service)"
        case .vfsError(let message):
            return "VFS 错误: \(message)"
        case .syncError(let message):
            return "同步错误: \(message)"
        }
    }
}
