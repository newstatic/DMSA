import Foundation

/// 淘汰统计
struct EvictionStats: Codable, Sendable {
    var evictedCount: Int
    var evictedSize: Int64
    var lastEvictionTime: Date?
    var skippedDirty: Int
    var skippedLocked: Int
    var failedSync: Int
}

/// 淘汰结果
struct EvictionResult: Sendable {
    let evictedFiles: [String]
    let freedSpace: Int64
    let errors: [String]
}

/// LRU 淘汰管理器
/// 负责在本地空间不足时清理已同步的文件
actor EvictionManager {

    private let logger = Logger.forService("Eviction")

    /// 淘汰配置
    struct Config {
        /// 触发淘汰的阈值 (可用空间低于此值)
        var triggerThreshold: Int64 = 5 * 1024 * 1024 * 1024  // 5GB
        /// 目标可用空间 (淘汰到此值)
        var targetFreeSpace: Int64 = 10 * 1024 * 1024 * 1024  // 10GB
        /// 单次淘汰最大文件数
        var maxFilesPerRun: Int = 100
        /// 最小文件年龄 (秒) - 防止淘汰刚创建的文件
        var minFileAge: TimeInterval = 3600  // 1小时
        /// 是否启用自动淘汰
        var autoEvictionEnabled: Bool = true
        /// 自动检查间隔 (秒)
        var checkInterval: TimeInterval = 300  // 5分钟
    }

    private var config = Config()
    private var stats = EvictionStats(
        evictedCount: 0,
        evictedSize: 0,
        lastEvictionTime: nil,
        skippedDirty: 0,
        skippedLocked: 0,
        failedSync: 0
    )

    private weak var vfsManager: VFSManager?
    private weak var syncManager: SyncManager?

    private var checkTimer: DispatchSourceTimer?
    private var isRunning = false

    // MARK: - 初始化

    func setManagers(vfs: VFSManager, sync: SyncManager) {
        self.vfsManager = vfs
        self.syncManager = sync
    }

    func updateConfig(_ newConfig: Config) {
        self.config = newConfig
    }

    func getConfig() -> Config {
        return config
    }

    func getStats() -> EvictionStats {
        return stats
    }

    // MARK: - 自动淘汰

    func startAutoEviction() {
        guard config.autoEvictionEnabled else {
            logger.info("自动淘汰已禁用")
            return
        }

        stopAutoEviction()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + config.checkInterval, repeating: config.checkInterval)
        timer.setEventHandler { [weak self] in
            Task {
                await self?.checkAndEvictIfNeeded()
            }
        }
        timer.resume()
        checkTimer = timer

        logger.info("自动淘汰已启动，检查间隔: \(Int(config.checkInterval))秒")
    }

    func stopAutoEviction() {
        checkTimer?.cancel()
        checkTimer = nil
        logger.info("自动淘汰已停止")
    }

    // MARK: - 淘汰逻辑

    /// 检查并执行淘汰 (如果需要)
    func checkAndEvictIfNeeded() async {
        guard !isRunning else {
            logger.debug("淘汰正在进行中，跳过")
            return
        }

        guard let vfsManager = vfsManager else {
            logger.warning("VFSManager 未设置")
            return
        }

        // 获取所有挂载点
        let mounts = await vfsManager.getAllMounts()

        for mount in mounts {
            let freeSpace = getAvailableSpace(at: mount.localDir)

            if freeSpace < config.triggerThreshold {
                logger.info("触发淘汰: \(mount.syncPairId), 可用空间: \(formatBytes(freeSpace))")

                let result = await evict(
                    syncPairId: mount.syncPairId,
                    targetFreeSpace: config.targetFreeSpace
                )

                logger.info("淘汰完成: 释放 \(formatBytes(result.freedSpace)), 淘汰 \(result.evictedFiles.count) 个文件")
            }
        }
    }

    /// 执行淘汰
    /// - Parameters:
    ///   - syncPairId: 同步对 ID
    ///   - targetFreeSpace: 目标可用空间 (可选，默认使用配置)
    /// - Returns: 淘汰结果
    func evict(syncPairId: String, targetFreeSpace: Int64? = nil) async -> EvictionResult {
        isRunning = true
        defer { isRunning = false }

        let target = targetFreeSpace ?? config.targetFreeSpace
        var evictedFiles: [String] = []
        var freedSpace: Int64 = 0
        var errors: [String] = []

        guard let vfsManager = vfsManager else {
            errors.append("VFSManager 未设置")
            return EvictionResult(evictedFiles: [], freedSpace: 0, errors: errors)
        }

        // 获取挂载点信息
        let mounts = await vfsManager.getAllMounts()
        guard let mount = mounts.first(where: { $0.syncPairId == syncPairId }) else {
            errors.append("同步对未挂载: \(syncPairId)")
            return EvictionResult(evictedFiles: [], freedSpace: 0, errors: errors)
        }

        let localDir = mount.localDir
        var currentFreeSpace = getAvailableSpace(at: localDir)

        logger.info("开始淘汰: 当前可用 \(formatBytes(currentFreeSpace)), 目标 \(formatBytes(target))")

        // 获取可淘汰的文件列表 (按 LRU 排序)
        let candidates = await getEvictionCandidates(syncPairId: syncPairId)

        logger.info("找到 \(candidates.count) 个候选文件")

        let fm = FileManager.default
        var processedCount = 0

        for entry in candidates {
            // 检查是否已达到目标
            if currentFreeSpace >= target {
                logger.info("已达到目标空间")
                break
            }

            // 检查单次限制
            if processedCount >= config.maxFilesPerRun {
                logger.info("已达到单次最大文件数限制")
                break
            }

            // 跳过目录
            if entry.isDirectory { continue }

            // 跳过脏文件 (需要先同步)
            if entry.isDirty {
                stats.skippedDirty += 1
                continue
            }

            // 跳过被锁定的文件
            if entry.isLocked {
                stats.skippedLocked += 1
                continue
            }

            // 跳过太新的文件
            let fileAge = Date().timeIntervalSince(entry.accessedAt)
            if fileAge < config.minFileAge {
                continue
            }

            // 确保文件在 EXTERNAL 存在
            guard let externalPath = entry.externalPath,
                  fm.fileExists(atPath: externalPath) else {
                // 需要先同步到 EXTERNAL
                if let syncManager = syncManager, let syncPairId = entry.syncPairId {
                    do {
                        try await syncManager.syncFile(virtualPath: entry.virtualPath, syncPairId: syncPairId)
                        // 同步成功后跳过淘汰，等下次检查时再处理
                        continue
                    } catch {
                        stats.failedSync += 1
                        errors.append("同步失败: \(entry.virtualPath) - \(error.localizedDescription)")
                        continue
                    }
                } else {
                    errors.append("SyncManager 未设置或缺少 syncPairId: \(entry.virtualPath)")
                    continue
                }
            }

            // 执行淘汰 (删除本地副本)
            guard let localPath = entry.localPath else { continue }

            do {
                let fileSize = entry.size
                try fm.removeItem(atPath: localPath)

                evictedFiles.append(entry.virtualPath)
                freedSpace += fileSize
                currentFreeSpace += fileSize
                processedCount += 1

                // 更新索引 (位置变为 externalOnly)
                await updateEntryLocation(entry: entry, vfsManager: vfsManager)

                logger.debug("淘汰: \(entry.virtualPath) (\(formatBytes(fileSize)))")

            } catch {
                errors.append("删除失败: \(entry.virtualPath) - \(error.localizedDescription)")
            }
        }

        // 更新统计
        stats.evictedCount += evictedFiles.count
        stats.evictedSize += freedSpace
        stats.lastEvictionTime = Date()

        return EvictionResult(evictedFiles: evictedFiles, freedSpace: freedSpace, errors: errors)
    }

    /// 获取淘汰候选文件 (按 LRU 排序)
    private func getEvictionCandidates(syncPairId: String) async -> [FileEntry] {
        guard let vfsManager = vfsManager else { return [] }

        // 获取所有索引条目
        let allStats = await vfsManager.getIndexStats(syncPairId: syncPairId)
        guard allStats != nil else { return [] }

        // 获取状态为 BOTH 的文件 (两端都有的可以安全淘汰)
        var candidates: [FileEntry] = []

        let mounts = await vfsManager.getAllMounts()
        guard let mount = mounts.first(where: { $0.syncPairId == syncPairId }) else {
            return []
        }

        // 扫描本地目录获取文件
        let fm = FileManager.default
        guard let contents = try? fm.subpathsOfDirectory(atPath: mount.localDir) else {
            return []
        }

        for relativePath in contents {
            let localPath = (mount.localDir as NSString).appendingPathComponent(relativePath)
            let virtualPath = "/" + relativePath

            // 获取文件属性
            guard let attrs = try? fm.attributesOfItem(atPath: localPath) else { continue }

            // 跳过目录
            if (attrs[.type] as? FileAttributeType) == .typeDirectory { continue }

            // 检查 EXTERNAL 是否存在
            var externalPath: String? = nil
            if let externalDir = mount.externalDir {
                let extPath = (externalDir as NSString).appendingPathComponent(relativePath)
                if fm.fileExists(atPath: extPath) {
                    externalPath = extPath
                }
            }

            // 只有当 EXTERNAL 存在时才是候选
            guard externalPath != nil else { continue }

            let entry = FileEntry(virtualPath: virtualPath, localPath: localPath, externalPath: externalPath)
            entry.syncPairId = syncPairId
            entry.size = attrs[.size] as? Int64 ?? 0
            entry.modifiedAt = attrs[.modificationDate] as? Date ?? Date()
            entry.accessedAt = attrs[.creationDate] as? Date ?? Date()  // 使用创建时间作为近似访问时间
            entry.location = .both

            candidates.append(entry)
        }

        // 按访问时间排序 (最旧的在前)
        candidates.sort { $0.accessedAt < $1.accessedAt }

        return candidates
    }

    /// 更新文件条目位置
    private func updateEntryLocation(entry: FileEntry, vfsManager: VFSManager) async {
        // 通知 VFSManager 文件已从本地删除
        if let syncPairId = entry.syncPairId {
            await vfsManager.onFileDeleted(virtualPath: entry.virtualPath, syncPairId: syncPairId)
        }
    }

    // MARK: - 手动淘汰

    /// 淘汰指定文件
    func evictFile(virtualPath: String, syncPairId: String) async throws {
        guard let vfsManager = vfsManager else {
            throw EvictionError.managerNotSet
        }

        guard let entry = await vfsManager.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) else {
            throw EvictionError.fileNotFound(virtualPath)
        }

        // 检查文件是否可淘汰
        if entry.isDirty {
            throw EvictionError.fileIsDirty(virtualPath)
        }

        if entry.isLocked {
            throw EvictionError.fileIsLocked(virtualPath)
        }

        guard entry.location == .both else {
            throw EvictionError.notSynced(virtualPath)
        }

        guard let localPath = entry.localPath else {
            throw EvictionError.noLocalPath(virtualPath)
        }

        // 删除本地副本
        try FileManager.default.removeItem(atPath: localPath)

        // 更新索引
        await updateEntryLocation(entry: entry, vfsManager: vfsManager)

        stats.evictedCount += 1
        stats.evictedSize += entry.size

        logger.info("手动淘汰: \(virtualPath)")
    }

    /// 预取文件 (从 EXTERNAL 复制到 LOCAL)
    func prefetchFile(virtualPath: String, syncPairId: String) async throws {
        guard let vfsManager = vfsManager else {
            throw EvictionError.managerNotSet
        }

        guard let entry = await vfsManager.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) else {
            throw EvictionError.fileNotFound(virtualPath)
        }

        guard entry.location == .externalOnly else {
            logger.debug("文件已在本地: \(virtualPath)")
            return
        }

        guard let externalPath = entry.externalPath else {
            throw EvictionError.noExternalPath(virtualPath)
        }

        // 获取挂载点信息
        let mounts = await vfsManager.getAllMounts()
        guard let mount = mounts.first(where: { $0.syncPairId == syncPairId }) else {
            throw EvictionError.notMounted(syncPairId)
        }

        // 计算本地路径
        let relativePath = String(virtualPath.dropFirst())  // 去掉开头的 /
        let localPath = (mount.localDir as NSString).appendingPathComponent(relativePath)

        // 确保父目录存在
        let parentDir = (localPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // 复制文件
        try FileManager.default.copyItem(atPath: externalPath, toPath: localPath)

        logger.info("预取完成: \(virtualPath)")
    }

    // MARK: - 工具方法

    private func getAvailableSpace(at path: String) -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            return attrs[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - 错误类型

enum EvictionError: Error, LocalizedError {
    case managerNotSet
    case fileNotFound(String)
    case fileIsDirty(String)
    case fileIsLocked(String)
    case notSynced(String)
    case noLocalPath(String)
    case noExternalPath(String)
    case notMounted(String)

    var errorDescription: String? {
        switch self {
        case .managerNotSet:
            return "管理器未设置"
        case .fileNotFound(let path):
            return "文件未找到: \(path)"
        case .fileIsDirty(let path):
            return "文件有未同步更改: \(path)"
        case .fileIsLocked(let path):
            return "文件被锁定: \(path)"
        case .notSynced(let path):
            return "文件未同步到外部: \(path)"
        case .noLocalPath(let path):
            return "无本地路径: \(path)"
        case .noExternalPath(let path):
            return "无外部路径: \(path)"
        case .notMounted(let id):
            return "同步对未挂载: \(id)"
        }
    }
}
