import Foundation

/// Error code definitions
/// Grouped by functional module, each module occupies 1000 error codes
struct ErrorCodes {

    // MARK: - Connection Errors (1xxx)

    /// Connection failed
    static let connectionFailed = 1001
    /// Connection interrupted
    static let connectionInterrupted = 1002
    /// Connection timeout
    static let connectionTimeout = 1003
    /// Connection refused
    static let connectionRefused = 1004
    /// Service unavailable
    static let serviceUnavailable = 1005
    /// Version incompatible
    static let versionIncompatible = 1006

    // MARK: - Sync Errors (2xxx)

    /// Sync failed
    static let syncFailed = 2001
    /// Sync conflict
    static let syncConflict = 2002
    /// Sync timeout
    static let syncTimeout = 2003
    /// Sync cancelled
    static let syncCancelled = 2004
    /// Sync paused
    static let syncPaused = 2005
    /// Sync path not found
    static let syncPathNotFound = 2006
    /// Sync permission denied
    static let syncPermissionDenied = 2007

    // MARK: - Config Errors (3xxx)

    /// Config invalid
    static let configInvalid = 3001
    /// Config save failed
    static let configSaveFailed = 3002
    /// Config load failed
    static let configLoadFailed = 3003
    /// Config missing
    static let configMissing = 3004
    /// Config format error
    static let configFormatError = 3005

    // MARK: - Disk Errors (4xxx)

    /// Disk not found
    static let diskNotFound = 4001
    /// Disk access denied
    static let diskAccessDenied = 4002
    /// Disk full
    static let diskFull = 4003
    /// Disk read-only
    static let diskReadOnly = 4004
    /// Disk disconnected
    static let diskDisconnected = 4005
    /// Disk format not supported
    static let diskUnsupportedFormat = 4006

    // MARK: - Permission Errors (5xxx)

    /// Permission denied
    static let permissionDenied = 5001
    /// Service not authorized
    static let serviceNotAuthorized = 5002
    /// TCC permission missing
    static let tccPermissionMissing = 5003
    /// Admin required
    static let adminRequired = 5004

    // MARK: - Component Errors (6xxx)

    /// Component error (generic)
    static let componentError = 6001
    /// VFS component error
    static let vfsError = 6002
    /// Sync engine error
    static let syncEngineError = 6003
    /// Database error
    static let databaseError = 6004
    /// Monitor component error
    static let monitorError = 6005

    // MARK: - VFS Errors (7xxx)

    /// VFS mount failed
    static let vfsMountFailed = 7001
    /// VFS unmount failed
    static let vfsUnmountFailed = 7002
    /// VFS invalid path
    static let vfsInvalidPath = 7003
    /// macFUSE not installed
    static let macFUSENotInstalled = 7004
    /// macFUSE version too old
    static let macFUSEVersionTooOld = 7005

    // MARK: - File Errors (8xxx)

    /// File not found
    static let fileNotFound = 8001
    /// File already exists
    static let fileAlreadyExists = 8002
    /// File access denied
    static let fileAccessDenied = 8003
    /// File locked
    static let fileLocked = 8004
    /// File checksum mismatch
    static let fileChecksumMismatch = 8005
    /// File too large
    static let fileTooLarge = 8006

    // MARK: - Helper Methods

    /// Get module for error code
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

    /// Whether error code is critical
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

    /// Whether error code is recoverable
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

    /// Get default message for error code
    static func defaultMessage(for code: Int) -> String {
        switch code {
        // Connection errors
        case connectionFailed: return "error.connection.failed".localized
        case connectionInterrupted: return "error.connection.interrupted".localized
        case connectionTimeout: return "error.connection.timeout".localized
        case connectionRefused: return "error.connection.refused".localized
        case serviceUnavailable: return "error.service.unavailable".localized
        case versionIncompatible: return "error.version.incompatible".localized

        // Sync errors
        case syncFailed: return "error.sync.failed".localized
        case syncConflict: return "error.sync.conflict".localized
        case syncTimeout: return "error.sync.timeout".localized
        case syncCancelled: return "error.sync.cancelled".localized
        case syncPathNotFound: return "error.sync.path.notfound".localized
        case syncPermissionDenied: return "error.sync.permission.denied".localized

        // Config errors
        case configInvalid: return "error.config.invalid".localized
        case configSaveFailed: return "error.config.save.failed".localized
        case configLoadFailed: return "error.config.load.failed".localized

        // Disk errors
        case diskNotFound: return "error.disk.notfound".localized
        case diskAccessDenied: return "error.disk.access.denied".localized
        case diskFull: return "error.disk.full".localized
        case diskDisconnected: return "error.disk.disconnected".localized

        // Permission errors
        case permissionDenied: return "error.permission.denied".localized
        case serviceNotAuthorized: return "error.service.notauthorized".localized
        case tccPermissionMissing: return "error.tcc.missing".localized

        // VFS errors
        case vfsMountFailed: return "error.vfs.mount.failed".localized
        case vfsUnmountFailed: return "error.vfs.unmount.failed".localized
        case macFUSENotInstalled: return "error.macfuse.notinstalled".localized
        case macFUSEVersionTooOld: return "error.macfuse.outdated".localized

        // File errors
        case fileNotFound: return "error.file.notfound".localized
        case fileAlreadyExists: return "error.file.exists".localized
        case fileAccessDenied: return "error.file.access.denied".localized
        case fileChecksumMismatch: return "error.file.checksum".localized

        default: return "error.unknown".localized
        }
    }
}
