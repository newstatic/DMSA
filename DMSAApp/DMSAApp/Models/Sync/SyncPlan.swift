import Foundation

// MARK: - 同步动作

/// 同步动作类型
enum SyncAction: Codable, Identifiable {
    case copy(source: String, destination: String, metadata: FileMetadata)
    case update(source: String, destination: String, metadata: FileMetadata)
    case delete(path: String, metadata: FileMetadata)
    case createDirectory(path: String)
    case createSymlink(path: String, target: String)
    case resolveConflict(conflict: ConflictInfo)
    case skip(path: String, reason: SkipReason)

    var id: String {
        switch self {
        case .copy(_, let dest, _): return "copy:\(dest)"
        case .update(_, let dest, _): return "update:\(dest)"
        case .delete(let path, _): return "delete:\(path)"
        case .createDirectory(let path): return "mkdir:\(path)"
        case .createSymlink(let path, _): return "symlink:\(path)"
        case .resolveConflict(let conflict): return "conflict:\(conflict.relativePath)"
        case .skip(let path, _): return "skip:\(path)"
        }
    }

    /// 动作描述
    var description: String {
        switch self {
        case .copy(_, let dest, let meta):
            return "复制: \(meta.fileName) → \(dest)"
        case .update(_, let dest, let meta):
            return "更新: \(meta.fileName) → \(dest)"
        case .delete(let path, _):
            return "删除: \(path)"
        case .createDirectory(let path):
            return "创建目录: \(path)"
        case .createSymlink(let path, let target):
            return "创建链接: \(path) → \(target)"
        case .resolveConflict(let conflict):
            return "解决冲突: \(conflict.relativePath)"
        case .skip(let path, let reason):
            return "跳过: \(path) (\(reason.description))"
        }
    }

    /// 涉及的字节数
    var bytes: Int64 {
        switch self {
        case .copy(_, _, let meta), .update(_, _, let meta):
            return meta.size
        default:
            return 0
        }
    }

    /// 目标路径
    var targetPath: String {
        switch self {
        case .copy(_, let dest, _), .update(_, let dest, _):
            return dest
        case .delete(let path, _), .createDirectory(let path), .createSymlink(let path, _):
            return path
        case .resolveConflict(let conflict):
            return conflict.relativePath
        case .skip(let path, _):
            return path
        }
    }
}

/// 跳过原因
enum SkipReason: String, Codable {
    case identical = "identical"          // 文件相同
    case excluded = "excluded"            // 被排除规则过滤
    case permissionDenied = "permission"  // 权限不足
    case tooLarge = "too_large"           // 文件过大
    case inUse = "in_use"                 // 文件正在使用
    case notSupported = "not_supported"   // 不支持的文件类型

    var description: String {
        switch self {
        case .identical: return "文件相同"
        case .excluded: return "被排除"
        case .permissionDenied: return "权限不足"
        case .tooLarge: return "文件过大"
        case .inUse: return "文件占用中"
        case .notSupported: return "不支持"
        }
    }
}

// MARK: - 同步计划

/// 同步计划 - 包含所有待执行的同步动作
struct SyncPlan: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let syncPairId: String
    let direction: SyncDirection

    /// 源目录路径
    let sourcePath: String

    /// 目标目录路径
    let destinationPath: String

    /// 待执行的动作列表
    var actions: [SyncAction]

    /// 冲突列表
    var conflicts: [ConflictInfo]

    /// 源目录快照
    var sourceSnapshot: DirectorySnapshot?

    /// 目标目录快照
    var destinationSnapshot: DirectorySnapshot?

    // MARK: - 统计信息

    /// 总文件数
    var totalFiles: Int {
        actions.filter { action in
            switch action {
            case .copy, .update: return true
            default: return false
            }
        }.count
    }

    /// 总字节数
    var totalBytes: Int64 {
        actions.reduce(0) { $0 + $1.bytes }
    }

    /// 需要复制的文件数
    var filesToCopy: Int {
        actions.filter { if case .copy = $0 { return true }; return false }.count
    }

    /// 需要更新的文件数
    var filesToUpdate: Int {
        actions.filter { if case .update = $0 { return true }; return false }.count
    }

    /// 需要删除的文件数
    var filesToDelete: Int {
        actions.filter { if case .delete = $0 { return true }; return false }.count
    }

    /// 需要创建的目录数
    var directoriesToCreate: Int {
        actions.filter { if case .createDirectory = $0 { return true }; return false }.count
    }

    /// 跳过的文件数
    var skippedFiles: Int {
        actions.filter { if case .skip = $0 { return true }; return false }.count
    }

    /// 冲突数量
    var conflictCount: Int {
        conflicts.count
    }

    /// 是否有待处理的冲突
    var hasUnresolvedConflicts: Bool {
        conflicts.contains { $0.resolution == nil }
    }

    // MARK: - 初始化

    init(
        syncPairId: String,
        direction: SyncDirection,
        sourcePath: String,
        destinationPath: String,
        actions: [SyncAction] = [],
        conflicts: [ConflictInfo] = []
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.syncPairId = syncPairId
        self.direction = direction
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.actions = actions
        self.conflicts = conflicts
    }

    // MARK: - 方法

    /// 获取计划摘要
    var summary: SyncPlanSummary {
        SyncPlanSummary(
            totalFiles: totalFiles,
            totalBytes: totalBytes,
            filesToCopy: filesToCopy,
            filesToUpdate: filesToUpdate,
            filesToDelete: filesToDelete,
            directoriesToCreate: directoriesToCreate,
            skippedFiles: skippedFiles,
            conflictCount: conflictCount
        )
    }

    /// 添加动作
    mutating func addAction(_ action: SyncAction) {
        actions.append(action)
    }

    /// 添加冲突
    mutating func addConflict(_ conflict: ConflictInfo) {
        conflicts.append(conflict)
    }

    /// 移除已解决的冲突对应的动作
    mutating func applyConflictResolutions() {
        for conflict in conflicts where conflict.resolution != nil {
            // 移除原有的冲突动作
            actions.removeAll { action in
                if case .resolveConflict(let c) = action {
                    return c.id == conflict.id
                }
                return false
            }

            // 根据解决方案添加新动作
            if let resolution = conflict.resolution {
                switch resolution {
                case .keepLocal:
                    if let localMeta = conflict.localMetadata {
                        actions.append(.update(
                            source: conflict.localPath,
                            destination: conflict.externalPath,
                            metadata: localMeta
                        ))
                    }
                case .keepExternal:
                    if let externalMeta = conflict.externalMetadata {
                        actions.append(.update(
                            source: conflict.externalPath,
                            destination: conflict.localPath,
                            metadata: externalMeta
                        ))
                    }
                case .keepBoth:
                    // 保留两者，重命名处理
                    break
                case .skip:
                    actions.append(.skip(path: conflict.relativePath, reason: .identical))
                case .localWinsWithBackup, .externalWinsWithBackup:
                    // 备份处理在执行时进行
                    break
                }
            }
        }
    }
}

/// 同步计划摘要
struct SyncPlanSummary: Codable {
    let totalFiles: Int
    let totalBytes: Int64
    let filesToCopy: Int
    let filesToUpdate: Int
    let filesToDelete: Int
    let directoriesToCreate: Int
    let skippedFiles: Int
    let conflictCount: Int

    var formattedTotalBytes: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var isEmpty: Bool {
        filesToCopy == 0 && filesToUpdate == 0 && filesToDelete == 0 && directoriesToCreate == 0
    }

    var description: String {
        var parts: [String] = []
        if filesToCopy > 0 { parts.append("复制 \(filesToCopy) 个") }
        if filesToUpdate > 0 { parts.append("更新 \(filesToUpdate) 个") }
        if filesToDelete > 0 { parts.append("删除 \(filesToDelete) 个") }
        if directoriesToCreate > 0 { parts.append("创建 \(directoriesToCreate) 个目录") }
        if conflictCount > 0 { parts.append("\(conflictCount) 个冲突") }

        if parts.isEmpty {
            return "无需同步"
        }

        return parts.joined(separator: ", ") + " (\(formattedTotalBytes))"
    }
}

// MARK: - 同步结果

/// 同步执行结果
struct SyncResult: Codable {
    let planId: UUID
    let startTime: Date
    let endTime: Date
    let success: Bool

    /// 成功的动作数
    let succeededActions: Int

    /// 失败的动作
    let failedActions: [FailedAction]

    /// 传输的文件数
    let filesTransferred: Int

    /// 传输的字节数
    let bytesTransferred: Int64

    /// 已验证的文件数
    let filesVerified: Int

    /// 验证失败的文件数
    let verificationFailures: Int

    /// 错误信息
    let errorMessage: String?

    /// 是否被取消
    let wasCancelled: Bool

    /// 是否从暂停恢复
    let wasResumed: Bool

    /// 执行耗时
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// 格式化的耗时
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "\(Int(duration))s"
    }

    /// 平均传输速度 (bytes/s)
    var averageSpeed: Int64 {
        guard duration > 0 else { return 0 }
        return Int64(Double(bytesTransferred) / duration)
    }

    /// 格式化的传输速度
    var formattedSpeed: String {
        ByteCountFormatter.string(fromByteCount: averageSpeed, countStyle: .file) + "/s"
    }
}

/// 失败的动作记录
struct FailedAction: Codable {
    let action: SyncAction
    let error: String
    let timestamp: Date
}
