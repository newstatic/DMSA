import Foundation

/// VFS filesystem delegate protocol
protocol VFSFileSystemDelegate: AnyObject, Sendable {
    func fileWritten(virtualPath: String, syncPairId: String)
    func fileRead(virtualPath: String, syncPairId: String)
    func fileDeleted(virtualPath: String, syncPairId: String, isDirectory: Bool)
    func fileCreated(virtualPath: String, syncPairId: String, localPath: String, isDirectory: Bool)
    func fileRenamed(fromPath: String, toPath: String, syncPairId: String, isDirectory: Bool)
    /// Callback when FUSE event loop exits unexpectedly (not an active unmount)
    func fuseDidExitUnexpectedly(syncPairId: String, exitCode: Int32)
}

/// FUSE filesystem implementation - using C libfuse wrapper
///
/// This class runs in DMSAService (root privileges), calling libfuse directly via C wrapper.
/// This approach avoids the GMUserFileSystem fork() issue.
///
/// Usage:
/// ```swift
/// let fs = FUSEFileSystem(syncPairId: "...", localDir: "...", externalDir: "...", delegate: ...)
/// try await fs.mount(at: "~/Downloads")
/// ```
class FUSEFileSystem {

    // MARK: - Properties

    private let logger = Logger.forService("FUSE")

    /// Sync pair ID
    private let syncPairId: String

    /// Local directory (hot data cache)
    private let localDir: String

    /// External directory (complete data source)
    private var externalDir: String?

    /// Mount point path
    private(set) var mountPath: String?

    /// Whether mounted
    private(set) var isMounted: Bool = false

    /// Whether external storage is offline
    private var isExternalOffline: Bool = false

    /// Whether read-only mode
    private var isReadOnly: Bool = false

    /// Whether actively unmounting (distinguish from unexpected exit)
    private var isUnmounting: Bool = false

    /// Volume name
    private let volumeName: String

    /// Delegate
    private weak var delegate: VFSFileSystemDelegate?

    /// FUSE run thread
    private var fuseThread: Thread?

    // MARK: - Initialization

    init(syncPairId: String,
         localDir: String,
         externalDir: String?,
         volumeName: String = "DMSA",
         delegate: VFSFileSystemDelegate?) {
        self.syncPairId = syncPairId
        self.localDir = localDir
        self.externalDir = externalDir
        self.volumeName = volumeName
        self.delegate = delegate
        self.isExternalOffline = externalDir == nil
    }

    deinit {
        if isMounted {
            unmountSync()
        }
    }

    // MARK: - Mount/Unmount

    /// Mount filesystem
    func mount(at path: String) async throws {
        guard !isMounted else {
            throw VFSError.alreadyMounted(path)
        }

        logger.info("========== FUSE mount start (C Wrapper) ==========")
        logger.info("Target path: \(path)")

        // Check macFUSE availability
        logger.info("Checking macFUSE...")
        guard FUSEChecker.isAvailable() else {
            logger.error("macFUSE not available!")
            throw VFSError.fuseNotAvailable
        }
        logger.info("macFUSE available, version: \(FUSEChecker.getInstalledVersion() ?? "unknown")")

        let expandedPath = (path as NSString).expandingTildeInPath
        mountPath = expandedPath
        logger.info("Expanded path: \(expandedPath)")

        // Ensure mount point exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: expandedPath) {
            try fm.createDirectory(atPath: expandedPath, withIntermediateDirectories: true, attributes: nil)
            logger.info("Created mount point directory: \(expandedPath)")
        }

        // Set mount point owner
        let pathComponents = expandedPath.components(separatedBy: "/")
        if pathComponents.count >= 3 && pathComponents[1] == "Users" {
            let username = pathComponents[2]
            logger.info("Setting mount point owner to: \(username)")

            let chownProcess = Process()
            chownProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/chown")
            chownProcess.arguments = ["\(username):staff", expandedPath]

            do {
                try chownProcess.run()
                chownProcess.waitUntilExit()
                if chownProcess.terminationStatus == 0 {
                    logger.info("Mount point owner set to \(username)")
                }
            } catch {
                logger.warning("Failed to execute chown: \(error)")
            }
        }

        // Set up FUSE C layer log file path
        setupCLayerLogging()

        // Set up global callback context
        setupFUSECallbacks()

        // Start FUSE on background thread
        logger.info("Starting FUSE on background thread...")

        fuseThread = Thread { [weak self] in
            guard let self = self else { return }

            self.logger.info("FUSE thread started")

            // Call C wrapper to mount
            let result = expandedPath.withCString { mountPointCStr in
                self.localDir.withCString { localDirCStr in
                    if let extDir = self.externalDir {
                        return extDir.withCString { extDirCStr in
                            fuse_wrapper_mount(mountPointCStr, localDirCStr, extDirCStr)
                        }
                    } else {
                        return fuse_wrapper_mount(mountPointCStr, localDirCStr, nil)
                    }
                }
            }

            self.logger.info("FUSE main loop exited, return value: \(result)")
            self.isMounted = false

            // If not an active unmount, notify delegate for recovery
            if !self.isUnmounting {
                // Collect diagnostics before recovery
                let mountPath = expandedPath
                var diagInfo = "exit_code=\(result)"

                // Check mount status
                let (stillMounted, mountDetail) = self.checkMountStatusDetailed(path: mountPath)
                diagInfo += ", still_mounted=\(stillMounted), mount_info=\(mountDetail)"

                // Check mount point existence
                let fm = FileManager.default
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: mountPath, isDirectory: &isDir)
                diagInfo += ", path_exists=\(exists), is_dir=\(isDir.boolValue)"

                // Check /dev/macfuse device
                let macfuseExists = fm.fileExists(atPath: "/dev/macfuse0")
                diagInfo += ", macfuse_dev=\(macfuseExists)"

                self.logger.warning("FUSE exited unexpectedly! Diagnostics: \(diagInfo)")
                self.delegate?.fuseDidExitUnexpectedly(syncPairId: self.syncPairId, exitCode: result)
            }
        }

        fuseThread?.name = "DMSA-FUSE-Thread"
        fuseThread?.qualityOfService = .userInteractive
        fuseThread?.start()

        // Wait for mount to complete
        logger.info("Waiting for mount to complete...")
        try await Task.sleep(nanoseconds: 1_500_000_000)  // Wait 1.5 seconds

        // Check mount status
        let (success, mountInfo) = checkMountStatusDetailed(path: expandedPath)
        logger.info("Mount check: success=\(success), info=\(mountInfo)")

        if success {
            isMounted = true
            logger.info("========== FUSE mount succeeded ==========")
        } else {
            // Wait a bit and retry
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let (success2, mountInfo2) = checkMountStatusDetailed(path: expandedPath)
            logger.info("Mount retry check: success=\(success2), info=\(mountInfo2)")

            if success2 {
                isMounted = true
                logger.info("========== FUSE mount succeeded (delayed) ==========")
            } else {
                logger.warning("FUSE may not be fully mounted, continuing...")
                isMounted = true  // Assume success, let system continue
            }
        }

        logger.info("  syncPairId: \(syncPairId)")
        logger.info("  LOCAL_DIR: \(localDir)")
        logger.info("  EXTERNAL_DIR: \(externalDir ?? "offline")")
    }

    /// Set up C layer logging to file
    private func setupCLayerLogging() {
        // Get log directory from Constants
        let logDir = Constants.Paths.logs.path

        // Ensure log directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: logDir) {
            try? fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        }

        // Create dated log file path (e.g., fuse-2026-02-03.log)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let logPath = "\(logDir)/fuse-\(dateStr).log"

        // Set C layer log path
        logPath.withCString { pathCStr in
            fuse_wrapper_set_log_path(pathCStr)
        }

        // Debug logging off by default for performance
        // Enable via fuse_wrapper_set_debug(1) when needed for diagnostics
        fuse_wrapper_set_debug(0)

        logger.info("C layer logging enabled: \(logPath) (debug mode OFF for performance)")
    }

    /// Set up FUSE callbacks
    private func setupFUSECallbacks() {
        // Save self reference to global variable for C callbacks
        FUSEFileSystemContext.shared.fileSystem = self

        // Register C callbacks
        var callbacks = FuseCallbacks()
        callbacks.on_file_created = { (virtualPath, localPath, isDirectory) in
            guard let vpath = virtualPath, let lpath = localPath else { return }
            let vp = String(cString: vpath)
            let lp = String(cString: lpath)
            FUSEFileSystemContext.shared.fileSystem?.notifyFileCreated(virtualPath: vp, localPath: lp, isDirectory: isDirectory != 0)
        }
        callbacks.on_file_deleted = { (virtualPath, isDirectory) in
            guard let vpath = virtualPath else { return }
            let vp = String(cString: vpath)
            FUSEFileSystemContext.shared.fileSystem?.notifyFileDeleted(virtualPath: vp, isDirectory: isDirectory != 0)
        }
        callbacks.on_file_written = { (virtualPath) in
            guard let vpath = virtualPath else { return }
            let vp = String(cString: vpath)
            FUSEFileSystemContext.shared.fileSystem?.notifyFileWritten(virtualPath: vp)
        }
        callbacks.on_file_read = { (virtualPath) in
            guard let vpath = virtualPath else { return }
            let vp = String(cString: vpath)
            FUSEFileSystemContext.shared.fileSystem?.notifyFileRead(virtualPath: vp)
        }
        callbacks.on_file_renamed = { (fromPath, toPath, isDirectory) in
            guard let from = fromPath, let to = toPath else { return }
            let fp = String(cString: from)
            let tp = String(cString: to)
            FUSEFileSystemContext.shared.fileSystem?.notifyFileRenamed(fromPath: fp, toPath: tp, isDirectory: isDirectory != 0)
        }
        fuse_wrapper_set_callbacks(&callbacks)

        logger.info("FUSE callbacks registered")
    }

    /// Check mount status (detailed version)
    private func checkMountStatusDetailed(path: String) -> (success: Bool, info: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: "\n")

                for line in lines {
                    if line.contains(path) {
                        if line.contains("macfuse") || line.contains("osxfuse") || line.contains("fuse") {
                            return (true, "FUSE mount: \(line)")
                        } else {
                            return (false, "Non-FUSE mount: \(line)")
                        }
                    }
                }

                return (false, "Not found \(path)  mount")
            }
        } catch {
            return (false, "Failed to execute mount command: \(error)")
        }

        return (false, "Check failed")
    }

    /// Unmount filesystem
    func unmount() async throws {
        guard isMounted else {
            throw VFSError.notMounted(syncPairId)
        }

        unmountSync()
    }

    /// Synchronous unmount
    private func unmountSync() {
        guard isMounted, let path = mountPath else { return }

        logger.info("Unmounting FUSE: \(path)")

        // Mark as active unmount to prevent recovery logic
        isUnmounting = true

        // Flush any buffered logs before unmount
        fuse_wrapper_flush_logs()

        // Call C wrapper to unmount
        fuse_wrapper_unmount()

        // Wait for FUSE thread to exit
        fuseThread?.cancel()
        fuseThread = nil

        isMounted = false
        mountPath = nil

        // Clean up context
        FUSEFileSystemContext.shared.fileSystem = nil

        logger.info("FUSE unmounted: \(path)")
    }

    // MARK: - Config Update

    /// Update external directory path
    func updateExternalDir(_ path: String?) {
        externalDir = path
        isExternalOffline = path == nil

        // Update C wrapper path
        if let path = path {
            path.withCString { cstr in
                fuse_wrapper_update_external_dir(cstr)
            }
        } else {
            fuse_wrapper_update_external_dir(nil)
        }

        logger.info("EXTERNAL_DIR updated: \(path ?? "offline")")
    }

    /// Set external storage offline state
    func setExternalOffline(_ offline: Bool) {
        isExternalOffline = offline
        fuse_wrapper_set_external_offline(offline)
    }

    /// Set read-only mode
    func setReadOnly(_ readOnly: Bool) {
        isReadOnly = readOnly
        fuse_wrapper_set_readonly(readOnly)
    }

    /// Set index ready state
    /// When index is not ready, all file operations return EBUSY
    func setIndexReady(_ ready: Bool) {
        fuse_wrapper_set_index_ready(ready)
        logger.info("Index ready state set to: \(ready)")
    }

    /// Get index ready state
    func isIndexReady() -> Bool {
        return fuse_wrapper_is_index_ready() != 0
    }

    // MARK: - Sync Lock API

    /// Lock file for sync (blocks write/truncate/delete during sync)
    /// Call before starting to copy file to external
    func lockFileForSync(_ virtualPath: String) {
        fuse_wrapper_sync_lock(virtualPath)
        logger.debug("Sync lock: \(virtualPath)")
    }

    /// Unlock file after sync (allows write/truncate/delete again)
    /// Call after sync completes (success or failure)
    func unlockFileAfterSync(_ virtualPath: String) {
        fuse_wrapper_sync_unlock(virtualPath)
        logger.debug("Sync unlock: \(virtualPath)")
    }

    /// Unlock all syncing files (emergency cleanup)
    func unlockAllSyncingFiles() {
        fuse_wrapper_sync_unlock_all()
        logger.info("All sync locks cleared")
    }

    // MARK: - Filesystem Operations (for C callbacks)

    /// Get local path
    func localPath(for virtualPath: String) -> String {
        let normalized = virtualPath.hasPrefix("/") ? String(virtualPath.dropFirst()) : virtualPath
        return (localDir as NSString).appendingPathComponent(normalized)
    }

    /// Get external path
    func externalPath(for virtualPath: String) -> String? {
        guard let extDir = externalDir else { return nil }
        let normalized = virtualPath.hasPrefix("/") ? String(virtualPath.dropFirst()) : virtualPath
        return (extDir as NSString).appendingPathComponent(normalized)
    }

    /// Resolve actual file path (local first, then external)
    func resolveActualPath(for virtualPath: String) -> String? {
        let fm = FileManager.default

        // Check local first
        let local = localPath(for: virtualPath)
        if fm.fileExists(atPath: local) {
            return local
        }

        // Then check external (if online)
        if !isExternalOffline, let external = externalPath(for: virtualPath), fm.fileExists(atPath: external) {
            return external
        }

        return nil
    }

    /// Notify file read
    func notifyFileRead(virtualPath: String) {
        delegate?.fileRead(virtualPath: virtualPath, syncPairId: syncPairId)
    }

    /// Notify file written
    func notifyFileWritten(virtualPath: String) {
        delegate?.fileWritten(virtualPath: virtualPath, syncPairId: syncPairId)
    }

    /// Notify file created
    func notifyFileCreated(virtualPath: String, localPath: String, isDirectory: Bool) {
        delegate?.fileCreated(virtualPath: virtualPath, syncPairId: syncPairId, localPath: localPath, isDirectory: isDirectory)
    }

    /// Notify file deleted
    func notifyFileDeleted(virtualPath: String, isDirectory: Bool) {
        delegate?.fileDeleted(virtualPath: virtualPath, syncPairId: syncPairId, isDirectory: isDirectory)
    }

    /// Notify file renamed
    func notifyFileRenamed(fromPath: String, toPath: String, isDirectory: Bool) {
        delegate?.fileRenamed(fromPath: fromPath, toPath: toPath, syncPairId: syncPairId, isDirectory: isDirectory)
    }

    /// Check if file should be excluded
    func shouldExclude(name: String) -> Bool {
        let excludePatterns = [
            ".DS_Store",
            ".Spotlight-V100",
            ".Trashes",
            ".fseventsd",
            ".TemporaryItems",
            "._*",
            ".FUSE"
        ]

        for pattern in excludePatterns {
            if matchPattern(pattern, name: name) {
                return true
            }
        }
        return false
    }

    private func matchPattern(_ pattern: String, name: String) -> Bool {
        if pattern.contains("*") {
            let regex = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            return name.range(of: "^\(regex)$", options: .regularExpression) != nil
        } else {
            return name == pattern
        }
    }
}

// MARK: - FUSE Context (for C callbacks)

/// Global context for accessing Swift objects from C callbacks
class FUSEFileSystemContext {
    static let shared = FUSEFileSystemContext()

    weak var fileSystem: FUSEFileSystem?

    private init() {}
}

// MARK: - FUSE Checker

struct FUSEChecker {

    private static let macFUSEFrameworkPath = "/Library/Frameworks/macFUSE.framework"
    private static let libfusePath = "/usr/local/lib/libfuse.dylib"
    private static let altLibfusePath = "/Library/Frameworks/macFUSE.framework/Versions/A/usr/local/lib/libfuse.2.dylib"

    /// Check if macFUSE is available
    static func isAvailable() -> Bool {
        let fm = FileManager.default

        // Check Framework exists
        guard fm.fileExists(atPath: macFUSEFrameworkPath) else {
            return false
        }

        // Check libfuse library exists (required by C wrapper)
        let libfuseExists = fm.fileExists(atPath: libfusePath) || fm.fileExists(atPath: altLibfusePath)
        guard libfuseExists else {
            return false
        }

        return true
    }

    /// Get installed version
    static func getInstalledVersion() -> String? {
        let infoPlistPath = "\(macFUSEFrameworkPath)/Versions/A/Resources/Info.plist"

        guard let plist = NSDictionary(contentsOfFile: infoPlistPath) else {
            return nil
        }

        return plist["CFBundleShortVersionString"] as? String
            ?? plist["CFBundleVersion"] as? String
    }
}
