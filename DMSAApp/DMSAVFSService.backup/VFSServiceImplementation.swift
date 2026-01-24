import Foundation

/// VFS Service XPC 协议实现
final class VFSServiceImplementation: NSObject, VFSServiceProtocol {

    private let logger = Logger.forService("VFS")
    private let vfsManager = VFSManager()
    private var config: AppConfig?

    /// 发送分布式通知
    private func postNotification(_ name: String) {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(name),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    override init() {
        super.init()
        loadConfig()
    }

    // MARK: - 配置管理

    private func loadConfig() {
        let configURL = Constants.Paths.config

        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            logger.warn("配置文件不存在或解析失败，使用默认配置")
            self.config = AppConfig()
            return
        }

        self.config = config
        logger.info("配置加载成功: \(config.syncPairs.count) 个同步对")
    }

    /// 自动挂载
    func autoMount() async {
        guard let config = config, config.vfs.autoMount else {
            logger.info("自动挂载已禁用")
            return
        }

        for syncPair in config.syncPairs where syncPair.enabled {
            // 查找对应的磁盘
            guard let disk = config.disks.first(where: { $0.id == syncPair.diskId }) else {
                logger.warn("同步对 \(syncPair.id) 找不到对应磁盘")
                continue
            }

            let externalDir = syncPair.fullExternalDir(diskMountPath: disk.mountPath)
            let isExternalOnline = FileManager.default.fileExists(atPath: externalDir)

            do {
                try await vfsManager.mount(
                    syncPairId: syncPair.id,
                    localDir: syncPair.localDir,
                    externalDir: isExternalOnline ? externalDir : nil,
                    targetDir: syncPair.expandedLocalPath
                )
                logger.info("自动挂载成功: \(syncPair.name)")
            } catch {
                logger.error("自动挂载失败: \(syncPair.name) - \(error)")
            }
        }
    }

    /// 关闭服务
    func shutdown() async {
        logger.info("卸载所有 VFS...")
        await vfsManager.unmountAll()
    }

    /// 重新加载配置
    func reloadConfig() async {
        loadConfig()
        // 可选：重新挂载 VFS
    }

    // MARK: - VFSServiceProtocol 实现

    func mount(syncPairId: String,
               localDir: String,
               externalDir: String,
               targetDir: String,
               withReply reply: @escaping (Bool, String?) -> Void) {

        logger.info("挂载请求: syncPairId=\(syncPairId), target=\(targetDir)")

        Task {
            do {
                try await vfsManager.mount(
                    syncPairId: syncPairId,
                    localDir: localDir,
                    externalDir: externalDir.isEmpty ? nil : externalDir,
                    targetDir: targetDir
                )
                logger.info("挂载成功: \(targetDir)")

                // 更新共享状态
                SharedState.update { state in
                    if !state.vfsMountedPairs.contains(syncPairId) {
                        state.vfsMountedPairs.append(syncPairId)
                    }
                }

                // 发送通知
                self.postNotification(Constants.Notifications.vfsMounted)

                reply(true, nil)
            } catch {
                logger.error("挂载失败: \(error)")
                reply(false, error.localizedDescription)
            }
        }
    }

    func unmount(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void) {

        logger.info("卸载请求: syncPairId=\(syncPairId)")

        Task {
            do {
                try await vfsManager.unmount(syncPairId: syncPairId)
                logger.info("卸载成功: \(syncPairId)")

                // 更新共享状态
                SharedState.update { state in
                    state.vfsMountedPairs.removeAll { $0 == syncPairId }
                }

                // 发送通知
                self.postNotification(Constants.Notifications.vfsUnmounted)

                reply(true, nil)
            } catch {
                logger.error("卸载失败: \(error)")
                reply(false, error.localizedDescription)
            }
        }
    }

    func unmountAll(withReply reply: @escaping (Bool, String?) -> Void) {
        logger.info("卸载所有 VFS")

        Task {
            await vfsManager.unmountAll()

            SharedState.update { state in
                state.vfsMountedPairs.removeAll()
            }

            reply(true, nil)
        }
    }

    func getMountStatus(syncPairId: String,
                        withReply reply: @escaping (Bool, String?) -> Void) {

        Task {
            let isMounted = await vfsManager.isMounted(syncPairId: syncPairId)
            reply(isMounted, nil)
        }
    }

    func getAllMounts(withReply reply: @escaping (Data) -> Void) {
        Task {
            let mounts = await vfsManager.getAllMounts()

            if let data = try? JSONEncoder().encode(mounts) {
                reply(data)
            } else {
                reply(Data())
            }
        }
    }

    func getFileStatus(virtualPath: String,
                       syncPairId: String,
                       withReply reply: @escaping (Data?) -> Void) {

        Task {
            if let entry = await vfsManager.getFileEntry(virtualPath: virtualPath, syncPairId: syncPairId) {
                let dict = entry.toDictionary()
                if let data = try? JSONSerialization.data(withJSONObject: dict) {
                    reply(data)
                    return
                }
            }
            reply(nil)
        }
    }

    func getFileLocation(virtualPath: String,
                         syncPairId: String,
                         withReply reply: @escaping (String) -> Void) {

        Task {
            let location = await vfsManager.getFileLocation(virtualPath: virtualPath, syncPairId: syncPairId)
            reply(location.displayName)
        }
    }

    func updateExternalPath(syncPairId: String,
                            newPath: String,
                            withReply reply: @escaping (Bool, String?) -> Void) {

        logger.info("更新 EXTERNAL 路径: syncPairId=\(syncPairId), path=\(newPath)")

        Task {
            do {
                try await vfsManager.updateExternalPath(syncPairId: syncPairId, newPath: newPath)
                reply(true, nil)
            } catch {
                logger.error("更新 EXTERNAL 路径失败: \(error)")
                reply(false, error.localizedDescription)
            }
        }
    }

    func setExternalOffline(syncPairId: String,
                            offline: Bool,
                            withReply reply: @escaping (Bool, String?) -> Void) {

        logger.info("设置 EXTERNAL 离线状态: syncPairId=\(syncPairId), offline=\(offline)")

        Task {
            await vfsManager.setExternalOffline(syncPairId: syncPairId, offline: offline)
            reply(true, nil)
        }
    }

    func setReadOnly(syncPairId: String,
                     readOnly: Bool,
                     withReply reply: @escaping (Bool, String?) -> Void) {

        logger.info("设置只读模式: syncPairId=\(syncPairId), readOnly=\(readOnly)")

        Task {
            await vfsManager.setReadOnly(syncPairId: syncPairId, readOnly: readOnly)
            reply(true, nil)
        }
    }

    func reloadConfig(withReply reply: @escaping (Bool, String?) -> Void) {
        Task {
            await reloadConfig()
            reply(true, nil)
        }
    }

    func rebuildIndex(syncPairId: String,
                      withReply reply: @escaping (Bool, String?) -> Void) {

        logger.info("重建索引: syncPairId=\(syncPairId)")

        Task {
            do {
                try await vfsManager.rebuildIndex(syncPairId: syncPairId)
                logger.info("索引重建完成")
                reply(true, nil)
            } catch {
                logger.error("索引重建失败: \(error)")
                reply(false, error.localizedDescription)
            }
        }
    }

    func getIndexStats(syncPairId: String,
                       withReply reply: @escaping (Data?) -> Void) {

        Task {
            if let stats = await vfsManager.getIndexStats(syncPairId: syncPairId),
               let data = try? JSONEncoder().encode(stats) {
                reply(data)
            } else {
                reply(nil)
            }
        }
    }

    func prepareForShutdown(withReply reply: @escaping (Bool) -> Void) {
        Task {
            await shutdown()
            reply(true)
        }
    }

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(Constants.version)
    }

    func healthCheck(withReply reply: @escaping (Bool, String?) -> Void) {
        // 检查 VFS 管理器状态
        Task {
            let mountedCount = await vfsManager.mountedCount

            if mountedCount >= 0 {
                reply(true, "VFS Service 运行正常，\(mountedCount) 个挂载点")
            } else {
                reply(false, "VFS Service 状态异常")
            }
        }
    }
}
