import Foundation

/// Sync Task (for internal scheduling)
struct InternalSyncTask: Identifiable {
    let id: String
    let syncPairId: String
    let files: [String]  // Empty means full sync
    var status: SyncStatus
    var progress: SyncProgress?
    var scheduledAt: Date
    var startedAt: Date?
}

/// Sync Manager
/// - Integrates NativeSyncEngine to provide comprehensive sync functionality
/// - Uses ServiceDatabaseManager for persistent sync history
/// - Uses ServiceConfigManager for saving sync state
actor SyncManager {

    private let logger = Logger.forService("Sync")
    private var config: AppConfig?

    // Data persistence
    private let database = ServiceDatabaseManager.shared
    private let configManager = ServiceConfigManager.shared

    // VFSManager reference (for sync lock)
    private var vfsManager: VFSManager?

    // Sync engine (uses NativeSyncEngine)
    private var syncEngine: NativeSyncEngine?

    // Sync state (in-memory cache, periodically persisted)
    private var syncStatuses: [String: SyncStatusInfo] = [:]
    private var syncProgress: [String: SyncProgress] = [:]
    private var pendingTasks: [String: [InternalSyncTask]] = [:]  // [syncPairId: [tasks]]
    private var dirtyFiles: [String: Set<String>] = [:]   // [syncPairId: [virtualPaths]]

    // Scheduler
    private var schedulerTask: Task<Void, Never>?
    private var debounceTimers: [String: Task<Void, Never>] = [:]

    // Configuration
    private let debounceInterval: TimeInterval = 5.0

    // Progress notification throttling
    private var lastProgressNotificationTime: Date = .distantPast
    private let progressNotificationInterval: TimeInterval = 0.2  // Max once per 200ms

    // MARK: - Dependency Injection

    func setVFSManager(_ manager: VFSManager) {
        self.vfsManager = manager
        logger.info("VFSManager injected")
    }

    // MARK: - Lifecycle

    func startScheduler(config: AppConfig?) async {
        self.config = config
        logger.info("Starting sync scheduler")
        logger.info("  Received config: \(config == nil ? "nil" : "valid")")
        if let config = config {
            logger.info("  syncPairs: \(config.syncPairs.map { $0.id })")
            logger.info("  disks: \(config.disks.map { $0.id })")
        }

        // Load sync configuration from config manager
        let serviceConfig = await configManager.getConfig()

        // Initialize sync engine
        let engineConfig = NativeSyncEngine.Config(
            enableChecksum: serviceConfig.sync.enableChecksum,
            checksumAlgorithm: serviceConfig.sync.checksumAlgorithm == "sha256" ? .sha256 : .md5,
            verifyAfterCopy: serviceConfig.sync.verifyAfterCopy,
            conflictStrategy: ConflictStrategy(rawValue: serviceConfig.sync.conflictStrategy) ?? .localWinsWithBackup,
            enableDelete: serviceConfig.sync.enableDelete,
            excludePatterns: serviceConfig.sync.excludePatterns.isEmpty ? Constants.defaultExcludePatterns : serviceConfig.sync.excludePatterns,
            enablePauseResume: true
        )
        syncEngine = NativeSyncEngine(config: engineConfig)

        // Initialize sync pair states
        for syncPair in config?.syncPairs ?? [] {
            // Try to restore state from config manager
            if let savedState = await configManager.getSyncState(syncPairId: syncPair.id) {
                var status = SyncStatusInfo(syncPairId: syncPair.id)
                status.lastSyncTime = savedState.lastSyncTime
                status.dirtyFiles = savedState.dirtyFileCount
                syncStatuses[syncPair.id] = status
            } else {
                syncStatuses[syncPair.id] = SyncStatusInfo(syncPairId: syncPair.id)
            }
            dirtyFiles[syncPair.id] = []
        }

        // Start scheduled sync task
        schedulerTask = Task {
            await runScheduler()
        }
    }

    func resumePendingTasks() async {
        logger.info("Resuming incomplete sync tasks")
        // Load incomplete tasks from persistent storage
        // Can read from database or file here
    }

    func shutdown() async {
        logger.info("Shutting down sync manager")

        // Cancel scheduler
        schedulerTask?.cancel()

        // Cancel all debounce timers
        for timer in debounceTimers.values {
            timer.cancel()
        }
        debounceTimers.removeAll()

        // Save state to config manager
        for (syncPairId, status) in syncStatuses {
            var syncState = SyncState(syncPairId: syncPairId)
            syncState.lastSyncTime = status.lastSyncTime
            syncState.dirtyFileCount = dirtyFiles[syncPairId]?.count ?? 0
            await configManager.setSyncState(syncState)
        }

        // Force save database
        await database.forceSave()

        logger.info("Sync manager shut down")
    }

    func updateConfig(_ config: AppConfig?) async {
        self.config = config

        // Update sync pair states
        for syncPair in config?.syncPairs ?? [] {
            if syncStatuses[syncPair.id] == nil {
                syncStatuses[syncPair.id] = SyncStatusInfo(syncPairId: syncPair.id)
            }
        }
    }

    // MARK: - Scheduler

    private func runScheduler() async {
        logger.info("Sync scheduler started")

        while !Task.isCancelled {
            // Check scheduled syncs
            await checkScheduledSyncs()

            // Process pending task queue
            await processPendingTasks()

            // Sleep for a while
            try? await Task.sleep(nanoseconds: 10_000_000_000)  // 10 seconds
        }

        logger.info("Sync scheduler stopped")
    }

    private func checkScheduledSyncs() async {
        guard let config = config, config.general.autoSyncEnabled else { return }

        for syncPair in config.syncPairs where syncPair.enabled {
            guard var status = syncStatuses[syncPair.id] else { continue }

            // Check if next sync time reached
            if let nextSync = status.nextSyncTime, Date() >= nextSync {
                // Trigger auto sync
                do {
                    try await performSync(syncPairId: syncPair.id, files: [])
                } catch {
                    logger.error("Auto sync failed: \(syncPair.id) - \(error)")
                }

                // Set next sync time (simplified to fixed interval)
                status.nextSyncTime = Date().addingTimeInterval(3600)  // 1 hour later
                syncStatuses[syncPair.id] = status
            }
        }
    }

    private func processPendingTasks() async {
        for (syncPairId, tasks) in pendingTasks {
            guard !tasks.isEmpty else { continue }

            // Get first pending task
            var task = tasks[0]
            task.status = .inProgress
            task.startedAt = Date()

            do {
                try await performSync(syncPairId: syncPairId, files: task.files)
                task.status = .completed

                // Remove completed task
                pendingTasks[syncPairId]?.removeFirst()
            } catch {
                task.status = .failed
                logger.error("Sync task failed: \(task.id) - \(error)")

                // Remove failed task (or could retry)
                pendingTasks[syncPairId]?.removeFirst()
            }
        }
    }

    // MARK: - Sync Control

    func syncNow(syncPairId: String) async throws {
        logger.info("Executing immediate sync: \(syncPairId)")
        logger.info("  Current config: \(config == nil ? "nil" : "valid")")
        if let config = config {
            logger.info("  syncPairs count: \(config.syncPairs.count)")
            logger.info("  disks count: \(config.disks.count)")
        }
        try await performSync(syncPairId: syncPairId, files: [])
    }

    func syncAll() async {
        guard let config = config else {
            logger.warning("syncAll skipped: config is nil")
            return
        }

        for syncPair in config.syncPairs where syncPair.enabled {
            do {
                try await performSync(syncPairId: syncPair.id, files: [])
            } catch {
                logger.error("Sync failed: \(syncPair.id) - \(error)")
            }
        }
    }

    func syncFile(virtualPath: String, syncPairId: String) async throws {
        try await performSync(syncPairId: syncPairId, files: [virtualPath])
    }

    func scheduleFileSync(file: String, syncPairId: String) async {
        // Add to dirty file list
        if dirtyFiles[syncPairId] == nil {
            dirtyFiles[syncPairId] = []
        }
        dirtyFiles[syncPairId]?.insert(file)

        // Update status
        if var status = syncStatuses[syncPairId] {
            status.dirtyFiles = dirtyFiles[syncPairId]?.count ?? 0
            syncStatuses[syncPairId] = status
        }

        // Cancel existing debounce timer
        debounceTimers[syncPairId]?.cancel()

        // Create new debounce timer
        debounceTimers[syncPairId] = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))

            guard !Task.isCancelled else { return }

            // Execute sync
            let filesToSync = Array(self.dirtyFiles[syncPairId] ?? [])
            self.dirtyFiles[syncPairId]?.removeAll()

            if !filesToSync.isEmpty {
                do {
                    try await self.performSync(syncPairId: syncPairId, files: filesToSync)
                } catch {
                    self.logger.error("Debounced sync failed: \(syncPairId) - \(error)")
                }
            }
        }
    }

    func pauseSync(syncPairId: String) async {
        if var status = syncStatuses[syncPairId] {
            status.isPaused = true
            status.status = .paused
            syncStatuses[syncPairId] = status
        }
        // Update progress state
        if var progress = syncProgress[syncPairId] {
            progress.phase = .paused
            syncProgress[syncPairId] = progress
            notifyProgressUpdate(progress)
        }
        // Notify App
        notifySyncStatusChanged(syncPairId: syncPairId, status: .paused, message: "Sync paused")
        logger.info("Sync paused: \(syncPairId)")
    }

    /// Pause all sync pairs
    func pauseAll() async {
        for syncPairId in syncStatuses.keys {
            await pauseSync(syncPairId: syncPairId)
        }
    }

    /// Resume all sync pairs
    func resumeAll() async {
        for syncPairId in syncStatuses.keys {
            await resumeSync(syncPairId: syncPairId)
        }
    }

    func resumeSync(syncPairId: String) async {
        if var status = syncStatuses[syncPairId] {
            status.isPaused = false
            status.status = .inProgress
            syncStatuses[syncPairId] = status
        }
        // Update progress state
        if var progress = syncProgress[syncPairId] {
            progress.phase = .syncing
            syncProgress[syncPairId] = progress
            notifyProgressUpdate(progress)
        }
        // Notify App
        notifySyncStatusChanged(syncPairId: syncPairId, status: .inProgress, message: "Sync resumed")
        logger.info("Sync resumed: \(syncPairId)")
    }

    func cancelSync(syncPairId: String) async {
        // Cancel ongoing sync
        pendingTasks[syncPairId]?.removeAll()

        if var status = syncStatuses[syncPairId] {
            status.status = .cancelled
            syncStatuses[syncPairId] = status
        }
        // Update progress state
        if var progress = syncProgress[syncPairId] {
            progress.phase = .cancelled
            progress.status = .cancelled
            syncProgress[syncPairId] = progress
            notifyProgressUpdate(progress)
        }
        // Notify App
        notifySyncStatusChanged(syncPairId: syncPairId, status: .cancelled, message: "Sync cancelled")
        logger.info("Sync cancelled: \(syncPairId)")
    }

    // MARK: - Sync Execution

    private func performSync(syncPairId: String, files: [String]) async throws {
        // Detailed debug logging
        guard let currentConfig = config else {
            logger.error("performSync failed: config is nil")
            throw SyncError.configurationError("Cannot find sync pair config: config is nil")
        }

        guard let syncPair = currentConfig.syncPairs.first(where: { $0.id == syncPairId }) else {
            logger.error("performSync failed: syncPairId=\(syncPairId) not found")
            logger.error("  Available syncPairs: \(currentConfig.syncPairs.map { $0.id })")
            throw SyncError.configurationError("Cannot find sync pair config: syncPairId mismatch")
        }

        guard let disk = currentConfig.disks.first(where: { $0.id == syncPair.diskId }) else {
            logger.error("performSync failed: diskId=\(syncPair.diskId) not found")
            logger.error("  Available disks: \(currentConfig.disks.map { $0.id })")
            throw SyncError.configurationError("Cannot find sync pair config: diskId mismatch")
        }

        // Check if paused
        if syncStatuses[syncPairId]?.isPaused == true {
            throw SyncError.cancelled
        }

        // Check if disk is connected (check mount point, not specific directory)
        let externalDir = syncPair.fullExternalDir(diskMountPath: disk.mountPath)
        guard FileManager.default.fileExists(atPath: disk.mountPath) else {
            throw SyncError.diskNotConnected(disk.name)
        }

        // Auto-create external directory if it doesn't exist (first sync scenario)
        if !FileManager.default.fileExists(atPath: externalDir) {
            do {
                try FileManager.default.createDirectory(atPath: externalDir, withIntermediateDirectories: true, attributes: nil)
                logger.info("Auto-created external directory: \(externalDir)")
            } catch {
                logger.error("Failed to create external directory: \(externalDir) - \(error)")
                throw SyncError.permissionDenied(path: externalDir)
            }
        }

        // Update status
        var status = syncStatuses[syncPairId] ?? SyncStatusInfo(syncPairId: syncPairId)
        status.status = .inProgress
        syncStatuses[syncPairId] = status

        // Create progress tracker
        var progress = SyncProgress(syncPairId: syncPairId)
        progress.status = .inProgress
        progress.startTime = Date()
        progress.phase = .scanning
        syncProgress[syncPairId] = progress

        // Notify: sync started
        notifySyncStatusChanged(syncPairId: syncPairId, status: .inProgress, message: "Sync started")
        notifyProgressUpdate(progress)

        // Record activity
        await ActivityManager.shared.addSyncActivity(type: .syncStarted, syncPairId: syncPairId, diskId: disk.id)

        // Create history record (using service-side entity)
        var history = ServiceSyncHistory(syncPairId: syncPairId, diskId: disk.id)

        logger.info("Starting sync: \(syncPair.name)")
        logger.info("  LOCAL_DIR: \(syncPair.localDir)")
        logger.info("  EXTERNAL_DIR: \(externalDir)")

        // Determine files to sync (defined outside do block for catch block access)
        let filesToSync: [String]
        if !files.isEmpty {
            // Specific files specified
            filesToSync = files
        } else {
            // Full sync: get files needing sync from file index
            // needsSync = isDirty || localOnly (marked during index build)
            logger.info("Getting files to sync from file index...")
            progress.phase = .scanning
            syncProgress[syncPairId] = progress
            notifyProgressUpdate(progress)

            let entries = await database.getFilesToSync(syncPairId: syncPairId)
            filesToSync = entries.map { entry -> String in
                // virtualPath starts with "/", need to strip it
                let path = entry.virtualPath
                return path.hasPrefix("/") ? String(path.dropFirst()) : path
            }
            logger.info("Got \(filesToSync.count) files to sync from index")
        }

        do {
            let fm = FileManager.default
            let localDir = syncPair.localDir

            // Calculate total bytes
            var totalBytes: Int64 = 0
            for virtualPath in filesToSync {
                let relativePath = virtualPath.hasPrefix("/") ? String(virtualPath.dropFirst()) : virtualPath
                let localPath = (localDir as NSString).appendingPathComponent(relativePath)
                if let attrs = try? fm.attributesOfItem(atPath: localPath),
                   let size = attrs[.size] as? Int64 {
                    totalBytes += size
                }
            }

            progress.totalFiles = filesToSync.count
            progress.totalBytes = totalBytes
            progress.phase = .syncing
            syncProgress[syncPairId] = progress
            notifyProgressUpdate(progress)
            logger.info("Sync total: \(filesToSync.count) files, \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")

            // Execute sync (batch save file records)
            var fileRecordBatch: [ServiceSyncFileRecord] = []
            let batchSize = 100

            for (index, virtualPath) in filesToSync.enumerated() {
                // Check if cancelled
                if syncStatuses[syncPairId]?.status == .cancelled {
                    // Save remaining batch
                    if !fileRecordBatch.isEmpty {
                        await database.saveSyncFileRecords(fileRecordBatch)
                        fileRecordBatch.removeAll()
                    }
                    throw SyncError.cancelled
                }

                // Check if paused, wait for resume
                while syncStatuses[syncPairId]?.isPaused == true {
                    // Check if cancelled while paused
                    if syncStatuses[syncPairId]?.status == .cancelled {
                        if !fileRecordBatch.isEmpty {
                            await database.saveSyncFileRecords(fileRecordBatch)
                            fileRecordBatch.removeAll()
                        }
                        throw SyncError.cancelled
                    }
                    try await Task.sleep(nanoseconds: 500_000_000) // Check every 0.5 seconds
                }

                let relativePath = virtualPath.hasPrefix("/") ? String(virtualPath.dropFirst()) : virtualPath
                let localPath = (localDir as NSString).appendingPathComponent(relativePath)
                let externalPath = (externalDir as NSString).appendingPathComponent(relativePath)

                // Update progress
                progress.currentFile = virtualPath
                progress.processedFiles = index + 1

                // Lock file before sync (blocks write/truncate/delete)
                let vPathForLock = virtualPath.hasPrefix("/") ? virtualPath : "/\(virtualPath)"
                await vfsManager?.lockFileForSync(vPathForLock, syncPairId: syncPairId)

                defer {
                    // Unlock file after sync (success or failure)
                    Task {
                        await self.vfsManager?.unlockFileAfterSync(vPathForLock, syncPairId: syncPairId)
                    }
                }

                do {
                    // Ensure target directory exists
                    let parentDir = (externalPath as NSString).deletingLastPathComponent
                    if !fm.fileExists(atPath: parentDir) {
                        try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                    }

                    // Copy file
                    var fileSize: Int64 = 0
                    if fm.fileExists(atPath: localPath) {
                        if fm.fileExists(atPath: externalPath) {
                            try fm.removeItem(atPath: externalPath)
                        }
                        try fm.copyItem(atPath: localPath, toPath: externalPath)

                        // Get file size
                        if let attrs = try? fm.attributesOfItem(atPath: localPath),
                           let size = attrs[.size] as? Int64 {
                            fileSize = size
                            progress.processedBytes += size
                            history.bytesTransferred += size
                        }

                        // Calculate speed (bytes/second)
                        if let startTime = progress.startTime {
                            let elapsed = Date().timeIntervalSince(startTime)
                            if elapsed > 0 {
                                progress.speed = Int64(Double(progress.processedBytes) / elapsed)
                            }
                        }

                        history.filesUpdated += 1
                        logger.debug("Synced file: \(virtualPath)")
                    }

                    // Clear dirty flag
                    dirtyFiles[syncPairId]?.remove(virtualPath)

                    // Record file sync success
                    let record = ServiceSyncFileRecord(syncPairId: syncPairId, diskId: disk.id, virtualPath: virtualPath, fileSize: fileSize)
                    record.status = 0  // Success
                    fileRecordBatch.append(record)

                } catch {
                    logger.error("Failed to sync file: \(virtualPath) - \(error)")
                    history.filesSkipped += 1

                    // Record file sync failure
                    let record = ServiceSyncFileRecord(syncPairId: syncPairId, diskId: disk.id, virtualPath: virtualPath, fileSize: 0)
                    record.status = 1  // Failed
                    record.errorMessage = error.localizedDescription
                    fileRecordBatch.append(record)
                }

                // Batch save file records
                if fileRecordBatch.count >= batchSize {
                    await database.saveSyncFileRecords(fileRecordBatch)
                    fileRecordBatch.removeAll()
                }

                syncProgress[syncPairId] = progress

                // Push progress in real-time
                notifyProgressUpdate(progress)
            }

            // Save remaining batch
            if !fileRecordBatch.isEmpty {
                await database.saveSyncFileRecords(fileRecordBatch)
                fileRecordBatch.removeAll()
            }

            // Clean up old file sync records
            await database.cleanupOldSyncFileRecords(syncPairId: syncPairId)

            // Sync completed
            progress.status = .completed
            progress.phase = .completed
            progress.endTime = Date()
            syncProgress[syncPairId] = progress

            status.status = .completed
            status.lastSyncTime = Date()
            status.dirtyFiles = dirtyFiles[syncPairId]?.count ?? 0
            syncStatuses[syncPairId] = status

            history.status = SyncStatus.completed.rawValue
            history.endTime = Date()
            history.totalFiles = filesToSync.count

            logger.info("Sync completed: \(syncPair.name), \(history.filesUpdated) files")

            // Send notification: sync completed (via XPC callback)
            notifySyncStatusChanged(syncPairId: syncPairId, status: .completed, message: "Sync completed, \(history.filesUpdated) files")
            notifyProgressUpdate(progress)
            XPCNotifier.notifySyncCompleted(syncPairId: syncPairId, filesCount: history.filesUpdated, bytesCount: history.bytesTransferred)

            // Record activity
            await ActivityManager.shared.addSyncActivity(type: .syncCompleted, syncPairId: syncPairId, diskId: disk.id, filesCount: history.filesUpdated, bytesCount: history.bytesTransferred)

        } catch {
            // Sync failed
            progress.status = .failed
            progress.phase = .failed
            progress.endTime = Date()
            progress.errorMessage = error.localizedDescription
            syncProgress[syncPairId] = progress

            status.status = .failed
            syncStatuses[syncPairId] = status

            history.status = SyncStatus.failed.rawValue
            history.endTime = Date()
            history.errorMessage = error.localizedDescription
            history.totalFiles = filesToSync.count

            logger.error("Sync failed: \(syncPair.name) - \(error)")

            // Send notification: sync failed
            notifySyncStatusChanged(syncPairId: syncPairId, status: .failed, message: error.localizedDescription)
            notifyProgressUpdate(progress)

            // Record activity
            await ActivityManager.shared.addSyncActivity(type: .syncFailed, syncPairId: syncPairId, diskId: disk.id, detail: error.localizedDescription)

            // Save history record even on failure
            await database.saveSyncHistory(history)

            throw error
        }

        // Save history record to database
        await database.saveSyncHistory(history)

        // Update sync state to config manager
        await configManager.markSyncCompleted(syncPairId: syncPairId)
    }

    // MARK: - Status Query

    func getSyncStatus(syncPairId: String) async -> SyncStatusInfo {
        return syncStatuses[syncPairId] ?? SyncStatusInfo(syncPairId: syncPairId)
    }

    func getAllSyncStatus() async -> [SyncStatusInfo] {
        return Array(syncStatuses.values)
    }

    func getSyncProgress(syncPairId: String) async -> SyncProgress? {
        return syncProgress[syncPairId]
    }

    func getPendingQueue(syncPairId: String) async -> [String] {
        return Array(dirtyFiles[syncPairId] ?? [])
    }

    func getSyncHistory(syncPairId: String, limit: Int) async -> [ServiceSyncHistory] {
        return await database.getSyncHistory(syncPairId: syncPairId, limit: limit)
    }

    func getSyncStatistics(syncPairId: String) async -> ServiceSyncStatistics? {
        // Get today's statistics from database
        return await database.getTodayStatistics(syncPairId: syncPairId)
    }

    func getStatisticsForDays(syncPairId: String, days: Int) async -> [ServiceSyncStatistics] {
        return await database.getStatistics(syncPairId: syncPairId, days: days)
    }

    // MARK: - Dirty File Management

    func getDirtyFiles(syncPairId: String) async -> [String] {
        return Array(dirtyFiles[syncPairId] ?? [])
    }

    func markFileDirty(virtualPath: String, syncPairId: String) async {
        if dirtyFiles[syncPairId] == nil {
            dirtyFiles[syncPairId] = []
        }
        dirtyFiles[syncPairId]?.insert(virtualPath)
    }

    func clearFileDirty(virtualPath: String, syncPairId: String) async {
        dirtyFiles[syncPairId]?.remove(virtualPath)
    }

    // MARK: - Disk Events

    func diskConnected(diskName: String, mountPoint: String) async {
        logger.info("Disk connected: \(diskName)")

        // Trigger sync for associated sync pairs
        guard let config = config else { return }

        for syncPair in config.syncPairs {
            guard let disk = config.disks.first(where: { $0.id == syncPair.diskId }),
                  disk.name == diskName else { continue }

            // Resume sync first (it was paused when disk disconnected)
            await resumeSync(syncPairId: syncPair.id)

            // Auto-sync dirty files when disk connects
            if let dirty = dirtyFiles[syncPair.id], !dirty.isEmpty {
                logger.info("Syncing dirty files after disk connect: \(dirty.count) files")
                do {
                    try await performSync(syncPairId: syncPair.id, files: Array(dirty))
                } catch {
                    logger.error("Sync after disk connect failed: \(error)")
                }
            }
        }
    }

    func diskDisconnected(diskName: String) async {
        logger.info("Disk disconnected: \(diskName)")

        // Pause sync for associated sync pairs
        guard let config = config else { return }

        for syncPair in config.syncPairs {
            guard let disk = config.disks.first(where: { $0.id == syncPair.diskId }),
                  disk.name == diskName else { continue }

            await pauseSync(syncPairId: syncPair.id)
        }
    }

    // MARK: - Health Check

    func healthCheck() -> Bool {
        // Check basic state
        return true
    }

    // MARK: - Progress Notifications

    /// Send sync progress notification to App (via XPC callback)
    private func notifyProgressUpdate(_ progress: SyncProgress) {
        // Throttle: avoid overly frequent notifications
        let now = Date()
        guard now.timeIntervalSince(lastProgressNotificationTime) >= progressNotificationInterval else {
            return
        }
        lastProgressNotificationTime = now

        // Send progress via XPC callback
        guard let data = try? JSONEncoder().encode(progress) else {
            return
        }
        XPCNotifier.notifySyncProgress(data: data)
    }

    /// Send sync status change notification (via XPC callback)
    private func notifySyncStatusChanged(syncPairId: String, status: SyncStatus, message: String? = nil) {
        XPCNotifier.notifySyncStatusChanged(syncPairId: syncPairId, status: status, message: message)
    }

    // MARK: - Additional Methods (required by ServiceImplementation)

    func getStatus(syncPairId: String) -> SyncStatusInfo {
        return syncStatuses[syncPairId] ?? SyncStatusInfo(syncPairId: syncPairId)
    }

    func getAllStatus() -> [SyncStatusInfo] {
        return Array(syncStatuses.values)
    }

    func getProgress(syncPairId: String) -> SyncProgress? {
        return syncProgress[syncPairId]
    }

    func getHistory(syncPairId: String, limit: Int) async -> [ServiceSyncHistory] {
        return await database.getSyncHistory(syncPairId: syncPairId, limit: limit)
    }

    func getStatistics(syncPairId: String) async -> ServiceSyncStatistics? {
        return await database.getTodayStatistics(syncPairId: syncPairId)
    }

    func pause(syncPairId: String) {
        Task {
            await pauseSync(syncPairId: syncPairId)
        }
    }

    func resume(syncPairId: String) {
        Task {
            await resumeSync(syncPairId: syncPairId)
        }
    }

    func cancel(syncPairId: String) {
        Task {
            await cancelSync(syncPairId: syncPairId)
        }
    }

    func updateConfig(syncPairId: String, config: SyncPairConfig) {
        // Update single sync pair configuration
        logger.info("Updating sync pair config: \(syncPairId)")
    }

    func stopScheduler() {
        Task {
            await shutdown()
        }
    }

    func waitForCompletion() {
        // Wait for all syncs to complete
        logger.info("Waiting for sync completion...")
    }
}
