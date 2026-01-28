import Foundation

// MARK: - VFS Types
// Note: MountInfo, SyncStatusInfo, ServiceVersionInfo 定义在 DMSAShared/Models/SharedState.swift

/// 索引统计信息
 struct IndexStats: Codable {
     var totalFiles: Int
     var totalDirectories: Int
     var localOnlyCount: Int
     var externalOnlyCount: Int
     var bothCount: Int
     var dirtyCount: Int
     var totalSize: Int64
     var lastUpdated: Date?

     init(totalFiles: Int = 0,
                totalDirectories: Int = 0,
                localOnlyCount: Int = 0,
                externalOnlyCount: Int = 0,
                bothCount: Int = 0,
                dirtyCount: Int = 0,
                totalSize: Int64 = 0,
                lastUpdated: Date? = nil) {
        self.totalFiles = totalFiles
        self.totalDirectories = totalDirectories
        self.localOnlyCount = localOnlyCount
        self.externalOnlyCount = externalOnlyCount
        self.bothCount = bothCount
        self.dirtyCount = dirtyCount
        self.totalSize = totalSize
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Sync Types
// Note: SyncStatusInfo 定义在 DMSAShared/Models/SharedState.swift

/// 同步进度 XPC 响应 (从服务返回的可解码版本)
 struct SyncProgressResponse: Codable {
     var syncPairId: String
     var status: SyncStatus
     var totalFiles: Int
     var processedFiles: Int
     var totalBytes: Int64
     var processedBytes: Int64
     var currentFile: String?
     var startTime: Date?
     var endTime: Date?
     var errorMessage: String?
     var speed: Int64

     init(syncPairId: String) {
        self.syncPairId = syncPairId
        self.status = .pending
        self.totalFiles = 0
        self.processedFiles = 0
        self.totalBytes = 0
        self.processedBytes = 0
        self.currentFile = nil
        self.startTime = nil
        self.endTime = nil
        self.errorMessage = nil
        self.speed = 0
    }

     static func from(data: Data) -> SyncProgressResponse? {
        return try? JSONDecoder().decode(SyncProgressResponse.self, from: data)
    }

     var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(processedBytes) / Double(totalBytes)
    }

     var fileProgress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(processedFiles) / Double(totalFiles)
    }

    /// 总体进度 (字节维度)
    var overallProgress: Double {
        return progress
    }

    /// 是否正在运行
    var isRunning: Bool {
        return status == .inProgress
    }

    /// 是否已暂停
    var isPaused: Bool {
        return status == .paused
    }
}

/// 同步统计 XPC 响应
 struct SyncStatisticsResponse: Codable {
     var syncPairId: String
     var totalSyncs: Int
     var successfulSyncs: Int
     var failedSyncs: Int
     var totalFilesProcessed: Int
     var totalBytesTransferred: Int64
     var averageDuration: TimeInterval

     init(syncPairId: String) {
        self.syncPairId = syncPairId
        self.totalSyncs = 0
        self.successfulSyncs = 0
        self.failedSyncs = 0
        self.totalFilesProcessed = 0
        self.totalBytesTransferred = 0
        self.averageDuration = 0
    }

     static func from(data: Data) -> SyncStatisticsResponse? {
        return try? JSONDecoder().decode(SyncStatisticsResponse.self, from: data)
    }
}

// MARK: - FileEntry Extension

extension FileEntry {
    /// 从字典创建 FileEntry
    static func from(dictionary: [String: Any]) -> FileEntry? {
        let entry = FileEntry()

        entry.virtualPath = dictionary["virtualPath"] as? String ?? ""
        entry.localPath = dictionary["localPath"] as? String
        entry.externalPath = dictionary["externalPath"] as? String
        entry.size = dictionary["size"] as? Int64 ?? 0
        entry.isDirty = dictionary["isDirty"] as? Bool ?? false
        entry.isDirectory = dictionary["isDirectory"] as? Bool ?? false
        entry.syncPairId = dictionary["syncPairId"] as? String
        entry.diskId = dictionary["diskId"] as? String
        entry.checksum = dictionary["checksum"] as? String

        if let locationRaw = dictionary["location"] as? Int,
           let location = FileLocation(rawValue: locationRaw) {
            entry.location = location
        }

        if let modifiedInterval = dictionary["modifiedAt"] as? TimeInterval {
            entry.modifiedAt = Date(timeIntervalSince1970: modifiedInterval)
        }

        if let accessedInterval = dictionary["accessedAt"] as? TimeInterval {
            entry.accessedAt = Date(timeIntervalSince1970: accessedInterval)
        }

        return entry
    }

    /// 转换为字典
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "virtualPath": virtualPath,
            "location": location.rawValue,
            "size": size,
            "isDirty": isDirty,
            "isDirectory": isDirectory,
            "modifiedAt": modifiedAt.timeIntervalSince1970,
            "accessedAt": accessedAt.timeIntervalSince1970
        ]

        if let localPath = localPath {
            dict["localPath"] = localPath
        }
        if let externalPath = externalPath {
            dict["externalPath"] = externalPath
        }
        if let syncPairId = syncPairId {
            dict["syncPairId"] = syncPairId
        }
        if let diskId = diskId {
            dict["diskId"] = diskId
        }
        if let checksum = checksum {
            dict["checksum"] = checksum
        }

        return dict
    }
}

// MARK: - Eviction Types

/// 淘汰配置
struct EvictionConfig: Codable {
    var triggerThreshold: Int64
    var targetFreeSpace: Int64
    var maxFilesPerRun: Int
    var minFileAge: TimeInterval
    var autoEvictionEnabled: Bool
    var checkInterval: TimeInterval

    init(triggerThreshold: Int64 = 5 * 1024 * 1024 * 1024,
         targetFreeSpace: Int64 = 10 * 1024 * 1024 * 1024,
         maxFilesPerRun: Int = 100,
         minFileAge: TimeInterval = 3600,
         autoEvictionEnabled: Bool = true,
         checkInterval: TimeInterval = 300) {
        self.triggerThreshold = triggerThreshold
        self.targetFreeSpace = targetFreeSpace
        self.maxFilesPerRun = maxFilesPerRun
        self.minFileAge = minFileAge
        self.autoEvictionEnabled = autoEvictionEnabled
        self.checkInterval = checkInterval
    }
}

/// 淘汰统计
struct EvictionStats: Codable {
    var evictedCount: Int
    var evictedSize: Int64
    var lastEvictionTime: Date?
    var skippedDirty: Int
    var skippedLocked: Int
    var failedSync: Int

    init(evictedCount: Int = 0,
         evictedSize: Int64 = 0,
         lastEvictionTime: Date? = nil,
         skippedDirty: Int = 0,
         skippedLocked: Int = 0,
         failedSync: Int = 0) {
        self.evictedCount = evictedCount
        self.evictedSize = evictedSize
        self.lastEvictionTime = lastEvictionTime
        self.skippedDirty = skippedDirty
        self.skippedLocked = skippedLocked
        self.failedSync = failedSync
    }
}

/// 淘汰结果
struct EvictionResult: Codable {
    var evictedFiles: [String]
    var freedSpace: Int64
    var errors: [String]

    init(evictedFiles: [String] = [],
         freedSpace: Int64 = 0,
         errors: [String] = []) {
        self.evictedFiles = evictedFiles
        self.freedSpace = freedSpace
        self.errors = errors
    }
}

// MARK: - SyncFileRecord

/// 文件级同步/淘汰记录 (App 端模型)
struct SyncFileRecord: Codable, Identifiable {
    var id: UInt64 = 0
    var syncPairId: String = ""
    var diskId: String = ""
    var virtualPath: String = ""
    var fileSize: Int64 = 0
    var syncedAt: Date = Date()
    /// 操作状态: 0=同步成功, 1=同步失败, 2=跳过, 3=淘汰成功, 4=淘汰失败
    var status: Int = 0
    var errorMessage: String?
    var syncTaskId: UInt64 = 0

    var statusDescription: String {
        switch status {
        case 0: return "同步成功"
        case 1: return "同步失败"
        case 2: return "跳过"
        case 3: return "淘汰成功"
        case 4: return "淘汰失败"
        default: return "未知"
        }
    }

    var isSuccess: Bool { status == 0 || status == 3 }
    var isSync: Bool { status <= 2 }
    var isEviction: Bool { status >= 3 }

    var fileName: String {
        (virtualPath as NSString).lastPathComponent
    }

    static func arrayFrom(data: Data) -> [SyncFileRecord] {
        return (try? JSONDecoder().decode([SyncFileRecord].self, from: data)) ?? []
    }
}

// MARK: - SyncHistory Extension

extension SyncHistory {
    /// 从 Data 数组创建 SyncHistory 数组
    static func arrayFrom(data: Data) -> [SyncHistory] {
        do {
            let histories = try JSONDecoder().decode([SyncHistory].self, from: data)
            return histories
        } catch {
            Logger.shared.error("[SyncHistory] 解码失败: \(error)")
            if let jsonStr = String(data: data, encoding: .utf8) {
                Logger.shared.debug("[SyncHistory] 原始 JSON (前 500 字符): \(String(jsonStr.prefix(500)))")
            }
            return []
        }
    }
}
