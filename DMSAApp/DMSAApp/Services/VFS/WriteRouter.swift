import Foundation

/// 写入路由器
/// 负责处理文件写入请求，实现 Write-Back 策略
/// 写入到 Downloads_Local，异步同步到 EXTERNAL
final class WriteRouter {

    static let shared = WriteRouter()

    private let fileManager = FileManager.default
    private let databaseManager = DatabaseManager.shared
    private let lockManager = LockManager.shared
    private let syncScheduler = SyncScheduler.shared

    /// Downloads_Local 根路径
    var downloadsLocalRoot: URL {
        Constants.Paths.downloadsLocal
    }

    /// 写入防抖时间（秒）
    private let syncDebounceInterval: TimeInterval = 5.0

    /// 待同步的脏文件路径（用于批量同步）
    private var pendingDirtyPaths: Set<String> = []
    private let pendingQueue = DispatchQueue(label: "com.dmsa.writeRouter.pending")

    /// 防抖定时器
    private var debounceTimer: Timer?

    private init() {}

    // MARK: - Public Methods

    /// 处理文件写入
    /// - Parameters:
    ///   - virtualPath: 虚拟路径
    ///   - data: 写入数据
    /// - Returns: 写入结果
    func handleWrite(_ virtualPath: String, data: Data) async -> Result<Void, VFSError> {
        // 1. 获取或创建 FileEntry
        let entry = getOrCreateEntry(virtualPath)

        // 2. 检查同步锁
        if entry.isLocked {
            Logger.shared.debug("文件同步中，等待锁释放: \(virtualPath)")

            // 等待锁释放
            let waitResult = await lockManager.waitForUnlock(virtualPath)
            switch waitResult {
            case .success:
                Logger.shared.debug("锁已释放，继续写入: \(virtualPath)")
            case .timeout:
                Logger.shared.warn("写入等待超时: \(virtualPath)")
                return .failure(.writeTimeout(virtualPath))
            case .cancelled:
                return .failure(.writeFailed("操作已取消"))
            }
        }

        // 3. 写入 Downloads_Local
        let localPath = localPath(for: virtualPath)

        // 确保父目录存在
        let parentDir = (localPath as NSString).deletingLastPathComponent
        do {
            try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        } catch {
            return .failure(.writeFailed("创建目录失败: \(error.localizedDescription)"))
        }

        // 写入文件
        do {
            try data.write(to: URL(fileURLWithPath: localPath))
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }

        // 4. 更新元数据
        entry.localPath = localPath
        entry.size = Int64(data.count)
        entry.modifiedAt = Date()
        entry.isDirty = true

        // 更新位置状态
        if entry.location == .externalOnly || entry.location == .notExists {
            entry.location = .localOnly
        }
        // 如果之前是 .both，现在 LOCAL 有新数据，保持 .both 但标记 dirty

        databaseManager.saveFileEntry(entry)

        Logger.shared.debug("写入完成: \(virtualPath), 大小: \(formatBytes(Int64(data.count)))")

        // 5. 调度同步任务（防抖）
        scheduleDirtySync(virtualPath)

        return .success(())
    }

    /// 处理文件创建
    /// - Parameters:
    ///   - virtualPath: 虚拟路径
    ///   - isDirectory: 是否为目录
    /// - Returns: 创建结果
    func handleCreate(_ virtualPath: String, isDirectory: Bool = false) async -> Result<String, VFSError> {
        // 检查同步锁
        if lockManager.isLocked(virtualPath) {
            let waitResult = await lockManager.waitForUnlock(virtualPath)
            if case .timeout = waitResult {
                return .failure(.writeTimeout(virtualPath))
            }
        }

        let localFilePath = localPath(for: virtualPath)

        do {
            if isDirectory {
                try fileManager.createDirectory(atPath: localFilePath, withIntermediateDirectories: true)
            } else {
                // 确保父目录存在
                let parentDir = (localFilePath as NSString).deletingLastPathComponent
                try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                // 创建空文件
                fileManager.createFile(atPath: localFilePath, contents: nil)
            }

            // 创建 FileEntry
            let entry = FileEntry(virtualPath: virtualPath, localPath: localFilePath)
            entry.location = .localOnly
            entry.isDirty = true
            entry.size = 0
            databaseManager.saveFileEntry(entry)

            Logger.shared.debug("创建\(isDirectory ? "目录" : "文件"): \(virtualPath)")

            // 调度同步
            scheduleDirtySync(virtualPath)

            return .success(localFilePath)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    /// 处理文件删除
    /// - Parameter virtualPath: 虚拟路径
    /// - Returns: 删除结果
    func handleDelete(_ virtualPath: String) async -> Result<Void, VFSError> {
        guard let entry = databaseManager.getFileEntry(virtualPath: virtualPath) else {
            return .failure(.fileNotFound(virtualPath))
        }

        // 检查同步锁
        if entry.isLocked {
            let waitResult = await lockManager.waitForUnlock(virtualPath)
            if case .timeout = waitResult {
                return .failure(.writeTimeout(virtualPath))
            }
        }

        // 删除 LOCAL 文件
        if let localPath = entry.localPath {
            do {
                try fileManager.removeItem(atPath: localPath)
            } catch {
                Logger.shared.warn("删除 LOCAL 文件失败: \(error.localizedDescription)")
            }
        }

        // 更新状态
        if entry.location == .both {
            // 两端都有，只删除 LOCAL
            entry.location = .externalOnly
            entry.localPath = nil
            entry.isDirty = false  // 不需要同步删除到 EXTERNAL（保留 EXTERNAL 数据）
            databaseManager.saveFileEntry(entry)
        } else if entry.location == .localOnly {
            // 仅在 LOCAL，完全删除
            databaseManager.deleteFileEntry(virtualPath: virtualPath)
        }

        Logger.shared.debug("删除文件: \(virtualPath)")
        return .success(())
    }

    /// 处理文件重命名/移动
    /// - Parameters:
    ///   - oldPath: 原路径
    ///   - newPath: 新路径
    /// - Returns: 重命名结果
    func handleRename(_ oldPath: String, to newPath: String) async -> Result<Void, VFSError> {
        guard let entry = databaseManager.getFileEntry(virtualPath: oldPath) else {
            return .failure(.fileNotFound(oldPath))
        }

        // 检查同步锁
        if entry.isLocked {
            let waitResult = await lockManager.waitForUnlock(oldPath)
            if case .timeout = waitResult {
                return .failure(.writeTimeout(oldPath))
            }
        }

        // 重命名 Downloads_Local 文件
        if let oldLocalPath = entry.localPath {
            let newLocalPath = localPath(for: newPath)

            // 确保目标目录存在
            let parentDir = (newLocalPath as NSString).deletingLastPathComponent
            do {
                try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
                try fileManager.moveItem(atPath: oldLocalPath, toPath: newLocalPath)
            } catch {
                return .failure(.writeFailed("重命名失败: \(error.localizedDescription)"))
            }

            entry.localPath = newLocalPath
        }

        // 更新虚拟路径
        entry.virtualPath = newPath
        entry.modifiedAt = Date()
        entry.isDirty = true

        // 删除旧条目，保存新条目
        databaseManager.deleteFileEntry(virtualPath: oldPath)
        databaseManager.saveFileEntry(entry)

        Logger.shared.debug("重命名: \(oldPath) -> \(newPath)")

        // 调度同步
        scheduleDirtySync(newPath)

        return .success(())
    }

    /// 获取所有脏文件路径
    func getDirtyPaths() -> [String] {
        return databaseManager.getDirtyFiles().map { $0.virtualPath }
    }

    /// 标记文件已同步（清除 dirty 状态）
    func markClean(_ virtualPath: String) {
        if let entry = databaseManager.getFileEntry(virtualPath: virtualPath) {
            entry.isDirty = false
            if entry.externalPath != nil {
                entry.location = .both
            }
            databaseManager.saveFileEntry(entry)
        }

        // 从待同步列表中移除
        pendingQueue.sync {
            pendingDirtyPaths.remove(virtualPath)
        }
    }

    /// 批量标记已同步
    func markClean(_ paths: [String]) {
        for path in paths {
            markClean(path)
        }
    }

    // MARK: - Private Methods

    /// 获取 Downloads_Local 路径
    func localPath(for virtualPath: String) -> String {
        return downloadsLocalRoot.appendingPathComponent(virtualPath).path
    }

    /// 获取或创建 FileEntry
    private func getOrCreateEntry(_ virtualPath: String) -> FileEntry {
        if let existing = databaseManager.getFileEntry(virtualPath: virtualPath) {
            return existing
        }

        let entry = FileEntry(virtualPath: virtualPath)
        entry.location = .notExists
        return entry
    }

    /// 调度脏文件同步（带防抖）
    private func scheduleDirtySync(_ virtualPath: String) {
        pendingQueue.async { [weak self] in
            self?.pendingDirtyPaths.insert(virtualPath)
        }

        // 取消之前的定时器
        debounceTimer?.invalidate()

        // 设置新的防抖定时器
        debounceTimer = Timer.scheduledTimer(withTimeInterval: syncDebounceInterval, repeats: false) { [weak self] _ in
            self?.triggerDirtySync()
        }
    }

    /// 触发脏文件同步
    private func triggerDirtySync() {
        let pathsToSync = pendingQueue.sync { () -> [String] in
            let paths = Array(pendingDirtyPaths)
            pendingDirtyPaths.removeAll()
            return paths
        }

        guard !pathsToSync.isEmpty else { return }

        Logger.shared.info("触发脏文件同步: \(pathsToSync.count) 个文件")

        // 通知同步调度器
        Task {
            await syncScheduler.scheduleDirtySync(paths: pathsToSync)
        }
    }
}
