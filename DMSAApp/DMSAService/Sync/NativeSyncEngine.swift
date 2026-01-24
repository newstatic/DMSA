import Foundation
import Combine

/// 原生同步引擎 - 替代 rsync 的完整同步解决方案
class NativeSyncEngine: ObservableObject {

    // MARK: - 配置

    struct Config {
        /// 是否启用校验和
        var enableChecksum: Bool = true

        /// 校验算法
        var checksumAlgorithm: FileHasher.HashAlgorithm = .md5

        /// 复制后验证
        var verifyAfterCopy: Bool = true

        /// 冲突策略
        var conflictStrategy: ConflictStrategy = .localWinsWithBackup

        /// 备份后缀
        var backupSuffix: String = "_backup"

        /// 启用删除
        var enableDelete: Bool = true

        /// 缓冲区大小
        var bufferSize: Int = 1024 * 1024

        /// 并行操作数
        var parallelOperations: Int = 4

        /// 排除模式
        var excludePatterns: [String] = []

        /// 包含隐藏文件
        var includeHidden: Bool = false

        /// 最大文件大小
        var maxFileSize: Int64? = nil

        /// 跟随符号链接
        var followSymlinks: Bool = false

        /// 启用暂停/恢复
        var enablePauseResume: Bool = true

        /// 状态检查点间隔
        var stateCheckpointInterval: Int = 50

        static var `default`: Config { Config() }
    }

    // MARK: - 组件

    private let scanner: FileScanner
    private let hasher: FileHasher
    private let diffEngine: DiffEngine
    private let copier: FileCopier
    private let stateManager: SyncStateManager
    private let conflictResolver: ConflictResolver
    private let lockManager = LockManager.shared

    // MARK: - 状态

    /// 同步进度
    @Published var progress: ServiceSyncProgress

    /// 当前同步计划
    @Published var currentPlan: SyncPlan?

    /// 当前状态
    var currentState: SyncStateManager.SyncState?

    /// 是否已暂停
    @Published var isPaused: Bool = false

    /// 是否已取消
    @Published var isCancelled: Bool = false

    /// 是否正在同步
    @Published var isSyncing: Bool = false

    /// 配置
    var config: Config

    /// 当前锁定的文件路径 (用于同步完成后释放锁)
    private var lockedPaths: Set<String> = []
    private let lockedPathsLock = NSLock()

    // MARK: - 进度回调节流

    /// 上次进度回调时间
    private var lastProgressCallbackTime: Date = .distantPast

    /// 进度回调最小间隔 (秒)
    private let progressCallbackInterval: TimeInterval = 0.1

    /// 上次报告的进度值
    private var lastReportedProgress: Double = -1

    // MARK: - 委托

    weak var delegate: NativeSyncEngineDelegate?

    // MARK: - Logger

    private let logger = Logger.forService("NativeSyncEngine")

    // MARK: - 初始化

    init(config: Config = .default) {
        self.config = config
        self.progress = ServiceSyncProgress()

        // 初始化组件
        self.scanner = FileScanner(
            excludePatterns: config.excludePatterns,
            includeHidden: config.includeHidden,
            maxFileSize: config.maxFileSize,
            followSymlinks: config.followSymlinks
        )

        self.hasher = FileHasher(bufferSize: config.bufferSize)

        self.diffEngine = DiffEngine()

        self.copier = FileCopier()

        self.stateManager = SyncStateManager()
        self.stateManager.checkpointInterval = config.stateCheckpointInterval

        self.conflictResolver = ConflictResolver(
            defaultStrategy: config.conflictStrategy,
            backupSuffix: config.backupSuffix
        )
    }

    // MARK: - 主要方法

    /// 执行同步任务
    func execute(_ task: SyncTask) async throws -> SyncResult {
        guard !isSyncing else {
            throw NativeSyncError.alreadyInProgress
        }

        isSyncing = true
        isCancelled = false
        isPaused = false
        progress.reset()
        progress.start()
        resetProgressThrottle()

        let startTime = Date()

        defer {
            isSyncing = false
            progress.updateElapsedTime()
        }

        // 通知开始
        delegate?.nativeSyncEngine(self, didStartTask: task)

        do {
            // 检查是否有可恢复的状态
            if config.enablePauseResume,
               let savedState = try stateManager.loadState(for: task.syncPair.id),
               savedState.isResumable {
                logger.info("检测到可恢复的同步状态，从断点继续")
                return try await resumeSync(from: savedState, task: task)
            }

            // 阶段 1: 扫描
            let (sourceSnapshot, destSnapshot) = try await scanPhase(task: task)

            // 检查取消
            try checkCancelled()

            // 阶段 2: 计算校验和
            var sourceWithChecksum = sourceSnapshot
            var destWithChecksum = destSnapshot

            if config.enableChecksum {
                (sourceWithChecksum, destWithChecksum) = try await checksumPhase(
                    source: sourceSnapshot,
                    destination: destSnapshot
                )
            }

            // 检查取消
            try checkCancelled()

            // 阶段 3: 计算差异
            let plan = try await diffPhase(
                task: task,
                source: sourceWithChecksum,
                destination: destWithChecksum
            )

            currentPlan = plan

            // 检查是否有变化
            if plan.summary.isEmpty {
                logger.info("无需同步: \(task.syncPair.id)")
                progress.setPhase(.completed)

                return SyncResult(
                    planId: plan.id,
                    startTime: startTime,
                    endTime: Date(),
                    success: true,
                    succeededActions: 0,
                    failedActions: [],
                    filesTransferred: 0,
                    bytesTransferred: 0,
                    filesVerified: 0,
                    verificationFailures: 0,
                    errorMessage: nil,
                    wasCancelled: false,
                    wasResumed: false
                )
            }

            // 阶段 4: 解决冲突
            var resolvedPlan = plan
            if !plan.conflicts.isEmpty {
                resolvedPlan = try await resolveConflictsPhase(plan: plan)
            }

            // 检查取消
            try checkCancelled()

            // 创建状态（用于暂停/恢复）
            if config.enablePauseResume {
                currentState = stateManager.createState(for: resolvedPlan)
            }

            // 阶段 5: 执行同步
            let copyResult = try await syncPhase(plan: resolvedPlan)

            // 阶段 6: 验证（如果启用）
            var verificationFailures = 0
            if config.verifyAfterCopy {
                verificationFailures = try await verifyPhase(plan: resolvedPlan)
            }

            // 清除状态
            if config.enablePauseResume {
                try? stateManager.clearState(for: task.syncPair.id)
            }

            progress.setPhase(.completed)

            let result = SyncResult(
                planId: plan.id,
                startTime: startTime,
                endTime: Date(),
                success: copyResult.failed.isEmpty,
                succeededActions: copyResult.succeeded,
                failedActions: copyResult.failed.map { FailedAction(
                    action: .skip(path: $0.path, reason: .permissionDenied),
                    error: $0.error.localizedDescription,
                    timestamp: Date()
                )},
                filesTransferred: copyResult.succeeded,
                bytesTransferred: copyResult.totalBytes,
                filesVerified: copyResult.verified,
                verificationFailures: verificationFailures,
                errorMessage: copyResult.failed.first?.error.localizedDescription,
                wasCancelled: false,
                wasResumed: false
            )

            delegate?.nativeSyncEngine(self, didCompleteTask: task, result: result)
            return result

        } catch {
            // 确保释放所有锁
            releaseAllLocks()

            progress.setPhase(isCancelled ? .cancelled : .failed)
            progress.lastError = error.localizedDescription

            let result = SyncResult(
                planId: currentPlan?.id ?? UUID(),
                startTime: startTime,
                endTime: Date(),
                success: false,
                succeededActions: progress.processedFiles,
                failedActions: [],
                filesTransferred: progress.processedFiles,
                bytesTransferred: progress.processedBytes,
                filesVerified: 0,
                verificationFailures: 0,
                errorMessage: error.localizedDescription,
                wasCancelled: isCancelled,
                wasResumed: false
            )

            delegate?.nativeSyncEngine(self, didFailTask: task, error: error)
            throw error
        }
    }

    /// 暂停同步
    func pause() {
        guard isSyncing else { return }
        isPaused = true
        progress.setPhase(.paused)

        Task {
            await copier.pause()
        }

        // 保存状态
        if var state = currentState {
            stateManager.updatePhase(state: &state, phase: .paused)
            try? stateManager.saveState(state)
        }

        logger.info("同步已暂停")
    }

    /// 恢复同步
    func resume() async throws {
        guard isPaused else { return }
        isPaused = false

        await copier.resume()

        logger.info("同步已恢复")
    }

    /// 取消同步
    func cancel() {
        isCancelled = true
        isPaused = false
        progress.setPhase(.cancelled)

        Task {
            await scanner.cancel()
            await hasher.cancel()
            await copier.cancel()
        }

        // 释放所有锁
        releaseAllLocks()

        logger.info("同步已取消")
    }

    /// 预览同步计划（不执行）
    func preview(_ task: SyncTask) async throws -> SyncPlan {
        // 扫描
        let (sourceSnapshot, destSnapshot) = try await scanPhase(task: task)

        // 计算校验和（如果启用）
        var sourceWithChecksum = sourceSnapshot
        var destWithChecksum = destSnapshot

        if config.enableChecksum {
            (sourceWithChecksum, destWithChecksum) = try await checksumPhase(
                source: sourceSnapshot,
                destination: destSnapshot
            )
        }

        // 计算差异并生成计划
        return try await diffPhase(
            task: task,
            source: sourceWithChecksum,
            destination: destWithChecksum
        )
    }

    /// 检查是否有可恢复的同步
    func hasResumableSync(for syncPairId: String) -> Bool {
        return stateManager.hasResumableSync(for: syncPairId)
    }

    /// 获取可恢复同步的摘要
    func getResumeSummary(for syncPairId: String) -> String? {
        guard let state = try? stateManager.loadState(for: syncPairId) else {
            return nil
        }
        return stateManager.getResumeSummary(from: state)
    }

    // MARK: - 私有方法 - 各阶段实现

    /// 扫描阶段
    private func scanPhase(task: SyncTask) async throws -> (DirectorySnapshot, DirectorySnapshot) {
        progress.setPhase(.scanning)
        logger.info("开始扫描: \(task.syncPair.id)")

        let sourceURL = URL(fileURLWithPath: task.syncPair.expandedLocalPath)
        let destURL = URL(fileURLWithPath: task.syncPair.externalFullPath(diskMountPath: task.disk.mountPath))

        // 并行扫描源和目标
        async let sourceTask = scanner.scan(directory: sourceURL) { [weak self] count, file in
            self?.progress.currentFile = file
            self?.throttledProgressCallback(message: "扫描源: \(file)", progress: 0)
        }

        async let destTask = scanner.scan(directory: destURL) { [weak self] count, file in
            self?.progress.currentFile = file
            self?.throttledProgressCallback(message: "扫描目标: \(file)", progress: 0)
        }

        let (sourceSnapshot, destSnapshot) = try await (sourceTask, destTask)

        progress.totalFiles = sourceSnapshot.fileCount

        logger.info("扫描完成: 源 \(sourceSnapshot.fileCount) 文件, 目标 \(destSnapshot.fileCount) 文件")

        return (sourceSnapshot, destSnapshot)
    }

    /// 校验和阶段
    private func checksumPhase(
        source: DirectorySnapshot,
        destination: DirectorySnapshot
    ) async throws -> (DirectorySnapshot, DirectorySnapshot) {
        progress.setPhase(.checksumming)
        logger.info("开始计算校验和")

        var sourceWithChecksum = source
        var destWithChecksum = destination

        let totalFiles = source.files.values.filter { !$0.isDirectory }.count +
                        destination.files.values.filter { !$0.isDirectory }.count
        var processedFiles = 0

        progress.totalFilesToChecksum = totalFiles

        // 计算源目录校验和
        try await sourceWithChecksum.computeChecksums(
            algorithm: config.checksumAlgorithm
        ) { [weak self] completed, total, file in
            processedFiles = completed
            self?.progress.checksummedFiles = processedFiles
            self?.progress.checksumProgress = Double(processedFiles) / Double(totalFiles)
            self?.progress.checksumPhase = "源: \(file)"
            self?.throttledProgressCallback(
                message: "校验源: \(file)",
                progress: self?.progress.checksumProgress ?? 0
            )
        }

        // 计算目标目录校验和
        let sourceCount = source.files.values.filter { !$0.isDirectory }.count
        try await destWithChecksum.computeChecksums(
            algorithm: config.checksumAlgorithm
        ) { [weak self] completed, total, file in
            processedFiles = sourceCount + completed
            self?.progress.checksummedFiles = processedFiles
            self?.progress.checksumProgress = Double(processedFiles) / Double(totalFiles)
            self?.progress.checksumPhase = "目标: \(file)"
            self?.throttledProgressCallback(
                message: "校验目标: \(file)",
                progress: self?.progress.checksumProgress ?? 0
            )
        }

        logger.info("校验和计算完成")

        return (sourceWithChecksum, destWithChecksum)
    }

    /// 差异计算阶段
    private func diffPhase(
        task: SyncTask,
        source: DirectorySnapshot,
        destination: DirectorySnapshot
    ) async throws -> SyncPlan {
        progress.setPhase(.calculating)
        logger.info("开始计算差异")

        let options = DiffEngine.DiffOptions(
            compareChecksums: config.enableChecksum,
            detectMoves: true,
            ignorePermissions: false,
            enableDelete: config.enableDelete,
            maxFileSize: config.maxFileSize
        )

        let diffResult = diffEngine.calculateDiff(
            source: source,
            destination: destination,
            direction: task.direction,
            options: options
        )

        logger.info("差异计算完成: \(diffResult.summary)")

        let plan = diffEngine.createSyncPlan(
            from: diffResult,
            source: source,
            destination: destination,
            syncPairId: task.syncPair.id,
            direction: task.direction
        )

        // 更新进度统计
        progress.totalFiles = plan.totalFiles
        progress.totalBytes = plan.totalBytes

        return plan
    }

    /// 冲突解决阶段
    private func resolveConflictsPhase(plan: SyncPlan) async throws -> SyncPlan {
        progress.setPhase(.resolving)
        logger.info("开始解决 \(plan.conflicts.count) 个冲突")

        let resolvedConflicts = await conflictResolver.resolve(conflicts: plan.conflicts)

        var updatedPlan = plan
        updatedPlan.conflicts = resolvedConflicts
        updatedPlan.applyConflictResolutions()

        logger.info("冲突解决完成")

        return updatedPlan
    }

    /// 同步执行阶段
    private func syncPhase(plan: SyncPlan) async throws -> FileCopier.CopyResult {
        progress.setPhase(.syncing)
        progress.processedFiles = 0
        progress.processedBytes = 0
        logger.info("开始同步: \(plan.totalFiles) 文件, \(ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file))")

        // 创建目录
        for action in plan.actions {
            if case .createDirectory(let path) = action {
                try await copier.createDirectory(at: URL(fileURLWithPath: path))
            }
        }

        // 执行冲突解决
        if !plan.conflicts.isEmpty {
            let conflictResult = try await conflictResolver.executeResolutions(
                plan.conflicts,
                copier: copier
            ) { [weak self] completed, total, file in
                self?.throttledProgressCallback(
                    message: "解决冲突: \(file)",
                    progress: Double(completed) / Double(total)
                )
            }
            logger.info("冲突解决执行完成: \(conflictResult.summary)")
        }

        // 获取需要复制的文件的虚拟路径并加锁
        let filesToLock = plan.actions.compactMap { action -> (virtualPath: String, sourcePath: String, direction: SyncLockDirection)? in
            switch action {
            case .copy(let source, _, _), .update(let source, _, _):
                // 根据同步方向确定虚拟路径和锁方向
                // 假设 plan.direction 表示同步方向
                let virtualPath = extractVirtualPath(from: source)
                let direction: SyncLockDirection = plan.direction == .localToExternal ? .localToExternal : .externalToLocal
                return (virtualPath, source, direction)
            default:
                return nil
            }
        }

        // 批量获取锁
        for file in filesToLock {
            if lockManager.acquireLock(file.virtualPath, direction: file.direction, sourcePath: file.sourcePath) {
                addLockedPath(file.virtualPath)
                logger.debug("获取同步锁: \(file.virtualPath)")
            } else {
                logger.warning("无法获取同步锁，文件可能正在被其他操作使用: \(file.virtualPath)")
            }
        }

        // 复制文件
        let copyOptions = FileCopier.CopyOptions(
            preserveAttributes: true,
            verifyAfterCopy: config.verifyAfterCopy,
            verifyAlgorithm: config.checksumAlgorithm,
            bufferSize: config.bufferSize,
            overwriteExisting: true,
            atomicWrite: true
        )

        let result = try await copier.copyFiles(
            actions: plan.actions,
            options: copyOptions,
            progress: progress
        ) { [weak self] progress in
            self?.throttledProgressCallback(
                message: progress.currentFile,
                progress: progress.overallProgress
            )

            // 更新状态
            if self?.config.enablePauseResume == true,
               var state = self?.currentState {
                self?.stateManager.updateProgress(
                    state: &state,
                    completedIndex: progress.processedFiles - 1,
                    bytes: progress.processedBytes
                )
                self?.currentState = state
            }
        }

        // 释放所有锁
        releaseAllLocks()

        // 执行删除
        if config.enableDelete {
            for action in plan.actions {
                if case .delete(let path, _) = action {
                    try await copier.deleteFile(at: URL(fileURLWithPath: path))
                }
            }
        }

        logger.info("同步执行完成: 成功 \(result.succeeded), 失败 \(result.failed.count)")

        return result
    }

    // MARK: - 锁管理辅助方法

    /// 从文件路径提取虚拟路径
    private func extractVirtualPath(from path: String) -> String {
        // 尝试从 Downloads_Local 路径提取
        let downloadsLocalPath = Constants.Paths.downloadsLocal.path
        if path.hasPrefix(downloadsLocalPath) {
            return String(path.dropFirst(downloadsLocalPath.count + 1))
        }

        // 尝试从 EXTERNAL 路径提取 (去掉 /Volumes/XXX/Downloads/ 前缀)
        if path.hasPrefix("/Volumes/") {
            let components = path.split(separator: "/", maxSplits: 4)
            if components.count >= 4 {
                // /Volumes/DiskName/Downloads/file.txt -> file.txt
                return String(components[3...].joined(separator: "/"))
            }
        }

        // 默认返回原路径
        return path
    }

    /// 添加锁定的路径
    private func addLockedPath(_ path: String) {
        lockedPathsLock.lock()
        defer { lockedPathsLock.unlock() }
        lockedPaths.insert(path)
    }

    /// 释放所有锁
    private func releaseAllLocks() {
        lockedPathsLock.lock()
        let pathsToRelease = lockedPaths
        lockedPaths.removeAll()
        lockedPathsLock.unlock()

        for path in pathsToRelease {
            lockManager.releaseLock(path)
            logger.debug("释放同步锁: \(path)")
        }

        if !pathsToRelease.isEmpty {
            logger.info("已释放 \(pathsToRelease.count) 个同步锁")
        }
    }

    /// 验证阶段
    private func verifyPhase(plan: SyncPlan) async throws -> Int {
        progress.setPhase(.verifying)
        logger.info("开始验证")

        var failures = 0
        let filesToVerify = plan.actions.compactMap { action -> (String, String)? in
            switch action {
            case .copy(let source, let dest, _), .update(let source, let dest, _):
                return (source, dest)
            default:
                return nil
            }
        }

        progress.verifiedFiles = 0

        for (index, (source, dest)) in filesToVerify.enumerated() {
            try checkCancelled()

            let sourceURL = URL(fileURLWithPath: source)
            let destURL = URL(fileURLWithPath: dest)

            let sourceChecksum = try await hasher.hash(file: sourceURL, algorithm: config.checksumAlgorithm)
            let destChecksum = try await hasher.hash(file: destURL, algorithm: config.checksumAlgorithm)

            if sourceChecksum != destChecksum {
                failures += 1
                progress.verificationFailures += 1
                logger.error("验证失败: \(dest)")
            }

            progress.verifiedFiles = index + 1
            progress.verificationProgress = Double(index + 1) / Double(filesToVerify.count)

            throttledProgressCallback(
                message: "验证: \(destURL.lastPathComponent)",
                progress: progress.verificationProgress ?? 0
            )
        }

        logger.info("验证完成: \(filesToVerify.count) 文件, \(failures) 失败")

        return failures
    }

    /// 从保存的状态恢复同步
    private func resumeSync(
        from state: SyncStateManager.SyncState,
        task: SyncTask
    ) async throws -> SyncResult {
        let startTime = Date()

        // 恢复进度
        progress = stateManager.restoreProgress(from: state)
        currentState = state
        currentPlan = state.plan

        logger.info("从断点恢复: 已完成 \(state.completedActionIndices.count)/\(state.plan.actions.count)")

        // 获取剩余动作
        let pendingActions = stateManager.getPendingActions(from: state)

        // 执行剩余同步
        progress.setPhase(.syncing)

        let copyOptions = FileCopier.CopyOptions(
            preserveAttributes: true,
            verifyAfterCopy: config.verifyAfterCopy,
            verifyAlgorithm: config.checksumAlgorithm,
            bufferSize: config.bufferSize,
            overwriteExisting: true,
            atomicWrite: true
        )

        let result = try await copier.copyFiles(
            actions: pendingActions,
            options: copyOptions,
            progress: progress
        ) { [weak self] progress in
            self?.throttledProgressCallback(
                message: progress.currentFile,
                progress: progress.overallProgress
            )
        }

        // 清除状态
        try? stateManager.clearState(for: task.syncPair.id)

        progress.setPhase(.completed)

        return SyncResult(
            planId: state.plan.id,
            startTime: startTime,
            endTime: Date(),
            success: result.failed.isEmpty,
            succeededActions: state.completedActionIndices.count + result.succeeded,
            failedActions: result.failed.map { FailedAction(
                action: .skip(path: $0.path, reason: .permissionDenied),
                error: $0.error.localizedDescription,
                timestamp: Date()
            )},
            filesTransferred: state.processedFiles + result.succeeded,
            bytesTransferred: state.processedBytes + result.totalBytes,
            filesVerified: result.verified,
            verificationFailures: result.verificationFailed.count,
            errorMessage: result.failed.first?.error.localizedDescription,
            wasCancelled: false,
            wasResumed: true
        )
    }

    /// 检查是否已取消
    private func checkCancelled() throws {
        if isCancelled {
            throw NativeSyncError.cancelled
        }
    }

    /// 节流进度回调 - 避免频繁调用导致 UI 卡顿
    private func throttledProgressCallback(message: String, progress: Double) {
        let now = Date()

        // 检查时间间隔和进度变化
        let timeSinceLastCallback = now.timeIntervalSince(lastProgressCallbackTime)
        let progressDelta = abs(progress - lastReportedProgress)

        // 仅在时间间隔足够长或进度变化显著时才回调
        guard timeSinceLastCallback >= progressCallbackInterval || progressDelta >= 0.05 else {
            return
        }

        lastProgressCallbackTime = now
        lastReportedProgress = progress

        delegate?.nativeSyncEngine(self, didUpdateProgress: message, progress: progress)
    }

    /// 重置进度回调节流状态
    private func resetProgressThrottle() {
        lastProgressCallbackTime = .distantPast
        lastReportedProgress = -1
    }
}

// MARK: - 委托协议

protocol NativeSyncEngineDelegate: AnyObject {
    /// 同步任务开始
    func nativeSyncEngine(_ engine: NativeSyncEngine, didStartTask task: SyncTask)

    /// 同步进度更新
    func nativeSyncEngine(_ engine: NativeSyncEngine, didUpdateProgress message: String, progress: Double)

    /// 同步任务完成
    func nativeSyncEngine(_ engine: NativeSyncEngine, didCompleteTask task: SyncTask, result: SyncResult)

    /// 同步任务失败
    func nativeSyncEngine(_ engine: NativeSyncEngine, didFailTask task: SyncTask, error: Error)
}

// MARK: - 错误类型

enum NativeSyncError: Error, LocalizedError {
    case alreadyInProgress
    case cancelled
    case sourceNotFound(String)
    case destinationNotFound(String)
    case permissionDenied(String)
    case insufficientSpace(required: Int64, available: Int64)
    case verificationFailed(path: String)
    case configurationError(String)

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress:
            return "同步任务已在进行中"
        case .cancelled:
            return "同步已取消"
        case .sourceNotFound(let path):
            return "源目录不存在: \(path)"
        case .destinationNotFound(let path):
            return "目标目录不存在: \(path)"
        case .permissionDenied(let path):
            return "权限不足: \(path)"
        case .insufficientSpace(let required, let available):
            let reqStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "磁盘空间不足: 需要 \(reqStr), 可用 \(availStr)"
        case .verificationFailed(let path):
            return "验证失败: \(path)"
        case .configurationError(let message):
            return "配置错误: \(message)"
        }
    }
}
