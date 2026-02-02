import Foundation

// MARK: - DMSA Common Errors

/// DMSA common error type
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
            return "VFS error: \(msg)"
        case .syncError(let msg):
            return "Sync error: \(msg)"
        case .helperError(let msg):
            return "Helper error: \(msg)"
        case .configError(let msg):
            return "Config error: \(msg)"
        case .databaseError(let msg):
            return "Database error: \(msg)"
        case .xpcError(let msg):
            return "XPC communication error: \(msg)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .serviceNotAvailable(let service):
            return "Service unavailable: \(service)"
        case .timeout:
            return "Operation timed out"
        case .cancelled:
            return "Operation cancelled"
        case .unknown(let msg):
            return "Unknown error: \(msg)"
        }
    }
}

// MARK: - Sync Errors

/// Sync error
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
            return "Disk not connected: \(name)"
        case .sourceNotFound(let path):
            return "Source path not found: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .insufficientSpace(let required, let available):
            return "Insufficient space: requires \(formatBytes(required)), available \(formatBytes(available))"
        case .syncFailed(let msg):
            return "Sync failed: \(msg)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch: expected \(expected), actual \(actual)"
        case .verificationFailed(let path):
            return "Verification failed: \(path)"
        case .symlinkCreationFailed(let path, let error):
            return "Symlink creation failed: \(path) - \(error)"
        case .configurationError(let msg):
            return "Configuration error: \(msg)"
        case .databaseError(let msg):
            return "Database error: \(msg)"
        case .timeout:
            return "Sync timed out"
        case .cancelled:
            return "Sync cancelled"
        case .alreadyInProgress:
            return "Sync already in progress"
        case .renameLocalFailed(let path, let error):
            return "Rename failed: \(path) - \(error)"
        case .localBackupExists(let path):
            return "Local backup already exists: \(path)"
        case .fullDiskAccessRequired:
            return "Full disk access required"
        case .localDirectoryNotMigrated(let path):
            return "Local directory not migrated: \(path)"
        case .symlinkNotCreated(let path):
            return "Symlink not created: \(path)"
        case .serviceNotRunning:
            return "Sync service not running"
        }
    }
}

// MARK: - VFS Errors

/// VFS error
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
    case conflictingPaths(String, String)  // Both TARGET_DIR and LOCAL_DIR exist

    public var errorDescription: String? {
        switch self {
        case .fuseNotAvailable:
            return "macFUSE not installed"
        case .fuseVersionTooOld(let version):
            return "macFUSE version too old: \(version)"
        case .mountFailed(let msg):
            return "Mount failed: \(msg)"
        case .unmountFailed(let msg):
            return "Unmount failed: \(msg)"
        case .alreadyMounted(let path):
            return "Already mounted: \(path)"
        case .notMounted(let path):
            return "Not mounted: \(path)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .ioError(let msg):
            return "IO error: \(msg)"
        case .indexError(let msg):
            return "Index error: \(msg)"
        case .serviceNotRunning:
            return "VFS service not running"
        case .externalOffline:
            return "External storage offline"
        case .conflictingPaths(let target, let local):
            return "Path conflict: both \(target) and \(local) exist, please resolve manually"
        }
    }
}

// MARK: - Config Errors

/// Config error
public enum ConfigError: Error, LocalizedError {
    case fileNotFound
    case parseError(String)
    case validationError(String)
    case writeError(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Config file not found"
        case .parseError(let msg):
            return "Config parse error: \(msg)"
        case .validationError(let msg):
            return "Config validation error: \(msg)"
        case .writeError(let msg):
            return "Config write error: \(msg)"
        }
    }
}

// MARK: - Helper Errors

/// Helper error
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
            return "Helper service not installed"
        case .installFailed(let msg):
            return "Helper installation failed: \(msg)"
        case .connectionFailed(let msg):
            return "Helper connection failed: \(msg)"
        case .operationFailed(let msg):
            return "Helper operation failed: \(msg)"
        case .pathNotAllowed(let path):
            return "Path not allowed: \(path)"
        case .authorizationFailed:
            return "Authorization failed"
        }
    }
}

// MARK: - Utility Functions

/// Byte formatting
public func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
