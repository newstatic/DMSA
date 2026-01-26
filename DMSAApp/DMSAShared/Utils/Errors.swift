import Foundation

// MARK: - DMSA 通用错误

/// DMSA 通用错误类型
public enum DMSAError: Error, LocalizedError {
    case vfsError(String)
    case syncError(String)
    case helperError(String)
    case configError(String)
    case databaseError(String)
    case xpcError(String)
    case permissionDenied(String)
    case fileNotFound(String)
    case serviceNotAvailable(String)
    case timeout
    case cancelled
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .vfsError(let msg):
            return "VFS 错误: \(msg)"
        case .syncError(let msg):
            return "同步错误: \(msg)"
        case .helperError(let msg):
            return "Helper 错误: \(msg)"
        case .configError(let msg):
            return "配置错误: \(msg)"
        case .databaseError(let msg):
            return "数据库错误: \(msg)"
        case .xpcError(let msg):
            return "XPC 通信错误: \(msg)"
        case .permissionDenied(let path):
            return "权限被拒绝: \(path)"
        case .fileNotFound(let path):
            return "文件不存在: \(path)"
        case .serviceNotAvailable(let service):
            return "服务不可用: \(service)"
        case .timeout:
            return "操作超时"
        case .cancelled:
            return "操作已取消"
        case .unknown(let msg):
            return "未知错误: \(msg)"
        }
    }
}

// MARK: - 同步错误

/// 同步错误
public enum SyncError: Error, LocalizedError {
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
    case serviceNotRunning

    public var errorDescription: String? {
        switch self {
        case .diskNotConnected(let name):
            return "硬盘未连接: \(name)"
        case .sourceNotFound(let path):
            return "源路径不存在: \(path)"
        case .fileNotFound(let path):
            return "文件不存在: \(path)"
        case .permissionDenied(let path):
            return "权限被拒绝: \(path)"
        case .insufficientSpace(let required, let available):
            return "空间不足: 需要 \(formatBytes(required))，可用 \(formatBytes(available))"
        case .syncFailed(let msg):
            return "同步失败: \(msg)"
        case .checksumMismatch(let expected, let actual):
            return "校验和不匹配: 期望 \(expected)，实际 \(actual)"
        case .verificationFailed(let path):
            return "验证失败: \(path)"
        case .symlinkCreationFailed(let path, let error):
            return "符号链接创建失败: \(path) - \(error)"
        case .configurationError(let msg):
            return "配置错误: \(msg)"
        case .databaseError(let msg):
            return "数据库错误: \(msg)"
        case .timeout:
            return "同步超时"
        case .cancelled:
            return "同步已取消"
        case .alreadyInProgress:
            return "同步已在进行中"
        case .renameLocalFailed(let path, let error):
            return "重命名失败: \(path) - \(error)"
        case .localBackupExists(let path):
            return "本地备份已存在: \(path)"
        case .fullDiskAccessRequired:
            return "需要完全磁盘访问权限"
        case .localDirectoryNotMigrated(let path):
            return "本地目录未迁移: \(path)"
        case .symlinkNotCreated(let path):
            return "符号链接未创建: \(path)"
        case .serviceNotRunning:
            return "同步服务未运行"
        }
    }
}

// MARK: - VFS 错误

/// VFS 错误
public enum VFSError: Error, LocalizedError {
    case fuseNotAvailable
    case fuseVersionTooOld(String)
    case mountFailed(String)
    case unmountFailed(String)
    case alreadyMounted(String)
    case notMounted(String)
    case invalidPath(String)
    case fileNotFound(String)
    case permissionDenied(String)
    case ioError(String)
    case indexError(String)
    case serviceNotRunning
    case externalOffline
    case conflictingPaths(String, String)  // TARGET_DIR 和 LOCAL_DIR 都存在

    public var errorDescription: String? {
        switch self {
        case .fuseNotAvailable:
            return "macFUSE 未安装"
        case .fuseVersionTooOld(let version):
            return "macFUSE 版本过旧: \(version)"
        case .mountFailed(let msg):
            return "挂载失败: \(msg)"
        case .unmountFailed(let msg):
            return "卸载失败: \(msg)"
        case .alreadyMounted(let path):
            return "已经挂载: \(path)"
        case .notMounted(let path):
            return "未挂载: \(path)"
        case .invalidPath(let path):
            return "无效路径: \(path)"
        case .fileNotFound(let path):
            return "文件不存在: \(path)"
        case .permissionDenied(let path):
            return "权限被拒绝: \(path)"
        case .ioError(let msg):
            return "IO 错误: \(msg)"
        case .indexError(let msg):
            return "索引错误: \(msg)"
        case .serviceNotRunning:
            return "VFS 服务未运行"
        case .externalOffline:
            return "外部存储离线"
        case .conflictingPaths(let target, let local):
            return "路径冲突: \(target) 和 \(local) 都存在，请手动处理"
        }
    }
}

// MARK: - 配置错误

/// 配置错误
public enum ConfigError: Error, LocalizedError {
    case fileNotFound
    case parseError(String)
    case validationError(String)
    case writeError(String)

    public var errorDescription: String? {
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

// MARK: - Helper 错误

/// Helper 错误
public enum HelperError: Error, LocalizedError {
    case notInstalled
    case installFailed(String)
    case connectionFailed(String)
    case operationFailed(String)
    case pathNotAllowed(String)
    case authorizationFailed

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Helper 服务未安装"
        case .installFailed(let msg):
            return "Helper 安装失败: \(msg)"
        case .connectionFailed(let msg):
            return "Helper 连接失败: \(msg)"
        case .operationFailed(let msg):
            return "Helper 操作失败: \(msg)"
        case .pathNotAllowed(let path):
            return "路径不允许操作: \(path)"
        case .authorizationFailed:
            return "授权失败"
        }
    }
}

// MARK: - 工具函数

/// 字节格式化
public func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
