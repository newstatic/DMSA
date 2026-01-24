# DMSA 会话详细记录归档

> 此文档存放详细的会话记录，供需要时查阅。精简版见 `CLAUDE.md`。

---

### 记忆文档初始化

**相关会话:** (初始化)
**日期:** 2026-01-20
**状态:** ✅ 完成

**功能描述:**
创建 CLAUDE.md v1.0，建立项目记忆文档框架。

**完成任务:**
1. ✅ 创建 CLAUDE.md 基础结构
2. ✅ 定义快速上下文表
3. ✅ 记录项目基本信息
4. ✅ 定义技术栈

---

### v2.0 架构设计

**相关会话:** (重构)
**日期:** 2026-01-20
**状态:** ✅ 完成

**功能描述:**
收集用户需求，设计 DMSA v2.0 核心架构。

**实现思路:**
- 用户需求：实现 VFS 智能合并，用户通过 ~/Downloads 统一访问
- 设计决策：使用 macFUSE 实现 FUSE 文件系统
- 同步策略：单向 LOCAL → EXTERNAL，Write-Back 模式

**完成任务:**
1. ✅ 需求收集与整理
2. ✅ 架构设计文档
3. ✅ 核心流程设计
4. ✅ 目录结构规划

---

### 核心代码实施

**相关会话:** (实施)
**日期:** 2026-01-20
**状态:** ✅ 完成

**功能描述:**
根据 v2.0 架构设计，实现核心 Swift 代码。

**完成任务:**
1. ✅ 创建 21 个 Swift 源文件
2. ✅ 实现 VFS 核心组件
3. ✅ 实现同步引擎
4. ✅ 实现数据库管理

**修改文件:**
```
DMSAApp/DMSAApp/
├── App/AppDelegate.swift
├── Models/Config.swift, FileEntry.swift, SyncHistory.swift
├── Services/DatabaseManager.swift, DiskManager.swift, SyncEngine.swift
├── Services/Sync/NativeSyncEngine.swift, FileScanner.swift, DiffEngine.swift
├── UI/MenuBarManager.swift, Views/*.swift
└── Utils/Logger.swift, Constants.swift, Errors.swift
```

---

### UI 卡死修复

**相关会话:** (性能修复)
**日期:** 2026-01-21
**状态:** ✅ 完成

**功能描述:**
修复点击同步后 UI 卡死的问题。

**问题分析:**
- 现象: 点击同步后主线程卡死
- 根因: 进度回调过于频繁，每次文件操作都触发 UI 更新

**解决方案:**
1. 进度回调节流 100ms
2. 日志批量刷新
3. 异步数据加载

**修改文件:**
```
NativeSyncEngine.swift  # 添加节流逻辑
AppDelegate.swift       # 异步处理回调
```

---

### v2.1 架构纠正

**相关会话:** (架构纠正)
**日期:** 2026-01-21
**状态:** ✅ 完成

**功能描述:**
纠正架构设计问题，移除 LocalCache 目录，改用 Downloads_Local。

**变更内容:**

| 变更项 | 旧设计 | 新设计 |
|--------|--------|--------|
| 本地存储 | `~/Library/.../LocalCache/` | `~/Downloads_Local` |
| 缓存管理 | CacheManager 管理淘汰 | 不需要，直接使用本地目录 |
| VFS 显示 | 单一来源路由 | 智能合并 (并集显示) |
| 首次设置 | 无 | 重命名 ~/Downloads → ~/Downloads_Local |

**已删除文件:**
- `CacheManager.swift`
- `CacheSettingsView.swift`

**修改文件:**
- `Constants.swift` - 移除 `localCache`，添加 `downloadsLocal`
- `ReadRouter.swift` - 改用 Downloads_Local 路径
- `WriteRouter.swift` - 改用 Downloads_Local 路径

---

### macFUSE 集成

**相关会话:** (macFUSE)
**日期:** 2026-01-24
**状态:** ✅ 完成

**功能描述:**
集成 macFUSE 5.1.3+，实现 VFS 核心组件。

**实现思路:**
- 使用 macFUSE (非 FUSE-T，因 FUSE-T 服务器组件闭源)
- 通过 GMUserFileSystem 类挂载虚拟文件系统
- Objective-C 桥接头文件导入 macFUSE Framework

**完成任务:**
1. ✅ FUSEManager - macFUSE 检测、版本验证、安装引导
2. ✅ DMSAFileSystem - GMUserFileSystem 委托实现
3. ✅ VFSCore - FUSE 操作入口
4. ✅ MergeEngine - 智能合并引擎
5. ✅ ReadRouter/WriteRouter - 读写路由
6. ✅ LockManager - 文件锁管理

**Xcode 配置:**
- Framework Search Paths: `/Library/Frameworks`
- LD_RUNPATH_SEARCH_PATHS: `/Library/Frameworks`
- Bridging Header: `DMSAApp/DMSAApp-Bridging-Header.h`

---

### v4.1 服务统一

**相关会话:** (v4.1)
**日期:** 2026-01-24
**状态:** ✅ 完成

**功能描述:**
将三个独立服务 (VFS, Sync, Helper) 合并为单一 DMSAService。

**变更内容:**

| 变更项 | v4.0 (旧) | v4.1 (新) |
|--------|-----------|-----------|
| 服务数量 | 3 个独立 LaunchDaemon | 1 个统一 LaunchDaemon |
| XPC 连接 | 3 个独立连接 | 1 个统一连接 |
| 服务标识 | `vfs`, `sync`, `helper` | `com.ttttt.dmsa.service` |

**新建文件:**
- `DMSAService/main.swift`
- `DMSAService/ServiceDelegate.swift`
- `DMSAService/ServiceImplementation.swift`
- `DMSAService/VFS/VFSManager.swift`
- `DMSAService/Sync/SyncManager.swift`
- `DMSAShared/Protocols/DMSAServiceProtocol.swift`
- `DMSAApp/Services/ServiceClient.swift`

**架构优势:**
1. GUI 退出不影响核心服务
2. 简化 XPC 通信
3. root 权限运行
4. launchd 自动恢复

---

### v4.2 FUSE 服务迁移

**相关会话:** (v4.2)
**日期:** 2026-01-24
**状态:** ✅ 完成

**功能描述:**
将 macFUSE 挂载从 DMSAApp 移至 DMSAService。

**变更内容:**
- FUSE 挂载位置: DMSAApp → DMSAService
- VFSCore 调用方式: 直接创建实例 → 通过 ServiceClient.mountVFS() XPC 调用

**新建文件:**
- `DMSAService/VFS/FUSEFileSystem.swift`

**删除文件:**
- `DMSAApp/Services/VFS/DMSAFileSystem.swift`

**架构优势:**
1. GUI 退出不影响 FUSE
2. 权限统一
3. 简化 App 代码

---

### v4.3 EvictionManager

**相关会话:** (v4.3)
**日期:** 2026-01-24
**状态:** ✅ 完成

**功能描述:**
在 DMSAService 中实现 LRU (Least Recently Used) 淘汰机制。

**新建文件:**
- `DMSAService/VFS/EvictionManager.swift`

**功能列表:**
- 自动淘汰 - 定时检查空间，低于阈值时自动触发
- 手动淘汰 - 支持按需淘汰指定文件
- LRU 排序 - 按访问时间排序，优先淘汰最久未访问的文件
- 安全检查 - 仅淘汰已同步到 EXTERNAL 的非脏文件
- 预取支持 - 支持从 EXTERNAL 预取文件到 LOCAL

**配置参数:**

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `triggerThreshold` | 5GB | 触发淘汰的可用空间阈值 |
| `targetFreeSpace` | 10GB | 淘汰目标可用空间 |
| `maxFilesPerRun` | 100 | 单次淘汰最大文件数 |
| `minFileAge` | 1小时 | 最小文件年龄 |
| `checkInterval` | 5分钟 | 自动检查间隔 |

---

### v4.4 业务逻辑迁移

**相关会话:** (v4.4)
**日期:** 2026-01-24
**状态:** ✅ 完成

**功能描述:**
将 DMSAApp 中剩余的业务逻辑代码全面迁移到 DMSAService。

**迁移内容:**

**Phase 1: 同步逻辑**
- NativeSyncEngine.swift
- FileScanner.swift
- FileHasher.swift
- DiffEngine.swift
- FileCopier.swift
- ConflictResolver.swift
- SyncStateManager.swift

**Phase 2: VFS 代码**
- MergeEngine.swift
- ReadRouter.swift
- WriteRouter.swift
- LockManager.swift

**Phase 3: 数据管理**
- ServiceDatabaseManager.swift
- ServiceTreeVersionManager.swift
- ServiceConfigManager.swift

**Phase 4: 监控**
- ServiceFSEventsMonitor.swift
- ServiceDiskMonitor.swift

**变更统计:**

| 维度 | v4.3 | v4.4 |
|------|------|------|
| DMSAApp 代码量 | ~8000 行 | ~2500 行 |
| DMSAApp 职责 | UI + 部分业务 | 纯 UI 客户端 |

---

### v4.5 App 端清理

**相关会话:** (v4.5)
**日期:** 2026-01-24
**状态:** ✅ 完成

**功能描述:**
移除 DMSAApp 中所有冗余代码和兼容性逻辑。

**已删除文件 (20+ 个):**
- Services/SyncEngine.swift (~480 行)
- Services/SyncScheduler.swift (~250 行)
- Services/FSEventsMonitor.swift (~380 行)
- Services/Sync/*.swift (6 个文件)
- Services/VFS/MergeEngine.swift (~430 行)
- Services/VFS/ReadRouter.swift (~270 行)
- Services/VFS/WriteRouter.swift (~320 行)
- Services/FileFilter.swift (~300 行)
- Services/VFS/VFSCore.swift (~330 行)
- Services/VFS/FUSEBridge.swift (~450 行)
- Services/VFS/VFSError.swift (~160 行)

**代码清理:**
- DatabaseManager.swift - 移除 17 个 deprecated 方法

**变更统计:**

| 维度 | v4.4 | v4.5 |
|------|------|------|
| Services 文件数 | 20+ | 12 |
| 代码行数 | ~5000 | ~2500 |
| deprecated 方法 | 17+ | 0 |

---

### v4.6 纯 UI 架构

**相关会话:** (v4.6)
**日期:** 2026-01-24
**状态:** ✅ 完成

**功能描述:**
最终清理，使 DMSAApp 成为纯 UI 客户端，Services 目录仅剩 10 个文件。

**DMSAApp 最终 Services 结构:**

```
DMSAApp/Services/
├── AlertManager.swift          # UI 弹窗
├── AppearanceManager.swift     # 外观管理
├── ConfigManager.swift         # 配置管理
├── DatabaseManager.swift       # 内存缓存
├── DiskManager.swift           # 磁盘事件 + UI 回调
├── LaunchAtLoginManager.swift  # 启动项管理
├── NotificationManager.swift   # 通知管理
├── PermissionManager.swift     # 权限管理
├── ServiceClient.swift         # XPC 客户端 (核心)
└── VFS/
    └── FUSEManager.swift       # macFUSE 检测
```

**DMSAService 最终结构:**

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
│   ├── NativeSyncEngine.swift
│   ├── FileScanner.swift
│   ├── FileHasher.swift
│   ├── DiffEngine.swift
│   ├── FileCopier.swift
│   ├── ConflictResolver.swift
│   └── SyncStateManager.swift
├── Data/
│   ├── ServiceDatabaseManager.swift
│   ├── ServiceTreeVersionManager.swift
│   └── ServiceConfigManager.swift
├── Monitor/
│   ├── ServiceFSEventsMonitor.swift
│   └── ServiceDiskMonitor.swift
└── Privileged/
    └── PrivilegedOperations.swift
```

**设计原则:**
1. App 只做 UI，不包含任何业务逻辑
2. Service 是大脑，所有同步、VFS、数据管理都在 Service
3. XPC 是桥梁，App 通过 ServiceClient 与 Service 通信
4. 无兼容代码，删除所有 deprecated 方法

---

### v4.5 编译修复

**相关会话:** 505f841a
**日期:** 2026-01-24
**状态:** ✅ 完成

**功能描述:**
修复 v4.5 代码清理后的编译错误，确保 DMSAApp 和 DMSAService 都能成功编译。

**问题与解决方案:**

| 问题 | 文件 | 解决方案 |
|------|------|----------|
| getSyncHistory 重复定义 | ServiceClient.swift | 删除 History Operations 区域的重复函数 |
| ConfigManager 类型找不到 | MenuBarManager.swift | 从 git 恢复 ConfigManager.swift 并添加到项目 |
| MainActor 隔离错误 | AppDelegate.swift | 用 `Task { @MainActor in }` 包装 alertManager 调用 |
| MainWindowController 缺少参数 | AppDelegate.swift | 传入 `configManager: ConfigManager.shared` |
| 可选 String 类型不匹配 | DashboardView.swift | `progress.currentFile ?? ""` |
| 表达式复杂度超时 | StatisticsView.swift | 拆分 SyncStatistics 初始化为多个语句 |
| SyncStatistics 初始化参数错误 | StatisticsView.swift | 改用实例属性赋值方式 |
| SyncProgress/ServiceSyncProgress 类型混用 | FileCopier.swift | 统一使用 ServiceSyncProgress (class) |
| FileEntry/ServiceFileEntry 类型混用 | EvictionManager.swift | 统一使用 ServiceFileEntry |
| SyncStatus/FileLocation 枚举缺失 | Config.swift | 在 DMSAApp 端添加枚举定义 |

**新增文件:**
- `DMSAShared/Models/NotificationRecord.swift` - 通知记录模型
- `DMSAShared/Models/Sync/SyncTask.swift` - 同步任务模型
- `DMSAService/Sync/ServiceSyncProgress.swift` - Service 端进度类
- `DMSAService/VFS/LockManager.swift` - 从 App 迁移的锁管理器

**修改文件:**
- `ServiceClient.swift` - 删除重复函数
- `AppDelegate.swift` - MainActor 隔离修复
- `Config.swift` - 添加 SyncDirection/SyncStatus/FileLocation 枚举
- `DashboardView.swift` - 可选类型处理
- `StatisticsView.swift` - 表达式拆分
- `FileCopier.swift` - 使用 ServiceSyncProgress
- `SyncStateManager.swift` - 返回类型修改
- `SyncManager.swift` - 变量作用域修复
- `EvictionManager.swift` - 使用 ServiceFileEntry
- `ServiceDatabaseManager.swift` - 数组类型推断修复
- `project.pbxproj` - 添加 ConfigManager 和 NotificationRecord

**关键代码变更:**

```swift
// FileCopier.swift - 改用 class 避免 inout
typealias BatchProgressHandler = (ServiceSyncProgress) -> Void
func copyFiles(..., progress: ServiceSyncProgress, ...)

// EvictionManager.swift - 使用 ServiceFileEntry
private func getEvictionCandidates(syncPairId: String) async -> [ServiceFileEntry]
guard entry.fileLocation == .both else { ... }

// Config.swift - 添加枚举
enum SyncStatus: Int, Codable { ... }
enum FileLocation: Int, Codable { ... }
```

**Git 提交:** `e04cf58` - v4.5: App端代码精简，修复编译错误

**编译结果:**
- ✅ DMSAApp - BUILD SUCCEEDED
- ✅ com.ttttt.dmsa.service - BUILD SUCCEEDED

---

*文档维护: 每次会话结束时追加新的会话记录*
