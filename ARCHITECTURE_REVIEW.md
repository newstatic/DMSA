# DMSA 架构审查报告

> 审查日期: 2026-01-24
> 版本: v4.3
> 核心原则: **UI 进程只是一个单纯的管理客户端 UI，不需要太多的功能**

---

## 一、架构目标

```
┌─────────────────────────────────────────────────────────────────────┐
│                         理想架构                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  DMSAApp (UI)                    DMSAService (Backend)              │
│  ┌──────────────────┐            ┌──────────────────────────┐       │
│  │ • 状态显示        │            │ • VFS 挂载/卸载           │       │
│  │ • 设置界面        │   XPC      │ • 同步调度和执行          │       │
│  │ • 通知展示        │ ◄────────► │ • LRU 淘汰               │       │
│  │ • 用户交互        │            │ • 文件监控 (FSEvents)     │       │
│  │                  │            │ • 磁盘事件处理            │       │
│  │ 用户权限          │            │ • 数据库管理              │       │
│  └──────────────────┘            │ • 特权操作               │       │
│                                  │                          │       │
│                                  │ root 权限 (LaunchDaemon) │       │
│                                  └──────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────┘
```

**核心原则:**
- UI 进程退出不影响核心功能
- 同步和挂载在后台持续运行
- UI 仅作为状态查看和配置管理的窗口

---

## 二、当前问题摘要

| 问题 | 影响 | 严重程度 |
|------|------|----------|
| DMSAApp 包含 5000+ 行业务逻辑 | 违反架构原则 | 🔴 严重 |
| 同步逻辑在 UI 进程 | App 退出同步中断 | 🔴 严重 |
| VFS 回调在 UI 进程 | 仅部分迁移 | 🟡 中等 |
| 数据库在 UI 进程 | 状态不持久 | 🔴 严重 |
| 文件监控在 UI 进程 | 后台无法检测变更 | 🟡 中等 |

---

## 三、详细代码审查

### 3.1 严重问题 (必须迁移)

#### ❌ SyncEngine.swift (DMSAApp/Services/)
**行数:** 478 行
**问题:** 完整的同步逻辑在 UI 进程

```swift
// 违规代码示例 (行 123-168)
func execute() async throws {
    // 完整的同步执行逻辑
    // 应该通过 XPC 调用 DMSAService
}
```

**应该:**
```swift
// 正确做法: 通过 XPC 调用
func execute() async throws {
    try await serviceClient.syncNow(syncPairId: syncPair.id)
}
```

---

#### ❌ NativeSyncEngine.swift (DMSAApp/Services/Sync/)
**行数:** 500+ 行
**问题:** 核心同步算法 (扫描、哈希、差异、复制、冲突解决)

**违规内容:**
- FileScanner.swift - 文件扫描
- FileHasher.swift - 文件哈希
- DiffEngine.swift - 差异计算
- FileCopier.swift - 文件复制
- ConflictResolver.swift - 冲突解决
- SyncStateManager.swift - 状态管理

**结论:** 整个 `Sync/` 目录应迁移到 DMSAService

---

#### ❌ VFSCore.swift (DMSAApp/Services/VFS/)
**行数:** 666 行
**问题:** 300+ 行 FUSE 回调实现

```swift
// 违规代码 (行 280-579)
func fuseGetattr(_ path: String, syncPairId: UUID) async -> ...
func fuseReaddir(_ path: String, syncPairId: UUID) async -> ...
func fuseOpen(_ path: String, flags: Int32, syncPairId: UUID) async -> ...
func fuseWrite(_ path: String, ...) async -> ...
// ... 更多 FUSE 回调
```

**注意:** 虽然 v4.2 已将 FUSE 挂载迁移到 DMSAService，但 VFSCore.swift 仍保留大量 FUSE 回调代码

---

#### ❌ DatabaseManager.swift (DMSAApp/Services/)
**问题:** 内存缓存在 App 退出时丢失

```swift
// 违规代码 (行 19-22)
private var fileEntryCache: [String: FileEntry] = [:]
private var syncHistoryCache: [SyncHistory] = []
// App 退出时这些都会丢失
```

**影响:** 文件跟踪状态在 App 重启后不一致

---

#### ❌ SyncScheduler.swift (DMSAApp/Services/)
**行数:** 237 行
**问题:** 任务队列和定时器在 UI 进程

```swift
// 违规代码 (行 12-50)
private var pendingTasks: [SyncTask] = []
private var debounceTimer: Task<Void, Never>?

// 违规代码 (行 178-202)
func startPeriodicSync(interval: TimeInterval) {
    // 定时同步 - App 退出后停止
}
```

**影响:**
- 队列任务在 App 退出时丢失
- 定时同步仅在 App 运行时有效

---

#### ❌ TreeVersionManager.swift (DMSAApp/Services/)
**行数:** 414 行
**问题:** Actor 定义在 UI 进程

```swift
// 当前位置: DMSAApp
actor TreeVersionManager {
    static let shared = TreeVersionManager()
    // ...
}
```

**应该:** 迁移到 DMSAService，通过 XPC 调用

---

### 3.2 中等问题 (应该迁移)

#### ⚠️ FSEventsMonitor.swift
**问题:** 文件系统监控在 UI 进程
**影响:** App 不运行时无法检测文件变更

---

#### ⚠️ DiskManager.swift
**问题:** 磁盘挂载/卸载监控在 UI 进程
**影响:** App 不运行时无法响应磁盘事件

---

#### ⚠️ AppDelegate.swift
**问题:** 包含大量业务逻辑

```swift
// 违规代码示例
func performSyncForDisk(_ diskId: String) async {
    // 直接执行同步逻辑
    // 应该只调用 serviceClient.syncNow()
}

func handleDiskConnected(_ diskId: String) async {
    // 磁盘事件处理
    // 应该由 DMSAService 处理
}
```

---

### 3.3 正确的代码 (应该保留在 DMSAApp)

| 文件 | 用途 | 状态 |
|------|------|------|
| ServiceClient.swift | XPC 客户端 | ✅ 正确 |
| MenuBarManager.swift | 菜单栏 UI | ✅ 正确 |
| AlertManager.swift | 通知显示 | ✅ 正确 |
| AppearanceManager.swift | 主题管理 | ✅ 正确 |
| LaunchAtLoginManager.swift | 开机启动 | ✅ 正确 |
| UI/Views/* | 所有视图 | ✅ 正确 |
| ConfigManager.swift | 配置管理 | ✅ 正确 |

---

## 四、迁移计划

### Phase 1: 同步逻辑迁移 (优先级: P0)

| 源文件 (DMSAApp) | 目标 (DMSAService) | 操作 |
|------------------|-------------------|------|
| SyncEngine.swift | 删除，使用 ServiceClient | 重构 |
| NativeSyncEngine.swift | DMSAService/Sync/ | 迁移 |
| Sync/FileScanner.swift | DMSAService/Sync/ | 迁移 |
| Sync/FileHasher.swift | DMSAService/Sync/ | 迁移 |
| Sync/DiffEngine.swift | DMSAService/Sync/ | 迁移 |
| Sync/FileCopier.swift | DMSAService/Sync/ | 迁移 |
| Sync/ConflictResolver.swift | DMSAService/Sync/ | 迁移 |
| Sync/SyncStateManager.swift | DMSAService/Sync/ | 迁移 |
| SyncScheduler.swift | DMSAService/Sync/ | 迁移 |

**DMSAApp 保留:**
```swift
// ServiceClient.swift - 只需调用 XPC
func syncNow(syncPairId: String) async throws
func syncAll() async throws
func getSyncProgress(syncPairId: String) async -> SyncProgress?
```

---

### Phase 2: VFS 逻辑清理 (优先级: P0)

| 操作 | 说明 |
|------|------|
| 删除 VFSCore.swift 中的 FUSE 回调 | 行 280-579 |
| 保留 VFSCore 的状态查询功能 | 通过 XPC |
| 删除 MergeEngine.swift | 已在 DMSAService |
| 删除 ReadRouter.swift | 已在 DMSAService |
| 删除 WriteRouter.swift | 已在 DMSAService |
| 删除 LockManager.swift | 已在 DMSAService |

---

### Phase 3: 数据管理迁移 (优先级: P1)

| 源文件 (DMSAApp) | 目标 | 操作 |
|------------------|------|------|
| DatabaseManager.swift | DMSAService | 迁移 |
| TreeVersionManager.swift | DMSAService | 迁移 |

**DMSAApp 保留:**
```swift
// 通过 XPC 获取数据
func getFileEntry(virtualPath: String) async -> FileEntry?
func getSyncHistory(limit: Int) async -> [SyncHistory]
```

---

### Phase 4: 监控迁移 (优先级: P1)

| 源文件 (DMSAApp) | 目标 | 操作 |
|------------------|------|------|
| FSEventsMonitor.swift | DMSAService | 迁移 |
| DiskManager.swift 核心逻辑 | DMSAService | 迁移 |

**DMSAApp 保留:**
- DiskManager 的 UI 通知功能

---

### Phase 5: AppDelegate 重构 (优先级: P2)

**删除:**
- `performSyncForDisk()` - 改用 `serviceClient.syncNow()`
- `handleDiskConnected()` 核心逻辑 - 改为通知 Service
- `checkMacFUSE()` 安装逻辑 - 仅保留检测

**保留:**
- 应用生命周期管理
- UI 窗口管理
- 菜单栏管理

---

## 五、目标架构

### DMSAApp 最终结构

```
DMSAApp/
├── App/
│   └── AppDelegate.swift        # 仅生命周期管理
├── Services/
│   ├── ServiceClient.swift      # XPC 客户端 (唯一)
│   └── ConfigManager.swift      # 配置管理
├── UI/
│   ├── MenuBarManager.swift     # 菜单栏
│   └── Views/                   # 所有视图
└── Utils/
    ├── Constants.swift
    ├── Logger.swift
    └── Errors.swift
```

**文件数:** ~15 个核心文件 (当前 ~45 个)
**代码量:** ~2000 行 (当前 ~8000 行)

---

### DMSAService 最终结构

```
DMSAService/
├── main.swift
├── ServiceDelegate.swift
├── ServiceImplementation.swift
├── VFS/
│   ├── VFSManager.swift
│   ├── FUSEFileSystem.swift
│   ├── EvictionManager.swift
│   ├── MergeEngine.swift
│   ├── ReadRouter.swift
│   ├── WriteRouter.swift
│   └── LockManager.swift
├── Sync/
│   ├── SyncManager.swift
│   ├── SyncScheduler.swift
│   ├── NativeSyncEngine.swift
│   ├── FileScanner.swift
│   ├── FileHasher.swift
│   ├── DiffEngine.swift
│   ├── FileCopier.swift
│   ├── ConflictResolver.swift
│   └── SyncStateManager.swift
├── Data/
│   ├── DatabaseManager.swift
│   └── TreeVersionManager.swift
├── Monitor/
│   ├── FSEventsMonitor.swift
│   └── DiskMonitor.swift
├── Privileged/
│   └── PrivilegedOperations.swift
└── Resources/
    └── *.plist
```

---

## 六、迁移优先级

| 优先级 | 任务 | 预估工作量 | 影响 |
|--------|------|-----------|------|
| **P0** | 同步逻辑迁移 | 2-3 天 | 后台同步可用 |
| **P0** | VFS 代码清理 | 1 天 | 代码简洁 |
| **P1** | 数据管理迁移 | 1-2 天 | 状态持久 |
| **P1** | 监控迁移 | 1-2 天 | 后台监控 |
| **P2** | AppDelegate 重构 | 1 天 | 代码整洁 |

**总计:** 6-9 天工作量

---

## 七、验收标准

### UI 进程 (DMSAApp)

- [ ] 退出 App 后同步继续运行
- [ ] 退出 App 后 VFS 挂载保持
- [ ] 退出 App 后文件监控继续
- [ ] 重启 App 后状态正确恢复
- [ ] 代码量 < 2500 行
- [ ] Services/ 目录仅含 ServiceClient

### 服务进程 (DMSAService)

- [ ] 所有同步逻辑在服务中
- [ ] 所有 VFS 逻辑在服务中
- [ ] 所有数据管理在服务中
- [ ] 所有监控在服务中
- [ ] 崩溃后 launchd 自动重启

---

## 八、总结

当前 DMSAApp 包含大量应该在 DMSAService 的业务逻辑，违反了 "UI 进程只是一个单纯的管理客户端 UI" 的核心原则。

**关键问题:**
1. 同步逻辑在 UI 进程 - App 退出同步中断
2. 数据库在 UI 进程 - 状态不持久
3. 监控在 UI 进程 - 后台无法工作

**建议:** 按优先级分 Phase 迁移，确保每个 Phase 完成后系统可用。

---

*文档维护: 每次架构变更后更新*
