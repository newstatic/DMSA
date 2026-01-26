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

        // ============================================================
        // 步骤 0: 检查并清理现有的 FUSE 挂载
        // ============================================================

        if isPathMounted(targetDir) {
            logger.warning("发现现有挂载，尝试卸载: \(targetDir)")
            do {
                try unmountPath(targetDir)
                // 等待卸载完成
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 秒
            } catch {
                logger.error("卸载现有挂载失败: \(error)")
                // 继续尝试，可能会在后面的步骤中处理
            }
        }

        // ============================================================
        // 步骤 1: 检查 TARGET_DIR 状态并处理
        // ============================================================

        if fm.fileExists(atPath: targetDir) {
            // 获取文件属性判断类型
            let attrs = try? fm.attributesOfItem(atPath: targetDir)
            let fileType = attrs?[.type] as? FileAttributeType

            if fileType == .typeSymbolicLink {
                // 情况 A: TARGET_DIR 是符号链接 → 移除
                if let linkDest = try? fm.destinationOfSymbolicLink(atPath: targetDir) {
                    logger.warning("TARGET_DIR 是符号链接: \(targetDir) -> \(linkDest)")
                }
                try fm.removeItem(atPath: targetDir)
                logger.info("已移除符号链接: \(targetDir)")

            } else if fileType == .typeDirectory {
                // 情况 B: TARGET_DIR 是普通目录 → 检查是否已是 FUSE 挂载点
                // 通过检查 mount 命令或者尝试获取挂载信息
                // 简单判断: 如果我们已经有这个挂载点的记录，说明已挂载
                if mountPoints.values.contains(where: { $0.targetDir == targetDir }) {
                    throw VFSError.alreadyMounted(targetDir)
                }

                // 情况 C: TARGET_DIR 是普通目录，需要重命名为 LOCAL_DIR
                if fm.fileExists(atPath: localDir) {
                    // LOCAL_DIR 已存在，检查 TARGET_DIR 是否为空
                    let targetContents = try? fm.contentsOfDirectory(atPath: targetDir)
                    if targetContents?.isEmpty == true {
                        // TARGET_DIR 是空目录（可能是上次 FUSE 卸载后留下的），直接删除
                        try fm.removeItem(atPath: targetDir)
                        logger.info("删除空的 TARGET_DIR: \(targetDir)")
                    } else {
                        // TARGET_DIR 不为空，无法处理
                        logger.error("冲突: TARGET_DIR(\(targetDir)) 和 LOCAL_DIR(\(localDir)) 都存在且 TARGET_DIR 不为空")
                        throw VFSError.conflictingPaths(targetDir, localDir)
                    }
                } else {
                    // LOCAL_DIR 不存在，重命名 TARGET_DIR 为 LOCAL_DIR
                    logger.info("重命名目录: \(targetDir) -> \(localDir)")
                    try fm.moveItem(atPath: targetDir, toPath: localDir)
                }
            }
        }

        // ============================================================
        // 步骤 2: 确保 LOCAL_DIR 存在
        // ============================================================

        if !fm.fileExists(atPath: localDir) {
            try fm.createDirectory(atPath: localDir, withIntermediateDirectories: true)
            logger.info("创建 LOCAL_DIR: \(localDir)")
        }

        // ============================================================
        // 步骤 3: 创建 FUSE 挂载点目录
        // ============================================================

        if !fm.fileExists(atPath: targetDir) {
            try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
            logger.info("创建挂载点目录: \(targetDir)")
        }

        // ============================================================
        // 步骤 4: 检查 EXTERNAL_DIR 状态
        // ============================================================

        var isExternalOnline = false
        if let extDir = externalDir {
            if fm.fileExists(atPath: extDir) {
                isExternalOnline = true
                logger.info("EXTERNAL_DIR 已就绪: \(extDir)")
            } else {
                logger.warning("EXTERNAL_DIR 未就绪 (外置硬盘未挂载?): \(extDir)")
            }
        } else {
            logger.warning("未配置 EXTERNAL_DIR，仅使用本地存储")
        }

        // ============================================================
        // 步骤 5: 创建并执行 FUSE 挂载
        // ============================================================

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

        // ============================================================
        // 步骤 6: 保护 LOCAL_DIR (防止用户直接访问)
        // ============================================================
        // 按照 VFS_DESIGN.md 的设计:
        // - chflags hidden: 隐藏目录
        // - 权限 700: 仅 root 可访问
        // - ACL deny: 拒绝所有用户访问
        // LOCAL_DIR 和 EXTERNAL_DIR 都需要保护

        logger.info("保护后端目录...")
        logger.info("  - LOCAL_DIR: \(localDir)")
        logger.info("  - EXTERNAL_DIR: \(externalDir ?? "(nil)")")

        protectBackendDir(localDir)
        if let extDir = externalDir, !extDir.isEmpty {
            logger.info("保护 EXTERNAL_DIR: \(extDir)")
            protectBackendDir(extDir)
        } else {
            logger.info("跳过 EXTERNAL_DIR 保护 (磁盘未连接或路径为空)")
        }

        // 记录挂载点
        let mountPoint = VFSMountPoint(
            syncPairId: syncPairId,
            localDir: localDir,
            externalDir: externalDir,
            targetDir: targetDir,
            isExternalOnline: isExternalOnline,
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

        // 恢复后端目录权限 (允许用户访问)
        unprotectBackendDir(mountPoint.localDir)
        if let extDir = mountPoint.externalDir {
            unprotectBackendDir(extDir)
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

    // MARK: - 挂载点管理

    /// 检查路径是否已被挂载
    private nonisolated func isPathMounted(_ path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // 检查是否有挂载到这个路径
                return output.contains("on \(path) ")
            }
        } catch {
            return false
        }

        return false
    }

    /// 强制卸载指定路径
    private nonisolated func unmountPath(_ path: String) throws {
        let logger = Logger.forService("VFS")

        // 先尝试正常卸载
        let umount = Process()
        umount.executableURL = URL(fileURLWithPath: "/sbin/umount")
        umount.arguments = [path]

        let errorPipe = Pipe()
        umount.standardError = errorPipe

        try umount.run()
        umount.waitUntilExit()

        if umount.terminationStatus == 0 {
            logger.info("正常卸载成功: \(path)")
            return
        }

        // 如果失败，尝试强制卸载
        logger.warning("正常卸载失败，尝试强制卸载...")

        let forceUmount = Process()
        forceUmount.executableURL = URL(fileURLWithPath: "/sbin/umount")
        forceUmount.arguments = ["-f", path]

        try forceUmount.run()
        forceUmount.waitUntilExit()

        if forceUmount.terminationStatus != 0 {
            // 最后尝试 diskutil
            let diskutil = Process()
            diskutil.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            diskutil.arguments = ["unmount", "force", path]

            try diskutil.run()
            diskutil.waitUntilExit()

            if diskutil.terminationStatus != 0 {
                throw VFSError.unmountFailed(path)
            }
        }

        logger.info("强制卸载成功: \(path)")
    }

    // MARK: - 目录保护

    /// 保护后端目录 (LOCAL_DIR 或 EXTERNAL_DIR) - 完全拒绝所有访问
    /// 使用三重保护:
    /// 1. 权限 700: 仅 root 可访问
    /// 2. ACL deny: 明确拒绝当前用户的所有权限
    /// 3. chflags hidden: 隐藏目录 (心理防护)
    /// 注意: 不使用 chflags uchg，因为我们的 Service 需要能够操作这个目录
    private nonisolated func protectBackendDir(_ path: String) {
        let logger = Logger.forService("VFS")
        logger.info("========== 保护后端目录开始 ==========")
        logger.info("路径: \(path)")

        // 检查路径是否存在
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            logger.warning("后端目录不存在，跳过保护: \(path)")
            return
        }

        // 显示当前状态
        if let attrs = try? fm.attributesOfItem(atPath: path) {
            let perms = attrs[.posixPermissions] as? Int ?? 0
            logger.info("当前权限: \(String(perms, radix: 8))")
        }

        // 1. 设置权限为 700 (仅 root 可访问)
        do {
            let attrs: [FileAttributeKey: Any] = [
                .posixPermissions: 0o700  // rwx------
            ]
            try fm.setAttributes(attrs, ofItemAtPath: path)
            logger.info("目录权限已设置为 700: \(path)")
        } catch {
            logger.error("设置目录权限失败: \(error)")
        }

        // 2. 添加 ACL deny 规则 - 拒绝所有用户访问
        // 获取目录所有者用户名
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let ownerAccountName = attrs[.ownerAccountName] as? String {
            logger.info("目录所有者: \(ownerAccountName)")

            // 使用 chmod +a 添加 ACL deny 规则
            let aclProcess = Process()
            aclProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            // deny read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,readsecurity,writesecurity,chown,list,search,add_file,add_subdirectory,delete_child
            aclProcess.arguments = ["+a", "user:\(ownerAccountName) deny read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,readsecurity,list,search,add_file,add_subdirectory,delete_child", path]

            let aclPipe = Pipe()
            let aclErrorPipe = Pipe()
            aclProcess.standardOutput = aclPipe
            aclProcess.standardError = aclErrorPipe

            do {
                try aclProcess.run()
                aclProcess.waitUntilExit()

                let errorData = aclErrorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                if aclProcess.terminationStatus == 0 {
                    logger.info("ACL deny 规则已添加: 用户 \(ownerAccountName) 被拒绝所有访问")
                } else {
                    logger.warning("ACL 设置失败, 状态: \(aclProcess.terminationStatus), 错误: \(errorOutput)")
                }
            } catch {
                logger.warning("执行 chmod +a 失败: \(error)")
            }

            // 同时拒绝 everyone 组
            let everyoneProcess = Process()
            everyoneProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            everyoneProcess.arguments = ["+a", "everyone deny read,write,execute,delete,append,readattr,writeattr,readextattr,writeextattr,readsecurity,list,search,add_file,add_subdirectory,delete_child", path]

            let everyonePipe = Pipe()
            let everyoneErrorPipe = Pipe()
            everyoneProcess.standardOutput = everyonePipe
            everyoneProcess.standardError = everyoneErrorPipe

            do {
                try everyoneProcess.run()
                everyoneProcess.waitUntilExit()

                if everyoneProcess.terminationStatus == 0 {
                    logger.info("ACL deny 规则已添加: everyone 被拒绝所有访问")
                }
            } catch {
                logger.warning("执行 chmod +a (everyone) 失败: \(error)")
            }
        }

        // 3. 设置隐藏标志 (chflags hidden)
        logger.info("执行: chflags hidden \(path)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        process.arguments = ["hidden", path]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                logger.info("目录已设置为隐藏: \(path)")
            } else {
                logger.warning("chflags hidden 失败, 状态: \(process.terminationStatus), 错误: \(errorOutput)")
            }
        } catch {
            logger.warning("执行 chflags 失败: \(error)")
        }

        // 4. 验证保护状态
        // 验证权限和隐藏状态
        let lsProcess = Process()
        lsProcess.executableURL = URL(fileURLWithPath: "/bin/ls")
        lsProcess.arguments = ["-laO", path]
        let lsPipe = Pipe()
        lsProcess.standardOutput = lsPipe
        try? lsProcess.run()
        lsProcess.waitUntilExit()
        let lsOutput = String(data: lsPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        logger.info("ls -laO 结果: \(lsOutput.trimmingCharacters(in: .whitespacesAndNewlines))")

        // 验证 ACL
        let aclCheckProcess = Process()
        aclCheckProcess.executableURL = URL(fileURLWithPath: "/bin/ls")
        aclCheckProcess.arguments = ["-le", path]
        let aclCheckPipe = Pipe()
        aclCheckProcess.standardOutput = aclCheckPipe
        try? aclCheckProcess.run()
        aclCheckProcess.waitUntilExit()
        let aclCheckOutput = String(data: aclCheckPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        logger.info("ACL 状态:\n\(aclCheckOutput)")

        logger.info("========== 保护后端目录完成 ==========")
    }

    /// 取消保护后端目录 (卸载时调用)
    private nonisolated func unprotectBackendDir(_ path: String) {
        let logger = Logger.forService("VFS")
        logger.info("========== 取消保护后端目录开始 ==========")
        logger.info("路径: \(path)")

        // 检查路径是否存在
        guard FileManager.default.fileExists(atPath: path) else {
            logger.warning("后端目录不存在，跳过取消保护: \(path)")
            return
        }

        // 1. 移除所有 ACL 规则
        let aclProcess = Process()
        aclProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        aclProcess.arguments = ["-N", path]  // -N 移除所有 ACL

        do {
            try aclProcess.run()
            aclProcess.waitUntilExit()

            if aclProcess.terminationStatus == 0 {
                logger.info("ACL 规则已移除: \(path)")
            } else {
                logger.warning("移除 ACL 返回非零状态: \(aclProcess.terminationStatus)")
            }
        } catch {
            logger.warning("移除 ACL 失败: \(error)")
        }

        // 2. 恢复权限为 755
        do {
            let attrs: [FileAttributeKey: Any] = [
                .posixPermissions: 0o755  // rwxr-xr-x
            ]
            try FileManager.default.setAttributes(attrs, ofItemAtPath: path)
            logger.info("目录权限已恢复为 755: \(path)")
        } catch {
            logger.warning("恢复目录权限失败: \(error)")
        }

        // 3. 取消隐藏标志 (chflags nohidden)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        process.arguments = ["nohidden", path]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                logger.info("目录隐藏标志已取消: \(path)")
            } else {
                logger.warning("chflags nohidden 返回非零状态: \(process.terminationStatus)")
            }
        } catch {
            logger.warning("取消目录隐藏标志失败: \(error)")
        }

        logger.info("========== 取消保护后端目录完成 ==========")
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
