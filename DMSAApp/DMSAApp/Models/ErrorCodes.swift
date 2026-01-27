import Foundation

/// 错误码定义
/// 按功能模块分组，每个模块占用 1000 个错误码
struct ErrorCodes {

    // MARK: - 连接错误 (1xxx)

    /// 连接失败
    static let connectionFailed = 1001
    /// 连接中断
    static let connectionInterrupted = 1002
    /// 连接超时
    static let connectionTimeout = 1003
    /// 连接被拒绝
    static let connectionRefused = 1004
    /// 服务不可用
    static let serviceUnavailable = 1005
    /// 版本不兼容
    static let versionIncompatible = 1006

    // MARK: - 同步错误 (2xxx)

    /// 同步失败
    static let syncFailed = 2001
    /// 同步冲突
    static let syncConflict = 2002
    /// 同步超时
    static let syncTimeout = 2003
    /// 同步已取消
    static let syncCancelled = 2004
    /// 同步暂停
    static let syncPaused = 2005
    /// 同步路径不存在
    static let syncPathNotFound = 2006
    /// 同步权限不足
    static let syncPermissionDenied = 2007

    // MARK: - 配置错误 (3xxx)

    /// 配置无效
    static let configInvalid = 3001
    /// 配置保存失败
    static let configSaveFailed = 3002
    /// 配置加载失败
    static let configLoadFailed = 3003
    /// 配置项缺失
    static let configMissing = 3004
    /// 配置格式错误
    static let configFormatError = 3005

    // MARK: - 磁盘错误 (4xxx)

    /// 磁盘未找到
    static let diskNotFound = 4001
    /// 磁盘访问被拒绝
    static let diskAccessDenied = 4002
    /// 磁盘已满
    static let diskFull = 4003
    /// 磁盘只读
    static let diskReadOnly = 4004
    /// 磁盘已断开
    static let diskDisconnected = 4005
    /// 磁盘格式不支持
    static let diskUnsupportedFormat = 4006

    // MARK: - 权限错误 (5xxx)

    /// 权限被拒绝
    static let permissionDenied = 5001
    /// 服务未授权
    static let serviceNotAuthorized = 5002
    /// TCC 权限缺失
    static let tccPermissionMissing = 5003
    /// 需要管理员权限
    static let adminRequired = 5004

    // MARK: - 组件错误 (6xxx)

    /// 组件错误 (通用)
    static let componentError = 6001
    /// VFS 组件错误
    static let vfsError = 6002
    /// 同步引擎错误
    static let syncEngineError = 6003
    /// 数据库错误
    static let databaseError = 6004
    /// 监控组件错误
    static let monitorError = 6005

    // MARK: - VFS 错误 (7xxx)

    /// VFS 挂载失败
    static let vfsMountFailed = 7001
    /// VFS 卸载失败
    static let vfsUnmountFailed = 7002
    /// VFS 路径无效
    static let vfsInvalidPath = 7003
    /// macFUSE 未安装
    static let macFUSENotInstalled = 7004
    /// macFUSE 版本过低
    static let macFUSEVersionTooOld = 7005

    // MARK: - 文件错误 (8xxx)

    /// 文件未找到
    static let fileNotFound = 8001
    /// 文件已存在
    static let fileAlreadyExists = 8002
    /// 文件访问被拒绝
    static let fileAccessDenied = 8003
    /// 文件已锁定
    static let fileLocked = 8004
    /// 文件校验失败
    static let fileChecksumMismatch = 8005
    /// 文件太大
    static let fileTooLarge = 8006

    // MARK: - 辅助方法

    /// 获取错误码所属模块
    static func module(for code: Int) -> String {
        switch code {
        case 1000..<2000: return "connection"
        case 2000..<3000: return "sync"
        case 3000..<4000: return "config"
        case 4000..<5000: return "disk"
        case 5000..<6000: return "permission"
        case 6000..<7000: return "component"
        case 7000..<8000: return "vfs"
        case 8000..<9000: return "file"
        default: return "unknown"
        }
    }

    /// 错误码是否为严重错误
    static func isCritical(_ code: Int) -> Bool {
        switch code {
        case connectionFailed,
             serviceUnavailable,
             versionIncompatible,
             vfsMountFailed,
             macFUSENotInstalled,
             serviceNotAuthorized:
            return true
        default:
            return false
        }
    }

    /// 错误码是否可恢复
    static func isRecoverable(_ code: Int) -> Bool {
        switch code {
        case connectionInterrupted,
             connectionTimeout,
             syncTimeout,
             syncPaused,
             diskDisconnected:
            return true
        default:
            return false
        }
    }

    /// 获取错误码的默认消息
    static func defaultMessage(for code: Int) -> String {
        switch code {
        // 连接错误
        case connectionFailed: return "error.connection.failed".localized
        case connectionInterrupted: return "error.connection.interrupted".localized
        case connectionTimeout: return "error.connection.timeout".localized
        case connectionRefused: return "error.connection.refused".localized
        case serviceUnavailable: return "error.service.unavailable".localized
        case versionIncompatible: return "error.version.incompatible".localized

        // 同步错误
        case syncFailed: return "error.sync.failed".localized
        case syncConflict: return "error.sync.conflict".localized
        case syncTimeout: return "error.sync.timeout".localized
        case syncCancelled: return "error.sync.cancelled".localized
        case syncPathNotFound: return "error.sync.path.notfound".localized
        case syncPermissionDenied: return "error.sync.permission.denied".localized

        // 配置错误
        case configInvalid: return "error.config.invalid".localized
        case configSaveFailed: return "error.config.save.failed".localized
        case configLoadFailed: return "error.config.load.failed".localized

        // 磁盘错误
        case diskNotFound: return "error.disk.notfound".localized
        case diskAccessDenied: return "error.disk.access.denied".localized
        case diskFull: return "error.disk.full".localized
        case diskDisconnected: return "error.disk.disconnected".localized

        // 权限错误
        case permissionDenied: return "error.permission.denied".localized
        case serviceNotAuthorized: return "error.service.notauthorized".localized
        case tccPermissionMissing: return "error.tcc.missing".localized

        // VFS 错误
        case vfsMountFailed: return "error.vfs.mount.failed".localized
        case vfsUnmountFailed: return "error.vfs.unmount.failed".localized
        case macFUSENotInstalled: return "error.macfuse.notinstalled".localized
        case macFUSEVersionTooOld: return "error.macfuse.outdated".localized

        // 文件错误
        case fileNotFound: return "error.file.notfound".localized
        case fileAlreadyExists: return "error.file.exists".localized
        case fileAccessDenied: return "error.file.access.denied".localized
        case fileChecksumMismatch: return "error.file.checksum".localized

        default: return "error.unknown".localized
        }
    }
}
