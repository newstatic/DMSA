import Foundation

// MARK: - 文件树版本管理器 (Service 端)
// 用于检测文件树变更并决定是否需要重建索引

/// 文件树版本信息
struct ServiceTreeVersion: Codable, Sendable {
    let version: Int
    let format: String
    let source: String
    let treeVersion: String
    let lastScanAt: Date
    let fileCount: Int
    let totalSize: Int64
    let checksum: String
    let entries: [String: EntryInfo]

    struct EntryInfo: Codable, Sendable {
        let size: Int64?
        let modifiedAt: Date
        let checksum: String?
        let isDirectory: Bool?
    }

    static let formatIdentifier = "DMSA_TREE_V1"
    static let currentVersion = 1

    static func generateVersionString() -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let random = UUID().uuidString.prefix(8)
        return "\(timestamp)_\(random)"
    }
}

/// 版本检查结果
struct ServiceVersionCheckResult: Sendable {
    var localFileVersion: ServiceTreeVersion?
    var externalFileVersion: ServiceTreeVersion?
    var dbLocalVersion: String?
    var dbExternalVersion: String?
    var externalConnected: Bool = false
    var needRebuildLocal: Bool = false
    var needRebuildExternal: Bool = false

    var needsAnyRebuild: Bool {
        needRebuildLocal || needRebuildExternal
    }
}

/// 树数据源
enum ServiceTreeSource: Sendable {
    case local
    case external
}

/// 树版本错误
enum ServiceTreeVersionError: Error, LocalizedError {
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

// MARK: - Service 端树版本管理器

actor ServiceTreeVersionManager {

    static let shared = ServiceTreeVersionManager()

    private let logger = Logger.forService("TreeVersion")
    private let fileManager = FileManager.default

    /// 版本文件路径 (相对于数据源根目录)
    static let versionFileName = ".FUSE/db.json"

    /// 存储的版本信息 [sourceKey: treeVersion]
    private var storedVersions: [String: String] = [:]

    /// 版本文件路径
    private let versionsURL: URL

    private init() {
        let dataDir = URL(fileURLWithPath: "/Library/Application Support/DMSA/ServiceData")
        versionsURL = dataDir.appendingPathComponent("tree_versions.json")

        Task {
            await loadStoredVersions()
        }
    }

    // MARK: - 加载/保存版本记录

    private func loadStoredVersions() async {
        do {
            let data = try Data(contentsOf: versionsURL)
            storedVersions = try JSONDecoder().decode([String: String].self, from: data)
            logger.info("加载 \(storedVersions.count) 个树版本记录")
        } catch {
            logger.debug("无版本记录文件或读取失败: \(error.localizedDescription)")
        }
    }

    private func saveStoredVersions() async {
        do {
            let dir = versionsURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(storedVersions)
            try data.write(to: versionsURL, options: .atomic)
        } catch {
            logger.error("保存版本记录失败: \(error)")
        }
    }

    // MARK: - 公开接口

    /// 启动时版本检查
    func checkVersionsOnStartup(localDir: String, externalDir: String?, syncPairId: String) async -> ServiceVersionCheckResult {
        var result = ServiceVersionCheckResult()

        // 1. 读取 LOCAL_DIR 版本文件
        let localVersionPath = (localDir as NSString).appendingPathComponent(Self.versionFileName)
        result.localFileVersion = readVersionFile(at: localVersionPath)

        // 2. 读取 EXTERNAL_DIR 版本文件 (如果已连接)
        if let extDir = externalDir, fileManager.fileExists(atPath: extDir) {
            result.externalConnected = true
            let externalVersionPath = (extDir as NSString).appendingPathComponent(Self.versionFileName)
            result.externalFileVersion = readVersionFile(at: externalVersionPath)
        }

        // 3. 读取数据库中存储的版本
        let localKey = "LOCAL:\(syncPairId)"
        let externalKey = "EXTERNAL:\(syncPairId)"
        result.dbLocalVersion = storedVersions[localKey]
        result.dbExternalVersion = storedVersions[externalKey]

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

        logger.info("版本检查: LOCAL 需重建=\(result.needRebuildLocal), EXTERNAL 需重建=\(result.needRebuildExternal)")

        return result
    }

    /// 执行文件树重建
    func rebuildTree(
        rootPath: String,
        syncPairId: String,
        source: ServiceTreeSource
    ) async throws -> (entries: [ServiceFileEntry], version: String) {
        let startTime = Date()
        logger.info("开始重建文件树: \(source) - \(rootPath)")

        let sourceKey = source == .local ? "LOCAL:\(syncPairId)" : "EXTERNAL:\(syncPairId)"

        // 1. 扫描目录
        let entries = try await scanDirectory(rootPath, syncPairId: syncPairId, source: source)

        // 2. 计算统计信息
        var totalSize: Int64 = 0
        var fileCount = 0
        var entryInfos: [String: ServiceTreeVersion.EntryInfo] = [:]

        for entry in entries {
            entryInfos[entry.virtualPath] = ServiceTreeVersion.EntryInfo(
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
        let newVersion = ServiceTreeVersion.generateVersionString()

        // 4. 计算校验和
        let checksum = calculateChecksum(entries: entryInfos)

        // 5. 创建版本对象
        let treeVersion = ServiceTreeVersion(
            version: ServiceTreeVersion.currentVersion,
            format: ServiceTreeVersion.formatIdentifier,
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

        // 7. 更新存储的版本记录
        storedVersions[sourceKey] = newVersion
        await saveStoredVersions()

        let elapsed = Date().timeIntervalSince(startTime)
        logger.info("文件树重建完成: \(fileCount) 文件, \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)), 耗时 \(String(format: "%.2f", elapsed))s")

        return (entries, newVersion)
    }

    /// 获取当前版本
    func getCurrentVersion(syncPairId: String, source: ServiceTreeSource) -> String? {
        let key = source == .local ? "LOCAL:\(syncPairId)" : "EXTERNAL:\(syncPairId)"
        return storedVersions[key]
    }

    /// 使版本失效
    func invalidateVersion(syncPairId: String, source: ServiceTreeSource) async {
        let key = source == .local ? "LOCAL:\(syncPairId)" : "EXTERNAL:\(syncPairId)"
        storedVersions.removeValue(forKey: key)
        await saveStoredVersions()
        logger.debug("版本已失效: \(key)")
    }

    /// 清除所有版本记录
    func clearAllVersions() async {
        storedVersions.removeAll()
        try? fileManager.removeItem(at: versionsURL)
        logger.info("所有版本记录已清除")
    }

    // MARK: - 私有方法

    private func readVersionFile(at path: String) -> ServiceTreeVersion? {
        guard fileManager.fileExists(atPath: path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let version = try decoder.decode(ServiceTreeVersion.self, from: data)

            guard version.format == ServiceTreeVersion.formatIdentifier else {
                logger.warning("版本文件格式无效: \(path)")
                return nil
            }

            return version
        } catch {
            logger.error("读取版本文件失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func writeVersionFile(_ version: ServiceTreeVersion, to path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try fileManager.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(version)
        try data.write(to: URL(fileURLWithPath: path))

        logger.debug("版本文件已写入: \(path)")
    }

    private func shouldRebuild(fileVersion: ServiceTreeVersion?, dbVersion: String?) -> Bool {
        guard let fileVersion = fileVersion else {
            return true
        }
        guard let dbVersion = dbVersion else {
            return true
        }
        return fileVersion.treeVersion != dbVersion
    }

    private func scanDirectory(
        _ rootPath: String,
        syncPairId: String,
        source: ServiceTreeSource
    ) async throws -> [ServiceFileEntry] {
        var entries: [ServiceFileEntry] = []

        let expandedPath = (rootPath as NSString).expandingTildeInPath

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: expandedPath),
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ServiceTreeVersionError.scanFailed(rootPath)
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

                var entry = ServiceFileEntry(virtualPath: relativePath, syncPairId: syncPairId)
                entry.isDirectory = resourceValues.isDirectory ?? false
                entry.size = Int64(resourceValues.fileSize ?? 0)
                entry.modifiedAt = resourceValues.contentModificationDate ?? Date()
                entry.createdAt = resourceValues.creationDate ?? Date()
                entry.accessedAt = Date()

                // 设置路径和位置
                switch source {
                case .local:
                    entry.localPath = url.path
                    entry.location = FileLocation.localOnly.rawValue
                case .external:
                    entry.externalPath = url.path
                    entry.location = FileLocation.externalOnly.rawValue
                }

                entries.append(entry)
            } catch {
                logger.warning("无法读取文件属性: \(url.path)")
            }
        }

        return entries
    }

    private func calculateChecksum(entries: [String: ServiceTreeVersion.EntryInfo]) -> String {
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
