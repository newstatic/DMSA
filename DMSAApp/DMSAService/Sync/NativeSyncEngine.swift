import Foundation
import Combine

/// Native Sync Engine - Complete sync solution replacing rsync
class NativeSyncEngine: ObservableObject {

    // MARK: - Configuration

    struct Config {
        /// Whether to enable checksums
        var enableChecksum: Bool = true

        /// Checksum algorithm
        var checksumAlgorithm: FileHasher.HashAlgorithm = .md5

        /// Verify after copy
        var verifyAfterCopy: Bool = true

        /// Conflict strategy
        var conflictStrategy: ConflictStrategy = .localWinsWithBackup

        /// Backup suffix
        var backupSuffix: String = "_backup"

        /// Enable deletion
        var enableDelete: Bool = true

        /// Buffer size
        var bufferSize: Int = 1024 * 1024

        /// Parallel operations count
        var parallelOperations: Int = 4

        /// Exclude patterns
        var excludePatterns: [String] = []

        /// Include hidden files
        var includeHidden: Bool = false

        /// Maximum file size
        var maxFileSize: Int64? = nil

        /// Follow symbolic links
        var followSymlinks: Bool = false

        /// Enable pause/resume
        var enablePauseResume: Bool = true

        /// State checkpoint interval
        var stateCheckpointInterval: Int = 50

        static var `default`: Config { Config() }
    }

    // MARK: - Components

    private let scanner: FileScanner
    private let hasher: FileHasher
    private let diffEngine: DiffEngine
    private let copier: FileCopier
    private let stateManager: SyncStateManager
    private let conflictResolver: ConflictResolver
    private let lockManager = LockManager.shared

    // MARK: - State

    /// Sync progress
    @Published var progress: ServiceSyncProgress

    /// Current sync plan
    @Published var currentPlan: SyncPlan?

    /// Current state
    var currentState: SyncStateManager.SyncState?

    /// Whether paused
    @Published var isPaused: Bool = false

    /// Whether cancelled
    @Published var isCancelled: Bool = false

    /// Whether syncing
    @Published var isSyncing: Bool = false

    /// Configuration
    var config: Config

    /// Currently locked file paths (for releasing locks after sync completes)
    private var lockedPaths: Set<String> = []
    private let lockedPathsLock = NSLock()

    // MARK: - Progress Callback Throttling

    /// Last progress callback time
    private var lastProgressCallbackTime: Date = .distantPast

    /// Minimum progress callback interval (seconds)
    private let progressCallbackInterval: TimeInterval = 0.1

    /// Last reported progress value
    private var lastReportedProgress: Double = -1

    // MARK: - Delegate

    weak var delegate: NativeSyncEngineDelegate?

    // MARK: - Logger

    private let logger = Logger.forService("NativeSyncEngine")

    // MARK: - Initialization

    init(config: Config = .default) {
        self.config = config
        self.progress = ServiceSyncProgress()

        // Initialize components
        self.scanner = FileScanner(
            excludePatterns: config.excludePatterns,
            includeHidden: config.includeHidden,
            maxFileSize: config.maxFileSize,
            followSymlinks: config.followSymlinks
        )

        self.hasher = FileHasher(bufferSize: config.bufferSize)

        self.diffEngine = DiffEngine()

        self.copier = FileCopier()

        self.stateManager = SyncStateManager()
        self.stateManager.checkpointInterval = config.stateCheckpointInterval

        self.conflictResolver = ConflictResolver(
            defaultStrategy: config.conflictStrategy,
            backupSuffix: config.backupSuffix
        )
    }

    // MARK: - Main Methods

    /// Execute sync task
    func execute(_ task: SyncTask) async throws -> SyncResult {
        guard !isSyncing else {
            throw NativeSyncError.alreadyInProgress
        }

        isSyncing = true
        isCancelled = false
        isPaused = false
        progress.reset()
        progress.start()
        resetProgressThrottle()

        let startTime = Date()

        defer {
            isSyncing = false
            progress.updateElapsedTime()
        }

        // Notify start
        delegate?.nativeSyncEngine(self, didStartTask: task)

        do {
            // Check for resumable state
            if config.enablePauseResume,
               let savedState = try stateManager.loadState(for: task.syncPair.id),
               savedState.isResumable {
                logger.info("Detected resumable sync state, continuing from checkpoint")
                return try await resumeSync(from: savedState, task: task)
            }

            // Phase 1: Scan
            let (sourceSnapshot, destSnapshot) = try await scanPhase(task: task)

            // Check cancelled
            try checkCancelled()

            // Phase 2: Calculate checksums
            var sourceWithChecksum = sourceSnapshot
            var destWithChecksum = destSnapshot

            if config.enableChecksum {
                (sourceWithChecksum, destWithChecksum) = try await checksumPhase(
                    source: sourceSnapshot,
                    destination: destSnapshot
                )
            }

            // Check cancelled
            try checkCancelled()

            // Phase 3: Calculate diff
            let plan = try await diffPhase(
                task: task,
                source: sourceWithChecksum,
                destination: destWithChecksum
            )

            currentPlan = plan

            // Check if there are changes
            if plan.summary.isEmpty {
                logger.info("No sync needed: \(task.syncPair.id)")
                progress.setPhase(.completed)

                return SyncResult(
                    planId: plan.id,
                    startTime: startTime,
                    endTime: Date(),
                    success: true,
                    succeededActions: 0,
                    failedActions: [],
                    filesTransferred: 0,
                    bytesTransferred: 0,
                    filesVerified: 0,
                    verificationFailures: 0,
                    errorMessage: nil,
                    wasCancelled: false,
                    wasResumed: false
                )
            }

            // Phase 4: Resolve conflicts
            var resolvedPlan = plan
            if !plan.conflicts.isEmpty {
                resolvedPlan = try await resolveConflictsPhase(plan: plan)
            }

            // Check cancelled
            try checkCancelled()

            // Create state (for pause/resume)
            if config.enablePauseResume {
                currentState = stateManager.createState(for: resolvedPlan)
            }

            // Phase 5: Execute sync
            let copyResult = try await syncPhase(plan: resolvedPlan)

            // Phase 6: Verify (if enabled)
            var verificationFailures = 0
            if config.verifyAfterCopy {
                verificationFailures = try await verifyPhase(plan: resolvedPlan)
            }

            // Clear state
            if config.enablePauseResume {
                try? stateManager.clearState(for: task.syncPair.id)
            }

            progress.setPhase(.completed)

            let result = SyncResult(
                planId: plan.id,
                startTime: startTime,
                endTime: Date(),
                success: copyResult.failed.isEmpty,
                succeededActions: copyResult.succeeded,
                failedActions: copyResult.failed.map { FailedAction(
                    action: .skip(path: $0.path, reason: .permissionDenied),
                    error: $0.error.localizedDescription,
                    timestamp: Date()
                )},
                filesTransferred: copyResult.succeeded,
                bytesTransferred: copyResult.totalBytes,
                filesVerified: copyResult.verified,
                verificationFailures: verificationFailures,
                errorMessage: copyResult.failed.first?.error.localizedDescription,
                wasCancelled: false,
                wasResumed: false
            )

            delegate?.nativeSyncEngine(self, didCompleteTask: task, result: result)
            return result

        } catch {
            // Ensure all locks are released
            releaseAllLocks()

            progress.setPhase(isCancelled ? .cancelled : .failed)
            progress.lastError = error.localizedDescription

            let result = SyncResult(
                planId: currentPlan?.id ?? UUID(),
                startTime: startTime,
                endTime: Date(),
                success: false,
                succeededActions: progress.processedFiles,
                failedActions: [],
                filesTransferred: progress.processedFiles,
                bytesTransferred: progress.processedBytes,
                filesVerified: 0,
                verificationFailures: 0,
                errorMessage: error.localizedDescription,
                wasCancelled: isCancelled,
                wasResumed: false
            )

            delegate?.nativeSyncEngine(self, didFailTask: task, error: error)
            throw error
        }
    }

    /// Pause sync
    func pause() {
        guard isSyncing else { return }
        isPaused = true
        progress.setPhase(.paused)

        Task {
            await copier.pause()
        }

        // Save state
        if var state = currentState {
            stateManager.updatePhase(state: &state, phase: .paused)
            try? stateManager.saveState(state)
        }

        logger.info("Sync paused")
    }

    /// Resume sync
    func resume() async throws {
        guard isPaused else { return }
        isPaused = false

        await copier.resume()

        logger.info("Sync resumed")
    }

    /// Cancel sync
    func cancel() {
        isCancelled = true
        isPaused = false
        progress.setPhase(.cancelled)

        Task {
            await scanner.cancel()
            await hasher.cancel()
            await copier.cancel()
        }

        // Release all locks
        releaseAllLocks()

        logger.info("Sync cancelled")
    }

    /// Preview sync plan (without executing)
    func preview(_ task: SyncTask) async throws -> SyncPlan {
        // Scan
        let (sourceSnapshot, destSnapshot) = try await scanPhase(task: task)

        // Calculate checksums (if enabled)
        var sourceWithChecksum = sourceSnapshot
        var destWithChecksum = destSnapshot

        if config.enableChecksum {
            (sourceWithChecksum, destWithChecksum) = try await checksumPhase(
                source: sourceSnapshot,
                destination: destSnapshot
            )
        }

        // Calculate diff and generate plan
        return try await diffPhase(
            task: task,
            source: sourceWithChecksum,
            destination: destWithChecksum
        )
    }

    /// Check if there is a resumable sync
    func hasResumableSync(for syncPairId: String) -> Bool {
        return stateManager.hasResumableSync(for: syncPairId)
    }

    /// Get resumable sync summary
    func getResumeSummary(for syncPairId: String) -> String? {
        guard let state = try? stateManager.loadState(for: syncPairId) else {
            return nil
        }
        return stateManager.getResumeSummary(from: state)
    }

    // MARK: - Private Methods - Phase Implementations

    /// Scan phase
    private func scanPhase(task: SyncTask) async throws -> (DirectorySnapshot, DirectorySnapshot) {
        progress.setPhase(.scanning)
        logger.info("Starting scan: \(task.syncPair.id)")

        let sourceURL = URL(fileURLWithPath: task.syncPair.expandedLocalPath)
        let destURL = URL(fileURLWithPath: task.syncPair.externalFullPath(diskMountPath: task.disk.mountPath))

        // Parallel scan source and destination
        async let sourceTask = scanner.scan(directory: sourceURL) { [weak self] count, file in
            self?.progress.currentFile = file
            self?.throttledProgressCallback(message: "Scanning source: \(file)", progress: 0)
        }

        async let destTask = scanner.scan(directory: destURL) { [weak self] count, file in
            self?.progress.currentFile = file
            self?.throttledProgressCallback(message: "Scanning destination: \(file)", progress: 0)
        }

        let (sourceSnapshot, destSnapshot) = try await (sourceTask, destTask)

        progress.totalFiles = sourceSnapshot.fileCount

        logger.info("Scan completed: source \(sourceSnapshot.fileCount) files, destination \(destSnapshot.fileCount) files")

        return (sourceSnapshot, destSnapshot)
    }

    /// Checksum phase
    private func checksumPhase(
        source: DirectorySnapshot,
        destination: DirectorySnapshot
    ) async throws -> (DirectorySnapshot, DirectorySnapshot) {
        progress.setPhase(.checksumming)
        logger.info("Starting checksum calculation")

        var sourceWithChecksum = source
        var destWithChecksum = destination

        let totalFiles = source.files.values.filter { !$0.isDirectory }.count +
                        destination.files.values.filter { !$0.isDirectory }.count
        var processedFiles = 0

        progress.totalFilesToChecksum = totalFiles

        // Calculate source directory checksums
        try await sourceWithChecksum.computeChecksums(
            algorithm: config.checksumAlgorithm
        ) { [weak self] completed, total, file in
            processedFiles = completed
            self?.progress.checksummedFiles = processedFiles
            self?.progress.checksumProgress = Double(processedFiles) / Double(totalFiles)
            self?.progress.checksumPhase = "Source: \(file)"
            self?.throttledProgressCallback(
                message: "Checksumming source: \(file)",
                progress: self?.progress.checksumProgress ?? 0
            )
        }

        // Calculate destination directory checksums
        let sourceCount = source.files.values.filter { !$0.isDirectory }.count
        try await destWithChecksum.computeChecksums(
            algorithm: config.checksumAlgorithm
        ) { [weak self] completed, total, file in
            processedFiles = sourceCount + completed
            self?.progress.checksummedFiles = processedFiles
            self?.progress.checksumProgress = Double(processedFiles) / Double(totalFiles)
            self?.progress.checksumPhase = "Destination: \(file)"
            self?.throttledProgressCallback(
                message: "Checksumming destination: \(file)",
                progress: self?.progress.checksumProgress ?? 0
            )
        }

        logger.info("Checksum calculation completed")

        return (sourceWithChecksum, destWithChecksum)
    }

    /// Diff calculation phase
    private func diffPhase(
        task: SyncTask,
        source: DirectorySnapshot,
        destination: DirectorySnapshot
    ) async throws -> SyncPlan {
        progress.setPhase(.calculating)
        logger.info("Starting diff calculation")

        let options = DiffEngine.DiffOptions(
            compareChecksums: config.enableChecksum,
            detectMoves: true,
            ignorePermissions: false,
            enableDelete: config.enableDelete,
            maxFileSize: config.maxFileSize
        )

        let diffResult = diffEngine.calculateDiff(
            source: source,
            destination: destination,
            direction: task.direction,
            options: options
        )

        logger.info("Diff calculation completed: \(diffResult.summary)")

        let plan = diffEngine.createSyncPlan(
            from: diffResult,
            source: source,
            destination: destination,
            syncPairId: task.syncPair.id,
            direction: task.direction
        )

        // Update progress statistics
        progress.totalFiles = plan.totalFiles
        progress.totalBytes = plan.totalBytes

        return plan
    }

    /// Conflict resolution phase
    private func resolveConflictsPhase(plan: SyncPlan) async throws -> SyncPlan {
        progress.setPhase(.resolving)
        logger.info("Starting to resolve \(plan.conflicts.count) conflicts")

        let resolvedConflicts = await conflictResolver.resolve(conflicts: plan.conflicts)

        var updatedPlan = plan
        updatedPlan.conflicts = resolvedConflicts
        updatedPlan.applyConflictResolutions()

        logger.info("Conflict resolution completed")

        return updatedPlan
    }

    /// Sync execution phase
    private func syncPhase(plan: SyncPlan) async throws -> FileCopier.CopyResult {
        progress.setPhase(.syncing)
        progress.processedFiles = 0
        progress.processedBytes = 0
        logger.info("Starting sync: \(plan.totalFiles) files, \(ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file))")

        // Create directories
        for action in plan.actions {
            if case .createDirectory(let path) = action {
                try await copier.createDirectory(at: URL(fileURLWithPath: path))
            }
        }

        // Execute conflict resolutions
        if !plan.conflicts.isEmpty {
            let conflictResult = try await conflictResolver.executeResolutions(
                plan.conflicts,
                copier: copier
            ) { [weak self] completed, total, file in
                self?.throttledProgressCallback(
                    message: "Resolving conflict: \(file)",
                    progress: Double(completed) / Double(total)
                )
            }
            logger.info("Conflict resolution execution completed: \(conflictResult.summary)")
        }

        // Get virtual paths of files to copy and acquire locks
        let filesToLock = plan.actions.compactMap { action -> (virtualPath: String, sourcePath: String, direction: SyncLockDirection)? in
            switch action {
            case .copy(let source, _, _), .update(let source, _, _):
                // Determine virtual path and lock direction based on sync direction
                let virtualPath = extractVirtualPath(from: source)
                let direction: SyncLockDirection = plan.direction == .localToExternal ? .localToExternal : .externalToLocal
                return (virtualPath, source, direction)
            default:
                return nil
            }
        }

        // Batch acquire locks
        for file in filesToLock {
            if lockManager.acquireLock(file.virtualPath, direction: file.direction, sourcePath: file.sourcePath) {
                addLockedPath(file.virtualPath)
                logger.debug("Acquired sync lock: \(file.virtualPath)")
            } else {
                logger.warning("Cannot acquire sync lock, file may be in use by another operation: \(file.virtualPath)")
            }
        }

        // Copy files
        let copyOptions = FileCopier.CopyOptions(
            preserveAttributes: true,
            verifyAfterCopy: config.verifyAfterCopy,
            verifyAlgorithm: config.checksumAlgorithm,
            bufferSize: config.bufferSize,
            overwriteExisting: true,
            atomicWrite: true
        )

        let result = try await copier.copyFiles(
            actions: plan.actions,
            options: copyOptions,
            progress: progress
        ) { [weak self] progress in
            self?.throttledProgressCallback(
                message: progress.currentFile,
                progress: progress.overallProgress
            )

            // Update state
            if self?.config.enablePauseResume == true,
               var state = self?.currentState {
                self?.stateManager.updateProgress(
                    state: &state,
                    completedIndex: progress.processedFiles - 1,
                    bytes: progress.processedBytes
                )
                self?.currentState = state
            }
        }

        // Release all locks
        releaseAllLocks()

        // Execute deletions
        if config.enableDelete {
            for action in plan.actions {
                if case .delete(let path, _) = action {
                    try await copier.deleteFile(at: URL(fileURLWithPath: path))
                }
            }
        }

        logger.info("Sync execution completed: succeeded \(result.succeeded), failed \(result.failed.count)")

        return result
    }

    // MARK: - Lock Management Helpers

    /// Extract virtual path from file path
    private func extractVirtualPath(from path: String) -> String {
        // Try to extract from Downloads_Local path
        let downloadsLocalPath = Constants.Paths.downloadsLocal.path
        if path.hasPrefix(downloadsLocalPath) {
            return String(path.dropFirst(downloadsLocalPath.count + 1))
        }

        // Try to extract from EXTERNAL path (strip /Volumes/XXX/Downloads/ prefix)
        if path.hasPrefix("/Volumes/") {
            let components = path.split(separator: "/", maxSplits: 4)
            if components.count >= 4 {
                // /Volumes/DiskName/Downloads/file.txt -> file.txt
                return String(components[3...].joined(separator: "/"))
            }
        }

        // Default: return original path
        return path
    }

    /// Add locked path
    private func addLockedPath(_ path: String) {
        lockedPathsLock.lock()
        defer { lockedPathsLock.unlock() }
        lockedPaths.insert(path)
    }

    /// Release all locks
    private func releaseAllLocks() {
        lockedPathsLock.lock()
        let pathsToRelease = lockedPaths
        lockedPaths.removeAll()
        lockedPathsLock.unlock()

        for path in pathsToRelease {
            lockManager.releaseLock(path)
            logger.debug("Released sync lock: \(path)")
        }

        if !pathsToRelease.isEmpty {
            logger.info("Released \(pathsToRelease.count) sync locks")
        }
    }

    /// Verify phase
    private func verifyPhase(plan: SyncPlan) async throws -> Int {
        progress.setPhase(.verifying)
        logger.info("Starting verification")

        var failures = 0
        let filesToVerify = plan.actions.compactMap { action -> (String, String)? in
            switch action {
            case .copy(let source, let dest, _), .update(let source, let dest, _):
                return (source, dest)
            default:
                return nil
            }
        }

        progress.verifiedFiles = 0

        for (index, (source, dest)) in filesToVerify.enumerated() {
            try checkCancelled()

            let sourceURL = URL(fileURLWithPath: source)
            let destURL = URL(fileURLWithPath: dest)

            let sourceChecksum = try await hasher.hash(file: sourceURL, algorithm: config.checksumAlgorithm)
            let destChecksum = try await hasher.hash(file: destURL, algorithm: config.checksumAlgorithm)

            if sourceChecksum != destChecksum {
                failures += 1
                progress.verificationFailures += 1
                logger.error("Verification failed: \(dest)")
            }

            progress.verifiedFiles = index + 1
            progress.verificationProgress = Double(index + 1) / Double(filesToVerify.count)

            throttledProgressCallback(
                message: "Verifying: \(destURL.lastPathComponent)",
                progress: progress.verificationProgress ?? 0
            )
        }

        logger.info("Verification completed: \(filesToVerify.count) files, \(failures) failures")

        return failures
    }

    /// Resume sync from saved state
    private func resumeSync(
        from state: SyncStateManager.SyncState,
        task: SyncTask
    ) async throws -> SyncResult {
        let startTime = Date()

        // Restore progress
        progress = stateManager.restoreProgress(from: state)
        currentState = state
        currentPlan = state.plan

        logger.info("Resuming from checkpoint: completed \(state.completedActionIndices.count)/\(state.plan.actions.count)")

        // Get pending actions
        let pendingActions = stateManager.getPendingActions(from: state)

        // Execute remaining sync
        progress.setPhase(.syncing)

        let copyOptions = FileCopier.CopyOptions(
            preserveAttributes: true,
            verifyAfterCopy: config.verifyAfterCopy,
            verifyAlgorithm: config.checksumAlgorithm,
            bufferSize: config.bufferSize,
            overwriteExisting: true,
            atomicWrite: true
        )

        let result = try await copier.copyFiles(
            actions: pendingActions,
            options: copyOptions,
            progress: progress
        ) { [weak self] progress in
            self?.throttledProgressCallback(
                message: progress.currentFile,
                progress: progress.overallProgress
            )
        }

        // Clear state
        try? stateManager.clearState(for: task.syncPair.id)

        progress.setPhase(.completed)

        return SyncResult(
            planId: state.plan.id,
            startTime: startTime,
            endTime: Date(),
            success: result.failed.isEmpty,
            succeededActions: state.completedActionIndices.count + result.succeeded,
            failedActions: result.failed.map { FailedAction(
                action: .skip(path: $0.path, reason: .permissionDenied),
                error: $0.error.localizedDescription,
                timestamp: Date()
            )},
            filesTransferred: state.processedFiles + result.succeeded,
            bytesTransferred: state.processedBytes + result.totalBytes,
            filesVerified: result.verified,
            verificationFailures: result.verificationFailed.count,
            errorMessage: result.failed.first?.error.localizedDescription,
            wasCancelled: false,
            wasResumed: true
        )
    }

    /// Check if cancelled
    private func checkCancelled() throws {
        if isCancelled {
            throw NativeSyncError.cancelled
        }
    }

    /// Throttled progress callback - Avoids frequent calls causing UI lag
    private func throttledProgressCallback(message: String, progress: Double) {
        let now = Date()

        // Check time interval and progress change
        let timeSinceLastCallback = now.timeIntervalSince(lastProgressCallbackTime)
        let progressDelta = abs(progress - lastReportedProgress)

        // Only callback when enough time has elapsed or progress changed significantly
        guard timeSinceLastCallback >= progressCallbackInterval || progressDelta >= 0.05 else {
            return
        }

        lastProgressCallbackTime = now
        lastReportedProgress = progress

        delegate?.nativeSyncEngine(self, didUpdateProgress: message, progress: progress)
    }

    /// Reset progress callback throttle state
    private func resetProgressThrottle() {
        lastProgressCallbackTime = .distantPast
        lastReportedProgress = -1
    }
}

// MARK: - Delegate Protocol

protocol NativeSyncEngineDelegate: AnyObject {
    /// Sync task started
    func nativeSyncEngine(_ engine: NativeSyncEngine, didStartTask task: SyncTask)

    /// Sync progress updated
    func nativeSyncEngine(_ engine: NativeSyncEngine, didUpdateProgress message: String, progress: Double)

    /// Sync task completed
    func nativeSyncEngine(_ engine: NativeSyncEngine, didCompleteTask task: SyncTask, result: SyncResult)

    /// Sync task failed
    func nativeSyncEngine(_ engine: NativeSyncEngine, didFailTask task: SyncTask, error: Error)
}

// MARK: - Error Types

enum NativeSyncError: Error, LocalizedError {
    case alreadyInProgress
    case cancelled
    case sourceNotFound(String)
    case destinationNotFound(String)
    case permissionDenied(String)
    case insufficientSpace(required: Int64, available: Int64)
    case verificationFailed(path: String)
    case configurationError(String)

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "Sync task already in progress"
        case .cancelled:
            return "Sync cancelled"
        case .sourceNotFound(let path):
            return "Source directory not found: \(path)"
        case .destinationNotFound(let path):
            return "Destination directory not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .insufficientSpace(let required, let available):
            let reqStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Insufficient disk space: required \(reqStr), available \(availStr)"
        case .verificationFailed(let path):
            return "Verification failed: \(path)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}
