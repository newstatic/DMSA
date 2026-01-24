import Foundation
import CryptoKit

/// 文件校验计算器 - 支持 MD5、SHA256、xxHash
actor FileHasher {
    // MARK: - 配置

    /// 缓冲区大小 (默认 1MB)
    private let bufferSize: Int

    /// 是否已取消
    private var isCancelled: Bool = false

    // MARK: - Logger

    private let logger = Logger.forService("FileHasher")

    // MARK: - 类型定义

    /// 哈希算法
    enum HashAlgorithm: String, Codable {
        case md5 = "md5"
        case sha256 = "sha256"
        case xxhash64 = "xxhash64"

        var displayName: String {
            switch self {
            case .md5: return "MD5"
            case .sha256: return "SHA-256"
            case .xxhash64: return "xxHash64"
            }
        }
    }

    /// 进度回调
    typealias FileProgressHandler = (Int64, Int64) -> Void
    typealias BatchProgressHandler = (Int, Int, String) -> Void

    // MARK: - 初始化

    init(bufferSize: Int = 1024 * 1024) {
        self.bufferSize = bufferSize
    }

    // MARK: - 公共方法

    /// 计算单个文件的校验和
    func hash(
        file: URL,
        algorithm: HashAlgorithm = .md5,
        progressHandler: FileProgressHandler? = nil
    ) async throws -> String {
        isCancelled = false

        guard FileManager.default.fileExists(atPath: file.path) else {
            throw HasherError.fileNotFound(file.path)
        }

        guard let fileHandle = try? FileHandle(forReadingFrom: file) else {
            throw HasherError.cannotOpenFile(file.path)
        }

        defer { try? fileHandle.close() }

        // 获取文件大小
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let fileSize = (attributes[.size] as? Int64) ?? 0

        switch algorithm {
        case .md5:
            return try await hashMD5(fileHandle: fileHandle, fileSize: fileSize, progressHandler: progressHandler)
        case .sha256:
            return try await hashSHA256(fileHandle: fileHandle, fileSize: fileSize, progressHandler: progressHandler)
        case .xxhash64:
            return try await hashXXHash64(fileHandle: fileHandle, fileSize: fileSize, progressHandler: progressHandler)
        }
    }

    /// 批量计算文件校验和
    func hashFiles(
        files: [URL],
        algorithm: HashAlgorithm = .md5,
        progressHandler: BatchProgressHandler? = nil
    ) async throws -> [URL: String] {
        isCancelled = false

        var results: [URL: String] = [:]
        let total = files.count

        for (index, file) in files.enumerated() {
            if isCancelled {
                throw HasherError.cancelled
            }

            progressHandler?(index + 1, total, file.lastPathComponent)

            do {
                let checksum = try await hash(file: file, algorithm: algorithm)
                results[file] = checksum
            } catch {
                logger.warning("计算校验和失败: \(file.path), 错误: \(error)")
                // 继续处理其他文件
            }
        }

        return results
    }

    /// 批量计算文件校验和 (并行版本)
    func hashFilesParallel(
        files: [URL],
        algorithm: HashAlgorithm = .md5,
        maxConcurrent: Int = 4,
        progressHandler: BatchProgressHandler? = nil
    ) async throws -> [URL: String] {
        isCancelled = false

        let results = await withTaskGroup(of: (URL, String?).self) { group in
            var completed = 0
            var resultDict: [URL: String] = [:]
            var pending = files[...]

            // 启动初始批次
            for _ in 0..<min(maxConcurrent, files.count) {
                if let file = pending.popFirst() {
                    group.addTask {
                        do {
                            let checksum = try await self.hashSingle(file: file, algorithm: algorithm)
                            return (file, checksum)
                        } catch {
                            return (file, nil)
                        }
                    }
                }
            }

            // 处理完成的任务并添加新任务
            for await (file, checksum) in group {
                completed += 1
                if let checksum = checksum {
                    resultDict[file] = checksum
                }

                progressHandler?(completed, files.count, file.lastPathComponent)

                // 添加下一个待处理文件
                if let nextFile = pending.popFirst() {
                    group.addTask {
                        do {
                            let checksum = try await self.hashSingle(file: nextFile, algorithm: algorithm)
                            return (nextFile, checksum)
                        } catch {
                            return (nextFile, nil)
                        }
                    }
                }
            }

            return resultDict
        }

        return results
    }

    /// 验证文件校验和
    func verify(
        file: URL,
        expectedChecksum: String,
        algorithm: HashAlgorithm = .md5
    ) async throws -> Bool {
        let actualChecksum = try await hash(file: file, algorithm: algorithm)
        return actualChecksum.lowercased() == expectedChecksum.lowercased()
    }

    /// 取消计算
    func cancel() {
        isCancelled = true
    }

    // MARK: - 私有方法

    /// 单文件哈希 (用于并行处理)
    private func hashSingle(file: URL, algorithm: HashAlgorithm) async throws -> String {
        guard !isCancelled else { throw HasherError.cancelled }
        return try await hash(file: file, algorithm: algorithm)
    }

    /// MD5 哈希
    private func hashMD5(
        fileHandle: FileHandle,
        fileSize: Int64,
        progressHandler: FileProgressHandler?
    ) async throws -> String {
        var hasher = Insecure.MD5()
        var bytesRead: Int64 = 0

        while true {
            if isCancelled { throw HasherError.cancelled }

            autoreleasepool {
                let data = fileHandle.readData(ofLength: bufferSize)
                if !data.isEmpty {
                    hasher.update(data: data)
                    bytesRead += Int64(data.count)
                    progressHandler?(bytesRead, fileSize)
                }
            }

            // 检查是否到达文件末尾
            if fileHandle.offsetInFile >= fileSize {
                break
            }
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 哈希
    private func hashSHA256(
        fileHandle: FileHandle,
        fileSize: Int64,
        progressHandler: FileProgressHandler?
    ) async throws -> String {
        var hasher = SHA256()
        var bytesRead: Int64 = 0

        while true {
            if isCancelled { throw HasherError.cancelled }

            autoreleasepool {
                let data = fileHandle.readData(ofLength: bufferSize)
                if !data.isEmpty {
                    hasher.update(data: data)
                    bytesRead += Int64(data.count)
                    progressHandler?(bytesRead, fileSize)
                }
            }

            if fileHandle.offsetInFile >= fileSize {
                break
            }
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// xxHash64 哈希 (快速非加密哈希)
    private func hashXXHash64(
        fileHandle: FileHandle,
        fileSize: Int64,
        progressHandler: FileProgressHandler?
    ) async throws -> String {
        // 使用简化的 xxHash64 实现
        var hash: UInt64 = 0
        let prime1: UInt64 = 11400714785074694791
        let prime2: UInt64 = 14029467366897019727
        let prime5: UInt64 = 2870177450012600261

        var bytesRead: Int64 = 0

        while true {
            if isCancelled { throw HasherError.cancelled }

            let data = fileHandle.readData(ofLength: bufferSize)
            if data.isEmpty { break }

            bytesRead += Int64(data.count)

            data.withUnsafeBytes { buffer in
                let bytes = buffer.bindMemory(to: UInt8.self)
                for byte in bytes {
                    hash = hash ^ UInt64(byte)
                    hash = hash &* prime1
                    hash = (hash << 31) | (hash >> 33)
                    hash = hash &* prime2
                }
            }

            progressHandler?(bytesRead, fileSize)

            if fileHandle.offsetInFile >= fileSize {
                break
            }
        }

        // 最终混合
        hash = hash ^ (hash >> 33)
        hash = hash &* prime2
        hash = hash ^ (hash >> 29)
        hash = hash &* prime5
        hash = hash ^ (hash >> 32)

        return String(format: "%016llx", hash)
    }
}

// MARK: - 哈希器错误

enum HasherError: Error, LocalizedError {
    case fileNotFound(String)
    case cannotOpenFile(String)
    case readError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "文件不存在: \(path)"
        case .cannotOpenFile(let path):
            return "无法打开文件: \(path)"
        case .readError(let path):
            return "读取文件失败: \(path)"
        case .cancelled:
            return "校验计算已取消"
        }
    }
}

// MARK: - 便捷扩展

extension FileMetadata {
    /// 计算并更新校验和
    mutating func computeChecksum(
        baseURL: URL,
        algorithm: FileHasher.HashAlgorithm = .md5
    ) async throws {
        guard !isDirectory else { return }

        let fileURL = baseURL.appendingPathComponent(relativePath)
        let hasher = FileHasher()
        checksum = try await hasher.hash(file: fileURL, algorithm: algorithm)
    }
}

extension DirectorySnapshot {
    /// 批量计算校验和
    mutating func computeChecksums(
        algorithm: FileHasher.HashAlgorithm = .md5,
        progressHandler: FileHasher.BatchProgressHandler? = nil
    ) async throws {
        let hasher = FileHasher()
        let baseURL = URL(fileURLWithPath: rootPath)

        // 只对文件计算校验和，跳过目录
        let filesToHash = files.values.filter { !$0.isDirectory }
        let fileURLs = filesToHash.map { baseURL.appendingPathComponent($0.relativePath) }

        let checksums = try await hasher.hashFilesParallel(
            files: fileURLs,
            algorithm: algorithm,
            progressHandler: progressHandler
        )

        // 更新元数据
        for (url, checksum) in checksums {
            let relativePath = url.path.replacingOccurrences(of: rootPath + "/", with: "")
            if var metadata = files[relativePath] {
                metadata.checksum = checksum
                files[relativePath] = metadata
            }
        }
    }
}
