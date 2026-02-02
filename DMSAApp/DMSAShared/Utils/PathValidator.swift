import Foundation

/// Path safety validator
public struct PathValidator {

    /// Check if path is allowed for operations
    public static func isAllowed(_ path: String) -> Bool {
        let resolvedPath = resolvePath(path)

        // Check forbidden paths
        for forbidden in Constants.forbiddenPaths {
            if resolvedPath.hasPrefix(forbidden) {
                return false
            }
        }

        // Check allowed paths
        for allowed in Constants.allowedPathPrefixes {
            if resolvedPath.hasPrefix(allowed) {
                return true
            }
        }

        return false
    }

    /// Validate path is safe (no path traversal attacks)
    public static func isSafe(_ path: String) -> Bool {
        let resolvedPath = resolvePath(path)

        // Check for path traversal attacks
        if path.contains("..") {
            // Resolved path should not contain .. components
            let components = resolvedPath.components(separatedBy: "/")
            if components.contains("..") {
                return false
            }
        }

        // Check for null byte injection
        if path.contains("\0") {
            return false
        }

        return true
    }

    /// Validate path is under specified directory
    public static func isUnder(_ path: String, directory: String) -> Bool {
        let resolvedPath = resolvePath(path)
        let resolvedDir = resolvePath(directory)

        // Ensure directory path ends with / for comparison
        let dirPrefix = resolvedDir.hasSuffix("/") ? resolvedDir : resolvedDir + "/"

        return resolvedPath.hasPrefix(dirPrefix) || resolvedPath == resolvedDir
    }

    /// Resolve path (expand ~ and resolve symlinks)
    public static func resolvePath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        return standardized
    }

    /// Validate path and return error message
    public static func validate(_ path: String) -> Result<String, HelperError> {
        guard isSafe(path) else {
            return .failure(.pathNotAllowed("Path contains illegal characters or traversal attack: \(path)"))
        }

        guard isAllowed(path) else {
            return .failure(.pathNotAllowed("Path not in allowed list: \(path)"))
        }

        return .success(resolvePath(path))
    }

    /// Batch validate paths
    public static func validateAll(_ paths: [String]) -> Result<[String], HelperError> {
        var resolvedPaths: [String] = []

        for path in paths {
            switch validate(path) {
            case .success(let resolved):
                resolvedPaths.append(resolved)
            case .failure(let error):
                return .failure(error)
            }
        }

        return .success(resolvedPaths)
    }
}

// MARK: - Path Extensions

public extension String {
    /// Expand and standardize path
    var resolvedPath: String {
        return PathValidator.resolvePath(self)
    }

    /// Check if path is allowed for operations
    var isAllowedPath: Bool {
        return PathValidator.isAllowed(self)
    }

    /// Check if path is safe
    var isSafePath: Bool {
        return PathValidator.isSafe(self)
    }
}
