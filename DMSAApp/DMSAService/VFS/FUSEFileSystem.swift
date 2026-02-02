import Foundation

/// VFS 文件系统委托协议
protocol VFSFileSystemDelegate: AnyObject, Sendable {
    func fileWritten(virtualPath: String, syncPairId: String)
    func fileRead(virtualPath: String, syncPairId: String)
    func fileDeleted(virtualPath: String, syncPairId: String)
    func fileCreated(virtualPath: String, syncPairId: String, localPath: String, isDirectory: Bool)
    /// FUSE 事件循环意外退出时回调 (非主动 unmount)
    func fuseDidExitUnexpectedly(syncPairId: String, exitCode: Int32)
}

/// FUSE 文件系统实现 - 使用 C libfuse 包装器
///
/// 此类在 DMSAService (root 权限) 中运行，通过 C 包装器直接调用 libfuse。
/// 这种方式避免了 GMUserFileSystem 的 fork() 问题。
///
/// 使用方式:
/// ```swift
/// let fs = FUSEFileSystem(syncPairId: "...", localDir: "...", externalDir: "...", delegate: ...)
/// try await fs.mount(at: "~/Downloads")
/// ```
class FUSEFileSystem {

    // MARK: - 属性

    private let logger = Logger.forService("FUSE")

    /// 同步对 ID
    private let syncPairId: String

    /// 本地目录 (热数据缓存)
    private let localDir: String

    /// 外部目录 (完整数据源)
    private var externalDir: String?

    /// 挂载点路径
    private(set) var mountPath: String?

    /// 是否已挂载
    private(set) var isMounted: Bool = false

    /// 外部存储是否离线
    private var isExternalOffline: Bool = false

    /// 是否只读模式
    private var isReadOnly: Bool = false

    /// 是否正在执行主动卸载 (区分意外退出和主动卸载)
    private var isUnmounting: Bool = false

    /// 卷名
    private let volumeName: String

    /// 委托
    private weak var delegate: VFSFileSystemDelegate?

    /// FUSE 运行线程
    private var fuseThread: Thread?

    // MARK: - 初始化

    init(syncPairId: String,
         localDir: String,
         externalDir: String?,
         volumeName: String = "DMSA",
         delegate: VFSFileSystemDelegate?) {
        self.syncPairId = syncPairId
        self.localDir = localDir
        self.externalDir = externalDir
        self.volumeName = volumeName
        self.delegate = delegate
        self.isExternalOffline = externalDir == nil
    }

    deinit {
        if isMounted {
            unmountSync()
        }
    }

    // MARK: - 挂载/卸载

    /// 挂载文件系统
    func mount(at path: String) async throws {
        guard !isMounted else {
            throw VFSError.alreadyMounted(path)
        }

        logger.info("========== FUSE 挂载开始 (C Wrapper) ==========")
        logger.info("目标路径: \(path)")

        // 检查 macFUSE 可用性
        logger.info("检查 macFUSE...")
        guard FUSEChecker.isAvailable() else {
            logger.error("macFUSE 不可用!")
            throw VFSError.fuseNotAvailable
        }
        logger.info("macFUSE 可用, 版本: \(FUSEChecker.getInstalledVersion() ?? "未知")")

        let expandedPath = (path as NSString).expandingTildeInPath
        mountPath = expandedPath
        logger.info("扩展路径: \(expandedPath)")

        // 确保挂载点存在
        let fm = FileManager.default
        if !fm.fileExists(atPath: expandedPath) {
            try fm.createDirectory(atPath: expandedPath, withIntermediateDirectories: true, attributes: nil)
            logger.info("创建挂载点目录: \(expandedPath)")
        }

        // 设置挂载点所有者
        let pathComponents = expandedPath.components(separatedBy: "/")
        if pathComponents.count >= 3 && pathComponents[1] == "Users" {
            let username = pathComponents[2]
            logger.info("设置挂载点所有者为: \(username)")

            let chownProcess = Process()
            chownProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/chown")
            chownProcess.arguments = ["\(username):staff", expandedPath]

            do {
                try chownProcess.run()
                chownProcess.waitUntilExit()
                if chownProcess.terminationStatus == 0 {
                    logger.info("挂载点所有者已设置为 \(username)")
                }
            } catch {
                logger.warning("执行 chown 失败: \(error)")
            }
        }

        // 设置全局回调上下文
        setupFUSECallbacks()

        // 在后台线程启动 FUSE
        logger.info("在后台线程启动 FUSE...")

        fuseThread = Thread { [weak self] in
            guard let self = self else { return }

            self.logger.info("FUSE 线程开始运行")

            // 调用 C 包装器挂载
            let result = expandedPath.withCString { mountPointCStr in
                self.localDir.withCString { localDirCStr in
                    if let extDir = self.externalDir {
                        return extDir.withCString { extDirCStr in
                            fuse_wrapper_mount(mountPointCStr, localDirCStr, extDirCStr)
                        }
                    } else {
                        return fuse_wrapper_mount(mountPointCStr, localDirCStr, nil)
                    }
                }
            }

            self.logger.info("FUSE 主循环退出，返回值: \(result)")
            self.isMounted = false

            // 如果不是主动卸载，通知委托进行恢复
            if !self.isUnmounting {
                self.logger.warning("FUSE 意外退出! 将通知 VFSManager 尝试恢复")
                self.delegate?.fuseDidExitUnexpectedly(syncPairId: self.syncPairId, exitCode: result)
            }
        }

        fuseThread?.name = "DMSA-FUSE-Thread"
        fuseThread?.qualityOfService = .userInteractive
        fuseThread?.start()

        // 等待挂载完成
        logger.info("等待挂载完成...")
        try await Task.sleep(nanoseconds: 1_500_000_000)  // 等待 1.5 秒

        // 检查挂载状态
        let (success, mountInfo) = checkMountStatusDetailed(path: expandedPath)
        logger.info("挂载检查: success=\(success), info=\(mountInfo)")

        if success {
            isMounted = true
            logger.info("========== FUSE 挂载成功 ==========")
        } else {
            // 再等待一下重试
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let (success2, mountInfo2) = checkMountStatusDetailed(path: expandedPath)
            logger.info("挂载重试检查: success=\(success2), info=\(mountInfo2)")

            if success2 {
                isMounted = true
                logger.info("========== FUSE 挂载成功 (延迟) ==========")
            } else {
                logger.warning("FUSE 可能未完全挂载，继续运行...")
                isMounted = true  // 假设成功，让系统继续
            }
        }

        logger.info("  syncPairId: \(syncPairId)")
        logger.info("  LOCAL_DIR: \(localDir)")
        logger.info("  EXTERNAL_DIR: \(externalDir ?? "离线")")
    }

    /// 设置 FUSE 回调
    private func setupFUSECallbacks() {
        // 保存 self 引用到全局变量，供 C 回调使用
        FUSEFileSystemContext.shared.fileSystem = self

        logger.info("FUSE 回调上下文已设置")
    }

    /// 检查挂载状态 (详细版本)
    private func checkMountStatusDetailed(path: String) -> (success: Bool, info: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: "\n")

                for line in lines {
                    if line.contains(path) {
                        if line.contains("macfuse") || line.contains("osxfuse") || line.contains("fuse") {
                            return (true, "FUSE 挂载: \(line)")
                        } else {
                            return (false, "非 FUSE 挂载: \(line)")
                        }
                    }
                }

                return (false, "未找到 \(path) 的挂载")
            }
        } catch {
            return (false, "执行 mount 命令失败: \(error)")
        }

        return (false, "检查失败")
    }

    /// 卸载文件系统
    func unmount() async throws {
        guard isMounted else {
            throw VFSError.notMounted(syncPairId)
        }

        unmountSync()
    }

    /// 同步卸载
    private func unmountSync() {
        guard isMounted, let path = mountPath else { return }

        logger.info("卸载 FUSE: \(path)")

        // 标记为主动卸载，防止触发恢复逻辑
        isUnmounting = true

        // 调用 C 包装器卸载
        fuse_wrapper_unmount()

        // 等待 FUSE 线程退出
        fuseThread?.cancel()
        fuseThread = nil

        isMounted = false
        mountPath = nil

        // 清理上下文
        FUSEFileSystemContext.shared.fileSystem = nil

        logger.info("FUSE 已卸载: \(path)")
    }

    // MARK: - 配置更新

    /// 更新外部目录路径
    func updateExternalDir(_ path: String?) {
        externalDir = path
        isExternalOffline = path == nil

        // 更新 C 包装器的路径
        if let path = path {
            path.withCString { cstr in
                fuse_wrapper_update_external_dir(cstr)
            }
        } else {
            fuse_wrapper_update_external_dir(nil)
        }

        logger.info("EXTERNAL_DIR 已更新: \(path ?? "离线")")
    }

    /// 设置外部存储离线状态
    func setExternalOffline(_ offline: Bool) {
        isExternalOffline = offline
        fuse_wrapper_set_external_offline(offline)
    }

    /// 设置只读模式
    func setReadOnly(_ readOnly: Bool) {
        isReadOnly = readOnly
        fuse_wrapper_set_readonly(readOnly)
    }

    /// 设置索引就绪状态
    /// 索引未就绪时，所有文件操作返回 EBUSY
    func setIndexReady(_ ready: Bool) {
        fuse_wrapper_set_index_ready(ready)
        logger.info("索引就绪状态设置为: \(ready)")
    }

    /// 获取索引就绪状态
    func isIndexReady() -> Bool {
        return fuse_wrapper_is_index_ready() != 0
    }

    // MARK: - 文件系统操作 (供 C 回调使用)

    /// 获取本地路径
    func localPath(for virtualPath: String) -> String {
        let normalized = virtualPath.hasPrefix("/") ? String(virtualPath.dropFirst()) : virtualPath
        return (localDir as NSString).appendingPathComponent(normalized)
    }

    /// 获取外部路径
    func externalPath(for virtualPath: String) -> String? {
        guard let extDir = externalDir else { return nil }
        let normalized = virtualPath.hasPrefix("/") ? String(virtualPath.dropFirst()) : virtualPath
        return (extDir as NSString).appendingPathComponent(normalized)
    }

    /// 解析实际文件路径 (优先本地，其次外部)
    func resolveActualPath(for virtualPath: String) -> String? {
        let fm = FileManager.default

        // 优先检查本地
        let local = localPath(for: virtualPath)
        if fm.fileExists(atPath: local) {
            return local
        }

        // 其次检查外部 (如果在线)
        if !isExternalOffline, let external = externalPath(for: virtualPath), fm.fileExists(atPath: external) {
            return external
        }

        return nil
    }

    /// 通知文件读取
    func notifyFileRead(virtualPath: String) {
        delegate?.fileRead(virtualPath: virtualPath, syncPairId: syncPairId)
    }

    /// 通知文件写入
    func notifyFileWritten(virtualPath: String) {
        delegate?.fileWritten(virtualPath: virtualPath, syncPairId: syncPairId)
    }

    /// 通知文件创建
    func notifyFileCreated(virtualPath: String, localPath: String, isDirectory: Bool) {
        delegate?.fileCreated(virtualPath: virtualPath, syncPairId: syncPairId, localPath: localPath, isDirectory: isDirectory)
    }

    /// 通知文件删除
    func notifyFileDeleted(virtualPath: String) {
        delegate?.fileDeleted(virtualPath: virtualPath, syncPairId: syncPairId)
    }

    /// 检查是否应该排除的文件
    func shouldExclude(name: String) -> Bool {
        let excludePatterns = [
            ".DS_Store",
            ".Spotlight-V100",
            ".Trashes",
            ".fseventsd",
            ".TemporaryItems",
            "._*",
            ".FUSE"
        ]

        for pattern in excludePatterns {
            if matchPattern(pattern, name: name) {
                return true
            }
        }
        return false
    }

    private func matchPattern(_ pattern: String, name: String) -> Bool {
        if pattern.contains("*") {
            let regex = pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            return name.range(of: "^\(regex)$", options: .regularExpression) != nil
        } else {
            return name == pattern
        }
    }
}

// MARK: - FUSE 上下文 (用于 C 回调)

/// 全局上下文，用于在 C 回调中访问 Swift 对象
class FUSEFileSystemContext {
    static let shared = FUSEFileSystemContext()

    weak var fileSystem: FUSEFileSystem?

    private init() {}
}

// MARK: - FUSE 检查器

struct FUSEChecker {

    private static let macFUSEFrameworkPath = "/Library/Frameworks/macFUSE.framework"
    private static let libfusePath = "/usr/local/lib/libfuse.dylib"
    private static let altLibfusePath = "/Library/Frameworks/macFUSE.framework/Versions/A/usr/local/lib/libfuse.2.dylib"

    /// 检查 macFUSE 是否可用
    static func isAvailable() -> Bool {
        let fm = FileManager.default

        // 检查 Framework 存在
        guard fm.fileExists(atPath: macFUSEFrameworkPath) else {
            return false
        }

        // 检查 libfuse 库存在 (C 包装器需要)
        let libfuseExists = fm.fileExists(atPath: libfusePath) || fm.fileExists(atPath: altLibfusePath)
        guard libfuseExists else {
            return false
        }

        return true
    }

    /// 获取已安装版本
    static func getInstalledVersion() -> String? {
        let infoPlistPath = "\(macFUSEFrameworkPath)/Versions/A/Resources/Info.plist"

        guard let plist = NSDictionary(contentsOfFile: infoPlistPath) else {
            return nil
        }

        return plist["CFBundleShortVersionString"] as? String
            ?? plist["CFBundleVersion"] as? String
    }
}
