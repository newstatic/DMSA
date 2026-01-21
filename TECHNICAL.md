# Delt MACOS Sync App (DMSA) 技术架构文档

> 版本: 2.0 | 更新日期: 2026-01-20

---

## 1. 系统架构概览

### 1.1 核心设计理念

本应用采用**虚拟文件系统 + 双后端存储**架构，实现本地缓存与外置硬盘的透明融合。

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户应用层                                │
│                    (Finder, Safari, etc.)                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    虚拟文件系统层 (VFS)                          │
│              Endpoint Security Framework                         │
│    ┌─────────────┬─────────────┬─────────────┬─────────────┐   │
│    │  读取路由器  │  写入路由器  │  元数据管理  │  冲突解决器  │   │
│    └─────────────┴─────────────┴─────────────┴─────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│    LOCAL 后端            │     │    EXTERNAL 后端         │
│  ~/Library/Application  │     │   /Volumes/BACKUP/      │
│  Support/DMSA/ │     │   Downloads/            │
│  LocalCache/            │     │                         │
│                         │     │                         │
│  - 热数据缓存            │     │  - 完整数据存储          │
│  - 最大空间限制          │     │  - 主存储源              │
│  - LRU 淘汰策略          │     │  - 可能离线              │
└─────────────────────────┘     └─────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    数据持久层 (ObjectBox)                        │
│    ┌─────────────┬─────────────┬─────────────┬─────────────┐   │
│    │  文件索引    │  同步状态    │  配置数据    │  历史统计    │   │
│    └─────────────┴─────────────┴─────────────┴─────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 关键技术选型

| 组件 | 技术方案 | 选型理由 |
|------|----------|----------|
| 文件系统监控 | Endpoint Security | Apple 原生，无需第三方驱动，系统级集成 |
| 数据存储 | ObjectBox Swift | 高性能嵌入式数据库，支持实时同步 |
| 同步引擎 | rsync + 自定义逻辑 | 成熟稳定，支持增量同步 |
| UI 框架 | SwiftUI | 现代化，支持深色模式，代码简洁 |
| 进程管理 | LaunchAgent | 系统原生，开机自启动 |

---

## 2. 虚拟文件系统层 (VFS)

### 2.1 Endpoint Security Framework

#### 2.1.1 概述

Endpoint Security (ES) 是 Apple 提供的系统级安全框架，允许应用监控和授权文件系统操作。

**权限要求:**
- System Extension 批准
- Full Disk Access (TCC)
- com.apple.developer.endpoint-security.client entitlement

#### 2.1.2 事件订阅

```swift
// 需要监控的 ES 事件
enum MonitoredEvents {
    // 文件操作
    static let fileEvents: [es_event_type_t] = [
        ES_EVENT_TYPE_AUTH_OPEN,        // 文件打开授权
        ES_EVENT_TYPE_AUTH_CREATE,      // 文件创建授权
        ES_EVENT_TYPE_AUTH_UNLINK,      // 文件删除授权
        ES_EVENT_TYPE_AUTH_RENAME,      // 文件重命名授权
        ES_EVENT_TYPE_AUTH_WRITE,       // 文件写入授权
        ES_EVENT_TYPE_AUTH_TRUNCATE,    // 文件截断授权

        ES_EVENT_TYPE_NOTIFY_WRITE,     // 写入完成通知
        ES_EVENT_TYPE_NOTIFY_UNLINK,    // 删除完成通知
        ES_EVENT_TYPE_NOTIFY_RENAME,    // 重命名完成通知
    ]
}
```

#### 2.1.3 核心流程

```
┌──────────────────────────────────────────────────────────────┐
│                    文件操作请求流程                            │
└──────────────────────────────────────────────────────────────┘

用户打开文件 ~/Downloads/file.pdf
         │
         ▼
┌─────────────────┐
│ ES_EVENT_AUTH_  │
│     OPEN        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ 检查文件位置     │────▶│ 不在监控目录内   │──▶ ES_AUTH_RESULT_ALLOW
└────────┬────────┘     └─────────────────┘
         │ 在监控目录内
         ▼
┌─────────────────┐
│ 查询 ObjectBox  │
│ 获取文件状态     │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌───────┐  ┌───────┐
│LOCAL有│  │LOCAL无│
└───┬───┘  └───┬───┘
    │          │
    ▼          ▼
┌───────┐  ┌─────────────────┐
│直接放行│  │检查 EXTERNAL     │
└───────┘  └────────┬────────┘
                    │
              ┌─────┴─────┐
              ▼           ▼
         ┌───────┐   ┌───────┐
         │已连接  │   │未连接  │
         └───┬───┘   └───┬───┘
             │           │
             ▼           ▼
      ┌──────────┐  ┌──────────┐
      │从EXTERNAL │  │返回错误   │
      │拉取到LOCAL│  │ENOENT    │
      └──────────┘  └──────────┘
```

### 2.2 读取路由器 (ReadRouter)

#### 2.2.1 职责

- 拦截文件读取请求
- 确定数据来源 (LOCAL / EXTERNAL)
- 必要时从 EXTERNAL 拉取到 LOCAL
- 更新访问时间戳

#### 2.2.2 路由策略

```swift
enum ReadSource {
    case local           // 文件在 LOCAL，直接读取
    case external        // 文件仅在 EXTERNAL，需要拉取
    case notFound        // 文件不存在
    case offlineError    // 文件在 EXTERNAL 但硬盘离线
}

class ReadRouter {
    func resolveReadPath(_ virtualPath: String) -> ReadResult {
        let fileState = objectBox.getFileState(virtualPath)

        switch fileState.location {
        case .localOnly, .both:
            // 文件在 LOCAL，更新访问时间
            objectBox.updateAccessTime(virtualPath)
            return .success(localPath(virtualPath))

        case .externalOnly:
            if diskManager.isExternalConnected {
                // 从 EXTERNAL 拉取到 LOCAL
                let pullResult = pullToLocal(virtualPath)
                return pullResult
            } else {
                // 硬盘离线，返回错误
                return .failure(.offlineError)
            }

        case .notExists:
            return .failure(.notFound)
        }
    }
}
```

### 2.3 写入路由器 (WriteRouter)

#### 2.3.1 职责

- 拦截文件写入请求
- 实现 Write-Back 策略
- 管理脏数据队列
- 触发异步同步

#### 2.3.2 Write-Back 流程

```
┌──────────────────────────────────────────────────────────────┐
│                    Write-Back 写入流程                        │
└──────────────────────────────────────────────────────────────┘

写入请求: ~/Downloads/new_file.zip
         │
         ▼
┌─────────────────┐
│ 写入 LOCAL      │  ◀── 立即完成，返回成功
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 标记为 dirty    │
│ 记录到 ObjectBox│
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 加入同步队列     │
└────────┬────────┘
         │
         ▼ (异步)
┌─────────────────┐     ┌─────────────────┐
│ 检查 EXTERNAL   │────▶│ 未连接: 保持队列 │
│ 连接状态        │     └─────────────────┘
└────────┬────────┘
         │ 已连接
         ▼
┌─────────────────┐
│ rsync 同步到    │
│ EXTERNAL        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 清除 dirty 标记 │
│ 更新 ObjectBox  │
└─────────────────┘
```

#### 2.3.3 数据结构

```swift
struct DirtyFile {
    let virtualPath: String
    let localPath: String
    let createdAt: Date
    let modifiedAt: Date
    var syncAttempts: Int
    var lastSyncError: String?
}

class WriteRouter {
    private var dirtyQueue: [DirtyFile] = []
    private let syncDebounce: TimeInterval = 5.0

    func handleWrite(_ virtualPath: String, data: Data) -> Bool {
        // 1. 写入 LOCAL
        let localPath = localPathFor(virtualPath)
        guard FileManager.default.createFile(atPath: localPath, contents: data) else {
            return false
        }

        // 2. 记录到 ObjectBox
        let fileEntry = FileEntry(
            virtualPath: virtualPath,
            location: .localOnly,
            isDirty: true,
            modifiedAt: Date()
        )
        objectBox.put(fileEntry)

        // 3. 加入同步队列
        scheduleSyncDebounced()

        return true
    }
}
```

### 2.4 元数据管理器 (MetadataManager)

#### 2.4.1 职责

- 维护文件的完整元数据
- 提供快速的文件查询能力
- 管理文件的位置状态

#### 2.4.2 文件位置状态机

```
                    ┌─────────────┐
                    │  NOT_EXISTS │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │LOCAL_ONLY│ │EXTERNAL_ │ │  BOTH    │
        │          │ │  ONLY    │ │          │
        └────┬─────┘ └────┬─────┘ └────┬─────┘
             │            │            │
             │            │            │
             ▼            ▼            ▼
        ┌──────────────────────────────────┐
        │          状态转换规则             │
        ├──────────────────────────────────┤
        │ LOCAL_ONLY + 同步完成 → BOTH     │
        │ EXTERNAL_ONLY + 拉取 → BOTH      │
        │ BOTH + LOCAL淘汰 → EXTERNAL_ONLY │
        │ BOTH + EXTERNAL删除 → LOCAL_ONLY │
        │ 任意 + 双端删除 → NOT_EXISTS      │
        └──────────────────────────────────┘
```

---

## 3. LOCAL 缓存管理

### 3.1 缓存策略

#### 3.1.1 设计原则

- **最大空间限制**: 用户可配置 LOCAL 最大占用空间
- **基于修改时间淘汰**: 超出限制时，按修改时间排序，淘汰最旧的文件
- **写入双写**: 新写入的文件同时存在于 LOCAL (立即) 和 EXTERNAL (异步)

#### 3.1.2 淘汰算法

```swift
class CacheManager {
    private let maxCacheSize: Int64  // 用户配置的最大空间 (bytes)

    func enforceSpaceLimit() {
        let currentSize = calculateLocalCacheSize()

        guard currentSize > maxCacheSize else { return }

        // 获取所有可淘汰的文件 (非 dirty 且已同步到 EXTERNAL)
        let evictable = objectBox.query(FileEntry.self)
            .where { $0.location == .both && $0.isDirty == false }
            .orderBy(\.modifiedAt, ascending: true)  // 最旧的在前
            .find()

        var freedSpace: Int64 = 0
        let targetFree = currentSize - maxCacheSize + reserveBuffer

        for file in evictable {
            if freedSpace >= targetFree { break }

            // 删除 LOCAL 副本
            try? FileManager.default.removeItem(atPath: file.localPath)

            // 更新状态
            file.location = .externalOnly
            objectBox.put(file)

            freedSpace += file.size

            log("Evicted from LOCAL: \(file.virtualPath), freed \(file.size) bytes")
        }
    }
}
```

#### 3.1.3 配置参数

```swift
struct CacheConfig {
    /// LOCAL 缓存最大空间 (默认 10GB)
    var maxCacheSize: Int64 = 10 * 1024 * 1024 * 1024

    /// 预留缓冲空间 (默认 500MB)
    var reserveBuffer: Int64 = 500 * 1024 * 1024

    /// 淘汰检查间隔 (默认 5 分钟)
    var evictionCheckInterval: TimeInterval = 300

    /// 是否启用自动淘汰
    var autoEvictionEnabled: Bool = true
}
```

### 3.2 缓存目录结构

```
~/Library/Application Support/DMSA/
├── LocalCache/                    # LOCAL 缓存目录
│   ├── Downloads/                 # 映射 ~/Downloads
│   │   ├── file1.pdf
│   │   ├── file2.zip
│   │   └── ...
│   ├── Documents/                 # 映射 ~/Documents (如果配置)
│   │   └── ...
│   └── .metadata/                 # 元数据目录
│       └── checksums.json         # 文件校验和
│
├── Database/                      # ObjectBox 数据库
│   └── objectbox/
│       ├── data.mdb
│       └── lock.mdb
│
├── Logs/                          # 日志目录
│   ├── sync.log
│   └── error.log
│
└── config.json                    # 配置文件
```

---

## 4. ObjectBox 数据模型

### 4.1 实体定义

#### 4.1.1 FileEntry (文件索引)

```swift
// objectbox: entity
class FileEntry: Entity {
    var id: Id = 0

    /// 虚拟路径 (用户看到的路径)
    // objectbox: unique
    var virtualPath: String = ""

    /// LOCAL 实际路径
    var localPath: String?

    /// EXTERNAL 实际路径
    var externalPath: String?

    /// 文件位置状态
    var location: FileLocation = .notExists

    /// 是否为脏数据 (待同步)
    var isDirty: Bool = false

    /// 文件大小 (bytes)
    var size: Int64 = 0

    /// 文件类型 (UTI)
    var fileType: String = ""

    /// 创建时间
    var createdAt: Date = Date()

    /// 最后修改时间
    var modifiedAt: Date = Date()

    /// 最后访问时间
    var accessedAt: Date = Date()

    /// 文件校验和 (MD5/SHA256)
    var checksum: String?

    /// 所属同步对 ID
    var syncPairId: String = ""
}

enum FileLocation: Int {
    case notExists = 0
    case localOnly = 1
    case externalOnly = 2
    case both = 3
}
```

#### 4.1.2 SyncHistory (同步历史)

```swift
// objectbox: entity
class SyncHistory: Entity {
    var id: Id = 0

    /// 同步开始时间
    var startedAt: Date = Date()

    /// 同步结束时间
    var completedAt: Date?

    /// 同步方向
    var direction: SyncDirection = .localToExternal

    /// 同步状态
    var status: SyncStatus = .pending

    /// 同步的文件数
    var filesCount: Int = 0

    /// 同步的总大小
    var totalSize: Int64 = 0

    /// 新增文件数
    var addedCount: Int = 0

    /// 更新文件数
    var updatedCount: Int = 0

    /// 删除文件数
    var deletedCount: Int = 0

    /// 错误信息
    var errorMessage: String?

    /// 关联的硬盘 ID
    var diskId: String = ""

    /// 关联的同步对 ID
    var syncPairId: String = ""
}

enum SyncDirection: Int {
    case localToExternal = 0
    case externalToLocal = 1
    case bidirectional = 2
}

enum SyncStatus: Int {
    case pending = 0
    case inProgress = 1
    case completed = 2
    case failed = 3
    case cancelled = 4
}
```

#### 4.1.3 DiskConfig (硬盘配置)

```swift
// objectbox: entity
class DiskConfig: Entity {
    var id: Id = 0

    /// 唯一标识符 (UUID)
    // objectbox: unique
    var diskId: String = ""

    /// 硬盘名称
    var name: String = ""

    /// 挂载路径
    var mountPath: String = ""

    /// 优先级 (数字越小优先级越高)
    var priority: Int = 0

    /// 是否启用
    var isEnabled: Bool = true

    /// 上次连接时间
    var lastConnectedAt: Date?

    /// 硬盘总容量
    var totalSpace: Int64 = 0

    /// 硬盘可用空间
    var availableSpace: Int64 = 0
}
```

#### 4.1.4 SyncPairConfig (同步对配置)

```swift
// objectbox: entity
class SyncPairConfig: Entity {
    var id: Id = 0

    /// 唯一标识符 (UUID)
    // objectbox: unique
    var pairId: String = ""

    /// 关联的硬盘 ID
    var diskId: String = ""

    /// 本地路径
    var localPath: String = ""

    /// 外置硬盘相对路径
    var externalRelativePath: String = ""

    /// 同步方向
    var direction: SyncDirection = .localToExternal

    /// 是否创建符号链接
    var createSymlink: Bool = true

    /// 是否启用
    var isEnabled: Bool = true

    /// 排除规则 (JSON 数组)
    var excludePatterns: String = "[]"
}
```

#### 4.1.5 SyncStatistics (统计数据)

```swift
// objectbox: entity
class SyncStatistics: Entity {
    var id: Id = 0

    /// 统计日期 (YYYY-MM-DD)
    // objectbox: unique
    var date: String = ""

    /// 同步次数
    var syncCount: Int = 0

    /// 同步的文件总数
    var filesCount: Int = 0

    /// 同步的数据总量
    var totalSize: Int64 = 0

    /// 成功次数
    var successCount: Int = 0

    /// 失败次数
    var failureCount: Int = 0

    /// 平均同步时间 (秒)
    var averageDuration: Double = 0
}
```

### 4.2 索引设计

```swift
// FileEntry 索引
extension FileEntry {
    // objectbox: index
    static let virtualPathIndex = PropertyIndex(\.virtualPath)

    // objectbox: index
    static let locationIndex = PropertyIndex(\.location)

    // objectbox: index
    static let isDirtyIndex = PropertyIndex(\.isDirty)

    // objectbox: index
    static let modifiedAtIndex = PropertyIndex(\.modifiedAt)

    // objectbox: index
    static let syncPairIdIndex = PropertyIndex(\.syncPairId)
}
```

### 4.3 常用查询

```swift
class FileRepository {
    private let box: Box<FileEntry>

    /// 获取所有脏文件
    func getDirtyFiles() -> [FileEntry] {
        return try! box.query { $0.isDirty == true }
            .order(\.modifiedAt)
            .build()
            .find()
    }

    /// 获取可淘汰的文件 (按修改时间排序)
    func getEvictableFiles(limit: Int) -> [FileEntry] {
        return try! box.query {
            $0.location == .both && $0.isDirty == false
        }
        .order(\.modifiedAt, ascending: true)
        .build()
        .find(limit: limit)
    }

    /// 获取仅在 EXTERNAL 的文件
    func getExternalOnlyFiles(syncPairId: String) -> [FileEntry] {
        return try! box.query {
            $0.location == .externalOnly && $0.syncPairId == syncPairId
        }
        .build()
        .find()
    }

    /// 计算 LOCAL 缓存总大小
    func calculateLocalCacheSize() -> Int64 {
        let files = try! box.query {
            $0.location == .localOnly || $0.location == .both
        }
        .build()
        .find()

        return files.reduce(0) { $0 + $1.size }
    }
}
```

---

## 5. 同步引擎

### 5.1 同步调度器 (SyncScheduler)

```swift
class SyncScheduler {
    private let diskManager: DiskManager
    private let syncEngine: SyncEngine
    private var pendingTasks: [SyncTask] = []
    private var isRunning: Bool = false

    /// 调度同步任务
    func scheduleSyncTask(_ task: SyncTask) {
        pendingTasks.append(task)
        processNextTask()
    }

    /// 处理下一个任务
    private func processNextTask() {
        guard !isRunning, let task = pendingTasks.first else { return }
        pendingTasks.removeFirst()

        isRunning = true

        Task {
            do {
                try await syncEngine.execute(task)
                recordSuccess(task)
            } catch {
                recordFailure(task, error: error)
            }

            isRunning = false
            processNextTask()
        }
    }
}
```

### 5.2 增量同步算法

```
┌──────────────────────────────────────────────────────────────┐
│                    增量同步算法                               │
└──────────────────────────────────────────────────────────────┘

1. 构建源文件列表
   ├─ 扫描源目录
   ├─ 应用排除规则
   └─ 生成 {path, size, mtime, checksum} 列表

2. 构建目标文件列表
   ├─ 扫描目标目录 (如果在线)
   └─ 或从 ObjectBox 获取缓存的元数据

3. 差异计算
   ├─ 新增: 源有目标无
   ├─ 删除: 源无目标有 (如果配置了 --delete)
   ├─ 更新: 两边都有但 mtime 或 size 不同
   └─ 不变: 两边一致

4. 执行同步
   ├─ 新增文件: rsync 复制
   ├─ 更新文件: rsync 覆盖
   └─ 删除文件: 直接删除

5. 更新 ObjectBox
   └─ 同步完成后更新所有受影响文件的状态
```

### 5.3 rsync 封装

```swift
class RsyncWrapper {

    func sync(
        source: String,
        destination: String,
        options: RsyncOptions
    ) async throws -> RsyncResult {

        var arguments = ["-av"]

        // 增量同步
        if options.incremental {
            arguments.append("--checksum")
        }

        // 删除目标多余文件
        if options.deleteExtraneous {
            arguments.append("--delete")
        }

        // 排除规则
        for pattern in options.excludePatterns {
            arguments.append("--exclude=\(pattern)")
        }

        // 进度输出
        arguments.append("--progress")

        // 源和目标
        arguments.append(source.hasSuffix("/") ? source : source + "/")
        arguments.append(destination.hasSuffix("/") ? destination : destination + "/")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // 异步读取输出
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: RsyncResult(
                        success: true,
                        output: output,
                        filesTransferred: self.parseFilesCount(output),
                        bytesTransferred: self.parseBytesTransferred(output)
                    ))
                } else {
                    continuation.resume(throwing: SyncError.rsyncFailed(error))
                }
            }
        }
    }
}
```

---

## 6. Endpoint Security 实现

### 6.1 系统扩展结构

```
DMSA.app/
└── Contents/
    └── Library/
        └── SystemExtensions/
            └── com.ttttt.dmsa.extension.systemextension/
                └── Contents/
                    ├── Info.plist
                    └── MacOS/
                        └── com.ttttt.dmsa.extension
```

### 6.2 Extension 入口

```swift
import EndpointSecurity
import Foundation

@main
struct DMSAExtension {
    static func main() {
        var client: OpaquePointer?

        let result = es_new_client(&client) { client, message in
            handleSecurityEvent(client: client, message: message)
        }

        guard result == ES_NEW_CLIENT_RESULT_SUCCESS else {
            fatalError("Failed to create ES client: \(result)")
        }

        // 订阅事件
        let events: [es_event_type_t] = [
            ES_EVENT_TYPE_AUTH_OPEN,
            ES_EVENT_TYPE_AUTH_CREATE,
            ES_EVENT_TYPE_AUTH_UNLINK,
            ES_EVENT_TYPE_AUTH_RENAME,
            ES_EVENT_TYPE_NOTIFY_WRITE,
        ]

        es_subscribe(client!, events, UInt32(events.count))

        // 保持运行
        dispatchMain()
    }

    static func handleSecurityEvent(client: OpaquePointer, message: UnsafePointer<es_message_t>) {
        let msg = message.pointee

        // 检查是否是我们监控的路径
        guard isMonitoredPath(msg) else {
            if msg.action_type == ES_ACTION_TYPE_AUTH {
                es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
            }
            return
        }

        switch msg.event_type {
        case ES_EVENT_TYPE_AUTH_OPEN:
            handleAuthOpen(client: client, message: message)
        case ES_EVENT_TYPE_AUTH_CREATE:
            handleAuthCreate(client: client, message: message)
        case ES_EVENT_TYPE_NOTIFY_WRITE:
            handleNotifyWrite(message: message)
        // ... 其他事件
        default:
            if msg.action_type == ES_ACTION_TYPE_AUTH {
                es_respond_auth_result(client, message, ES_AUTH_RESULT_ALLOW, false)
            }
        }
    }
}
```

### 6.3 权限配置

**Info.plist (Extension):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ttttt.dmsa.extension</string>
    <key>CFBundlePackageType</key>
    <string>SYSX</string>
    <key>NSEndpointSecurityEarlyBoot</key>
    <false/>
    <key>NSEndpointSecurityRebootRequired</key>
    <false/>
</dict>
</plist>
```

**Entitlements:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.endpoint-security.client</key>
    <true/>
    <key>com.apple.developer.system-extension.install</key>
    <true/>
</dict>
</plist>
```

---

## 7. 模块依赖关系

```
┌─────────────────────────────────────────────────────────────────┐
│                        应用层                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │  AppDelegate │  │  MainMenu   │  │  Settings   │              │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        服务层                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ DiskManager │  │SyncScheduler│  │CacheManager │              │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
│         │                │                │                      │
│         └────────────────┼────────────────┘                      │
│                          ▼                                       │
│                   ┌─────────────┐                                │
│                   │ SyncEngine  │                                │
│                   └──────┬──────┘                                │
└──────────────────────────┼──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                        核心层                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ ReadRouter  │  │ WriteRouter │  │MetadataMgr  │              │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
│         │                │                │                      │
│         └────────────────┼────────────────┘                      │
│                          ▼                                       │
│                   ┌─────────────┐                                │
│                   │  VFSCore    │                                │
│                   └──────┬──────┘                                │
└──────────────────────────┼──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                        基础层                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │  ObjectBox  │  │RsyncWrapper │  │   Logger    │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                   System Extension                               │
│                   (Endpoint Security)                            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. 错误处理

### 8.1 错误类型定义

```swift
enum SyncError: Error, LocalizedError {
    case diskNotConnected(diskName: String)
    case fileNotFound(path: String)
    case permissionDenied(path: String)
    case insufficientSpace(required: Int64, available: Int64)
    case rsyncFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case symlinkCreationFailed(path: String, error: String)
    case objectBoxError(String)
    case configurationError(String)

    var errorDescription: String? {
        switch self {
        case .diskNotConnected(let name):
            return "外置硬盘 \(name) 未连接"
        case .fileNotFound(let path):
            return "文件不存在: \(path)"
        case .permissionDenied(let path):
            return "权限不足: \(path)"
        case .insufficientSpace(let required, let available):
            return "空间不足: 需要 \(formatBytes(required)), 可用 \(formatBytes(available))"
        case .rsyncFailed(let msg):
            return "同步失败: \(msg)"
        case .checksumMismatch(let expected, let actual):
            return "文件校验失败: 期望 \(expected), 实际 \(actual)"
        case .symlinkCreationFailed(let path, let error):
            return "创建符号链接失败 \(path): \(error)"
        case .objectBoxError(let msg):
            return "数据库错误: \(msg)"
        case .configurationError(let msg):
            return "配置错误: \(msg)"
        }
    }
}
```

### 8.2 恢复策略

| 错误类型 | 恢复策略 |
|----------|----------|
| 硬盘离线 | 将操作加入队列，硬盘重连后自动执行 |
| 空间不足 | 触发 LRU 淘汰，释放空间后重试 |
| rsync 失败 | 最多重试 3 次，间隔递增 |
| 校验失败 | 删除本地副本，重新从源拉取 |
| 数据库错误 | 尝试修复，失败则重建索引 |

---

## 9. 性能优化

### 9.1 批量操作

```swift
// 批量更新 ObjectBox
func batchUpdateFileStates(_ updates: [(String, FileLocation)]) {
    objectBox.runInTransaction {
        for (path, location) in updates {
            if let entry = box.get(path) {
                entry.location = location
                box.put(entry)
            }
        }
    }
}
```

### 9.2 异步 I/O

```swift
// 使用 DispatchIO 进行高效文件操作
func asyncReadFile(_ path: String) async throws -> Data {
    return try await withCheckedThrowingContinuation { continuation in
        let channel = DispatchIO(
            type: .stream,
            path: path,
            oflag: O_RDONLY,
            mode: 0,
            queue: .global()
        ) { error in
            if error != 0 {
                continuation.resume(throwing: POSIXError(POSIXErrorCode(rawValue: error)!))
            }
        }

        var data = Data()
        channel?.read(offset: 0, length: Int.max, queue: .global()) { done, chunk, error in
            if let chunk = chunk, !chunk.isEmpty {
                data.append(contentsOf: chunk)
            }
            if done {
                continuation.resume(returning: data)
            }
        }
    }
}
```

### 9.3 内存映射

```swift
// 大文件使用内存映射
func mmapFile(_ path: String) throws -> Data {
    let fd = open(path, O_RDONLY)
    guard fd >= 0 else { throw POSIXError(.ENOENT) }
    defer { close(fd) }

    var stat = stat()
    guard fstat(fd, &stat) == 0 else { throw POSIXError(.EIO) }

    let size = Int(stat.st_size)
    guard let ptr = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0),
          ptr != MAP_FAILED else {
        throw POSIXError(.ENOMEM)
    }

    return Data(bytesNoCopy: ptr, count: size, deallocator: .unmap)
}
```

---

## 10. 安全考虑

### 10.1 权限最小化

- 仅请求必要的系统权限
- 不存储用户密码或敏感信息
- 配置文件权限设置为 600

### 10.2 数据完整性

- 重要文件同步后进行 checksum 校验
- 事务性操作防止部分写入
- 崩溃恢复机制

### 10.3 隐私保护

- 日志中不记录文件内容
- 不上传任何用户数据
- 统计数据仅存储在本地

---

## 11. 测试策略

### 11.1 单元测试

| 模块 | 测试重点 |
|------|----------|
| ReadRouter | 路由逻辑、离线处理 |
| WriteRouter | Write-Back 逻辑、脏数据管理 |
| CacheManager | 淘汰算法、空间计算 |
| SyncEngine | 增量同步、冲突处理 |

### 11.2 集成测试

| 场景 | 测试内容 |
|------|----------|
| 硬盘热插拔 | 插入/拔出时的状态转换 |
| 大文件同步 | 1GB+ 文件的同步性能 |
| 并发写入 | 多进程同时写入同一目录 |
| 崩溃恢复 | 同步中断后的数据一致性 |

---

## 12. 附录

### 12.1 ObjectBox Swift 集成

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/objectbox/objectbox-swift", from: "1.9.0"),
]

// 生成模型代码
// 运行: Pods/ObjectBox/setup.rb
// 或使用 SPM: swift package objectbox-generate
```

### 12.2 Endpoint Security 开发要求

- macOS 10.15+
- Xcode 12+
- Apple Developer Program 会员资格
- System Extension 签名证书

### 12.3 参考文档

- [Endpoint Security Framework](https://developer.apple.com/documentation/endpointsecurity)
- [ObjectBox Swift](https://swift.objectbox.io/)
- [System Extensions](https://developer.apple.com/documentation/systemextensions)
- [rsync man page](https://download.samba.org/pub/rsync/rsync.1)

---

*文档维护: 技术变更时更新此文档*
