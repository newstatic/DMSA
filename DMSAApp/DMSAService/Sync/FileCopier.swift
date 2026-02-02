import Foundation

/// File copier - efficiently copies files with progress tracking
actor FileCopier {

    // MARK: - Configuration

    struct CopyOptions {
        /// Whether to preserve file attributes (permissions, timestamps, etc.)
        var preserveAttributes: Bool = true

        /// Whether to verify checksum after copy
        var verifyAfterCopy: Bool = false

        /// Hash algorithm used for verification
        var verifyAlgorithm: FileHasher.HashAlgorithm = .md5

        /// Buffer size
        var bufferSize: Int = 1024 * 1024  // 1MB

        /// Whether to overwrite existing files
        var overwriteExisting: Bool = true

        /// Whether to use atomic write (write to temp file then rename)
        var atomicWrite: Bool = true

        /// Temporary file suffix
        var tempSuffix: String = ".dmsa_tmp"

        static var `default`: CopyOptions { CopyOptions() }
    }

    /// Copy result
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

    // MARK: - State

    private var isCancelled: Bool = false
    private var isPaused: Bool = false
    private let fileManager = FileManager.default

    // MARK: - Logger

    private let logger = Logger.forService("FileCopier")

    // MARK: - Progress Callback

    typealias FileProgressHandler = (Int64, Int64) -> Void
    typealias BatchProgressHandler = (ServiceSyncProgress) -> Void

    // MARK: - Public Methods

    /// Copy a single file
    func copy(
        from source: URL,
        to destination: URL,
        options: CopyOptions = .default,
        progressHandler: FileProgressHandler? = nil
    ) async throws {
        isCancelled = false

        // Verify source file exists
        guard fileManager.fileExists(atPath: source.path) else {
            throw CopierError.sourceNotFound(source.path)
        }

        // Check if destination already exists
        if fileManager.fileExists(atPath: destination.path) {
            if options.overwriteExisting {
                try fileManager.removeItem(at: destination)
            } else {
                throw CopierError.destinationExists(destination.path)
            }
        }

        // Create destination directory
        let destDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destDir.path) {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        }

        // Get source file attributes
        let sourceAttrs = try fileManager.attributesOfItem(atPath: source.path)
        let fileSize = (sourceAttrs[.size] as? Int64) ?? 0

        // Determine write target
        let writeTarget = options.atomicWrite
            ? destination.appendingPathExtension(options.tempSuffix.replacingOccurrences(of: ".", with: ""))
            : destination

        // Perform copy
        try await copyFileContents(
            from: source,
            to: writeTarget,
            fileSize: fileSize,
            bufferSize: options.bufferSize,
            progressHandler: progressHandler
        )

        // Atomic write: rename temp file
        if options.atomicWrite {
            try fileManager.moveItem(at: writeTarget, to: destination)
        }

        // Preserve attributes
        if options.preserveAttributes {
            try preserveAttributes(from: source, to: destination)
        }

        // Verify
        if options.verifyAfterCopy {
            let hasher = FileHasher()

            let sourceChecksum = try await hasher.hash(file: source, algorithm: options.verifyAlgorithm)
            let destChecksum = try await hasher.hash(file: destination, algorithm: options.verifyAlgorithm)

            if sourceChecksum != destChecksum {
                // Delete corrupted file
                try? fileManager.removeItem(at: destination)
                throw CopierError.verificationFailed(
                    path: destination.path,
                    expected: sourceChecksum,
                    actual: destChecksum
                )
            }
        }
    }

    /// Batch copy files
    func copyFiles(
        actions: [SyncAction],
        options: CopyOptions = .default,
        progress: ServiceSyncProgress,
        progressHandler: BatchProgressHandler? = nil
    ) async throws -> CopyResult {
        isCancelled = false
        isPaused = false

        var result = CopyResult()
        let startTime = Date()

        // Filter copy and update actions
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
            // Check cancellation
            if isCancelled {
                throw CopierError.cancelled
            }

            // Check pause
            while isPaused {
                try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                if isCancelled { throw CopierError.cancelled }
            }

            guard case let .copy(source, destination, metadata) = action else {
                if case let .update(source, destination, metadata) = action {
                    // Handle update action
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

    /// Pause copying
    func pause() {
        isPaused = true
    }

    /// Resume copying
    func resume() {
        isPaused = false
    }

    /// Cancel copying
    func cancel() {
        isCancelled = true
        isPaused = false
    }

    /// Create directory
    func createDirectory(at path: URL) throws {
        try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
    }

    /// Delete file
    func deleteFile(at path: URL) throws {
        guard fileManager.fileExists(atPath: path.path) else { return }
        try fileManager.removeItem(at: path)
    }

    /// Create backup
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

        // If backup already exists, add numeric suffix
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

    // MARK: - Private Methods

    /// Copy file contents
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

        // Create output file
        fileManager.createFile(atPath: destination.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: destination) else {
            throw CopierError.cannotCreateDestination(destination.path)
        }
        defer { try? outputHandle.close() }

        var bytesWritten: Int64 = 0

        while true {
            if isCancelled {
                // Clean up temp file
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

        // Sync to disk
        try outputHandle.synchronize()
    }

    /// Preserve file attributes
    private func preserveAttributes(from source: URL, to destination: URL) throws {
        let attrs = try fileManager.attributesOfItem(atPath: source.path)

        var newAttrs: [FileAttributeKey: Any] = [:]

        // Preserve modification time
        if let modDate = attrs[.modificationDate] {
            newAttrs[.modificationDate] = modDate
        }

        // Preserve creation time
        if let createDate = attrs[.creationDate] {
            newAttrs[.creationDate] = createDate
        }

        // Preserve permissions
        if let permissions = attrs[.posixPermissions] {
            newAttrs[.posixPermissions] = permissions
        }

        if !newAttrs.isEmpty {
            try fileManager.setAttributes(newAttrs, ofItemAtPath: destination.path)
        }
    }

    /// Process a single copy action
    private func processCopyAction(
        source: String,
        destination: String,
        metadata: FileMetadata,
        options: CopyOptions,
        progress: ServiceSyncProgress,
        result: inout CopyResult
    ) async {
        let sourceURL = URL(fileURLWithPath: source)
        let destURL = URL(fileURLWithPath: destination)

        progress.currentFile = metadata.fileName

        do {
            try await copy(
                from: sourceURL,
                to: destURL,
                options: options
            ) { bytesTransferred, totalSize in
                // Progress tracking handled by caller
            }

            result.succeeded += 1
            result.totalBytes += metadata.size
            progress.processedFiles += 1
            progress.processedBytes += metadata.size

            if options.verifyAfterCopy {
                result.verified += 1
            }

        } catch CopierError.verificationFailed(let path, let expected, let actual) {
            result.verificationFailed.append((path, expected, actual))
            progress.errorMessage = "Verification failed: \(source)"
        } catch {
            result.failed.append((source, error))
            progress.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Copier Error

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
            return "Source file not found: \(path)"
        case .destinationExists(let path):
            return "Destination file already exists: \(path)"
        case .cannotOpenSource(let path):
            return "Cannot open source file: \(path)"
        case .cannotCreateDestination(let path):
            return "Cannot create destination file: \(path)"
        case .writeError(let path):
            return "Write error: \(path)"
        case .verificationFailed(let path, let expected, let actual):
            return "Verification failed: \(path) (expected: \(expected.prefix(8))..., actual: \(actual.prefix(8))...)"
        case .cancelled:
            return "Copy cancelled"
        case .insufficientSpace(let required, let available):
            let reqStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Insufficient space: required \(reqStr), available \(availStr)"
        }
    }
}
