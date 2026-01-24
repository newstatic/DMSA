# DMSA v4.1 实施计划

> 基于 Code Review 报告的优先级排序
> 版本: 4.1 | 更新日期: 2026-01-24

---

## 目录

1. [当前状态](#1-当前状态)
2. [P0 - 必须修复](#2-p0---必须修复)
3. [P1 - 重要改进](#3-p1---重要改进)
4. [P2 - 可选优化](#4-p2---可选优化)
5. [依赖关系图](#5-依赖关系图)
6. [里程碑规划](#6-里程碑规划)

---

## 1. 当前状态

### 1.1 已完成 ✅

| 模块 | 完成度 | 说明 |
|------|--------|------|
| 双进程架构 | 100% | DMSAApp + DMSAService |
| 统一 XPC 协议 | 100% | DMSAServiceProtocol |
| ServiceClient | 100% | 统一 XPC 客户端 |
| VFSManager (骨架) | 80% | Actor 实现，缺 FUSE 集成 |
| SyncManager | 80% | 基础同步逻辑完成 |
| PrivilegedOperations | 100% | 目录保护、ACL 管理 |
| 配置管理 | 100% | AppConfig + ConfigManager |
| 日志系统 | 100% | Logger 多模块支持 |

### 1.2 待实现 ❌

| 模块 | 完成度 | 阻塞原因 |
|------|--------|----------|
| macFUSE 集成 | 0% | VFSFileSystem 仅模拟 |
| TreeVersionManager | 0% | 未开始实现 |
| EvictionManager | 0% | 未开始实现 |
| DELETED 状态处理 | 0% | 未开始实现 |
| 冲突解决 UI | 0% | 未开始实现 |

---

## 2. P0 - 必须修复

### 2.1 macFUSE 实际集成

**目标**: 让 VFSFileSystem 真正通过 macFUSE 挂载虚拟文件系统

**涉及文件**:
- `DMSAService/VFS/VFSFileSystem.swift`
- `DMSAApp/DMSAApp-Bridging-Header.h`
- `DMSAApp/Services/VFS/DMSAFileSystem.swift` (已有部分实现)

**实施步骤**:

```
步骤 1: 确认 macFUSE Framework 配置
├── 检查 /Library/Frameworks/macFUSE.framework 存在
├── 确认 Xcode Build Settings:
│   ├── Framework Search Paths: /Library/Frameworks
│   └── LD_RUNPATH_SEARCH_PATHS: /Library/Frameworks
└── 验证 Bridging Header 导入 <macFUSE/macFUSE.h>

步骤 2: 在 DMSAService 中实现 FUSE 委托
├── 创建 FUSEFileSystemDelegate 类
├── 实现 GMUserFileSystem 委托方法:
│   ├── contentsOfDirectoryAtPath:error:
│   ├── attributesOfItemAtPath:userData:error:
│   ├── openFileAtPath:mode:userData:error:
│   ├── readFileAtPath:userData:buffer:size:offset:error:
│   ├── writeFileAtPath:userData:buffer:size:offset:error:
│   ├── createFileAtPath:attributes:userData:error:
│   ├── removeItemAtPath:error:
│   └── moveItemAtPath:toPath:error:
└── 确保所有方法调用 VFSFileSystem 的对应逻辑

步骤 3: 修改 VFSFileSystem.mount()
├── 创建 GMUserFileSystem 实例
├── 设置挂载选项:
│   ├── volname=DMSA
│   ├── allow_other
│   └── default_permissions
├── 调用 [fs mountAtPath:withOptions:]
└── 处理挂载错误

步骤 4: 修改 VFSFileSystem.unmount()
├── 调用 [fs unmount]
└── 清理资源

步骤 5: 测试验证
├── 挂载 ~/Downloads 虚拟目录
├── 验证文件列表显示 (智能合并)
├── 验证读取路由 (LOCAL > EXTERNAL)
├── 验证写入路由 (写入 LOCAL_DIR)
└── 验证卸载功能
```

**验收标准**:
- [ ] `ls ~/Downloads` 显示合并后的文件列表
- [ ] 读取 EXTERNAL_ONLY 文件成功
- [ ] 写入文件到 LOCAL_DIR 成功
- [ ] 卸载后 ~/Downloads 恢复正常

---

### 2.2 TreeVersionManager 实现

**目标**: 实现文件树版本控制，启动时检测变更

**涉及文件**:
- 新建 `DMSAService/VFS/TreeVersionManager.swift`
- 新建 `DMSAShared/Models/TreeVersion.swift`
- 修改 `DMSAService/VFS/VFSManager.swift`

**实施步骤**:

```
步骤 1: 定义数据模型
├── TreeVersion 结构体:
│   ├── version: String (UUID)
│   ├── timestamp: Date
│   ├── fileCount: Int
│   ├── totalSize: Int64
│   └── entries: [String: FileEntryMeta]
└── FileEntryMeta 结构体:
    ├── hash: String (MD5/SHA256)
    ├── size: Int64
    └── modifiedAt: Date

步骤 2: 实现 TreeVersionManager Actor
├── 版本文件路径: .FUSE/db.json
├── readVersionFile(_ path: URL) -> TreeVersion?
├── writeVersionFile(_ version: TreeVersion, to path: URL)
├── checkVersions(for syncPair: SyncPair) -> VersionCheckResult
│   ├── 读取 LOCAL_DIR/.FUSE/db.json
│   ├── 读取 EXTERNAL_DIR/.FUSE/db.json (如果连接)
│   ├── 与 ObjectBox 存储的版本比对
│   └── 返回 needRebuildLocal / needRebuildExternal
├── rebuildTree(for syncPair: SyncPair, source: TreeSource)
│   ├── 扫描目录生成 FileEntry 列表
│   ├── 计算版本 hash
│   ├── 写入版本文件
│   └── 更新 ObjectBox
└── generateTreeVersion() -> String

步骤 3: 集成到 VFSManager
├── 在 mount() 前调用 checkVersions()
├── 根据结果决定是否 rebuildTree()
└── 挂载后注册文件监控

步骤 4: 测试验证
├── 首次启动生成版本文件
├── 重启后版本一致则跳过重建
├── 外部修改后检测到变更并重建
└── 断电恢复场景测试
```

**验收标准**:
- [ ] 首次启动在 LOCAL_DIR/.FUSE/db.json 生成版本文件
- [ ] 重启后版本一致则 < 1s 完成初始化
- [ ] 手动修改文件后重启触发重建

---

## 3. P1 - 重要改进

### 3.1 LRU 淘汰机制 (EvictionManager)

**目标**: 当 LOCAL_DIR 空间不足时，自动淘汰最久未访问的 BOTH 状态文件

**涉及文件**:
- 新建 `DMSAService/VFS/EvictionManager.swift`
- 修改 `DMSAService/VFS/VFSManager.swift`
- 修改 `DMSAService/VFS/VFSFileSystem.swift`

**实施步骤**:

```
步骤 1: 定义淘汰策略
├── 配额: 每个 SyncPair 独立配额 (localQuotaGB)
├── 触发条件: 写入时检查剩余空间 < 阈值 (10%)
├── 淘汰顺序: accessedAt 最早的 BOTH 状态文件
└── 安全检查: 淘汰前验证 EXTERNAL 存在

步骤 2: 实现 EvictionManager Actor
├── checkAndEvict(syncPairId: String, requiredSpace: Int64)
├── getEvictionCandidates(syncPairId: String, count: Int) -> [FileEntry]
│   ├── 筛选条件: location == .both && !isDirty
│   └── 排序: accessedAt ASC
├── evictFile(entry: FileEntry) async throws
│   ├── 验证 EXTERNAL 文件存在
│   ├── 删除 LOCAL 副本
│   └── 更新状态为 EXTERNAL_ONLY
└── getSpaceUsage(syncPairId: String) -> (used: Int64, quota: Int64)

步骤 3: 集成到 VFSFileSystem
├── 在 writeFile() 前调用 checkAndEvict()
└── 淘汰失败时返回 ENOSPC 错误

步骤 4: 测试验证
├── 设置小配额 (100MB) 测试淘汰触发
├── 验证只淘汰 BOTH 状态文件
├── 验证 LOCAL_ONLY 和脏文件不被淘汰
└── 验证 EXTERNAL 离线时跳过淘汰
```

**验收标准**:
- [ ] 空间不足时自动淘汰旧文件
- [ ] LOCAL_ONLY 文件永不被淘汰
- [ ] 脏文件永不被淘汰
- [ ] 淘汰后文件仍可从 EXTERNAL 读取

---

### 3.2 文件索引持久化

**目标**: 将 VFSManager.fileIndex 持久化到 ObjectBox，避免重启丢失

**涉及文件**:
- 修改 `DMSAApp/DMSAApp/Models/Entities/FileEntry.swift`
- 修改 `DMSAService/VFS/VFSManager.swift`

**实施步骤**:

```
步骤 1: 确认 FileEntry ObjectBox 实体
├── 添加 @Entity 注解
├── 添加 @Id 属性
├── 添加索引: virtualPath + syncPairId
└── 确认所有字段支持 Codable

步骤 2: 修改 VFSManager
├── buildIndex() 后保存到 ObjectBox
├── mount() 时优先从 ObjectBox 加载
├── onFileWritten/onFileDeleted 同步更新 ObjectBox
└── 添加 syncIndexToDatabase() 方法

步骤 3: 测试验证
├── 重启后索引保留
├── 大量文件 (10000+) 性能测试
└── 并发写入测试
```

**验收标准**:
- [ ] 重启后文件索引保留
- [ ] 10000 文件索引加载 < 1s
- [ ] 并发写入不丢失数据

---

### 3.3 DELETED 状态处理

**目标**: 实现外部删除检测和 DELETED 状态转换

**涉及文件**:
- 修改 `DMSAShared/Models/FileLocation.swift`
- 修改 `DMSAService/VFS/VFSManager.swift`
- 修改 `DMSAService/VFS/VFSFileSystem.swift`

**实施步骤**:

```
步骤 1: 添加 DELETED 状态
├── FileLocation.deleted case
└── 更新所有 switch 语句

步骤 2: 实现检测逻辑
├── 在 buildIndex() 中检测:
│   └── 如果数据库有记录但 EXTERNAL 不存在 → 标记 DELETED
├── 在 readDirectory() 中:
│   └── DELETED 文件显示但标记为不可访问
└── 在 readFile() 中:
    └── DELETED 文件返回 ENOENT

步骤 3: 实现清理逻辑
├── 用户删除 DELETED 文件 → 从数据库移除记录
└── EXTERNAL 重新出现 → 恢复为 EXTERNAL_ONLY

步骤 4: 测试验证
├── 外部删除文件后重启检测到 DELETED
├── DELETED 文件无法读取
├── 用户删除 DELETED 文件成功
└── EXTERNAL 恢复后状态正确更新
```

**验收标准**:
- [ ] 外部删除后显示 DELETED 状态
- [ ] DELETED 文件读取返回错误
- [ ] 用户可删除 DELETED 记录

---

### 3.4 同步任务持久化

**目标**: 将 SyncManager.pendingTasks 和 dirtyFiles 持久化，避免重启丢失

**涉及文件**:
- 新建 `DMSAShared/Models/Entities/SyncTask.swift`
- 修改 `DMSAService/Sync/SyncManager.swift`

**实施步骤**:

```
步骤 1: 定义 SyncTask 实体
├── id: String
├── syncPairId: String
├── files: [String]
├── status: SyncStatus
├── scheduledAt: Date
└── priority: Int

步骤 2: 修改 SyncManager
├── scheduleFileSync() 保存到数据库
├── startScheduler() 加载未完成任务
├── 任务完成后从数据库删除
└── 服务重启后恢复任务

步骤 3: 测试验证
├── 服务重启后恢复待同步文件
├── 大量脏文件 (1000+) 不丢失
└── 异常退出后恢复测试
```

**验收标准**:
- [ ] 服务重启后待同步文件保留
- [ ] 异常退出后恢复同步队列

---

## 4. P2 - 可选优化

### 4.1 XPC 心跳检测

**实施步骤**:
```
├── ServiceClient 添加 startHeartbeat() 方法
├── 每 30s 调用 healthCheck()
├── 连续 3 次失败触发重连
└── 通知 UI 显示连接状态
```

---

### 4.2 冲突解决 UI

**实施步骤**:
```
├── 定义 ConflictInfo 模型
├── 创建 ConflictResolutionView (SwiftUI)
├── 显示两端文件信息 (大小、修改时间)
├── 提供选项: 保留本地 / 保留外部 / 保留两者
└── 冲突解决后触发同步
```

---

### 4.3 大文件分块处理

**实施步骤**:
```
├── 定义分块大小 (64MB)
├── 实现分块 hash 校验
├── 实现断点续传逻辑
└── 进度回调支持
```

---

### 4.4 首次设置向导

**实施步骤**:
```
├── 检测 ~/Downloads 是否存在
├── 引导用户确认重命名
├── 自动配置首个 SyncPair
└── 完成后启动 VFS
```

---

## 5. 依赖关系图

```
                    ┌─────────────────────────────┐
                    │   P0: macFUSE 集成          │
                    │   (VFSFileSystem.mount)     │
                    └─────────────────────────────┘
                                  │
                                  ▼
          ┌───────────────────────┴───────────────────────┐
          │                                               │
          ▼                                               ▼
┌─────────────────────────┐               ┌─────────────────────────┐
│  P0: TreeVersionManager │               │  P1: EvictionManager    │
│  (版本控制)              │               │  (LRU 淘汰)             │
└─────────────────────────┘               └─────────────────────────┘
          │                                               │
          ▼                                               ▼
┌─────────────────────────┐               ┌─────────────────────────┐
│  P1: 索引持久化          │               │  P1: DELETED 状态       │
│  (ObjectBox)            │               │  (外部删除检测)          │
└─────────────────────────┘               └─────────────────────────┘
          │                                               │
          └───────────────────────┬───────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │  P1: 同步任务持久化          │
                    │  (重启恢复)                  │
                    └─────────────────────────────┘
                                  │
                                  ▼
          ┌───────────────────────┴───────────────────────┐
          │                       │                       │
          ▼                       ▼                       ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ P2: XPC 心跳    │   │ P2: 冲突解决 UI │   │ P2: 大文件分块  │
└─────────────────┘   └─────────────────┘   └─────────────────┘
```

---

## 6. 里程碑规划

### Milestone 1: VFS 核心功能 (P0)
**目标**: 完成 macFUSE 集成和版本控制

| 任务 | 依赖 |
|------|------|
| macFUSE 集成 | 无 |
| TreeVersionManager | macFUSE |

**验收标准**:
- VFS 挂载成功，文件可读写
- 版本文件正确生成和检测

---

### Milestone 2: 数据安全 (P1)
**目标**: 完成淘汰机制和持久化

| 任务 | 依赖 |
|------|------|
| EvictionManager | Milestone 1 |
| 索引持久化 | Milestone 1 |
| DELETED 状态 | Milestone 1 |
| 同步任务持久化 | 无 |

**验收标准**:
- 空间不足时自动淘汰
- 重启后数据不丢失
- 外部删除正确检测

---

### Milestone 3: 用户体验 (P2)
**目标**: 完善交互和可靠性

| 任务 | 依赖 |
|------|------|
| XPC 心跳 | 无 |
| 冲突解决 UI | Milestone 2 |
| 大文件分块 | Milestone 2 |
| 首次设置向导 | 无 |

**验收标准**:
- 连接断开有提示
- 冲突可手动解决
- 大文件传输可靠

---

## 附录: 快速命令

```bash
# 编译 DMSAApp
cd /Users/ttttt/Documents/xcodeProjects/DMSA/DMSAApp
xcodebuild -scheme DMSAApp -configuration Debug build

# 编译 DMSAService
xcodebuild -target "com.ttttt.dmsa.service" -configuration Debug build

# 查看日志
tail -f ~/Library/Logs/DMSA/app.log

# 检查 macFUSE
ls -la /Library/Frameworks/macFUSE.framework

# 检查服务状态 (macOS 13+)
launchctl print system/com.ttttt.dmsa.service
```

---

*文档生成时间: 2026-01-24*
