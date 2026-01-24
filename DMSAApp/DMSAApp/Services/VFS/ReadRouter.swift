import Foundation

/// 读取路由器
/// 负责决定从 Downloads_Local 或 EXTERNAL 读取文件
/// 如果文件正在同步，直接从源读取（不阻塞）
final class ReadRouter {

    static let shared = ReadRouter()

    private let fileManager = FileManager.default
    private let databaseManager = DatabaseManager.shared
    private let lockManager = LockManager.shared
    private let diskManager = DiskManager.shared

    /// Downloads_Local 根路径
    var downloadsLocalRoot: URL {
        Constants.Paths.downloadsLocal
    }

    private init() {}

    // MARK: - Public Methods

    /// 解析读取路径
    /// - Parameter virtualPath: 虚拟路径
    /// - Returns: 实际文件路径
    func resolveReadPath(_ virtualPath: String) -> Result<String, VFSError> {
        // 1. 获取文件元数据
        guard let entry = databaseManager.getFileEntry(virtualPath: virtualPath) else {
            return .failure(.fileNotFound(virtualPath))
        }

        // 2. 如果文件正在同步，直接从源读取（不阻塞）
        if entry.isLocked {
            if let sourcePath = entry.syncSourcePath {
                Logger.shared.debug("文件同步中，从源读取: \(virtualPath) -> \(sourcePath)")
                return .success(sourcePath)
            }
            // 如果没有源路径信息，尝试从 LockManager 获取
            if let sourcePath = lockManager.getSourcePath(virtualPath) {
                Logger.shared.debug("文件同步中，从源读取: \(virtualPath) -> \(sourcePath)")
                return .success(sourcePath)
            }
        }

        // 3. 根据位置决定读取来源
        switch entry.location {
        case .localOnly:
            // 仅在 LOCAL，直接读取
            guard let localPath = entry.localPath else {
                return .failure(.fileNotFound(virtualPath))
            }
            updateAccessTime(entry)
            return .success(localPath)

        case .both:
            // 两端都有，优先从 LOCAL 读取
            guard let localPath = entry.localPath else {
                // LOCAL 路径丢失，尝试从 EXTERNAL 读取
                return readFromExternal(entry)
            }
            updateAccessTime(entry)
            return .success(localPath)

        case .externalOnly:
            // 仅在 EXTERNAL，需要拉取到 LOCAL
            return pullToLocalAndRead(entry)

        case .notExists:
            return .failure(.fileNotFound(virtualPath))
        }
    }

    /// 检查文件是否存在
    /// - Parameter virtualPath: 虚拟路径
    /// - Returns: 是否存在
    func fileExists(_ virtualPath: String) -> Bool {
        guard let entry = databaseManager.getFileEntry(virtualPath: virtualPath) else {
            return false
        }
        return entry.location != .notExists
    }

    /// 获取文件属性
    /// - Parameter virtualPath: 虚拟路径
    /// - Returns: 文件属性
    func getFileAttributes(_ virtualPath: String) -> Result<FileAttributes, VFSError> {
        guard let entry = databaseManager.getFileEntry(virtualPath: virtualPath) else {
            return .failure(.fileNotFound(virtualPath))
        }

        // 获取实际文件路径
        let actualPath: String
        switch entry.location {
        case .localOnly, .both:
            actualPath = entry.localPath ?? localPath(for: virtualPath)
        case .externalOnly:
            guard let extPath = entry.externalPath else {
                return .failure(.fileNotFound(virtualPath))
            }
            actualPath = extPath
        case .notExists:
            return .failure(.fileNotFound(virtualPath))
        }

        // 获取文件系统属性
        do {
            let attrs = try fileManager.attributesOfItem(atPath: actualPath)
            return .success(FileAttributes(
                size: entry.size,
                createdAt: entry.createdAt,
                modifiedAt: entry.modifiedAt,
                accessedAt: entry.accessedAt,
                isDirectory: attrs[.type] as? FileAttributeType == .typeDirectory,
                isSymlink: attrs[.type] as? FileAttributeType == .typeSymbolicLink,
                permissions: attrs[.posixPermissions] as? Int ?? 0o644
            ))
        } catch {
            return .failure(.readFailed(error.localizedDescription))
        }
    }

    /// 读取目录内容
    /// - Parameter virtualPath: 虚拟目录路径
    /// - Returns: 目录内容列表
    func readDirectory(_ virtualPath: String) -> Result<[DirectoryEntry], VFSError> {
        // 获取该目录下的所有文件条目
        let allEntries = databaseManager.getAllFileEntries()
        let prefix = virtualPath.isEmpty ? "" : virtualPath + "/"

        var result: [DirectoryEntry] = []
        var seenNames: Set<String> = []

        for entry in allEntries {
            // 检查是否在指定目录下
            guard entry.virtualPath.hasPrefix(prefix) else { continue }

            // 获取相对路径
            let relativePath = String(entry.virtualPath.dropFirst(prefix.count))

            // 获取直接子项名称（第一个路径组件）
            let components = relativePath.split(separator: "/")
            guard let firstComponent = components.first else { continue }
            let name = String(firstComponent)

            // 跳过已处理的名称
            guard !seenNames.contains(name) else { continue }
            seenNames.insert(name)

            // 判断是文件还是目录
            let isDirectory = components.count > 1

            result.append(DirectoryEntry(
                name: name,
                isDirectory: isDirectory,
                size: isDirectory ? 0 : entry.size,
                modifiedAt: entry.modifiedAt
            ))
        }

        return .success(result)
    }

    // MARK: - Private Methods

    /// 从 EXTERNAL 读取（EXTERNAL 离线时返回错误）
    private func readFromExternal(_ entry: FileEntry) -> Result<String, VFSError> {
        guard let externalPath = entry.externalPath else {
            return .failure(.fileNotFound(entry.virtualPath))
        }

        // 检查 EXTERNAL 是否连接
        guard !diskManager.connectedDisks.isEmpty else {
            return .failure(.externalOffline)
        }

        // 检查文件是否存在
        guard fileManager.fileExists(atPath: externalPath) else {
            return .failure(.fileNotFound(entry.virtualPath))
        }

        return .success(externalPath)
    }

    /// 拉取到 Downloads_Local 并返回路径
    private func pullToLocalAndRead(_ entry: FileEntry) -> Result<String, VFSError> {
        guard let externalPath = entry.externalPath else {
            return .failure(.fileNotFound(entry.virtualPath))
        }

        // 检查 EXTERNAL 是否连接
        guard !diskManager.connectedDisks.isEmpty else {
            return .failure(.externalOffline)
        }

        // 检查 EXTERNAL 文件是否存在
        guard fileManager.fileExists(atPath: externalPath) else {
            return .failure(.fileNotFound(entry.virtualPath))
        }

        // 拉取到 Downloads_Local
        do {
            let destPath = localPath(for: entry.virtualPath)

            // 确保父目录存在
            let parentDir = (destPath as NSString).deletingLastPathComponent
            try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

            // 复制文件
            try fileManager.copyItem(atPath: externalPath, toPath: destPath)

            // 更新状态
            entry.localPath = destPath
            entry.location = .both
            entry.accessedAt = Date()
            databaseManager.saveFileEntry(entry)

            Logger.shared.debug("拉取到 Downloads_Local: \(entry.virtualPath)")
            return .success(destPath)
        } catch {
            return .failure(.copyFailed(error.localizedDescription))
        }
    }

    /// 获取 Downloads_Local 路径
    func localPath(for virtualPath: String) -> String {
        return downloadsLocalRoot.appendingPathComponent(virtualPath).path
    }

    /// 更新访问时间
    private func updateAccessTime(_ entry: FileEntry) {
        entry.accessedAt = Date()
        databaseManager.updateAccessTime(entry.virtualPath)
    }
}

// MARK: - Supporting Types

/// 文件属性
struct FileAttributes {
    let size: Int64
    let createdAt: Date
    let modifiedAt: Date
    let accessedAt: Date
    let isDirectory: Bool
    let isSymlink: Bool
    let permissions: Int
}

/// 目录条目
struct DirectoryEntry {
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modifiedAt: Date
}
