import Foundation

// MARK: - VFS Types

/// 挂载信息
 struct MountInfo: Codable, Identifiable {
     var id: String  // syncPairId
     var syncPairId: String
     var targetDir: String
     var localDir: String
     var externalDir: String?
     var isMounted: Bool
     var isExternalOnline: Bool
     var mountedAt: Date?
     var fileCount: Int
     var totalSize: Int64

     init(syncPairId: String, targetDir: String, localDir: String) {
        self.id = syncPairId
        self.syncPairId = syncPairId
        self.targetDir = targetDir
        self.localDir = localDir
        self.externalDir = nil
        self.isMounted = false
        self.isExternalOnline = false
        self.mountedAt = nil
        self.fileCount = 0
        self.totalSize = 0
    }

     static func arrayFrom(data: Data) -> [MountInfo] {
        return (try? JSONDecoder().decode([MountInfo].self, from: data)) ?? []
    }

     static func from(data: Data) -> MountInfo? {
        return try? JSONDecoder().decode(MountInfo.self, from: data)
    }
}

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

/// 同步状态信息
 struct SyncStatusInfo: Codable, Identifiable {
     var id: String  // syncPairId
     var syncPairId: String
     var status: SyncStatus
     var isPaused: Bool
     var lastSyncTime: Date?
     var nextSyncTime: Date?
     var pendingFiles: Int
     var dirtyFiles: Int

     init(syncPairId: String) {
        self.id = syncPairId
        self.syncPairId = syncPairId
        self.status = .pending
        self.isPaused = false
        self.lastSyncTime = nil
        self.nextSyncTime = nil
        self.pendingFiles = 0
        self.dirtyFiles = 0
    }

     static func from(data: Data) -> SyncStatusInfo? {
        return try? JSONDecoder().decode(SyncStatusInfo.self, from: data)
    }

     static func arrayFrom(data: Data) -> [SyncStatusInfo] {
        guard let statuses = try? JSONDecoder().decode([SyncStatusInfo].self, from: data) else {
            return []
        }
        return statuses
    }
}

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

// MARK: - SyncHistory Extension

extension SyncHistory {
    /// 从 Data 数组创建 SyncHistory 数组
    static func arrayFrom(data: Data) -> [SyncHistory] {
        guard let histories = try? JSONDecoder().decode([SyncHistory].self, from: data) else {
            return []
        }
        return histories
    }
}
