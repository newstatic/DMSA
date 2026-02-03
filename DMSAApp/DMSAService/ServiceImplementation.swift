import Foundation

/// DMSA Service Implementation
/// Implements DMSAServiceProtocol, integrating VFS + Sync + Privileged functionality
final class ServiceImplementation: NSObject, DMSAServiceProtocol {

    private let logger = Logger.forService("DMSAService")
    private let vfsManager = VFSManager()
    private let syncManager = SyncManager()
    private let evictionManager = EvictionManager()
    private var config: AppConfig
    private let startedAt: Date = Date()

    /// XPC debug logging toggle
    private let xpcDebugEnabled = true

    override init() {
        self.config = Self.loadConfig()
        super.init()

        // Set up cross-references between VFSManager and SyncManager
        Task {
            // VFSManager needs SyncManager to trigger sync on file write
            await vfsManager.setSyncManager(syncManager)
            // SyncManager needs VFSManager to lock files during sync
            await syncManager.setVFSManager(vfsManager)
            // EvictionManager needs both
            await evictionManager.setManagers(vfs: vfsManager, sync: syncManager)
            await evictionManager.startAutoEviction()
        }

        logger.info("ServiceImplementation initialization complete")
    }

    // MARK: - XPC Logging Helpers

    private func logXPCReceive(_ method: String, params: [String: Any] = [:]) {
        guard xpcDebugEnabled else { return }
        let paramsStr = params.isEmpty ? "" : " params=\(params)"
        logger.debug("[XPC⬇] \(method)\(paramsStr)")
    }

    private func logXPCReply(_ method: String, success: Bool, result: Any? = nil, error: String? = nil) {
        guard xpcDebugEnabled else { return }
        if success {
            let resultStr = result.map { " result=\($0)" } ?? ""
            logger.debug("[XPC⬆] \(method) ✓\(resultStr)")
        } else {
            logger.debug("[XPC⬆] \(method) ✗ error=\(error ?? "unknown")")
        }
    }

    private func logXPCReplyData(_ method: String, data: Data?) {
        guard xpcDebugEnabled else { return }
        if let data = data, let str = String(data: data, encoding: .utf8) {
            let preview = str.count > 200 ? String(str.prefix(200)) + "..." : str
            logger.debug("[XPC⬆] \(method) data=\(preview)")
        } else {
            logger.debug("[XPC⬆] \(method) data=\(data?.count ?? 0) bytes")
        }
    }

    private static func loadConfig() -> AppConfig {
        let logger = Logger.forService("DMSAService")
        let configURL = Constants.Paths.config
        logger.info("loadConfig: Loading config from \(configURL.path)")

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            logger.warning("loadConfig: Config file not found")
            return AppConfig()
        }

        guard let data = try? Data(contentsOf: configURL) else {
            logger.warning("loadConfig: Failed to read config file")
            return AppConfig()
        }

        guard let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            logger.warning("loadConfig: JSON parsing failed")
            return AppConfig()
        }

        logger.info("loadConfig: Config loaded successfully")
        logger.info("  syncPairs: \(config.syncPairs.map { $0.id })")
        logger.info("  disks: \(config.disks.map { $0.id })")
        return config
    }

    // MARK: - ========== VFS Operations ==========

    func vfsMount(syncPairId: String,
                  localDir: String,
                  externalDir: String?,
                  targetDir: String,
                  withReply reply: @escaping (Bool, String?) -> Void) {
        logXPCReceive("vfsMount", params: ["syncPairId": syncPairId, "localDir": localDir, "externalDir": externalDir ?? "nil", "targetDir": targetDir])
        Task {
            do {
                try await vfsManager.mount(
                    syncPairId: syncPairId,
                    localDir: localDir,
                    externalDir: externalDir,
                    targetDir: targetDir
                )
                logger.info("VFS mount succeeded: \(syncPairId)")
                logXPCReply("vfsMount", success: true)
                reply(true, nil)
            } catch {
                logger.error("VFS mount failed: \(error)")
                logXPCReply("vfsMount", success: false, error: error.localizedDescription)
                reply(false, error.localizedDescription)
            }
        }
    }

    func vfsUnmount(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void) {
        logXPCReceive("vfsUnmount", params: ["syncPairId": syncPairId])
        Task {
            do {
                try await vfsManager.unmount(syncPairId: syncPairId)
                logger.info("VFS unmount succeeded: \(syncPairId)")
                logXPCReply("vfsUnmount", success: true)
                reply(true, nil)
            } catch {
                logger.error("VFS unmount failed: \(error)")
                logXPCReply("vfsUnmount", success: false, error: error.localizedDescription)
                reply(false, error.localizedDescription)
            }
        }
    }

    func vfsUnmountAll(withReply reply: @escaping (Bool, String?) -> Void) {
        logXPCReceive("vfsUnmountAll")
        Task {
            await vfsManager.unmountAll()
            logger.info("All VFS mounts unmounted")
            logXPCReply("vfsUnmountAll", success: true)
            reply(true, nil)
        }
    }

    func vfsGetMountStatus(syncPairId: String,
                           withReply reply: @escaping (Bool, String?) -> Void) {
        logXPCReceive("vfsGetMountStatus", params: ["syncPairId": syncPairId])
        Task {
            let isMounted = await vfsManager.isMounted(syncPairId: syncPairId)
            logXPCReply("vfsGetMountStatus", success: true, result: isMounted)
            reply(isMounted, nil)
        }
    }

    func vfsGetAllMounts(withReply reply: @escaping (Data) -> Void) {
        logXPCReceive("vfsGetAllMounts")
        Task {
            let mounts = await vfsManager.getAllMounts()
            let data = (try? JSONEncoder().encode(mounts)) ?? Data()
            logXPCReplyData("vfsGetAllMounts", data: data)
            reply(data)
        }
    }

    func vfsGetFileStatus(virtualPath: String,
                          syncPairId: String,
                          withReply reply: @escaping (Data?) -> Void) {
        Task {
            if let entry = await vfsManager.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) {
                let data = try? JSONEncoder().encode(entry)
                reply(data)
            } else {
                reply(nil)
            }
        }
    }

    func vfsGetFileLocation(virtualPath: String,
                            syncPairId: String,
                            withReply reply: @escaping (String) -> Void) {
        Task {
            let location = await vfsManager.getFileLocation(virtualPath: virtualPath, syncPairId: syncPairId)
            reply(String(location.rawValue))
        }
    }

    func vfsUpdateExternalPath(syncPairId: String,
                               newPath: String,
                               withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                try await vfsManager.updateExternalPath(syncPairId: syncPairId, newPath: newPath)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func vfsSetExternalOffline(syncPairId: String,
                               offline: Bool,
                               withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            await vfsManager.setExternalOffline(syncPairId: syncPairId, offline: offline)
            reply(true, nil)
        }
    }

    func vfsSetReadOnly(syncPairId: String,
                        readOnly: Bool,
                        withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            await vfsManager.setReadOnly(syncPairId: syncPairId, readOnly: readOnly)
            reply(true, nil)
        }
    }

    func vfsRebuildIndex(syncPairId: String,
                         withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                try await vfsManager.rebuildIndex(syncPairId: syncPairId)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func vfsGetIndexStats(syncPairId: String,
                          withReply reply: @escaping (Data?) -> Void) {
        Task {
            let stats = await vfsManager.getIndexStats(syncPairId: syncPairId)
            let data = try? JSONEncoder().encode(stats)
            reply(data)
        }
    }

    // MARK: - ========== Sync Operations ==========

    func syncNow(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void) {
        logXPCReceive("syncNow", params: ["syncPairId": syncPairId])
        Task {
            do {
                try await syncManager.syncNow(syncPairId: syncPairId)
                logXPCReply("syncNow", success: true)
                reply(true, nil)
            } catch {
                logXPCReply("syncNow", success: false, error: error.localizedDescription)
                reply(false, error.localizedDescription)
            }
        }
    }

    func syncAll(withReply reply: @escaping (Bool, String?) -> Void) {
        logXPCReceive("syncAll")
        Task {
            do {
                try await syncManager.syncAll()
                logXPCReply("syncAll", success: true)
                reply(true, nil)
            } catch {
                logXPCReply("syncAll", success: false, error: error.localizedDescription)
                reply(false, error.localizedDescription)
            }
        }
    }

    func syncFile(virtualPath: String,
                  syncPairId: String,
                  withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                try await syncManager.syncFile(virtualPath: virtualPath, syncPairId: syncPairId)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func syncPause(syncPairId: String,
                   withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            await syncManager.pause(syncPairId: syncPairId)
            reply(true, nil)
        }
    }

    func syncResume(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            await syncManager.resume(syncPairId: syncPairId)
            reply(true, nil)
        }
    }

    func syncCancel(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            await syncManager.cancel(syncPairId: syncPairId)
            reply(true, nil)
        }
    }

    func syncGetStatus(syncPairId: String,
                       withReply reply: @escaping (Data) -> Void) {
        Task {
            let status = await syncManager.getStatus(syncPairId: syncPairId)
            let data = (try? JSONEncoder().encode(status)) ?? Data()
            reply(data)
        }
    }

    func syncGetAllStatus(withReply reply: @escaping (Data) -> Void) {
        Task {
            let statuses = await syncManager.getAllStatus()
            let data = (try? JSONEncoder().encode(statuses)) ?? Data()
            reply(data)
        }
    }

    func syncGetPendingQueue(syncPairId: String,
                             withReply reply: @escaping (Data) -> Void) {
        Task {
            let queue = await syncManager.getPendingQueue(syncPairId: syncPairId)
            let data = (try? JSONEncoder().encode(queue)) ?? Data()
            reply(data)
        }
    }

    func syncGetProgress(syncPairId: String,
                         withReply reply: @escaping (Data?) -> Void) {
        Task {
            if let progress = await syncManager.getProgress(syncPairId: syncPairId) {
                let data = try? JSONEncoder().encode(progress)
                reply(data)
            } else {
                reply(nil)
            }
        }
    }

    func syncGetHistory(syncPairId: String,
                        limit: Int,
                        withReply reply: @escaping (Data) -> Void) {
        Task {
            let history = await syncManager.getHistory(syncPairId: syncPairId, limit: limit)
            let data = (try? JSONEncoder().encode(history)) ?? Data()
            reply(data)
        }
    }

    func syncGetStatistics(syncPairId: String,
                           withReply reply: @escaping (Data?) -> Void) {
        Task {
            if let stats = await syncManager.getStatistics(syncPairId: syncPairId) {
                let data = try? JSONEncoder().encode(stats)
                reply(data)
            } else {
                reply(nil)
            }
        }
    }

    func syncGetDirtyFiles(syncPairId: String,
                           withReply reply: @escaping (Data) -> Void) {
        Task {
            let files = await syncManager.getDirtyFiles(syncPairId: syncPairId)
            let data = (try? JSONEncoder().encode(files)) ?? Data()
            reply(data)
        }
    }

    func syncMarkFileDirty(virtualPath: String,
                           syncPairId: String,
                           withReply reply: @escaping (Bool) -> Void) {
        Task {
            await syncManager.markFileDirty(virtualPath: virtualPath, syncPairId: syncPairId)
            reply(true)
        }
    }

    func syncClearFileDirty(virtualPath: String,
                            syncPairId: String,
                            withReply reply: @escaping (Bool) -> Void) {
        Task {
            await syncManager.clearFileDirty(virtualPath: virtualPath, syncPairId: syncPairId)
            reply(true)
        }
    }

    func syncUpdateConfig(syncPairId: String,
                          configData: Data,
                          withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                let syncConfig = try JSONDecoder().decode(SyncPairConfig.self, from: configData)
                await syncManager.updateConfig(syncPairId: syncPairId, config: syncConfig)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func diskConnected(diskName: String,
                       mountPoint: String,
                       withReply reply: @escaping (Bool) -> Void) {
        Task {
            await syncManager.diskConnected(diskName: diskName, mountPoint: mountPoint)

            // Also update VFS external paths
            for syncPair in config.syncPairs where syncPair.diskId == diskName {
                let externalPath = mountPoint + "/" + syncPair.externalRelativePath
                try? await vfsManager.updateExternalPath(syncPairId: syncPair.id, newPath: externalPath)
                await vfsManager.setExternalOffline(syncPairId: syncPair.id, offline: false)
            }

            reply(true)
        }
    }

    func diskDisconnected(diskName: String,
                          withReply reply: @escaping (Bool) -> Void) {
        Task {
            await syncManager.diskDisconnected(diskName: diskName)

            // Also update VFS state
            for syncPair in config.syncPairs where syncPair.diskId == diskName {
                await vfsManager.setExternalOffline(syncPairId: syncPair.id, offline: true)
            }

            reply(true)
        }
    }

    // MARK: - ========== Privileged Operations ==========

    func privilegedLockDirectory(_ path: String,
                                 withReply reply: @escaping (Bool, String?) -> Void) {
        let result = PrivilegedOperations.lockDirectory(path)
        reply(result.success, result.error)
    }

    func privilegedUnlockDirectory(_ path: String,
                                   withReply reply: @escaping (Bool, String?) -> Void) {
        let result = PrivilegedOperations.unlockDirectory(path)
        reply(result.success, result.error)
    }

    func privilegedSetACL(_ path: String,
                          deny: Bool,
                          permissions: [String],
                          user: String,
                          withReply reply: @escaping (Bool, String?) -> Void) {
        let result = PrivilegedOperations.setACL(path, deny: deny, permissions: permissions, user: user)
        reply(result.success, result.error)
    }

    func privilegedRemoveACL(_ path: String,
                             withReply reply: @escaping (Bool, String?) -> Void) {
        let result = PrivilegedOperations.removeACL(path)
        reply(result.success, result.error)
    }

    func privilegedHideDirectory(_ path: String,
                                 withReply reply: @escaping (Bool, String?) -> Void) {
        let result = PrivilegedOperations.hideDirectory(path)
        reply(result.success, result.error)
    }

    func privilegedUnhideDirectory(_ path: String,
                                   withReply reply: @escaping (Bool, String?) -> Void) {
        let result = PrivilegedOperations.unhideDirectory(path)
        reply(result.success, result.error)
    }

    func privilegedProtectDirectory(_ path: String,
                                    withReply reply: @escaping (Bool, String?) -> Void) {
        let result = PrivilegedOperations.protectDirectory(path)
        reply(result.success, result.error)
    }

    func privilegedUnprotectDirectory(_ path: String,
                                      withReply reply: @escaping (Bool, String?) -> Void) {
        let result = PrivilegedOperations.unprotectDirectory(path)
        reply(result.success, result.error)
    }

    func privilegedCreateDirectory(_ path: String,
                                   withReply reply: @escaping (Bool, String?) -> Void) {
        let result = PrivilegedOperations.createDirectory(path)
        reply(result.success, result.error)
    }

    func privilegedMoveItem(from source: String,
                            to destination: String,
                            withReply reply: @escaping (Bool, String?) -> Void) {
        let result = PrivilegedOperations.moveItem(from: source, to: destination)
        reply(result.success, result.error)
    }

    func privilegedRemoveItem(_ path: String,
                              withReply reply: @escaping (Bool, String?) -> Void) {
        let result = PrivilegedOperations.removeItem(path)
        reply(result.success, result.error)
    }

    // MARK: - ========== Eviction Operations ==========

    func evictionTrigger(syncPairId: String,
                         targetFreeSpace: Int64,
                         withReply reply: @escaping (Bool, Int64, String?) -> Void) {
        Task {
            let result = await evictionManager.evict(syncPairId: syncPairId, targetFreeSpace: targetFreeSpace)
            if result.errors.isEmpty {
                reply(true, result.freedSpace, nil)
            } else {
                reply(true, result.freedSpace, result.errors.joined(separator: "; "))
            }
        }
    }

    func evictionEvictFile(virtualPath: String,
                           syncPairId: String,
                           withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                try await evictionManager.evictFile(virtualPath: virtualPath, syncPairId: syncPairId)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func evictionPrefetchFile(virtualPath: String,
                              syncPairId: String,
                              withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                try await evictionManager.prefetchFile(virtualPath: virtualPath, syncPairId: syncPairId)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func evictionGetStats(withReply reply: @escaping (Data) -> Void) {
        Task {
            let stats = await evictionManager.getStats()
            let data = (try? JSONEncoder().encode(stats)) ?? Data()
            reply(data)
        }
    }

    func evictionUpdateConfig(triggerThreshold: Int64,
                              targetFreeSpace: Int64,
                              autoEnabled: Bool,
                              withReply reply: @escaping (Bool) -> Void) {
        Task {
            var config = await evictionManager.getConfig()
            config.triggerThreshold = triggerThreshold
            config.targetFreeSpace = targetFreeSpace
            config.autoEvictionEnabled = autoEnabled
            await evictionManager.updateConfig(config)

            if autoEnabled {
                await evictionManager.startAutoEviction()
            } else {
                await evictionManager.stopAutoEviction()
            }

            reply(true)
        }
    }

    // MARK: - ========== Data Query Operations ==========

    func dataGetFileEntry(virtualPath: String,
                          syncPairId: String,
                          withReply reply: @escaping (Data?) -> Void) {
        Task {
            let entry = await ServiceDatabaseManager.shared.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId)
            let data = entry != nil ? try? JSONEncoder().encode(entry) : nil
            reply(data)
        }
    }

    func dataGetAllFileEntries(syncPairId: String,
                               withReply reply: @escaping (Data) -> Void) {
        Task {
            let entries = await ServiceDatabaseManager.shared.getAllFileEntries(syncPairId: syncPairId)
            let data = (try? JSONEncoder().encode(entries)) ?? Data()
            reply(data)
        }
    }

    func dataGetSyncHistory(limit: Int,
                            withReply reply: @escaping (Data) -> Void) {
        Task {
            let history = await ServiceDatabaseManager.shared.getAllSyncHistory(limit: limit)
            let data = (try? JSONEncoder().encode(history)) ?? Data()
            reply(data)
        }
    }

    func dataGetSyncFileRecords(syncPairId: String,
                                limit: Int,
                                withReply reply: @escaping (Data) -> Void) {
        Task {
            let records = await ServiceDatabaseManager.shared.getSyncFileRecords(syncPairId: syncPairId, limit: limit)
            let data = (try? JSONEncoder().encode(records)) ?? Data()
            reply(data)
        }
    }

    func dataGetAllSyncFileRecords(limit: Int,
                                   offset: Int,
                                   withReply reply: @escaping (Data) -> Void) {
        Task {
            let records = await ServiceDatabaseManager.shared.getAllSyncFileRecords(limit: limit, offset: offset)
            let data = (try? JSONEncoder().encode(records)) ?? Data()
            reply(data)
        }
    }

    func dataGetTreeVersion(syncPairId: String,
                            source: String,
                            withReply reply: @escaping (String?) -> Void) {
        Task {
            let treeSource: ServiceTreeSource = source == "local" ? .local : .external
            let version = await ServiceTreeVersionManager.shared.getCurrentVersion(syncPairId: syncPairId, source: treeSource)
            reply(version)
        }
    }

    func dataCheckTreeVersions(localDir: String,
                               externalDir: String?,
                               syncPairId: String,
                               withReply reply: @escaping (Data) -> Void) {
        Task {
            let result = await ServiceTreeVersionManager.shared.checkVersionsOnStartup(
                localDir: localDir,
                externalDir: externalDir,
                syncPairId: syncPairId
            )
            // Encode result
            let resultDict: [String: Any] = [
                "externalConnected": result.externalConnected,
                "needRebuildLocal": result.needRebuildLocal,
                "needRebuildExternal": result.needRebuildExternal,
                "needsAnyRebuild": result.needsAnyRebuild
            ]
            let data = (try? JSONSerialization.data(withJSONObject: resultDict)) ?? Data()
            reply(data)
        }
    }

    func dataRebuildTree(rootPath: String,
                         syncPairId: String,
                         source: String,
                         withReply reply: @escaping (Bool, String?, String?) -> Void) {
        Task {
            do {
                let treeSource: ServiceTreeSource = source == "local" ? .local : .external
                let (entries, version) = try await ServiceTreeVersionManager.shared.rebuildTree(
                    rootPath: rootPath,
                    syncPairId: syncPairId,
                    source: treeSource
                )
                // Save to database
                await ServiceDatabaseManager.shared.saveFileEntries(entries)
                reply(true, version, nil)
            } catch {
                reply(false, nil, error.localizedDescription)
            }
        }
    }

    func dataInvalidateTreeVersion(syncPairId: String,
                                   source: String,
                                   withReply reply: @escaping (Bool) -> Void) {
        Task {
            let treeSource: ServiceTreeSource = source == "local" ? .local : .external
            await ServiceTreeVersionManager.shared.invalidateVersion(syncPairId: syncPairId, source: treeSource)
            reply(true)
        }
    }

    // MARK: - ========== General Operations ==========

    func setUserHome(_ path: String, withReply reply: @escaping (Bool) -> Void) {
        UserPathManager.shared.setUserHome(path)
        logger.info("User home directory set: \(path)")
        reply(true)
    }

    func reloadConfig(withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            await reloadConfig()
            reply(true, nil)
        }
    }

    func prepareForShutdown(withReply reply: @escaping (Bool) -> Void) {
        Task {
            await stopScheduler()
            await unmountAllVFS()
            await waitForSyncCompletion()
            reply(true)
        }
    }

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(Constants.version)
    }

    func getVersionInfo(withReply reply: @escaping (Data) -> Void) {
        let info = ServiceVersionInfo(
            version: Constants.version,
            buildNumber: Constants.ServiceVersion.buildNumber,
            protocolVersion: Constants.ServiceVersion.protocolVersion,
            minAppVersion: Constants.ServiceVersion.minAppVersion,
            startedAt: startedAt
        )
        let data = info.toData() ?? Data()
        reply(data)
    }

    func checkCompatibility(appVersion: String,
                            withReply reply: @escaping (Bool, String?, Bool) -> Void) {
        // Compare version numbers
        let minVersion = Constants.ServiceVersion.minAppVersion
        let isCompatible = compareVersions(appVersion, minVersion) >= 0

        if !isCompatible {
            reply(false, "App version \(appVersion) is too old, requires \(minVersion) or higher", false)
            return
        }

        // Check if service needs update
        let serviceVersion = Constants.version
        let needsServiceUpdate = compareVersions(appVersion, serviceVersion) > 0

        if needsServiceUpdate {
            reply(true, "Service version \(serviceVersion) is outdated, consider updating", true)
        } else {
            reply(true, nil, false)
        }
    }

    /// Compare version numbers (returns: -1 less than, 0 equal, 1 greater than)
    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(parts1.count, parts2.count)
        for i in 0..<maxLen {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return -1 }
            if p1 > p2 { return 1 }
        }
        return 0
    }

    func healthCheck(withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            let vfsOK = await vfsManager.healthCheck()
            let syncOK = await syncManager.healthCheck()
            let allOK = vfsOK && syncOK

            if allOK {
                reply(true, nil)
            } else {
                var issues: [String] = []
                if !vfsOK { issues.append("VFS") }
                if !syncOK { issues.append("Sync") }
                reply(false, "Problematic modules: \(issues.joined(separator: ", "))")
            }
        }
    }

    // MARK: - ========== Config Operations ==========

    func configGetAll(withReply reply: @escaping (Data) -> Void) {
        let data = (try? JSONEncoder().encode(config)) ?? Data()
        reply(data)
    }

    func configUpdate(configData: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        guard let newConfig = try? JSONDecoder().decode(AppConfig.self, from: configData) else {
            reply(false, "Config parsing failed")
            return
        }
        config = newConfig
        do {
            try configData.write(to: Constants.Paths.config)
            Task { await syncManager.updateConfig(config) }
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func configGetDisks(withReply reply: @escaping (Data) -> Void) {
        let data = (try? JSONEncoder().encode(config.disks)) ?? Data()
        reply(data)
    }

    func configAddDisk(diskData: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        guard let disk = try? JSONDecoder().decode(DiskConfig.self, from: diskData) else {
            reply(false, "Disk config parsing failed")
            return
        }
        config.disks.append(disk)
        saveConfig()
        reply(true, nil)
    }

    func configRemoveDisk(diskId: String, withReply reply: @escaping (Bool, String?) -> Void) {
        config.disks.removeAll { $0.id == diskId }
        saveConfig()
        reply(true, nil)
    }

    func configGetSyncPairs(withReply reply: @escaping (Data) -> Void) {
        let data = (try? JSONEncoder().encode(config.syncPairs)) ?? Data()
        reply(data)
    }

    func configAddSyncPair(pairData: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        guard let pair = try? JSONDecoder().decode(SyncPairConfig.self, from: pairData) else {
            reply(false, "Sync pair config parsing failed")
            return
        }
        config.syncPairs.append(pair)
        saveConfig()
        reply(true, nil)
    }

    func configRemoveSyncPair(pairId: String, withReply reply: @escaping (Bool, String?) -> Void) {
        config.syncPairs.removeAll { $0.id == pairId }
        saveConfig()
        reply(true, nil)
    }

    func configGetNotifications(withReply reply: @escaping (Data) -> Void) {
        let data = (try? JSONEncoder().encode(config.notifications)) ?? Data()
        reply(data)
    }

    func configUpdateNotifications(configData: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        guard let notifConfig = try? JSONDecoder().decode(NotificationConfig.self, from: configData) else {
            reply(false, "Notification config parsing failed")
            return
        }
        config.notifications = notifConfig
        saveConfig()
        reply(true, nil)
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: Constants.Paths.config)
        }
    }

    // MARK: - ========== Notification Operations ==========

    func notificationSave(recordData: Data, withReply reply: @escaping (Bool) -> Void) {
        // TODO: Implement notification record saving
        reply(true)
    }

    func notificationGetAll(limit: Int, withReply reply: @escaping (Data) -> Void) {
        // TODO: Implement fetching notification records from database
        let emptyArray: [NotificationRecord] = []
        let data = (try? JSONEncoder().encode(emptyArray)) ?? Data()
        reply(data)
    }

    func notificationGetUnreadCount(withReply reply: @escaping (Int) -> Void) {
        // TODO: Implement unread count
        reply(0)
    }

    func notificationMarkAsRead(recordId: UInt64, withReply reply: @escaping (Bool) -> Void) {
        // TODO: Implement mark as read
        reply(true)
    }

    func notificationMarkAllAsRead(withReply reply: @escaping (Bool) -> Void) {
        // TODO: Implement mark all as read
        reply(true)
    }

    func notificationClearAll(withReply reply: @escaping (Bool) -> Void) {
        // TODO: Implement clear all notifications
        reply(true)
    }

    // MARK: - Internal Methods

    func autoMount() async {
        logger.info("autoMount: Starting, \(config.syncPairs.count) sync pairs, \(config.disks.count) disks")

        // Print config details
        for disk in config.disks {
            logger.info("Disk config: \(disk.name), id=\(disk.id), mountPath=\(disk.mountPath), isConnected=\(disk.isConnected)")
        }

        for syncPair in config.syncPairs {
            logger.info("Sync pair config: \(syncPair.name), id=\(syncPair.id), enabled=\(syncPair.enabled), diskId=\(syncPair.diskId)")
            logger.info("  - localDir=\(syncPair.localDir)")
            logger.info("  - externalRelativePath=\(syncPair.externalRelativePath)")
            logger.info("  - targetDir=\(syncPair.targetDir)")
        }

        for syncPair in config.syncPairs where syncPair.enabled {
            logger.info("Processing sync pair: \(syncPair.name)")

            // Find corresponding disk config
            guard let disk = config.disks.first(where: { $0.id == syncPair.diskId }) else {
                logger.warning("Disk config not found for sync pair \(syncPair.name) (diskId=\(syncPair.diskId))")
                continue
            }

            logger.info("Found disk: \(disk.name), isConnected=\(disk.isConnected)")

            do {
                // Note: externalDir should be nil rather than empty string to correctly trigger protection logic
                let externalPath: String? = disk.isConnected ? syncPair.fullExternalDir(diskMountPath: disk.mountPath) : nil
                logger.info("Preparing mount: syncPairId=\(syncPair.id)")
                logger.info("  - localDir=\(syncPair.localDir)")
                logger.info("  - externalDir=\(externalPath ?? "(nil - disk not connected)")")
                logger.info("  - targetDir=\(syncPair.targetDir)")
                logger.info("  - disk.isConnected=\(disk.isConnected)")

                try await vfsManager.mount(
                    syncPairId: syncPair.id,
                    localDir: syncPair.localDir,
                    externalDir: externalPath,
                    targetDir: syncPair.targetDir
                )
                logger.info("Auto-mount succeeded: \(syncPair.name)")
            } catch {
                logger.error("Auto-mount failed \(syncPair.name): \(error)")
            }
        }

        logger.info("autoMount: Processing complete")
    }

    func startScheduler() async {
        await syncManager.startScheduler(config: config)
    }

    func stopScheduler() async {
        await syncManager.stopScheduler()
    }

    func unmountAllVFS() async {
        try? await vfsManager.unmountAll()
    }

    func waitForSyncCompletion() async {
        await syncManager.waitForCompletion()
    }

    func reloadConfig() async {
        config = Self.loadConfig()
        await syncManager.updateConfig(config)
        logger.info("Config reloaded")
    }

    /// Pause sync before system sleep
    func pauseSyncForSleep() async {
        logger.info("[Power] System going to sleep, pausing sync")
        await syncManager.pauseAll()
    }

    /// Check and recover FUSE mounts after system wake
    func checkAndRecoverAfterWake() async {
        logger.info("[Power] System woke up, checking FUSE mounts...")
        await vfsManager.checkAndRecoverMounts()
        logger.info("[Power] Resuming sync")
        await syncManager.resumeAll()
    }

    // MARK: - ========== State Management Operations ==========

    func getFullState(withReply reply: @escaping (Data) -> Void) {
        logXPCReceive("getFullState")
        Task {
            let fullState = await ServiceStateManager.shared.getFullState()
            let data = (try? JSONEncoder().encode(fullState)) ?? Data()
            logXPCReplyData("getFullState", data: data)
            reply(data)
        }
    }

    func getGlobalState(withReply reply: @escaping (Int, String) -> Void) {
        logXPCReceive("getGlobalState")
        Task {
            let state = await ServiceStateManager.shared.getState()
            logXPCReply("getGlobalState", success: true, result: "\(state.rawValue) (\(state.name))")
            reply(state.rawValue, state.name)
        }
    }

    func canPerformOperation(_ operation: String, withReply reply: @escaping (Bool) -> Void) {
        logXPCReceive("canPerformOperation", params: ["operation": operation])
        Task {
            guard let op = ServiceOperation(rawValue: operation) else {
                logXPCReply("canPerformOperation", success: false, error: "Unknown operation")
                reply(false)
                return
            }
            let canPerform = await ServiceStateManager.shared.canPerform(op)
            logXPCReply("canPerformOperation", success: true, result: canPerform)
            reply(canPerform)
        }
    }

    // MARK: - ========== Activity Records ==========

    func getRecentActivities(withReply reply: @escaping (Data) -> Void) {
        logXPCReceive("getRecentActivities")
        Task {
            let activities = await ActivityManager.shared.getActivities()
            let data = (try? JSONEncoder().encode(activities)) ?? Data()
            logXPCReplyData("getRecentActivities", data: data)
            reply(data)
        }
    }
}
