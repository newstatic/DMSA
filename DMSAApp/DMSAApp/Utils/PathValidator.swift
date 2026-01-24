import Foundation

/// 路径安全验证器
/// 防止路径遍历攻击和未授权的文件系统访问
struct PathValidator {

    // MARK: - 配置

    /// 允许的根路径 (白名单)
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

    /// 危险路径模式 (黑名单)
    private static let dangerousPatterns = [
        "../",           // 路径遍历
        "/etc/",         // 系统配置
        "/private/",     // 系统私有目录
        "/System/",      // 系统文件
        "/usr/",         // 用户二进制
        "/bin/",         // 系统二进制
        "/sbin/",        // 系统管理二进制
        "/var/",         // 变量数据
        "/tmp/",         // 临时文件 (安全风险)
        "/Library/",     // 全局库 (非用户)
        "/..",           // 隐藏路径遍历
        "/~/"            // 波浪号注入
    ]

    // MARK: - 公开方法

    /// 验证路径是否安全且在允许的基础路径内
    /// - Parameters:
    ///   - path: 待验证的路径
    ///   - basePath: 允许的基础路径
    /// - Returns: 安全的规范化路径，如果验证失败返回 nil
    static func validatePath(_ path: String, within basePath: String) -> String? {
        // 1. 规范化路径
        let normalized = (path as NSString).standardizingPath
        let normalizedBase = (basePath as NSString).standardizingPath

        // 2. 展开波浪号
        let expanded = (normalized as NSString).expandingTildeInPath
        let expandedBase = (normalizedBase as NSString).expandingTildeInPath

        // 3. 解析符号链接 (防止符号链接攻击)
        let resolved = (expanded as NSString).resolvingSymlinksInPath
        let resolvedBase = (expandedBase as NSString).resolvingSymlinksInPath

        // 4. 检查是否在基础路径内
        guard resolved.hasPrefix(resolvedBase + "/") || resolved == resolvedBase else {
            Logger.shared.warning("PathValidator: 路径遍历被阻止: \(path) 不在 \(basePath) 内")
            return nil
        }

        // 5. 检查危险模式
        for pattern in dangerousPatterns {
            // 只有当路径不在用户主目录下时才检查危险模式
            if normalized.contains(pattern) && !resolved.hasPrefix(NSHomeDirectory()) {
                Logger.shared.warning("PathValidator: 检测到危险模式: \(pattern) in \(path)")
                return nil
            }
        }

        // 6. 检查双重编码攻击
        if let decoded = path.removingPercentEncoding, decoded != path {
            if decoded.contains("..") || decoded.contains("//") {
                Logger.shared.warning("PathValidator: 检测到编码攻击: \(path)")
                return nil
            }
        }

        // 7. 检查空字节注入
        if path.contains("\0") {
            Logger.shared.warning("PathValidator: 检测到空字节注入: \(path)")
            return nil
        }

        return resolved
    }

    /// 检查是否为允许的 DMSA 路径
    /// - Parameter path: 待检查的路径
    /// - Returns: 是否在允许列表中
    static func isAllowedDMSAPath(_ path: String) -> Bool {
        let normalized = (path as NSString)
            .standardizingPath
            .expandingTildeInPath
            .resolvingSymlinksInPath

        // 检查是否匹配任何允许的根路径
        for root in allowedRoots {
            let resolvedRoot = (root as NSString).resolvingSymlinksInPath
            if normalized.hasPrefix(resolvedRoot) {
                return true
            }
        }

        return false
    }

    /// 构建安全路径
    /// - Parameters:
    ///   - base: 基础路径
    ///   - relative: 相对路径
    /// - Returns: 安全的完整路径，如果验证失败返回 nil
    static func safePath(base: String, relative: String) -> String? {
        // 移除前导和尾随斜杠
        let clean = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // 检查相对路径中是否有危险模式
        if clean.contains("..") || clean.contains("//") {
            Logger.shared.warning("PathValidator: 相对路径包含危险模式: \(relative)")
            return nil
        }

        // 构建完整路径
        let full = (base as NSString).appendingPathComponent(clean)

        // 验证完整路径
        return validatePath(full, within: base)
    }

    /// 验证虚拟路径 (FUSE 使用)
    /// - Parameters:
    ///   - virtualPath: VFS 虚拟路径
    ///   - syncPair: 同步对配置
    /// - Returns: 验证后的安全路径，如果验证失败返回 nil
    static func validateVirtualPath(_ virtualPath: String, for syncPair: SyncPairConfig) -> String? {
        // 虚拟路径不应以斜杠开头 (相对于 TARGET_DIR)
        let clean = virtualPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // 检查危险模式
        if clean.contains("..") || clean.contains("//") || clean.hasPrefix(".") {
            Logger.shared.warning("PathValidator: 虚拟路径包含危险模式: \(virtualPath)")
            return nil
        }

        return clean
    }

    /// 获取 LOCAL_DIR 的安全路径
    static func localPath(for virtualPath: String, in syncPair: SyncPairConfig) -> String? {
        guard let cleanVirtual = validateVirtualPath(virtualPath, for: syncPair) else {
            return nil
        }
        return safePath(base: syncPair.localDir, relative: cleanVirtual)
    }

    /// 获取 EXTERNAL_DIR 的安全路径
    static func externalPath(for virtualPath: String, in syncPair: SyncPairConfig) -> String? {
        guard let cleanVirtual = validateVirtualPath(virtualPath, for: syncPair) else {
            return nil
        }
        return safePath(base: syncPair.externalDir, relative: cleanVirtual)
    }

    // MARK: - 内部验证方法

    /// 检查路径是否包含危险字符
    private static func containsDangerousCharacters(_ path: String) -> Bool {
        let dangerous = CharacterSet(charactersIn: "\0\n\r")
        return path.unicodeScalars.contains { dangerous.contains($0) }
    }

    /// 检查路径长度
    static func isPathLengthValid(_ path: String) -> Bool {
        // macOS PATH_MAX = 1024
        return path.utf8.count <= 1024
    }

    /// 检查文件名长度
    static func isFileNameValid(_ name: String) -> Bool {
        // macOS NAME_MAX = 255
        return name.utf8.count <= 255 && !name.isEmpty
    }

    /// 检查是否为隐藏文件/目录
    static func isHidden(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.hasPrefix(".")
    }
}

// MARK: - 路径验证错误

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
            return "路径遍历攻击被阻止: \(path)"
        case .outsideBasePath(let path):
            return "路径超出允许范围: \(path)"
        case .dangerousPattern(let pattern):
            return "检测到危险模式: \(pattern)"
        case .encodingAttack(let path):
            return "检测到编码攻击: \(path)"
        case .nullByteInjection(let path):
            return "检测到空字节注入: \(path)"
        case .pathTooLong(let path):
            return "路径过长: \(path)"
        case .fileNameTooLong(let name):
            return "文件名过长: \(name)"
        case .invalidPath(let path):
            return "无效路径: \(path)"
        }
    }
}

// MARK: - 路径验证结果

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

// MARK: - PathValidator 扩展方法

extension PathValidator {

    /// 完整验证并返回详细结果
    static func fullValidation(_ path: String, within basePath: String) -> PathValidationResult {
        // 检查路径长度
        guard isPathLengthValid(path) else {
            return .failure(.pathTooLong(path))
        }

        // 检查文件名长度
        let fileName = (path as NSString).lastPathComponent
        guard isFileNameValid(fileName) else {
            return .failure(.fileNameTooLong(fileName))
        }

        // 执行标准验证
        if let validated = validatePath(path, within: basePath) {
            return .success(validated)
        } else {
            return .failure(.invalidPath(path))
        }
    }
}

// MARK: - String 扩展

extension String {
    /// 路径解析 (符号链接)
    var resolvingSymlinksInPath: String {
        return (self as NSString).resolvingSymlinksInPath
    }

    /// 路径展开波浪号
    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }
}
