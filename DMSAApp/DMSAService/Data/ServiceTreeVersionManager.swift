import Foundation

// MARK: - File Tree Version Manager (Service-side)
// Used to detect file tree changes and determine whether index rebuild is needed

/// File tree version info
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

/// Version check result
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

/// Tree data source
enum ServiceTreeSource: Sendable {
    case local
    case external
}

/// Tree version error
enum ServiceTreeVersionError: Error, LocalizedError {
    case scanFailed(String)
    case writeFailed(String)
    case invalidFormat(String)
    case versionMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .scanFailed(let path):
            return "Directory scan failed: \(path)"
        case .writeFailed(let path):
            return "Version file write failed: \(path)"
        case .invalidFormat(let path):
            return "Invalid version file format: \(path)"
        case .versionMismatch(let expected, let actual):
            return "Version mismatch: expected \(expected), actual \(actual)"
        }
    }
}

// MARK: - Service-side Tree Version Manager

actor ServiceTreeVersionManager {

    static let shared = ServiceTreeVersionManager()

    private let logger = Logger.forService("TreeVersion")
    private let fileManager = FileManager.default

    /// Version file path (relative to data source root)
    static let versionFileName = ".FUSE/db.json"

    /// Stored version info [sourceKey: treeVersion]
    private var storedVersions: [String: String] = [:]

    /// Version file path
    private let versionsURL: URL

    private init() {
        let dataDir = URL(fileURLWithPath: "/Library/Application Support/DMSA/ServiceData")
        versionsURL = dataDir.appendingPathComponent("tree_versions.json")

        Task {
            await loadStoredVersions()
        }
    }

    // MARK: - Load/Save Version Records

    private func loadStoredVersions() async {
        do {
            let data = try Data(contentsOf: versionsURL)
            storedVersions = try JSONDecoder().decode([String: String].self, from: data)
            logger.info("Loaded \(storedVersions.count) tree version records")
        } catch {
            logger.debug("No version records file or read failed: \(error.localizedDescription)")
        }
    }

    private func saveStoredVersions() async {
        do {
            let dir = versionsURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(storedVersions)
            try data.write(to: versionsURL, options: .atomic)
        } catch {
            logger.error("Failed to save version records: \(error)")
        }
    }

    // MARK: - Public Interface

    /// Startup version check
    func checkVersionsOnStartup(localDir: String, externalDir: String?, syncPairId: String) async -> ServiceVersionCheckResult {
        var result = ServiceVersionCheckResult()

        // 1. Read LOCAL_DIR version file
        let localVersionPath = (localDir as NSString).appendingPathComponent(Self.versionFileName)
        result.localFileVersion = readVersionFile(at: localVersionPath)

        // 2. Read EXTERNAL_DIR version file (if connected)
        if let extDir = externalDir, fileManager.fileExists(atPath: extDir) {
            result.externalConnected = true
            let externalVersionPath = (extDir as NSString).appendingPathComponent(Self.versionFileName)
            result.externalFileVersion = readVersionFile(at: externalVersionPath)
        }

        // 3. Read stored versions from database
        let localKey = "LOCAL:\(syncPairId)"
        let externalKey = "EXTERNAL:\(syncPairId)"
        result.dbLocalVersion = storedVersions[localKey]
        result.dbExternalVersion = storedVersions[externalKey]

        // 4. Compare versions
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

        logger.info("Version check: LOCAL needsRebuild=\(result.needRebuildLocal), EXTERNAL needsRebuild=\(result.needRebuildExternal)")

        return result
    }

    /// Rebuild file tree
    func rebuildTree(
        rootPath: String,
        syncPairId: String,
        source: ServiceTreeSource
    ) async throws -> (entries: [ServiceFileEntry], version: String) {
        let startTime = Date()
        logger.info("Starting file tree rebuild: \(source) - \(rootPath)")

        let sourceKey = source == .local ? "LOCAL:\(syncPairId)" : "EXTERNAL:\(syncPairId)"

        // 1. Scan directory
        let entries = try await scanDirectory(rootPath, syncPairId: syncPairId, source: source)

        // 2. Calculate statistics
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

        // 3. Generate new version string
        let newVersion = ServiceTreeVersion.generateVersionString()

        // 4. Calculate checksum
        let checksum = calculateChecksum(entries: entryInfos)

        // 5. Create version object
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

        // 6. Write version file
        let versionPath = (rootPath as NSString).appendingPathComponent(Self.versionFileName)
        try writeVersionFile(treeVersion, to: versionPath)

        // 7. Update stored version records
        storedVersions[sourceKey] = newVersion
        await saveStoredVersions()

        let elapsed = Date().timeIntervalSince(startTime)
        logger.info("File tree rebuild complete: \(fileCount) files, \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)), took \(String(format: "%.2f", elapsed))s")

        return (entries, newVersion)
    }

    /// Get current version
    func getCurrentVersion(syncPairId: String, source: ServiceTreeSource) -> String? {
        let key = source == .local ? "LOCAL:\(syncPairId)" : "EXTERNAL:\(syncPairId)"
        return storedVersions[key]
    }

    /// Invalidate version
    func invalidateVersion(syncPairId: String, source: ServiceTreeSource) async {
        let key = source == .local ? "LOCAL:\(syncPairId)" : "EXTERNAL:\(syncPairId)"
        storedVersions.removeValue(forKey: key)
        await saveStoredVersions()
        logger.debug("Version invalidated: \(key)")
    }

    /// Clear all version records
    func clearAllVersions() async {
        storedVersions.removeAll()
        try? fileManager.removeItem(at: versionsURL)
        logger.info("All version records cleared")
    }

    // MARK: - Private Methods

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
                logger.warning("Invalid version file format: \(path)")
                return nil
            }

            return version
        } catch {
            logger.error("Failed to read version file: \(error.localizedDescription)")
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

        logger.debug("Version file written: \(path)")
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
            // Skip version file directory
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

                // Set path and location
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
                logger.warning("Cannot read file attributes: \(url.path)")
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
