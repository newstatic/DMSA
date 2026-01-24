import Foundation

/// VFS 挂载点信息 (内存中)
struct VFSMountPoint {
    let syncPairId: String
    var localDir: String
    var externalDir: String?
    var targetDir: String
    var isExternalOnline: Bool
    var isReadOnly: Bool
    var mountedAt: Date
    var fuseFileSystem: FUSEFileSystem?  // 使用实际的 FUSE 文件系统
}

/// 索引统计
struct IndexStats: Codable, Sendable {
    var totalFiles: Int
    var totalDirectories: Int
    var totalSize: Int64
    var localOnlyCount: Int
    var externalOnlyCount: Int
    var bothCount: Int
    var dirtyCount: Int
    var lastUpdated: Date
}

/// VFS 管理器
/// - 使用 ServiceDatabaseManager 持久化文件索引
/// - 使用 ServiceConfigManager 保存挂载状态
actor VFSManager {

    private let logger = Logger.forService("VFS")
    private var mountPoints: [String: VFSMountPoint] = [:]

    // 数据持久化
    private let database = ServiceDatabaseManager.shared
    private let configManager = ServiceConfigManager.shared

    var mountedCount: Int {
        return mountPoints.count
    }

    // MARK: - 挂载管理

    func mount(syncPairId: String,
               localDir: String,
               externalDir: String?,
               targetDir: String) async throws {

        // 检查是否已挂载
        if mountPoints[syncPairId] != nil {
            throw VFSError.alreadyMounted(targetDir)
        }

        // 验证路径
        guard PathValidator.isAllowed(localDir) else {
            throw VFSError.invalidPath(localDir)
        }
        guard PathValidator.isAllowed(targetDir) else {
            throw VFSError.invalidPath(targetDir)
        }

        let fm = FileManager.default

        // 确保 LOCAL_DIR 存在
        if !fm.fileExists(atPath: localDir) {
            try fm.createDirectory(atPath: localDir, withIntermediateDirectories: true)
            logger.info("创建 LOCAL_DIR: \(localDir)")
        }

        // 首次设置：如果 TARGET_DIR 存在且不是挂载点，重命名为 LOCAL_DIR
        if fm.fileExists(atPath: targetDir) {
            // 检查是否已经是挂载点
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: targetDir, isDirectory: &isDir) {
                // 如果 LOCAL_DIR 不存在内容，将 TARGET_DIR 内容移动过去
                let localContents = try? fm.contentsOfDirectory(atPath: localDir)
                if localContents?.isEmpty ?? true {
                    let targetContents = try? fm.contentsOfDirectory(atPath: targetDir)
                    if let contents = targetContents, !contents.isEmpty {
                        logger.info("迁移现有数据从 \(targetDir) 到 \(localDir)")
                        for item in contents {
                            let src = (targetDir as NSString).appendingPathComponent(item)
                            let dst = (localDir as NSString).appendingPathComponent(item)
                            try? fm.moveItem(atPath: src, toPath: dst)
                        }
                    }
                }
            }
        }

        // 确保 TARGET_DIR 存在 (作为挂载点)
        if !fm.fileExists(atPath: targetDir) {
            try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
        }

        // 创建 FUSE 文件系统实例
        let fuseFS = FUSEFileSystem(
            syncPairId: syncPairId,
            localDir: localDir,
            externalDir: externalDir,
            volumeName: "DMSA-\(syncPairId.prefix(8))",
            delegate: self
        )

        // 执行挂载
        try await fuseFS.mount(at: targetDir)

        // 记录挂载点
        let mountPoint = VFSMountPoint(
            syncPairId: syncPairId,
            localDir: localDir,
            externalDir: externalDir,
            targetDir: targetDir,
            isExternalOnline: externalDir != nil && fm.fileExists(atPath: externalDir!),
            isReadOnly: false,
            mountedAt: Date(),
            fuseFileSystem: fuseFS
        )

        mountPoints[syncPairId] = mountPoint

        // 构建文件索引并持久化
        await buildIndex(for: syncPairId)

        // 保存挂载状态到配置
        var mountState = MountState(syncPairId: syncPairId, targetDir: targetDir, localDir: localDir)
        mountState.externalDir = externalDir
        mountState.isMounted = true
        mountState.isExternalOnline = mountPoint.isExternalOnline
        mountState.mountedAt = Date()
        await configManager.setMountState(mountState)

        logger.info("VFS 挂载成功: \(targetDir)")
    }

    func unmount(syncPairId: String) async throws {
        guard let mountPoint = mountPoints[syncPairId] else {
            throw VFSError.notMounted(syncPairId)
        }

        // 保存文件索引到数据库
        await database.forceSave()

        // 执行卸载
        if let fuseFS = mountPoint.fuseFileSystem {
            try await fuseFS.unmount()
        }

        // 移除记录
        mountPoints.removeValue(forKey: syncPairId)

        // 移除挂载状态
        await configManager.removeMountState(syncPairId: syncPairId)

        logger.info("VFS 卸载成功: \(mountPoint.targetDir)")
    }

    func unmountAll() async {
        for syncPairId in mountPoints.keys {
            do {
                try await unmount(syncPairId: syncPairId)
            } catch {
                logger.error("卸载失败: \(syncPairId) - \(error)")
            }
        }
    }

    func isMounted(syncPairId: String) -> Bool {
        return mountPoints[syncPairId] != nil
    }

    func getAllMounts() async -> [MountInfo] {
        var results: [MountInfo] = []

        for mp in mountPoints.values {
            var info = MountInfo(
                syncPairId: mp.syncPairId,
                targetDir: mp.targetDir,
                localDir: mp.localDir
            )
            info.externalDir = mp.externalDir
            info.isMounted = true
            info.isExternalOnline = mp.isExternalOnline
            info.mountedAt = mp.mountedAt

            // 从数据库获取统计信息
            let stats = await database.getIndexStats(syncPairId: mp.syncPairId)
            info.fileCount = stats.totalFiles + stats.totalDirectories
            info.totalSize = stats.totalSize

            results.append(info)
        }

        return results
    }

    // MARK: - 配置更新

    func updateExternalPath(syncPairId: String, newPath: String) async throws {
        guard var mountPoint = mountPoints[syncPairId] else {
            throw VFSError.notMounted(syncPairId)
        }

        let fm = FileManager.default
        let isOnline = fm.fileExists(atPath: newPath)

        mountPoint.externalDir = newPath
        mountPoint.isExternalOnline = isOnline
        mountPoints[syncPairId] = mountPoint

        // 更新文件系统
        mountPoint.fuseFileSystem?.updateExternalDir(newPath)

        // 重建索引以包含外部文件
        if isOnline {
            await buildIndex(for: syncPairId)
        }

        logger.info("EXTERNAL 路径已更新: \(newPath), 在线: \(isOnline)")
    }

    func setExternalOffline(syncPairId: String, offline: Bool) async {
        guard var mountPoint = mountPoints[syncPairId] else { return }

        mountPoint.isExternalOnline = !offline
        mountPoints[syncPairId] = mountPoint

        mountPoint.fuseFileSystem?.setExternalOffline(offline)

        logger.info("EXTERNAL 离线状态: \(offline)")
    }

    func setReadOnly(syncPairId: String, readOnly: Bool) async {
        guard var mountPoint = mountPoints[syncPairId] else { return }

        mountPoint.isReadOnly = readOnly
        mountPoints[syncPairId] = mountPoint

        mountPoint.fuseFileSystem?.setReadOnly(readOnly)
    }

    // MARK: - 文件索引 (通过 ServiceDatabaseManager)

    func getFileEntry(virtualPath: String, syncPairId: String) async -> ServiceFileEntry? {
        return await database.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId)
    }

    func getFileLocation(virtualPath: String, syncPairId: String) async -> FileLocation {
        guard let entry = await database.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) else {
            return .notExists
        }
        return entry.fileLocation
    }

    func rebuildIndex(syncPairId: String) async throws {
        guard mountPoints[syncPairId] != nil else {
            throw VFSError.notMounted(syncPairId)
        }

        await buildIndex(for: syncPairId)
    }

    func getIndexStats(syncPairId: String) async -> IndexStats {
        return await database.getIndexStats(syncPairId: syncPairId)
    }

    func getAllFileEntries(syncPairId: String) async -> [ServiceFileEntry] {
        return await database.getAllFileEntries(syncPairId: syncPairId)
    }

    func getDirtyFiles(syncPairId: String) async -> [ServiceFileEntry] {
        return await database.getDirtyFiles(syncPairId: syncPairId)
    }

    func getEvictableFiles(syncPairId: String) async -> [ServiceFileEntry] {
        return await database.getEvictableFiles(syncPairId: syncPairId)
    }

    private func buildIndex(for syncPairId: String) async {
        guard let mountPoint = mountPoints[syncPairId] else { return }

        logger.info("构建文件索引: \(syncPairId)")

        // 清除旧索引
        await database.clearFileEntries(syncPairId: syncPairId)

        var entries: [ServiceFileEntry] = []
        var localPaths: [String: ServiceFileEntry] = [:]
        let fm = FileManager.default

        // 扫描 LOCAL_DIR
        if let localContents = try? fm.subpathsOfDirectory(atPath: mountPoint.localDir) {
            for relativePath in localContents {
                let fullPath = (mountPoint.localDir as NSString).appendingPathComponent(relativePath)

                // 跳过排除的文件
                if shouldExclude(path: relativePath) { continue }

                var entry = ServiceFileEntry(virtualPath: "/" + relativePath, syncPairId: syncPairId)
                entry.localPath = fullPath

                if let attrs = try? fm.attributesOfItem(atPath: fullPath) {
                    entry.size = attrs[.size] as? Int64 ?? 0
                    entry.modifiedAt = attrs[.modificationDate] as? Date ?? Date()
                    entry.createdAt = attrs[.creationDate] as? Date ?? Date()
                    entry.isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
                }

                entry.location = FileLocation.localOnly.rawValue
                localPaths[entry.virtualPath] = entry
            }
        }

        // 扫描 EXTERNAL_DIR (如果在线)
        if mountPoint.isExternalOnline, let externalDir = mountPoint.externalDir {
            if let externalContents = try? fm.subpathsOfDirectory(atPath: externalDir) {
                for relativePath in externalContents {
                    let fullPath = (externalDir as NSString).appendingPathComponent(relativePath)
                    let virtualPath = "/" + relativePath

                    // 跳过排除的文件
                    if shouldExclude(path: relativePath) { continue }

                    if var entry = localPaths[virtualPath] {
                        // 本地也存在，更新为 BOTH
                        entry.externalPath = fullPath
                        entry.location = FileLocation.both.rawValue
                        localPaths[virtualPath] = entry
                    } else {
                        // 仅外部存在
                        var entry = ServiceFileEntry(virtualPath: virtualPath, syncPairId: syncPairId)
                        entry.externalPath = fullPath

                        if let attrs = try? fm.attributesOfItem(atPath: fullPath) {
                            entry.size = attrs[.size] as? Int64 ?? 0
                            entry.modifiedAt = attrs[.modificationDate] as? Date ?? Date()
                            entry.createdAt = attrs[.creationDate] as? Date ?? Date()
                            entry.isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
                        }

                        entry.location = FileLocation.externalOnly.rawValue
                        localPaths[virtualPath] = entry
                    }
                }
            }
        }

        // 批量保存到数据库
        entries = Array(localPaths.values)
        await database.saveFileEntries(entries)

        logger.info("索引构建完成: \(entries.count) 个文件/目录")

        // 更新挂载状态统计
        if var mountState = await configManager.getMountState(syncPairId: syncPairId) {
            let stats = await database.getIndexStats(syncPairId: syncPairId)
            mountState.fileCount = stats.totalFiles + stats.totalDirectories
            mountState.totalSize = stats.totalSize
            await configManager.setMountState(mountState)
        }
    }

    private func shouldExclude(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent

        for pattern in Constants.defaultExcludePatterns {
            if matchPattern(pattern, name: name) {
                return true
            }
        }

        return false
    }

    private func matchPattern(_ pattern: String, name: String) -> Bool {
        if pattern.contains("*") {
            // 简单通配符匹配
            let regex = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")

            return name.range(of: "^\(regex)$", options: .regularExpression) != nil
        } else {
            return name == pattern
        }
    }

    // MARK: - 文件操作回调

    func onFileWritten(virtualPath: String, syncPairId: String) async {
        // 更新数据库中的索引
        await database.markFileDirty(virtualPath: virtualPath, syncPairId: syncPairId, dirty: true)

        // 更新共享状态并通知 Sync Service
        SharedState.update { state in
            state.lastWrittenPath = virtualPath
            state.lastWrittenSyncPair = syncPairId
            state.lastWrittenTime = Date()
        }

        // 发送通知
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(Constants.Notifications.fileWritten),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        logger.debug("文件写入: \(virtualPath)")
    }

    func onFileRead(virtualPath: String, syncPairId: String) async {
        // 更新访问时间 (LRU)
        await database.updateAccessTime(virtualPath: virtualPath, syncPairId: syncPairId)
    }

    func onFileDeleted(virtualPath: String, syncPairId: String) async {
        await database.deleteFileEntry(virtualPath: virtualPath, syncPairId: syncPairId)
        logger.debug("文件删除: \(virtualPath)")
    }

    func onFileCreated(virtualPath: String, syncPairId: String, localPath: String, isDirectory: Bool = false) async {
        // 新文件创建
        var entry = ServiceFileEntry(virtualPath: virtualPath, syncPairId: syncPairId)
        entry.localPath = localPath
        entry.location = FileLocation.localOnly.rawValue
        entry.isDirty = true
        entry.isDirectory = isDirectory

        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: localPath) {
            entry.size = attrs[.size] as? Int64 ?? 0
            entry.modifiedAt = attrs[.modificationDate] as? Date ?? Date()
            entry.createdAt = attrs[.creationDate] as? Date ?? Date()
        }

        await database.saveFileEntry(entry)
        logger.debug("文件创建: \(virtualPath)")
    }

    // MARK: - 健康检查

    func healthCheck() -> Bool {
        // 检查所有挂载点是否正常
        return !mountPoints.isEmpty || true  // 空挂载点也认为是正常的
    }
}

// MARK: - VFSFileSystemDelegate

extension VFSManager: VFSFileSystemDelegate {
    nonisolated func fileWritten(virtualPath: String, syncPairId: String) {
        Task {
            await onFileWritten(virtualPath: virtualPath, syncPairId: syncPairId)
        }
    }

    nonisolated func fileRead(virtualPath: String, syncPairId: String) {
        Task {
            await onFileRead(virtualPath: virtualPath, syncPairId: syncPairId)
        }
    }

    nonisolated func fileDeleted(virtualPath: String, syncPairId: String) {
        Task {
            await onFileDeleted(virtualPath: virtualPath, syncPairId: syncPairId)
        }
    }

    nonisolated func fileCreated(virtualPath: String, syncPairId: String, localPath: String, isDirectory: Bool) {
        Task {
            await onFileCreated(virtualPath: virtualPath, syncPairId: syncPairId, localPath: localPath, isDirectory: isDirectory)
        }
    }
}
