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

### 代码签名修复

**相关会话:** eae6e63e
**日期:** 2026-01-26
**状态:** ✅ 完成

**功能描述:**
修复 DMSAService 安装失败和 macFUSE 加载失败的代码签名问题。

**问题与解决方案:**

| 问题 | 错误信息 | 解决方案 |
|------|----------|----------|
| Service 安装失败 | `SMAppServiceErrorDomain Code=1 "Operation not permitted"` | 设置 `DEVELOPMENT_TEAM = 9QGKH6ZBPG` |
| macFUSE 加载失败 | `different Team IDs` | 添加 `com.apple.security.cs.disable-library-validation` |

**问题分析:**

1. **Service 安装失败:**
   - 根因: `com.ttttt.dmsa.service` target 的 `DEVELOPMENT_TEAM = ""` (空)
   - 导致 service 用 ad-hoc 签名，SMAppService 无法注册
   - 修复: 在 project.pbxproj 中设置 `DEVELOPMENT_TEAM = 9QGKH6ZBPG`

2. **macFUSE 加载失败:**
   - 根因: macFUSE 由第三方签名，与 App 的 Team ID 不同
   - 默认启用的 Library Validation 阻止加载不同签名的动态库
   - 修复: 在 DMSA.entitlements 添加 `disable-library-validation`

**修改文件:**
- `DMSAApp.xcodeproj/project.pbxproj` - Service Debug/Release 的 DEVELOPMENT_TEAM
- `DMSAApp/Resources/DMSA.entitlements` - 添加 disable-library-validation

**关键配置变更:**

```xml
<!-- DMSA.entitlements -->
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

```
// project.pbxproj (SVC700001, SVC700002)
DEVELOPMENT_TEAM = 9QGKH6ZBPG;
```

**后续步骤:**
- 用户需前往 **系统设置 > 隐私与安全性 > 登录项与扩展** 批准 "DMSA Service"

---

### C FUSE Wrapper 与权限修复

**相关会话:** 2a099f6b
**日期:** 2026-01-26
**状态:** ✅ 完成

**功能描述:**
用 C 语言实现 libfuse wrapper，替换 GMUserFileSystem，解决多线程 fork() 崩溃问题。同时修复 FUSE 文件所有权和后端目录保护问题。

**实现思路:**
- GMUserFileSystem (Objective-C) 在多线程环境下 fork() 会崩溃
- 用纯 C 直接调用 libfuse API，避免 ObjC runtime 问题
- Service 以 root 运行，需从父目录获取用户 uid/gid

**问题与解决方案:**

| 问题 | 根因 | 解决方案 |
|------|------|----------|
| ~/Downloads 显示 root:wheel | getuid() 在 root 进程返回 0 | 从挂载点父目录获取 owner uid/gid |
| "移到废纸篓" 变成 "立即删除" | root 所有者无法移到用户废纸篓 | 同上 |
| EXTERNAL_DIR 未被保护 | externalPath 为空字符串而非 nil | 磁盘未连接时设为 nil |
| 增量编译未更新 VFSManager | Xcode 增量编译跳过 | 执行 clean build |

**新建文件:**
- `DMSAService/VFS/fuse_wrapper.c` - C 语言 FUSE 实现 (~1200 行)
- `DMSAService/VFS/fuse_wrapper.h` - 头文件
- `DMSAService/DMSAService-Bridging-Header.h` - Swift-C 桥接

**修改文件:**
- `VFSManager.swift` - 调用 fuse_wrapper，添加保护日志
- `ServiceImplementation.swift` - externalPath nil vs ""
- `main.swift` - 添加构建时间日志
- `com.ttttt.dmsa.service.plist` - 正确 Program 路径

**关键代码变更:**

```c
// fuse_wrapper.c - 从父目录获取 owner
struct stat parent_stat;
char *parent_path = strdup(mount_path);
char *last_slash = strrchr(parent_path, '/');
if (last_slash && last_slash != parent_path) {
    *last_slash = '\0';
    if (stat(parent_path, &parent_stat) == 0) {
        g_state.owner_uid = parent_stat.st_uid;
        g_state.owner_gid = parent_stat.st_gid;
    }
}

// dmsa_getattr - 使用保存的 owner
stbuf->st_uid = g_state.owner_uid;  // 不再用 getuid()
stbuf->st_gid = g_state.owner_gid;
```

```swift
// ServiceImplementation.swift
// Before: let externalPath = disk.isConnected ? ... : ""
// After:
let externalPath: String? = disk.isConnected ? ... : nil
```

**FUSE wrapper 功能:**
- mount/unmount 管理
- readdir 智能合并 (LOCAL ∪ EXTERNAL)
- 读写路由 (优先 LOCAL，fallback EXTERNAL)
- 离线模式支持
- 后端目录保护 (chmod/ACL/chflags hidden)

**部署步骤:**
```bash
# 1. Clean build
xcodebuild clean build -scheme "com.ttttt.dmsa.service" -configuration Debug

# 2. 停止服务
sudo launchctl bootout system/com.ttttt.dmsa.service

# 3. 复制二进制
sudo cp .../Debug/com.ttttt.dmsa.service /Library/PrivilegedHelperTools/

# 4. 启动服务
sudo launchctl bootstrap system /Library/LaunchDaemons/com.ttttt.dmsa.service.plist
```

---

### MD 文档清理

**相关会话:** e4bd3c09
**日期:** 2026-01-27
**状态:** ✅ 完成

**功能描述:**
清理项目中的 MD 文档，删除已完成的计划文档和过时的设计文档，精简项目结构。

**完成任务:**
1. ✅ 删除已完成的计划文档 (6 个)
2. ✅ 删除过时的设计文档 (7 个)
3. ✅ 更新 README.md 为 v4.8 精简版
4. ✅ 更新 CLAUDE.md 版本和引用

**删除文件 (13 个):**
- `SERVICE_MERGE_PLAN.md` - 服务合并计划 (已完成)
- `XCODE_PROJECT_UPDATE_GUIDE.md` - Xcode 迁移指南 (已完成)
- `CODE_REVIEW_REPORT.md` - v4.1 代码评审 (已过时)
- `ARCHITECTURE_REVIEW.md` - v4.3 架构评审 (已过时)
- `MIGRATION_PLAN.md` - 迁移计划 (已完成)
- `VFS_FIX_PLAN.md` - VFS 修复计划 (已完成)
- `REQUIREMENTS.md` - v3.0 需求文档
- `TECHNICAL.md` - v3.0 技术文档
- `CONFIGURATIONS.md` - 配置文档
- `FLOWCHARTS.md` - 流程图
- `UI_DESIGN.md` - UI 设计文档
- `VFS_DESIGN.md` - VFS 设计文档
- `SYSTEM_ARCHITECTURE.md` - v4.0 架构设计

**保留文件 (4 个):**
- `CLAUDE.md` - 项目记忆文档 (v5.2)
- `CLAUDE_SESSIONS.md` - 会话详细记录归档
- `README.md` - 项目介绍 (v4.8)
- `OBJECTBOX_SETUP.md` - ObjectBox 集成指南

**变更统计:**
- 文件数量: 17 → 4 (减少 76%)
- 代码行数: -13,543 行

---

### SERVICE_FLOW 文档体系

**相关会话:** 50877371
**日期:** 2026-01-27
**状态:** ✅ 完成

**功能描述:**
创建完整的 SERVICE_FLOW 文档体系，包含 Service 端和 App 端所有流程的详细设计文档，采用最佳架构设计原则。

**实现思路:**
- 将原有单一大文档拆分为 17 个独立主题文件
- 新增 App 端完整交互流程文档 (20_App启动与交互流程.md)
- 使用 Mermaid 图表描述所有流程
- 不依赖现有代码，按最佳实践设计

**完成任务:**
1. ✅ 创建 SERVICE_FLOW 文件夹
2. ✅ 拆分主流程文档为 17 个文件 (01-17)
3. ✅ 创建索引文件 (00_README.md)
4. ✅ 补充 VFS 文件操作处理流程 (create/write/read/unlink/rename/mkdir/rmdir 等)
5. ✅ 创建 App 启动与交互流程完整文档 (20_App启动与交互流程.md，约 950 行)
6. ✅ 修复 Mermaid 语法错误

**创建文件 (19 个):**
```
SERVICE_FLOW/
├── 00_README.md                    # 索引和快速导航
├── 01_服务状态定义.md              # ServiceState, ComponentState
├── 02_配置管理.md                  # 配置加载、验证、冲突解决
├── 03_启动流程总览.md              # 5 个启动阶段概览
├── 04_XPC通信与通知.md             # 通知缓存、连接管理
├── 05_状态管理器.md                # ServiceStateManager
├── 06_XPC优先启动.md               # XPC 优先启动原因
├── 07_VFS预挂载机制.md             # FUSE 预挂载、文件操作处理
├── 08_索引构建流程.md              # 版本管理、索引构建
├── 09_文件同步流程.md              # 同步策略、脏文件管理
├── 10_冲突处理流程.md              # 冲突检测、解决策略
├── 11_热数据淘汰流程.md            # LRU 淘汰、安全检查
├── 12_完整启动时序.md              # Sequence Diagram
├── 13_App端交互流程.md             # App UI 状态映射
├── 14_分布式通知.md                # 通知事件、触发条件
├── 15_错误处理.md                  # 错误分类、恢复接口
├── 16_日志规范.md                  # 日志格式、示例
├── 17_检查清单.md                  # 启动检查清单
└── 20_App启动与交互流程.md         # App 完整设计 (15 章节)
```

**20_App启动与交互流程.md 核心内容:**
- 架构概览 (4 层架构)
- App 生命周期
- 详细启动流程 (5 阶段)
- 首次启动向导 (5 步骤)
- XPC 连接管理
- 状态同步机制
- UI 状态机
- 用户交互流程 (同步、淘汰、冲突处理)
- 配置管理交互
- 磁盘管理交互
- 错误处理与恢复
- 通知处理
- 前后台切换
- 退出流程

**关键技术概念:**
- Copy-on-Write (COW) 机制
- isDirty 脏文件标记
- DeletePending 延迟删除
- XPC 连接状态机 (disconnected/connecting/connected/interrupted/failed)
- UI 状态机 (initializing/connecting/starting/ready/syncing/evicting/error)
- 首次启动向导流程

**问题与解决:**
- Mermaid 语法: 方括号内嵌套引号需改用外层引号包裹

---

### v4.9 服务端代码修改 (P0-P3 全部完成)

**相关会话:** 50877371 (续)
**日期:** 2026-01-27
**状态:** ✅ 完成

**功能描述:**
基于 SERVICE_FLOW 文档体系对现有代码进行审查和修改，实现所有缺失功能。全部 P0-P3 任务已完成。

**实现内容:**

**阶段 1 - P0 核心状态管理:**
- `ServiceState.swift` - 全局服务状态枚举 (9 种状态)
- `ServiceFullState.swift` - 完整状态结构
- `ServiceStateManager.swift` - 状态管理器 Actor + NotificationQueue
- `DMSAServiceProtocol.swift` - 添加 getFullState/getGlobalState/canPerformOperation
- `ServiceImplementation.swift` - 实现新增 XPC 方法

**阶段 2 - P1 VFS 阻塞机制:**
- `fuse_wrapper.h/c` - 添加 index_ready 标记，EBUSY 阻塞
- `FUSEFileSystem.swift` - 添加 setIndexReady() Swift 封装
- `VFSManager.swift` - 索引完成后开放 VFS 访问

**阶段 3 - P2 通知与错误码:**
- `Constants.swift` - 添加所有通知常量 (10 种)
- `ServiceError.swift` - 统一错误码定义 (1xxx-6xxx)

**阶段 4 - P3 优化项:**
- `StartupChecker.swift` - 12 项启动检查 (5 预启动 + 7 运行时)
- `ServiceConfigManager.swift` - 4 种配置冲突检测
- `Logger.swift` - 标准格式日志支持
- `main.swift` - 集成预启动检查 + LoggerStateCache

**技术要点:**
1. **状态管理**: Swift Actor 保证线程安全，通知队列在 XPC 就绪前缓存
2. **VFS 阻塞**: FUSE 层使用 C 实现，pthread_mutex 保护 index_ready 状态
3. **配置冲突检测**:
   - MULTIPLE_EXTERNAL_DIRS - 多个 syncPair 使用同一 EXTERNAL_DIR
   - OVERLAPPING_LOCAL - LOCAL_DIR 有重叠
   - DISK_NOT_FOUND - 引用的 disk 不存在
   - CIRCULAR_SYNC - 循环同步检测
4. **日志格式**: `[时间戳] [级别] [全局状态] [组件] [组件状态] 消息`
5. **启动检查**: 严重错误 (不可恢复) vs 可恢复错误，预启动失败直接退出

**新建文件:**
```
DMSAShared/Models/ServiceState.swift
DMSAShared/Models/ServiceFullState.swift
DMSAShared/Models/ServiceError.swift
DMSAService/State/ServiceStateManager.swift
DMSAService/Utils/StartupChecker.swift
SERVICE_FLOW/99_服务端代码修改计划.md
```

**修改文件:**
```
DMSAShared/Protocols/DMSAServiceProtocol.swift
DMSAShared/Utils/Constants.swift
DMSAShared/Utils/Logger.swift
DMSAService/ServiceImplementation.swift
DMSAService/main.swift
DMSAService/VFS/fuse_wrapper.h
DMSAService/VFS/fuse_wrapper.c
DMSAService/VFS/FUSEFileSystem.swift
DMSAService/VFS/VFSManager.swift
DMSAService/Data/ServiceConfigManager.swift
```

**验收标准:**
- ✅ App 可通过 XPC 调用 getFullState() 获取完整服务状态
- ✅ 挂载后索引完成前，访问 VFS 返回 EBUSY
- ✅ App 可接收所有 10 种通知类型
- ✅ 错误码符合文档定义 (1xxx-6xxx)
- ✅ 启动时执行 5 项预启动检查
- ✅ 配置加载时检测 4 种冲突
- ✅ Service 日志使用标准格式

---

### UI 设计规范文档与 HTML 原型

**相关会话:** 50877371 (续)
**日期:** 2026-01-27
**状态:** ✅ 完成

**功能描述:**
基于 `20_App启动与交互流程.md` 创建 UI 设计规范文档和 HTML 原型。

**实现内容:**

1. **UI 设计规范文档** (`SERVICE_FLOW/21_UI设计规范.md`)
   - 12 个主要章节 (已移除首次启动向导)
   - 采用自然语言 + 结构化 YAML 格式
   - 符合 macOS Human Interface Guidelines

2. **HTML 原型** (`SERVICE_FLOW/ui_prototype.html`)
   - 完整实现设计规范中的所有组件
   - 支持深色模式 (CSS media query)
   - 约 2000 行代码，73KB

**文档结构 (21_UI设计规范.md):**
```
1. 设计原则 - 核心理念、状态优先、渐进式披露
2. 设计系统 - 颜色、字体、间距、图标
3. 状态栏组件 - 8 种状态图标 + 动画
4. 菜单栏设计 - 5 种状态的菜单内容
5. 设置窗口 - 5 个标签页 (通用/同步/存储/磁盘/高级)
6. 同步详情窗口 - 进度、统计、错误列表
7. 冲突解决界面 - 冲突列表、解决弹窗
8. 磁盘管理界面 - 侧边栏 + 详情面板
9. 弹窗与通知 - 确认对话框、错误弹窗、系统通知
10. 响应式设计 - 窗口尺寸适配、文本截断
11. 无障碍设计 - VoiceOver、键盘导航
12. 组件规范 - 按钮、表单、列表、进度指示器
```

**HTML 原型覆盖:**
- ✅ 状态栏图标 (8 种状态 + 动画)
- ✅ 菜单栏 (就绪/同步中)
- ✅ 设置窗口 (5 个标签页)
- ✅ 同步详情窗口 (同步中/已完成)
- ✅ 冲突列表
- ✅ 磁盘管理 (侧边栏 + 详情)
- ✅ 对话框和通知
- ✅ 按钮和表单控件

**新建文件:**
```
SERVICE_FLOW/21_UI设计规范.md
SERVICE_FLOW/ui_prototype.html
```

**修改文件:**
```
SERVICE_FLOW/00_README.md - 添加文档索引
```

---

### App 修改计划 - 代码审查与 P0-P2 修复

**相关会话:** 4f263311
**日期:** 2026-01-27
**状态:** ✅ 完成

**功能描述:**
根据 `20_App启动与交互流程.md` 和 `22_UI修改计划.md` 执行代码审查，生成 App 修改计划文档，并完成 P0-P2 问题修复。

**实现思路:**
- 对比设计规范与当前代码实现
- 识别架构差距和缺失组件
- 制定分阶段修改计划
- 实施关键问题修复

---

**阶段 1: 代码审查与计划生成**

**完成任务:**
1. ✅ 读取并分析 20_App启动与交互流程.md
2. ✅ 读取并分析 22_UI修改计划.md
3. ✅ 审查 AppDelegate.swift, ServiceClient.swift, MainView.swift, MenuBarManager.swift
4. ✅ 生成 23_App修改计划.md 和 24_App代码审查报告.md

**代码审查发现:**

| 设计规范要求 | 当前实现 | 状态 |
|-------------|---------|------|
| AppCoordinator 协调器 | 直接在 AppDelegate 处理 | **待实现** |
| StateManager 状态管理 | AppUIState (简化版) | **需增强** |
| NotificationHandler | 在 ServiceClient 处理 | **需分离** |
| 后台/前台切换处理 | 缺失 | **待实现** |
| 错误处理与恢复 | 基础弹窗 | **需完善** |
| menuBarDidRequestOpenTab | MenuBarDelegate 已添加但 AppDelegate 未实现 | **紧急修复** |

---

**阶段 2: P0-P2 问题修复**

**修复的问题:**

| 优先级 | 问题 | 修复方式 | 文件 |
|--------|------|----------|------|
| P0 | XPC 调用无超时保护 | 添加 `withTimeout` 包装器，默认 10s | ServiceClient.swift |
| P0 | 连接恢复后无 UI 通知 | 添加 `onConnectionStateChanged` 回调 | ServiceClient.swift |
| P1 | 配置缓存竞态条件 | 添加 `configLock` 锁保护 + `isConfigFetching` 防并发 | AppDelegate.swift |
| P1 | 磁盘匹配逻辑脆弱 | 新增 `matchesDisk()` 精确匹配方法 | DiskManager.swift |
| P2 | 定时器未在 deinit 中清理 | 添加 `deinit` 清理 + `applicationWillTerminate` 清理 | AppDelegate.swift |

**关键代码变更:**

```swift
// ServiceClient.swift - XPC 超时保护
private let defaultTimeout: TimeInterval = 10
var onConnectionStateChanged: ((Bool) -> Void)?

private func withTimeout<T>(
    _ operation: String,
    timeout: TimeInterval? = nil,
    task: @escaping () async throws -> T
) async throws -> T {
    let timeoutDuration = timeout ?? defaultTimeout
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await task() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeoutDuration * 1_000_000_000))
            throw ServiceError.timeout
        }
        guard let result = try await group.next() else {
            throw ServiceError.timeout
        }
        group.cancelAll()
        return result
    }
}

// AppDelegate.swift - 配置缓存锁保护
private let configLock = NSLock()
private var isConfigFetching = false

private func getConfig() async -> AppConfig {
    configLock.lock()
    if let cached = cachedConfig,
       let lastFetch = lastConfigFetch,
       Date().timeIntervalSince(lastFetch) < configCacheTimeout {
        configLock.unlock()
        return cached
    }
    if isConfigFetching {
        configLock.unlock()
        try? await Task.sleep(nanoseconds: 100_000_000)
        return await getConfig()
    }
    isConfigFetching = true
    configLock.unlock()
    // ... fetch config
}

// DiskManager.swift - 精确磁盘匹配
private func matchesDisk(devicePath: String, disk: DiskConfig) -> Bool {
    // 1. 完全路径匹配
    if devicePath == disk.mountPath { return true }
    // 2. 卷名匹配: /Volumes/{name}
    if devicePath == "/Volumes/\(disk.name)" { return true }
    // 3. 处理带序号的卷名 (如 BACKUP-1)
    if let range = normalizedName.range(of: "-\\d+$", options: .regularExpression) {
        let baseName = String(normalizedName[..<range.lowerBound])
        if baseName == disk.name { return true }
    }
    return false
}
```

**XPC 超时覆盖:**
- VFS 操作: `mountVFS` (30s), `unmountVFS` (30s), `getVFSMounts`, `updateExternalPath`, `setExternalOffline`
- 同步操作: `syncNow`, `syncAll`, `pauseSync`, `resumeSync`, `cancelSync`, `getSyncStatus`, `getAllSyncStatus`, `getSyncProgress`, `getSyncHistory`

---

**新建/修改文件:**

新建:
```
DMSAApp/DMSAApp/Models/AppStates.swift
DMSAApp/DMSAApp/Models/ErrorCodes.swift
DMSAApp/DMSAApp/Services/ErrorHandler.swift
DMSAApp/DMSAApp/Services/NotificationHandler.swift
DMSAApp/DMSAApp/Services/StateManager.swift
DMSAApp/Docs/24_App代码审查报告.md
SERVICE_FLOW/23_App修改计划.md
```

修改:
```
DMSAApp/DMSAApp/App/AppDelegate.swift  # 配置缓存锁 + 定时器清理
DMSAApp/DMSAApp/Services/ServiceClient.swift  # XPC 超时保护 + 连接状态回调
DMSAApp/DMSAApp/Services/DiskManager.swift  # 精确磁盘匹配
DMSAApp/DMSAApp/UI/Views/MainView.swift  # 使用 StateManager
```

**代码质量评分:**
- 之前: 6.9/10
- 之后: 7.5/10 (提升 +0.6)

---

### UI 文件清理 + pbxproj 工具

**相关会话:** 4f263311 (续)
**日期:** 2026-01-27
**状态:** ✅ 完成

**功能描述:**
基于 `22_UI修改计划.md` 和 `21_UI设计规范.md` 执行 UI 文件清理，删除 14 个已废弃的旧 UI 文件，并创建通用的 Xcode 项目管理工具 `pbxproj_tool.py`。

**实现思路:**
- 根据设计规范审查现有 UI 文件，识别不再使用的旧组件
- MainView.swift 只引用 6 个新页面，旧 Settings/History/Progress/Wizard 目录下的文件可安全删除
- 将 VFSSettingsViewModel 从即将删除的文件迁移到 SettingsPage.swift
- 创建 Python 工具自动化 Xcode 项目文件管理

---

**阶段 1: 依赖分析与迁移**

**完成任务:**
1. ✅ 验证 MainView.swift 不引用任何旧组件
2. ✅ 检查 VFSSettingsViewModel 依赖关系
3. ✅ 将 VFSSettingsViewModel 和 VFSMountInfo 迁移到 SettingsPage.swift
4. ✅ 生成清理报告文档 25_UI文件清理报告.md

**迁移的代码:**
```swift
// SettingsPage.swift - 新增 VFSSettingsViewModel
class VFSSettingsViewModel: ObservableObject {
    @Published var isMacFUSEInstalled = false
    @Published var macFUSEVersion: String?
    @Published var macFUSEStatusText = "检查中..."
    @Published var macFUSEStatusColor: Color = .secondary
    @Published var isHelperInstalled = false
    @Published var helperVersion: String?
    @Published var helperStatusText = "检查中..."
    @Published var helperStatusColor: Color = .secondary
    @Published var mountedVFS: [VFSMountInfo] = []

    func checkMacFUSE() async { ... }
    func checkService() async { ... }
    func loadVFSMounts() async { ... }
}

struct VFSMountInfo {
    let targetDir: String
    let localDir: String
    let externalDir: String
}
```

---

**阶段 2: 删除旧 UI 文件**

**删除文件 (14 个, ~5,600 行):**

| 目录 | 文件 | 行数 | 原因 |
|------|------|------|------|
| Settings/ | GeneralSettingsView.swift | 106 | 已合并到 SettingsPage |
| Settings/ | NotificationSettingsView.swift | 150 | 已合并到 SettingsPage |
| Settings/ | FilterSettingsView.swift | 251 | 已合并到 SettingsPage |
| Settings/ | AdvancedSettingsView.swift | 352 | 已合并到 SettingsPage |
| Settings/ | SyncPairSettingsView.swift | 446 | 已合并到 SettingsPage |
| Settings/ | VFSSettingsView.swift | 374 | 已合并到 SettingsPage |
| Settings/ | SettingsView.swift | 196 | 被 SettingsPage 替代 |
| Settings/ | DiskSettingsView.swift | 387 | 已合并到 DisksPage |
| Settings/ | StatisticsView.swift | 492 | 已合并到 DashboardView |
| History/ | HistoryView.swift | 663 | 已合并到 SyncPage |
| History/ | HistoryContentView.swift | 326 | 已合并到 SyncPage |
| Notifications/ | NotificationHistoryView.swift | 494 | 已合并到 SyncPage |
| Progress/ | SyncProgressView.swift | 357 | 已合并到 SyncPage |
| Wizard/ | WizardView.swift | 1017 | 设计规范未包含 |

---

**阶段 3: pbxproj_tool.py 创建**

**完成任务:**
1. ✅ 创建 Python 虚拟环境并安装 pbxproj
2. ✅ 创建通用 Xcode 项目管理工具
3. ✅ 移除 14 个已删除文件的项目引用
4. ✅ 修复 96 个损坏的 PBXBuildFile 引用

**工具功能 (pbxproj_tool.py):**

```python
class PBXProjTool:
    # 文件列表
    def list_files(self, pattern=None, file_type=None)
    def list_groups(self)
    def list_targets(self)

    # 文件操作
    def add_file(self, file_path, target_name=None, group_path=None)
    def remove_files(self, file_names, save=True)
    def find_files(self, pattern)
    def file_info(self, file_name)

    # 项目维护
    def check(self)   # 检查项目完整性
    def fix(self)     # 修复损坏引用
    def backup(self)  # 备份项目文件
    def restore(self, backup_name=None)  # 恢复备份
```

**命令行用法:**
```bash
# 列出所有 Swift 文件
python pbxproj_tool.py list --type swift

# 查找匹配模式的文件
python pbxproj_tool.py find "Settings"

# 检查项目完整性
python pbxproj_tool.py check

# 修复损坏引用
python pbxproj_tool.py fix

# 移除文件
python pbxproj_tool.py remove "OldView.swift"
```

**问题与解决:**

| 问题 | 根因 | 解决方案 |
|------|------|----------|
| `'objects' has no attribute 'values'` | pbxproj API 变更 | 使用 `get_objects_in_section()` |
| 部分文件路径不匹配 | 文件在不同子目录 | 使用 Glob 查找实际路径 |
| `remove_file_by_id()` 不工作 | PBXBuildFile 特殊处理 | 直接 `del project.objects[ref_id]` |
| 96 个损坏引用 | 历史遗留问题 | 使用 fix() 命令自动修复 |

---

**变更统计:**

| 维度 | 修改前 | 修改后 |
|------|--------|--------|
| UI 文件数 | 44 | 30 |
| UI 代码行数 | ~14,815 | ~9,200 |
| 代码精简比例 | - | 36% |
| pbxproj 损坏引用 | 96 | 0 |

**新建文件:**
```
pbxproj_tool.py                          # Xcode 项目管理工具 (645 行)
DMSAApp/Docs/25_UI文件清理报告.md         # 清理报告文档
.pbxproj_backups/                        # 项目备份目录
```

**修改文件:**
```
DMSAApp/DMSAApp.xcodeproj/project.pbxproj  # 移除 14 个文件引用 + 修复 96 个损坏引用
DMSAApp/DMSAApp/UI/Views/SettingsPage.swift  # 添加 VFSSettingsViewModel
```

**删除文件:**
- Settings/ 目录下 9 个文件
- History/ 目录下 2 个文件
- Notifications/ 目录下 1 个文件
- Progress/ 目录下 1 个文件
- Wizard/ 目录下 1 个文件

---

### Ruby xcodeproj 迁移

**相关会话:** 4f263311 (续)
**日期:** 2026-01-28
**状态:** ✅ 完成

**功能描述:**
Python pbxproj 库存在 bug，导致连续添加文件后项目损坏。切换到 Ruby xcodeproj 库 (CocoaPods 使用的同一个库)。

**问题与解决:**

| 问题 | 根因 | 解决方案 |
|------|------|----------|
| `'NoneType' object has no attribute 'isa'` | Python pbxproj 在 save() 后内部状态损坏 | 切换到 Ruby xcodeproj 库 |
| 编码错误 `invalid byte sequence in US-ASCII` | Ruby 默认 ASCII 编码 | 设置 `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` |
| 路径重复 `/DMSAService/Utils/DMSAService/Utils/` | `group.new_file()` 使用了完整路径 | 只传文件名 `File.basename(file_path)` |
| Service 编译错误: 缺少类型定义 | StartupChecker 等文件未添加到项目 | 使用 Ruby 工具添加缺失文件 |
| App 编译错误: 缺少 AppUIState 等 | 新 UI 代码引用未定义类型 | 代码问题，需后续修复 |

**实现思路:**

1. Python pbxproj 库在添加文件并保存后，再次加载会产生损坏引用
2. Ruby xcodeproj 是 CocoaPods 官方使用的库，更稳定可靠
3. 创建 `pbxproj_tool.rb` 替代原 Python 版本

**Ruby 工具用法:**
```bash
# 从项目根目录运行
LANG=en_US.UTF-8 bundle exec ruby pbxproj_tool.rb list-targets

# 从 DMSAApp 目录运行添加文件
cd DMSAApp
LANG=en_US.UTF-8 bundle exec ruby ../pbxproj_tool.rb add-multi com.ttttt.dmsa.service \
  DMSAService/Utils/StartupChecker.swift \
  DMSAShared/Models/ServiceState.swift

# 移除文件
LANG=en_US.UTF-8 bundle exec ruby ../pbxproj_tool.rb remove HistoryView.swift
```

**编译状态:**

| Target | 状态 | 说明 |
|--------|------|------|
| com.ttttt.dmsa.service | ✅ 成功 | 添加了 4 个缺失文件后编译通过 |
| DMSAApp | ❌ 失败 | 代码问题：DashboardView 引用未定义的 AppUIState、ActivityItem 等类型 |

**新建/修改文件:**
```
pbxproj_tool.rb              # Ruby 版 Xcode 项目管理工具
Gemfile                      # Ruby 依赖配置
vendor/bundle/               # Ruby gems 本地安装目录
```

**删除文件:**
```
.venv/                       # Python 虚拟环境 (已删除)
pbxproj_tool.py              # Python 版工具 (已删除)
```

---

### DMSAApp 编译错误修复

**相关会话:** 7ec270c8
**日期:** 2026-01-28
**状态:** ✅ 完成

**功能描述:**
修复 DMSAApp 编译错误，解决 P0 级类型引用问题，使项目成功编译。

**问题与解决:**

| 问题 | 文件 | 解决方案 |
|------|------|----------|
| AppUIState 未定义 | DashboardView.swift, ConflictsPage.swift, MenuBarManager.swift | 替换为 StateManager.shared |
| ActivityItem 未定义 | DashboardView.swift | 删除未使用的变量 |
| serviceState 类型 String | StateManager.swift | 改为 ServiceState 枚举类型 |
| SyncStatus 枚举成员错误 | NotificationHandler.swift, StateManager.swift, ServiceClient.swift | `.idle/.syncing/.error` → `.pending/.inProgress/.failed` |
| SyncStatusInfo.message 不存在 | StateManager.swift | 改用默认错误消息 |
| SyncProgressInfo 参数顺序 | NotificationHandler.swift | 调整 currentFile 位置 |
| AddDiskSheet 未定义 | DisksPage.swift | 创建 AddDiskSheet.swift 组件 |
| externalPath 不存在 | DisksPage.swift | 改为 externalRelativePath |
| syncMode 不存在 | DisksPage.swift | 改为 direction |
| Color.tertiaryLabel 不存在 | ActivityRow.swift, ConflictCard.swift | 改为 Color(NSColor.tertiaryLabelColor) |
| Color.quaternaryLabel 不存在 | ConflictCard.swift | 改为 Color(NSColor.quaternaryLabelColor) |
| await ?? 操作符错误 | AppDelegate.swift | 拆分为 if let + return |
| MainActor 隔离问题 | AppDelegate.swift | Task 添加 @MainActor in |

**关键代码变更:**

```swift
// DashboardView.swift - 替换状态管理
// Before:
@StateObject private var appState = AppUIState.shared
// After:
@ObservedObject private var stateManager = StateManager.shared

// StateManager.swift - 枚举类型
@Published var serviceState: ServiceState = .starting

// NotificationHandler.swift - SyncStatus 枚举修复
switch status {
case .pending, .completed, .cancelled:  // 原: .idle, .completed
    stateManager.updateUIState(.ready)
case .inProgress:  // 原: .syncing
    break
case .failed:  // 原: .error
    stateManager.updateError(error)
}

// ServiceClient.swift - 错误状态修复
progressDelegate?.syncStatusDidChange(
    syncPairId: "",
    status: .failed,  // 原: .error
    message: "XPC 连接中断"
)

// ActivityRow.swift - macOS Color 修复
.foregroundColor(Color(NSColor.tertiaryLabelColor))

// AppDelegate.swift - await 语法修复
// Before:
return cached ?? await getConfig()
// After:
if let cached = cached { return cached }
return await getConfig()
```

**新建文件:**
```
DMSAApp/DMSAApp/UI/Components/AddDiskSheet.swift  # 添加硬盘 Sheet 组件
SERVICE_FLOW/26_UI代码审查报告.md                   # 代码审查报告
```

**修改文件:**
```
DMSAApp/DMSAApp/App/AppDelegate.swift              # await 语法 + MainActor
DMSAApp/DMSAApp/Models/AppStates.swift             # ComponentState 重命名
DMSAApp/DMSAApp/Services/AlertManager.swift        # MainTab.history → .logs
DMSAApp/DMSAApp/Services/NotificationHandler.swift # SyncStatus 枚举修复
DMSAApp/DMSAApp/Services/ServiceClient.swift       # .error → .failed
DMSAApp/DMSAApp/Services/StateManager.swift        # serviceState 类型 + SyncStatus
DMSAApp/DMSAApp/UI/Components/ActivityRow.swift    # Color 扩展修复
DMSAApp/DMSAApp/UI/Components/ConflictCard.swift   # Color 扩展 + 删除重复枚举
DMSAApp/DMSAApp/UI/MenuBarManager.swift            # MainActor.assumeIsolated
DMSAApp/DMSAApp/UI/Views/ConflictsPage.swift       # AppUIState → StateManager
DMSAApp/DMSAApp/UI/Views/DisksPage.swift           # 属性名修复
DMSAApp/DMSAApp/UI/Views/Settings/DashboardView.swift # AppUIState → StateManager
DMSAApp/DMSAApp.xcodeproj/project.pbxproj          # 添加 AddDiskSheet
```

**编译结果:**
- ✅ DMSAApp - BUILD SUCCEEDED
- ✅ com.ttttt.dmsa.service - BUILD SUCCEEDED

---

## Session 7ec270c8 - 文件级同步/淘汰记录 (2026-01-28)

### 任务
- 实现文件级别的同步和淘汰历史记录 (每个文件单独记录)
- 修复 saveSyncHistory 失败路径未调用的 bug
- 配置添加后自动建立索引
- getIndexStats 超时修复 (10s → 30s)

### 实现思路
用户要求同步历史记录到每一个文件，而不是任务级别。创建 `ServiceSyncFileRecord` ObjectBox 实体，status 字段统一覆盖同步和淘汰操作:
- 0=同步成功, 1=同步失败, 2=跳过, 3=淘汰成功, 4=淘汰失败

同步循环中使用批量写入 (batch size=100) 提升性能，避免逐条写入影响 500K+ 文件的同步速度。

### 修改文件
| 文件 | 修改内容 |
|------|----------|
| `ServiceDatabaseManager.swift` | 新增 ServiceSyncFileRecord 实体 + CRUD 方法 |
| `SyncManager.swift` | 同步循环中批量记录文件级操作 + saveSyncHistory 失败路径修复 |
| `EvictionManager.swift` | 淘汰操作记录到 ServiceSyncFileRecord |
| `DMSAServiceProtocol.swift` | 新增 dataGetSyncFileRecords/dataGetAllSyncFileRecords |
| `ServiceImplementation.swift` | 实现上述 XPC 方法 |
| `XPCClientTypes.swift` | App 端 SyncFileRecord 模型 |
| `ServiceClient.swift` | getSyncFileRecords/getAllSyncFileRecords + rebuildIndex |
| `DashboardView.swift` | 新增文件同步记录列表 (FileRecordRow) |
| `EntityInfo-*.generated.swift` | 手动添加 ServiceSyncFileRecord ObjectBox 绑定 |
| `Localizable.strings` (en/zh) | dashboard.fileHistory 相关键 |
| `DisksPage.swift` | 添加同步对后自动触发索引重建 |

### 问题与解决
1. **saveSyncHistory 失败路径 bug**: catch 块中 throw 在 saveSyncHistory 之前，导致失败时历史不记录。修复: 在 catch 块中也调用 saveSyncHistory
2. **getIndexStats 超时**: 506K 文件响应需 18s，10s 默认超时不够。修复: 增加到 30s
3. **ObjectBox EntityInspectable**: 新实体需要手动添加生成的绑定代码 (entity ID=4, index ID 7-10)

### 编译结果
- ✅ BUILD SUCCEEDED

---

*文档维护: 每次会话结束时追加新的会话记录*
