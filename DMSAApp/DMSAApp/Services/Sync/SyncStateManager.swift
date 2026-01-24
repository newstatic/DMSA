import Foundation

/// 同步状态管理器 - 支持暂停/恢复同步
class SyncStateManager {

    // MARK: - 状态数据结构

    /// 同步状态快照
    struct SyncState: Codable {
        /// 同步对 ID
        let syncPairId: String

        /// 开始时间
        let startedAt: Date

        /// 最后更新时间
        var lastUpdatedAt: Date

        /// 当前阶段
        var phase: SyncProgress.SyncPhase

        /// 已完成的动作索引
        var completedActionIndices: Set<Int>

        /// 待处理的动作索引
        var pendingActionIndices: Set<Int>

        /// 原始同步计划
        var plan: SyncPlan

        /// 源目录快照
        var sourceSnapshot: DirectorySnapshot?

        /// 目标目录快照
        var destinationSnapshot: DirectorySnapshot?

        /// 已处理字节数
        var processedBytes: Int64

        /// 已处理文件数
        var processedFiles: Int

        /// 失败的动作
        var failedActions: [FailedAction]

        /// 是否可恢复
        var isResumable: Bool {
            !pendingActionIndices.isEmpty && phase != .completed && phase != .cancelled
        }

        /// 恢复进度
        var resumeProgress: Double {
            let total = completedActionIndices.count + pendingActionIndices.count
            return total > 0 ? Double(completedActionIndices.count) / Double(total) : 0
        }
    }

    // MARK: - 属性

    /// 状态文件目录
    private let stateDirectory: URL

    /// 文件管理器
    private let fileManager = FileManager.default

    /// JSON 编码器
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// JSON 解码器
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// 自动保存间隔（文件数）
    var checkpointInterval: Int = 50

    // MARK: - 初始化

    init(stateDirectory: URL? = nil) {
        if let dir = stateDirectory {
            self.stateDirectory = dir
        } else {
            // 默认使用 Application Support 目录
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.stateDirectory = appSupport.appendingPathComponent("DMSA/SyncState")
        }

        // 确保目录存在
        try? fileManager.createDirectory(at: self.stateDirectory, withIntermediateDirectories: true)
    }

    // MARK: - 公共方法

    /// 创建新的同步状态
    func createState(for plan: SyncPlan) -> SyncState {
        let actionIndices = Set(0..<plan.actions.count)

        return SyncState(
            syncPairId: plan.syncPairId,
            startedAt: Date(),
            lastUpdatedAt: Date(),
            phase: .idle,
            completedActionIndices: [],
            pendingActionIndices: actionIndices,
            plan: plan,
            sourceSnapshot: plan.sourceSnapshot,
            destinationSnapshot: plan.destinationSnapshot,
            processedBytes: 0,
            processedFiles: 0,
            failedActions: []
        )
    }

    /// 保存同步状态
    func saveState(_ state: SyncState) throws {
        var mutableState = state
        mutableState.lastUpdatedAt = Date()

        let data = try encoder.encode(mutableState)
        let filePath = stateFilePath(for: state.syncPairId)

        try data.write(to: filePath, options: .atomic)

        Logger.shared.debug("同步状态已保存: \(state.syncPairId)")
    }

    /// 加载同步状态
    func loadState(for syncPairId: String) throws -> SyncState? {
        let filePath = stateFilePath(for: syncPairId)

        guard fileManager.fileExists(atPath: filePath.path) else {
            return nil
        }

        let data = try Data(contentsOf: filePath)
        let state = try decoder.decode(SyncState.self, from: data)

        Logger.shared.debug("同步状态已加载: \(syncPairId)")
        return state
    }

    /// 清除同步状态
    func clearState(for syncPairId: String) throws {
        let filePath = stateFilePath(for: syncPairId)

        if fileManager.fileExists(atPath: filePath.path) {
            try fileManager.removeItem(at: filePath)
            Logger.shared.debug("同步状态已清除: \(syncPairId)")
        }
    }

    /// 获取所有可恢复的状态
    func getResumableStates() throws -> [SyncState] {
        guard fileManager.fileExists(atPath: stateDirectory.path) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(
            at: stateDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var states: [SyncState] = []

        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let state = try decoder.decode(SyncState.self, from: data)
                if state.isResumable {
                    states.append(state)
                }
            } catch {
                Logger.shared.warn("无法加载状态文件: \(file.path), 错误: \(error)")
            }
        }

        return states.sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
    }

    /// 清理过期状态（默认 7 天）
    func cleanupExpiredStates(olderThan days: Int = 7) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        guard fileManager.fileExists(atPath: stateDirectory.path) else {
            return
        }

        let files = try fileManager.contentsOfDirectory(
            at: stateDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )

        for file in files {
            let attrs = try file.resourceValues(forKeys: [.contentModificationDateKey])
            if let modDate = attrs.contentModificationDate, modDate < cutoffDate {
                try fileManager.removeItem(at: file)
                Logger.shared.info("已清理过期状态: \(file.lastPathComponent)")
            }
        }
    }

    /// 更新状态进度
    func updateProgress(
        state: inout SyncState,
        completedIndex: Int,
        bytes: Int64 = 0
    ) {
        state.completedActionIndices.insert(completedIndex)
        state.pendingActionIndices.remove(completedIndex)
        state.processedFiles += 1
        state.processedBytes += bytes
        state.lastUpdatedAt = Date()

        // 检查是否需要自动保存
        if state.processedFiles % checkpointInterval == 0 {
            try? saveState(state)
        }
    }

    /// 标记动作失败
    func markFailed(
        state: inout SyncState,
        index: Int,
        error: Error
    ) {
        state.pendingActionIndices.remove(index)

        let action = state.plan.actions[index]
        state.failedActions.append(FailedAction(
            action: action,
            error: error.localizedDescription,
            timestamp: Date()
        ))

        state.lastUpdatedAt = Date()
    }

    /// 更新阶段
    func updatePhase(state: inout SyncState, phase: SyncProgress.SyncPhase) {
        state.phase = phase
        state.lastUpdatedAt = Date()
        try? saveState(state)
    }

    /// 获取剩余动作
    func getPendingActions(from state: SyncState) -> [SyncAction] {
        return state.pendingActionIndices.sorted().compactMap { index in
            guard index < state.plan.actions.count else { return nil }
            return state.plan.actions[index]
        }
    }

    /// 检查是否有可恢复的同步
    func hasResumableSync(for syncPairId: String) -> Bool {
        guard let state = try? loadState(for: syncPairId) else {
            return false
        }
        return state.isResumable
    }

    // MARK: - 私有方法

    private func stateFilePath(for syncPairId: String) -> URL {
        let safeId = syncPairId.replacingOccurrences(of: "/", with: "_")
        return stateDirectory.appendingPathComponent("\(safeId).json")
    }
}

// MARK: - 状态恢复辅助

extension SyncStateManager {

    /// 从状态恢复同步进度对象
    func restoreProgress(from state: SyncState) -> SyncProgress {
        let progress = SyncProgress()

        progress.phase = state.phase
        progress.processedFiles = state.processedFiles
        progress.totalFiles = state.plan.actions.filter { action in
            switch action {
            case .copy, .update: return true
            default: return false
            }
        }.count
        progress.processedBytes = state.processedBytes
        progress.totalBytes = state.plan.totalBytes
        progress.startTime = state.startedAt

        // 计算总体进度
        let total = state.completedActionIndices.count + state.pendingActionIndices.count
        if total > 0 {
            progress.overallProgress = Double(state.completedActionIndices.count) / Double(total)
        }

        return progress
    }

    /// 生成恢复摘要
    func getResumeSummary(from state: SyncState) -> String {
        let completed = state.completedActionIndices.count
        let pending = state.pendingActionIndices.count
        let total = completed + pending
        let progress = total > 0 ? Int(Double(completed) / Double(total) * 100) : 0

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        let lastUpdate = formatter.string(from: state.lastUpdatedAt)

        return """
        同步对: \(state.syncPairId)
        进度: \(completed)/\(total) (\(progress)%)
        已处理: \(ByteCountFormatter.string(fromByteCount: state.processedBytes, countStyle: .file))
        最后更新: \(lastUpdate)
        阶段: \(state.phase.description)
        """
    }
}
