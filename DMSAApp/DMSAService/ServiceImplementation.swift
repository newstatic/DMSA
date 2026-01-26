import Foundation

/// DMSA 服务实现
/// 实现 DMSAServiceProtocol，集成 VFS + Sync + Privileged 功能
final class ServiceImplementation: NSObject, DMSAServiceProtocol {

    private let logger = Logger.forService("DMSAService")
    private let vfsManager = VFSManager()
    private let syncManager = SyncManager()
    private let evictionManager = EvictionManager()
    private var config: AppConfig
    private let startedAt: Date = Date()

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

    // MARK: - ========== 数据查询操作 ==========

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
            // 编码结果
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
                // 保存到数据库
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

    // MARK: - ========== 通用操作 ==========

    func setUserHome(_ path: String, withReply reply: @escaping (Bool) -> Void) {
        UserPathManager.shared.setUserHome(path)
        logger.info("用户 Home 目录已设置: \(path)")
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
        // 比较版本号
        let minVersion = Constants.ServiceVersion.minAppVersion
        let isCompatible = compareVersions(appVersion, minVersion) >= 0

        if !isCompatible {
            reply(false, "App 版本 \(appVersion) 过低，需要 \(minVersion) 或更高版本", false)
            return
        }

        // 检查是否需要更新服务
        let serviceVersion = Constants.version
        let needsServiceUpdate = compareVersions(appVersion, serviceVersion) > 0

        if needsServiceUpdate {
            reply(true, "服务版本 \(serviceVersion) 较旧，建议更新服务", true)
        } else {
            reply(true, nil, false)
        }
    }

    /// 比较版本号 (返回: -1 小于, 0 等于, 1 大于)
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
                reply(false, "问题模块: \(issues.joined(separator: ", "))")
            }
        }
    }

    // MARK: - ========== 配置操作 ==========

    func configGetAll(withReply reply: @escaping (Data) -> Void) {
        let data = (try? JSONEncoder().encode(config)) ?? Data()
        reply(data)
    }

    func configUpdate(configData: Data, withReply reply: @escaping (Bool, String?) -> Void) {
        guard let newConfig = try? JSONDecoder().decode(AppConfig.self, from: configData) else {
            reply(false, "配置解析失败")
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
            reply(false, "磁盘配置解析失败")
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
            reply(false, "同步对配置解析失败")
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
            reply(false, "通知配置解析失败")
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

    // MARK: - ========== 通知操作 ==========

    func notificationSave(recordData: Data, withReply reply: @escaping (Bool) -> Void) {
        // TODO: 实现通知记录保存
        reply(true)
    }

    func notificationGetAll(limit: Int, withReply reply: @escaping (Data) -> Void) {
        // TODO: 实现从数据库获取通知记录
        let emptyArray: [NotificationRecord] = []
        let data = (try? JSONEncoder().encode(emptyArray)) ?? Data()
        reply(data)
    }

    func notificationGetUnreadCount(withReply reply: @escaping (Int) -> Void) {
        // TODO: 实现未读计数
        reply(0)
    }

    func notificationMarkAsRead(recordId: UInt64, withReply reply: @escaping (Bool) -> Void) {
        // TODO: 实现标记已读
        reply(true)
    }

    func notificationMarkAllAsRead(withReply reply: @escaping (Bool) -> Void) {
        // TODO: 实现全部标记已读
        reply(true)
    }

    func notificationClearAll(withReply reply: @escaping (Bool) -> Void) {
        // TODO: 实现清除所有通知
        reply(true)
    }

    // MARK: - 内部方法

    func autoMount() async {
        logger.info("autoMount: 开始处理，共 \(config.syncPairs.count) 个同步对，\(config.disks.count) 个磁盘")

        // 打印配置详情
        for disk in config.disks {
            logger.info("磁盘配置: \(disk.name), id=\(disk.id), mountPath=\(disk.mountPath), isConnected=\(disk.isConnected)")
        }

        for syncPair in config.syncPairs {
            logger.info("同步对配置: \(syncPair.name), id=\(syncPair.id), enabled=\(syncPair.enabled), diskId=\(syncPair.diskId)")
            logger.info("  - localDir=\(syncPair.localDir)")
            logger.info("  - externalRelativePath=\(syncPair.externalRelativePath)")
            logger.info("  - targetDir=\(syncPair.targetDir)")
        }

        for syncPair in config.syncPairs where syncPair.enabled {
            logger.info("处理同步对: \(syncPair.name)")

            // 查找对应的磁盘配置
            guard let disk = config.disks.first(where: { $0.id == syncPair.diskId }) else {
                logger.warning("找不到同步对 \(syncPair.name) 的磁盘配置 (diskId=\(syncPair.diskId))")
                continue
            }

            logger.info("找到磁盘: \(disk.name), isConnected=\(disk.isConnected)")

            do {
                // 注意：externalDir 需要是 nil 而不是空字符串，以便正确触发保护逻辑
                let externalPath: String? = disk.isConnected ? syncPair.fullExternalDir(diskMountPath: disk.mountPath) : nil
                logger.info("准备挂载: syncPairId=\(syncPair.id)")
                logger.info("  - localDir=\(syncPair.localDir)")
                logger.info("  - externalDir=\(externalPath ?? "(nil - 磁盘未连接)")")
                logger.info("  - targetDir=\(syncPair.targetDir)")
                logger.info("  - disk.isConnected=\(disk.isConnected)")

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

        logger.info("autoMount: 处理完成")
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
