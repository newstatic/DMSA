# DMSA v4.3 架构清理执行计划

> 版本: 2.0 | 创建日期: 2026-01-24
> 基于: ARCHITECTURE_REVIEW.md 代码审查结果
> 核心原则: **UI 进程只是一个单纯的管理客户端 UI，不需要太多的功能**

---

## 目录

1. [执行概述](#1-执行概述)
2. [当前状态](#2-当前状态)
3. [目标状态](#3-目标状态)
4. [执行阶段](#4-执行阶段)
5. [详细步骤](#5-详细步骤)
6. [验收标准](#6-验收标准)
7. [回滚方案](#7-回滚方案)

---

## 1. 执行概述

### 1.1 背景

v4.1/v4.2 已建立统一服务架构 (DMSAService)，但 DMSAApp 仍保留大量业务逻辑代码：

- ~5000+ 行业务逻辑应迁移到 DMSAService
- ~8000 行代码应精简到 ~2000 行
- ~45 个文件应精简到 ~15 个

### 1.2 目标

| 维度 | 当前 | 目标 |
|------|------|------|
| **DMSAApp 代码量** | ~8000 行 | ~2000 行 |
| **DMSAApp 文件数** | ~45 个 | ~15 个 |
| **业务逻辑位置** | UI + Service 混合 | 全部在 Service |
| **App 退出影响** | 同步中断 | 无影响 |

### 1.3 执行顺序

```
Phase 1 (P0) ─► Phase 2 (P0) ─► Phase 3 (P1) ─► Phase 4 (P1) ─► Phase 5 (P2)
同步逻辑迁移    VFS 代码清理    数据管理迁移    监控迁移       AppDelegate 重构
```

---

## 2. 当前状态

### 2.1 DMSAApp 问题文件清单

| 文件 | 行数 | 问题 | 优先级 |
|------|------|------|--------|
| `Services/SyncEngine.swift` | 478 | 完整同步逻辑 | P0 |
| `Services/Sync/NativeSyncEngine.swift` | 500+ | 核心同步算法 | P0 |
| `Services/Sync/FileScanner.swift` | ~200 | 文件扫描 | P0 |
| `Services/Sync/FileHasher.swift` | ~150 | 文件哈希 | P0 |
| `Services/Sync/DiffEngine.swift` | ~180 | 差异计算 | P0 |
| `Services/Sync/FileCopier.swift` | ~200 | 文件复制 | P0 |
| `Services/Sync/ConflictResolver.swift` | ~150 | 冲突解决 | P0 |
| `Services/Sync/SyncStateManager.swift` | ~120 | 状态管理 | P0 |
| `Services/SyncScheduler.swift` | 237 | 任务队列 | P0 |
| `Services/VFS/VFSCore.swift` | 666 | FUSE 回调 (300+ 行) | P0 |
| `Services/DatabaseManager.swift` | ~400 | 数据库管理 | P1 |
| `Services/TreeVersionManager.swift` | 414 | 版本管理 Actor | P1 |
| `Services/FSEventsMonitor.swift` | ~300 | 文件监控 | P1 |
| `Services/DiskManager.swift` | ~250 | 磁盘监控核心逻辑 | P1 |
| `App/AppDelegate.swift` | ~500 | 业务逻辑 | P2 |

### 2.2 正确保留的文件

| 文件 | 用途 |
|------|------|
| `Services/ServiceClient.swift` | XPC 客户端 |
| `Services/ConfigManager.swift` | 配置管理 |
| `UI/MenuBarManager.swift` | 菜单栏 |
| `UI/AlertManager.swift` | 通知显示 |
| `UI/Views/*` | 所有视图 |
| `Utils/Constants.swift` | 常量 |
| `Utils/Logger.swift` | 日志 |

---

## 3. 目标状态

### 3.1 DMSAApp 最终结构

```
DMSAApp/
├── App/
│   └── AppDelegate.swift        # 仅生命周期管理 (~100 行)
├── Services/
│   ├── ServiceClient.swift      # XPC 客户端 (唯一服务文件)
│   └── ConfigManager.swift      # 配置管理
├── UI/
│   ├── MenuBarManager.swift     # 菜单栏
│   ├── AlertManager.swift       # 通知
│   └── Views/                   # 所有视图
└── Utils/
    ├── Constants.swift
    └── Logger.swift
```

### 3.2 DMSAService 最终结构

```
DMSAService/
├── main.swift
├── ServiceDelegate.swift
├── ServiceImplementation.swift
├── VFS/
│   ├── VFSManager.swift         # 已有
│   ├── FUSEFileSystem.swift     # 已有
│   ├── EvictionManager.swift    # 已有
│   ├── MergeEngine.swift        # 从 DMSAApp 迁移
│   ├── ReadRouter.swift         # 从 DMSAApp 迁移
│   ├── WriteRouter.swift        # 从 DMSAApp 迁移
│   └── LockManager.swift        # 从 DMSAApp 迁移
├── Sync/
│   ├── SyncManager.swift        # 扩展，整合同步逻辑
│   ├── SyncScheduler.swift      # 从 DMSAApp 迁移
│   ├── NativeSyncEngine.swift   # 从 DMSAApp 迁移
│   ├── FileScanner.swift        # 从 DMSAApp 迁移
│   ├── FileHasher.swift         # 从 DMSAApp 迁移
│   ├── DiffEngine.swift         # 从 DMSAApp 迁移
│   ├── FileCopier.swift         # 从 DMSAApp 迁移
│   ├── ConflictResolver.swift   # 从 DMSAApp 迁移
│   └── SyncStateManager.swift   # 从 DMSAApp 迁移
├── Data/
│   ├── DatabaseManager.swift    # 从 DMSAApp 迁移
│   └── TreeVersionManager.swift # 从 DMSAApp 迁移
├── Monitor/
│   ├── FSEventsMonitor.swift    # 从 DMSAApp 迁移
│   └── DiskMonitor.swift        # 从 DMSAApp 迁移核心逻辑
└── Privileged/
    └── PrivilegedOperations.swift # 已有
```

---

## 4. 执行阶段

### Phase 1: 同步逻辑迁移 (P0)

**目标:** 将所有同步相关代码迁移到 DMSAService

**涉及文件:**
- `SyncEngine.swift` → 删除，功能由 ServiceClient 代理
- `NativeSyncEngine.swift` → 迁移到 DMSAService/Sync/
- `FileScanner.swift` → 迁移到 DMSAService/Sync/
- `FileHasher.swift` → 迁移到 DMSAService/Sync/
- `DiffEngine.swift` → 迁移到 DMSAService/Sync/
- `FileCopier.swift` → 迁移到 DMSAService/Sync/
- `ConflictResolver.swift` → 迁移到 DMSAService/Sync/
- `SyncStateManager.swift` → 迁移到 DMSAService/Sync/
- `SyncScheduler.swift` → 迁移到 DMSAService/Sync/

**DMSAApp 保留接口:**
```swift
// ServiceClient.swift
func syncNow(syncPairId: String) async throws
func syncAll() async throws
func getSyncProgress(syncPairId: String) async -> SyncProgress?
func getSyncStatus(syncPairId: String) async -> SyncStatus
```

---

### Phase 2: VFS 代码清理 (P0)

**目标:** 删除 DMSAApp 中多余的 VFS 实现代码

**涉及文件:**
- `VFSCore.swift` → 删除 FUSE 回调 (行 280-579)，保留状态查询
- `MergeEngine.swift` → 迁移到 DMSAService/VFS/ (如未迁移)
- `ReadRouter.swift` → 迁移到 DMSAService/VFS/ (如未迁移)
- `WriteRouter.swift` → 迁移到 DMSAService/VFS/ (如未迁移)
- `LockManager.swift` → 迁移到 DMSAService/VFS/ (如未迁移)

**DMSAApp 保留接口:**
```swift
// ServiceClient.swift (已有)
func mountVFS(syncPairId: String, ...) async throws
func unmountVFS(syncPairId: String) async throws
func getVFSStatus(syncPairId: String) async -> VFSStatus?
```

---

### Phase 3: 数据管理迁移 (P1)

**目标:** 将数据库和版本管理迁移到 DMSAService

**涉及文件:**
- `DatabaseManager.swift` → 迁移到 DMSAService/Data/
- `TreeVersionManager.swift` → 迁移到 DMSAService/Data/

**DMSAApp 保留接口:**
```swift
// ServiceClient.swift 新增
func getFileEntry(virtualPath: String, syncPairId: String) async -> FileEntry?
func getSyncHistory(limit: Int) async -> [SyncHistory]
func getTreeVersion(syncPairId: String) async -> TreeVersion?
```

**XPC 协议新增:**
```swift
// DMSAServiceProtocol
func dataGetFileEntry(virtualPath: String, syncPairId: String, withReply: ...)
func dataGetSyncHistory(limit: Int, withReply: ...)
func dataGetTreeVersion(syncPairId: String, withReply: ...)
```

---

### Phase 4: 监控迁移 (P1)

**目标:** 将文件和磁盘监控迁移到 DMSAService

**涉及文件:**
- `FSEventsMonitor.swift` → 迁移到 DMSAService/Monitor/
- `DiskManager.swift` 核心逻辑 → 迁移到 DMSAService/Monitor/DiskMonitor.swift

**DMSAApp 保留:**
- `DiskManager.swift` 的 UI 通知功能 (精简为 ~50 行)

**XPC 协议新增:**
```swift
// DMSAServiceProtocol
func monitorStartFSEvents(paths: [String], withReply: ...)
func monitorStopFSEvents(withReply: ...)
func monitorGetDiskStatus(withReply: ...)
```

---

### Phase 5: AppDelegate 重构 (P2)

**目标:** 精简 AppDelegate，移除业务逻辑

**删除内容:**
- `performSyncForDisk()` → 改用 `serviceClient.syncNow()`
- `handleDiskConnected()` 核心逻辑 → 改为通知 Service
- `checkMacFUSE()` 安装逻辑 → 仅保留检测，安装引导

**保留内容:**
- 应用生命周期管理
- UI 窗口管理
- 菜单栏管理初始化

**目标代码量:** ~100-150 行

---

## 5. 详细步骤

### 5.1 Phase 1 详细步骤

#### Step 1.1: 创建 Sync 目录结构

```bash
mkdir -p DMSAApp/DMSAService/Sync
```

#### Step 1.2: 迁移 NativeSyncEngine.swift

1. 复制文件到 `DMSAService/Sync/`
2. 修改 import 语句
3. 添加到 Xcode DMSAService target
4. 从 DMSAApp target 移除

#### Step 1.3: 迁移辅助文件

重复 Step 1.2 对以下文件:
- FileScanner.swift
- FileHasher.swift
- DiffEngine.swift
- FileCopier.swift
- ConflictResolver.swift
- SyncStateManager.swift

#### Step 1.4: 迁移 SyncScheduler.swift

1. 复制到 `DMSAService/Sync/`
2. 更新 SyncManager 使用 SyncScheduler
3. 更新 ServiceImplementation 集成

#### Step 1.5: 更新 SyncManager

扩展 `DMSAService/Sync/SyncManager.swift`:
```swift
actor SyncManager {
    private let scheduler = SyncScheduler()
    private let engine: NativeSyncEngine

    // 整合所有同步功能
    func syncNow(syncPairId: String) async throws { ... }
    func scheduleSync(for path: String, syncPairId: String) { ... }
    // ...
}
```

#### Step 1.6: 删除 DMSAApp 中的 SyncEngine.swift

1. 更新所有引用，改用 ServiceClient
2. 从 Xcode 移除
3. 删除文件

#### Step 1.7: 验证

- [ ] DMSAService 编译成功
- [ ] 同步功能通过 XPC 正常工作
- [ ] DMSAApp 不再包含同步逻辑代码

---

### 5.2 Phase 2 详细步骤

#### Step 2.1: 检查 VFS 文件迁移状态

确认以下文件是否已在 DMSAService:
- MergeEngine.swift
- ReadRouter.swift
- WriteRouter.swift
- LockManager.swift

#### Step 2.2: 迁移缺失的 VFS 文件

对于不在 DMSAService 的文件，执行迁移。

#### Step 2.3: 清理 VFSCore.swift

1. 删除 FUSE 回调方法 (行 280-579)
2. 保留状态查询方法
3. 确保通过 XPC 调用 DMSAService

#### Step 2.4: 从 DMSAApp 移除冗余 VFS 文件

- DMSAFileSystem.swift (如存在)
- FUSEManager.swift 核心逻辑

#### Step 2.5: 验证

- [ ] VFS 挂载/卸载正常
- [ ] 文件读写正常
- [ ] DMSAApp VFS 代码 < 100 行

---

### 5.3 Phase 3 详细步骤

#### Step 3.1: 创建 Data 目录

```bash
mkdir -p DMSAApp/DMSAService/Data
```

#### Step 3.2: 迁移 DatabaseManager.swift

1. 复制到 `DMSAService/Data/`
2. 更新为 Service 单例模式
3. 添加到 Xcode target

#### Step 3.3: 迁移 TreeVersionManager.swift

1. 复制到 `DMSAService/Data/`
2. 更新为 Service Actor
3. 添加到 Xcode target

#### Step 3.4: 更新 XPC 协议

在 `DMSAServiceProtocol.swift` 添加数据访问方法。

#### Step 3.5: 更新 ServiceImplementation

实现新的数据访问 XPC 方法。

#### Step 3.6: 更新 ServiceClient

添加数据访问客户端方法。

#### Step 3.7: 删除 DMSAApp 中的数据管理文件

1. 更新所有引用
2. 从 Xcode 移除
3. 删除文件

#### Step 3.8: 验证

- [ ] 数据查询通过 XPC 正常工作
- [ ] DMSAApp 无本地数据库访问

---

### 5.4 Phase 4 详细步骤

#### Step 4.1: 创建 Monitor 目录

```bash
mkdir -p DMSAApp/DMSAService/Monitor
```

#### Step 4.2: 迁移 FSEventsMonitor.swift

1. 复制到 `DMSAService/Monitor/`
2. 更新触发逻辑，调用 SyncManager
3. 添加到 Xcode target

#### Step 4.3: 创建 DiskMonitor.swift

1. 从 DiskManager.swift 提取核心监控逻辑
2. 创建 `DMSAService/Monitor/DiskMonitor.swift`
3. 添加到 Xcode target

#### Step 4.4: 精简 DiskManager.swift

保留 UI 相关功能:
- 通知显示
- 状态图标更新
- 用户提示

#### Step 4.5: 更新 XPC 协议

添加监控相关 XPC 方法。

#### Step 4.6: 验证

- [ ] 文件监控在 Service 中运行
- [ ] 磁盘事件正确处理
- [ ] DMSAApp DiskManager < 100 行

---

### 5.5 Phase 5 详细步骤

#### Step 5.1: 分析 AppDelegate 当前内容

识别需要移除的业务逻辑。

#### Step 5.2: 删除业务逻辑方法

- `performSyncForDisk()`
- `handleDiskConnected()` 核心逻辑
- `checkMacFUSE()` 安装逻辑

#### Step 5.3: 重构保留功能

- 应用生命周期 (`applicationDidFinishLaunching`, `applicationWillTerminate`)
- 窗口管理
- 菜单栏初始化

#### Step 5.4: 验证

- [ ] AppDelegate < 150 行
- [ ] 应用启动/退出正常
- [ ] 所有 UI 功能正常

---

## 6. 验收标准

### 6.1 DMSAApp 验收

- [ ] 代码量 < 2500 行
- [ ] 文件数 < 20 个
- [ ] Services/ 目录仅含 ServiceClient.swift 和 ConfigManager.swift
- [ ] 退出 App 后同步继续运行
- [ ] 退出 App 后 VFS 挂载保持
- [ ] 重启 App 后状态正确恢复

### 6.2 DMSAService 验收

- [ ] 所有同步逻辑在服务中
- [ ] 所有 VFS 逻辑在服务中
- [ ] 所有数据管理在服务中
- [ ] 所有监控在服务中
- [ ] 崩溃后 launchd 自动重启
- [ ] XPC 接口覆盖所有功能

### 6.3 功能验收

- [ ] VFS 挂载/卸载正常
- [ ] 文件读写正常
- [ ] 同步触发和执行正常
- [ ] 硬盘连接/断开处理正常
- [ ] LRU 淘汰正常
- [ ] 配置保存/加载正常

---

## 7. 回滚方案

### 7.1 Git 标签策略

```bash
# 每个 Phase 完成后创建标签
git tag v4.3-phase1-sync-migrated
git tag v4.3-phase2-vfs-cleaned
git tag v4.3-phase3-data-migrated
git tag v4.3-phase4-monitor-migrated
git tag v4.3-phase5-appdelegate-refactored
git tag v4.4-architecture-clean
```

### 7.2 Phase 回滚

如果某 Phase 出现问题:

```bash
# 回滚到上一个 Phase
git checkout v4.3-phase{N-1}-xxx

# 重新编译
xcodebuild -scheme DMSAApp -configuration Release
```

### 7.3 完全回滚

```bash
# 回滚到清理前状态
git checkout v4.3

# 重新编译
xcodebuild -scheme DMSAApp -configuration Release
```

---

## 附录

### A. 文件迁移检查清单

| 文件 | 源位置 | 目标位置 | 状态 |
|------|--------|----------|------|
| NativeSyncEngine.swift | DMSAApp/Services/Sync/ | DMSAService/Sync/ | ⬜ |
| FileScanner.swift | DMSAApp/Services/Sync/ | DMSAService/Sync/ | ⬜ |
| FileHasher.swift | DMSAApp/Services/Sync/ | DMSAService/Sync/ | ⬜ |
| DiffEngine.swift | DMSAApp/Services/Sync/ | DMSAService/Sync/ | ⬜ |
| FileCopier.swift | DMSAApp/Services/Sync/ | DMSAService/Sync/ | ⬜ |
| ConflictResolver.swift | DMSAApp/Services/Sync/ | DMSAService/Sync/ | ⬜ |
| SyncStateManager.swift | DMSAApp/Services/Sync/ | DMSAService/Sync/ | ⬜ |
| SyncScheduler.swift | DMSAApp/Services/ | DMSAService/Sync/ | ⬜ |
| MergeEngine.swift | DMSAApp/Services/VFS/ | DMSAService/VFS/ | ⬜ |
| ReadRouter.swift | DMSAApp/Services/VFS/ | DMSAService/VFS/ | ⬜ |
| WriteRouter.swift | DMSAApp/Services/VFS/ | DMSAService/VFS/ | ⬜ |
| LockManager.swift | DMSAApp/Services/VFS/ | DMSAService/VFS/ | ⬜ |
| DatabaseManager.swift | DMSAApp/Services/ | DMSAService/Data/ | ⬜ |
| TreeVersionManager.swift | DMSAApp/Services/ | DMSAService/Data/ | ⬜ |
| FSEventsMonitor.swift | DMSAApp/Services/ | DMSAService/Monitor/ | ⬜ |

### B. XPC 协议扩展计划

```swift
// Phase 3 新增
func dataGetFileEntry(virtualPath: String, syncPairId: String,
                      withReply: @escaping (Data?) -> Void)
func dataGetSyncHistory(limit: Int,
                        withReply: @escaping (Data) -> Void)
func dataGetTreeVersion(syncPairId: String,
                        withReply: @escaping (Data?) -> Void)

// Phase 4 新增
func monitorStartFSEvents(paths: [String],
                          withReply: @escaping (Bool) -> Void)
func monitorStopFSEvents(withReply: @escaping (Bool) -> Void)
func monitorGetDiskStatus(withReply: @escaping (Data) -> Void)
```

### C. 参考文档

- [ARCHITECTURE_REVIEW.md](./ARCHITECTURE_REVIEW.md) - 代码审查报告
- [CLAUDE.md](./CLAUDE.md) - 项目记忆文档
- [VFS_DESIGN.md](./VFS_DESIGN.md) - VFS 设计文档

---

*文档版本: 2.0 | 创建日期: 2026-01-24 | 基于 v4.3 架构*
