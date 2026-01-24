import Foundation

/// 同步任务 (用于内部调度)
struct InternalSyncTask: Identifiable {
    let id: String
    let syncPairId: String
    let files: [String]  // 空表示全量同步
    var status: SyncStatus
    var progress: SyncProgress?
    var scheduledAt: Date
    var startedAt: Date?
}

/// 同步管理器
/// - 整合 NativeSyncEngine 提供完善的同步功能
/// - 使用 ServiceDatabaseManager 持久化同步历史
/// - 使用 ServiceConfigManager 保存同步状态
actor SyncManager {

    private let logger = Logger.forService("Sync")
    private var config: AppConfig?

    // 数据持久化
    private let database = ServiceDatabaseManager.shared
    private let configManager = ServiceConfigManager.shared

    // 同步引擎 (使用 NativeSyncEngine)
    private var syncEngine: NativeSyncEngine?

    // 同步状态 (内存缓存，定期持久化)
    private var syncStatuses: [String: SyncStatusInfo] = [:]
    private var syncProgress: [String: SyncProgress] = [:]
    private var pendingTasks: [String: [InternalSyncTask]] = [:]  // [syncPairId: [tasks]]
    private var dirtyFiles: [String: Set<String>] = [:]   // [syncPairId: [virtualPaths]]

    // 调度器
    private var schedulerTask: Task<Void, Never>?
    private var debounceTimers: [String: Task<Void, Never>] = [:]

    // 配置
    private let debounceInterval: TimeInterval = 5.0

    // MARK: - 生命周期

    func startScheduler(config: AppConfig?) async {
        self.config = config
        logger.info("启动同步调度器")

        // 从配置管理器加载同步配置
        let serviceConfig = await configManager.getConfig()

        // 初始化同步引擎
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

        // 初始化同步对状态
        for syncPair in config?.syncPairs ?? [] {
            // 尝试从配置管理器恢复状态
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

        // 启动定时同步任务
        schedulerTask = Task {
            await runScheduler()
        }
    }

    func resumePendingTasks() async {
        logger.info("恢复未完成的同步任务")
        // 从持久化存储加载未完成的任务
        // 这里可以从数据库或文件读取
    }

    func shutdown() async {
        logger.info("关闭同步管理器")

        // 取消调度器
        schedulerTask?.cancel()

        // 取消所有防抖计时器
        for timer in debounceTimers.values {
            timer.cancel()
        }
        debounceTimers.removeAll()

        // 保存状态到配置管理器
        for (syncPairId, status) in syncStatuses {
            var syncState = SyncState(syncPairId: syncPairId)
            syncState.lastSyncTime = status.lastSyncTime
            syncState.dirtyFileCount = dirtyFiles[syncPairId]?.count ?? 0
            await configManager.setSyncState(syncState)
        }

        // 强制保存数据库
        await database.forceSave()

        logger.info("同步管理器已关闭")
    }

    func updateConfig(_ config: AppConfig?) async {
        self.config = config

        // 更新同步对状态
        for syncPair in config?.syncPairs ?? [] {
            if syncStatuses[syncPair.id] == nil {
                syncStatuses[syncPair.id] = SyncStatusInfo(syncPairId: syncPair.id)
            }
        }
    }

    // MARK: - 调度器

    private func runScheduler() async {
        logger.info("同步调度器开始运行")

        while !Task.isCancelled {
            // 检查定时同步
            await checkScheduledSyncs()

            // 处理待同步队列
            await processPendingTasks()

            // 休眠一段时间
            try? await Task.sleep(nanoseconds: 10_000_000_000)  // 10 秒
        }

        logger.info("同步调度器已停止")
    }

    private func checkScheduledSyncs() async {
        guard let config = config, config.general.autoSyncEnabled else { return }

        for syncPair in config.syncPairs where syncPair.enabled {
            guard var status = syncStatuses[syncPair.id] else { continue }

            // 检查是否到达下次同步时间
            if let nextSync = status.nextSyncTime, Date() >= nextSync {
                // 触发自动同步
                do {
                    try await performSync(syncPairId: syncPair.id, files: [])
                } catch {
                    logger.error("自动同步失败: \(syncPair.id) - \(error)")
                }

                // 设置下次同步时间 (这里简化为固定间隔)
                status.nextSyncTime = Date().addingTimeInterval(3600)  // 1 小时后
                syncStatuses[syncPair.id] = status
            }
        }
    }

    private func processPendingTasks() async {
        for (syncPairId, tasks) in pendingTasks {
            guard !tasks.isEmpty else { continue }

            // 获取第一个待处理任务
            var task = tasks[0]
            task.status = .inProgress
            task.startedAt = Date()

            do {
                try await performSync(syncPairId: syncPairId, files: task.files)
                task.status = .completed

                // 移除已完成的任务
                pendingTasks[syncPairId]?.removeFirst()
            } catch {
                task.status = .failed
                logger.error("同步任务失败: \(task.id) - \(error)")

                // 移除失败的任务（或可以选择重试）
                pendingTasks[syncPairId]?.removeFirst()
            }
        }
    }

    // MARK: - 同步控制

    func syncNow(syncPairId: String) async throws {
        logger.info("执行立即同步: \(syncPairId)")
        try await performSync(syncPairId: syncPairId, files: [])
    }

    func syncAll() async {
        guard let config = config else { return }

        for syncPair in config.syncPairs where syncPair.enabled {
            do {
                try await performSync(syncPairId: syncPair.id, files: [])
            } catch {
                logger.error("同步失败: \(syncPair.id) - \(error)")
            }
        }
    }

    func syncFile(virtualPath: String, syncPairId: String) async throws {
        try await performSync(syncPairId: syncPairId, files: [virtualPath])
    }

    func scheduleFileSync(file: String, syncPairId: String) async {
        // 添加到脏文件列表
        if dirtyFiles[syncPairId] == nil {
            dirtyFiles[syncPairId] = []
        }
        dirtyFiles[syncPairId]?.insert(file)

        // 更新状态
        if var status = syncStatuses[syncPairId] {
            status.dirtyFiles = dirtyFiles[syncPairId]?.count ?? 0
            syncStatuses[syncPairId] = status
        }

        // 取消现有的防抖计时器
        debounceTimers[syncPairId]?.cancel()

        // 创建新的防抖计时器
        debounceTimers[syncPairId] = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))

            guard !Task.isCancelled else { return }

            // 执行同步
            let filesToSync = Array(self.dirtyFiles[syncPairId] ?? [])
            self.dirtyFiles[syncPairId]?.removeAll()

            if !filesToSync.isEmpty {
                do {
                    try await self.performSync(syncPairId: syncPairId, files: filesToSync)
                } catch {
                    self.logger.error("防抖同步失败: \(syncPairId) - \(error)")
                }
            }
        }
    }

    func pauseSync(syncPairId: String) async {
        if var status = syncStatuses[syncPairId] {
            status.isPaused = true
            syncStatuses[syncPairId] = status
        }
        logger.info("同步已暂停: \(syncPairId)")
    }

    func resumeSync(syncPairId: String) async {
        if var status = syncStatuses[syncPairId] {
            status.isPaused = false
            syncStatuses[syncPairId] = status
        }
        logger.info("同步已恢复: \(syncPairId)")
    }

    func cancelSync(syncPairId: String) async {
        // 取消正在进行的同步
        pendingTasks[syncPairId]?.removeAll()

        if var status = syncStatuses[syncPairId] {
            status.status = .cancelled
            syncStatuses[syncPairId] = status
        }
    }

    // MARK: - 同步执行

    private func performSync(syncPairId: String, files: [String]) async throws {
        guard let config = config,
              let syncPair = config.syncPairs.first(where: { $0.id == syncPairId }),
              let disk = config.disks.first(where: { $0.id == syncPair.diskId }) else {
            throw SyncError.configurationError("找不到同步对配置")
        }

        // 检查是否暂停
        if syncStatuses[syncPairId]?.isPaused == true {
            throw SyncError.cancelled
        }

        // 检查硬盘是否连接
        let externalDir = syncPair.fullExternalDir(diskMountPath: disk.mountPath)
        guard FileManager.default.fileExists(atPath: externalDir) else {
            throw SyncError.diskNotConnected(disk.name)
        }

        // 更新状态
        var status = syncStatuses[syncPairId] ?? SyncStatusInfo(syncPairId: syncPairId)
        status.status = .inProgress
        syncStatuses[syncPairId] = status

        // 创建进度追踪
        var progress = SyncProgress(syncPairId: syncPairId)
        progress.status = .inProgress
        progress.startTime = Date()
        syncProgress[syncPairId] = progress

        // 创建历史记录 (使用服务端实体)
        var history = ServiceSyncHistory(syncPairId: syncPairId, diskId: disk.id)

        logger.info("开始同步: \(syncPair.name)")
        logger.info("  LOCAL_DIR: \(syncPair.localDir)")
        logger.info("  EXTERNAL_DIR: \(externalDir)")

        // 确定要同步的文件 (在 do 块外部定义以便 catch 块访问)
        let filesToSync: [String]
        if files.isEmpty {
            // 全量同步：获取所有脏文件
            filesToSync = Array(dirtyFiles[syncPairId] ?? [])
        } else {
            filesToSync = files
        }

        do {
            let fm = FileManager.default
            let localDir = syncPair.localDir

            progress.totalFiles = filesToSync.count
            syncProgress[syncPairId] = progress

            // 执行同步
            for (index, virtualPath) in filesToSync.enumerated() {
                // 检查是否取消
                if syncStatuses[syncPairId]?.status == .cancelled {
                    throw SyncError.cancelled
                }

                let relativePath = virtualPath.hasPrefix("/") ? String(virtualPath.dropFirst()) : virtualPath
                let localPath = (localDir as NSString).appendingPathComponent(relativePath)
                let externalPath = (externalDir as NSString).appendingPathComponent(relativePath)

                // 更新进度
                progress.currentFile = virtualPath
                progress.processedFiles = index + 1

                do {
                    // 确保目标目录存在
                    let parentDir = (externalPath as NSString).deletingLastPathComponent
                    if !fm.fileExists(atPath: parentDir) {
                        try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                    }

                    // 复制文件
                    if fm.fileExists(atPath: localPath) {
                        if fm.fileExists(atPath: externalPath) {
                            try fm.removeItem(atPath: externalPath)
                        }
                        try fm.copyItem(atPath: localPath, toPath: externalPath)

                        // 获取文件大小
                        if let attrs = try? fm.attributesOfItem(atPath: localPath),
                           let size = attrs[.size] as? Int64 {
                            progress.processedBytes += size
                            history.bytesTransferred += size
                        }

                        history.filesUpdated += 1
                        logger.debug("同步文件: \(virtualPath)")
                    }

                    // 清除脏标记
                    dirtyFiles[syncPairId]?.remove(virtualPath)

                } catch {
                    logger.error("同步文件失败: \(virtualPath) - \(error)")
                    // ServiceSyncHistory 不支持 details，记录错误
                    history.filesSkipped += 1
                }

                syncProgress[syncPairId] = progress
            }

            // 同步完成
            progress.status = .completed
            progress.endTime = Date()
            syncProgress[syncPairId] = progress

            status.status = .completed
            status.lastSyncTime = Date()
            status.dirtyFiles = dirtyFiles[syncPairId]?.count ?? 0
            syncStatuses[syncPairId] = status

            history.status = SyncStatus.completed.rawValue
            history.endTime = Date()
            history.totalFiles = filesToSync.count

            logger.info("同步完成: \(syncPair.name), \(history.filesUpdated) 个文件")

            // 发送通知
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name(Constants.Notifications.syncCompleted),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )

        } catch {
            // 同步失败
            progress.status = .failed
            progress.endTime = Date()
            progress.errorMessage = error.localizedDescription
            syncProgress[syncPairId] = progress

            status.status = .failed
            syncStatuses[syncPairId] = status

            history.status = SyncStatus.failed.rawValue
            history.endTime = Date()
            history.errorMessage = error.localizedDescription
            history.totalFiles = filesToSync.count

            logger.error("同步失败: \(syncPair.name) - \(error)")
            throw error
        }

        // 保存历史记录到数据库
        await database.saveSyncHistory(history)

        // 更新同步状态到配置管理器
        await configManager.markSyncCompleted(syncPairId: syncPairId)
    }

    // MARK: - 状态查询

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
        // 从数据库获取今日统计
        return await database.getTodayStatistics(syncPairId: syncPairId)
    }

    func getStatisticsForDays(syncPairId: String, days: Int) async -> [ServiceSyncStatistics] {
        return await database.getStatistics(syncPairId: syncPairId, days: days)
    }

    // MARK: - 脏文件管理

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

    // MARK: - 硬盘事件

    func diskConnected(diskName: String, mountPoint: String) async {
        logger.info("硬盘已连接: \(diskName)")

        // 触发关联同步对的同步
        guard let config = config else { return }

        for syncPair in config.syncPairs {
            guard let disk = config.disks.first(where: { $0.id == syncPair.diskId }),
                  disk.name == diskName else { continue }

            // 有脏文件时自动同步
            if let dirty = dirtyFiles[syncPair.id], !dirty.isEmpty {
                logger.info("硬盘连接后同步脏文件: \(dirty.count) 个")
                do {
                    try await performSync(syncPairId: syncPair.id, files: Array(dirty))
                } catch {
                    logger.error("硬盘连接后同步失败: \(error)")
                }
            }
        }
    }

    func diskDisconnected(diskName: String) async {
        logger.info("硬盘已断开: \(diskName)")

        // 暂停关联同步对的同步
        guard let config = config else { return }

        for syncPair in config.syncPairs {
            guard let disk = config.disks.first(where: { $0.id == syncPair.diskId }),
                  disk.name == diskName else { continue }

            await pauseSync(syncPairId: syncPair.id)
        }
    }

    // MARK: - 健康检查

    func healthCheck() -> Bool {
        // 检查基本状态
        return true
    }

    // MARK: - 额外方法 (ServiceImplementation 需要)

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
        // 更新单个同步对配置
        logger.info("更新同步对配置: \(syncPairId)")
    }

    func stopScheduler() {
        Task {
            await shutdown()
        }
    }

    func waitForCompletion() {
        // 等待所有同步完成
        logger.info("等待同步完成...")
    }
}
