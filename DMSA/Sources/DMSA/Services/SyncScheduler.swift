import Foundation

/// 同步调度器
final class SyncScheduler {

    static let shared = SyncScheduler()

    private let syncEngine = SyncEngine.shared
    private let configManager = ConfigManager.shared
    private let diskManager = DiskManager.shared
    private let notificationManager = NotificationManager.shared

    private var pendingTasks: [SyncTask] = []
    private var isProcessing = false
    private let queue = DispatchQueue(label: "com.ttttt.dmsa.scheduler")

    // 防抖定时器
    private var debounceTimer: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 5.0  // 5秒防抖

    private init() {}

    // MARK: - 任务调度

    /// 调度同步任务
    func schedule(_ task: SyncTask) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // 检查是否已有相同任务
            if self.pendingTasks.contains(where: { $0.syncPair.id == task.syncPair.id }) {
                Logger.shared.debug("任务已在队列中: \(task.syncPair.localPath)")
                return
            }

            self.pendingTasks.append(task)
            Logger.shared.info("任务已调度: \(task.syncPair.localPath)")

            self.scheduleProcessingDebounced()
        }
    }

    /// 调度硬盘的所有同步任务
    func scheduleAllPairs(for disk: DiskConfig) {
        let pairs = configManager.getSyncPairs(forDiskId: disk.id)

        for pair in pairs {
            let task = SyncTask(syncPair: pair, disk: disk)
            schedule(task)
        }
    }

    /// 调度脏文件同步
    func scheduleDirtyFilesSync(_ dirtyFiles: [DirtyFile]) {
        guard !dirtyFiles.isEmpty else { return }

        Logger.shared.info("调度 \(dirtyFiles.count) 个脏文件同步")

        // 按 syncPairId 分组
        var filesByPair: [String: [DirtyFile]] = [:]
        for file in dirtyFiles {
            // 这里需要根据文件路径确定属于哪个 syncPair
            // 简化实现：触发所有活跃的同步对
            let pairs = configManager.config.syncPairs.filter { $0.enabled }
            for pair in pairs {
                let expandedPath = (pair.localPath as NSString).expandingTildeInPath
                if file.localPath.hasPrefix(expandedPath) {
                    var files = filesByPair[pair.id] ?? []
                    files.append(file)
                    filesByPair[pair.id] = files
                }
            }
        }

        // 为每个有脏文件的同步对创建任务
        for (pairId, _) in filesByPair {
            if let pair = configManager.config.syncPairs.first(where: { $0.id == pairId }),
               let disk = configManager.getDisk(byId: pair.diskId),
               disk.isConnected {
                let task = SyncTask(syncPair: pair, disk: disk)
                schedule(task)
            }
        }
    }

    // MARK: - 任务处理

    private func scheduleProcessingDebounced() {
        debounceTimer?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.processPendingTasks()
        }

        debounceTimer = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func processPendingTasks() {
        guard !isProcessing else {
            Logger.shared.debug("已在处理任务，跳过")
            return
        }

        guard !pendingTasks.isEmpty else {
            Logger.shared.debug("无待处理任务")
            return
        }

        isProcessing = true

        // 按优先级排序
        let sortedTasks = pendingTasks.sorted { $0.priority < $1.priority }
        pendingTasks.removeAll()

        Task {
            for task in sortedTasks {
                // 检查硬盘是否仍然连接
                guard diskManager.isDiskConnected(task.disk.id) else {
                    Logger.shared.warn("硬盘已断开，跳过任务: \(task.syncPair.localPath)")
                    continue
                }

                do {
                    _ = try await syncEngine.execute(task)
                } catch {
                    Logger.shared.error("任务执行失败: \(error.localizedDescription)")
                }
            }

            queue.async { [weak self] in
                self?.isProcessing = false

                // 如果处理期间又有新任务加入，继续处理
                if !(self?.pendingTasks.isEmpty ?? true) {
                    self?.processPendingTasks()
                }
            }
        }
    }

    // MARK: - 定时同步

    private var periodicTimer: Timer?

    /// 启动定时同步
    func startPeriodicSync(interval: TimeInterval = 3600) {  // 默认1小时
        stopPeriodicSync()

        periodicTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.triggerPeriodicSync()
        }

        Logger.shared.info("定时同步已启动，间隔: \(Int(interval))秒")
    }

    /// 停止定时同步
    func stopPeriodicSync() {
        periodicTimer?.invalidate()
        periodicTimer = nil
        Logger.shared.info("定时同步已停止")
    }

    private func triggerPeriodicSync() {
        Logger.shared.info("触发定时同步")

        for disk in diskManager.connectedDisks.values {
            scheduleAllPairs(for: disk)
        }
    }

    // MARK: - 状态查询

    /// 获取待处理任务数
    var pendingTaskCount: Int {
        return queue.sync { pendingTasks.count }
    }

    /// 是否有任务正在处理
    var isBusy: Bool {
        return queue.sync { isProcessing || !pendingTasks.isEmpty }
    }

    /// 取消所有待处理任务
    func cancelAllPending() {
        queue.async { [weak self] in
            self?.pendingTasks.removeAll()
            self?.debounceTimer?.cancel()
            Logger.shared.info("已取消所有待处理任务")
        }
    }

    /// 取消指定硬盘的所有任务
    func cancelTasks(forDiskId diskId: String) {
        queue.async { [weak self] in
            self?.pendingTasks.removeAll { $0.disk.id == diskId }
            Logger.shared.info("已取消硬盘 \(diskId) 的所有任务")
        }
    }
}

// MARK: - DirtyFile (供 WriteRouter 使用)

/// 脏文件记录
struct DirtyFile {
    let virtualPath: String
    let localPath: String
    let createdAt: Date
    var modifiedAt: Date
    var syncAttempts: Int = 0
    var lastSyncError: String?

    init(virtualPath: String, localPath: String) {
        self.virtualPath = virtualPath
        self.localPath = localPath
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
