import Foundation

/// 路径安全验证器
public struct PathValidator {

    /// 验证路径是否允许操作
    public static func isAllowed(_ path: String) -> Bool {
        let resolvedPath = resolvePath(path)

        // 检查禁止路径
        for forbidden in Constants.forbiddenPaths {
            if resolvedPath.hasPrefix(forbidden) {
                return false
            }
        }

        // 检查允许路径
        for allowed in Constants.allowedPathPrefixes {
            if resolvedPath.hasPrefix(allowed) {
                return true
            }
        }

        return false
    }

    /// 验证路径是否安全 (没有路径遍历攻击)
    public static func isSafe(_ path: String) -> Bool {
        let resolvedPath = resolvePath(path)

        // 检查路径遍历攻击
        if path.contains("..") {
            // 解析后的路径应该不包含 .. 组件
            let components = resolvedPath.components(separatedBy: "/")
            if components.contains("..") {
                return false
            }
        }

        // 检查空字符注入
        if path.contains("\0") {
            return false
        }

        return true
    }

    /// 验证路径是否在指定目录下
    public static func isUnder(_ path: String, directory: String) -> Bool {
        let resolvedPath = resolvePath(path)
        let resolvedDir = resolvePath(directory)

        // 确保目录路径以 / 结尾进行比较
        let dirPrefix = resolvedDir.hasSuffix("/") ? resolvedDir : resolvedDir + "/"

        return resolvedPath.hasPrefix(dirPrefix) || resolvedPath == resolvedDir
    }

    /// 解析路径 (展开 ~ 和解析符号链接)
    public static func resolvePath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        return standardized
    }

    /// 验证路径并返回错误信息
    public static func validate(_ path: String) -> Result<String, HelperError> {
        guard isSafe(path) else {
            return .failure(.pathNotAllowed("路径包含非法字符或遍历攻击: \(path)"))
        }

        guard isAllowed(path) else {
            return .failure(.pathNotAllowed("路径不在允许列表中: \(path)"))
        }

        return .success(resolvePath(path))
    }

    /// 批量验证路径
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

// MARK: - 路径扩展

public extension String {
    /// 展开并标准化路径
    var resolvedPath: String {
        return PathValidator.resolvePath(self)
    }

    /// 检查路径是否允许操作
    var isAllowedPath: Bool {
        return PathValidator.isAllowed(self)
    }

    /// 检查路径是否安全
    var isSafePath: Bool {
        return PathValidator.isSafe(self)
    }
}
