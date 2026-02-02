# 服务端代码修改计划

> 基于 SERVICE_FLOW 文档对现有代码的审查结果
> 版本: 2.0 | 日期: 2026-01-27
>
> **实施状态**: 阶段 1 + 阶段 2 + 阶段 3 + 阶段 4 已全部完成 ✅

---

## 一、审查概述

### 1.1 审查范围

| 模块 | 现有文件 | 对应文档 |
|------|----------|----------|
| 服务状态 | ServiceConfigManager.swift | 01_服务状态定义.md |
| 配置管理 | ServiceConfigManager.swift | 02_配置管理.md |
| XPC 通信 | ServiceDelegate.swift, ServiceImplementation.swift | 04_XPC通信与通知.md |
| 状态管理 | (缺失) | 05_状态管理器.md |
| VFS | VFSManager.swift | 07_VFS预挂载机制.md |
| 索引 | VFSManager.swift (buildIndex) | 08_索引构建流程.md |
| 同步 | SyncManager.swift | 09_文件同步流程.md |
| 冲突 | ConflictResolver.swift | 10_冲突处理流程.md |
| 淘汰 | EvictionManager.swift | 11_热数据淘汰流程.md |
| 通知 | DistributedNotificationCenter | 14_分布式通知.md |
| 错误 | 各模块分散 | 15_错误处理.md |

### 1.2 审查结论

**总体评估**: 现有代码实现了核心功能，与 SERVICE_FLOW 文档设计的差距已大部分修复:

- ✅ **已完成**: ServiceStateManager (状态管理器) - `DMSAService/State/ServiceStateManager.swift`
- ✅ **已完成**: ServiceState 枚举 (全局服务状态) - `DMSAShared/Models/ServiceState.swift`
- ✅ **已完成**: ComponentState 枚举 (组件状态) - `DMSAShared/Models/ServiceState.swift`
- ✅ **已完成**: getFullState() XPC 接口 - `DMSAServiceProtocol.swift` + `ServiceImplementation.swift`
- ✅ **已完成**: 通知机制 (所有通知常量) - `Constants.swift`
- ✅ **已完成**: 错误码定义 - `DMSAShared/Models/ServiceError.swift`
- ✅ **已完成**: VFS 预挂载阻塞机制 (indexReady 标记) - `fuse_wrapper.c` + `VFSManager.swift`
- ✅ **已实现**: VFS 挂载/卸载
- ✅ **已实现**: 文件索引构建
- ✅ **已实现**: 同步引擎
- ✅ **已实现**: LRU 淘汰
- ✅ **已实现**: 冲突解决
- ✅ **已完成**: 配置冲突检测 (P3) - `ServiceConfigManager.swift`
- ✅ **已完成**: 启动检查清单 (P3) - `StartupChecker.swift`
- ✅ **已完成**: 日志格式标准化 (P3) - `Logger.swift`

---

## 二、高优先级修改项 (已完成 ✅)

### 2.1 新增 ServiceStateManager (P0 - 已完成 ✅)

**状态**: ✅ 已完成

**实现文件**: `DMSAService/State/ServiceStateManager.swift`

**问题**: 文档定义了完整的状态管理器，但代码中完全缺失。

**影响**:
- App 无法获取服务完整状态
- 无法追踪启动流程进度
- 组件错误无法聚合上报

**修改计划**:

```
新建文件: DMSAService/State/ServiceStateManager.swift
```

**实现内容**:
```swift
// 需要实现的结构
actor ServiceStateManager {
    static let shared = ServiceStateManager()

    private var globalState: ServiceState = .starting
    private var componentStates: [String: ComponentStateInfo] = [:]
    private var notificationQueue: NotificationQueue

    func setState(_ newState: ServiceState) async
    func setComponentState(_ component: String, state: ComponentState, error: ComponentError?) async
    func getFullState() -> ServiceFullState
    func waitForState(_ target: ServiceState) async
    func canPerform(_ operation: ServiceOperation) -> Bool
}
```

**依赖文件**:
- 新建 `DMSAShared/Models/ServiceState.swift` (ServiceState、ComponentState 枚举)
- 新建 `DMSAShared/Models/ServiceFullState.swift` (完整状态结构)

---

### 2.2 新增全局服务状态枚举 (P0 - 已完成 ✅)

**状态**: ✅ 已完成

**实现文件**: `DMSAShared/Models/ServiceState.swift`

**问题**: 文档定义了 7 种服务状态，代码中没有对应枚举。

**修改计划**:

```
新建文件: DMSAShared/Models/ServiceState.swift
```

**实现内容**:
```swift
public enum ServiceState: Int, Codable, Sendable {
    case starting       = 0  // 进程启动中
    case xpcReady       = 1  // XPC 监听就绪
    case vfsMounting    = 2  // FUSE 挂载进行中
    case vfsBlocked     = 3  // FUSE 已挂载，索引未就绪
    case indexing       = 4  // 正在构建索引
    case ready          = 5  // 索引完成，VFS 可正常访问
    case running        = 6  // 完全运行
    case shuttingDown   = 7  // 正在关闭
    case error          = 99 // 错误状态

    public var name: String { ... }
    public var allowsOperation: Bool { ... }
}

public enum ComponentState: Int, Codable, Sendable {
    case notStarted = 0
    case starting = 1
    case ready = 2
    case busy = 3
    case paused = 4
    case error = 99
}
```

---

### 2.3 新增 getFullState XPC 接口 (P0 - 已完成 ✅)

**状态**: ✅ 已完成

**实现文件**:
- `DMSAShared/Protocols/DMSAServiceProtocol.swift`
- `DMSAService/ServiceImplementation.swift`

**问题**: XPC 协议缺少 `getFullState()` 方法，App 无法获取完整服务状态。

**修改文件**: `DMSAShared/Protocols/DMSAServiceProtocol.swift`

**添加方法**:
```swift
/// 获取服务完整状态
func getFullState(withReply reply: @escaping (Data) -> Void)
```

**修改文件**: `DMSAService/ServiceImplementation.swift`

**添加实现**:
```swift
func getFullState(withReply reply: @escaping (Data) -> Void) {
    Task {
        let fullState = await ServiceStateManager.shared.getFullState()
        let data = try? JSONEncoder().encode(fullState)
        reply(data ?? Data())
    }
}
```

---

### 2.4 VFS 预挂载阻塞机制 (P1 - 已完成 ✅)

**状态**: ✅ 已完成

**实现文件**:
- `DMSAService/VFS/fuse_wrapper.h` - 添加 `fuse_wrapper_set_index_ready()` API
- `DMSAService/VFS/fuse_wrapper.c` - 实现 `index_ready` 标记，阻塞文件访问返回 EBUSY
- `DMSAService/VFS/FUSEFileSystem.swift` - 添加 `setIndexReady()` Swift 封装
- `DMSAService/VFS/VFSManager.swift` - 索引完成后调用 `setIndexReady(true)`

**问题**: 文档设计了 `indexReady` 标记和 `VFS_BLOCKED` 状态，但代码中 VFS 挂载后立即可访问。

**影响**: 用户可能在索引完成前访问 VFS，导致看不到 EXTERNAL 文件。

**修改文件**: `DMSAService/VFS/VFSManager.swift`

**修改点**:
1. 添加 `indexReady` 标记
2. 在 `buildIndex` 完成前，所有文件操作返回 `EBUSY`
3. 索引完成后设置 `indexReady = true` 并通知 App

**代码修改**:
```swift
actor VFSManager {
    // 新增
    private var indexReady: [String: Bool] = [:]  // [syncPairId: ready]

    func mount(...) async throws {
        // 现有挂载逻辑...

        // 新增: 初始化为未就绪
        indexReady[syncPairId] = false

        // 通知状态变更
        await ServiceStateManager.shared.setState(.vfsBlocked)

        // 构建索引 (异步)
        await buildIndex(for: syncPairId)

        // 新增: 标记索引就绪
        indexReady[syncPairId] = true
        await ServiceStateManager.shared.setState(.ready)
    }

    // 新增: 检查索引是否就绪
    func isIndexReady(syncPairId: String) -> Bool {
        return indexReady[syncPairId] ?? false
    }
}
```

**修改 FUSE 回调**:
```swift
// FUSEFileSystem.swift
func readdir(path: String, ...) -> Int32 {
    // 新增检查
    guard await vfsManager.isIndexReady(syncPairId) else {
        return -EBUSY  // 返回设备忙
    }
    // 现有逻辑...
}
```

---

## 三、中优先级修改项 (部分完成)

### 3.1 统一错误码定义 (P2 - 已完成 ✅)

**状态**: ✅ 已完成

**实现文件**: `DMSAShared/Models/ServiceError.swift`

**问题**: 错误码分散在各模块，没有统一定义。

**修改计划**:

```
新建文件: DMSAShared/Models/ServiceError.swift
```

**实现内容**:
```swift
public struct ServiceError: Codable, Sendable, Error {
    public let code: Int
    public let message: String
    public let component: String
    public let timestamp: Date
    public let recoverable: Bool
    public let context: [String: String]?

    // 预定义错误码
    public static let xpcListenFailed = ServiceError(code: 1001, ...)
    public static let xpcConnectionInvalid = ServiceError(code: 1002, ...)
    public static let configNotFound = ServiceError(code: 2001, ...)
    // ... 按文档 15_错误处理.md 定义
}
```

---

### 3.2 完善分布式通知 (P2 - 已完成 ✅)

**状态**: ✅ 已完成

**实现文件**: `DMSAShared/Utils/Constants.swift`

**问题**: 文档定义了 10 种通知类型，代码只实现了部分。

**现有通知**:
- ✅ `syncProgress`
- ✅ `syncCompleted`
- ✅ `syncStatusChanged`
- ✅ `fileWritten`

**现已实现的通知** (全部完成 ✅):
- ✅ `stateChanged` - 全局状态变更
- ✅ `xpcReady` - XPC 监听器启动
- ✅ `configStatus` - 配置加载/修补
- ✅ `configConflict` - 配置冲突
- ✅ `vfsMounted` - VFS 挂载完成
- ✅ `indexProgress` - 索引进度
- ✅ `indexReady` - 索引完成
- ✅ `serviceReady` - 服务完全就绪
- ✅ `serviceError` - 全局错误
- ✅ `componentError` - 组件错误

**修改文件**: `DMSAShared/Constants.swift`

**添加常量**:
```swift
public struct Notifications {
    // 现有
    public static let syncProgress = "com.ttttt.dmsa.syncProgress"
    public static let syncCompleted = "com.ttttt.dmsa.syncCompleted"
    public static let syncStatusChanged = "com.ttttt.dmsa.syncStatusChanged"
    public static let fileWritten = "com.ttttt.dmsa.fileWritten"

    // 新增
    public static let stateChanged = "com.ttttt.dmsa.stateChanged"
    public static let xpcReady = "com.ttttt.dmsa.xpcReady"
    public static let configStatus = "com.ttttt.dmsa.configStatus"
    public static let configConflict = "com.ttttt.dmsa.configConflict"
    public static let vfsMounted = "com.ttttt.dmsa.vfsMounted"
    public static let indexProgress = "com.ttttt.dmsa.indexProgress"
    public static let indexReady = "com.ttttt.dmsa.indexReady"
    public static let serviceReady = "com.ttttt.dmsa.serviceReady"
    public static let serviceError = "com.ttttt.dmsa.serviceError"
    public static let componentError = "com.ttttt.dmsa.componentError"
}
```

---

### 3.3 索引进度通知 (P2)

**问题**: 索引构建过程没有进度通知。

**修改文件**: `DMSAService/VFS/VFSManager.swift`

**修改 buildIndex 方法**:
```swift
private func buildIndex(for syncPairId: String) async {
    // 通知开始
    await ServiceStateManager.shared.setState(.indexing)
    sendIndexProgress(syncPairId: syncPairId, phase: "scanning", progress: 0)

    // 扫描 LOCAL_DIR
    sendIndexProgress(syncPairId: syncPairId, phase: "scanning_local", progress: 0.3)
    // ... 现有扫描逻辑

    // 扫描 EXTERNAL_DIR
    sendIndexProgress(syncPairId: syncPairId, phase: "scanning_external", progress: 0.6)
    // ... 现有扫描逻辑

    // 合并保存
    sendIndexProgress(syncPairId: syncPairId, phase: "merging", progress: 0.9)
    // ... 现有保存逻辑

    // 完成
    sendIndexProgress(syncPairId: syncPairId, phase: "completed", progress: 1.0)

    // 发送 indexReady 通知
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name(Constants.Notifications.indexReady),
        object: syncPairId,
        userInfo: nil,
        deliverImmediately: true
    )
}

private func sendIndexProgress(syncPairId: String, phase: String, progress: Double) {
    let info: [String: Any] = [
        "syncPairId": syncPairId,
        "phase": phase,
        "progress": progress
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: info),
          let json = String(data: data, encoding: .utf8) else { return }

    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name(Constants.Notifications.indexProgress),
        object: json,
        userInfo: nil,
        deliverImmediately: true
    )
}
```

---

## 四、低优先级修改项

### 4.1 配置冲突检测 (P3) ✅ 已完成

**状态**: ✅ 已完成

**实现文件**: `DMSAService/Data/ServiceConfigManager.swift`

**实现内容**:
- 添加 `detectConflicts(appConfig:)` 方法
- 实现 4 种冲突检测:
  1. `MULTIPLE_EXTERNAL_DIRS` - 多个 syncPair 使用同一 EXTERNAL_DIR
  2. `OVERLAPPING_LOCAL` - LOCAL_DIR 有重叠
  3. `DISK_NOT_FOUND` - 引用的 disk 不存在
  4. `CIRCULAR_SYNC` - 循环同步检测
- 添加 `validateConfig(appConfig:)` 方法，自动设置 ConfigStatus

---

### 4.2 启动检查清单 (P3) ✅ 已完成

**状态**: ✅ 已完成

**实现文件**: `DMSAService/Utils/StartupChecker.swift`

**实现内容**:
- 创建 `StartupChecker` 结构体
- 实现预启动检查 `runPreflightChecks()`:
  1. ✅ 进程以 root 权限运行
  2. ✅ 环境变量已设置
  3. ✅ macFUSE 加载成功
  4. ✅ 日志目录可写
  5. ✅ 配置目录存在
- 实现运行时检查方法:
  6. `checkXPCListener()` - XPC 监听器启动
  7. `checkConfigLoaded()` - 配置加载成功
  8. `checkFUSEMount()` - FUSE 挂载成功
  9. `checkBackendProtection()` - 后端目录保护成功
  10. `checkIndexBuild()` - 索引构建成功
  11. `checkScheduler()` - 调度器启动成功
  12. `checkNotificationQueue()` - 缓存通知已发送
- 在 `main.swift` 集成预启动检查

---

### 4.3 日志格式标准化 (P3) ✅ 已完成

**状态**: ✅ 已完成

**实现文件**: `DMSAShared/Utils/Logger.swift`

**实现内容**:
- 添加 `globalStateProvider` 静态属性
- 添加 `componentState` 实例属性
- 实现标准格式输出:
  ```
  [时间戳] [级别] [全局状态] [组件] [组件状态] 消息
  ```
- Service 端自动使用标准格式，App 端保持旧格式
- 在 `main.swift` 添加 `LoggerStateCache` 用于状态同步
- 在 `ServiceStateManager` 中更新日志状态缓存

---

## 五、文件修改清单

### 5.1 新建文件 (6 个)

| 文件 | 用途 | 优先级 | 状态 |
|------|------|--------|------|
| `DMSAShared/Models/ServiceState.swift` | 服务状态枚举 | P0 | ✅ 已完成 |
| `DMSAShared/Models/ServiceFullState.swift` | 完整状态结构 | P0 | ✅ 已完成 |
| `DMSAShared/Models/ServiceError.swift` | 统一错误码 | P2 | ✅ 已完成 |
| `DMSAService/State/ServiceStateManager.swift` | 状态管理器 | P0 | ✅ 已完成 |
| `DMSAService/State/NotificationQueue.swift` | 通知队列 | P2 | ✅ 已合并到 ServiceStateManager.swift |
| `DMSAService/Utils/StartupChecker.swift` | 启动检查 | P3 | ✅ 已完成 |

### 5.2 修改文件 (10 个)

| 文件 | 修改内容 | 优先级 | 状态 |
|------|----------|--------|------|
| `DMSAShared/Protocols/DMSAServiceProtocol.swift` | 添加 getFullState | P0 | ✅ 已完成 |
| `DMSAShared/Utils/Constants.swift` | 添加通知常量 | P2 | ✅ 已完成 |
| `DMSAService/ServiceImplementation.swift` | 实现 getFullState | P0 | ✅ 已完成 |
| `DMSAService/ServiceDelegate.swift` | 状态变更通知 | P1 | ✅ 已完成 (通过 ServiceStateManager) |
| `DMSAService/VFS/VFSManager.swift` | indexReady + 进度通知 | P1 | ✅ 已完成 |
| `DMSAService/VFS/FUSEFileSystem.swift` | setIndexReady 封装 | P1 | ✅ 已完成 |
| `DMSAService/VFS/fuse_wrapper.h` | index_ready API | P1 | ✅ 已完成 |
| `DMSAService/VFS/fuse_wrapper.c` | index_ready 实现 | P1 | ✅ 已完成 |
| `DMSAService/main.swift` | 启动检查 + 日志状态 | P3 | ✅ 已完成 |
| `DMSAService/Data/ServiceConfigManager.swift` | 冲突检测 | P3 | ✅ 已完成 |
| `DMSAShared/Utils/Logger.swift` | 标准格式日志 | P3 | ✅ 已完成 |

---

## 六、实施计划

### 阶段 1: 核心状态管理 (P0) ✅ 已完成

**目标**: 实现状态管理器和 getFullState 接口

**任务**:
1. ✅ 新建 ServiceState.swift
2. ✅ 新建 ServiceFullState.swift
3. ✅ 新建 ServiceStateManager.swift
4. ✅ 修改 DMSAServiceProtocol.swift
5. ✅ 修改 ServiceImplementation.swift

**验收标准**:
- ✅ App 可通过 XPC 调用 getFullState()
- ✅ 返回完整的服务状态信息

---

### 阶段 2: VFS 阻塞机制 (P1) ✅ 已完成

**目标**: 实现索引未就绪时的访问阻塞

**任务**:
1. ✅ fuse_wrapper.c 添加 index_ready 标记
2. ✅ FUSE 回调检查 index_ready，返回 EBUSY
3. ✅ VFSManager 索引完成后调用 setIndexReady(true)
4. ✅ 状态转换: INDEXING → READY

**验收标准**:
- ✅ 挂载后、索引完成前，访问 VFS 返回 EBUSY
- ✅ 索引完成后，VFS 正常访问

---

### 阶段 3: 通知完善 (P2) ✅ 已完成

**目标**: 实现所有分布式通知

**任务**:
1. ✅ 添加通知常量 (Constants.swift)
2. ✅ ServiceStateManager 发送对应通知
3. ✅ NotificationQueue 实现启动时缓存

**验收标准**:
- ✅ App 可接收所有通知类型
- ✅ 通知包含正确的数据

---

### 阶段 4: 错误处理 + P3 任务 ✅ 已完成

**目标**: 统一错误码，完善错误处理，实现 P3 优化项

**任务**:
1. ✅ 新建 ServiceError.swift (DMSAServiceError)
2. ✅ 启动检查清单 (StartupChecker.swift)
3. ✅ 配置冲突检测 (ServiceConfigManager.swift)
4. ✅ 日志格式标准化 (Logger.swift)

**验收标准**:
- ✅ 错误码符合文档定义
- ✅ 启动时执行预启动检查
- ✅ 配置加载时检测冲突
- ✅ Service 日志使用标准格式

---

## 七、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 状态管理器引入复杂度 | 可能影响性能 | 使用 actor 保证线程安全 |
| EBUSY 阻塞用户体验 | 用户困惑 | App 显示"正在准备..."提示 |
| 通知过多影响性能 | 系统资源消耗 | 通知节流 + 合并 |
| 兼容性问题 | 旧版 App 不兼容 | 版本协商 + 向后兼容 |

---

## 八、实施记录

### 2026-01-27 实施完成

**完成项**:
1. **ServiceState.swift** - 全局服务状态枚举 (9 种状态)
2. **ServiceFullState.swift** - 完整状态结构 (含 ConfigStatus, IndexProgress 等)
3. **ServiceStateManager.swift** - 状态管理器 actor + NotificationQueue
4. **ServiceError.swift** - 统一错误码 (1xxx-6xxx)
5. **DMSAServiceProtocol.swift** - 添加 getFullState(), getGlobalState(), canPerformOperation()
6. **ServiceImplementation.swift** - 实现新增 XPC 方法
7. **Constants.swift** - 添加所有通知常量
8. **fuse_wrapper.h/c** - 添加 index_ready 标记和 EBUSY 阻塞机制
9. **FUSEFileSystem.swift** - 添加 setIndexReady() Swift 封装
10. **VFSManager.swift** - 索引完成后开放 VFS 访问

**技术要点**:
- 使用 Swift actor 保证线程安全
- FUSE 层使用 C 实现，通过 pthread_mutex 保护状态
- 通知队列在 XPC 就绪前缓存通知，避免丢失
- VFS 预挂载阻塞: 挂载后 index_ready=false，getattr/readdir/open 返回 EBUSY

### 2026-01-27 P3 任务完成

**完成项**:
1. **StartupChecker.swift** - 启动检查清单
   - 12 项检查 (5 项预启动 + 7 项运行时)
   - 区分严重错误和可恢复错误
   - 在 main.swift 集成预启动检查

2. **ServiceConfigManager.swift** - 配置冲突检测
   - 4 种冲突类型检测
   - validateConfig() 自动设置 ConfigStatus

3. **Logger.swift** - 日志格式标准化
   - 标准格式: `[时间戳] [级别] [全局状态] [组件] [组件状态] 消息`
   - Service 自动使用标准格式
   - LoggerStateCache 状态同步机制

**所有修改计划已完成** ✅

---

*文档版本: 3.0 | 最后更新: 2026-01-27*
