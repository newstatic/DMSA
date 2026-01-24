import Foundation

/// 文件扫描器 - 遍历目录并收集文件元数据
actor FileScanner {
    // MARK: - 配置

    /// 排除模式列表
    private var excludePatterns: [String] = []

    /// 是否包含隐藏文件
    private var includeHidden: Bool = false

    /// 最大文件大小限制 (nil 表示无限制)
    private var maxFileSize: Int64?

    /// 是否跟随符号链接
    private var followSymlinks: Bool = false

    // MARK: - 状态

    /// 是否已取消
    private var isCancelled: Bool = false

    /// 扫描进度回调
    typealias ProgressHandler = (Int, String) -> Void

    // MARK: - Logger

    private let logger = Logger.forService("FileScanner")

    // MARK: - 初始化

    init(
        excludePatterns: [String] = [],
        includeHidden: Bool = false,
        maxFileSize: Int64? = nil,
        followSymlinks: Bool = false
    ) {
        self.excludePatterns = excludePatterns
        self.includeHidden = includeHidden
        self.maxFileSize = maxFileSize
        self.followSymlinks = followSymlinks
    }

    // MARK: - 公共方法

    /// 扫描目录，生成文件元数据快照
    func scan(
        directory: URL,
        progressHandler: ProgressHandler? = nil
    ) async throws -> DirectorySnapshot {
        isCancelled = false

        let fileManager = FileManager.default

        // 验证目录存在
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ScannerError.directoryNotFound(directory.path)
        }

        var snapshot = DirectorySnapshot(rootPath: directory.path)
        var fileCount = 0

        // 创建目录枚举器
        let options: FileManager.DirectoryEnumerationOptions = followSymlinks ? [] : [.skipsPackageDescendants]

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .creationDateKey
            ],
            options: options
        ) else {
            throw ScannerError.enumerationFailed(directory.path)
        }

        // 遍历所有文件
        for case let fileURL as URL in enumerator {
            // 检查取消状态
            if isCancelled {
                throw ScannerError.cancelled
            }

            // 获取相对路径
            let relativePath = fileURL.path.replacingOccurrences(
                of: directory.path + "/",
                with: ""
            )

            // 检查排除规则
            if shouldExclude(relativePath: relativePath, url: fileURL) {
                enumerator.skipDescendants()
                continue
            }

            // 获取文件元数据
            do {
                let metadata = try FileMetadata.from(url: fileURL, relativeTo: directory)

                // 检查文件大小限制
                if let maxSize = maxFileSize, !metadata.isDirectory && metadata.size > maxSize {
                    continue
                }

                snapshot.update(metadata)
                fileCount += 1

                // 回调进度
                progressHandler?(fileCount, relativePath)

            } catch {
                // 记录错误但继续扫描
                logger.warning("扫描文件失败: \(fileURL.path), 错误: \(error)")
            }
        }

        return snapshot
    }

    /// 增量扫描 - 基于上次快照，只扫描变化的文件
    func incrementalScan(
        directory: URL,
        previousSnapshot: DirectorySnapshot,
        progressHandler: ProgressHandler? = nil
    ) async throws -> DirectorySnapshot {
        isCancelled = false

        let fileManager = FileManager.default
        var newSnapshot = DirectorySnapshot(rootPath: directory.path)
        var fileCount = 0

        // 获取上次扫描的文件列表
        let previousFiles = Set(previousSnapshot.files.keys)
        var currentFiles = Set<String>()

        // 创建目录枚举器
        let options: FileManager.DirectoryEnumerationOptions = followSymlinks ? [] : [.skipsPackageDescendants]

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .contentModificationDateKey,
                .fileSizeKey
            ],
            options: options
        ) else {
            throw ScannerError.enumerationFailed(directory.path)
        }

        for case let fileURL as URL in enumerator {
            if isCancelled {
                throw ScannerError.cancelled
            }

            let relativePath = fileURL.path.replacingOccurrences(
                of: directory.path + "/",
                with: ""
            )

            if shouldExclude(relativePath: relativePath, url: fileURL) {
                enumerator.skipDescendants()
                continue
            }

            currentFiles.insert(relativePath)

            // 检查是否需要重新扫描
            if let previousMeta = previousSnapshot.metadata(for: relativePath) {
                // 快速检查：比较修改时间和大小
                let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let mtime = attrs?[.modificationDate] as? Date
                let size = attrs?[.size] as? Int64

                if let mtime = mtime, let size = size,
                   abs(mtime.timeIntervalSince(previousMeta.modifiedTime)) < 1.0 &&
                   size == previousMeta.size {
                    // 文件未变化，复用旧元数据
                    newSnapshot.update(previousMeta)
                    fileCount += 1
                    progressHandler?(fileCount, relativePath)
                    continue
                }
            }

            // 需要重新获取完整元数据
            do {
                let metadata = try FileMetadata.from(url: fileURL, relativeTo: directory)

                if let maxSize = maxFileSize, !metadata.isDirectory && metadata.size > maxSize {
                    continue
                }

                newSnapshot.update(metadata)
                fileCount += 1
                progressHandler?(fileCount, relativePath)

            } catch {
                logger.warning("增量扫描文件失败: \(fileURL.path), 错误: \(error)")
            }
        }

        // 标记已删除的文件 (可选：不添加到新快照中，它们自然不存在)
        let deletedFiles = previousFiles.subtracting(currentFiles)
        if !deletedFiles.isEmpty {
            logger.info("检测到 \(deletedFiles.count) 个已删除文件")
        }

        return newSnapshot
    }

    /// 取消扫描
    func cancel() {
        isCancelled = true
    }

    /// 更新配置
    func updateConfig(
        excludePatterns: [String]? = nil,
        includeHidden: Bool? = nil,
        maxFileSize: Int64? = nil,
        followSymlinks: Bool? = nil
    ) {
        if let patterns = excludePatterns {
            self.excludePatterns = patterns
        }
        if let hidden = includeHidden {
            self.includeHidden = hidden
        }
        if let size = maxFileSize {
            self.maxFileSize = size
        }
        if let symlinks = followSymlinks {
            self.followSymlinks = symlinks
        }
    }

    // MARK: - 私有方法

    /// 检查是否应该排除该文件
    private func shouldExclude(relativePath: String, url: URL) -> Bool {
        let fileName = url.lastPathComponent

        // 检查隐藏文件
        if !includeHidden && fileName.hasPrefix(".") {
            return true
        }

        // 检查排除模式
        for pattern in excludePatterns {
            if matchesPattern(relativePath, pattern: pattern) ||
               matchesPattern(fileName, pattern: pattern) {
                return true
            }
        }

        return false
    }

    /// 简单的 glob 模式匹配
    private func matchesPattern(_ string: String, pattern: String) -> Bool {
        // 处理简单的 glob 模式
        if pattern == string {
            return true
        }

        // 处理 * 通配符
        if pattern.contains("*") {
            let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*\\*", with: ".*")
                .replacingOccurrences(of: "\\*", with: "[^/]*") + "$"

            if let regex = try? NSRegularExpression(pattern: regexPattern, options: []) {
                let range = NSRange(string.startIndex..., in: string)
                return regex.firstMatch(in: string, options: [], range: range) != nil
            }
        }

        return false
    }
}

// MARK: - 扫描器错误

enum ScannerError: Error, LocalizedError {
    case directoryNotFound(String)
    case enumerationFailed(String)
    case permissionDenied(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "目录不存在: \(path)"
        case .enumerationFailed(let path):
            return "无法枚举目录: \(path)"
        case .permissionDenied(let path):
            return "权限不足: \(path)"
        case .cancelled:
            return "扫描已取消"
        }
    }
}
