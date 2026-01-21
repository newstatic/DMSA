import Foundation

/// 同步任务
struct SyncTask: Identifiable {
    let id: String
    let syncPair: SyncPairConfig
    let disk: DiskConfig
    let direction: SyncDirection
    let createdAt: Date
    var priority: Int = 0

    init(syncPair: SyncPairConfig, disk: DiskConfig, direction: SyncDirection? = nil) {
        self.id = UUID().uuidString
        self.syncPair = syncPair
        self.disk = disk
        self.direction = direction ?? syncPair.direction
        self.createdAt = Date()
    }
}

/// 同步引擎代理协议
protocol SyncEngineDelegate: AnyObject {
    func syncEngine(_ engine: SyncEngine, didStartTask task: SyncTask)
    func syncEngine(_ engine: SyncEngine, didUpdateProgress task: SyncTask, progress: Double, message: String)
    func syncEngine(_ engine: SyncEngine, didCompleteTask task: SyncTask, result: RsyncResult)
    func syncEngine(_ engine: SyncEngine, didFailTask task: SyncTask, error: Error)
}

/// 同步引擎
final class SyncEngine {

    static let shared = SyncEngine()

    private let rsync = RsyncWrapper.shared
    private let configManager = ConfigManager.shared
    private let fileManager = FileManager.default

    weak var delegate: SyncEngineDelegate?

    /// 当前正在执行的任务
    private(set) var currentTask: SyncTask?

    /// 任务队列
    private var taskQueue: [SyncTask] = []
    private let queue = DispatchQueue(label: "com.ttttt.dmsa.syncEngine")

    var isRunning: Bool {
        return currentTask != nil
    }

    private init() {}

    // MARK: - 公开方法

    /// 执行同步任务
    func execute(_ task: SyncTask) async throws -> RsyncResult {
        guard currentTask == nil else {
            throw SyncError.alreadyInProgress
        }

        currentTask = task
        delegate?.syncEngine(self, didStartTask: task)

        Logger.shared.info("开始同步任务: \(task.syncPair.localPath) <-> \(task.disk.name)")

        defer {
            currentTask = nil
        }

        do {
            let result = try await performSync(task)
            delegate?.syncEngine(self, didCompleteTask: task, result: result)
            return result
        } catch {
            delegate?.syncEngine(self, didFailTask: task, error: error)
            throw error
        }
    }

    /// 为指定硬盘执行所有同步
    func syncAllPairs(for disk: DiskConfig) async throws {
        let pairs = configManager.getSyncPairs(forDiskId: disk.id)

        guard !pairs.isEmpty else {
            Logger.shared.warn("硬盘 \(disk.name) 没有配置同步对")
            return
        }

        Logger.shared.info("开始同步硬盘 \(disk.name) 的 \(pairs.count) 个同步对")

        for pair in pairs {
            let task = SyncTask(syncPair: pair, disk: disk)
            do {
                _ = try await execute(task)
            } catch {
                Logger.shared.error("同步对 \(pair.localPath) 失败: \(error.localizedDescription)")
                // 继续处理下一个同步对
            }
        }
    }

    /// 取消当前同步
    func cancel() {
        rsync.cancel()
        currentTask = nil
        Logger.shared.info("同步已取消")
    }

    // MARK: - 私有方法

    private func performSync(_ task: SyncTask) async throws -> RsyncResult {
        let localPath = (task.syncPair.localPath as NSString).expandingTildeInPath
        let externalPath = task.syncPair.externalFullPath(diskMountPath: task.disk.mountPath)

        // 1. 验证路径
        try validatePaths(localPath: localPath, externalPath: externalPath, task: task)

        // 2. 确保目录存在
        try ensureDirectoriesExist(localPath: localPath, externalPath: externalPath, direction: task.direction)

        // 3. 构建 rsync 选项
        let options = buildRsyncOptions(for: task)

        // 4. 确定源和目标
        let (source, destination) = determineSourceAndDestination(
            localPath: localPath,
            externalPath: externalPath,
            direction: task.direction
        )

        // 5. 执行同步
        let result = try await rsync.sync(
            source: source,
            destination: destination,
            options: options
        ) { [weak self] message, progress in
            if let progress = progress {
                self?.delegate?.syncEngine(self!, didUpdateProgress: task, progress: progress, message: message)
            }
        }

        // 6. 处理符号链接 (如果配置了)
        if task.syncPair.createSymlink && result.success {
            try handleSymlink(localPath: localPath, externalPath: externalPath, task: task)
        }

        return result
    }

    private func validatePaths(localPath: String, externalPath: String, task: SyncTask) throws {
        // 检查外置硬盘是否已挂载
        guard fileManager.fileExists(atPath: task.disk.mountPath) else {
            throw SyncError.diskNotConnected(task.disk.name)
        }

        // 检查本地路径
        switch task.direction {
        case .localToExternal, .bidirectional:
            guard fileManager.fileExists(atPath: localPath) else {
                throw SyncError.sourceNotFound(localPath)
            }
        case .externalToLocal:
            guard fileManager.fileExists(atPath: externalPath) else {
                throw SyncError.sourceNotFound(externalPath)
            }
        }
    }

    private func ensureDirectoriesExist(localPath: String, externalPath: String, direction: SyncDirection) throws {
        switch direction {
        case .localToExternal:
            if !fileManager.fileExists(atPath: externalPath) {
                try fileManager.createDirectory(atPath: externalPath, withIntermediateDirectories: true)
                Logger.shared.info("创建外置目录: \(externalPath)")
            }
        case .externalToLocal:
            if !fileManager.fileExists(atPath: localPath) {
                try fileManager.createDirectory(atPath: localPath, withIntermediateDirectories: true)
                Logger.shared.info("创建本地目录: \(localPath)")
            }
        case .bidirectional:
            if !fileManager.fileExists(atPath: externalPath) {
                try fileManager.createDirectory(atPath: externalPath, withIntermediateDirectories: true)
            }
            if !fileManager.fileExists(atPath: localPath) {
                try fileManager.createDirectory(atPath: localPath, withIntermediateDirectories: true)
            }
        }
    }

    private func buildRsyncOptions(for task: SyncTask) -> RsyncOptions {
        var options = RsyncOptions()

        // 合并全局过滤规则和同步对特定规则
        options.excludePatterns = configManager.config.filters.excludePatterns + task.syncPair.excludePatterns

        // 双向同步时不使用 --delete
        options.delete = task.direction != .bidirectional

        return options
    }

    private func determineSourceAndDestination(
        localPath: String,
        externalPath: String,
        direction: SyncDirection
    ) -> (source: String, destination: String) {
        switch direction {
        case .localToExternal:
            return (localPath, externalPath)
        case .externalToLocal:
            return (externalPath, localPath)
        case .bidirectional:
            // 双向同步：比较修改时间，以较新的为源
            let localMtime = getDirectoryMtime(localPath)
            let externalMtime = getDirectoryMtime(externalPath)

            if localMtime >= externalMtime {
                Logger.shared.info("双向同步: 本地较新，本地 → 外置")
                return (localPath, externalPath)
            } else {
                Logger.shared.info("双向同步: 外置较新，外置 → 本地")
                return (externalPath, localPath)
            }
        }
    }

    private func getDirectoryMtime(_ path: String) -> Date {
        let attrs = try? fileManager.attributesOfItem(atPath: path)
        return attrs?[.modificationDate] as? Date ?? .distantPast
    }

    private func handleSymlink(localPath: String, externalPath: String, task: SyncTask) throws {
        // 只有 localToExternal 方向才创建符号链接
        guard task.direction == .localToExternal else { return }

        let backupPath = localPath + "_backup"

        // 检查本地路径是否已是符号链接
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: localPath, isDirectory: &isDirectory) {
            // 如果已经是指向正确位置的符号链接，跳过
            if let linkDest = try? fileManager.destinationOfSymbolicLink(atPath: localPath),
               linkDest == externalPath {
                Logger.shared.debug("符号链接已存在且正确: \(localPath) -> \(externalPath)")
                return
            }

            // 如果是普通目录，重命名为备份
            if isDirectory.boolValue {
                // 检查是否为符号链接
                let attrs = try fileManager.attributesOfItem(atPath: localPath)
                if attrs[.type] as? FileAttributeType != .typeSymbolicLink {
                    Logger.shared.info("重命名本地目录为备份: \(localPath) -> \(backupPath)")
                    try fileManager.moveItem(atPath: localPath, toPath: backupPath)
                }
            }
        }

        // 创建符号链接
        try fileManager.createSymbolicLink(atPath: localPath, withDestinationPath: externalPath)
        Logger.shared.info("创建符号链接: \(localPath) -> \(externalPath)")
    }

    /// 移除符号链接并恢复备份
    func removeSymlinkAndRestore(localPath: String) throws {
        let backupPath = localPath + "_backup"

        // 检查是否为符号链接
        let attrs = try fileManager.attributesOfItem(atPath: localPath)
        if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            try fileManager.removeItem(atPath: localPath)
            Logger.shared.info("已删除符号链接: \(localPath)")

            // 恢复备份
            if fileManager.fileExists(atPath: backupPath) {
                try fileManager.moveItem(atPath: backupPath, toPath: localPath)
                Logger.shared.info("已恢复备份: \(backupPath) -> \(localPath)")
            }
        }
    }
}
