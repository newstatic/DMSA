import Foundation

/// Path security validator
/// Prevents path traversal attacks and unauthorized file system access
struct PathValidator {

    // MARK: - Configuration

    /// Allowed root paths (whitelist)
    private static var allowedRoots: [String] {
        let home = NSHomeDirectory()
        return [
            home + "/Downloads_Local",
            home + "/Downloads",
            home + "/Documents_Local",
            home + "/Documents",
            home + "/Desktop_Local",
            home + "/Desktop",
            home + "/Pictures_Local",
            home + "/Pictures",
            home + "/Movies_Local",
            home + "/Movies",
            home + "/Music_Local",
            home + "/Music",
            home + "/Projects_Local",
            home + "/Projects",
            "/Volumes/"
        ]
    }

    /// Dangerous path patterns (blacklist)
    private static let dangerousPatterns = [
        "../",           // Path traversal
        "/etc/",         // System config
        "/private/",     // System private directory
        "/System/",      // System files
        "/usr/",         // User binaries
        "/bin/",         // System binaries
        "/sbin/",        // System admin binaries
        "/var/",         // Variable data
        "/tmp/",         // Temp files (security risk)
        "/Library/",     // Global library (non-user)
        "/..",           // Hidden path traversal
        "/~/"            // Tilde injection
    ]

    // MARK: - Public Methods

    /// Validate that a path is safe and within the allowed base path
    /// - Parameters:
    ///   - path: Path to validate
    ///   - basePath: Allowed base path
    /// - Returns: Safe normalized path, or nil if validation fails
    static func validatePath(_ path: String, within basePath: String) -> String? {
        // 1. Normalize path
        let normalized = (path as NSString).standardizingPath
        let normalizedBase = (basePath as NSString).standardizingPath

        // 2. Expand tilde
        let expanded = (normalized as NSString).expandingTildeInPath
        let expandedBase = (normalizedBase as NSString).expandingTildeInPath

        // 3. Resolve symlinks (prevent symlink attacks)
        let resolved = (expanded as NSString).resolvingSymlinksInPath
        let resolvedBase = (expandedBase as NSString).resolvingSymlinksInPath

        // 4. Check if within base path
        guard resolved.hasPrefix(resolvedBase + "/") || resolved == resolvedBase else {
            Logger.shared.warning("PathValidator: Path traversal blocked: \(path) is not within \(basePath)")
            return nil
        }

        // 5. Check dangerous patterns
        for pattern in dangerousPatterns {
            // Only check dangerous patterns when path is outside user home directory
            if normalized.contains(pattern) && !resolved.hasPrefix(NSHomeDirectory()) {
                Logger.shared.warning("PathValidator: Dangerous pattern detected: \(pattern) in \(path)")
                return nil
            }
        }

        // 6. Check double-encoding attacks
        if let decoded = path.removingPercentEncoding, decoded != path {
            if decoded.contains("..") || decoded.contains("//") {
                Logger.shared.warning("PathValidator: Encoding attack detected: \(path)")
                return nil
            }
        }

        // 7. Check null byte injection
        if path.contains("\0") {
            Logger.shared.warning("PathValidator: Null byte injection detected: \(path)")
            return nil
        }

        return resolved
    }

    /// Check if path is an allowed DMSA path
    /// - Parameter path: Path to check
    /// - Returns: Whether the path is in the allowed list
    static func isAllowedDMSAPath(_ path: String) -> Bool {
        let normalized = (path as NSString)
            .standardizingPath
            .expandingTildeInPath
            .resolvingSymlinksInPath

        // Check if it matches any allowed root path
        for root in allowedRoots {
            let resolvedRoot = (root as NSString).resolvingSymlinksInPath
            if normalized.hasPrefix(resolvedRoot) {
                return true
            }
        }

        return false
    }

    /// Build a safe path
    /// - Parameters:
    ///   - base: Base path
    ///   - relative: Relative path
    /// - Returns: Safe full path, or nil if validation fails
    static func safePath(base: String, relative: String) -> String? {
        // Remove leading and trailing slashes
        let clean = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Check for dangerous patterns in relative path
        if clean.contains("..") || clean.contains("//") {
            Logger.shared.warning("PathValidator: Relative path contains dangerous pattern: \(relative)")
            return nil
        }

        // Build full path
        let full = (base as NSString).appendingPathComponent(clean)

        // Validate full path
        return validatePath(full, within: base)
    }

    /// Validate virtual path (for FUSE)
    /// - Parameters:
    ///   - virtualPath: VFS virtual path
    ///   - syncPair: Sync pair config
    /// - Returns: Validated safe path, or nil if validation fails
    static func validateVirtualPath(_ virtualPath: String, for syncPair: SyncPairConfig) -> String? {
        // Virtual path should not start with slash (relative to TARGET_DIR)
        let clean = virtualPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Check dangerous patterns
        if clean.contains("..") || clean.contains("//") || clean.hasPrefix(".") {
            Logger.shared.warning("PathValidator: Virtual path contains dangerous pattern: \(virtualPath)")
            return nil
        }

        return clean
    }

    /// Get safe LOCAL_DIR path
    static func localPath(for virtualPath: String, in syncPair: SyncPairConfig) -> String? {
        guard let cleanVirtual = validateVirtualPath(virtualPath, for: syncPair) else {
            return nil
        }
        return safePath(base: syncPair.localDir, relative: cleanVirtual)
    }

    /// Get safe EXTERNAL_DIR path
    static func externalPath(for virtualPath: String, in syncPair: SyncPairConfig) -> String? {
        guard let cleanVirtual = validateVirtualPath(virtualPath, for: syncPair) else {
            return nil
        }
        return safePath(base: syncPair.externalDir, relative: cleanVirtual)
    }

    // MARK: - Internal Validation Methods

    /// Check if path contains dangerous characters
    private static func containsDangerousCharacters(_ path: String) -> Bool {
        let dangerous = CharacterSet(charactersIn: "\0\n\r")
        return path.unicodeScalars.contains { dangerous.contains($0) }
    }

    /// Check path length
    static func isPathLengthValid(_ path: String) -> Bool {
        // macOS PATH_MAX = 1024
        return path.utf8.count <= 1024
    }

    /// Check file name length
    static func isFileNameValid(_ name: String) -> Bool {
        // macOS NAME_MAX = 255
        return name.utf8.count <= 255 && !name.isEmpty
    }

    /// Check if file/directory is hidden
    static func isHidden(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.hasPrefix(".")
    }
}

// MARK: - Path Validation Errors

enum PathValidationError: Error, LocalizedError {
    case pathTraversal(String)
    case outsideBasePath(String)
    case dangerousPattern(String)
    case encodingAttack(String)
    case nullByteInjection(String)
    case pathTooLong(String)
    case fileNameTooLong(String)
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .pathTraversal(let path):
            return "Path traversal attack blocked: \(path)"
        case .outsideBasePath(let path):
            return "Path outside allowed range: \(path)"
        case .dangerousPattern(let pattern):
            return "Dangerous pattern detected: \(pattern)"
        case .encodingAttack(let path):
            return "Encoding attack detected: \(path)"
        case .nullByteInjection(let path):
            return "Null byte injection detected: \(path)"
        case .pathTooLong(let path):
            return "Path too long: \(path)"
        case .fileNameTooLong(let name):
            return "File name too long: \(name)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        }
    }
}

// MARK: - Path Validation Result

struct PathValidationResult {
    let isValid: Bool
    let normalizedPath: String?
    let error: PathValidationError?

    static func success(_ path: String) -> PathValidationResult {
        return PathValidationResult(isValid: true, normalizedPath: path, error: nil)
    }

    static func failure(_ error: PathValidationError) -> PathValidationResult {
        return PathValidationResult(isValid: false, normalizedPath: nil, error: error)
    }
}

// MARK: - PathValidator Extension Methods

extension PathValidator {

    /// Full validation with detailed result
    static func fullValidation(_ path: String, within basePath: String) -> PathValidationResult {
        // Check path length
        guard isPathLengthValid(path) else {
            return .failure(.pathTooLong(path))
        }

        // Check file name length
        let fileName = (path as NSString).lastPathComponent
        guard isFileNameValid(fileName) else {
            return .failure(.fileNameTooLong(fileName))
        }

        // Perform standard validation
        if let validated = validatePath(path, within: basePath) {
            return .success(validated)
        } else {
            return .failure(.invalidPath(path))
        }
    }
}

// MARK: - String Extension

extension String {
    /// Resolve symlinks in path
    var resolvingSymlinksInPath: String {
        return (self as NSString).resolvingSymlinksInPath
    }

    /// Expand tilde in path
    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }
}
