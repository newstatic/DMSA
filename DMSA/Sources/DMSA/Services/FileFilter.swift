import Foundation

/// 文件过滤器
final class FileFilter {

    static let shared = FileFilter()

    private let configManager = ConfigManager.shared

    private init() {}

    /// 检查文件是否应被排除
    func shouldExclude(path: String) -> Bool {
        let config = configManager.config.filters
        let fileName = (path as NSString).lastPathComponent

        // 1. 检查排除模式
        for pattern in config.excludePatterns {
            if matchesPattern(fileName: fileName, pattern: pattern) {
                return true
            }
        }

        // 2. 检查隐藏文件
        if config.excludeHidden && fileName.hasPrefix(".") {
            return true
        }

        // 3. 检查文件大小
        if let fileSize = getFileSize(at: path) {
            if let maxSize = config.maxFileSize, fileSize > maxSize {
                return true
            }
            if let minSize = config.minFileSize, fileSize < minSize {
                return true
            }
        }

        return false
    }

    /// 检查文件是否应被包含
    func shouldInclude(path: String) -> Bool {
        let config = configManager.config.filters
        let fileName = (path as NSString).lastPathComponent

        // 如果没有包含模式或模式为 ["*"]，则包含所有
        if config.includePatterns.isEmpty || config.includePatterns == ["*"] {
            return true
        }

        // 检查包含模式
        for pattern in config.includePatterns {
            if matchesPattern(fileName: fileName, pattern: pattern) {
                return true
            }
        }

        return false
    }

    /// 过滤文件列表
    func filter(paths: [String]) -> [String] {
        return paths.filter { path in
            shouldInclude(path: path) && !shouldExclude(path: path)
        }
    }

    /// 过滤 URL 列表
    func filter(urls: [URL]) -> [URL] {
        return urls.filter { url in
            let path = url.path
            return shouldInclude(path: path) && !shouldExclude(path: path)
        }
    }

    /// 检查文件名是否匹配模式
    private func matchesPattern(fileName: String, pattern: String) -> Bool {
        // 完全匹配
        if fileName == pattern {
            return true
        }

        // 通配符匹配
        if pattern.contains("*") {
            return matchesWildcard(fileName: fileName, pattern: pattern)
        }

        // 前缀匹配 (如 ".DS_Store")
        if pattern.hasPrefix(".") && fileName.hasPrefix(pattern) {
            return true
        }

        return false
    }

    /// 通配符匹配
    private func matchesWildcard(fileName: String, pattern: String) -> Bool {
        // 处理 *.ext 模式
        if pattern.hasPrefix("*.") {
            let ext = String(pattern.dropFirst(2))
            return fileName.hasSuffix("." + ext)
        }

        // 处理 prefix* 模式
        if pattern.hasSuffix("*") {
            let prefix = String(pattern.dropLast())
            return fileName.hasPrefix(prefix)
        }

        // 处理 *suffix 模式
        if pattern.hasPrefix("*") {
            let suffix = String(pattern.dropFirst())
            return fileName.hasSuffix(suffix)
        }

        // 使用正则表达式处理复杂模式
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")

        do {
            let regex = try NSRegularExpression(pattern: "^" + regexPattern + "$", options: .caseInsensitive)
            let range = NSRange(fileName.startIndex..., in: fileName)
            return regex.firstMatch(in: fileName, range: range) != nil
        } catch {
            return false
        }
    }

    /// 获取文件大小
    private func getFileSize(at path: String) -> Int64? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            return attrs[.size] as? Int64
        } catch {
            return nil
        }
    }

    // MARK: - 预设过滤规则

    /// 默认排除模式
    static let defaultExcludePatterns: [String] = [
        // macOS 系统文件
        ".DS_Store",
        ".Trash",
        ".Spotlight-V100",
        ".fseventsd",
        ".TemporaryItems",
        ".VolumeIcon.icns",
        "._*",                  // AppleDouble 文件

        // 临时文件
        "*.tmp",
        "*.temp",
        "*.swp",
        "*.swo",
        "*~",

        // Windows 文件
        "Thumbs.db",
        "desktop.ini",
        "ehthumbs.db",

        // 下载中的文件
        "*.part",
        "*.crdownload",
        "*.download",
        "*.partial",

        // IDE/编辑器
        ".idea",
        ".vscode",
        "*.xcuserdata",

        // Git
        ".git",
        ".gitignore"
    ]

    /// 开发相关排除模式
    static let developerExcludePatterns: [String] = [
        "node_modules",
        "vendor",
        ".gradle",
        "build",
        "dist",
        "target",
        "__pycache__",
        "*.pyc",
        ".cache",
        "Pods"
    ]

    /// 媒体文件过滤 (仅同步媒体)
    static let mediaIncludePatterns: [String] = [
        "*.jpg",
        "*.jpeg",
        "*.png",
        "*.gif",
        "*.bmp",
        "*.tiff",
        "*.heic",
        "*.mp4",
        "*.mov",
        "*.avi",
        "*.mkv",
        "*.mp3",
        "*.wav",
        "*.flac",
        "*.aac"
    ]

    /// 文档文件过滤
    static let documentIncludePatterns: [String] = [
        "*.pdf",
        "*.doc",
        "*.docx",
        "*.xls",
        "*.xlsx",
        "*.ppt",
        "*.pptx",
        "*.txt",
        "*.md",
        "*.rtf",
        "*.pages",
        "*.numbers",
        "*.keynote"
    ]
}

// MARK: - FilterPreset

/// 过滤预设
struct FilterPreset: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var description: String
    var excludePatterns: [String]
    var includePatterns: [String]
    var excludeHidden: Bool
    var maxFileSize: Int64?
    var minFileSize: Int64?

    /// 默认预设
    static let defaultPreset = FilterPreset(
        name: "默认",
        description: "排除系统文件和临时文件",
        excludePatterns: FileFilter.defaultExcludePatterns,
        includePatterns: ["*"],
        excludeHidden: false,
        maxFileSize: nil,
        minFileSize: nil
    )

    /// 开发者预设
    static let developerPreset = FilterPreset(
        name: "开发者",
        description: "排除系统文件、临时文件和开发依赖",
        excludePatterns: FileFilter.defaultExcludePatterns + FileFilter.developerExcludePatterns,
        includePatterns: ["*"],
        excludeHidden: false,
        maxFileSize: nil,
        minFileSize: nil
    )

    /// 媒体文件预设
    static let mediaPreset = FilterPreset(
        name: "媒体文件",
        description: "仅同步图片、视频和音频文件",
        excludePatterns: FileFilter.defaultExcludePatterns,
        includePatterns: FileFilter.mediaIncludePatterns,
        excludeHidden: true,
        maxFileSize: nil,
        minFileSize: nil
    )

    /// 文档预设
    static let documentPreset = FilterPreset(
        name: "文档",
        description: "仅同步文档文件",
        excludePatterns: FileFilter.defaultExcludePatterns,
        includePatterns: FileFilter.documentIncludePatterns,
        excludeHidden: true,
        maxFileSize: nil,
        minFileSize: nil
    )

    /// 所有内置预设
    static let builtInPresets: [FilterPreset] = [
        defaultPreset,
        developerPreset,
        mediaPreset,
        documentPreset
    ]
}
