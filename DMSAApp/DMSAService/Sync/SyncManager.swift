import Foundation

/// 同步任务
struct SyncTask: Identifiable {
    let id: String
    let syncPairId: String
    let files: [String]  // 空表示全量同步
    var status: SyncStatus
    var progress: SyncProgress?
    var scheduledAt: Date
    var startedAt: Date?
}

/// 同步管理器
actor SyncManager {

    private let logger = Logger.forService("Sync")
    private var config: AppConfig?

    // 同步状态
    private var syncStatuses: [String: SyncStatusInfo] = [:]
    private var syncProgress: [String: SyncProgress] = [:]
    private var pendingTasks: [String: [SyncTask]] = [:]  // [syncPairId: [tasks]]
    private var dirtyFiles: [String: Set<String>] = [:]   // [syncPairId: [virtualPaths]]
    private var syncHistory: [String: [SyncHistory]] = [:]  // [syncPairId: [history]]

    // 调度器
    private var schedulerTask: Task<Void, Never>?
    private var debounceTimers: [String: Task<Void, Never>] = [:]

    // 配置
    private let debounceInterval: TimeInterval = 5.0
    private let maxHistoryPerPair = 100

    // MARK: - 生命周期

    func startScheduler(config: AppConfig?) async {
        self.config = config
        logger.info("启动同步调度器")

        // 初始化同步对状态
        for syncPair in config?.syncPairs ?? [] {
            syncStatuses[syncPair.id] = SyncStatusInfo(syncPairId: syncPair.id)
            dirtyFiles[syncPair.id] = []
            syncHistory[syncPair.id] = []
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

        // 等待当前正在进行的同步完成
        // ...

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

        // 创建历史记录
        var history = SyncHistory(syncPairId: syncPairId, diskId: disk.id)

        logger.info("开始同步: \(syncPair.name)")
        logger.info("  LOCAL_DIR: \(syncPair.localDir)")
        logger.info("  EXTERNAL_DIR: \(externalDir)")

        do {
            let fm = FileManager.default
            let localDir = syncPair.localDir

            // 确定要同步的文件
            let filesToSync: [String]
            if files.isEmpty {
                // 全量同步：获取所有脏文件
                filesToSync = Array(dirtyFiles[syncPairId] ?? [])
            } else {
                filesToSync = files
            }

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
                    history.details.append(SyncOperationDetail(
                        path: virtualPath,
                        operation: .update,
                        size: 0
                    ))
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

            history.status = .completed
            history.endTime = Date()

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

            history.status = .failed
            history.endTime = Date()
            history.errorMessage = error.localizedDescription

            logger.error("同步失败: \(syncPair.name) - \(error)")
            throw error
        }

        // 保存历史记录
        if syncHistory[syncPairId] == nil {
            syncHistory[syncPairId] = []
        }
        syncHistory[syncPairId]?.insert(history, at: 0)

        // 限制历史记录数量
        if let count = syncHistory[syncPairId]?.count, count > maxHistoryPerPair {
            syncHistory[syncPairId]?.removeLast(count - maxHistoryPerPair)
        }
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

    func getSyncHistory(syncPairId: String, limit: Int) async -> [SyncHistory] {
        return Array((syncHistory[syncPairId] ?? []).prefix(limit))
    }

    func getSyncStatistics(syncPairId: String) async -> SyncStatistics? {
        // 计算统计信息
        guard let history = syncHistory[syncPairId] else { return nil }

        var stats = SyncStatistics(syncPairId: syncPairId)
        stats.totalSyncs = history.count
        stats.successfulSyncs = history.filter { $0.status == .completed }.count
        stats.failedSyncs = history.filter { $0.status == .failed }.count
        stats.totalFilesProcessed = history.reduce(0) { $0 + $1.totalFiles }
        stats.totalBytesTransferred = history.reduce(0) { $0 + $1.bytesTransferred }

        let durations = history.compactMap { $0.duration }
        if !durations.isEmpty {
            stats.averageDuration = durations.reduce(0, +) / Double(durations.count)
        }

        return stats
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

    func getHistory(syncPairId: String, limit: Int) -> [SyncHistory] {
        return Array((syncHistory[syncPairId] ?? []).prefix(limit))
    }

    func getStatistics(syncPairId: String) -> SyncStatistics? {
        guard let history = syncHistory[syncPairId] else { return nil }

        var stats = SyncStatistics(syncPairId: syncPairId)
        stats.totalSyncs = history.count
        stats.successfulSyncs = history.filter { $0.status == .completed }.count
        stats.failedSyncs = history.filter { $0.status == .failed }.count
        stats.totalFilesProcessed = history.reduce(0) { $0 + $1.totalFiles }
        stats.totalBytesTransferred = history.reduce(0) { $0 + $1.bytesTransferred }

        let durations = history.compactMap { $0.duration }
        if !durations.isEmpty {
            stats.averageDuration = durations.reduce(0, +) / Double(durations.count)
        }

        return stats
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
