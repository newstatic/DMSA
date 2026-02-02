import Foundation

/// Conflict Resolver - Handles sync conflicts
class ConflictResolver {

    // MARK: - Properties

    /// Default strategy
    var defaultStrategy: ConflictStrategy = .localWinsWithBackup

    /// Backup file suffix
    var backupSuffix: String = "_backup"

    /// Whether to auto-resolve conflicts
    var autoResolve: Bool = true

    /// User conflict resolution callback
    var userResolutionHandler: (([ConflictInfo]) async -> [ConflictInfo])?

    /// File manager
    private let fileManager = FileManager.default

    /// Logger
    private let logger = Logger.forService("ConflictResolver")

    // MARK: - Initialization

    init(
        defaultStrategy: ConflictStrategy = .localWinsWithBackup,
        backupSuffix: String = "_backup",
        autoResolve: Bool = true
    ) {
        self.defaultStrategy = defaultStrategy
        self.backupSuffix = backupSuffix
        self.autoResolve = autoResolve
    }

    // MARK: - Public Methods

    /// Resolve conflict list
    func resolve(conflicts: [ConflictInfo]) async -> [ConflictInfo] {
        if autoResolve {
            return autoResolveConflicts(conflicts)
        } else if let handler = userResolutionHandler {
            return await handler(conflicts)
        } else {
            return autoResolveConflicts(conflicts)
        }
    }

    /// Auto-resolve conflicts
    func autoResolveConflicts(_ conflicts: [ConflictInfo]) -> [ConflictInfo] {
        return conflicts.map { conflict in
            var resolved = conflict
            if resolved.resolution == nil {
                resolved.resolve(with: resolveWithStrategy(conflict, strategy: defaultStrategy))
            }
            return resolved
        }
    }

    /// Resolve single conflict with specified strategy
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
            // If strategy is ask user but no handler, use recommended resolution
            return conflict.recommendedResolution()

        case .keepBoth:
            return .keepBoth
        }
    }

    /// Execute conflict resolution
    func executeResolution(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        guard let resolution = conflict.resolution else {
            throw ConflictError.unresolved(conflict.relativePath)
        }

        switch resolution {
        case .keepLocal:
            // Overwrite external version with local version
            try await copyLocalToExternal(conflict, copier: copier)

        case .keepExternal:
            // Overwrite local version with external version
            try await copyExternalToLocal(conflict, copier: copier)

        case .localWinsWithBackup:
            // Backup external file, then overwrite with local
            try await backupAndCopyLocalToExternal(conflict, copier: copier)

        case .externalWinsWithBackup:
            // Backup local file, then overwrite with external
            try await backupAndCopyExternalToLocal(conflict, copier: copier)

        case .keepBoth:
            // Keep both versions, rename
            try await keepBothVersions(conflict, copier: copier)

        case .skip:
            // No action
            logger.info("Skipping conflict: \(conflict.relativePath)")
        }
    }

    /// Batch execute conflict resolutions
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
                logger.error("Failed to resolve conflict: \(conflict.relativePath), error: \(error)")
            }
        }

        return result
    }

    // MARK: - Private Methods

    /// Newer file wins strategy
    private func resolveNewerWins(_ conflict: ConflictInfo) -> ConflictResolution {
        guard let localTime = conflict.localModifiedTime,
              let externalTime = conflict.externalModifiedTime else {
            return .localWinsWithBackup
        }

        return localTime > externalTime ? .localWinsWithBackup : .externalWinsWithBackup
    }

    /// Larger file wins strategy
    private func resolveLargerWins(_ conflict: ConflictInfo) -> ConflictResolution {
        return conflict.localSize >= conflict.externalSize ? .keepLocal : .keepExternal
    }

    /// Copy local to external
    private func copyLocalToExternal(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        let localURL = URL(fileURLWithPath: conflict.localPath)
        let externalURL = URL(fileURLWithPath: conflict.externalPath)

        try await copier.copy(from: localURL, to: externalURL)
    }

    /// Copy external to local
    private func copyExternalToLocal(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        let localURL = URL(fileURLWithPath: conflict.localPath)
        let externalURL = URL(fileURLWithPath: conflict.externalPath)

        try await copier.copy(from: externalURL, to: localURL)
    }

    /// Backup external file and overwrite with local
    private func backupAndCopyLocalToExternal(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        let localURL = URL(fileURLWithPath: conflict.localPath)
        let externalURL = URL(fileURLWithPath: conflict.externalPath)

        // Backup external file
        if fileManager.fileExists(atPath: externalURL.path) {
            let backupURL = try await copier.createBackup(of: externalURL, suffix: backupSuffix)
            logger.info("Backed up: \(externalURL.lastPathComponent) -> \(backupURL.lastPathComponent)")
        }

        // Copy local to external
        try await copier.copy(from: localURL, to: externalURL)
    }

    /// Backup local file and overwrite with external
    private func backupAndCopyExternalToLocal(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        let localURL = URL(fileURLWithPath: conflict.localPath)
        let externalURL = URL(fileURLWithPath: conflict.externalPath)

        // Backup local file
        if fileManager.fileExists(atPath: localURL.path) {
            let backupURL = try await copier.createBackup(of: localURL, suffix: backupSuffix)
            logger.info("Backed up: \(localURL.lastPathComponent) -> \(backupURL.lastPathComponent)")
        }

        // Copy external to local
        try await copier.copy(from: externalURL, to: localURL)
    }

    /// Keep both versions
    private func keepBothVersions(_ conflict: ConflictInfo, copier: FileCopier) async throws {
        let localURL = URL(fileURLWithPath: conflict.localPath)
        let externalURL = URL(fileURLWithPath: conflict.externalPath)

        // Rename local file
        let localRenamed = generateVersionedPath(localURL, suffix: "_local")
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.moveItem(at: localURL, to: localRenamed)
        }

        // Rename external file (if in same directory)
        let externalRenamed = generateVersionedPath(externalURL, suffix: "_external")
        if fileManager.fileExists(atPath: externalURL.path) {
            try fileManager.moveItem(at: externalURL, to: externalRenamed)
        }

        logger.info("Kept both versions: \(conflict.fileName)")
    }

    /// Generate versioned path
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

// MARK: - Conflict Resolution Result

struct ConflictResolutionResult {
    /// Resolved conflicts
    var resolved: [ConflictInfo] = []

    /// Skipped conflicts (no resolution set)
    var skipped: [ConflictInfo] = []

    /// Failed conflicts
    var failed: [(conflict: ConflictInfo, error: Error)] = []

    var totalCount: Int {
        resolved.count + skipped.count + failed.count
    }

    var successRate: Double {
        totalCount > 0 ? Double(resolved.count) / Double(totalCount) : 1.0
    }

    var summary: String {
        var parts: [String] = []
        if !resolved.isEmpty { parts.append("resolved \(resolved.count)") }
        if !skipped.isEmpty { parts.append("skipped \(skipped.count)") }
        if !failed.isEmpty { parts.append("failed \(failed.count)") }
        return parts.isEmpty ? "no conflicts" : parts.joined(separator: ", ")
    }
}

// MARK: - Conflict Errors

enum ConflictError: Error, LocalizedError {
    case unresolved(String)
    case backupFailed(String, Error)
    case copyFailed(String, Error)
    case invalidResolution(String)

    var errorDescription: String? {
        switch self {
        case .unresolved(let path):
            return "Conflict unresolved: \(path)"
        case .backupFailed(let path, let error):
            return "Backup failed: \(path), error: \(error.localizedDescription)"
        case .copyFailed(let path, let error):
            return "Copy failed: \(path), error: \(error.localizedDescription)"
        case .invalidResolution(let path):
            return "Invalid resolution: \(path)"
        }
    }
}

// MARK: - Convenience Extensions

extension Array where Element == ConflictInfo {
    /// Group by conflict type
    var groupedByType: [ConflictType: [ConflictInfo]] {
        Dictionary(grouping: self) { $0.conflictType }
    }

    /// Unresolved conflicts
    var unresolved: [ConflictInfo] {
        filter { $0.resolution == nil }
    }

    /// Resolved conflicts
    var resolved: [ConflictInfo] {
        filter { $0.resolution != nil }
    }
}
