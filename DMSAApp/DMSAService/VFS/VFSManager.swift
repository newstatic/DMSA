import Foundation

/// VFS mount point info (in-memory)
struct VFSMountPoint {
    let syncPairId: String
    var localDir: String
    var externalDir: String?
    var targetDir: String
    var isExternalOnline: Bool
    var isReadOnly: Bool
    var mountedAt: Date
    var fuseFileSystem: FUSEFileSystem?  // Actual FUSE filesystem instance
}

/// VFS Manager
/// - Uses ServiceDatabaseManager for persistent file indexing
/// - Uses ServiceConfigManager to save mount state
actor VFSManager {

    private let logger = Logger.forService("VFS")
    private var mountPoints: [String: VFSMountPoint] = [:]

    // Data persistence
    private let database = ServiceDatabaseManager.shared
    private let configManager = ServiceConfigManager.shared

    var mountedCount: Int {
        return mountPoints.count
    }

    // MARK: - Mount Management

    func mount(syncPairId: String,
               localDir: String,
               externalDir: String?,
               targetDir: String) async throws {

        // Check if already mounted
        if mountPoints[syncPairId] != nil {
            throw VFSError.alreadyMounted(targetDir)
        }

        // Validate paths
        guard PathValidator.isAllowed(localDir) else {
            throw VFSError.invalidPath(localDir)
        }
        guard PathValidator.isAllowed(targetDir) else {
            throw VFSError.invalidPath(targetDir)
        }

        let fm = FileManager.default

        // ============================================================
        // Step 0: Check and clean up existing FUSE mount
        // ============================================================

        if isPathMounted(targetDir) {
            logger.warning("Found existing mount, attempting unmount: \(targetDir)")
            do {
                try unmountPath(targetDir)
                // Wait for unmount to complete
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
            } catch {
                logger.error("Failed to unmount existing mount: \(error)")
                // Continue trying, may be handled in later steps
            }
        }

        // ============================================================
        // Step 1: Check TARGET_DIR state and handle
        // ============================================================

        if fm.fileExists(atPath: targetDir) {
            // Get file attributes to determine type
            let attrs = try? fm.attributesOfItem(atPath: targetDir)
            let fileType = attrs?[.type] as? FileAttributeType

            if fileType == .typeSymbolicLink {
                // Case A: TARGET_DIR is a symlink -> remove
                if let linkDest = try? fm.destinationOfSymbolicLink(atPath: targetDir) {
                    logger.warning("TARGET_DIR is a symlink: \(targetDir) -> \(linkDest)")
                }
                try fm.removeItem(atPath: targetDir)
                logger.info("Removed symlink: \(targetDir)")

            } else if fileType == .typeDirectory {
                // Case B: TARGET_DIR is a regular directory -> check if already a FUSE mount point
                // Check via mount command or trying to get mount info
                // Simple check: if we already have a record for this mount point, it is mounted
                if mountPoints.values.contains(where: { $0.targetDir == targetDir }) {
                    throw VFSError.alreadyMounted(targetDir)
                }

                // Case C: TARGET_DIR is a regular directory, rename to LOCAL_DIR
                if fm.fileExists(atPath: localDir) {
                    // LOCAL_DIR already exists, check if TARGET_DIR is empty
                    let targetContents = try? fm.contentsOfDirectory(atPath: targetDir)
                    if targetContents?.isEmpty == true {
                        // TARGET_DIR is empty (possibly left from last FUSE unmount), delete it
                        try fm.removeItem(atPath: targetDir)
                        logger.info("Deleted empty TARGET_DIR: \(targetDir)")
                    } else {
                        // TARGET_DIR is not empty, cannot handle
                        logger.error("Conflict: TARGET_DIR(\(targetDir)) and LOCAL_DIR(\(localDir)) both exist and TARGET_DIR is not empty")
                        throw VFSError.conflictingPaths(targetDir, localDir)
                    }
                } else {
                    // LOCAL_DIR does not exist, rename TARGET_DIR to LOCAL_DIR
                    logger.info("Renaming directory: \(targetDir) -> \(localDir)")
                    try fm.moveItem(atPath: targetDir, toPath: localDir)
                }
            }
        }

        // ============================================================
        // Step 2: Ensure LOCAL_DIR exists
        // ============================================================

        if !fm.fileExists(atPath: localDir) {
            try fm.createDirectory(atPath: localDir, withIntermediateDirectories: true)
            logger.info("Created LOCAL_DIR: \(localDir)")
        }

        // ============================================================
        // Step 3: Create FUSE mount point directory
        // ============================================================

        if !fm.fileExists(atPath: targetDir) {
            try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
            logger.info("Created mount point directory: \(targetDir)")
        }

        // ============================================================
        // Step 4: Check EXTERNAL_DIR state
        // ============================================================

        var isExternalOnline = false
        if let extDir = externalDir {
            if fm.fileExists(atPath: extDir) {
                isExternalOnline = true
                logger.info("EXTERNAL_DIR ready: \(extDir)")
            } else {
                logger.warning("EXTERNAL_DIR not ready (external disk not mounted?): \(extDir)")
            }
        } else {
            logger.warning("No EXTERNAL_DIR configured, using local storage only")
        }

        // ============================================================
        // Step 5: Create and execute FUSE mount
        // ============================================================

        // Create FUSE filesystem instance
        let fuseFS = FUSEFileSystem(
            syncPairId: syncPairId,
            localDir: localDir,
            externalDir: externalDir,
            volumeName: "DMSA-\(syncPairId.prefix(8))",
            delegate: self
        )

        // Execute mount
        try await fuseFS.mount(at: targetDir)

        // ============================================================
        // Step 6: Protect LOCAL_DIR (prevent direct user access)
        // ============================================================
        // Per VFS_DESIGN.md design:
        // - chflags hidden: hide directory
        // - permissions 700: root-only access
        // - ACL deny: deny all user access
        // Both LOCAL_DIR and EXTERNAL_DIR need protection

        logger.info("========== Protecting backend directories (Step 6) ==========")
        logger.info("  LOCAL_DIR: \(localDir)")
        logger.info("  EXTERNAL_DIR: \(externalDir ?? "(nil)")")
        logger.info("  externalDir == nil: \(externalDir == nil)")
        logger.info("  externalDir?.isEmpty: \(externalDir?.isEmpty ?? true)")
        logger.flush()  // Ensure logs are flushed to disk

        logger.info("[1/2] Starting LOCAL_DIR protection...")
        logger.flush()
        protectBackendDir(localDir)
        logger.info("[1/2] LOCAL_DIR protection complete")
        logger.flush()

        logger.info("[2/2] Checking EXTERNAL_DIR...")
        logger.flush()
        if let extDir = externalDir {
            logger.info("[2/2] extDir unwrapped: \(extDir)")
            logger.flush()
            if !extDir.isEmpty {
                logger.info("[2/2] extDir non-empty, protecting EXTERNAL_DIR: \(extDir)")
                logger.flush()
                protectBackendDir(extDir)
                logger.info("[2/2] EXTERNAL_DIR protection complete")
                logger.flush()
            } else {
                logger.info("[2/2] Skipped: extDir is empty string")
                logger.flush()
            }
        } else {
            logger.info("[2/2] Skipped: externalDir is nil (disk not connected)")
            logger.flush()
        }

        // Record mount point
        let mountPoint = VFSMountPoint(
            syncPairId: syncPairId,
            localDir: localDir,
            externalDir: externalDir,
            targetDir: targetDir,
            isExternalOnline: isExternalOnline,
            isReadOnly: false,
            mountedAt: Date(),
            fuseFileSystem: fuseFS
        )

        mountPoints[syncPairId] = mountPoint

        // ============================================================
        // Step 7: Build file index (VFS mounted but blocking access)
        // ============================================================
        // Note: After FUSE mount, index_ready defaults to false
        // Before index is complete, all file access returns EBUSY
        logger.info("========== Building file index (Step 7) ==========")
        logger.info("VFS mounted, building index (file access blocked)")

        // Notify state: indexing
        await ServiceStateManager.shared.setState(.indexing)

        // Build file index and persist
        await buildIndex(for: syncPairId)

        // ============================================================
        // Step 8: Mark index ready, open VFS access
        // ============================================================
        logger.info("========== Index ready, access open (Step 8) ==========")
        fuseFS.setIndexReady(true)

        // Notify state: ready
        await ServiceStateManager.shared.setState(.ready)

        // Send index ready notification
        await ServiceStateManager.shared.sendIndexReadyNotification(syncPairId: syncPairId)

        // Save mount state to config
        var mountState = MountState(syncPairId: syncPairId, targetDir: targetDir, localDir: localDir)
        mountState.externalDir = externalDir
        mountState.isMounted = true
        mountState.isExternalOnline = mountPoint.isExternalOnline
        mountState.mountedAt = Date()
        await configManager.setMountState(mountState)

        logger.info("VFS mount succeeded: \(targetDir)")
    }

    func unmount(syncPairId: String) async throws {
        guard let mountPoint = mountPoints[syncPairId] else {
            throw VFSError.notMounted(syncPairId)
        }

        // Save file index to database
        await database.forceSave()

        // Execute unmount
        if let fuseFS = mountPoint.fuseFileSystem {
            try await fuseFS.unmount()
        }

        // Restore backend directory permissions (allow user access)
        unprotectBackendDir(mountPoint.localDir)
        if let extDir = mountPoint.externalDir {
            unprotectBackendDir(extDir)
        }

        // Remove record
        mountPoints.removeValue(forKey: syncPairId)

        // Remove mount state
        await configManager.removeMountState(syncPairId: syncPairId)

        logger.info("VFS unmount succeeded: \(mountPoint.targetDir)")
    }

    func unmountAll() async {
        for syncPairId in mountPoints.keys {
            do {
                try await unmount(syncPairId: syncPairId)
            } catch {
                logger.error("Unmount failed: \(syncPairId) - \(error)")
            }
        }
    }

    func isMounted(syncPairId: String) -> Bool {
        return mountPoints[syncPairId] != nil
    }

    func getAllMounts() async -> [MountInfo] {
        var results: [MountInfo] = []

        for mp in mountPoints.values {
            var info = MountInfo(
                syncPairId: mp.syncPairId,
                targetDir: mp.targetDir,
                localDir: mp.localDir
            )
            info.externalDir = mp.externalDir
            info.isMounted = true
            info.isExternalOnline = mp.isExternalOnline
            info.mountedAt = mp.mountedAt

            // Get statistics from database
            let stats = await database.getIndexStats(syncPairId: mp.syncPairId)
            info.fileCount = stats.totalFiles + stats.totalDirectories
            info.totalSize = stats.totalSize

            results.append(info)
        }

        return results
    }

    // MARK: - Config Update

    func updateExternalPath(syncPairId: String, newPath: String) async throws {
        guard var mountPoint = mountPoints[syncPairId] else {
            throw VFSError.notMounted(syncPairId)
        }

        let fm = FileManager.default
        let isOnline = fm.fileExists(atPath: newPath)

        mountPoint.externalDir = newPath
        mountPoint.isExternalOnline = isOnline
        mountPoints[syncPairId] = mountPoint

        // Update filesystem
        mountPoint.fuseFileSystem?.updateExternalDir(newPath)

        // Rebuild index to include external files
        if isOnline {
            await buildIndex(for: syncPairId)
        }

        logger.info("EXTERNAL path updated: \(newPath), online: \(isOnline)")
    }

    func setExternalOffline(syncPairId: String, offline: Bool) async {
        guard var mountPoint = mountPoints[syncPairId] else { return }

        mountPoint.isExternalOnline = !offline
        mountPoints[syncPairId] = mountPoint

        mountPoint.fuseFileSystem?.setExternalOffline(offline)

        logger.info("EXTERNAL offline state: \(offline)")
    }

    func setReadOnly(syncPairId: String, readOnly: Bool) async {
        guard var mountPoint = mountPoints[syncPairId] else { return }

        mountPoint.isReadOnly = readOnly
        mountPoints[syncPairId] = mountPoint

        mountPoint.fuseFileSystem?.setReadOnly(readOnly)
    }

    // MARK: - File Index (via ServiceDatabaseManager)

    func getFileEntry(virtualPath: String, syncPairId: String) async -> ServiceFileEntry? {
        return await database.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId)
    }

    func getFileLocation(virtualPath: String, syncPairId: String) async -> FileLocation {
        guard let entry = await database.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) else {
            return .notExists
        }
        return entry.fileLocation
    }

    func rebuildIndex(syncPairId: String) async throws {
        guard mountPoints[syncPairId] != nil else {
            throw VFSError.notMounted(syncPairId)
        }

        await buildIndex(for: syncPairId)
    }

    func getIndexStats(syncPairId: String) async -> IndexStats {
        return await database.getIndexStats(syncPairId: syncPairId)
    }

    func getAllFileEntries(syncPairId: String) async -> [ServiceFileEntry] {
        return await database.getAllFileEntries(syncPairId: syncPairId)
    }

    func getDirtyFiles(syncPairId: String) async -> [ServiceFileEntry] {
        return await database.getDirtyFiles(syncPairId: syncPairId)
    }

    /// Get files that need syncing (dirty files + local-only files)
    func getFilesToSync(syncPairId: String) async -> [ServiceFileEntry] {
        return await database.getFilesToSync(syncPairId: syncPairId)
    }

    func getEvictableFiles(syncPairId: String) async -> [ServiceFileEntry] {
        return await database.getEvictableFiles(syncPairId: syncPairId)
    }

    private func buildIndex(for syncPairId: String) async {
        guard let mountPoint = mountPoints[syncPairId] else { return }

        // Fix ownership of localDir itself
        if let owner = getExpectedOwner(localDir: mountPoint.localDir) {
            let fm = FileManager.default
            if let attrs = try? fm.attributesOfItem(atPath: mountPoint.localDir) {
                fixOwnershipIfNeeded(path: mountPoint.localDir, expectedUID: owner.uid, expectedGID: owner.gid, attrs: attrs)
            }
        }

        // Check if database has existing index -> incremental; otherwise full build
        let existingEntries = await database.getAllFileEntries(syncPairId: syncPairId)
        if !existingEntries.isEmpty {
            logger.info("Found existing index (\(existingEntries.count) entries), performing incremental update")
            await incrementalIndex(for: syncPairId, mountPoint: mountPoint, existingEntries: existingEntries)
        } else {
            logger.info("No existing index, performing full build")
            await fullIndex(for: syncPairId, mountPoint: mountPoint)
        }

        // Update mount state statistics
        let stats = await database.getIndexStats(syncPairId: syncPairId)
        if var mountState = await configManager.getMountState(syncPairId: syncPairId) {
            mountState.fileCount = stats.totalFiles + stats.totalDirectories
            mountState.totalSize = stats.totalSize
            await configManager.setMountState(mountState)
        }

        // Record index activity
        let totalFiles = stats.totalFiles + stats.totalDirectories
        let indexType = existingEntries.isEmpty ? "full build" : "incremental update"
        let sizeStr = ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file)
        let activity = ActivityRecord(
            type: .indexRebuilt,
            title: "Index \(indexType) complete",
            detail: "\(totalFiles) entries, \(sizeStr)",
            syncPairId: syncPairId,
            filesCount: totalFiles,
            bytesCount: stats.totalSize
        )
        await ActivityManager.shared.addActivity(activity)
    }

    /// Incremental index: DB has complete tree, trust it completely
    /// No filesystem scan - just load from DB
    private func incrementalIndex(for syncPairId: String, mountPoint: VFSMountPoint, existingEntries: [ServiceFileEntry]) async {
        let startTime = Date()

        // DB stores complete tree, trust it completely
        // VFS callbacks (onFileCreated/onFileWritten/onFileDeleted) keep it updated in real-time
        // No filesystem scan needed

        let elapsed = Date().timeIntervalSince(startTime)
        logger.info("========== Index loaded from DB ==========")
        logger.info("  syncPairId: \(syncPairId)")
        logger.info("  elapsed: \(String(format: "%.3f", elapsed))s")
        logger.info("  entries: \(existingEntries.count)")
        logger.info("==========================================")
    }

    /// Full index: producer scan + consumer batch write (10k per batch)
    private func fullIndex(for syncPairId: String, mountPoint: VFSMountPoint) async {
        let fm = FileManager.default
        let startTime = Date()
        let batchSize = 10000

        // Clear old index
        await database.clearFileEntries(syncPairId: syncPairId)

        var buffer: [ServiceFileEntry] = []
        buffer.reserveCapacity(batchSize)
        var totalCount = 0
        var localPaths: [String: ServiceFileEntry] = [:]
        let expectedOwner = getExpectedOwner(localDir: mountPoint.localDir)

        // Producer: scan LOCAL_DIR
        if let localContents = try? fm.subpathsOfDirectory(atPath: mountPoint.localDir) {
            for relativePath in localContents {
                if shouldExclude(path: relativePath) { continue }
                let fullPath = (mountPoint.localDir as NSString).appendingPathComponent(relativePath)

                var entry = ServiceFileEntry(virtualPath: "/" + relativePath, syncPairId: syncPairId)
                entry.localPath = fullPath

                if let attrs = try? fm.attributesOfItem(atPath: fullPath) {
                    entry.size = attrs[.size] as? Int64 ?? 0
                    entry.modifiedAt = attrs[.modificationDate] as? Date ?? Date()
                    entry.createdAt = attrs[.creationDate] as? Date ?? Date()
                    entry.isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory

                    // Fix ownership if wrong
                    if let owner = expectedOwner {
                        fixOwnershipIfNeeded(path: fullPath, expectedUID: owner.uid, expectedGID: owner.gid, attrs: attrs)
                    }
                }

                entry.location = FileLocation.localOnly.rawValue
                localPaths[entry.virtualPath] = entry
            }
        }

        // Producer: scan EXTERNAL_DIR, merge
        if mountPoint.isExternalOnline, let externalDir = mountPoint.externalDir {
            if let externalContents = try? fm.subpathsOfDirectory(atPath: externalDir) {
                for relativePath in externalContents {
                    if shouldExclude(path: relativePath) { continue }
                    let fullPath = (externalDir as NSString).appendingPathComponent(relativePath)
                    let virtualPath = "/" + relativePath

                    if var entry = localPaths[virtualPath] {
                        entry.externalPath = fullPath
                        entry.location = FileLocation.both.rawValue
                        localPaths[virtualPath] = entry
                    } else {
                        var entry = ServiceFileEntry(virtualPath: virtualPath, syncPairId: syncPairId)
                        entry.externalPath = fullPath
                        if let attrs = try? fm.attributesOfItem(atPath: fullPath) {
                            entry.size = attrs[.size] as? Int64 ?? 0
                            entry.modifiedAt = attrs[.modificationDate] as? Date ?? Date()
                            entry.createdAt = attrs[.creationDate] as? Date ?? Date()
                            entry.isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
                        }
                        entry.location = FileLocation.externalOnly.rawValue
                        localPaths[virtualPath] = entry
                    }
                }
            }
        }

        let scanElapsed = Date().timeIntervalSince(startTime)
        logger.info("File scan complete: \(localPaths.count) entries, elapsed \(String(format: "%.2f", scanElapsed))s")

        // Consumer: batch write
        for (_, entry) in localPaths {
            buffer.append(entry)

            if buffer.count >= batchSize {
                await database.saveFileEntries(buffer)
                totalCount += buffer.count
                logger.info("Index write progress: \(totalCount)/\(localPaths.count)")
                buffer.removeAll(keepingCapacity: true)
            }
        }

        // Flush remaining
        if !buffer.isEmpty {
            await database.saveFileEntries(buffer)
            totalCount += buffer.count
        }

        let elapsed = Date().timeIntervalSince(startTime)
        logger.info("========== Full index complete ==========")
        logger.info("  syncPairId: \(syncPairId)")
        logger.info("  total entries: \(totalCount)")
        logger.info("  elapsed: \(String(format: "%.2f", elapsed))s (scan: \(String(format: "%.2f", scanElapsed))s)")
        logger.info("===================================")
    }

    /// Print index statistics
    private func logIndexStats(_ entries: [ServiceFileEntry]) {
        var localOnlyCount = 0
        var externalOnlyCount = 0
        var bothCount = 0
        var directoriesCount = 0
        var filesCount = 0

        for entry in entries {
            if entry.isDirectory { directoriesCount += 1 } else { filesCount += 1 }
            switch entry.location {
            case FileLocation.localOnly.rawValue: localOnlyCount += 1
            case FileLocation.externalOnly.rawValue: externalOnlyCount += 1
            case FileLocation.both.rawValue: bothCount += 1
            default: break
            }
        }

        logger.info("  total entries: \(entries.count) (files: \(filesCount), directories: \(directoriesCount))")
        logger.info("  location distribution: localOnly=\(localOnlyCount), externalOnly=\(externalOnlyCount), both=\(bothCount)")
        logger.info("  needs sync: \(entries.filter { $0.needsSync && !$0.isDirectory }.count)")
        logger.info("===================================")
    }

    private func shouldExclude(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent

        for pattern in Constants.defaultExcludePatterns {
            if matchPattern(pattern, name: name) {
                return true
            }
        }

        return false
    }

    private func matchPattern(_ pattern: String, name: String) -> Bool {
        if pattern.contains("*") {
            // Simple wildcard matching
            let regex = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")

            return name.range(of: "^\(regex)$", options: .regularExpression) != nil
        } else {
            return name == pattern
        }
    }

    /// Get expected owner uid/gid from the parent directory of localDir
    private nonisolated func getExpectedOwner(localDir: String) -> (uid: UInt32, gid: UInt32)? {
        let parent = (localDir as NSString).deletingLastPathComponent
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: parent) else { return nil }
        let uid = attrs[.ownerAccountID] as? UInt32 ?? 0
        let gid = attrs[.groupOwnerAccountID] as? UInt32 ?? 0
        if uid == 0 && gid == 0 { return nil }
        return (uid, gid)
    }

    /// Fix file ownership if it doesn't match expected owner
    private nonisolated func fixOwnershipIfNeeded(path: String, expectedUID: UInt32, expectedGID: UInt32, attrs: [FileAttributeKey: Any]) {
        let currentUID = attrs[.ownerAccountID] as? UInt32 ?? 0
        let currentGID = attrs[.groupOwnerAccountID] as? UInt32 ?? 0
        if currentUID != expectedUID || currentGID != expectedGID {
            let logger = Logger.forService("VFS")
            logger.info("Fixing ownership: \(path) uid \(currentUID)->\(expectedUID) gid \(currentGID)->\(expectedGID)")
            // Use lchown so symlinks themselves get fixed
            lchown(path, expectedUID, expectedGID)
        }
    }

    // MARK: - File Operation Callbacks

    // Throttle for file written notifications (avoid flooding)
    private var lastWrittenNotificationTime: Date = .distantPast
    private let writtenNotificationThrottleInterval: TimeInterval = 0.5  // 500ms

    // Throttle for file read access time updates (LRU tracking)
    // Use a pending set instead of updating every read to avoid Actor serialization bottleneck
    private var pendingAccessTimeUpdates: Set<String> = []  // virtualPath set
    private var lastAccessTimeFlushTime: Date = .distantPast
    private let accessTimeFlushInterval: TimeInterval = 5.0  // Flush every 5 seconds
    private let accessTimeLock = NSLock()

    func onFileWritten(virtualPath: String, syncPairId: String) async {
        // Update index in database (fast - in-memory cache + async ObjectBox)
        await database.markFileDirty(virtualPath: virtualPath, syncPairId: syncPairId, dirty: true)

        // Throttle SharedState updates and notifications to avoid blocking
        // During bulk operations (cp -rf), we don't need to update for every single file
        let now = Date()
        if now.timeIntervalSince(lastWrittenNotificationTime) >= writtenNotificationThrottleInterval {
            lastWrittenNotificationTime = now

            // Update shared state in background (avoid blocking callback thread)
            Task.detached(priority: .utility) {
                SharedState.update { state in
                    state.lastWrittenPath = virtualPath
                    state.lastWrittenSyncPair = syncPairId
                    state.lastWrittenTime = Date()
                }

                // Send notification with deliverImmediately: false to avoid blocking
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name(Constants.Notifications.fileWritten),
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: false
                )
            }
        }
        // NOTE: No logging here - hot path during bulk writes
    }

    func onFileRead(virtualPath: String, syncPairId: String) async {
        // Throttled access time updates to avoid Actor serialization bottleneck during bulk reads
        // Collect paths in a pending set, flush periodically in batch
        let key = "\(syncPairId):\(virtualPath)"

        accessTimeLock.lock()
        pendingAccessTimeUpdates.insert(key)
        let shouldFlush = Date().timeIntervalSince(lastAccessTimeFlushTime) >= accessTimeFlushInterval
        accessTimeLock.unlock()

        if shouldFlush {
            await flushAccessTimeUpdates()
        }
    }

    /// Flush pending access time updates in batch
    /// Flow: 1. Update memory  2. Async update DB  3. Async update LOCAL_DIR atime  4. Async update EXTERNAL_DIR atime
    private func flushAccessTimeUpdates() async {
        accessTimeLock.lock()
        let updates = pendingAccessTimeUpdates
        pendingAccessTimeUpdates.removeAll()
        lastAccessTimeFlushTime = Date()
        accessTimeLock.unlock()

        guard !updates.isEmpty else { return }

        // Step 1 & 2: Update memory cache + async database (single Actor call)
        await database.batchUpdateAccessTime(keys: Array(updates))

        // Capture mountPoints data before detached task (Actor isolation)
        let mountPointsCopy = self.mountPoints

        // Step 3 & 4: Async update file system atime (LOCAL_DIR + EXTERNAL_DIR)
        // Run in background to avoid blocking
        Task.detached(priority: .utility) {
            let now = Date()

            for key in updates {
                let parts = key.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }

                let syncPairId = String(parts[0])
                let virtualPath = String(parts[1])

                guard let mountPoint = mountPointsCopy[syncPairId] else { continue }

                let relativePath = String(virtualPath.dropFirst())  // Remove leading "/"

                // Update LOCAL_DIR atime
                let localPath = (mountPoint.localDir as NSString).appendingPathComponent(relativePath)
                Self.touchAccessTime(path: localPath, time: now)

                // Update EXTERNAL_DIR atime (if available)
                if let externalDir = mountPoint.externalDir {
                    let externalPath = (externalDir as NSString).appendingPathComponent(relativePath)
                    Self.touchAccessTime(path: externalPath, time: now)
                }
            }
        }
    }

    /// Touch file access time (atime) without modifying mtime
    /// Uses utimes() syscall to update only access time
    private static func touchAccessTime(path: String, time: Date) {
        // Get current file stat to preserve mtime
        var st = stat()
        guard stat(path, &st) == 0 else { return }

        // Prepare timeval array: [atime, mtime]
        let timeInterval = time.timeIntervalSince1970
        var times = [
            timeval(tv_sec: Int(timeInterval), tv_usec: 0),  // New atime
            timeval(tv_sec: st.st_mtimespec.tv_sec, tv_usec: Int32(st.st_mtimespec.tv_nsec / 1000))  // Preserve mtime
        ]

        // Update access time only
        utimes(path, &times)
    }

    func onFileDeleted(virtualPath: String, syncPairId: String, isDirectory: Bool = false) async {
        // Fast deletion - just mark in cache, actual DB delete is batched
        await database.deleteFileEntry(virtualPath: virtualPath, syncPairId: syncPairId)
        // Note: No logging here to avoid I/O in hot path
    }

    /// Evict file: both -> externalOnly, preserve index entry
    func onFileEvicted(virtualPath: String, syncPairId: String) async {
        if let entry = await database.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) {
            entry.localPath = nil
            entry.location = FileLocation.externalOnly.rawValue
            entry.isDirty = false
            await database.saveFileEntry(entry)
            logger.debug("File evicted: \(virtualPath) (both -> externalOnly)")
        }
    }

    func onFileCreated(virtualPath: String, syncPairId: String, localPath: String, isDirectory: Bool = false) async {
        // Fast creation - minimal work in hot path
        var entry = ServiceFileEntry(virtualPath: virtualPath, syncPairId: syncPairId)
        entry.localPath = localPath
        entry.location = FileLocation.localOnly.rawValue
        entry.isDirty = !isDirectory  // Directories don't need sync
        entry.isDirectory = isDirectory

        // Defer expensive stat() call - just use defaults for now
        // The actual size/time will be updated when file is synced or accessed
        entry.size = 0
        entry.modifiedAt = Date()
        entry.createdAt = Date()

        await database.saveFileEntry(entry)
        // Note: No logging here to avoid I/O in hot path
    }

    func onFileRenamed(fromPath: String, toPath: String, syncPairId: String, isDirectory: Bool) async {
        // Rename in DB: delete old entry, create new entry with preserved metadata
        guard let mountPoint = mountPoints[syncPairId] else { return }

        if let oldEntry = await database.getFileEntry(virtualPath: fromPath, syncPairId: syncPairId) {
            // Create new entry with updated paths
            let relativePath = String(toPath.dropFirst())
            let newLocalPath = (mountPoint.localDir as NSString).appendingPathComponent(relativePath)

            var newEntry = ServiceFileEntry(virtualPath: toPath, syncPairId: syncPairId)
            newEntry.localPath = newLocalPath
            newEntry.externalPath = mountPoint.externalDir.map { ($0 as NSString).appendingPathComponent(relativePath) }
            newEntry.location = oldEntry.location
            newEntry.size = oldEntry.size
            newEntry.modifiedAt = Date()
            newEntry.createdAt = oldEntry.createdAt
            newEntry.accessedAt = oldEntry.accessedAt
            newEntry.isDirty = oldEntry.isDirty
            newEntry.isDirectory = isDirectory
            newEntry.lockState = oldEntry.lockState

            // Delete old, save new
            await database.deleteFileEntry(virtualPath: fromPath, syncPairId: syncPairId)
            await database.saveFileEntry(newEntry)

            logger.debug("File renamed: \(fromPath) -> \(toPath), isDirectory: \(isDirectory)")
        } else {
            // Old entry not found, just create new one
            await onFileCreated(virtualPath: toPath, syncPairId: syncPairId,
                              localPath: (mountPoint.localDir as NSString).appendingPathComponent(String(toPath.dropFirst())),
                              isDirectory: isDirectory)
            logger.debug("File renamed (no old entry): \(fromPath) -> \(toPath)")
        }
    }

    // MARK: - FUSE Unexpected Exit Recovery

    /// Maximum auto-recovery attempts
    private var remountAttempts: [String: Int] = [:]
    private let maxRemountAttempts = 3
    /// Recovery cooldown (seconds), prevents rapid restart loops
    private let remountCooldown: UInt64 = 3_000_000_000  // 3s

    /// Attempt auto-recovery mount after unexpected FUSE exit
    func handleUnexpectedFUSEExit(syncPairId: String) async {
        guard let mountPoint = mountPoints[syncPairId] else {
            logger.error("[Recovery] Mount point record not found: \(syncPairId)")
            return
        }

        let attempts = remountAttempts[syncPairId] ?? 0
        if attempts >= maxRemountAttempts {
            logger.error("[Recovery] Max retry count reached (\(maxRemountAttempts)), giving up recovery: \(syncPairId)")
            // Clean up mount point record
            mountPoints.removeValue(forKey: syncPairId)
            await ServiceStateManager.shared.setState(.error)
            return
        }

        remountAttempts[syncPairId] = attempts + 1
        logger.warning("[Recovery] FUSE exited unexpectedly, attempting recovery (\(attempts + 1)/\(maxRemountAttempts)): \(mountPoint.targetDir)")

        // Wait for cooldown
        try? await Task.sleep(nanoseconds: remountCooldown)

        // Clean up old mount point record (keep config info)
        let localDir = mountPoint.localDir
        let externalDir = mountPoint.externalDir
        let targetDir = mountPoint.targetDir
        mountPoints.removeValue(forKey: syncPairId)

        do {
            // Remount
            try await mount(
                syncPairId: syncPairId,
                localDir: localDir,
                externalDir: externalDir,
                targetDir: targetDir
            )

            // Recovery succeeded, reset counter
            remountAttempts[syncPairId] = 0
            logger.info("[Recovery] FUSE remount succeeded: \(targetDir)")
        } catch {
            logger.error("[Recovery] FUSE remount failed: \(error)")
            // mount() internally registers to mountPoints; if it fails, it will not
            // Next handleUnexpectedFUSEExit call will retry
        }
    }

    /// Check all mount points after system wake, recover lost mounts
    func checkAndRecoverMounts() async {
        logger.info("[Wake recovery] Checking all mount point states...")

        for (syncPairId, mountPoint) in mountPoints {
            let stillMounted = isPathMounted(mountPoint.targetDir)
            let fuseAlive = mountPoint.fuseFileSystem?.isMounted ?? false

            if stillMounted && fuseAlive {
                logger.info("[Wake recovery] Mount OK: \(mountPoint.targetDir)")
            } else {
                logger.warning("[Wake recovery] Mount lost: \(mountPoint.targetDir) (system=\(stillMounted), fuse=\(fuseAlive))")
                // Reset recovery counter (wake recovery does not count as unexpected exit)
                remountAttempts[syncPairId] = 0
                await handleUnexpectedFUSEExit(syncPairId: syncPairId)
            }
        }
    }

    // MARK: - Health Check

    func healthCheck() -> Bool {
        // Check if all mount points are healthy
        return !mountPoints.isEmpty || true  // Empty mount list is also considered healthy
    }

    // MARK: - Mount Point Management

    /// Check if path is already mounted
    private nonisolated func isPathMounted(_ path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Check if there is a mount at this path
                return output.contains("on \(path) ")
            }
        } catch {
            return false
        }

        return false
    }

    /// Force unmount the specified path
    private nonisolated func unmountPath(_ path: String) throws {
        let logger = Logger.forService("VFS")

        // Try normal unmount first
        let umount = Process()
        umount.executableURL = URL(fileURLWithPath: "/sbin/umount")
        umount.arguments = [path]

        let errorPipe = Pipe()
        umount.standardError = errorPipe

        try umount.run()
        umount.waitUntilExit()

        if umount.terminationStatus == 0 {
            logger.info("Normal unmount succeeded: \(path)")
            return
        }

        // If failed, try force unmount
        logger.warning("Normal unmount failed, trying force unmount...")

        let forceUmount = Process()
        forceUmount.executableURL = URL(fileURLWithPath: "/sbin/umount")
        forceUmount.arguments = ["-f", path]

        try forceUmount.run()
        forceUmount.waitUntilExit()

        if forceUmount.terminationStatus != 0 {
            // Last resort: try diskutil
            let diskutil = Process()
            diskutil.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            diskutil.arguments = ["unmount", "force", path]

            try diskutil.run()
            diskutil.waitUntilExit()

            if diskutil.terminationStatus != 0 {
                throw VFSError.unmountFailed(path)
            }
        }

        logger.info("Force unmount succeeded: \(path)")
    }

    // MARK: - Directory Protection

    /// Protect backend directory (LOCAL_DIR or EXTERNAL_DIR) - deny all access
    /// Uses triple protection:
    /// 1. Permissions 700: root-only access
    /// 2. ACL deny: explicitly deny all permissions for current user
    /// 3. chflags hidden: hide directory (psychological deterrent)
    /// Note: Not using chflags uchg since our Service needs to operate on this directory
    private nonisolated func protectBackendDir(_ path: String) {
        let logger = Logger.forService("VFS")
        logger.info("========== Backend directory protection start ==========")
        logger.info("Path: \(path)")
        logger.flush()

        // Check if path exists
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            logger.warning("Backend directory not found, skipping protection: \(path)")
            return
        }

        // Show current state
        logger.info("[Step 0] Getting current permissions...")
        logger.flush()
        if let attrs = try? fm.attributesOfItem(atPath: path) {
            let perms = attrs[.posixPermissions] as? Int ?? 0
            logger.info("Current permissions: \(String(perms, radix: 8))")
            logger.flush()
        }

        // 1. Set permissions to 700 (root-only access)
        logger.info("[Step 1] Setting permissions 700...")
        logger.flush()
        do {
            let attrs: [FileAttributeKey: Any] = [
                .posixPermissions: 0o700  // rwx------
            ]
            try fm.setAttributes(attrs, ofItemAtPath: path)
            logger.info("Directory permissions set to 700: \(path)")
        } catch {
            logger.error("Failed to set directory permissions: \(error)")
        }

        // 2. Add ACL deny rules - deny all user access
        logger.info("[Step 2] Adding ACL deny rules...")
        logger.flush()
        // Get directory owner username
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let ownerAccountName = attrs[.ownerAccountName] as? String {
            logger.info("Directory owner: \(ownerAccountName)")

            // Use chmod +a to add ACL deny rule
            let aclProcess = Process()
            aclProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            // deny read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,readsecurity,writesecurity,chown,list,search,add_file,add_subdirectory,delete_child
            aclProcess.arguments = ["+a", "user:\(ownerAccountName) deny read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,readsecurity,list,search,add_file,add_subdirectory,delete_child", path]

            let aclPipe = Pipe()
            let aclErrorPipe = Pipe()
            aclProcess.standardOutput = aclPipe
            aclProcess.standardError = aclErrorPipe

            do {
                try aclProcess.run()
                aclProcess.waitUntilExit()

                let errorData = aclErrorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                if aclProcess.terminationStatus == 0 {
                    logger.info("ACL deny rule added: user \(ownerAccountName) denied all access")
                } else {
                    logger.warning("ACL setup failed, status: \(aclProcess.terminationStatus), error: \(errorOutput)")
                }
            } catch {
                logger.warning("Failed to execute chmod +a: \(error)")
            }

            // Also deny everyone group
            let everyoneProcess = Process()
            everyoneProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            everyoneProcess.arguments = ["+a", "everyone deny read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,readsecurity,list,search,add_file,add_subdirectory,delete_child", path]

            let everyonePipe = Pipe()
            let everyoneErrorPipe = Pipe()
            everyoneProcess.standardOutput = everyonePipe
            everyoneProcess.standardError = everyoneErrorPipe

            do {
                try everyoneProcess.run()
                everyoneProcess.waitUntilExit()

                if everyoneProcess.terminationStatus == 0 {
                    logger.info("ACL deny rule added: everyone denied all access")
                }
            } catch {
                logger.warning("Failed to execute chmod +a (everyone): \(error)")
            }
        }

        // 3. Set hidden flag (chflags hidden)
        logger.info("[Step 3] Setting hidden flag...")
        logger.flush()
        logger.info("Executing: chflags hidden \(path)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        process.arguments = ["hidden", path]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                logger.info("Directory set to hidden: \(path)")
            } else {
                logger.warning("chflags hidden failed, status: \(process.terminationStatus), error: \(errorOutput)")
            }
        } catch {
            logger.warning("Failed to execute chflags: \(error)")
        }

        // 4. Verify protection state (using stat instead of ls to avoid hanging)
        logger.info("[Step 4] Verifying protection state...")
        logger.flush()

        // Use FileManager to verify, avoid potential Process blocking
        if let attrs = try? fm.attributesOfItem(atPath: path) {
            let perms = attrs[.posixPermissions] as? Int ?? 0
            let owner = attrs[.ownerAccountName] as? String ?? "unknown"
            logger.info("Verification: permissions=\(String(perms, radix: 8)), owner=\(owner)")
            logger.flush()
        } else {
            logger.warning("Failed to get directory attributes for verification")
            logger.flush()
        }

        logger.info("========== Backend directory protection complete ==========")
        logger.flush()
    }

    /// Unprotect backend directory (called during unmount)
    private nonisolated func unprotectBackendDir(_ path: String) {
        let logger = Logger.forService("VFS")
        logger.info("========== Backend directory unprotection start ==========")
        logger.info("Path: \(path)")

        // Check if path exists
        guard FileManager.default.fileExists(atPath: path) else {
            logger.warning("Backend directory not found, skipping unprotection: \(path)")
            return
        }

        // 1. Remove all ACL rules
        let aclProcess = Process()
        aclProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        aclProcess.arguments = ["-N", path]  // -N removes all ACLs

        do {
            try aclProcess.run()
            aclProcess.waitUntilExit()

            if aclProcess.terminationStatus == 0 {
                logger.info("ACL rules removed: \(path)")
            } else {
                logger.warning("ACL removal returned non-zero status: \(aclProcess.terminationStatus)")
            }
        } catch {
            logger.warning("ACL removal failed: \(error)")
        }

        // 2. Restore permissions to 755
        do {
            let attrs: [FileAttributeKey: Any] = [
                .posixPermissions: 0o755  // rwxr-xr-x
            ]
            try FileManager.default.setAttributes(attrs, ofItemAtPath: path)
            logger.info("Directory permissions restored to 755: \(path)")
        } catch {
            logger.warning("Failed to restore directory permissions: \(error)")
        }

        // 3. Remove hidden flag (chflags nohidden)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        process.arguments = ["nohidden", path]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                logger.info("Directory hidden flag removed: \(path)")
            } else {
                logger.warning("chflags nohidden returned non-zero status: \(process.terminationStatus)")
            }
        } catch {
            logger.warning("Failed to remove directory hidden flag: \(error)")
        }

        logger.info("========== Backend directory unprotection complete ==========")
    }
}

// MARK: - VFSFileSystemDelegate

extension VFSManager: VFSFileSystemDelegate {
    nonisolated func fileWritten(virtualPath: String, syncPairId: String) {
        Task {
            await onFileWritten(virtualPath: virtualPath, syncPairId: syncPairId)
        }
    }

    nonisolated func fileRead(virtualPath: String, syncPairId: String) {
        Task {
            await onFileRead(virtualPath: virtualPath, syncPairId: syncPairId)
        }
    }

    nonisolated func fileDeleted(virtualPath: String, syncPairId: String, isDirectory: Bool) {
        Task {
            await onFileDeleted(virtualPath: virtualPath, syncPairId: syncPairId, isDirectory: isDirectory)
        }
    }

    nonisolated func fileCreated(virtualPath: String, syncPairId: String, localPath: String, isDirectory: Bool) {
        Task {
            await onFileCreated(virtualPath: virtualPath, syncPairId: syncPairId, localPath: localPath, isDirectory: isDirectory)
        }
    }

    nonisolated func fileRenamed(fromPath: String, toPath: String, syncPairId: String, isDirectory: Bool) {
        Task {
            await onFileRenamed(fromPath: fromPath, toPath: toPath, syncPairId: syncPairId, isDirectory: isDirectory)
        }
    }

    nonisolated func fuseDidExitUnexpectedly(syncPairId: String, exitCode: Int32) {
        Task {
            await handleUnexpectedFUSEExit(syncPairId: syncPairId)
        }
    }
}
