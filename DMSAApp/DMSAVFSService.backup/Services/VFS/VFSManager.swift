import Foundation

/// VFS 挂载点信息
struct VFSMountPoint {
    let syncPairId: String
    var localDir: String
    var externalDir: String?
    var targetDir: String
    var isExternalOnline: Bool
    var isReadOnly: Bool
    var mountedAt: Date
    var fileSystem: VFSFileSystem?
}

/// 索引统计
struct IndexStats: Codable {
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
actor VFSManager {

    private let logger = Logger.forService("VFS")
    private var mountPoints: [String: VFSMountPoint] = [:]
    private var fileIndex: [String: [String: FileEntry]] = [:]  // [syncPairId: [virtualPath: FileEntry]]

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

        // 创建文件系统实例
        let vfs = VFSFileSystem(
            syncPairId: syncPairId,
            localDir: localDir,
            externalDir: externalDir,
            delegate: self
        )

        // 执行挂载
        try await vfs.mount(at: targetDir)

        // 记录挂载点
        let mountPoint = VFSMountPoint(
            syncPairId: syncPairId,
            localDir: localDir,
            externalDir: externalDir,
            targetDir: targetDir,
            isExternalOnline: externalDir != nil && fm.fileExists(atPath: externalDir!),
            isReadOnly: false,
            mountedAt: Date(),
            fileSystem: vfs
        )

        mountPoints[syncPairId] = mountPoint

        // 构建文件索引
        await buildIndex(for: syncPairId)

        logger.info("VFS 挂载成功: \(targetDir)")
    }

    func unmount(syncPairId: String) async throws {
        guard let mountPoint = mountPoints[syncPairId] else {
            throw VFSError.notMounted(syncPairId)
        }

        // 执行卸载
        if let vfs = mountPoint.fileSystem {
            try await vfs.unmount()
        }

        // 移除记录
        mountPoints.removeValue(forKey: syncPairId)
        fileIndex.removeValue(forKey: syncPairId)

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

    func getAllMounts() -> [MountInfo] {
        return mountPoints.values.map { mp in
            var info = MountInfo(
                syncPairId: mp.syncPairId,
                targetDir: mp.targetDir,
                localDir: mp.localDir
            )
            info.externalDir = mp.externalDir
            info.isMounted = true
            info.isExternalOnline = mp.isExternalOnline
            info.mountedAt = mp.mountedAt

            // 获取统计信息
            if let index = fileIndex[mp.syncPairId] {
                info.fileCount = index.count
                info.totalSize = index.values.reduce(0) { $0 + $1.size }
            }

            return info
        }
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
        await mountPoint.fileSystem?.updateExternalDir(newPath)

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

        await mountPoint.fileSystem?.setExternalOffline(offline)

        logger.info("EXTERNAL 离线状态: \(offline)")
    }

    func setReadOnly(syncPairId: String, readOnly: Bool) async {
        guard var mountPoint = mountPoints[syncPairId] else { return }

        mountPoint.isReadOnly = readOnly
        mountPoints[syncPairId] = mountPoint

        await mountPoint.fileSystem?.setReadOnly(readOnly)
    }

    // MARK: - 文件索引

    func getFileEntry(virtualPath: String, syncPairId: String) async -> FileEntry? {
        return fileIndex[syncPairId]?[virtualPath]
    }

    func getFileLocation(virtualPath: String, syncPairId: String) async -> FileLocation {
        return fileIndex[syncPairId]?[virtualPath]?.location ?? .notExists
    }

    func rebuildIndex(syncPairId: String) async throws {
        guard mountPoints[syncPairId] != nil else {
            throw VFSError.notMounted(syncPairId)
        }

        await buildIndex(for: syncPairId)
    }

    func getIndexStats(syncPairId: String) async -> IndexStats? {
        guard let index = fileIndex[syncPairId] else { return nil }

        var stats = IndexStats(
            totalFiles: 0,
            totalDirectories: 0,
            totalSize: 0,
            localOnlyCount: 0,
            externalOnlyCount: 0,
            bothCount: 0,
            dirtyCount: 0,
            lastUpdated: Date()
        )

        for entry in index.values {
            if entry.isDirectory {
                stats.totalDirectories += 1
            } else {
                stats.totalFiles += 1
                stats.totalSize += entry.size
            }

            switch entry.location {
            case .localOnly: stats.localOnlyCount += 1
            case .externalOnly: stats.externalOnlyCount += 1
            case .both: stats.bothCount += 1
            default: break
            }

            if entry.isDirty {
                stats.dirtyCount += 1
            }
        }

        return stats
    }

    private func buildIndex(for syncPairId: String) async {
        guard let mountPoint = mountPoints[syncPairId] else { return }

        logger.info("构建文件索引: \(syncPairId)")

        var index: [String: FileEntry] = [:]
        let fm = FileManager.default

        // 扫描 LOCAL_DIR
        if let localContents = try? fm.subpathsOfDirectory(atPath: mountPoint.localDir) {
            for relativePath in localContents {
                let fullPath = (mountPoint.localDir as NSString).appendingPathComponent(relativePath)

                // 跳过排除的文件
                if shouldExclude(path: relativePath) { continue }

                var entry = FileEntry(virtualPath: "/" + relativePath, localPath: fullPath)
                entry.syncPairId = syncPairId

                if let attrs = try? fm.attributesOfItem(atPath: fullPath) {
                    entry.size = attrs[.size] as? Int64 ?? 0
                    entry.modifiedAt = attrs[.modificationDate] as? Date ?? Date()
                    entry.createdAt = attrs[.creationDate] as? Date ?? Date()
                    entry.isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
                }

                entry.location = .localOnly
                index[entry.virtualPath] = entry
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

                    if var entry = index[virtualPath] {
                        // 本地也存在，更新为 BOTH
                        entry.externalPath = fullPath
                        entry.location = .both
                        index[virtualPath] = entry
                    } else {
                        // 仅外部存在
                        var entry = FileEntry(virtualPath: virtualPath, externalPath: fullPath)
                        entry.syncPairId = syncPairId

                        if let attrs = try? fm.attributesOfItem(atPath: fullPath) {
                            entry.size = attrs[.size] as? Int64 ?? 0
                            entry.modifiedAt = attrs[.modificationDate] as? Date ?? Date()
                            entry.createdAt = attrs[.creationDate] as? Date ?? Date()
                            entry.isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
                        }

                        entry.location = .externalOnly
                        index[virtualPath] = entry
                    }
                }
            }
        }

        fileIndex[syncPairId] = index
        logger.info("索引构建完成: \(index.count) 个文件/目录")
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

    func onFileWritten(virtualPath: String, syncPairId: String) {
        // 更新索引
        if var entry = fileIndex[syncPairId]?[virtualPath] {
            entry.isDirty = true
            entry.modifiedAt = Date()
            entry.accessedAt = Date()

            if entry.location == .externalOnly {
                entry.location = .both
            }

            fileIndex[syncPairId]?[virtualPath] = entry
        }

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

    func onFileRead(virtualPath: String, syncPairId: String) {
        // 更新访问时间 (LRU)
        if var entry = fileIndex[syncPairId]?[virtualPath] {
            entry.accessedAt = Date()
            fileIndex[syncPairId]?[virtualPath] = entry
        }
    }

    func onFileDeleted(virtualPath: String, syncPairId: String) {
        fileIndex[syncPairId]?.removeValue(forKey: virtualPath)
        logger.debug("文件删除: \(virtualPath)")
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
}
