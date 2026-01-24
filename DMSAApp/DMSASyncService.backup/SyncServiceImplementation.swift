import Foundation

/// Sync Service XPC 协议实现
final class SyncServiceImplementation: NSObject, SyncServiceProtocol {

    private let logger = Logger.forService("Sync")
    private let syncManager = SyncManager()
    private var config: AppConfig?

    override init() {
        super.init()
        loadConfig()
    }

    // MARK: - 配置管理

    private func loadConfig() {
        let configURL = Constants.Paths.config

        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            logger.warn("配置文件不存在或解析失败，使用默认配置")
            self.config = AppConfig()
            return
        }

        self.config = config
        logger.info("配置加载成功: \(config.syncPairs.count) 个同步对")
    }

    /// 启动调度器
    func startScheduler() async {
        await syncManager.startScheduler(config: config)
    }

    /// 恢复未完成的任务
    func resumePendingTasks() async {
        await syncManager.resumePendingTasks()
    }

    /// 调度文件同步
    func scheduleSync(file: String, syncPairId: String) async {
        await syncManager.scheduleFileSync(file: file, syncPairId: syncPairId)
    }

    /// 关闭服务
    func shutdown() async {
        await syncManager.shutdown()
    }

    /// 重新加载配置
    func reloadConfig() async {
        loadConfig()
        await syncManager.updateConfig(config)
    }

    // MARK: - SyncServiceProtocol 实现

    func syncNow(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void) {

        logger.info("立即同步请求: \(syncPairId)")

        Task {
            do {
                try await syncManager.syncNow(syncPairId: syncPairId)
                reply(true, nil)
            } catch {
                logger.error("同步失败: \(error)")
                reply(false, error.localizedDescription)
            }
        }
    }

    func syncAll(withReply reply: @escaping (Bool, String?) -> Void) {
        logger.info("同步所有同步对")

        Task {
            await syncManager.syncAll()
            reply(true, nil)
        }
    }

    func syncFile(virtualPath: String,
                  syncPairId: String,
                  withReply reply: @escaping (Bool, String?) -> Void) {

        logger.info("同步单个文件: \(virtualPath)")

        Task {
            do {
                try await syncManager.syncFile(virtualPath: virtualPath, syncPairId: syncPairId)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func pauseSync(syncPairId: String,
                   withReply reply: @escaping (Bool, String?) -> Void) {

        logger.info("暂停同步: \(syncPairId)")

        Task {
            await syncManager.pauseSync(syncPairId: syncPairId)
            reply(true, nil)
        }
    }

    func resumeSync(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void) {

        logger.info("恢复同步: \(syncPairId)")

        Task {
            await syncManager.resumeSync(syncPairId: syncPairId)
            reply(true, nil)
        }
    }

    func cancelSync(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void) {

        logger.info("取消同步: \(syncPairId)")

        Task {
            await syncManager.cancelSync(syncPairId: syncPairId)
            reply(true, nil)
        }
    }

    func getSyncStatus(syncPairId: String,
                       withReply reply: @escaping (Data) -> Void) {

        Task {
            let status = await syncManager.getSyncStatus(syncPairId: syncPairId)
            if let data = status.toData() {
                reply(data)
            } else {
                reply(Data())
            }
        }
    }

    func getAllSyncStatus(withReply reply: @escaping (Data) -> Void) {
        Task {
            let statuses = await syncManager.getAllSyncStatus()
            if let data = try? JSONEncoder().encode(statuses) {
                reply(data)
            } else {
                reply(Data())
            }
        }
    }

    func getPendingQueue(syncPairId: String,
                         withReply reply: @escaping (Data) -> Void) {

        Task {
            let queue = await syncManager.getPendingQueue(syncPairId: syncPairId)
            if let data = try? JSONEncoder().encode(queue) {
                reply(data)
            } else {
                reply(Data())
            }
        }
    }

    func getSyncProgress(syncPairId: String,
                         withReply reply: @escaping (Data?) -> Void) {

        Task {
            if let progress = await syncManager.getSyncProgress(syncPairId: syncPairId),
               let data = progress.toData() {
                reply(data)
            } else {
                reply(nil)
            }
        }
    }

    func getSyncHistory(syncPairId: String,
                        limit: Int,
                        withReply reply: @escaping (Data) -> Void) {

        Task {
            let history = await syncManager.getSyncHistory(syncPairId: syncPairId, limit: limit)
            if let data = try? JSONEncoder().encode(history) {
                reply(data)
            } else {
                reply(Data())
            }
        }
    }

    func getSyncStatistics(syncPairId: String,
                           withReply reply: @escaping (Data?) -> Void) {

        Task {
            if let stats = await syncManager.getSyncStatistics(syncPairId: syncPairId),
               let data = try? JSONEncoder().encode(stats) {
                reply(data)
            } else {
                reply(nil)
            }
        }
    }

    func getDirtyFiles(syncPairId: String,
                       withReply reply: @escaping (Data) -> Void) {

        Task {
            let files = await syncManager.getDirtyFiles(syncPairId: syncPairId)
            if let data = try? JSONEncoder().encode(files) {
                reply(data)
            } else {
                reply(Data())
            }
        }
    }

    func markFileDirty(virtualPath: String,
                       syncPairId: String,
                       withReply reply: @escaping (Bool) -> Void) {

        Task {
            await syncManager.markFileDirty(virtualPath: virtualPath, syncPairId: syncPairId)
            reply(true)
        }
    }

    func clearFileDirty(virtualPath: String,
                        syncPairId: String,
                        withReply reply: @escaping (Bool) -> Void) {

        Task {
            await syncManager.clearFileDirty(virtualPath: virtualPath, syncPairId: syncPairId)
            reply(true)
        }
    }

    func updateSyncConfig(syncPairId: String,
                          configData: Data,
                          withReply reply: @escaping (Bool, String?) -> Void) {

        // 更新特定同步对的配置
        // 这里可以实现更细粒度的配置更新
        reply(true, nil)
    }

    func reloadConfig(withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            await reloadConfig()
            reply(true, nil)
        }
    }

    func diskConnected(diskName: String,
                       mountPoint: String,
                       withReply reply: @escaping (Bool) -> Void) {

        logger.info("硬盘连接: \(diskName) at \(mountPoint)")

        Task {
            await syncManager.diskConnected(diskName: diskName, mountPoint: mountPoint)

            // 更新共享状态
            SharedState.update { state in
                if !state.connectedDisks.contains(diskName) {
                    state.connectedDisks.append(diskName)
                }
            }

            reply(true)
        }
    }

    func diskDisconnected(diskName: String,
                          withReply reply: @escaping (Bool) -> Void) {

        logger.info("硬盘断开: \(diskName)")

        Task {
            await syncManager.diskDisconnected(diskName: diskName)

            // 更新共享状态
            SharedState.update { state in
                state.connectedDisks.removeAll { $0 == diskName }
            }

            reply(true)
        }
    }

    func prepareForShutdown(withReply reply: @escaping (Bool) -> Void) {
        Task {
            await shutdown()
            reply(true)
        }
    }

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(Constants.version)
    }

    func healthCheck(withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            let isHealthy = await syncManager.isHealthy()
            if isHealthy {
                reply(true, "Sync Service 运行正常")
            } else {
                reply(false, "Sync Service 状态异常")
            }
        }
    }
}
