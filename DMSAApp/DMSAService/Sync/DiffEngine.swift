import Foundation

/// Diff Calculation Engine - Compares two directory snapshots and generates a sync plan
class DiffEngine {

    // MARK: - Configuration

    struct DiffOptions {
        /// Whether to compare checksums
        var compareChecksums: Bool = false

        /// Whether to detect file moves
        var detectMoves: Bool = true

        /// Whether to ignore permission differences
        var ignorePermissions: Bool = false

        /// Whether to ignore ownership differences
        var ignoreOwnership: Bool = true

        /// Time tolerance (seconds) - files with modification times within this range are considered identical
        var timeTolerance: TimeInterval = 2.0

        /// Whether to enable deletion
        var enableDelete: Bool = true

        /// Maximum file size (nil means no limit)
        var maxFileSize: Int64? = nil

        static var `default`: DiffOptions { DiffOptions() }
    }

    // MARK: - Result Types

    struct DiffResult {
        /// Files to copy (exists in source, not in destination)
        var toCopy: [String] = []

        /// Files to update (exists in both but different)
        var toUpdate: [String] = []

        /// Files to delete (not in source, exists in destination)
        var toDelete: [String] = []

        /// Conflicting files (need special handling)
        var conflicts: [String] = []

        /// Identical files (no action needed)
        var identical: [String] = []

        /// Detected move operations (from -> to)
        var moves: [(from: String, to: String)] = []

        /// Directories to create
        var directoriesToCreate: [String] = []

        /// Directories to delete
        var directoriesToDelete: [String] = []

        /// Skipped files with reasons
        var skipped: [(path: String, reason: SkipReason)] = []

        // MARK: - Statistics

        var totalChanges: Int {
            toCopy.count + toUpdate.count + toDelete.count + moves.count
        }

        var hasChanges: Bool {
            totalChanges > 0 || directoriesToCreate.count > 0
        }

        var summary: String {
            var parts: [String] = []
            if !toCopy.isEmpty { parts.append("added \(toCopy.count)") }
            if !toUpdate.isEmpty { parts.append("updated \(toUpdate.count)") }
            if !toDelete.isEmpty { parts.append("deleted \(toDelete.count)") }
            if !moves.isEmpty { parts.append("moved \(moves.count)") }
            if !conflicts.isEmpty { parts.append("conflicts \(conflicts.count)") }
            if parts.isEmpty { return "no changes" }
            return parts.joined(separator: ", ")
        }
    }

    // MARK: - Public Methods

    /// Calculate diff between two directory snapshots
    func calculateDiff(
        source: DirectorySnapshot,
        destination: DirectorySnapshot,
        direction: SyncDirection,
        options: DiffOptions = .default
    ) -> DiffResult {
        var result = DiffResult()

        let sourceFiles = source.files
        let destFiles = destination.files

        let sourceKeys = Set(sourceFiles.keys)
        let destKeys = Set(destFiles.keys)

        // Process based on sync direction
        switch direction {
        case .localToExternal, .externalToLocal:
            // Unidirectional sync
            calculateUnidirectionalDiff(
                sourceFiles: sourceFiles,
                destFiles: destFiles,
                sourceKeys: sourceKeys,
                destKeys: destKeys,
                options: options,
                result: &result
            )

        case .bidirectional:
            // Bidirectional sync - needs conflict detection
            calculateBidirectionalDiff(
                sourceFiles: sourceFiles,
                destFiles: destFiles,
                sourceKeys: sourceKeys,
                destKeys: destKeys,
                options: options,
                result: &result
            )
        }

        // Detect move operations
        if options.detectMoves {
            detectMoves(result: &result, sourceFiles: sourceFiles, destFiles: destFiles)
        }

        // Sort directory creation order (parent directories first)
        result.directoriesToCreate.sort()

        // Sort directory deletion order (child directories first)
        result.directoriesToDelete.sort(by: >)

        return result
    }

    /// Generate sync plan from diff result
    func createSyncPlan(
        from diffResult: DiffResult,
        source: DirectorySnapshot,
        destination: DirectorySnapshot,
        syncPairId: String,
        direction: SyncDirection
    ) -> SyncPlan {
        var plan = SyncPlan(
            syncPairId: syncPairId,
            direction: direction,
            sourcePath: source.rootPath,
            destinationPath: destination.rootPath
        )

        // Add directory creation actions
        for dir in diffResult.directoriesToCreate {
            plan.addAction(.createDirectory(path: dir))
        }

        // Add copy actions
        for path in diffResult.toCopy {
            if let metadata = source.metadata(for: path) {
                let sourcePath = (source.rootPath as NSString).appendingPathComponent(path)
                let destPath = (destination.rootPath as NSString).appendingPathComponent(path)
                plan.addAction(.copy(source: sourcePath, destination: destPath, metadata: metadata))
            }
        }

        // Add update actions
        for path in diffResult.toUpdate {
            if let metadata = source.metadata(for: path) {
                let sourcePath = (source.rootPath as NSString).appendingPathComponent(path)
                let destPath = (destination.rootPath as NSString).appendingPathComponent(path)
                plan.addAction(.update(source: sourcePath, destination: destPath, metadata: metadata))
            }
        }

        // Add delete actions
        for path in diffResult.toDelete {
            if let metadata = destination.metadata(for: path) {
                let destPath = (destination.rootPath as NSString).appendingPathComponent(path)
                plan.addAction(.delete(path: destPath, metadata: metadata))
            }
        }

        // Add conflicts
        for path in diffResult.conflicts {
            let localMeta = source.metadata(for: path)
            let externalMeta = destination.metadata(for: path)

            let conflict = ConflictInfo(
                relativePath: path,
                localPath: (source.rootPath as NSString).appendingPathComponent(path),
                externalPath: (destination.rootPath as NSString).appendingPathComponent(path),
                localMetadata: localMeta,
                externalMetadata: externalMeta,
                conflictType: determineConflictType(local: localMeta, external: externalMeta)
            )

            plan.addConflict(conflict)
            plan.addAction(.resolveConflict(conflict: conflict))
        }

        // Add skip actions
        for (path, reason) in diffResult.skipped {
            plan.addAction(.skip(path: path, reason: reason))
        }

        // Save snapshots for later use
        plan.sourceSnapshot = source
        plan.destinationSnapshot = destination

        return plan
    }

    // MARK: - Private Methods

    /// Unidirectional sync diff calculation
    private func calculateUnidirectionalDiff(
        sourceFiles: [String: FileMetadata],
        destFiles: [String: FileMetadata],
        sourceKeys: Set<String>,
        destKeys: Set<String>,
        options: DiffOptions,
        result: inout DiffResult
    ) {
        // In source but not in destination -> copy
        let newFiles = sourceKeys.subtracting(destKeys)
        for path in newFiles {
            guard let meta = sourceFiles[path] else { continue }

            // Check file size limit
            if let maxSize = options.maxFileSize, meta.size > maxSize {
                result.skipped.append((path, .tooLarge))
                continue
            }

            if meta.isDirectory {
                result.directoriesToCreate.append(path)
            } else {
                result.toCopy.append(path)
            }
        }

        // Not in source but in destination -> delete (if enabled)
        if options.enableDelete {
            let removedFiles = destKeys.subtracting(sourceKeys)
            for path in removedFiles {
                if let meta = destFiles[path] {
                    if meta.isDirectory {
                        result.directoriesToDelete.append(path)
                    } else {
                        result.toDelete.append(path)
                    }
                }
            }
        }

        // In both -> check if update needed
        let commonFiles = sourceKeys.intersection(destKeys)
        for path in commonFiles {
            guard let sourceMeta = sourceFiles[path],
                  let destMeta = destFiles[path] else { continue }

            // Skip directories
            if sourceMeta.isDirectory && destMeta.isDirectory {
                continue
            }

            // Type mismatch
            if sourceMeta.isDirectory != destMeta.isDirectory {
                result.conflicts.append(path)
                continue
            }

            // Compare if identical
            if areFilesIdentical(sourceMeta, destMeta, options: options) {
                result.identical.append(path)
            } else {
                result.toUpdate.append(path)
            }
        }
    }

    /// Bidirectional sync diff calculation
    private func calculateBidirectionalDiff(
        sourceFiles: [String: FileMetadata],
        destFiles: [String: FileMetadata],
        sourceKeys: Set<String>,
        destKeys: Set<String>,
        options: DiffOptions,
        result: inout DiffResult
    ) {
        // In source but not in destination -> copy to destination
        let newInSource = sourceKeys.subtracting(destKeys)
        for path in newInSource {
            guard let meta = sourceFiles[path] else { continue }

            if let maxSize = options.maxFileSize, meta.size > maxSize {
                result.skipped.append((path, .tooLarge))
                continue
            }

            if meta.isDirectory {
                result.directoriesToCreate.append(path)
            } else {
                result.toCopy.append(path)
            }
        }

        // Not in source but in destination -> copy from destination to source (or mark conflict)
        let newInDest = destKeys.subtracting(sourceKeys)
        for path in newInDest {
            // In bidirectional sync, new files in destination may be ones the user wants to keep
            // Mark as needing sync from destination to source
            result.conflicts.append(path)
        }

        // In both -> detect conflicts
        let commonFiles = sourceKeys.intersection(destKeys)
        for path in commonFiles {
            guard let sourceMeta = sourceFiles[path],
                  let destMeta = destFiles[path] else { continue }

            if sourceMeta.isDirectory && destMeta.isDirectory {
                continue
            }

            if sourceMeta.isDirectory != destMeta.isDirectory {
                result.conflicts.append(path)
                continue
            }

            if areFilesIdentical(sourceMeta, destMeta, options: options) {
                result.identical.append(path)
            } else {
                // In bidirectional sync, different on both sides -> conflict
                result.conflicts.append(path)
            }
        }
    }

    /// Compare if two files are identical
    private func areFilesIdentical(
        _ source: FileMetadata,
        _ dest: FileMetadata,
        options: DiffOptions
    ) -> Bool {
        // Size must be identical
        if source.size != dest.size {
            return false
        }

        // Compare modification time (with tolerance)
        let timeDiff = abs(source.modifiedTime.timeIntervalSince(dest.modifiedTime))
        if timeDiff > options.timeTolerance {
            return false
        }

        // If checksum comparison enabled and both have checksums
        if options.compareChecksums,
           let sourceChecksum = source.checksum,
           let destChecksum = dest.checksum {
            return sourceChecksum.lowercased() == destChecksum.lowercased()
        }

        // Compare permissions (optional)
        if !options.ignorePermissions && source.permissions != dest.permissions {
            return false
        }

        return true
    }

    /// Detect file moves
    private func detectMoves(
        result: inout DiffResult,
        sourceFiles: [String: FileMetadata],
        destFiles: [String: FileMetadata]
    ) {
        // Build checksum index
        var destChecksumIndex: [String: [String]] = [:]
        for (path, meta) in destFiles {
            if let checksum = meta.checksum, !meta.isDirectory {
                destChecksumIndex[checksum, default: []].append(path)
            }
        }

        var detectedMoves: [(from: String, to: String)] = []
        var movedPaths: Set<String> = []

        // Detect "new" becoming "moved"
        for path in result.toCopy {
            guard let meta = sourceFiles[path],
                  let checksum = meta.checksum,
                  let candidates = destChecksumIndex[checksum] else { continue }

            // Check if deletion list contains file with same checksum
            for candidate in candidates {
                if result.toDelete.contains(candidate) && !movedPaths.contains(candidate) {
                    // Move detected
                    detectedMoves.append((from: candidate, to: path))
                    movedPaths.insert(candidate)
                    movedPaths.insert(path)
                    break
                }
            }
        }

        // Update result
        if !detectedMoves.isEmpty {
            result.moves = detectedMoves

            // Remove detected moves from copy and delete lists
            let movedFromPaths = Set(detectedMoves.map { $0.from })
            let movedToPaths = Set(detectedMoves.map { $0.to })

            result.toCopy.removeAll { movedToPaths.contains($0) }
            result.toDelete.removeAll { movedFromPaths.contains($0) }
        }
    }

    /// Determine conflict type
    private func determineConflictType(
        local: FileMetadata?,
        external: FileMetadata?
    ) -> ConflictType {
        switch (local, external) {
        case (nil, _):
            return .deletedOnLocal
        case (_, nil):
            return .deletedOnExternal
        case let (l?, e?) where l.isDirectory != e.isDirectory:
            return .typeChanged
        default:
            return .bothModified
        }
    }
}

// MARK: - Convenience Methods

extension DiffEngine {
    /// Quick compare two directories
    static func quickCompare(
        source: URL,
        destination: URL,
        excludePatterns: [String] = []
    ) async throws -> DiffResult {
        let scanner = FileScanner(excludePatterns: excludePatterns)

        async let sourceSnapshot = scanner.scan(directory: source)
        async let destSnapshot = scanner.scan(directory: destination)

        let engine = DiffEngine()
        return engine.calculateDiff(
            source: try await sourceSnapshot,
            destination: try await destSnapshot,
            direction: .localToExternal
        )
    }
}
