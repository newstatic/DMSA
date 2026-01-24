import Foundation

/// 冲突解决器 - 处理同步冲突
class ConflictResolver {

    // MARK: - 属性

    /// 默认策略
    var defaultStrategy: ConflictStrategy = .localWinsWithBackup

    /// 备份文件后缀
    var backupSuffix: String = "_backup"

    /// 是否自动解决冲突
    var autoResolve: Bool = true

    /// 用户解决冲突的回调
    var userResolutionHandler: (([ConflictInfo]) async -> [ConflictInfo])?

    /// 文件管理器
    private let fileManager = FileManager.default

    /// Logger
    private let logger = Logger.forService("ConflictResolver")

    // MARK: - 初始化

    init(
        defaultStrategy: ConflictStrategy = .localWinsWithBackup,
        backupSuffix: String = "_backup",
        autoResolve: Bool = true
    ) {
        self.defaultStrategy = defaultStrategy
        self.backupSuffix = backupSuffix
        self.autoResolve = autoResolve
    }

    // MARK: - 公共方法

    /// 解决冲突列表
    func resolve(conflicts: [ConflictInfo]) async -> [ConflictInfo] {
        if autoResolve {
            return autoResolveConflicts(conflicts)
        } else if let handler = userResolutionHandler {
            return await handler(conflicts)
        } else {
            return autoResolveConflicts(conflicts)
        }
    }

    /// 自动解决冲突
    func autoResolveConflicts(_ conflicts: [ConflictInfo]) -> [ConflictInfo] {
        return conflicts.map { conflict in
            var resolved = conflict
            if resolved.resolution == nil {
                resolved.resolve(with: resolveWithStrategy(conflict, strategy: defaultStrategy))
            }
            return resolved
        }
    }

    /// 使用指定策略解决单个冲突
    func resolveWithStrategy(_ conflict: ConflictInfo, strategy: ConflictStrategy) -> ConflictResolution {
        switch strategy {
        case .newerWins:
            return resolveNewerWins(conflict)

        case .largerWins:
            return resolveLargerWins(conflict)

        case .localWins:
            return .keepLocal

        case .externalWins:
            return .keepExternal

        case .localWinsWithBackup:
            return .localWinsWithBackup

        case .externalWinsWithBackup:
            return .externalWinsWithBackup

        case .askUser:
            // 如果策略是询问用户但没有处理程序，使用推荐方案
            return conflict.recommendedResolution()

        case .keepBoth:
            return .keepBoth
        }
    }

    /// 执行冲突解决方案
    func executeResolution(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        guard let resolution = conflict.resolution else {
            throw ConflictError.unresolved(conflict.relativePath)
        }

        switch resolution {
        case .keepLocal:
            // 用本地版本覆盖外置版本
            try await copyLocalToExternal(conflict, copier: copier)

        case .keepExternal:
            // 用外置版本覆盖本地版本
            try await copyExternalToLocal(conflict, copier: copier)

        case .localWinsWithBackup:
            // 备份外置文件，然后用本地覆盖
            try await backupAndCopyLocalToExternal(conflict, copier: copier)

        case .externalWinsWithBackup:
            // 备份本地文件，然后用外置覆盖
            try await backupAndCopyExternalToLocal(conflict, copier: copier)

        case .keepBoth:
            // 两个版本都保留，重命名
            try await keepBothVersions(conflict, copier: copier)

        case .skip:
            // 不做任何操作
            logger.info("跳过冲突: \(conflict.relativePath)")
        }
    }

    /// 批量执行冲突解决
    func executeResolutions(
        _ conflicts: [ConflictInfo],
        copier: FileCopier,
        progressHandler: ((Int, Int, String) -> Void)? = nil
    ) async throws -> ConflictResolutionResult {
        var result = ConflictResolutionResult()

        for (index, conflict) in conflicts.enumerated() {
            guard conflict.resolution != nil else {
                result.skipped.append(conflict)
                continue
            }

            progressHandler?(index + 1, conflicts.count, conflict.fileName)

            do {
                try await executeResolution(conflict, copier: copier)
                result.resolved.append(conflict)
            } catch {
                result.failed.append((conflict, error))
                logger.error("解决冲突失败: \(conflict.relativePath), 错误: \(error)")
            }
        }

        return result
    }

    // MARK: - 私有方法

    /// 新文件优先策略
    private func resolveNewerWins(_ conflict: ConflictInfo) -> ConflictResolution {
        guard let localTime = conflict.localModifiedTime,
              let externalTime = conflict.externalModifiedTime else {
            return .localWinsWithBackup
        }

        return localTime > externalTime ? .localWinsWithBackup : .externalWinsWithBackup
    }

    /// 大文件优先策略
    private func resolveLargerWins(_ conflict: ConflictInfo) -> ConflictResolution {
        return conflict.localSize >= conflict.externalSize ? .keepLocal : .keepExternal
    }

    /// 复制本地到外置
    private func copyLocalToExternal(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        let localURL = URL(fileURLWithPath: conflict.localPath)
        let externalURL = URL(fileURLWithPath: conflict.externalPath)

        try await copier.copy(from: localURL, to: externalURL)
    }

    /// 复制外置到本地
    private func copyExternalToLocal(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        let localURL = URL(fileURLWithPath: conflict.localPath)
        let externalURL = URL(fileURLWithPath: conflict.externalPath)

        try await copier.copy(from: externalURL, to: localURL)
    }

    /// 备份外置文件并用本地覆盖
    private func backupAndCopyLocalToExternal(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        let localURL = URL(fileURLWithPath: conflict.localPath)
        let externalURL = URL(fileURLWithPath: conflict.externalPath)

        // 备份外置文件
        if fileManager.fileExists(atPath: externalURL.path) {
            let backupURL = try await copier.createBackup(of: externalURL, suffix: backupSuffix)
            logger.info("已备份: \(externalURL.lastPathComponent) → \(backupURL.lastPathComponent)")
        }

        // 复制本地到外置
        try await copier.copy(from: localURL, to: externalURL)
    }

    /// 备份本地文件并用外置覆盖
    private func backupAndCopyExternalToLocal(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        let localURL = URL(fileURLWithPath: conflict.localPath)
        let externalURL = URL(fileURLWithPath: conflict.externalPath)

        // 备份本地文件
        if fileManager.fileExists(atPath: localURL.path) {
            let backupURL = try await copier.createBackup(of: localURL, suffix: backupSuffix)
            logger.info("已备份: \(localURL.lastPathComponent) → \(backupURL.lastPathComponent)")
        }

        // 复制外置到本地
        try await copier.copy(from: externalURL, to: localURL)
    }

    /// 保留两个版本
    private func keepBothVersions(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        let localURL = URL(fileURLWithPath: conflict.localPath)
        let externalURL = URL(fileURLWithPath: conflict.externalPath)

        // 重命名本地文件
        let localRenamed = generateVersionedPath(localURL, suffix: "_local")
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.moveItem(at: localURL, to: localRenamed)
        }

        // 重命名外置文件（如果在同一目录）
        let externalRenamed = generateVersionedPath(externalURL, suffix: "_external")
        if fileManager.fileExists(atPath: externalURL.path) {
            try fileManager.moveItem(at: externalURL, to: externalRenamed)
        }

        logger.info("保留两个版本: \(conflict.fileName)")
    }

    /// 生成版本化路径
    private func generateVersionedPath(_ url: URL, suffix: String) -> URL {
        let directory = url.deletingLastPathComponent()
        let fileName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        let newName = ext.isEmpty
            ? "\(fileName)\(suffix)"
            : "\(fileName)\(suffix).\(ext)"

        return directory.appendingPathComponent(newName)
    }
}

// MARK: - 冲突解决结果

struct ConflictResolutionResult {
    /// 已解决的冲突
    var resolved: [ConflictInfo] = []

    /// 跳过的冲突（未设置解决方案）
    var skipped: [ConflictInfo] = []

    /// 失败的冲突
    var failed: [(conflict: ConflictInfo, error: Error)] = []

    var totalCount: Int {
        resolved.count + skipped.count + failed.count
    }

    var successRate: Double {
        totalCount > 0 ? Double(resolved.count) / Double(totalCount) : 1.0
    }

    var summary: String {
        var parts: [String] = []
        if !resolved.isEmpty { parts.append("已解决 \(resolved.count)") }
        if !skipped.isEmpty { parts.append("跳过 \(skipped.count)") }
        if !failed.isEmpty { parts.append("失败 \(failed.count)") }
        return parts.isEmpty ? "无冲突" : parts.joined(separator: ", ")
    }
}

// MARK: - 冲突错误

enum ConflictError: Error, LocalizedError {
    case unresolved(String)
    case backupFailed(String, Error)
    case copyFailed(String, Error)
    case invalidResolution(String)

    var errorDescription: String? {
        switch self {
        case .unresolved(let path):
            return "冲突未解决: \(path)"
        case .backupFailed(let path, let error):
            return "备份失败: \(path), 错误: \(error.localizedDescription)"
        case .copyFailed(let path, let error):
            return "复制失败: \(path), 错误: \(error.localizedDescription)"
        case .invalidResolution(let path):
            return "无效的解决方案: \(path)"
        }
    }
}

// MARK: - 便捷扩展

extension Array where Element == ConflictInfo {
    /// 按冲突类型分组
    var groupedByType: [ConflictType: [ConflictInfo]] {
        Dictionary(grouping: self) { $0.conflictType }
    }

    /// 未解决的冲突
    var unresolved: [ConflictInfo] {
        filter { $0.resolution == nil }
    }

    /// 已解决的冲突
    var resolved: [ConflictInfo] {
        filter { $0.resolution != nil }
    }
}
