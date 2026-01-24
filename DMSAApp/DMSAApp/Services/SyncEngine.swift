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
    func syncEngine(_ engine: SyncEngine, didCompleteTask task: SyncTask, result: SyncResult)
    func syncEngine(_ engine: SyncEngine, didFailTask task: SyncTask, error: Error)
}

/// 同步引擎 - 使用原生同步引擎
final class SyncEngine {

    static let shared = SyncEngine()

    private let nativeEngine: NativeSyncEngine
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

    /// 是否已暂停
    var isPaused: Bool {
        return nativeEngine.isPaused
    }

    /// 当前进度
    var progress: SyncProgress {
        return nativeEngine.progress
    }

    private init() {
        // 从配置创建引擎配置
        let engineConfig = SyncEngine.createEngineConfig(from: configManager.config)
        self.nativeEngine = NativeSyncEngine(config: engineConfig)

        // 设置代理
        self.nativeEngine.delegate = self
    }

    // MARK: - 配置更新

    /// 从 AppConfig 创建引擎配置
    private static func createEngineConfig(from appConfig: AppConfig) -> NativeSyncEngine.Config {
        var config = NativeSyncEngine.Config()

        // 从 SyncEngineConfig 读取
        config.enableChecksum = appConfig.syncEngine.enableChecksum
        config.checksumAlgorithm = {
            switch appConfig.syncEngine.checksumAlgorithm {
            case .md5: return .md5
            case .sha256: return .sha256
            case .xxhash64: return .xxhash64
            }
        }()
        config.verifyAfterCopy = appConfig.syncEngine.verifyAfterCopy
        config.conflictStrategy = {
            switch appConfig.syncEngine.conflictStrategy {
            case .newerWins: return .newerWins
            case .largerWins: return .largerWins
            case .localWins: return .localWins
            case .externalWins: return .externalWins
            case .localWinsWithBackup: return .localWinsWithBackup
            case .externalWinsWithBackup: return .externalWinsWithBackup
            case .askUser: return .askUser
            case .keepBoth: return .keepBoth
            }
        }()
        config.backupSuffix = appConfig.syncEngine.backupSuffix
        config.enableDelete = appConfig.syncEngine.enableDelete
        config.bufferSize = appConfig.syncEngine.bufferSize
        config.parallelOperations = appConfig.syncEngine.parallelOperations
        config.includeHidden = appConfig.syncEngine.includeHidden
        config.followSymlinks = appConfig.syncEngine.followSymlinks
        config.enablePauseResume = appConfig.syncEngine.enablePauseResume
        config.stateCheckpointInterval = appConfig.syncEngine.stateCheckpointInterval

        // 从 FilterConfig 读取
        config.excludePatterns = appConfig.filters.excludePatterns
        config.maxFileSize = appConfig.filters.maxFileSize

        return config
    }

    /// 更新引擎配置
    func updateConfig() {
        let newConfig = SyncEngine.createEngineConfig(from: configManager.config)
        nativeEngine.config = newConfig
    }

    // MARK: - 公开方法

    /// 执行同步任务
    func execute(_ task: SyncTask) async throws -> SyncResult {
        guard currentTask == nil else {
            throw SyncError.alreadyInProgress
        }

        // 前置条件检查
        try await checkPreconditions(for: task)

        currentTask = task
        delegate?.syncEngine(self, didStartTask: task)

        Logger.shared.info("开始同步任务: \(task.syncPair.localPath) <-> \(task.disk.name)")

        defer {
            currentTask = nil
        }

        do {
            // 验证路径
            let localPath = (task.syncPair.localPath as NSString).expandingTildeInPath
            let externalPath = task.syncPair.externalFullPath(diskMountPath: task.disk.mountPath)
            try validatePaths(localPath: localPath, externalPath: externalPath, task: task)

            // 如果需要创建符号链接，先处理目录迁移和符号链接创建
            if task.syncPair.createSymlink && task.direction == .localToExternal {
                try setupVirtualMount(localPath: localPath, externalPath: externalPath, task: task)
            }

            // 确保目录存在
            try ensureDirectoriesExist(localPath: localPath, externalPath: externalPath, direction: task.direction)

            // 更新排除模式
            var config = nativeEngine.config
            config.excludePatterns = configManager.config.filters.excludePatterns + task.syncPair.excludePatterns
            nativeEngine.config = config

            // 执行同步
            let result = try await nativeEngine.execute(task)

            delegate?.syncEngine(self, didCompleteTask: task, result: result)
            return result
        } catch {
            delegate?.syncEngine(self, didFailTask: task, error: error)
            throw error
        }
    }

    // MARK: - 前置条件检查

    /// 检查同步前置条件
    private func checkPreconditions(for task: SyncTask) async throws {
        Logger.shared.info("检查同步前置条件...")

        // 1. 检查完全磁盘访问权限
        let permissionManager = await PermissionManager.shared
        await permissionManager.checkAllPermissions()

        guard await permissionManager.hasFullDiskAccess else {
            Logger.shared.error("前置条件检查失败: 缺少完全磁盘访问权限")
            throw SyncError.fullDiskAccessRequired
        }
        Logger.shared.info("✓ 完全磁盘访问权限已授权")

        // 2. 检查外置硬盘是否已挂载
        guard fileManager.fileExists(atPath: task.disk.mountPath) else {
            Logger.shared.error("前置条件检查失败: 外置硬盘未连接")
            throw SyncError.diskNotConnected(task.disk.name)
        }
        Logger.shared.info("✓ 外置硬盘 \(task.disk.name) 已连接")

        // 3. 如果需要创建符号链接，检查本地目录状态
        if task.syncPair.createSymlink && task.direction == .localToExternal {
            let localPath = (task.syncPair.localPath as NSString).expandingTildeInPath
            let externalPath = task.syncPair.externalFullPath(diskMountPath: task.disk.mountPath)

            // 检查本地路径是否已经是正确的符号链接
            if isVirtualMount(at: localPath) {
                if let dest = getSymlinkDestination(at: localPath), dest == externalPath {
                    Logger.shared.info("✓ 虚拟硬盘挂载点已正确配置")
                } else {
                    // 符号链接指向错误的位置
                    Logger.shared.warn("符号链接存在但指向错误位置，将重新配置")
                }
            } else {
                // 检查是否需要迁移
                let localBackupPath = localPath + "_Local"
                if fileManager.fileExists(atPath: localPath) && !fileManager.fileExists(atPath: localBackupPath) {
                    Logger.shared.info("本地目录需要迁移: \(localPath)")
                }
            }
        }

        Logger.shared.info("所有前置条件检查通过")
    }

    /// 设置虚拟硬盘挂载 (迁移目录 + 创建符号链接)
    private func setupVirtualMount(localPath: String, externalPath: String, task: SyncTask) throws {
        // 检查是否已经是正确的符号链接
        if isVirtualMount(at: localPath) {
            if let dest = getSymlinkDestination(at: localPath), dest == externalPath {
                Logger.shared.debug("虚拟硬盘挂载点已存在且正确: \(localPath) -> \(externalPath)")
                return
            }
            // 符号链接指向错误，需要删除并重新创建
            try fileManager.removeItem(atPath: localPath)
            Logger.shared.info("已删除错误的符号链接: \(localPath)")
        }

        let localBackupPath = localPath + "_Local"

        // 如果本地目录存在且不是符号链接，需要迁移
        if fileManager.fileExists(atPath: localPath) {
            // 检查备份目录是否已存在
            if fileManager.fileExists(atPath: localBackupPath) {
                Logger.shared.warn("本地备份目录已存在: \(localBackupPath)")
                throw SyncError.localBackupExists(localBackupPath)
            }

            // 迁移本地目录
            Logger.shared.info("迁移本地目录: \(localPath) -> \(localBackupPath)")
            do {
                // 先移除 ACL 限制（macOS 对 Downloads/Desktop/Documents 等目录设置了 deny delete ACL）
                removeACL(at: localPath)

                try fileManager.moveItem(atPath: localPath, toPath: localBackupPath)
                Logger.shared.info("✓ 本地目录迁移完成")
            } catch {
                Logger.shared.error("本地目录迁移失败: \(error.localizedDescription)")
                throw SyncError.renameLocalFailed(localPath, error.localizedDescription)
            }
        }

        // 确保外置目录存在
        if !fileManager.fileExists(atPath: externalPath) {
            try fileManager.createDirectory(atPath: externalPath, withIntermediateDirectories: true)
            Logger.shared.info("创建外置目录: \(externalPath)")
        }

        // 如果有迁移的本地数据，先复制到外置目录
        if fileManager.fileExists(atPath: localBackupPath) {
            Logger.shared.info("将本地数据复制到外置目录...")
            // 这里不需要复制，同步引擎会处理
        }

        // 创建符号链接
        do {
            try fileManager.createSymbolicLink(atPath: localPath, withDestinationPath: externalPath)
            Logger.shared.info("✓ 创建符号链接: \(localPath) -> \(externalPath)")
        } catch {
            // 符号链接创建失败，尝试恢复本地目录
            Logger.shared.error("创建符号链接失败: \(error.localizedDescription)")
            if fileManager.fileExists(atPath: localBackupPath) {
                try? fileManager.moveItem(atPath: localBackupPath, toPath: localPath)
                Logger.shared.info("已恢复本地目录: \(localBackupPath) -> \(localPath)")
            }
            throw SyncError.symlinkCreationFailed(localPath, error.localizedDescription)
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

    /// 暂停当前同步
    func pause() {
        nativeEngine.pause()
        Logger.shared.info("同步已暂停")
    }

    /// 恢复同步
    func resume() async throws {
        try await nativeEngine.resume()
        Logger.shared.info("同步已恢复")
    }

    /// 取消当前同步
    func cancel() {
        nativeEngine.cancel()
        currentTask = nil
        Logger.shared.info("同步已取消")
    }

    /// 预览同步计划（不执行）
    func preview(_ task: SyncTask) async throws -> SyncPlan {
        return try await nativeEngine.preview(task)
    }

    /// 检查是否有可恢复的同步
    func hasResumableSync(for syncPairId: String) -> Bool {
        return nativeEngine.hasResumableSync(for: syncPairId)
    }

    /// 获取可恢复同步的摘要
    func getResumeSummary(for syncPairId: String) -> String? {
        return nativeEngine.getResumeSummary(for: syncPairId)
    }

    // MARK: - 私有方法

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

    /// 移除符号链接并恢复本地目录
    func removeSymlinkAndRestore(localPath: String) throws {
        let localBackupPath = localPath + "_Local"
        let legacyBackupPath = localPath + "_backup"  // 兼容旧版本

        // 检查是否为符号链接
        guard fileManager.fileExists(atPath: localPath) else {
            Logger.shared.warn("路径不存在: \(localPath)")
            return
        }

        let attrs = try fileManager.attributesOfItem(atPath: localPath)
        if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            try fileManager.removeItem(atPath: localPath)
            Logger.shared.info("已删除符号链接: \(localPath)")

            // 恢复本地目录 (优先使用 _Local，兼容 _backup)
            if fileManager.fileExists(atPath: localBackupPath) {
                try fileManager.moveItem(atPath: localBackupPath, toPath: localPath)
                Logger.shared.info("已恢复本地目录: \(localBackupPath) -> \(localPath)")
            } else if fileManager.fileExists(atPath: legacyBackupPath) {
                try fileManager.moveItem(atPath: legacyBackupPath, toPath: localPath)
                Logger.shared.info("已恢复备份(旧版): \(legacyBackupPath) -> \(localPath)")
            } else {
                // 没有备份，创建空目录
                try fileManager.createDirectory(atPath: localPath, withIntermediateDirectories: true)
                Logger.shared.info("无本地备份，已创建空目录: \(localPath)")
            }
        }
    }

    /// 检查本地路径是否为虚拟盘挂载点
    func isVirtualMount(at localPath: String) -> Bool {
        guard fileManager.fileExists(atPath: localPath) else {
            return false
        }

        do {
            let attrs = try fileManager.attributesOfItem(atPath: localPath)
            return attrs[.type] as? FileAttributeType == .typeSymbolicLink
        } catch {
            return false
        }
    }

    /// 获取符号链接目标路径
    func getSymlinkDestination(at localPath: String) -> String? {
        guard isVirtualMount(at: localPath) else {
            return nil
        }

        return try? fileManager.destinationOfSymbolicLink(atPath: localPath)
    }

    /// 移除目录的 ACL 限制
    /// macOS 对 Downloads/Desktop/Documents 等用户目录设置了 "group:everyone deny delete" ACL
    /// 这会阻止移动/删除这些目录，即使有 FDA 权限
    private func removeACL(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["-N", path]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                Logger.shared.debug("已移除 ACL 限制: \(path)")
            } else {
                Logger.shared.warn("移除 ACL 失败 (exit \(process.terminationStatus)): \(path)")
            }
        } catch {
            Logger.shared.warn("移除 ACL 失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - NativeSyncEngineDelegate

extension SyncEngine: NativeSyncEngineDelegate {
    func nativeSyncEngine(_ engine: NativeSyncEngine, didStartTask task: SyncTask) {
        // 已在 execute 中处理
    }

    func nativeSyncEngine(_ engine: NativeSyncEngine, didUpdateProgress message: String, progress: Double) {
        if let task = currentTask {
            delegate?.syncEngine(self, didUpdateProgress: task, progress: progress, message: message)
        }
    }

    func nativeSyncEngine(_ engine: NativeSyncEngine, didCompleteTask task: SyncTask, result: SyncResult) {
        // 已在 execute 中处理
    }

    func nativeSyncEngine(_ engine: NativeSyncEngine, didFailTask task: SyncTask, error: Error) {
        // 已在 execute 中处理
    }
}
