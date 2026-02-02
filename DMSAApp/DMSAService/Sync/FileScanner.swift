import Foundation

/// File Scanner - Traverses directories and collects file metadata
actor FileScanner {
    // MARK: - Configuration

    /// Exclude pattern list
    private var excludePatterns: [String] = []

    /// Whether to include hidden files
    private var includeHidden: Bool = false

    /// Maximum file size limit (nil means no limit)
    private var maxFileSize: Int64?

    /// Whether to follow symbolic links
    private var followSymlinks: Bool = false

    // MARK: - State

    /// Whether cancelled
    private var isCancelled: Bool = false

    /// Scan progress callback
    typealias ProgressHandler = (Int, String) -> Void

    // MARK: - Logger

    private let logger = Logger.forService("FileScanner")

    // MARK: - Initialization

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

    // MARK: - Public Methods

    /// Scan directory and generate file metadata snapshot
    func scan(
        directory: URL,
        progressHandler: ProgressHandler? = nil
    ) async throws -> DirectorySnapshot {
        isCancelled = false

        let fileManager = FileManager.default

        // Verify directory exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ScannerError.directoryNotFound(directory.path)
        }

        var snapshot = DirectorySnapshot(rootPath: directory.path)
        var fileCount = 0

        // Create directory enumerator
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

        // Enumerate all files
        for case let fileURL as URL in enumerator {
            // Check cancellation
            if isCancelled {
                throw ScannerError.cancelled
            }

            // Get relative path
            let relativePath = fileURL.path.replacingOccurrences(
                of: directory.path + "/",
                with: ""
            )

            // Check exclusion rules
            if shouldExclude(relativePath: relativePath, url: fileURL) {
                enumerator.skipDescendants()
                continue
            }

            // Get file metadata
            do {
                let metadata = try FileMetadata.from(url: fileURL, relativeTo: directory)

                // Check file size limit
                if let maxSize = maxFileSize, !metadata.isDirectory && metadata.size > maxSize {
                    continue
                }

                snapshot.update(metadata)
                fileCount += 1

                // Progress callback
                progressHandler?(fileCount, relativePath)

            } catch {
                // Log error but continue scanning
                logger.warning("Failed to scan file: \(fileURL.path), error: \(error)")
            }
        }

        return snapshot
    }

    /// Incremental scan - Based on previous snapshot, only scan changed files
    func incrementalScan(
        directory: URL,
        previousSnapshot: DirectorySnapshot,
        progressHandler: ProgressHandler? = nil
    ) async throws -> DirectorySnapshot {
        isCancelled = false

        let fileManager = FileManager.default
        var newSnapshot = DirectorySnapshot(rootPath: directory.path)
        var fileCount = 0

        // Get file list from last scan
        let previousFiles = Set(previousSnapshot.files.keys)
        var currentFiles = Set<String>()

        // Create directory enumerator
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

            // Check if rescan needed
            if let previousMeta = previousSnapshot.metadata(for: relativePath) {
                // Quick check: compare modification time and size
                let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
                let mtime = attrs?[.modificationDate] as? Date
                let size = attrs?[.size] as? Int64

                if let mtime = mtime, let size = size,
                   abs(mtime.timeIntervalSince(previousMeta.modifiedTime)) < 1.0 &&
                   size == previousMeta.size {
                    // File unchanged, reuse old metadata
                    newSnapshot.update(previousMeta)
                    fileCount += 1
                    progressHandler?(fileCount, relativePath)
                    continue
                }
            }

            // Need to fetch full metadata
            do {
                let metadata = try FileMetadata.from(url: fileURL, relativeTo: directory)

                if let maxSize = maxFileSize, !metadata.isDirectory && metadata.size > maxSize {
                    continue
                }

                newSnapshot.update(metadata)
                fileCount += 1
                progressHandler?(fileCount, relativePath)

            } catch {
                logger.warning("Incremental scan failed for file: \(fileURL.path), error: \(error)")
            }
        }

        // Mark deleted files (optional: not adding to new snapshot means they naturally don't exist)
        let deletedFiles = previousFiles.subtracting(currentFiles)
        if !deletedFiles.isEmpty {
            logger.info("Detected \(deletedFiles.count) deleted files")
        }

        return newSnapshot
    }

    /// Cancel scan
    func cancel() {
        isCancelled = true
    }

    /// Update configuration
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

    // MARK: - Private Methods

    /// Check if file should be excluded
    private func shouldExclude(relativePath: String, url: URL) -> Bool {
        let fileName = url.lastPathComponent

        // Check hidden files
        if !includeHidden && fileName.hasPrefix(".") {
            return true
        }

        // Check exclude patterns
        for pattern in excludePatterns {
            if matchesPattern(relativePath, pattern: pattern) ||
               matchesPattern(fileName, pattern: pattern) {
                return true
            }
        }

        return false
    }

    /// Simple glob pattern matching
    private func matchesPattern(_ string: String, pattern: String) -> Bool {
        // Handle simple glob patterns
        if pattern == string {
            return true
        }

        // Handle * wildcard
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

// MARK: - Scanner Errors

enum ScannerError: Error, LocalizedError {
    case directoryNotFound(String)
    case enumerationFailed(String)
    case permissionDenied(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .directoryNotFound(let path):
            return "Directory not found: \(path)"
        case .enumerationFailed(let path):
            return "Failed to enumerate directory: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .cancelled:
            return "Scan cancelled"
        }
    }
}
