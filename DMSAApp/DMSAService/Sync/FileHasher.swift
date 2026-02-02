import Foundation
import CryptoKit

/// File Checksum Calculator - Supports MD5, SHA256, xxHash
actor FileHasher {
    // MARK: - Configuration

    /// Buffer size (default 1MB)
    private let bufferSize: Int

    /// Whether cancelled
    private var isCancelled: Bool = false

    // MARK: - Logger

    private let logger = Logger.forService("FileHasher")

    // MARK: - Type Definitions

    /// Hash algorithm
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

    /// Progress callback
    typealias FileProgressHandler = (Int64, Int64) -> Void
    typealias BatchProgressHandler = (Int, Int, String) -> Void

    // MARK: - Initialization

    init(bufferSize: Int = 1024 * 1024) {
        self.bufferSize = bufferSize
    }

    // MARK: - Public Methods

    /// Calculate checksum for a single file
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

        // Get file size
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

    /// Batch calculate file checksums
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
                logger.warning("Failed to calculate checksum: \(file.path), error: \(error)")
                // Continue processing other files
            }
        }

        return results
    }

    /// Batch calculate file checksums (parallel version)
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

            // Start initial batch
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

            // Process completed tasks and add new ones
            for await (file, checksum) in group {
                completed += 1
                if let checksum = checksum {
                    resultDict[file] = checksum
                }

                progressHandler?(completed, files.count, file.lastPathComponent)

                // Add next pending file
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

    /// Verify file checksum
    func verify(
        file: URL,
        expectedChecksum: String,
        algorithm: HashAlgorithm = .md5
    ) async throws -> Bool {
        let actualChecksum = try await hash(file: file, algorithm: algorithm)
        return actualChecksum.lowercased() == expectedChecksum.lowercased()
    }

    /// Cancel calculation
    func cancel() {
        isCancelled = true
    }

    // MARK: - Private Methods

    /// Single file hash (for parallel processing)
    private func hashSingle(file: URL, algorithm: HashAlgorithm) async throws -> String {
        guard !isCancelled else { throw HasherError.cancelled }
        return try await hash(file: file, algorithm: algorithm)
    }

    /// MD5 hash
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

            // Check if end of file reached
            if fileHandle.offsetInFile >= fileSize {
                break
            }
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 hash
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

    /// xxHash64 hash (fast non-cryptographic hash)
    private func hashXXHash64(
        fileHandle: FileHandle,
        fileSize: Int64,
        progressHandler: FileProgressHandler?
    ) async throws -> String {
        // Simplified xxHash64 implementation
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

        // Final mix
        hash = hash ^ (hash >> 33)
        hash = hash &* prime2
        hash = hash ^ (hash >> 29)
        hash = hash &* prime5
        hash = hash ^ (hash >> 32)

        return String(format: "%016llx", hash)
    }
}

// MARK: - Hasher Errors

enum HasherError: Error, LocalizedError {
    case fileNotFound(String)
    case cannotOpenFile(String)
    case readError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .cannotOpenFile(let path):
            return "Cannot open file: \(path)"
        case .readError(let path):
            return "Failed to read file: \(path)"
        case .cancelled:
            return "Checksum calculation cancelled"
        }
    }
}

// MARK: - Convenience Extensions

extension FileMetadata {
    /// Calculate and update checksum
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
    /// Batch calculate checksums
    mutating func computeChecksums(
        algorithm: FileHasher.HashAlgorithm = .md5,
        progressHandler: FileHasher.BatchProgressHandler? = nil
    ) async throws {
        let hasher = FileHasher()
        let baseURL = URL(fileURLWithPath: rootPath)

        // Only calculate checksums for files, skip directories
        let filesToHash = files.values.filter { !$0.isDirectory }
        let fileURLs = filesToHash.map { baseURL.appendingPathComponent($0.relativePath) }

        let checksums = try await hasher.hashFilesParallel(
            files: fileURLs,
            algorithm: algorithm,
            progressHandler: progressHandler
        )

        // Update metadata
        for (url, checksum) in checksums {
            let relativePath = url.path.replacingOccurrences(of: rootPath + "/", with: "")
            if var metadata = files[relativePath] {
                metadata.checksum = checksum
                files[relativePath] = metadata
            }
        }
    }
}
