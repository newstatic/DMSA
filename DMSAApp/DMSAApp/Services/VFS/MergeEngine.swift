import Foundation

/// 智能合并引擎 - 合并 LOCAL_DIR 和 EXTERNAL_DIR 的文件视图
/// 对应 VFS_DESIGN.md 第 7 章: 智能合并视图
actor MergeEngine {

    // MARK: - 类型定义

    /// 目录项 - 用于 FUSE readdir() 返回
    struct DirectoryEntry: Hashable, Sendable {
        let name: String
        let isDirectory: Bool
        let location: FileLocation
        let size: Int64
        let modifiedAt: Date
        let virtualPath: String

        /// 用于 FUSE 的文件类型
        var fileType: UInt32 {
            isDirectory ? UInt32(DT_DIR) : UInt32(DT_REG)
        }
    }

    /// 目录列表缓存
    struct DirectoryListing: Sendable {
        let entries: [DirectoryEntry]
        let timestamp: Date
        let syncPairId: UUID
    }

    /// 文件属性 - 用于 FUSE getattr() 返回
    struct FileAttributes: Sendable {
        let size: Int64
        let isDirectory: Bool
        let permissions: Int
        let modifiedAt: Date
        let accessedAt: Date
        let createdAt: Date
        let location: FileLocation
        let linkCount: Int

        /// 转换为 stat 结构 (FUSE 使用)
        var mode: mode_t {
            var m: mode_t = mode_t(permissions)
            if isDirectory {
                m |= S_IFDIR
            } else {
                m |= S_IFREG
            }
            return m
        }
    }

    // MARK: - 配置

    private let cacheExpiry: TimeInterval = 5.0  // 5秒缓存
    private let maxCacheEntries: Int = 100       // 最多缓存100个目录

    // MARK: - 缓存

    private var directoryCache: [String: DirectoryListing] = [:]
    private var cacheAccessOrder: [String] = []  // LRU 顺序

    // MARK: - 依赖

    private let databaseManager: DatabaseManager
    private let configManager: ConfigManager
    private let diskManager: DiskManager

    // MARK: - 单例

    static let shared = MergeEngine()

    // MARK: - 初始化

    init(databaseManager: DatabaseManager = .shared,
         configManager: ConfigManager = .shared,
         diskManager: DiskManager = .shared) {
        self.databaseManager = databaseManager
        self.configManager = configManager
        self.diskManager = diskManager
    }

    // MARK: - 公开接口

    /// 获取目录内容 (合并视图) - 对应 FUSE readdir()
    /// - Parameters:
    ///   - virtualPath: 相对于 TARGET_DIR 的虚拟路径 (空字符串表示根目录)
    ///   - syncPairId: 同步对 ID
    /// - Returns: 目录项列表
    func listDirectory(_ virtualPath: String, syncPairId: UUID) async throws -> [DirectoryEntry] {
        let cacheKey = "\(syncPairId.uuidString):\(virtualPath)"

        // 1. 检查缓存
        if let cached = getCachedListing(cacheKey) {
            Logger.shared.debug("MergeEngine: 缓存命中 \(virtualPath)")
            return cached.entries
        }

        // 2. 构建合并目录
        let entries = try await buildMergedDirectory(virtualPath, syncPairId: syncPairId)

        // 3. 更新缓存
        let listing = DirectoryListing(
            entries: entries,
            timestamp: Date(),
            syncPairId: syncPairId
        )
        updateCache(cacheKey, listing: listing)

        Logger.shared.debug("MergeEngine: 列出目录 \(virtualPath), \(entries.count) 项")
        return entries
    }

    /// 获取文件属性 - 对应 FUSE getattr()
    /// - Parameters:
    ///   - virtualPath: 相对于 TARGET_DIR 的虚拟路径
    ///   - syncPairId: 同步对 ID
    /// - Returns: 文件属性
    func getAttributes(_ virtualPath: String, syncPairId: UUID) async throws -> FileAttributes {
        // 根目录特殊处理
        if virtualPath.isEmpty || virtualPath == "/" {
            return FileAttributes(
                size: 0,
                isDirectory: true,
                permissions: 0o755,
                modifiedAt: Date(),
                accessedAt: Date(),
                createdAt: Date(),
                location: .both,
                linkCount: 2
            )
        }

        // 查询数据库
        guard let entry = databaseManager.getFileEntry(virtualPath: virtualPath) else {
            throw VFSError.fileNotFound(virtualPath)
        }

        // 检查是否已删除
        if entry.location == .notExists {
            throw VFSError.fileNotFound(virtualPath)
        }

        // 根据位置状态获取实际属性
        return try await getFileSystemAttributes(for: entry, syncPairId: syncPairId)
    }

    /// 检查文件是否存在 - 对应 FUSE access()
    /// - Parameters:
    ///   - virtualPath: 虚拟路径
    ///   - syncPairId: 同步对 ID
    /// - Returns: 是否存在
    func exists(_ virtualPath: String, syncPairId: UUID) async -> Bool {
        if virtualPath.isEmpty || virtualPath == "/" {
            return true
        }

        guard let entry = databaseManager.getFileEntry(virtualPath: virtualPath) else {
            return false
        }

        return entry.location != .notExists
    }

    /// 使缓存失效 (写入/删除后调用)
    /// - Parameter virtualPath: 指定路径失效，nil 表示清空所有缓存
    func invalidateCache(_ virtualPath: String? = nil) {
        if let path = virtualPath {
            // 使特定路径及其父目录失效
            invalidatePath(path)
        } else {
            // 清空所有缓存
            directoryCache.removeAll()
            cacheAccessOrder.removeAll()
            Logger.shared.debug("MergeEngine: 清空所有缓存")
        }
    }

    /// 预加载目录 (后台优化)
    /// - Parameters:
    ///   - virtualPath: 虚拟路径
    ///   - syncPairId: 同步对 ID
    func preloadDirectory(_ virtualPath: String, syncPairId: UUID) async {
        do {
            _ = try await listDirectory(virtualPath, syncPairId: syncPairId)
        } catch {
            Logger.shared.debug("MergeEngine: 预加载失败 \(virtualPath): \(error.localizedDescription)")
        }
    }

    // MARK: - 私有方法 - 目录合并

    /// 构建合并目录
    private func buildMergedDirectory(_ virtualPath: String, syncPairId: UUID) async throws -> [DirectoryEntry] {
        // 获取该同步对下的所有文件条目
        let allEntries = getAllFileEntries(forSyncPair: syncPairId)

        // 计算目录前缀
        let normalizedPath = virtualPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = normalizedPath.isEmpty ? "" : normalizedPath + "/"

        // 过滤直接子项
        var seenNames: Set<String> = []
        var result: [DirectoryEntry] = []

        for entry in allEntries {
            // 提取相对路径
            let entryPath = entry.virtualPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            // 确定是否在当前目录下
            let relativePath: String
            if prefix.isEmpty {
                // 根目录: 取第一级
                if entryPath.isEmpty {
                    continue
                }
                let components = entryPath.split(separator: "/", maxSplits: 1)
                relativePath = String(components[0])
            } else {
                // 子目录: 检查前缀
                guard entryPath.hasPrefix(prefix) else {
                    continue
                }
                let remaining = String(entryPath.dropFirst(prefix.count))
                if remaining.isEmpty {
                    continue
                }
                let components = remaining.split(separator: "/", maxSplits: 1)
                relativePath = String(components[0])
            }

            // 去重
            guard !seenNames.contains(relativePath) else { continue }
            seenNames.insert(relativePath)

            // 跳过 DELETED 和 NOT_EXISTS 状态
            guard entry.location != .notExists else { continue }

            // 判断是否为目录 (如果有更深的路径则为目录)
            let fullPath = prefix.isEmpty ? relativePath : prefix + relativePath
            let isDir = isDirectory(fullPath, in: allEntries) || entry.isDirectory

            result.append(DirectoryEntry(
                name: relativePath,
                isDirectory: isDir,
                location: entry.location,
                size: entry.size,
                modifiedAt: entry.modifiedAt,
                virtualPath: fullPath
            ))
        }

        // 按名称排序 (Finder 风格)
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 检查路径是否为目录
    private func isDirectory(_ path: String, in entries: [FileEntry]) -> Bool {
        let prefix = path + "/"
        return entries.contains { $0.virtualPath.hasPrefix(prefix) }
    }

    /// 获取同步对的所有文件条目
    private func getAllFileEntries(forSyncPair syncPairId: UUID) -> [FileEntry] {
        // 从数据库获取所有条目，过滤特定同步对
        let allEntries = databaseManager.getAllFileEntries()
        return allEntries.filter { $0.syncPairId == syncPairId.uuidString }
    }

    // MARK: - 私有方法 - 文件属性

    /// 从文件系统获取实际属性
    private func getFileSystemAttributes(for entry: FileEntry, syncPairId: UUID) async throws -> FileAttributes {
        let fm = FileManager.default

        // 确定实际路径
        let actualPath: String
        switch entry.location {
        case .localOnly, .both:
            guard let localPath = entry.localPath else {
                throw VFSError.pathNotFound("LOCAL path missing for: \(entry.virtualPath)")
            }
            actualPath = localPath

        case .externalOnly:
            guard let externalPath = entry.externalPath else {
                throw VFSError.pathNotFound("EXTERNAL path missing for: \(entry.virtualPath)")
            }
            // 检查 EXTERNAL 是否连接
            guard isExternalConnected(syncPairId: syncPairId) else {
                throw VFSError.externalOffline
            }
            actualPath = externalPath

        case .notExists:
            throw VFSError.fileNotFound(entry.virtualPath)
        }

        // 获取文件系统属性
        do {
            let attrs = try fm.attributesOfItem(atPath: actualPath)

            let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
            let size = (attrs[.size] as? Int64) ?? entry.size
            let permissions = (attrs[.posixPermissions] as? Int) ?? (isDir ? 0o755 : 0o644)
            let modifiedAt = (attrs[.modificationDate] as? Date) ?? entry.modifiedAt
            let createdAt = (attrs[.creationDate] as? Date) ?? entry.createdAt

            return FileAttributes(
                size: size,
                isDirectory: isDir,
                permissions: permissions,
                modifiedAt: modifiedAt,
                accessedAt: entry.accessedAt,
                createdAt: createdAt,
                location: entry.location,
                linkCount: isDir ? 2 : 1
            )
        } catch {
            Logger.shared.error("MergeEngine: 获取属性失败 \(actualPath): \(error.localizedDescription)")

            // 回退到数据库中的信息
            return FileAttributes(
                size: entry.size,
                isDirectory: false,
                permissions: 0o644,
                modifiedAt: entry.modifiedAt,
                accessedAt: entry.accessedAt,
                createdAt: entry.createdAt,
                location: entry.location,
                linkCount: 1
            )
        }
    }

    // MARK: - 私有方法 - 缓存管理

    private func getCachedListing(_ key: String) -> DirectoryListing? {
        guard let cached = directoryCache[key] else { return nil }

        // 检查是否过期
        guard Date().timeIntervalSince(cached.timestamp) < cacheExpiry else {
            directoryCache.removeValue(forKey: key)
            cacheAccessOrder.removeAll { $0 == key }
            return nil
        }

        // 更新 LRU 顺序
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)

        return cached
    }

    private func updateCache(_ key: String, listing: DirectoryListing) {
        // 检查缓存容量，淘汰最老的
        while directoryCache.count >= maxCacheEntries, let oldest = cacheAccessOrder.first {
            directoryCache.removeValue(forKey: oldest)
            cacheAccessOrder.removeFirst()
        }

        directoryCache[key] = listing
        cacheAccessOrder.append(key)
    }

    private func invalidatePath(_ path: String) {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // 使该路径及其子路径失效
        let keysToRemove = directoryCache.keys.filter { key in
            key.contains(normalizedPath)
        }
        for key in keysToRemove {
            directoryCache.removeValue(forKey: key)
            cacheAccessOrder.removeAll { $0 == key }
        }

        // 也使父目录失效
        let parent = (normalizedPath as NSString).deletingLastPathComponent
        if !parent.isEmpty && parent != normalizedPath {
            invalidatePath(parent)
        }

        Logger.shared.debug("MergeEngine: 缓存失效 \(path), 清除 \(keysToRemove.count) 项")
    }

    // MARK: - 私有方法 - 辅助

    private func isExternalConnected(syncPairId: UUID) -> Bool {
        guard let syncPair = configManager.getSyncPair(byId: syncPairId.uuidString) else {
            return false
        }

        // 检查外部路径是否可访问
        let fm = FileManager.default
        return fm.fileExists(atPath: syncPair.externalDir)
    }
}

// MARK: - VFSError 扩展

extension VFSError {
    /// 路径未找到
    static func pathNotFound(_ path: String) -> VFSError {
        return .invalidPath(path)
    }

    /// 文件已删除
    static func fileDeleted(_ path: String) -> VFSError {
        return .fileNotFound(path)
    }
}

// MARK: - ConfigManager 扩展

extension ConfigManager {
    /// 通过 ID 获取同步对
    func getSyncPair(byId id: String) -> SyncPairConfig? {
        return config.syncPairs.first { $0.id == id }
    }
}
