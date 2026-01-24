import Foundation

/// DMSA 服务实现
/// 实现 DMSAServiceProtocol，集成 VFS + Sync + Privileged 功能
final class ServiceImplementation: NSObject, DMSAServiceProtocol {

    private let logger = Logger.forService("DMSAService")
    private let vfsManager = VFSManager()
    private let syncManager = SyncManager()
    private let evictionManager = EvictionManager()
    private var config: AppConfig

    override init() {
        self.config = Self.loadConfig()
        super.init()

        // 设置 EvictionManager 的依赖
        Task {
            await evictionManager.setManagers(vfs: vfsManager, sync: syncManager)
            await evictionManager.startAutoEviction()
        }

        logger.info("ServiceImplementation 初始化完成")
    }

    private static func loadConfig() -> AppConfig {
        let configURL = Constants.Paths.config
        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            Logger.forService("DMSAService").warning("配置加载失败，使用默认配置")
            return AppConfig()
        }
        return config
    }

    // MARK: - ========== VFS 操作 ==========

    func vfsMount(syncPairId: String,
                  localDir: String,
                  externalDir: String?,
                  targetDir: String,
                  withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                try await vfsManager.mount(
                    syncPairId: syncPairId,
                    localDir: localDir,
                    externalDir: externalDir,
                    targetDir: targetDir
                )
                logger.info("VFS 挂载成功: \(syncPairId)")
                reply(true, nil)
            } catch {
                logger.error("VFS 挂载失败: \(error)")
                reply(false, error.localizedDescription)
            }
        }
    }

    func vfsUnmount(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                try await vfsManager.unmount(syncPairId: syncPairId)
                logger.info("VFS 卸载成功: \(syncPairId)")
                reply(true, nil)
            } catch {
                logger.error("VFS 卸载失败: \(error)")
                reply(false, error.localizedDescription)
            }
        }
    }

    func vfsUnmountAll(withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            await vfsManager.unmountAll()
            logger.info("所有 VFS 已卸载")
            reply(true, nil)
        }
    }

    func vfsGetMountStatus(syncPairId: String,
                           withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            let isMounted = await vfsManager.isMounted(syncPairId: syncPairId)
            reply(isMounted, nil)
        }
    }

    func vfsGetAllMounts(withReply reply: @escaping (Data) -> Void) {
        Task {
            let mounts = await vfsManager.getAllMounts()
            let data = (try? JSONEncoder().encode(mounts)) ?? Data()
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

    // MARK: - ========== 同步操作 ==========

    func syncNow(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                try await syncManager.syncNow(syncPairId: syncPairId)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func syncAll(withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            do {
                try await syncManager.syncAll()
                reply(true, nil)
            } catch {
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

            // 同时更新 VFS 的外部路径
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

            // 同时更新 VFS 状态
            for syncPair in config.syncPairs where syncPair.diskId == diskName {
                await vfsManager.setExternalOffline(syncPairId: syncPair.id, offline: true)
            }

            reply(true)
        }
    }

    // MARK: - ========== 特权操作 ==========

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

    // MARK: - ========== 淘汰操作 ==========

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

    // MARK: - ========== 通用操作 ==========

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
                reply(false, "问题模块: \(issues.joined(separator: ", "))")
            }
        }
    }

    // MARK: - 内部方法

    func autoMount() async {
        for syncPair in config.syncPairs where syncPair.enabled {
            // 查找对应的磁盘配置
            guard let disk = config.disks.first(where: { $0.id == syncPair.diskId }) else {
                logger.warning("找不到同步对 \(syncPair.name) 的磁盘配置")
                continue
            }

            do {
                let externalPath = disk.isConnected ? syncPair.fullExternalDir(diskMountPath: disk.mountPath) : ""
                try await vfsManager.mount(
                    syncPairId: syncPair.id,
                    localDir: syncPair.localDir,
                    externalDir: externalPath,
                    targetDir: syncPair.targetDir
                )
                logger.info("自动挂载成功: \(syncPair.name)")
            } catch {
                logger.error("自动挂载失败 \(syncPair.name): \(error)")
            }
        }
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
        logger.info("配置已重新加载")
    }
}
