import Foundation

/// 文件树版本管理器
/// 根据 VFS_DESIGN.md 第 6 章: 文件树版本控制
actor TreeVersionManager {

    // MARK: - 单例

    static let shared = TreeVersionManager()

    // MARK: - 常量

    /// 版本文件路径 (相对于数据源根目录)
    static let versionFileName = ".FUSE/db.json"

    /// 版本文件格式标识
    static let formatIdentifier = "DMSA_TREE_V1"

    /// 当前版本号
    static let currentVersion = 1

    // MARK: - 类型定义

    /// 文件树版本信息
    struct TreeVersion: Codable {
        let version: Int
        let format: String
        let source: String
        let treeVersion: String
        let lastScanAt: Date
        let fileCount: Int
        let totalSize: Int64
        let checksum: String
        let entries: [String: EntryInfo]

        struct EntryInfo: Codable {
            let size: Int64?
            let modifiedAt: Date
            let checksum: String?
            let isDirectory: Bool?
        }

        /// 生成新的树版本号
        static func generateVersionString() -> String {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let random = UUID().uuidString.prefix(8)
            return "\(timestamp)_\(random)"
        }
    }

    /// 版本检查结果
    struct VersionCheckResult {
        var localFileVersion: TreeVersion?
        var externalFileVersion: TreeVersion?
        var dbLocalVersion: String?
        var dbExternalVersion: String?
        var externalConnected: Bool = false
        var needRebuildLocal: Bool = false
        var needRebuildExternal: Bool = false

        var needsAnyRebuild: Bool {
            return needRebuildLocal || needRebuildExternal
        }
    }

    // MARK: - 依赖

    private let databaseManager: DatabaseManager
    private let configManager: ConfigManager
    private let diskManager: DiskManager

    // MARK: - 状态

    private var storedVersions: [String: String] = [:]  // source -> treeVersion

    // MARK: - 初始化

    private init(databaseManager: DatabaseManager = .shared,
                 configManager: ConfigManager = .shared,
                 diskManager: DiskManager = .shared) {
        self.databaseManager = databaseManager
        self.configManager = configManager
        self.diskManager = diskManager
    }

    // MARK: - 公开接口

    /// 启动时版本检查
    func checkVersionsOnStartup(for syncPair: SyncPairConfig) async -> VersionCheckResult {
        var result = VersionCheckResult()

        // 1. 读取 LOCAL_DIR 版本文件
        let localVersionPath = (syncPair.localDir as NSString)
            .appendingPathComponent(Self.versionFileName)
        result.localFileVersion = readVersionFile(at: localVersionPath)

        // 2. 读取 EXTERNAL_DIR 版本文件 (如果已连接)
        let fm = FileManager.default
        if fm.fileExists(atPath: syncPair.externalDir) {
            result.externalConnected = true
            let externalVersionPath = (syncPair.externalDir as NSString)
                .appendingPathComponent(Self.versionFileName)
            result.externalFileVersion = readVersionFile(at: externalVersionPath)
        }

        // 3. 读取数据库中存储的版本
        result.dbLocalVersion = getStoredVersion(source: localSourceKey(syncPair))
        result.dbExternalVersion = getStoredVersion(source: externalSourceKey(syncPair))

        // 4. 比对版本
        result.needRebuildLocal = shouldRebuild(
            fileVersion: result.localFileVersion,
            dbVersion: result.dbLocalVersion
        )

        if result.externalConnected {
            result.needRebuildExternal = shouldRebuild(
                fileVersion: result.externalFileVersion,
                dbVersion: result.dbExternalVersion
            )
        }

        Logger.shared.info("TreeVersionManager: 版本检查完成 - 需要重建 LOCAL: \(result.needRebuildLocal), EXTERNAL: \(result.needRebuildExternal)")

        return result
    }

    /// 执行文件树重建
    func rebuildTree(for syncPair: SyncPairConfig, source: TreeSource) async throws {
        let startTime = Date()
        Logger.shared.info("TreeVersionManager: 开始重建文件树 - \(source)")

        let rootPath: String
        let sourceKey: String

        switch source {
        case .local:
            rootPath = syncPair.localDir
            sourceKey = localSourceKey(syncPair)
        case .external:
            rootPath = syncPair.externalDir
            sourceKey = externalSourceKey(syncPair)
        }

        // 1. 扫描目录
        let entries = try await scanDirectory(rootPath)

        // 2. 计算统计信息
        var totalSize: Int64 = 0
        var fileCount = 0
        var entryInfos: [String: TreeVersion.EntryInfo] = [:]

        for entry in entries {
            let relativePath = entry.virtualPath
            entryInfos[relativePath] = TreeVersion.EntryInfo(
                size: entry.isDirectory ? nil : entry.size,
                modifiedAt: entry.modifiedAt,
                checksum: entry.checksum,
                isDirectory: entry.isDirectory
            )

            if !entry.isDirectory {
                totalSize += entry.size
                fileCount += 1
            }
        }

        // 3. 生成新版本号
        let newVersion = TreeVersion.generateVersionString()

        // 4. 计算校验和
        let checksum = calculateChecksum(entries: entryInfos)

        // 5. 创建版本对象
        let treeVersion = TreeVersion(
            version: Self.currentVersion,
            format: Self.formatIdentifier,
            source: sourceKey,
            treeVersion: newVersion,
            lastScanAt: Date(),
            fileCount: fileCount,
            totalSize: totalSize,
            checksum: checksum,
            entries: entryInfos
        )

        // 6. 写入版本文件
        let versionPath = (rootPath as NSString).appendingPathComponent(Self.versionFileName)
        try writeVersionFile(treeVersion, to: versionPath)

        // 7. 更新数据库中的版本记录
        updateStoredVersion(source: sourceKey, version: newVersion)

        // 8. 更新 FileEntry 数据库
        try await updateFileEntries(entries, syncPair: syncPair, source: source)

        let elapsed = Date().timeIntervalSince(startTime)
        Logger.shared.info("TreeVersionManager: 文件树重建完成 - \(fileCount) 文件, \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)), 耗时 \(String(format: "%.2f", elapsed))s")
    }

    /// 更新单个文件的版本信息
    func updateFileVersion(_ virtualPath: String, in syncPair: SyncPairConfig) async {
        // 使版本失效，下次启动时重建
        let localKey = localSourceKey(syncPair)
        storedVersions.removeValue(forKey: localKey)
        Logger.shared.debug("TreeVersionManager: 版本失效 - \(virtualPath)")
    }

    /// 获取当前版本
    func getCurrentVersion(for syncPair: SyncPairConfig, source: TreeSource) -> String? {
        let key = source == .local ? localSourceKey(syncPair) : externalSourceKey(syncPair)
        return storedVersions[key]
    }

    // MARK: - 私有方法 - 版本文件操作

    private func readVersionFile(at path: String) -> TreeVersion? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let version = try decoder.decode(TreeVersion.self, from: data)

            // 验证格式
            guard version.format == Self.formatIdentifier else {
                Logger.shared.warning("TreeVersionManager: 版本文件格式无效: \(path)")
                return nil
            }

            return version
        } catch {
            Logger.shared.error("TreeVersionManager: 读取版本文件失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func writeVersionFile(_ version: TreeVersion, to path: String) throws {
        // 确保目录存在
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // 编码并写入
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(version)
        try data.write(to: URL(fileURLWithPath: path))

        Logger.shared.debug("TreeVersionManager: 版本文件已写入: \(path)")
    }

    // MARK: - 私有方法 - 版本比对

    private func shouldRebuild(fileVersion: TreeVersion?, dbVersion: String?) -> Bool {
        // 版本文件不存在 → 需要重建
        guard let fileVersion = fileVersion else {
            return true
        }

        // 数据库版本不存在 → 需要重建
        guard let dbVersion = dbVersion else {
            return true
        }

        // 版本不匹配 → 需要重建
        return fileVersion.treeVersion != dbVersion
    }

    // MARK: - 私有方法 - 目录扫描

    private func scanDirectory(_ rootPath: String) async throws -> [FileEntry] {
        var entries: [FileEntry] = []
        let fm = FileManager.default

        let expandedPath = (rootPath as NSString).expandingTildeInPath

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: expandedPath),
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw TreeVersionError.scanFailed(rootPath)
        }

        while let url = enumerator.nextObject() as? URL {
            // 跳过版本文件目录
            if url.path.contains(".FUSE") {
                continue
            }

            let relativePath = String(url.path.dropFirst(expandedPath.count + 1))

            do {
                let resourceValues = try url.resourceValues(forKeys: [
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey
                ])

                let entry = FileEntry(virtualPath: relativePath)
                entry.isDirectory = resourceValues.isDirectory ?? false
                entry.size = Int64(resourceValues.fileSize ?? 0)
                entry.modifiedAt = resourceValues.contentModificationDate ?? Date()
                entry.createdAt = resourceValues.creationDate ?? Date()
                entry.accessedAt = Date()

                entries.append(entry)
            } catch {
                Logger.shared.warning("TreeVersionManager: 无法读取文件属性: \(url.path)")
            }
        }

        return entries
    }

    // MARK: - 私有方法 - 数据库操作

    private func getStoredVersion(source: String) -> String? {
        return storedVersions[source]
    }

    private func updateStoredVersion(source: String, version: String) {
        storedVersions[source] = version
    }

    private func updateFileEntries(_ entries: [FileEntry], syncPair: SyncPairConfig, source: TreeSource) async throws {
        for entry in entries {
            var mutableEntry = entry
            mutableEntry.syncPairId = syncPair.id

            switch source {
            case .local:
                mutableEntry.localPath = (syncPair.localDir as NSString)
                    .appendingPathComponent(entry.virtualPath)
                if mutableEntry.location == .notExists {
                    mutableEntry.location = .localOnly
                }
            case .external:
                mutableEntry.externalPath = (syncPair.externalDir as NSString)
                    .appendingPathComponent(entry.virtualPath)
                if mutableEntry.location == .notExists {
                    mutableEntry.location = .externalOnly
                } else if mutableEntry.location == .localOnly {
                    mutableEntry.location = .both
                }
            }

            databaseManager.saveFileEntry(mutableEntry)
        }
    }

    // MARK: - 私有方法 - 辅助

    private func localSourceKey(_ syncPair: SyncPairConfig) -> String {
        return "LOCAL:\(syncPair.id)"
    }

    private func externalSourceKey(_ syncPair: SyncPairConfig) -> String {
        return "EXTERNAL:\(syncPair.id)"
    }

    private func calculateChecksum(entries: [String: TreeVersion.EntryInfo]) -> String {
        // 简单实现：基于条目数量和键的哈希
        var hasher = Hasher()
        for key in entries.keys.sorted() {
            hasher.combine(key)
            if let info = entries[key] {
                hasher.combine(info.modifiedAt)
                if let size = info.size {
                    hasher.combine(size)
                }
            }
        }
        let hash = hasher.finalize()
        return "sha256:\(String(format: "%08x", abs(hash)))"
    }
}

// MARK: - 树数据源

enum TreeSource {
    case local
    case external
}

// MARK: - 错误类型

enum TreeVersionError: Error, LocalizedError {
    case scanFailed(String)
    case writeFailed(String)
    case invalidFormat(String)
    case versionMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .scanFailed(let path):
            return "目录扫描失败: \(path)"
        case .writeFailed(let path):
            return "版本文件写入失败: \(path)"
        case .invalidFormat(let path):
            return "版本文件格式无效: \(path)"
        case .versionMismatch(let expected, let actual):
            return "版本不匹配: 期望 \(expected), 实际 \(actual)"
        }
    }
}
