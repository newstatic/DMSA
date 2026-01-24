import Foundation

/// 冲突信息
public struct ConflictInfo: Codable, Identifiable, Sendable {
    public let id: UUID

    /// 文件相对路径
    public let relativePath: String

    /// 本地文件完整路径
    public let localPath: String

    /// 外置文件完整路径
    public let externalPath: String

    /// 本地文件元数据 (如果存在)
    public let localMetadata: FileMetadata?

    /// 外置文件元数据 (如果存在)
    public let externalMetadata: FileMetadata?

    /// 冲突类型
    public let conflictType: ConflictType

    /// 检测时间
    public let detectedAt: Date

    /// 用户选择的解决方案
    public var resolution: ConflictResolution?

    /// 解决时间
    public var resolvedAt: Date?

    // MARK: - 计算属性

    /// 文件名
    public var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    /// 本地文件大小
    public var localSize: Int64 {
        localMetadata?.size ?? 0
    }

    /// 外置文件大小
    public var externalSize: Int64 {
        externalMetadata?.size ?? 0
    }

    /// 本地修改时间
    public var localModifiedTime: Date? {
        localMetadata?.modifiedTime
    }

    /// 外置修改时间
    public var externalModifiedTime: Date? {
        externalMetadata?.modifiedTime
    }

    /// 是否已解决
    public var isResolved: Bool {
        resolution != nil
    }

    /// 冲突描述
    public var description: String {
        switch conflictType {
        case .bothModified:
            return "两端都修改了 \(fileName)"
        case .deletedOnLocal:
            return "\(fileName) 在本地被删除，但外置有修改"
        case .deletedOnExternal:
            return "\(fileName) 在外置被删除，但本地有修改"
        case .typeChanged:
            return "\(fileName) 的类型发生变化"
        case .permissionConflict:
            return "\(fileName) 的权限不一致"
        }
    }

    // MARK: - 初始化

    public init(
        relativePath: String,
        localPath: String,
        externalPath: String,
        localMetadata: FileMetadata?,
        externalMetadata: FileMetadata?,
        conflictType: ConflictType
    ) {
        self.id = UUID()
        self.relativePath = relativePath
        self.localPath = localPath
        self.externalPath = externalPath
        self.localMetadata = localMetadata
        self.externalMetadata = externalMetadata
        self.conflictType = conflictType
        self.detectedAt = Date()
    }

    // MARK: - 方法

    /// 应用解决方案
    public mutating func resolve(with resolution: ConflictResolution) {
        self.resolution = resolution
        self.resolvedAt = Date()
    }

    /// 获取推荐的解决方案
    public func recommendedResolution() -> ConflictResolution {
        switch conflictType {
        case .bothModified:
            // 比较修改时间，较新的优先
            if let localTime = localModifiedTime, let externalTime = externalModifiedTime {
                return localTime > externalTime ? .localWinsWithBackup : .externalWinsWithBackup
            }
            return .localWinsWithBackup

        case .deletedOnLocal:
            // 本地删除，保留外置版本
            return .keepExternal

        case .deletedOnExternal:
            // 外置删除，保留本地版本
            return .keepLocal

        case .typeChanged:
            // 类型变化，保留本地
            return .localWinsWithBackup

        case .permissionConflict:
            // 权限冲突，保留本地
            return .keepLocal
        }
    }
}

// MARK: - 冲突类型

/// 冲突类型枚举
public enum ConflictType: String, Codable, Sendable {
    /// 两端都修改了同一文件
    case bothModified = "both_modified"

    /// 本地删除但外置修改
    case deletedOnLocal = "deleted_on_local"

    /// 外置删除但本地修改
    case deletedOnExternal = "deleted_on_external"

    /// 文件类型变化 (如文件变目录)
    case typeChanged = "type_changed"

    /// 权限冲突
    case permissionConflict = "permission_conflict"

    public var description: String {
        switch self {
        case .bothModified: return "双方修改"
        case .deletedOnLocal: return "本地删除"
        case .deletedOnExternal: return "外置删除"
        case .typeChanged: return "类型变化"
        case .permissionConflict: return "权限冲突"
        }
    }

    public var icon: String {
        switch self {
        case .bothModified: return "arrow.triangle.2.circlepath"
        case .deletedOnLocal, .deletedOnExternal: return "trash"
        case .typeChanged: return "doc.badge.gearshape"
        case .permissionConflict: return "lock.trianglebadge.exclamationmark"
        }
    }
}

// MARK: - 冲突解决方案

/// 冲突解决方案枚举
public enum ConflictResolution: String, Codable, Sendable {
    /// 保留本地版本
    case keepLocal = "keep_local"

    /// 保留外置版本
    case keepExternal = "keep_external"

    /// 本地版本覆盖外置，备份外置文件
    case localWinsWithBackup = "local_wins_backup"

    /// 外置版本覆盖本地，备份本地文件
    case externalWinsWithBackup = "external_wins_backup"

    /// 保留两个版本 (重命名)
    case keepBoth = "keep_both"

    /// 跳过，不处理
    case skip = "skip"

    public var description: String {
        switch self {
        case .keepLocal: return "保留本地"
        case .keepExternal: return "保留外置"
        case .localWinsWithBackup: return "本地覆盖 (备份)"
        case .externalWinsWithBackup: return "外置覆盖 (备份)"
        case .keepBoth: return "保留两者"
        case .skip: return "跳过"
        }
    }

    public var icon: String {
        switch self {
        case .keepLocal: return "internaldrive"
        case .keepExternal: return "externaldrive"
        case .localWinsWithBackup: return "internaldrive.badge.checkmark"
        case .externalWinsWithBackup: return "externaldrive.badge.checkmark"
        case .keepBoth: return "doc.on.doc"
        case .skip: return "forward"
        }
    }
}

// MARK: - 冲突解决策略

/// 冲突自动解决策略
public enum ConflictStrategy: String, Codable, CaseIterable, Sendable {
    /// 较新的文件覆盖较旧的
    case newerWins = "newer_wins"

    /// 较大的文件覆盖较小的
    case largerWins = "larger_wins"

    /// 本地文件总是优先
    case localWins = "local_wins"

    /// 外置文件总是优先
    case externalWins = "external_wins"

    /// 本地优先，并备份目标文件 (默认)
    case localWinsWithBackup = "local_wins_backup"

    /// 外置优先，并备份本地文件
    case externalWinsWithBackup = "external_wins_backup"

    /// 总是询问用户
    case askUser = "ask_user"

    /// 保留两个版本
    case keepBoth = "keep_both"

    public var description: String {
        switch self {
        case .newerWins: return "新文件覆盖旧文件"
        case .largerWins: return "大文件覆盖小文件"
        case .localWins: return "本地优先"
        case .externalWins: return "外置优先"
        case .localWinsWithBackup: return "本地优先 (备份目标)"
        case .externalWinsWithBackup: return "外置优先 (备份本地)"
        case .askUser: return "总是询问"
        case .keepBoth: return "保留两个版本"
        }
    }

    /// 将策略转换为解决方案
    public func toResolution(for conflict: ConflictInfo) -> ConflictResolution? {
        switch self {
        case .newerWins:
            guard let localTime = conflict.localModifiedTime,
                  let externalTime = conflict.externalModifiedTime else {
                return nil
            }
            return localTime > externalTime ? .keepLocal : .keepExternal

        case .largerWins:
            return conflict.localSize >= conflict.externalSize ? .keepLocal : .keepExternal

        case .localWins:
            return .keepLocal

        case .externalWins:
            return .keepExternal

        case .localWinsWithBackup:
            return .localWinsWithBackup

        case .externalWinsWithBackup:
            return .externalWinsWithBackup

        case .askUser:
            return nil  // 需要用户决定

        case .keepBoth:
            return .keepBoth
        }
    }
}
