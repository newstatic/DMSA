import Foundation

/// 文件复制器 - 高效复制文件并支持进度追踪
actor FileCopier {

    // MARK: - 配置

    struct CopyOptions {
        /// 是否保留文件属性（权限、时间等）
        var preserveAttributes: Bool = true

        /// 是否在复制后验证校验和
        var verifyAfterCopy: Bool = false

        /// 验证使用的哈希算法
        var verifyAlgorithm: FileHasher.HashAlgorithm = .md5

        /// 缓冲区大小
        var bufferSize: Int = 1024 * 1024  // 1MB

        /// 是否覆盖已存在的文件
        var overwriteExisting: Bool = true

        /// 是否使用原子写入（先写临时文件再重命名）
        var atomicWrite: Bool = true

        /// 临时文件后缀
        var tempSuffix: String = ".dmsa_tmp"

        static var `default`: CopyOptions { CopyOptions() }
    }

    /// 复制结果
    struct CopyResult {
        var succeeded: Int = 0
        var failed: [(path: String, error: Error)] = []
        var verified: Int = 0
        var verificationFailed: [(path: String, expected: String, actual: String)] = []
        var totalBytes: Int64 = 0
        var duration: TimeInterval = 0

        var successRate: Double {
            let total = succeeded + failed.count
            return total > 0 ? Double(succeeded) / Double(total) : 1.0
        }

        var averageSpeed: Int64 {
            duration > 0 ? Int64(Double(totalBytes) / duration) : 0
        }
    }

    // MARK: - 状态

    private var isCancelled: Bool = false
    private var isPaused: Bool = false
    private let fileManager = FileManager.default

    // MARK: - Logger

    private let logger = Logger.forService("FileCopier")

    // MARK: - 进度回调

    typealias FileProgressHandler = (Int64, Int64) -> Void
    typealias BatchProgressHandler = (SyncProgress) -> Void

    // MARK: - 公共方法

    /// 复制单个文件
    func copy(
        from source: URL,
        to destination: URL,
        options: CopyOptions = .default,
        progressHandler: FileProgressHandler? = nil
    ) async throws {
        isCancelled = false

        // 验证源文件存在
        guard fileManager.fileExists(atPath: source.path) else {
            throw CopierError.sourceNotFound(source.path)
        }

        // 检查目标是否已存在
        if fileManager.fileExists(atPath: destination.path) {
            if options.overwriteExisting {
                try fileManager.removeItem(at: destination)
            } else {
                throw CopierError.destinationExists(destination.path)
            }
        }

        // 创建目标目录
        let destDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destDir.path) {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        }

        // 获取源文件属性
        let sourceAttrs = try fileManager.attributesOfItem(atPath: source.path)
        let fileSize = (sourceAttrs[.size] as? Int64) ?? 0

        // 确定写入目标
        let writeTarget = options.atomicWrite
            ? destination.appendingPathExtension(options.tempSuffix.replacingOccurrences(of: ".", with: ""))
            : destination

        // 执行复制
        try await copyFileContents(
            from: source,
            to: writeTarget,
            fileSize: fileSize,
            bufferSize: options.bufferSize,
            progressHandler: progressHandler
        )

        // 原子写入：重命名临时文件
        if options.atomicWrite {
            try fileManager.moveItem(at: writeTarget, to: destination)
        }

        // 保留属性
        if options.preserveAttributes {
            try preserveAttributes(from: source, to: destination)
        }

        // 验证
        if options.verifyAfterCopy {
            let hasher = FileHasher()

            let sourceChecksum = try await hasher.hash(file: source, algorithm: options.verifyAlgorithm)
            let destChecksum = try await hasher.hash(file: destination, algorithm: options.verifyAlgorithm)

            if sourceChecksum != destChecksum {
                // 删除损坏的文件
                try? fileManager.removeItem(at: destination)
                throw CopierError.verificationFailed(
                    path: destination.path,
                    expected: sourceChecksum,
                    actual: destChecksum
                )
            }
        }
    }

    /// 批量复制文件
    func copyFiles(
        actions: [SyncAction],
        options: CopyOptions = .default,
        progress: SyncProgress,
        progressHandler: BatchProgressHandler? = nil
    ) async throws -> CopyResult {
        isCancelled = false
        isPaused = false

        var result = CopyResult()
        let startTime = Date()

        // 筛选复制和更新动作
        let copyActions = actions.filter { action in
            switch action {
            case .copy, .update:
                return true
            default:
                return false
            }
        }

        progress.totalFiles = copyActions.count
        progress.totalBytes = copyActions.reduce(0) { $0 + $1.bytes }

        for (index, action) in copyActions.enumerated() {
            // 检查取消
            if isCancelled {
                throw CopierError.cancelled
            }

            // 检查暂停
            while isPaused {
                try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                if isCancelled { throw CopierError.cancelled }
            }

            guard case let .copy(source, destination, metadata) = action else {
                if case let .update(source, destination, metadata) = action {
                    // 处理更新动作
                    await processCopyAction(
                        source: source,
                        destination: destination,
                        metadata: metadata,
                        options: options,
                        progress: progress,
                        result: &result
                    )
                }
                continue
            }

            await processCopyAction(
                source: source,
                destination: destination,
                metadata: metadata,
                options: options,
                progress: progress,
                result: &result
            )

            progressHandler?(progress)
        }

        result.duration = Date().timeIntervalSince(startTime)
        return result
    }

    /// 暂停复制
    func pause() {
        isPaused = true
    }

    /// 恢复复制
    func resume() {
        isPaused = false
    }

    /// 取消复制
    func cancel() {
        isCancelled = true
        isPaused = false
    }

    /// 创建目录
    func createDirectory(at path: URL) throws {
        try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
    }

    /// 删除文件
    func deleteFile(at path: URL) throws {
        guard fileManager.fileExists(atPath: path.path) else { return }
        try fileManager.removeItem(at: path)
    }

    /// 创建备份
    func createBackup(
        of file: URL,
        suffix: String = "_backup"
    ) throws -> URL {
        guard fileManager.fileExists(atPath: file.path) else {
            throw CopierError.sourceNotFound(file.path)
        }

        let fileName = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        let backupName = ext.isEmpty
            ? "\(fileName)\(suffix)"
            : "\(fileName)\(suffix).\(ext)"

        let backupURL = file.deletingLastPathComponent().appendingPathComponent(backupName)

        // 如果备份已存在，添加数字后缀
        var finalBackupURL = backupURL
        var counter = 1
        while fileManager.fileExists(atPath: finalBackupURL.path) {
            let numberedName = ext.isEmpty
                ? "\(fileName)\(suffix)_\(counter)"
                : "\(fileName)\(suffix)_\(counter).\(ext)"
            finalBackupURL = file.deletingLastPathComponent().appendingPathComponent(numberedName)
            counter += 1
        }

        try fileManager.copyItem(at: file, to: finalBackupURL)
        return finalBackupURL
    }

    // MARK: - 私有方法

    /// 复制文件内容
    private func copyFileContents(
        from source: URL,
        to destination: URL,
        fileSize: Int64,
        bufferSize: Int,
        progressHandler: FileProgressHandler?
    ) async throws {
        guard let inputHandle = try? FileHandle(forReadingFrom: source) else {
            throw CopierError.cannotOpenSource(source.path)
        }
        defer { try? inputHandle.close() }

        // 创建输出文件
        fileManager.createFile(atPath: destination.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: destination) else {
            throw CopierError.cannotCreateDestination(destination.path)
        }
        defer { try? outputHandle.close() }

        var bytesWritten: Int64 = 0

        while true {
            if isCancelled {
                // 清理临时文件
                try? fileManager.removeItem(at: destination)
                throw CopierError.cancelled
            }

            while isPaused {
                try await Task.sleep(nanoseconds: 100_000_000)
                if isCancelled {
                    try? fileManager.removeItem(at: destination)
                    throw CopierError.cancelled
                }
            }

            let data = inputHandle.readData(ofLength: bufferSize)
            if data.isEmpty { break }

            outputHandle.write(data)
            bytesWritten += Int64(data.count)

            progressHandler?(bytesWritten, fileSize)
        }

        // 同步到磁盘
        try outputHandle.synchronize()
    }

    /// 保留文件属性
    private func preserveAttributes(from source: URL, to destination: URL) throws {
        let attrs = try fileManager.attributesOfItem(atPath: source.path)

        var newAttrs: [FileAttributeKey: Any] = [:]

        // 保留修改时间
        if let modDate = attrs[.modificationDate] {
            newAttrs[.modificationDate] = modDate
        }

        // 保留创建时间
        if let createDate = attrs[.creationDate] {
            newAttrs[.creationDate] = createDate
        }

        // 保留权限
        if let permissions = attrs[.posixPermissions] {
            newAttrs[.posixPermissions] = permissions
        }

        if !newAttrs.isEmpty {
            try fileManager.setAttributes(newAttrs, ofItemAtPath: destination.path)
        }
    }

    /// 处理单个复制动作
    private func processCopyAction(
        source: String,
        destination: String,
        metadata: FileMetadata,
        options: CopyOptions,
        progress: SyncProgress,
        result: inout CopyResult
    ) async {
        let sourceURL = URL(fileURLWithPath: source)
        let destURL = URL(fileURLWithPath: destination)

        progress.currentFile = metadata.fileName
        progress.currentFileSize = metadata.size
        progress.currentFileBytesTransferred = 0

        do {
            try await copy(
                from: sourceURL,
                to: destURL,
                options: options
            ) { bytesTransferred, totalSize in
                progress.currentFileBytesTransferred = bytesTransferred
                progress.currentFileProgress = Double(bytesTransferred) / Double(max(totalSize, 1))
            }

            result.succeeded += 1
            result.totalBytes += metadata.size
            progress.completeFile(bytes: metadata.size)

            if options.verifyAfterCopy {
                result.verified += 1
            }

        } catch CopierError.verificationFailed(let path, let expected, let actual) {
            result.verificationFailed.append((path, expected, actual))
            progress.failFile(path: source, error: "校验失败")
        } catch {
            result.failed.append((source, error))
            progress.failFile(path: source, error: error.localizedDescription)
        }
    }
}

// MARK: - 复制器错误

enum CopierError: Error, LocalizedError {
    case sourceNotFound(String)
    case destinationExists(String)
    case cannotOpenSource(String)
    case cannotCreateDestination(String)
    case writeError(String)
    case verificationFailed(path: String, expected: String, actual: String)
    case cancelled
    case insufficientSpace(required: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let path):
            return "源文件不存在: \(path)"
        case .destinationExists(let path):
            return "目标文件已存在: \(path)"
        case .cannotOpenSource(let path):
            return "无法打开源文件: \(path)"
        case .cannotCreateDestination(let path):
            return "无法创建目标文件: \(path)"
        case .writeError(let path):
            return "写入错误: \(path)"
        case .verificationFailed(let path, let expected, let actual):
            return "校验失败: \(path) (期望: \(expected.prefix(8))..., 实际: \(actual.prefix(8))...)"
        case .cancelled:
            return "复制已取消"
        case .insufficientSpace(let required, let available):
            let reqStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "空间不足: 需要 \(reqStr), 可用 \(availStr)"
        }
    }
}
