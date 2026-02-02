import Foundation

/// Eviction statistics
struct EvictionStats: Codable, Sendable {
    var evictedCount: Int
    var evictedSize: Int64
    var lastEvictionTime: Date?
    var skippedDirty: Int
    var skippedLocked: Int
    var failedSync: Int
}

/// Eviction result
struct EvictionResult: Sendable {
    let evictedFiles: [String]
    let freedSpace: Int64
    let errors: [String]
}

/// LRU Eviction Manager
/// Responsible for cleaning up synced files when local space is low
actor EvictionManager {

    private let logger = Logger.forService("Eviction")

    /// Eviction config
    struct Config {
        /// Eviction trigger threshold (when available space falls below this)
        var triggerThreshold: Int64 = 5 * 1024 * 1024 * 1024  // 5GB
        /// Target free space (evict until this level)
        var targetFreeSpace: Int64 = 10 * 1024 * 1024 * 1024  // 10GB
        /// Maximum files per eviction run
        var maxFilesPerRun: Int = 100
        /// Minimum file age (seconds) - prevents evicting newly created files
        var minFileAge: TimeInterval = 3600  // 1 hour
        /// Whether auto eviction is enabled
        var autoEvictionEnabled: Bool = true
        /// Auto check interval (seconds)
        var checkInterval: TimeInterval = 300  // 5 minutes
    }

    private var config = Config()
    private var stats = EvictionStats(
        evictedCount: 0,
        evictedSize: 0,
        lastEvictionTime: nil,
        skippedDirty: 0,
        skippedLocked: 0,
        failedSync: 0
    )

    private weak var vfsManager: VFSManager?
    private weak var syncManager: SyncManager?

    private var checkTimer: DispatchSourceTimer?
    private var isRunning = false

    // MARK: - Initialization

    func setManagers(vfs: VFSManager, sync: SyncManager) {
        self.vfsManager = vfs
        self.syncManager = sync
    }

    func updateConfig(_ newConfig: Config) {
        self.config = newConfig
    }

    func getConfig() -> Config {
        return config
    }

    func getStats() -> EvictionStats {
        return stats
    }

    // MARK: - Auto Eviction

    func startAutoEviction() {
        guard config.autoEvictionEnabled else {
            logger.info("Auto eviction is disabled")
            return
        }

        stopAutoEviction()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + config.checkInterval, repeating: config.checkInterval)
        timer.setEventHandler { [weak self] in
            Task {
                guard let self = self else {
                    Logger.forService("Eviction").warning("Eviction timer: self has been deallocated")
                    return
                }
                await self.checkAndEvictIfNeeded()
            }
        }
        timer.resume()
        checkTimer = timer

        logger.info("Auto eviction started, check interval: \(Int(config.checkInterval))s")
    }

    func stopAutoEviction() {
        checkTimer?.cancel()
        checkTimer = nil
        logger.info("Auto eviction stopped")
    }

    // MARK: - Eviction Logic

    /// Check and evict if needed
    /// Criteria: LOCAL_DIR total file size (index stats) > triggerThreshold
    func checkAndEvictIfNeeded() async {
        logger.info("========== Eviction check start ==========")

        guard !isRunning else {
            logger.info("Eviction check: skipped (previous eviction still running)")
            return
        }

        guard let vfsManager = vfsManager else {
            logger.warning("Eviction check: skipped (VFSManager not set, may have been deallocated)")
            return
        }

        // Get all mount points
        let mounts = await vfsManager.getAllMounts()
        logger.info("Eviction check: mount count=\(mounts.count), cache limit=\(formatBytes(config.triggerThreshold))")

        if mounts.isEmpty {
            logger.info("Eviction check: no mount points, skipping")
            return
        }

        let database = ServiceDatabaseManager.shared

        for mount in mounts {
            // LOCAL file actual usage based on index stats
            let stats = await database.getIndexStats(syncPairId: mount.syncPairId)
            let localSize = stats.localSize
            let needsEviction = localSize > config.triggerThreshold

            logger.info("Eviction check: syncPair=\(mount.syncPairId), local usage=\(formatBytes(localSize)), cache limit=\(formatBytes(config.triggerThreshold)), needs eviction=\(needsEviction)")

            if needsEviction {
                logger.info("Triggering eviction: \(mount.syncPairId), target down to \(formatBytes(config.targetFreeSpace))")

                let result = await evict(
                    syncPairId: mount.syncPairId,
                    targetFreeSpace: config.targetFreeSpace
                )

                logger.info("Eviction complete: freed \(formatBytes(result.freedSpace)), evicted \(result.evictedFiles.count) files, errors \(result.errors.count)")
            }
        }

        logger.info("========== Eviction check end ==========")
    }

    /// Execute eviction
    /// - Parameters:
    ///   - syncPairId: Sync pair ID
    ///   - targetFreeSpace: Target free space (optional, defaults to config)
    /// - Returns: Eviction result
    func evict(syncPairId: String, targetFreeSpace: Int64? = nil) async -> EvictionResult {
        isRunning = true
        defer { isRunning = false }

        let target = targetFreeSpace ?? config.targetFreeSpace
        var evictedFiles: [String] = []
        var freedSpace: Int64 = 0
        var errors: [String] = []

        guard let vfsManager = vfsManager else {
            errors.append("VFSManager not set")
            return EvictionResult(evictedFiles: [], freedSpace: 0, errors: errors)
        }

        // Get mount point info
        let mounts = await vfsManager.getAllMounts()
        guard let mount = mounts.first(where: { $0.syncPairId == syncPairId }) else {
            errors.append("Sync pair not mounted: \(syncPairId)")
            return EvictionResult(evictedFiles: [], freedSpace: 0, errors: errors)
        }

        // Get LOCAL actual usage based on index stats
        let database = ServiceDatabaseManager.shared
        let indexStats = await database.getIndexStats(syncPairId: syncPairId)
        var currentLocalSize = indexStats.localSize

        logger.info("Starting eviction: local usage \(formatBytes(currentLocalSize)), target down to \(formatBytes(target))")

        // Get evictable file list (sorted by LRU)
        let candidates = await getEvictionCandidates(syncPairId: syncPairId)

        logger.info("Found \(candidates.count) candidate files")

        let fm = FileManager.default
        var processedCount = 0

        for entry in candidates {
            // Check if target reached (local usage below target)
            if currentLocalSize <= target {
                logger.info("Target reached: local usage \(formatBytes(currentLocalSize)) <= \(formatBytes(target))")
                break
            }

            // Check per-run limit
            if processedCount >= config.maxFilesPerRun {
                logger.info("Per-run max file count limit reached")
                break
            }

            // Skip directories
            if entry.isDirectory { continue }

            // Skip dirty files (need sync first)
            if entry.isDirty {
                stats.skippedDirty += 1
                continue
            }

            // Skip locked files
            if entry.isLocked {
                stats.skippedLocked += 1
                continue
            }

            // Skip files that are too new
            let fileAge = Date().timeIntervalSince(entry.accessedAt)
            if fileAge < config.minFileAge {
                continue
            }

            // Ensure file exists in EXTERNAL
            guard let externalPath = entry.externalPath,
                  fm.fileExists(atPath: externalPath) else {
                // Need to sync to EXTERNAL first
                if let syncManager = syncManager {
                    do {
                        try await syncManager.syncFile(virtualPath: entry.virtualPath, syncPairId: entry.syncPairId)
                        // Skip eviction after sync success, handle in next check
                        continue
                    } catch {
                        stats.failedSync += 1
                        errors.append("Sync failed: \(entry.virtualPath) - \(error.localizedDescription)")
                        continue
                    }
                } else {
                    errors.append("SyncManager not set: \(entry.virtualPath)")
                    continue
                }
            }

            // Execute eviction (delete local copy)
            guard let localPath = entry.localPath else { continue }

            do {
                let fileSize = entry.size
                try fm.removeItem(atPath: localPath)

                evictedFiles.append(entry.virtualPath)
                freedSpace += fileSize
                currentLocalSize -= fileSize
                processedCount += 1

                // Update index (location becomes externalOnly)
                await updateEntryLocation(entry: entry, vfsManager: vfsManager)

                // Record eviction success
                let record = ServiceSyncFileRecord(syncPairId: syncPairId, diskId: "", virtualPath: entry.virtualPath, fileSize: fileSize)
                record.status = 3  // Eviction success
                await ServiceDatabaseManager.shared.saveSyncFileRecord(record)

                logger.debug("Evicted: \(entry.virtualPath) (\(formatBytes(fileSize)))")

            } catch {
                errors.append("Delete failed: \(entry.virtualPath) - \(error.localizedDescription)")

                // Record eviction failure
                let record = ServiceSyncFileRecord(syncPairId: syncPairId, diskId: "", virtualPath: entry.virtualPath, fileSize: 0)
                record.status = 4  // Eviction failure
                record.errorMessage = error.localizedDescription
                await ServiceDatabaseManager.shared.saveSyncFileRecord(record)
            }
        }

        // Update statistics
        stats.evictedCount += evictedFiles.count
        stats.evictedSize += freedSpace
        stats.lastEvictionTime = Date()

        // Record activity
        if !evictedFiles.isEmpty || !errors.isEmpty {
            await ActivityManager.shared.addEvictionActivity(
                filesCount: evictedFiles.count,
                bytesCount: freedSpace,
                syncPairId: syncPairId,
                failed: evictedFiles.isEmpty && !errors.isEmpty
            )
        }

        return EvictionResult(evictedFiles: evictedFiles, freedSpace: freedSpace, errors: errors)
    }

    /// Get eviction candidates (sorted by LRU)
    private func getEvictionCandidates(syncPairId: String) async -> [ServiceFileEntry] {
        guard let vfsManager = vfsManager else { return [] }

        // Get all index entries
        let allStats = await vfsManager.getIndexStats(syncPairId: syncPairId)
        guard allStats != nil else { return [] }

        // Get files with BOTH status (safe to evict)
        var candidates: [ServiceFileEntry] = []

        let mounts = await vfsManager.getAllMounts()
        guard let mount = mounts.first(where: { $0.syncPairId == syncPairId }) else {
            return []
        }

        // Scan local directory for files
        let fm = FileManager.default
        guard let contents = try? fm.subpathsOfDirectory(atPath: mount.localDir) else {
            return []
        }

        for relativePath in contents {
            let localPath = (mount.localDir as NSString).appendingPathComponent(relativePath)
            let virtualPath = "/" + relativePath

            // Get file attributes
            guard let attrs = try? fm.attributesOfItem(atPath: localPath) else { continue }

            // Skip directories
            if (attrs[.type] as? FileAttributeType) == .typeDirectory { continue }

            // Check if EXTERNAL exists
            var externalPath: String? = nil
            if let externalDir = mount.externalDir {
                let extPath = (externalDir as NSString).appendingPathComponent(relativePath)
                if fm.fileExists(atPath: extPath) {
                    externalPath = extPath
                }
            }

            // Only a candidate if EXTERNAL exists
            guard externalPath != nil else { continue }

            let entry = ServiceFileEntry(virtualPath: virtualPath, syncPairId: syncPairId)
            entry.localPath = localPath
            entry.externalPath = externalPath
            entry.size = attrs[.size] as? Int64 ?? 0
            entry.modifiedAt = attrs[.modificationDate] as? Date ?? Date()
            entry.accessedAt = attrs[.creationDate] as? Date ?? Date()  // Use creation time as approximate access time
            entry.fileLocation = .both

            candidates.append(entry)
        }

        // Sort by access time (oldest first)
        candidates.sort { $0.accessedAt < $1.accessedAt }

        return candidates
    }

    /// Update file entry location (eviction: both -> externalOnly)
    private func updateEntryLocation(entry: ServiceFileEntry, vfsManager: VFSManager) async {
        await vfsManager.onFileEvicted(virtualPath: entry.virtualPath, syncPairId: entry.syncPairId)
    }

    // MARK: - Manual Eviction

    /// Evict specified file
    func evictFile(virtualPath: String, syncPairId: String) async throws {
        guard let vfsManager = vfsManager else {
            throw EvictionError.managerNotSet
        }

        guard let entry = await vfsManager.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) else {
            throw EvictionError.fileNotFound(virtualPath)
        }

        // Check if file is evictable
        if entry.isDirty {
            throw EvictionError.fileIsDirty(virtualPath)
        }

        if entry.isLocked {
            throw EvictionError.fileIsLocked(virtualPath)
        }

        guard entry.fileLocation == .both else {
            throw EvictionError.notSynced(virtualPath)
        }

        guard let localPath = entry.localPath else {
            throw EvictionError.noLocalPath(virtualPath)
        }

        // Delete local copy
        try FileManager.default.removeItem(atPath: localPath)

        // Update index
        await updateEntryLocation(entry: entry, vfsManager: vfsManager)

        stats.evictedCount += 1
        stats.evictedSize += entry.size

        logger.info("Manual eviction: \(virtualPath)")
    }

    /// Prefetch file (copy from EXTERNAL to LOCAL)
    func prefetchFile(virtualPath: String, syncPairId: String) async throws {
        guard let vfsManager = vfsManager else {
            throw EvictionError.managerNotSet
        }

        guard let entry = await vfsManager.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) else {
            throw EvictionError.fileNotFound(virtualPath)
        }

        guard entry.fileLocation == .externalOnly else {
            logger.debug("File already local: \(virtualPath)")
            return
        }

        guard let externalPath = entry.externalPath else {
            throw EvictionError.noExternalPath(virtualPath)
        }

        // Get mount point info
        let mounts = await vfsManager.getAllMounts()
        guard let mount = mounts.first(where: { $0.syncPairId == syncPairId }) else {
            throw EvictionError.notMounted(syncPairId)
        }

        // Calculate local path
        let relativePath = String(virtualPath.dropFirst())  // Remove leading /
        let localPath = (mount.localDir as NSString).appendingPathComponent(relativePath)

        // Ensure parent directory exists
        let parentDir = (localPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // Copy file
        try FileManager.default.copyItem(atPath: externalPath, toPath: localPath)

        logger.info("Prefetch complete: \(virtualPath)")
    }

    // MARK: - Utility Methods

    private func getAvailableSpace(at path: String) -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            return attrs[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Error Types

enum EvictionError: Error, LocalizedError {
    case managerNotSet
    case fileNotFound(String)
    case fileIsDirty(String)
    case fileIsLocked(String)
    case notSynced(String)
    case noLocalPath(String)
    case noExternalPath(String)
    case notMounted(String)

    var errorDescription: String? {
        switch self {
        case .managerNotSet:
            return "Manager not set"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileIsDirty(let path):
            return "File has unsynced changes: \(path)"
        case .fileIsLocked(let path):
            return "File is locked: \(path)"
        case .notSynced(let path):
            return "File not synced to external: \(path)"
        case .noLocalPath(let path):
            return "No local path: \(path)"
        case .noExternalPath(let path):
            return "No external path: \(path)"
        case .notMounted(let id):
            return "Sync pair not mounted: \(id)"
        }
    }
}
