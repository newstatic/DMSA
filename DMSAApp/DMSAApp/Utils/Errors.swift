import Foundation

/// Sync error
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

/// Config error
enum ConfigError: Error, LocalizedError {
    case fileNotFound
    case parseError(String)
    case validationError(String)
    case writeError(String)

    var errorDescription: String? {
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

/// Byte formatter
func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

/// General DMSA error
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
            return "XPC connection failed: \(service)"
        case .xpcCallFailed(let message):
            return "XPC call failed: \(message)"
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        case .invalidResponse:
            return "Invalid response"
        case .timeout:
            return "Operation timed out"
        case .notFound(let item):
            return "Not found: \(item)"
        case .permissionDenied:
            return "Permission denied"
        case .serviceNotAvailable(let service):
            return "Service unavailable: \(service)"
        case .vfsError(let message):
            return "VFS error: \(message)"
        case .syncError(let message):
            return "Sync error: \(message)"
        }
    }
}
