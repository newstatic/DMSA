import Foundation

/// VFS 错误类型
enum VFSError: Error, LocalizedError {

    // === 文件操作错误 ===

    /// 文件不存在
    case fileNotFound(String)

    /// 权限不足
    case permissionDenied(String)

    /// 文件正在同步中（写入被阻塞）
    case fileBusy(String)

    /// 写入等待超时
    case writeTimeout(String)

    /// 读取失败
    case readFailed(String)

    /// 写入失败
    case writeFailed(String)

    /// 复制失败
    case copyFailed(String)

    /// 删除失败
    case deleteFailed(String)

    // === 空间错误 ===

    /// 空间不足
    case insufficientSpace

    /// 淘汰失败（无法释放足够空间）
    case evictionFailed

    // === 连接错误 ===

    /// 外置硬盘离线
    case externalOffline

    /// 挂载失败
    case mountFailed(String)

    // === 数据错误 ===

    /// 校验和不匹配
    case checksumMismatch

    /// 元数据损坏
    case metadataCorrupted

    /// 路径无效
    case invalidPath(String)

    // === 锁定错误 ===

    /// 获取锁失败
    case lockAcquisitionFailed(String)

    /// 锁已超时
    case lockTimeout(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "文件不存在: \(path)"
        case .permissionDenied(let path):
            return "权限不足: \(path)"
        case .fileBusy(let path):
            return "文件正在同步中: \(path)"
        case .writeTimeout(let path):
            return "写入等待超时: \(path)"
        case .readFailed(let msg):
            return "读取失败: \(msg)"
        case .writeFailed(let msg):
            return "写入失败: \(msg)"
        case .copyFailed(let msg):
            return "复制失败: \(msg)"
        case .deleteFailed(let msg):
            return "删除失败: \(msg)"
        case .insufficientSpace:
            return "本地缓存空间不足"
        case .evictionFailed:
            return "缓存淘汰失败，无法释放足够空间"
        case .externalOffline:
            return "外置硬盘未连接"
        case .mountFailed(let msg):
            return "挂载失败: \(msg)"
        case .checksumMismatch:
            return "文件校验失败，数据可能已损坏"
        case .metadataCorrupted:
            return "元数据损坏"
        case .invalidPath(let path):
            return "路径无效: \(path)"
        case .lockAcquisitionFailed(let path):
            return "获取文件锁失败: \(path)"
        case .lockTimeout(let path):
            return "文件锁超时: \(path)"
        }
    }

    /// 转换为 POSIX 错误码
    var posixErrorCode: Int32 {
        switch self {
        case .fileNotFound:
            return ENOENT      // 2: No such file or directory
        case .permissionDenied:
            return EACCES      // 13: Permission denied
        case .fileBusy, .writeTimeout:
            return EBUSY       // 16: Device or resource busy
        case .insufficientSpace, .evictionFailed:
            return ENOSPC      // 28: No space left on device
        case .externalOffline:
            return ENODEV      // 19: No such device
        case .checksumMismatch, .metadataCorrupted:
            return EIO         // 5: I/O error
        case .invalidPath:
            return EINVAL      // 22: Invalid argument
        case .lockAcquisitionFailed, .lockTimeout:
            return EAGAIN      // 35: Resource temporarily unavailable
        default:
            return EIO         // 5: I/O error
        }
    }

    /// 是否可重试
    var isRetryable: Bool {
        switch self {
        case .fileBusy, .writeTimeout, .lockAcquisitionFailed, .lockTimeout:
            return true
        case .externalOffline:
            return true  // 等待硬盘重新连接
        case .insufficientSpace:
            return true  // 可以尝试淘汰后重试
        default:
            return false
        }
    }

    /// 建议的重试延迟（秒）
    var suggestedRetryDelay: TimeInterval {
        switch self {
        case .fileBusy, .writeTimeout, .lockAcquisitionFailed, .lockTimeout:
            return 1.0
        case .externalOffline:
            return 5.0
        case .insufficientSpace:
            return 2.0
        default:
            return 0
        }
    }
}
