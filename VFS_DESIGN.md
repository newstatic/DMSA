# DMSA 虚拟文件系统 (VFS) 设计文档

> 版本: 3.1 | 更新日期: 2026-01-24

---

## 目录

1. [概述](#1-概述)
2. [核心概念](#2-核心概念)
3. [技术方案选型](#3-技术方案选型)
4. [系统架构](#4-系统架构)
5. [文件状态管理](#5-文件状态管理)
   - [5.4 核心数据约束：EXTERNAL 是完整数据源](#54-核心数据约束external-是完整数据源)
   - [5.5 DELETED 状态处理](#55-deleted-状态处理)
6. [文件树版本控制](#6-文件树版本控制)
7. [智能合并视图](#7-智能合并视图)
8. [读取路由器](#8-读取路由器-readrouter)
9. [写入路由器](#9-写入路由器-writerouter)
10. [删除路由器](#10-删除路由器-deleterouter)
11. [本地存储淘汰机制](#11-本地存储淘汰机制)
12. [同步锁定机制](#12-同步锁定机制)
13. [冲突解决机制](#13-冲突解决机制)
14. [多路同步架构](#14-多路同步架构)
15. [目录处理](#15-目录处理)
16. [大文件处理](#16-大文件处理)
17. [权限与特殊文件](#17-权限与特殊文件)
18. [EXTERNAL 断开处理](#18-external-断开处理)
19. [应用生命周期](#19-应用生命周期)
20. [数据模型与存储](#20-数据模型与存储)
21. [错误处理](#21-错误处理)
22. [性能优化](#22-性能优化)
23. [特权助手工具 (SMJobBless)](#23-特权助手工具-smjobbless)

---

## 1. 概述

### 1.1 设计目标

VFS (Virtual File System) 层是 DMSA 的核心组件，负责在 **LOCAL_DIR** (本地目录) 和 **EXTERNAL_DIR** (外部目录) 之间透明地路由文件操作，支持**多路同步**。

**核心目标:**
- 用户通过虚拟目录访问文件（每个 LOCAL_DIR 一个挂载点）
- 智能合并显示本地和外部目录的文件
- **单向同步**: LOCAL → EXTERNAL（EXTERNAL 作为备份）
- **多路同步**: 支持多个 `LOCAL_DIR ↔ EXTERNAL_DIR` 同步对
- EXTERNAL_ONLY 文件直接重定向读取，不复制到本地
- Write-Back 策略确保写入性能
- 基于 LRU 的本地存储淘汰机制
- 离线时仍可访问本地数据
- **文件系统保护**: FUSE 拦截直接访问，禁止直接修改 LOCAL_DIR 和 EXTERNAL_DIR

### 1.2 设计原则

| 原则 | 说明 |
|------|------|
| **透明性** | 用户看到统一的虚拟目录，不感知底层存储位置 |
| **智能合并** | 虚拟目录显示两端文件的合集 |
| **单向同步** | LOCAL → EXTERNAL，EXTERNAL 是只读备份 |
| **零拷贝读取** | EXTERNAL_ONLY 文件直接重定向读取，不产生本地副本 |
| **性能优先** | 读写优先使用本地存储，减少 I/O 延迟 |
| **空间管理** | LRU 淘汰策略自动管理本地存储空间（每个 LOCAL_DIR 独立配额）|
| **数据安全** | 确保数据一致性，冲突时 LOCAL 优先 |
| **离线可用** | EXTERNAL 离线时，本地数据仍可正常访问 |
| **文件系统保护** | 禁止直接修改 LOCAL_DIR 和 EXTERNAL_DIR，只能通过虚拟目录操作 |

### 1.3 v3.0 更新内容

| 变更项 | 旧设计 (v2.x) | 新设计 (v3.0) |
|--------|---------------|---------------|
| 同步架构 | 单一 EXTERNAL 硬盘 | 多路同步 (LOCAL_DIR ↔ EXTERNAL_DIR) |
| 同步方向 | 未明确 | 单向 LOCAL → EXTERNAL |
| 文件状态 | 4 种状态 | 5 种状态 (新增 DELETED) |
| 删除流程 | 未详细设计 | 完整三阶段删除机制 |
| 冲突解决 | 简单表格 | 完整冲突解决流程 + UI |
| 大文件 | 无特殊处理 | 分块校验 + 断点续传 |
| 文件系统保护 | 无 | FUSE 拦截直接访问 |
| 目录处理 | 未详细说明 | 完整目录同步/淘汰策略 |

---

## 2. 核心概念

### 2.1 同步对 (SyncPair)

DMSA 使用**同步对**的概念，每个同步对定义一个 `LOCAL_DIR ↔ EXTERNAL_DIR` 的一对一关系。

```swift
struct SyncPair {
    let id: UUID
    let localDir: URL        // LOCAL_DIR: 本地目录 (如 ~/Downloads_Local)
    let externalDir: URL     // EXTERNAL_DIR: 外部目录 (如 /Volumes/BACKUP/Downloads)
    let targetDir: URL       // TARGET_DIR: 用户访问入口 (如 ~/Downloads)
    var localQuotaGB: Int    // 本地配额 (GB)
    var enabled: Bool
}
```

**示例配置:**
```
同步对 1: ~/Downloads_Local ↔ /Volumes/BACKUP/Downloads   → 挂载 ~/Downloads
同步对 2: ~/Documents_Local ↔ /Volumes/NAS/Documents      → 挂载 ~/Documents
同步对 3: ~/Projects_Local ↔ /Volumes/PORTABLE/Projects   → 挂载 ~/Projects
```

### 2.2 目录角色与术语定义

本文档统一使用以下术语：

| 术语 | 示例路径 | 说明 |
|------|----------|------|
| **LOCAL_DIR** | `~/Downloads_Local` | 本地实际存储目录，用户不直接访问，存储热数据 |
| **EXTERNAL_DIR** | `/Volumes/BACKUP/Downloads/` | 外部备份目录，完整数据源 (Source of Truth) |
| **TARGET_DIR** | `~/Downloads` | FUSE 挂载点，用户唯一访问入口，显示合并视图 |

**术语映射:**
```
~/Downloads         → TARGET_DIR   (用户看到的目标目录)
~/Downloads_Local   → LOCAL_DIR    (本地热数据缓存)
/Volumes/BACKUP/Downloads → EXTERNAL_DIR (外部完整备份)
```

**为什么叫 TARGET_DIR:**
- 这是用户操作的**目标目录** (Target Directory)
- 用户的所有文件操作都以此目录为目标
- VFS 层将操作路由到 LOCAL_DIR 或 EXTERNAL_DIR

### 2.3 同步方向

**单向同步: LOCAL → EXTERNAL**

```
┌───────────────────────────────────────────────────────────────┐
│                         用户操作                               │
│                     (通过 TARGET_DIR)                          │
└───────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌───────────────────────────────────────────────────────────────┐
│                       VFS 层 (FUSE)                            │
│                     智能路由 + 访问控制                         │
└───────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│       LOCAL_DIR          │     │      EXTERNAL_DIR        │
│     (读写，热数据)        │ ──▶ │     (只读备份)            │
│   ~/Downloads_Local      │同步  │  /Volumes/BACKUP/       │
└─────────────────────────┘     └─────────────────────────┘
        ⬆ 禁止直接访问                  ⬆ 禁止直接访问
```

**关键点:**
- 写入总是先到 LOCAL_DIR，然后异步同步到 EXTERNAL_DIR
- EXTERNAL_DIR 是只读备份，不会反向同步到 LOCAL
- EXTERNAL_DIR 新增的文件会显示在合并视图中（EXTERNAL_ONLY 状态）
- 用户**不能**直接访问 LOCAL_DIR 或 EXTERNAL_DIR，必须通过 TARGET_DIR

### 2.4 文件系统保护机制

**FUSE 拦截直接访问:**

```
用户尝试直接访问 ~/Downloads_Local
         │
         ▼
┌─────────────────────────────────────┐
│     DMSA 系统监控检测到访问           │
│  (或 FUSE 挂载覆盖原目录)            │
└─────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│     拒绝访问 / 重定向到 TARGET_DIR    │
│     显示警告: "请通过 ~/Downloads 访问"│
└─────────────────────────────────────┘
```

**实现方式:**
1. 将 LOCAL_DIR 设为隐藏目录（以 `.` 开头或使用 chflags hidden）
2. FUSE 挂载在原始路径（如 `~/Downloads`）
3. 原始数据移动到 LOCAL_DIR（如 `~/.Downloads_Local`）

### 2.5 首次设置流程

```
1. 用户配置同步对
         │
         ▼
2. 对于每个同步对:
         │
    ┌────┴────┐
    ▼         ▼
 目录存在     不存在
    │           │
    ▼           ▼
3. 重命名为     创建
   LOCAL_DIR    LOCAL_DIR
         │
         ▼
4. 创建 FUSE 挂载点 TARGET_DIR
         │
         ▼
5. 挂载 VFS，开始智能合并
         │
         ▼
6. 检测 EXTERNAL_DIR 可访问性
         │
    ┌────┴────┐
    ▼         ▼
 可访问      不可访问
    │           │
    ▼           ▼
 扫描并      仅显示
 合并显示    LOCAL 数据
```

---

## 3. 技术方案选型

### 3.1 方案对比

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **FUSE-T** | 纯用户态，无需内核扩展 | 较新，社区较小 | macOS 原生支持受限环境 |
| **macFUSE** | 灵活，完全控制文件系统行为 | 需要第三方内核扩展 | 需要自定义文件系统 |
| **FSKit** | Apple 官方 API (macOS 15+) | 仅支持新系统 | 新版 macOS 应用 |
| **FileProvider** | Apple 推荐，云存储标准 | 主要用于云同步，限制较多 | iCloud 类应用 |

### 3.2 选定方案: FUSE-T (推荐)

**选择理由:**

1. **无内核扩展**: 纯用户态实现，安装简单
2. **完全控制**: 可以拦截所有文件操作 (open, read, write, create, delete)
3. **智能合并**: 可以动态合并 Downloads_Local 和 EXTERNAL 的内容
4. **透明路由**: 可以动态决定从哪个位置读取
5. **重定向支持**: 支持直接重定向到 EXTERNAL 读取

**依赖:**
- [FUSE-T](https://www.fuse-t.org/) - 推荐，kext-less 实现，使用 NFS v4 本地服务器
- [macFUSE](https://macfuse.github.io/) - 备选

### 3.3 存储层: ObjectBox

**选择理由:**

1. **高性能**: 针对移动/嵌入式设备优化，低延迟
2. **自动迁移**: 自动 schema 迁移，无需手动脚本
3. **类型安全**: 编译时检查，Swift 原生支持
4. **关系支持**: 内置对象关系 (ToOne, ToMany)
5. **索引支持**: 属性索引加速查询

**依赖:**
```swift
// Swift Package Manager
.package(url: "https://github.com/objectbox/objectbox-swift-spm.git", from: "5.1.0")
```

### 3.4 系统架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户应用层                                │
│                    (Finder, Safari, etc.)                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 文件操作 (open, read, write...)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     VFS 挂载点                                   │
│                  ~/Downloads (FUSE-T 挂载)                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ FUSE 回调
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DMSA VFS 核心                                 │
│  ┌─────────────┬─────────────┬─────────────┬─────────────┐     │
│  │ ReadRouter  │ WriteRouter │ MergeEngine │EvictionMgr │     │
│  └─────────────┴─────────────┴─────────────┴─────────────┘     │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 ObjectBox 存储层                          │   │
│  │              (FileEntry, SyncHistory, etc.)              │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│    Downloads_Local       │     │      EXTERNAL 后端       │
│   ~/Downloads_Local      │     │   /Volumes/BACKUP/      │
│   (热数据，可淘汰)        │     │   Downloads/ (完整数据)  │
└─────────────────────────┘     └─────────────────────────┘
```

---

## 4. 系统架构

### 4.1 核心组件

```
┌─────────────────────────────────────────────────────────────────┐
│                        VFSCore                                  │
│                    (FUSE 操作入口)                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   MergeEngine   │  │   ReadRouter    │  │   WriteRouter   │ │
│  │  (智能合并引擎)  │  │  (读取路由)      │  │  (写入路由)      │ │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘ │
│           │                    │                    │          │
│  ┌────────┴────────────────────┴────────────────────┴────────┐ │
│  │                    EvictionManager                         │ │
│  │                   (LRU 淘汰管理器)                          │ │
│  └────────────────────────────┬───────────────────────────────┘ │
│                               │                                 │
│                               ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    LockManager                           │   │
│  │                   (同步锁管理)                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                               │                                 │
│                               ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                ObjectBox Store                           │   │
│  │               (数据持久层)                                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 组件职责

| 组件 | 职责 |
|------|------|
| **VFSCore** | FUSE 操作入口，实现 FUSE 回调函数 |
| **MergeEngine** | 合并 Downloads_Local 和 EXTERNAL 的目录列表 |
| **ReadRouter** | 读取路由决策，重定向到正确的存储位置 |
| **WriteRouter** | 写入路由，实现 Write-Back 策略 |
| **EvictionManager** | LRU 淘汰管理，维护本地存储空间 |
| **LockManager** | 同步锁管理，处理正在同步的文件 |
| **ObjectBox Store** | 文件元数据持久化 |

---

## 5. 文件状态管理

### 5.1 文件位置状态 (FileLocation)

```swift
enum FileLocation: Int, Codable {
    case notExists = 0      // 文件不存在
    case localOnly = 1      // 仅在 LOCAL_DIR (待同步)
    case externalOnly = 2   // 仅在 EXTERNAL_DIR (可直接读取)
    case both = 3           // 两端都有 (已同步)
    case deleted = 4        // 已删除 (EXTERNAL 被外部删除，本地无数据)
}
```

### 5.2 状态转换图 (v3.0)

```
                         ┌─────────────────┐
                         │   NOT_EXISTS    │
                         └────────┬────────┘
                                  │
           ┌──────────────────────┼──────────────────────┐
           │                      │                      │
           │ 本地创建              │ 外部发现              │
           ▼                      ▼                      ▼
     ┌───────────┐         ┌───────────┐          ┌───────────┐
     │LOCAL_ONLY │         │EXTERNAL_  │          │   BOTH    │
     │ (isDirty) │         │   ONLY    │          │           │
     └─────┬─────┘         └─────┬─────┘          └─────┬─────┘
           │                     │                      │
           │    同步完成          │                      │
           └─────────►┌──────────┴──────────┐◄──────────┘
                      │        BOTH         │
                      └──────────┬──────────┘
                                 │
           ┌─────────────────────┼─────────────────────┐
           │                     │                     │
           │ 本地淘汰             │ 外部被删除           │ 用户删除
           ▼                     │                     ▼
     ┌───────────┐               │              ┌───────────┐
     │EXTERNAL_  │               │              │NOT_EXISTS │
     │   ONLY    │               │              │ (移除记录) │
     └─────┬─────┘               │              └───────────┘
           │                     │
           │ 外部被删除           │
           ▼                     ▼
     ┌───────────┐         ┌───────────┐
     │  DELETED  │◄────────│LOCAL_ONLY │
     │ (拒绝访问) │  本地无   │ (等待重同步)│
     └───────────┘  数据时   └───────────┘
           │                     ▲
           │ 用户删除             │ 本地有数据时
           ▼                     │
     ┌───────────┐               │
     │NOT_EXISTS │───────────────┘
     │ (移除记录) │
     └───────────┘
```

**EXTERNAL 被外部删除的处理逻辑:**
- 如果本地有数据 (`BOTH` → `LOCAL_ONLY`)：保留本地数据，等待重新同步
- 如果本地无数据 (`EXTERNAL_ONLY` → `DELETED`)：标记为已删除，拒绝访问
- `DELETED` 状态文件会在目录列表中显示，但访问时返回错误
- 用户可以通过虚拟目录删除 `DELETED` 记录，从数据库中完全移除

### 5.3 状态说明

| 状态 | 说明 | 读取行为 | 淘汰策略 | 删除行为 |
|------|------|----------|----------|----------|
| `LOCAL_ONLY` | 新文件，待同步 | 从本地读取 | 不可淘汰 | 直接删除本地+记录 |
| `EXTERNAL_ONLY` | 仅在外部目录 | 直接重定向读取 | 不适用 | 标记删除，在线时同步删除 |
| `BOTH` | 已同步 | 优先本地读取 | 可淘汰 | 三阶段删除 |
| `DELETED` | 外部被删除 | 返回错误 | 不适用 | 移除数据库记录 |

### 5.4 核心数据约束：EXTERNAL 是完整数据源

#### 5.4.1 设计原则

**核心约束**: Downloads_Local 中的任何文件，最终必须在 EXTERNAL 中存在。

```
Downloads_Local ⊆ EXTERNAL (最终一致)
```

**含义**:
- **EXTERNAL** 是**完整数据源 (Source of Truth)**
- **Downloads_Local** 是**热数据缓存**，是 EXTERNAL 的子集
- **LOCAL_ONLY** 是**临时状态**，允许延迟同步，但必须最终同步到 EXTERNAL

#### 5.4.2 状态与约束关系

```
┌─────────────────────────────────────────────────────────────────┐
│                        EXTERNAL (完整数据)                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Downloads_Local (热数据子集)                │   │
│  │                                                          │   │
│  │  LOCAL_ONLY (isDirty)  ──同步──▶  变成 BOTH             │   │
│  │  BOTH                  ──淘汰──▶  变成 EXTERNAL_ONLY     │   │
│  │                                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  EXTERNAL_ONLY (仅在外置硬盘，本地已淘汰或从未拉取)              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

| 状态 | Downloads_Local | EXTERNAL | 约束说明 |
|------|-----------------|----------|----------|
| `LOCAL_ONLY` | ✅ 存在 | ❌ 暂不存在 | **临时状态**，必须最终同步到 EXTERNAL |
| `BOTH` | ✅ 存在 | ✅ 存在 | 正常状态，满足约束 |
| `EXTERNAL_ONLY` | ❌ 不存在 | ✅ 存在 | 正常状态，满足约束 |

#### 5.4.3 延迟同步策略

**允许延迟，但必须同步**:

```
新文件写入                                    最终状态
    │                                           │
    ▼                                           ▼
┌─────────┐     延迟同步（允许）      ┌─────────┐
│LOCAL_ONLY│ ─────────────────────▶ │  BOTH   │
│ isDirty  │    (秒/分钟/小时...)     │         │
└─────────┘                         └─────────┘
    │                                    │
    │ 不允许永久停留                       │ 可以淘汰
    │                                    ▼
    ✗                              ┌───────────┐
                                   │EXTERNAL_  │
                                   │   ONLY    │
                                   └───────────┘
```

**同步触发时机**:

| 触发条件 | 说明 |
|----------|------|
| **EXTERNAL 连接时** | 外置硬盘挂载后，自动开始同步队列中的脏数据 |
| **定时同步** | 每隔 N 分钟检查并同步（可配置） |
| **手动触发** | 用户点击"立即同步" |
| **应用退出前** | 尝试同步所有脏数据（如果 EXTERNAL 在线） |
| **空间不足淘汰前** | 必须先确保文件已同步，才能淘汰本地副本 |

#### 5.4.4 写入流程 (Write-Back with Delayed Sync)

```
用户写入文件
     │
     ▼
写入 Downloads_Local ──▶ 立即返回成功（低延迟体验）
     │
     ▼
标记 isDirty = true
     │
     ▼
加入同步队列
     │
     ├── EXTERNAL 在线? ──▶ 异步同步 ──▶ isDirty = false, 状态 = BOTH
     │
     └── EXTERNAL 离线? ──▶ 队列等待（允许延迟）
```

#### 5.4.5 淘汰流程 (必须先同步)

```
空间不足，需要淘汰
     │
     ▼
选择候选文件（BOTH 状态 + 最久未访问）
     │
     ▼
检查: 文件真的在 EXTERNAL 存在?
     │
     ├── 存在 ──▶ 删除本地副本 ──▶ 状态变为 EXTERNAL_ONLY ✓
     │
     └── 不存在（异常情况）
           │
           ├── EXTERNAL 在线? ──▶ 先同步过去 ──▶ 再淘汰 ✓
           │
           └── EXTERNAL 离线? ──▶ 跳过此文件，不淘汰 ✗
                                 （保护数据完整性）
```

#### 5.4.6 LOCAL_ONLY 文件保护机制

```swift
/// 检查文件是否可以被淘汰
func canEvict(file: FileEntry) -> Bool {
    // LOCAL_ONLY 文件绝对不能淘汰（会丢数据）
    if file.location == .localOnly {
        return false
    }

    // isDirty 文件不能淘汰（尚未同步）
    if file.isDirty {
        return false
    }

    // BOTH 状态且非脏，可以淘汰
    return file.location == .both
}
```

#### 5.4.7 数据完整性保证

| 场景 | 处理方式 | 数据安全 |
|------|----------|----------|
| 写入后硬盘未连接 | 队列等待，连接后自动同步 | ✅ 安全 |
| 长时间离线 | 本地保留，不淘汰脏数据 | ✅ 安全 |
| 淘汰前检查 | 验证 EXTERNAL 存在才删除本地 | ✅ 安全 |
| 应用崩溃 | 重启后检查 isDirty，继续同步 | ✅ 安全 |

---

## 6. 文件树版本控制

### 6.1 设计目标

文件树版本控制用于解决以下问题：
1. **启动时快速恢复**: 避免每次启动都全量扫描文件系统
2. **增量更新**: 只处理变化的部分，提高效率
3. **一致性检测**: 检测外部修改（如用户直接操作文件系统）
4. **多源同步**: 管理 Downloads_Local 和 EXTERNAL 两个数据源的版本

### 6.2 版本文件设计

#### 6.2.1 版本文件位置

| 数据源 | 版本文件路径 | 说明 |
|--------|--------------|------|
| Downloads_Local | `~/Downloads_Local/.FUSE/db.json` | 本地存储版本信息 |
| EXTERNAL | `/Volumes/{DiskName}/Downloads/.FUSE/db.json` | 外置硬盘版本信息 |
| ObjectBox | 内部存储 `treeVersion` 字段 | 数据库中的版本记录 |

#### 6.2.2 版本文件格式 (.FUSE/db.json)

```json
{
    "version": 1,
    "format": "DMSA_TREE_V1",
    "source": "Downloads_Local",
    "treeVersion": "2026-01-21T10:30:00Z_a1b2c3d4",
    "lastScanAt": "2026-01-21T10:30:00Z",
    "fileCount": 1234,
    "totalSize": 5368709120,
    "checksum": "sha256:abc123...",
    "entries": {
        "file1.pdf": {
            "size": 102400,
            "modifiedAt": "2026-01-20T15:00:00Z",
            "checksum": "sha256:def456..."
        },
        "subdir/": {
            "isDirectory": true,
            "modifiedAt": "2026-01-19T12:00:00Z"
        },
        "subdir/doc.txt": {
            "size": 2048,
            "modifiedAt": "2026-01-19T12:00:00Z",
            "checksum": "sha256:ghi789..."
        }
    }
}
```

#### 6.2.3 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `version` | Int | 文件格式版本号 |
| `format` | String | 格式标识符 |
| `source` | String | 数据源标识 ("Downloads_Local" 或 "EXTERNAL:{diskName}") |
| `treeVersion` | String | 树版本号 (时间戳_随机后缀) |
| `lastScanAt` | ISO8601 | 最后扫描时间 |
| `fileCount` | Int | 文件总数 |
| `totalSize` | Int64 | 总大小 (bytes) |
| `checksum` | String | 整个 entries 的校验和 |
| `entries` | Dict | 文件条目映射 (相对路径 -> 元数据) |

### 6.3 启动时版本检查流程

```
┌──────────────────────────────────────────────────────────────────┐
│                      DMSA 应用启动                                │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                 Step 1: 读取版本文件                              │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ localVersion = read("~/Downloads_Local/.FUSE/db.json")      │ │
│  │   → 成功: 获取 treeVersion                                   │ │
│  │   → 失败: localVersion = null                               │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ externalVersion = read("/Volumes/BACKUP/Downloads/.FUSE/    │ │
│  │                        db.json")                             │ │
│  │   → 成功: 获取 treeVersion                                   │ │
│  │   → 未连接/失败: externalVersion = null                      │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                 Step 2: 查询 ObjectBox 存储的版本                  │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ dbLocalVersion = TreeMeta.get("Downloads_Local").treeVersion│ │
│  │ dbExternalVersion = TreeMeta.get("EXTERNAL").treeVersion    │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                 Step 3: 版本比对                                  │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ LOCAL 比对:                                                  │ │
│  │   localVersion == null         → needRebuildLocal = true    │ │
│  │   localVersion != dbLocalVersion → needRebuildLocal = true  │ │
│  │   localVersion == dbLocalVersion → needRebuildLocal = false │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ EXTERNAL 比对:                                               │ │
│  │   externalVersion == null (未连接) → 跳过 EXTERNAL          │ │
│  │   externalVersion == null (已连接) → needRebuildExt = true  │ │
│  │   externalVersion != dbExtVersion → needRebuildExt = true   │ │
│  │   externalVersion == dbExtVersion → needRebuildExt = false  │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                 Step 4: 执行重建 (如果需要)                        │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ if needRebuildLocal:                                         │ │
│  │   rebuildLocalTree()                                         │ │
│  │   updateLocalVersionFile()                                   │ │
│  │   updateObjectBoxVersion("Downloads_Local", newVersion)      │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ if needRebuildExternal:                                      │ │
│  │   rebuildExternalTree()                                      │ │
│  │   updateExternalVersionFile()                                │ │
│  │   updateObjectBoxVersion("EXTERNAL", newVersion)             │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                 Step 5: VFS 就绪                                  │
│                    可以开始处理文件请求                             │
└──────────────────────────────────────────────────────────────────┘
```

### 6.4 TreeVersionManager 实现

```swift
class TreeVersionManager {
    private let store: Store
    private let treeMetaBox: Box<TreeMeta>
    private let fileEntryBox: Box<FileEntry>

    /// 版本文件名
    static let versionFileName = ".FUSE/db.json"

    // MARK: - 版本检查

    /// 启动时检查版本一致性
    func checkVersionsOnStartup() -> VersionCheckResult {
        var result = VersionCheckResult()

        // 1. 读取 Downloads_Local 版本文件
        let localVersionFile = Paths.downloadsLocal
            .appendingPathComponent(Self.versionFileName)
        result.localFileVersion = readVersionFile(localVersionFile)

        // 2. 读取 EXTERNAL 版本文件 (如果已连接)
        if let externalRoot = DiskManager.shared.currentExternalPath {
            let externalVersionFile = externalRoot
                .appendingPathComponent(Self.versionFileName)
            result.externalFileVersion = readVersionFile(externalVersionFile)
            result.externalConnected = true
        }

        // 3. 读取 ObjectBox 中存储的版本
        result.dbLocalVersion = getStoredVersion(source: "Downloads_Local")
        result.dbExternalVersion = getStoredVersion(source: "EXTERNAL")

        // 4. 比对版本
        result.needRebuildLocal = shouldRebuild(
            fileVersion: result.localFileVersion,
            dbVersion: result.dbLocalVersion
        )

        if result.externalConnected {
            result.needRebuildExternal = shouldRebuild(
                fileVersion: result.externalFileVersion,
                dbVersion: result.dbExternalVersion
            )
        }

        return result
    }

    /// 判断是否需要重建
    private func shouldRebuild(fileVersion: TreeVersion?, dbVersion: String?) -> Bool {
        // 版本文件不存在 → 需要重建
        guard let fileVersion = fileVersion else {
            return true
        }

        // 数据库版本不存在 → 需要重建
        guard let dbVersion = dbVersion else {
            return true
        }

        // 版本不匹配 → 需要重建
        return fileVersion.treeVersion != dbVersion
    }

    // MARK: - 版本文件读写

    /// 读取版本文件
    func readVersionFile(_ path: URL) -> TreeVersion? {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: path)
            let version = try JSONDecoder().decode(TreeVersion.self, from: data)

            // 验证格式
            guard version.format == "DMSA_TREE_V1" else {
                Logger.warning("Invalid version file format: \(path)")
                return nil
            }

            return version
        } catch {
            Logger.error("Failed to read version file: \(error)")
            return nil
        }
    }

    /// 写入版本文件
    func writeVersionFile(_ version: TreeVersion, to path: URL) throws {
        // 确保 .FUSE 目录存在
        let fuseDir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: fuseDir,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(version)
        try data.write(to: path)

        // 设置隐藏属性 (macOS)
        try FileManager.default.setAttributes(
            [.extensionHidden: true],
            ofItemAtPath: fuseDir.path
        )
    }

    // MARK: - 数据库版本管理

    /// 获取存储的版本
    func getStoredVersion(source: String) -> String? {
        do {
            let query = try treeMetaBox.query {
                TreeMeta.source == source
            }.build()
            return try query.findFirst()?.treeVersion
        } catch {
            return nil
        }
    }

    /// 更新存储的版本
    func updateStoredVersion(source: String, version: String) throws {
        try store.runInTransaction {
            let query = try treeMetaBox.query {
                TreeMeta.source == source
            }.build()

            let meta: TreeMeta
            if let existing = try query.findFirst() {
                meta = existing
            } else {
                meta = TreeMeta()
                meta.source = source
            }

            meta.treeVersion = version
            meta.updatedAt = Date()
            try treeMetaBox.put(meta)
        }
    }

    // MARK: - 生成版本号

    /// 生成新的树版本号
    func generateTreeVersion() -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let random = UUID().uuidString.prefix(8)
        return "\(timestamp)_\(random)"
    }
}
```

### 6.5 树重建流程

```swift
class TreeRebuilder {
    private let store: Store
    private let fileEntryBox: Box<FileEntry>
    private let versionManager: TreeVersionManager

    /// 重建本地文件树
    func rebuildLocalTree() async throws {
        Logger.info("Rebuilding Downloads_Local tree...")

        let startTime = Date()
        let localRoot = Paths.downloadsLocal

        // 1. 清除旧的本地条目
        try clearEntriesForSource(.localOnly)
        try clearEntriesForSource(.both)

        // 2. 扫描文件系统
        var entries: [String: TreeEntry] = [:]
        var fileCount = 0
        var totalSize: Int64 = 0

        let enumerator = FileManager.default.enumerator(
            at: localRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            // 跳过 .FUSE 目录
            if url.path.contains("/.FUSE") {
                continue
            }

            let relativePath = url.path.replacingOccurrences(
                of: localRoot.path + "/",
                with: ""
            )

            let resourceValues = try url.resourceValues(
                forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            )

            let isDirectory = resourceValues.isDirectory ?? false
            let size = Int64(resourceValues.fileSize ?? 0)
            let modifiedAt = resourceValues.contentModificationDate ?? Date()

            // 创建 FileEntry
            let fileEntry = FileEntry()
            fileEntry.virtualPath = relativePath
            fileEntry.localPath = url.path
            fileEntry.location = .localOnly
            fileEntry.size = size
            fileEntry.modifiedAt = modifiedAt
            fileEntry.isDirectory = isDirectory
            fileEntry.accessedAt = Date()

            try fileEntryBox.put(fileEntry)

            // 构建版本文件条目
            entries[relativePath] = TreeEntry(
                size: size,
                modifiedAt: modifiedAt,
                isDirectory: isDirectory
            )

            if !isDirectory {
                fileCount += 1
                totalSize += size
            }
        }

        // 3. 生成并写入版本文件
        let newVersion = versionManager.generateTreeVersion()
        let treeVersion = TreeVersion(
            version: 1,
            format: "DMSA_TREE_V1",
            source: "Downloads_Local",
            treeVersion: newVersion,
            lastScanAt: Date(),
            fileCount: fileCount,
            totalSize: totalSize,
            entries: entries
        )

        let versionPath = localRoot.appendingPathComponent(TreeVersionManager.versionFileName)
        try versionManager.writeVersionFile(treeVersion, to: versionPath)

        // 4. 更新 ObjectBox 版本记录
        try versionManager.updateStoredVersion(source: "Downloads_Local", version: newVersion)

        let duration = Date().timeIntervalSince(startTime)
        Logger.info("Local tree rebuilt: \(fileCount) files, \(totalSize) bytes in \(duration)s")
    }

    /// 重建外部文件树
    func rebuildExternalTree() async throws {
        guard let externalRoot = DiskManager.shared.currentExternalPath else {
            throw VFSError.externalOffline
        }

        Logger.info("Rebuilding EXTERNAL tree...")

        let startTime = Date()

        // 1. 扫描 EXTERNAL
        var entries: [String: TreeEntry] = [:]
        var fileCount = 0
        var totalSize: Int64 = 0

        let enumerator = FileManager.default.enumerator(
            at: externalRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.path.contains("/.FUSE") {
                continue
            }

            let relativePath = url.path.replacingOccurrences(
                of: externalRoot.path + "/",
                with: ""
            )

            let resourceValues = try url.resourceValues(
                forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            )

            let isDirectory = resourceValues.isDirectory ?? false
            let size = Int64(resourceValues.fileSize ?? 0)
            let modifiedAt = resourceValues.contentModificationDate ?? Date()

            // 更新或创建 FileEntry
            try updateOrCreateExternalEntry(
                virtualPath: relativePath,
                externalPath: url.path,
                size: size,
                modifiedAt: modifiedAt,
                isDirectory: isDirectory
            )

            entries[relativePath] = TreeEntry(
                size: size,
                modifiedAt: modifiedAt,
                isDirectory: isDirectory
            )

            if !isDirectory {
                fileCount += 1
                totalSize += size
            }
        }

        // 2. 生成版本文件
        let newVersion = versionManager.generateTreeVersion()
        let treeVersion = TreeVersion(
            version: 1,
            format: "DMSA_TREE_V1",
            source: "EXTERNAL:\(DiskManager.shared.currentDiskName ?? "Unknown")",
            treeVersion: newVersion,
            lastScanAt: Date(),
            fileCount: fileCount,
            totalSize: totalSize,
            entries: entries
        )

        let versionPath = externalRoot.appendingPathComponent(TreeVersionManager.versionFileName)
        try versionManager.writeVersionFile(treeVersion, to: versionPath)

        // 3. 更新 ObjectBox 版本记录
        try versionManager.updateStoredVersion(source: "EXTERNAL", version: newVersion)

        let duration = Date().timeIntervalSince(startTime)
        Logger.info("External tree rebuilt: \(fileCount) files, \(totalSize) bytes in \(duration)s")
    }

    /// 更新或创建外部条目
    private func updateOrCreateExternalEntry(
        virtualPath: String,
        externalPath: String,
        size: Int64,
        modifiedAt: Date,
        isDirectory: Bool
    ) throws {
        try store.runInTransaction {
            let query = try fileEntryBox.query {
                FileEntry.virtualPath == virtualPath
            }.build()

            if let existing = try query.findFirst() {
                // 已存在，更新为 BOTH
                existing.externalPath = externalPath
                if existing.location == .localOnly {
                    existing.location = .both
                }
                try fileEntryBox.put(existing)
            } else {
                // 不存在，创建为 EXTERNAL_ONLY
                let entry = FileEntry()
                entry.virtualPath = virtualPath
                entry.externalPath = externalPath
                entry.location = .externalOnly
                entry.size = size
                entry.modifiedAt = modifiedAt
                entry.isDirectory = isDirectory
                entry.accessedAt = Date()
                try fileEntryBox.put(entry)
            }
        }
    }

    /// 清除指定来源的条目
    private func clearEntriesForSource(_ location: FileLocation) throws {
        let query = try fileEntryBox.query {
            FileEntry.locationRaw == location.rawValue
        }.build()
        try query.remove()
    }
}
```

### 6.6 运行时版本更新

当 VFS 操作修改文件时，**必须同步更新版本**以保证数据一致性：

```swift
extension TreeVersionManager {
    /// 同步更新版本 (必须同步执行，保证一致性)
    ///
    /// 重要: 版本更新必须是同步的原子操作
    /// - 文件系统变更 + 版本文件更新 + ObjectBox 更新 必须作为一个整体
    /// - 任何一步失败都应该回滚或报错
    func updateVersionSync(source: String, operation: () throws -> Void) throws {
        // 1. 执行文件系统操作
        try operation()

        // 2. 同步更新版本 (不能延迟!)
        let newVersion = generateTreeVersion()

        // 3. 更新版本文件
        let path: URL
        if source == "Downloads_Local" {
            path = Paths.downloadsLocal.appendingPathComponent(Self.versionFileName)
        } else if let externalRoot = DiskManager.shared.currentExternalPath {
            path = externalRoot.appendingPathComponent(Self.versionFileName)
        } else {
            throw VFSError.externalOffline
        }

        var version = readVersionFile(path) ?? createEmptyVersion(source: source)
        version.treeVersion = newVersion
        version.lastScanAt = Date()
        try writeVersionFile(version, to: path)

        // 4. 更新 ObjectBox (同步)
        try updateStoredVersion(source: source, version: newVersion)

        Logger.debug("Version updated synchronously: \(source) -> \(newVersion)")
    }

    /// 创建空版本结构
    private func createEmptyVersion(source: String) -> TreeVersion {
        TreeVersion(
            version: 1,
            format: "DMSA_TREE_V1",
            source: source,
            treeVersion: "",
            lastScanAt: Date(),
            fileCount: 0,
            totalSize: 0,
            entries: [:]
        )
    }
}

// 使用示例
extension WriteRouter {
    func handleWriteWithVersionUpdate(_ virtualPath: String, data: Data) -> Result<Void, VFSError> {
        do {
            try versionManager.updateVersionSync(source: "Downloads_Local") {
                // 实际的写入操作
                let localPath = Paths.downloadsLocal.appendingPathComponent(virtualPath).path
                try data.write(to: URL(fileURLWithPath: localPath))
            }
            return .success(())
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }
}
```

**为什么必须同步更新版本:**

| 问题 | 延迟写入的风险 | 同步写入的保证 |
|------|---------------|---------------|
| **崩溃恢复** | 文件已修改但版本未更新，重启后无法检测到变更 | 版本与文件状态一致，重启后正确恢复 |
| **并发操作** | 多个操作的版本更新可能乱序 | 每个操作完成时版本已确定 |
| **外部修改检测** | 无法准确判断何时发生修改 | 版本号精确反映修改时刻 |
| **同步冲突** | 可能丢失冲突检测 | 冲突检测基于准确的版本号 |

### 6.7 数据模型

```swift
/// 版本文件结构
struct TreeVersion: Codable {
    var version: Int
    var format: String
    var source: String
    var treeVersion: String
    var lastScanAt: Date
    var fileCount: Int
    var totalSize: Int64
    var checksum: String?
    var entries: [String: TreeEntry]
}

/// 文件条目 (版本文件中)
struct TreeEntry: Codable {
    var size: Int64
    var modifiedAt: Date
    var isDirectory: Bool
    var checksum: String?

    init(size: Int64 = 0, modifiedAt: Date = Date(), isDirectory: Bool = false, checksum: String? = nil) {
        self.size = size
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.checksum = checksum
    }
}

/// 版本检查结果
struct VersionCheckResult {
    var localFileVersion: TreeVersion?
    var externalFileVersion: TreeVersion?
    var dbLocalVersion: String?
    var dbExternalVersion: String?
    var externalConnected: Bool = false
    var needRebuildLocal: Bool = false
    var needRebuildExternal: Bool = false
}

// objectbox: entity
/// 树元数据 (存储在 ObjectBox)
class TreeMeta: Entity, Identifiable {
    var id: Id = 0

    /// 数据源标识
    // objectbox: index
    var source: String = ""

    /// 树版本号
    var treeVersion: String = ""

    /// 最后更新时间
    var updatedAt: Date = Date()

    /// 文件数量
    var fileCount: Int = 0

    /// 总大小
    var totalSize: Int64 = 0

    required init() {}
}
```

### 6.8 版本一致性保证

| 场景 | 处理方式 |
|------|----------|
| 正常启动 | 版本匹配，直接使用 ObjectBox 数据 |
| 首次启动 | 版本文件不存在，全量扫描重建 |
| 外部修改文件 | 版本不匹配，增量或全量重建 |
| 数据库损坏 | 版本不匹配，全量重建 |
| EXTERNAL 首次连接 | 版本文件不存在，扫描 EXTERNAL |
| EXTERNAL 重新连接 | 比对版本，不匹配则重建 |

---

## 7. 智能合并视图

### 7.1 合并原理

虚拟 `~/Downloads` 显示的是 **Downloads_Local** 和 **EXTERNAL** 的**并集**。

```
Downloads_Local/          EXTERNAL/              虚拟 ~/Downloads/
├── file1.pdf        +    ├── file1.pdf     =    ├── file1.pdf (BOTH)
├── file2.doc             ├── file3.zip          ├── file2.doc (LOCAL_ONLY)
└── subdir/               └── file4.mp4          ├── file3.zip (EXTERNAL_ONLY)
    └── a.txt                                    ├── file4.mp4 (EXTERNAL_ONLY)
                                                 └── subdir/
                                                     └── a.txt (LOCAL_ONLY)
```

### 7.2 FUSE readdir 实现详解

**关键限制 (FUSE-T):** `readdir` 必须在单次调用中返回所有结果。

#### 6.2.1 实现流程

```
┌──────────────────────────────────────────────────────────────────┐
│               用户 ls ~/Downloads/path                            │
│                   或 Finder 打开目录                               │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ FUSE readdir()  │
                    │ 回调触发         │
                    └────────┬────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                    MergeEngine.listDirectory()                    │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ Step 1: 扫描 Downloads_Local                                 │ │
│  │   localFiles = FileManager.contentsOfDirectory(localPath)    │ │
│  │   → 构建 entries[name] = VirtualEntry(.localOnly)           │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                             │                                     │
│                             ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ Step 2: 检查 EXTERNAL 连接状态                               │ │
│  │   if !diskManager.isExternalConnected → 返回当前 entries     │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                             │                                     │
│                             ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ Step 3: 扫描 EXTERNAL                                        │ │
│  │   externalFiles = FileManager.contentsOfDirectory(extPath)   │ │
│  │   for file in externalFiles:                                 │ │
│  │     if entries[file] exists → 更新为 .both                   │ │
│  │     else → 添加 VirtualEntry(.externalOnly)                  │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                             │                                     │
│                             ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ Step 4: 构建 FUSE 响应                                       │ │
│  │   for entry in entries.values:                               │ │
│  │     filler(buf, entry.name, entry.stat, 0)                  │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ 返回完整目录列表 │
                    └─────────────────┘
```

#### 6.2.2 MergeEngine 代码结构

```swift
class MergeEngine {
    private let diskManager: DiskManager
    private let store: Store  // ObjectBox
    private let fileEntryBox: Box<FileEntry>

    /// 获取合并后的目录列表
    /// 注意: FUSE-T 要求一次性返回所有结果
    func listDirectory(_ virtualPath: String) -> [VirtualEntry] {
        var entries: [String: VirtualEntry] = [:]

        // Step 1: 扫描 Downloads_Local
        let localPath = Paths.downloadsLocal.appendingPathComponent(virtualPath).path
        if let localFiles = try? FileManager.default.contentsOfDirectory(atPath: localPath) {
            for fileName in localFiles {
                let fullLocalPath = localPath + "/" + fileName
                let attrs = try? FileManager.default.attributesOfItem(atPath: fullLocalPath)

                entries[fileName] = VirtualEntry(
                    name: fileName,
                    location: .localOnly,
                    localPath: fullLocalPath,
                    externalPath: nil,
                    size: attrs?[.size] as? Int64 ?? 0,
                    modifiedAt: attrs?[.modificationDate] as? Date ?? Date(),
                    isDirectory: (attrs?[.type] as? FileAttributeType) == .typeDirectory
                )
            }
        }

        // Step 2: 扫描 EXTERNAL (如果已连接)
        guard diskManager.isExternalConnected,
              let externalRoot = diskManager.currentExternalPath else {
            return Array(entries.values)
        }

        let externalPath = externalRoot.appendingPathComponent(virtualPath).path
        if let externalFiles = try? FileManager.default.contentsOfDirectory(atPath: externalPath) {
            for fileName in externalFiles {
                let fullExternalPath = externalPath + "/" + fileName
                let attrs = try? FileManager.default.attributesOfItem(atPath: fullExternalPath)

                if var existing = entries[fileName] {
                    // 两端都有 → BOTH
                    existing.location = .both
                    existing.externalPath = fullExternalPath
                    entries[fileName] = existing
                } else {
                    // 仅 EXTERNAL
                    entries[fileName] = VirtualEntry(
                        name: fileName,
                        location: .externalOnly,
                        localPath: nil,
                        externalPath: fullExternalPath,
                        size: attrs?[.size] as? Int64 ?? 0,
                        modifiedAt: attrs?[.modificationDate] as? Date ?? Date(),
                        isDirectory: (attrs?[.type] as? FileAttributeType) == .typeDirectory
                    )
                }
            }
        }

        return Array(entries.values)
    }

    /// FUSE readdir 回调实现
    func fuseReaddir(
        path: String,
        buffer: UnsafeMutableRawPointer,
        filler: @escaping (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<stat>?, off_t) -> Int32
    ) -> Int32 {
        // 添加 . 和 ..
        filler(buffer, ".", nil, 0)
        filler(buffer, "..", nil, 0)

        // 获取合并后的目录列表
        let entries = listDirectory(path)

        for entry in entries {
            var fileStat = stat()
            fileStat.st_mode = entry.isDirectory ? S_IFDIR | 0o755 : S_IFREG | 0o644
            fileStat.st_size = off_t(entry.size)
            fileStat.st_mtime = time_t(entry.modifiedAt.timeIntervalSince1970)

            // FUSE-T 要求: 一次性填充所有条目
            let result = entry.name.withCString { nameCStr in
                filler(buffer, nameCStr, &fileStat, 0)
            }

            if result != 0 {
                // buffer 满了，但 FUSE-T 要求必须返回所有结果
                Logger.error("MergeEngine: readdir buffer full, some entries may be missing")
                break
            }
        }

        return 0  // 成功
    }
}
```

### 7.3 getattr 实现

```swift
extension MergeEngine {
    /// FUSE getattr 回调实现
    func fuseGetattr(path: String, stbuf: UnsafeMutablePointer<stat>) -> Int32 {
        // 根路径
        if path == "/" {
            stbuf.pointee.st_mode = S_IFDIR | 0o755
            stbuf.pointee.st_nlink = 2
            return 0
        }

        // 查找文件位置
        let entry = getEntry(path)

        switch entry.location {
        case .notExists:
            return -ENOENT

        case .localOnly, .both:
            // 从 Downloads_Local 获取属性
            let localPath = Paths.downloadsLocal.appendingPathComponent(path).path
            return getLocalAttr(localPath, stbuf: stbuf)

        case .externalOnly:
            // 从 EXTERNAL 获取属性
            guard diskManager.isExternalConnected,
                  let externalRoot = diskManager.currentExternalPath else {
                return -ENOENT
            }
            let externalPath = externalRoot.appendingPathComponent(path).path
            return getLocalAttr(externalPath, stbuf: stbuf)
        }
    }

    private func getLocalAttr(_ path: String, stbuf: UnsafeMutablePointer<stat>) -> Int32 {
        var s = stat()
        if stat(path, &s) != 0 {
            return -errno
        }
        stbuf.pointee = s
        return 0
    }
}
```

### 7.4 合并冲突处理

当同名文件在两端都存在但内容不同时：

| 场景 | 处理策略 |
|------|----------|
| 修改时间相同 | 内容相同，视为已同步 |
| 本地更新 | 标记 isDirty，待同步到 EXTERNAL |
| 外置更新 | 根据冲突策略处理 (默认: 本地优先+备份) |
| 双端都更新 | 触发冲突解决流程 |

---

## 7. 读取路由器 (ReadRouter)

### 8.1 核心变更: 零拷贝读取

**v2.1 关键变更:** `EXTERNAL_ONLY` 文件**直接重定向读取**，不再复制到本地。

| 文件位置 | v2.0 行为 | v2.1 行为 |
|----------|-----------|-----------|
| `LOCAL_ONLY` | 从本地读取 | 从本地读取 |
| `BOTH` | 从本地读取 | 从本地读取 |
| `EXTERNAL_ONLY` | 拉取到本地再读取 | **直接重定向读取 EXTERNAL** |

### 8.2 读取流程

```
┌──────────────────────────────────────────────────────────────────┐
│                     用户读取文件                                   │
│                 open("~/Downloads/file.pdf")                     │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ 查询文件位置     │
                    │ (MergeEngine)   │
                    └────────┬────────┘
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
    ┌───────────┐     ┌───────────┐      ┌───────────┐
    │LOCAL_ONLY │     │   BOTH    │      │EXTERNAL_  │
    │           │     │           │      │   ONLY    │
    └─────┬─────┘     └─────┬─────┘      └─────┬─────┘
          │                 │                  │
          ▼                 ▼                  ▼
    ┌───────────┐     ┌───────────┐      ┌───────────┐
    │从 Downloads│     │从 Downloads│     │检查 EXTERNAL│
    │_Local 读取 │     │_Local 读取 │     │连接状态     │
    └─────┬─────┘     └─────┬─────┘      └─────┬─────┘
          │                 │                  │
          │                 │            ┌─────┴─────┐
          │                 │            ▼           ▼
          │                 │      ┌──────────┐ ┌──────────┐
          │                 │      │ 已连接   │ │ 未连接   │
          │                 │      └────┬─────┘ └────┬─────┘
          │                 │           │            │
          │                 │           ▼            ▼
          │                 │      ┌──────────┐ ┌──────────┐
          │                 │      │直接重定向 │ │返回错误   │
          │                 │      │读取EXTERN│ │文件不可用 │
          │                 │      │AL (零拷贝)│ └──────────┘
          │                 │      └────┬─────┘
          │                 │           │
          │                 │           │ 更新 accessedAt
          └─────────────────┴───────────┘
                            │
                            ▼
                    ┌─────────────────┐
                    │ 更新访问时间     │
                    │ (LRU 统计)      │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │   返回文件数据   │
                    └─────────────────┘
```

### 8.3 ReadRouter 代码结构

```swift
class ReadRouter {
    private let mergeEngine: MergeEngine
    private let diskManager: DiskManager
    private let lockManager: LockManager
    private let store: Store
    private let fileEntryBox: Box<FileEntry>

    /// 解析读取路径 - 返回实际文件路径
    /// v2.1: EXTERNAL_ONLY 直接返回 EXTERNAL 路径，不复制
    func resolveReadPath(_ virtualPath: String) -> Result<String, VFSError> {
        let entry = mergeEngine.getEntry(virtualPath)

        switch entry.location {
        case .localOnly, .both:
            // 从 Downloads_Local 读取
            let localPath = Paths.downloadsLocal.appendingPathComponent(virtualPath).path
            updateAccessTime(virtualPath)
            return .success(localPath)

        case .externalOnly:
            // v2.1: 直接重定向到 EXTERNAL，不复制
            return resolveExternalPath(virtualPath)

        case .notExists:
            return .failure(.fileNotFound(virtualPath))
        }
    }

    /// 解析 EXTERNAL 路径 (零拷贝)
    private func resolveExternalPath(_ virtualPath: String) -> Result<String, VFSError> {
        guard diskManager.isExternalConnected else {
            return .failure(.externalOffline)
        }

        guard let externalRoot = diskManager.currentExternalPath else {
            return .failure(.externalOffline)
        }

        let externalPath = externalRoot.appendingPathComponent(virtualPath).path

        // 验证文件存在
        guard FileManager.default.fileExists(atPath: externalPath) else {
            return .failure(.fileNotFound(virtualPath))
        }

        // 更新访问时间 (用于统计，不影响淘汰因为不在本地)
        updateAccessTime(virtualPath)

        return .success(externalPath)
    }

    /// 更新文件访问时间 (用于 LRU)
    private func updateAccessTime(_ virtualPath: String) {
        do {
            try store.runInTransaction {
                let query = try fileEntryBox.query {
                    FileEntry.virtualPath == virtualPath
                }.build()

                if let entry = try query.findFirst() {
                    entry.accessedAt = Date()
                    try fileEntryBox.put(entry)
                }
            }
        } catch {
            Logger.warning("ReadRouter: Failed to update access time for \(virtualPath)")
        }
    }
}
```

### 8.4 FUSE open/read 回调

```swift
extension ReadRouter {
    /// FUSE open 回调
    func fuseOpen(path: String, fi: UnsafeMutablePointer<fuse_file_info>) -> Int32 {
        let result = resolveReadPath(path)

        switch result {
        case .success(let actualPath):
            // 打开实际文件
            let fd = open(actualPath, fi.pointee.flags)
            if fd < 0 {
                return -errno
            }
            fi.pointee.fh = UInt64(fd)
            return 0

        case .failure(let error):
            return error.posixErrorCode
        }
    }

    /// FUSE read 回调
    func fuseRead(
        path: String,
        buf: UnsafeMutablePointer<CChar>,
        size: size_t,
        offset: off_t,
        fi: UnsafeMutablePointer<fuse_file_info>
    ) -> Int32 {
        let fd = Int32(fi.pointee.fh)

        // 定位到指定偏移
        if lseek(fd, offset, SEEK_SET) < 0 {
            return -errno
        }

        // 读取数据
        let bytesRead = read(fd, buf, size)
        if bytesRead < 0 {
            return -errno
        }

        return Int32(bytesRead)
    }
}
```

---

## 8. 写入路由器 (WriteRouter)

### 9.1 Write-Back 策略

**核心思想:** 写入操作**始终**写入 Downloads_Local，标记为 dirty，异步同步到 EXTERNAL。

**写入时触发淘汰检查:** 当本地空间不足时，根据 LRU 策略淘汰旧文件。

### 9.2 写入流程

```
┌──────────────────────────────────────────────────────────────────┐
│                     用户写入文件                                   │
│              write("~/Downloads/file.pdf", data)                 │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ 检查同步锁      │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    ▼                 ▼
              ┌──────────┐      ┌──────────┐
              │ UNLOCKED │      │SYNC_LOCKED│
              └────┬─────┘      └────┬─────┘
                   │                 │
                   │                 ▼
                   │           ┌──────────────┐
                   │           │ 阻塞等待     │
                   │           │ 或返回 EBUSY │
                   │           └──────┬───────┘
                   │                  │
                   └─────┬────────────┘
                         ▼
                ┌─────────────────┐
                │ 检查本地空间    │
                │ 触发 LRU 淘汰   │ ←── 新增
                └────────┬────────┘
                         │
                         ▼
                ┌─────────────────┐
                │ 写入到           │
                │ Downloads_Local │
                └────────┬────────┘
                         │
                         ▼
                ┌─────────────────┐
                │ 标记 isDirty    │
                │ = true          │
                └────────┬────────┘
                         │
                         ▼
                ┌─────────────────┐
                │ 更新 accessedAt │
                │ (最新访问时间)   │
                └────────┬────────┘
                         │
                         ▼
                ┌─────────────────┐
                │ 加入同步队列     │
                │ (防抖 5 秒)      │
                └────────┬────────┘
                         │
                         ▼
                ┌─────────────────┐
                │ 返回写入成功     │
                └─────────────────┘
```

### 9.3 WriteRouter 代码结构

```swift
class WriteRouter {
    private let lockManager: LockManager
    private let syncScheduler: SyncScheduler
    private let evictionManager: EvictionManager
    private let store: Store
    private let fileEntryBox: Box<FileEntry>

    /// 处理写入请求
    func handleWrite(_ virtualPath: String, data: Data) -> Result<Void, VFSError> {
        // 1. 检查同步锁
        if lockManager.isLocked(virtualPath) {
            return .failure(.fileBusy(virtualPath))
        }

        // 2. 检查空间并触发淘汰
        let requiredSpace = Int64(data.count)
        if !evictionManager.ensureSpace(requiredSpace) {
            return .failure(.insufficientSpace)
        }

        // 3. 写入到 Downloads_Local
        let localPath = Paths.downloadsLocal.appendingPathComponent(virtualPath).path

        do {
            // 确保父目录存在
            let parentDir = (localPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true
            )

            try data.write(to: URL(fileURLWithPath: localPath))
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }

        // 4. 更新元数据
        updateFileEntry(virtualPath: virtualPath, size: Int64(data.count))

        // 5. 调度同步
        syncScheduler.markDirty(virtualPath)
        syncScheduler.scheduleDirtySync(virtualPath, debounce: 5.0)

        return .success(())
    }

    /// 更新文件元数据
    private func updateFileEntry(virtualPath: String, size: Int64) {
        do {
            try store.runInTransaction {
                let query = try fileEntryBox.query {
                    FileEntry.virtualPath == virtualPath
                }.build()

                let entry: FileEntry
                if let existing = try query.findFirst() {
                    entry = existing
                } else {
                    entry = FileEntry()
                    entry.virtualPath = virtualPath
                }

                entry.size = size
                entry.isDirty = true
                entry.accessedAt = Date()
                entry.modifiedAt = Date()
                entry.location = .localOnly

                try fileEntryBox.put(entry)
            }
        } catch {
            Logger.error("WriteRouter: Failed to update file entry for \(virtualPath)")
        }
    }
}
```

---

## 10. 删除路由器 (DeleteRouter)

### 10.1 删除策略

**核心原则:** 先标记数据库，再删除实际文件。三阶段标记保证原子性。

| 文件状态 | 删除行为 |
|----------|----------|
| `LOCAL_ONLY` | 直接删除本地文件 + 移除数据库记录 |
| `EXTERNAL_ONLY` | 标记待删除，EXTERNAL 在线时同步删除 |
| `BOTH` | 三阶段删除（见下文） |
| `DELETED` | 直接移除数据库记录 |

### 10.2 三阶段删除流程 (BOTH 状态)

```
用户删除 BOTH 状态文件
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    阶段 1: 标记数据库                             │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ entry.deletePhase = 1  // 标记删除意图                       ││
│  │ entry.deleteRequestedAt = Date()                            ││
│  │ try fileEntryBox.put(entry)                                 ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    阶段 2: 删除本地文件                           │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ try FileManager.removeItem(localPath)                       ││
│  │ entry.deletePhase = 2  // 本地已删除                         ││
│  │ entry.localPath = nil                                       ││
│  │ try fileEntryBox.put(entry)                                 ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    阶段 3: 删除 EXTERNAL 文件                     │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ if EXTERNAL 在线:                                            ││
│  │   try FileManager.removeItem(externalPath)                  ││
│  │   entry.deletePhase = 3  // 完成                             ││
│  │   try fileEntryBox.remove(entry)  // 移除记录                ││
│  │ else:                                                        ││
│  │   entry.pendingExternalDelete = true  // 等待在线时删除       ││
│  │   try fileEntryBox.put(entry)                               ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### 10.3 崩溃恢复

应用重启时检查未完成的删除操作：

```swift
func recoverPendingDeletes() {
    // 查找 deletePhase > 0 的记录
    let pendingDeletes = try fileEntryBox.query {
        FileEntry.deletePhase > 0
    }.build().find()

    for entry in pendingDeletes {
        switch entry.deletePhase {
        case 1:
            // 阶段 1: 重新开始删除流程
            continueDelete(entry, fromPhase: 1)
        case 2:
            // 阶段 2: 本地已删除，继续删除 EXTERNAL
            continueDelete(entry, fromPhase: 2)
        default:
            break
        }
    }
}
```

### 10.4 EXTERNAL 离线时的延迟删除

```swift
/// EXTERNAL 重新连接时处理待删除文件
func processPendingExternalDeletes() {
    let pending = try fileEntryBox.query {
        FileEntry.pendingExternalDelete == true
    }.build().find()

    for entry in pending {
        guard let externalPath = entry.externalPath else { continue }

        do {
            try FileManager.default.removeItem(atPath: externalPath)
            try fileEntryBox.remove(entry)
            Logger.info("Deleted pending external file: \(entry.virtualPath)")
        } catch {
            Logger.error("Failed to delete external file: \(error)")
        }
    }
}
```

### 10.5 DeleteRouter 代码结构

```swift
class DeleteRouter {
    private let store: Store
    private let fileEntryBox: Box<FileEntry>
    private let lockManager: LockManager
    private let externalManager: ExternalManager

    /// 处理删除请求
    func handleDelete(_ virtualPath: String) -> Result<Void, VFSError> {
        // 1. 检查同步锁
        if lockManager.isLocked(virtualPath) {
            return .failure(.fileBusy(virtualPath))
        }

        // 2. 获取文件状态
        guard let entry = getEntry(virtualPath) else {
            return .failure(.fileNotFound(virtualPath))
        }

        switch entry.location {
        case .localOnly:
            return deleteLocalOnly(entry)
        case .externalOnly:
            return deleteExternalOnly(entry)
        case .both:
            return deleteBoth(entry)
        case .deleted:
            return deleteRecord(entry)
        case .notExists:
            return .failure(.fileNotFound(virtualPath))
        }
    }

    /// 删除 LOCAL_ONLY 文件
    private func deleteLocalOnly(_ entry: FileEntry) -> Result<Void, VFSError> {
        do {
            // 直接删除本地文件
            if let localPath = entry.localPath {
                try FileManager.default.removeItem(atPath: localPath)
            }
            // 移除数据库记录
            try fileEntryBox.remove(entry)
            return .success(())
        } catch {
            return .failure(.deleteFailed(error.localizedDescription))
        }
    }

    /// 删除 EXTERNAL_ONLY 文件
    private func deleteExternalOnly(_ entry: FileEntry) -> Result<Void, VFSError> {
        if externalManager.isConnected {
            // 在线：直接删除
            do {
                if let externalPath = entry.externalPath {
                    try FileManager.default.removeItem(atPath: externalPath)
                }
                try fileEntryBox.remove(entry)
                return .success(())
            } catch {
                return .failure(.deleteFailed(error.localizedDescription))
            }
        } else {
            // 离线：标记待删除
            entry.pendingExternalDelete = true
            try? fileEntryBox.put(entry)
            return .success(())
        }
    }

    /// 删除 BOTH 状态文件 (三阶段)
    private func deleteBoth(_ entry: FileEntry) -> Result<Void, VFSError> {
        do {
            // 阶段 1: 标记删除意图
            entry.deletePhase = 1
            entry.deleteRequestedAt = Date()
            try fileEntryBox.put(entry)

            // 阶段 2: 删除本地文件
            if let localPath = entry.localPath {
                try FileManager.default.removeItem(atPath: localPath)
            }
            entry.deletePhase = 2
            entry.localPath = nil
            try fileEntryBox.put(entry)

            // 阶段 3: 删除 EXTERNAL
            if externalManager.isConnected {
                if let externalPath = entry.externalPath {
                    try FileManager.default.removeItem(atPath: externalPath)
                }
                try fileEntryBox.remove(entry)
            } else {
                entry.pendingExternalDelete = true
                try fileEntryBox.put(entry)
            }

            return .success(())
        } catch {
            return .failure(.deleteFailed(error.localizedDescription))
        }
    }

    /// 删除 DELETED 状态记录
    private func deleteRecord(_ entry: FileEntry) -> Result<Void, VFSError> {
        do {
            try fileEntryBox.remove(entry)
            return .success(())
        } catch {
            return .failure(.deleteFailed(error.localizedDescription))
        }
    }
}
```

---

## 11. 本地存储淘汰机制

### 9.1 设计原则

| 原则 | 说明 |
|------|------|
| **LRU 策略** | 基于最后访问时间 (accessedAt) 淘汰 |
| **保护脏数据** | isDirty = true 的文件不可淘汰 |
| **保护活跃文件** | 正在打开的文件不可淘汰 |
| **验证备份存在** | 淘汰前必须验证 EXTERNAL 中确实存在该文件 |
| **先同步后淘汰** | 如果 EXTERNAL 不存在，先同步；同步失败则不能淘汰 |
| **按需触发** | 写入时检查空间，不足时触发 |

### 9.2 淘汰流程

```
┌──────────────────────────────────────────────────────────────────┐
│                    写入请求到达                                    │
│                 需要 N bytes 空间                                  │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ 检查可用空间    │
                    │ available >= N? │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    ▼                 ▼
              ┌──────────┐      ┌──────────┐
              │   足够   │      │  不足    │
              │  继续写入 │      │ 触发淘汰 │
              └──────────┘      └────┬─────┘
                                     │
                                     ▼
                    ┌─────────────────────────────────┐
                    │ 查询可淘汰候选文件               │
                    │ WHERE location = BOTH           │
                    │   AND isDirty = false           │
                    │   AND NOT locked                │
                    │ ORDER BY accessedAt ASC         │
                    └────────────────┬────────────────┘
                                     │
                                     ▼
┌──────────────────────────────────────────────────────────────────┐
│                    循环处理每个候选文件                             │
│  for file in candidates:                                          │
│                              │                                     │
│                              ▼                                     │
│                    ┌─────────────────┐                            │
│                    │ EXTERNAL 已连接? │                            │
│                    └────────┬────────┘                            │
│                             │                                      │
│                    ┌────────┴────────┐                            │
│                    ▼                 ▼                             │
│              ┌──────────┐      ┌──────────┐                       │
│              │   是     │      │   否     │                       │
│              └────┬─────┘      └────┬─────┘                       │
│                   │                 │                              │
│                   ▼                 ▼                              │
│        ┌─────────────────┐   ┌─────────────────┐                  │
│        │ 文件存在于      │   │ 跳过此文件      │                  │
│        │ EXTERNAL?       │   │ (无法验证备份)   │                  │
│        └────────┬────────┘   └─────────────────┘                  │
│                 │                                                  │
│        ┌────────┴────────┐                                        │
│        ▼                 ▼                                         │
│  ┌──────────┐      ┌──────────┐                                   │
│  │   存在   │      │  不存在  │                                   │
│  └────┬─────┘      └────┬─────┘                                   │
│       │                 │                                          │
│       │                 ▼                                          │
│       │          ┌─────────────────┐                              │
│       │          │ 尝试同步到      │                              │
│       │          │ EXTERNAL        │                              │
│       │          └────────┬────────┘                              │
│       │                   │                                        │
│       │          ┌────────┴────────┐                              │
│       │          ▼                 ▼                               │
│       │    ┌──────────┐      ┌──────────┐                         │
│       │    │ 同步成功 │      │ 同步失败 │                         │
│       │    └────┬─────┘      └────┬─────┘                         │
│       │         │                 │                                │
│       │         │                 ▼                                │
│       │         │          ┌─────────────────┐                    │
│       │         │          │ 跳过此文件      │                    │
│       │         │          │ (无法确保备份)   │                    │
│       │         │          └─────────────────┘                    │
│       │         │                                                  │
│       └────┬────┘                                                  │
│            ▼                                                       │
│  ┌─────────────────┐                                              │
│  │ 删除本地文件    │                                              │
│  │ 更新 location   │                                              │
│  │ = EXTERNAL_ONLY │                                              │
│  └────────┬────────┘                                              │
│           │                                                        │
│           ▼                                                        │
│  ┌─────────────────┐                                              │
│  │ 空间足够?       │                                              │
│  │ available >= N? │                                              │
│  └────────┬────────┘                                              │
│           │                                                        │
│  ┌────────┴────────┐                                              │
│  ▼                 ▼                                               │
│ break          continue                                            │
└──────────────────────────────────────────────────────────────────┘
                              │
                      ┌───────┴───────┐
                      ▼               ▼
                ┌──────────┐    ┌──────────┐
                │ 淘汰成功 │    │ 空间仍不足│
                │ 继续写入 │    │ 返回错误  │
                └──────────┘    └──────────┘
```

### 9.3 EvictionManager 实现

```swift
class EvictionManager {
    private let store: Store
    private let fileEntryBox: Box<FileEntry>
    private let lockManager: LockManager
    private let diskManager: DiskManager
    private let syncEngine: SyncEngine

    /// 配置
    struct Config {
        /// 本地存储配额 (bytes)，0 表示不限制
        var localQuota: Int64 = 0

        /// 保留空间比例 (0.0-1.0)
        var reserveRatio: Double = 0.1

        /// 最小保留空间 (bytes)
        var minReserve: Int64 = 1_073_741_824  // 1GB

        /// 单次淘汰最大文件数
        var maxEvictCount: Int = 100

        /// 淘汰前同步超时 (秒)
        var syncTimeoutSeconds: TimeInterval = 30
    }

    var config = Config()

    /// 确保有足够空间
    /// - Parameter requiredSpace: 需要的空间 (bytes)
    /// - Returns: 是否成功确保空间
    func ensureSpace(_ requiredSpace: Int64) -> Bool {
        let available = availableSpace()

        if available >= requiredSpace {
            return true
        }

        let needToFree = requiredSpace - available + config.minReserve
        return evict(targetBytes: needToFree)
    }

    /// 获取可用空间
    private func availableSpace() -> Int64 {
        let localPath = Paths.downloadsLocal.path

        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: localPath)
            let freeSpace = attrs[.systemFreeSize] as? Int64 ?? 0

            // 如果设置了配额，使用配额限制
            if config.localQuota > 0 {
                let usedSpace = calculateLocalUsage()
                let quotaAvailable = config.localQuota - usedSpace
                return min(freeSpace, quotaAvailable)
            }

            return freeSpace
        } catch {
            return 0
        }
    }

    /// 计算本地目录使用量
    private func calculateLocalUsage() -> Int64 {
        // 从数据库查询本地文件总大小
        do {
            let query = try fileEntryBox.query {
                FileEntry.location == FileLocation.localOnly.rawValue ||
                FileEntry.location == FileLocation.both.rawValue
            }.build()

            let entries = try query.find()
            return entries.reduce(0) { $0 + $1.size }
        } catch {
            return 0
        }
    }

    /// 执行淘汰
    /// - Parameter targetBytes: 需要释放的空间
    /// - Returns: 是否成功
    private func evict(targetBytes: Int64) -> Bool {
        var freedBytes: Int64 = 0
        var evictedCount = 0
        var skippedCount = 0

        // 前置条件: EXTERNAL 必须已连接
        guard diskManager.isExternalConnected,
              let externalRoot = diskManager.currentExternalPath else {
            Logger.warning("Eviction skipped: EXTERNAL not connected")
            return false
        }

        do {
            // 查询可淘汰候选文件: BOTH 状态 + 非脏 + 按访问时间升序
            let query = try fileEntryBox.query {
                FileEntry.location == FileLocation.both.rawValue &&
                FileEntry.isDirty == false
            }
            .ordered(by: FileEntry.accessedAt)  // ASC: 最久未访问的在前
            .build()

            let candidates = try query.find()

            for entry in candidates {
                // 1. 检查是否被锁定
                if lockManager.isLocked(entry.virtualPath) {
                    skippedCount += 1
                    continue
                }

                // 2. 验证 EXTERNAL 中确实存在该文件
                let externalPath = externalRoot.appendingPathComponent(entry.virtualPath).path
                let existsInExternal = FileManager.default.fileExists(atPath: externalPath)

                if !existsInExternal {
                    // 3. EXTERNAL 中不存在，尝试同步
                    Logger.info("Eviction: \(entry.virtualPath) not in EXTERNAL, attempting sync...")

                    let syncSuccess = syncFileToExternal(entry, externalPath: externalPath)

                    if !syncSuccess {
                        // 同步失败，不能淘汰此文件
                        Logger.warning("Eviction skipped: failed to sync \(entry.virtualPath)")
                        skippedCount += 1
                        continue
                    }
                }

                // 4. 此时确认 EXTERNAL 中存在备份，可以安全淘汰
                guard let localPath = entry.localPath else {
                    skippedCount += 1
                    continue
                }

                do {
                    // 删除本地文件
                    try FileManager.default.removeItem(atPath: localPath)

                    // 更新数据库状态
                    try store.runInTransaction {
                        entry.location = .externalOnly
                        entry.localPath = nil
                        try fileEntryBox.put(entry)
                    }

                    freedBytes += entry.size
                    evictedCount += 1

                    Logger.info("Evicted: \(entry.virtualPath) (\(entry.size) bytes)")

                    // 检查是否已释放足够空间
                    if freedBytes >= targetBytes {
                        break
                    }

                    // 单次淘汰数量限制
                    if evictedCount >= config.maxEvictCount {
                        break
                    }

                } catch {
                    Logger.error("Eviction failed for \(entry.virtualPath): \(error)")
                    skippedCount += 1
                }
            }

            Logger.info("Eviction complete: freed \(freedBytes) bytes, evicted \(evictedCount) files, skipped \(skippedCount)")
            return freedBytes >= targetBytes

        } catch {
            Logger.error("Eviction query failed: \(error)")
            return false
        }
    }

    /// 同步单个文件到 EXTERNAL
    /// - Returns: 是否同步成功
    private func syncFileToExternal(_ entry: FileEntry, externalPath: String) -> Bool {
        guard let localPath = entry.localPath else {
            return false
        }

        // 确保文件仍然存在于本地
        guard FileManager.default.fileExists(atPath: localPath) else {
            return false
        }

        do {
            // 确保父目录存在
            let parentDir = (externalPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true
            )

            // 复制文件到 EXTERNAL
            try FileManager.default.copyItem(atPath: localPath, toPath: externalPath)

            // 验证复制成功
            guard FileManager.default.fileExists(atPath: externalPath) else {
                return false
            }

            // 可选: 验证文件大小
            let attrs = try? FileManager.default.attributesOfItem(atPath: externalPath)
            let copiedSize = attrs?[.size] as? Int64 ?? 0
            if copiedSize != entry.size {
                Logger.warning("Size mismatch after sync: expected \(entry.size), got \(copiedSize)")
                // 删除不完整的文件
                try? FileManager.default.removeItem(atPath: externalPath)
                return false
            }

            Logger.info("Sync before eviction successful: \(entry.virtualPath)")
            return true

        } catch {
            Logger.error("Sync failed: \(entry.virtualPath) - \(error)")
            return false
        }
    }

    /// 获取淘汰候选列表 (用于 UI 显示)
    /// 注意: 这只是候选列表，实际淘汰时还需验证 EXTERNAL 存在性
    func getEvictionCandidates(limit: Int = 50) -> [FileEntry] {
        do {
            let query = try fileEntryBox.query {
                FileEntry.location == FileLocation.both.rawValue &&
                FileEntry.isDirty == false
            }
            .ordered(by: FileEntry.accessedAt)
            .build()

            return try query.find(limit: limit)
        } catch {
            return []
        }
    }

    /// 检查文件是否可以被安全淘汰
    /// - Returns: (canEvict, reason)
    func canEvict(_ entry: FileEntry) -> (Bool, String) {
        // 检查状态
        if entry.location != .both {
            return (false, "文件不在 BOTH 状态")
        }

        if entry.isDirty {
            return (false, "文件有未同步的修改")
        }

        if lockManager.isLocked(entry.virtualPath) {
            return (false, "文件正在被使用")
        }

        // 检查 EXTERNAL 连接
        guard diskManager.isExternalConnected,
              let externalRoot = diskManager.currentExternalPath else {
            return (false, "外置硬盘未连接")
        }

        // 检查 EXTERNAL 中是否存在
        let externalPath = externalRoot.appendingPathComponent(entry.virtualPath).path
        if !FileManager.default.fileExists(atPath: externalPath) {
            return (false, "外置硬盘中不存在此文件，需要先同步")
        }

        return (true, "可以安全淘汰")
    }
}
```

### 9.4 淘汰策略配置

用户可配置的淘汰参数:

```swift
// config.json
{
    "eviction": {
        "enabled": true,
        "localQuotaGB": 50,        // 本地存储配额 (GB)
        "reserveGB": 5,            // 保留空间 (GB)
        "maxEvictPerRound": 100,   // 单次最大淘汰数
        "minFileAgeDays": 7        // 最小文件年龄 (天)
    }
}
```

---

## 10. 同步锁定机制

### 10.1 锁定策略

**策略: 悲观锁 + 读取不阻塞**

| 操作 | 锁定状态 | 行为 |
|------|----------|------|
| 读取 | `SYNC_LOCKED` | **允许**，直接从源文件读取 |
| 写入 | `SYNC_LOCKED` | **阻塞**，等待同步完成或超时 |
| 删除 | `SYNC_LOCKED` | **阻塞**，等待同步完成或超时 |
| 淘汰 | `SYNC_LOCKED` | **跳过**，淘汰下一个候选 |

### 10.2 锁定流程

```
同步开始
    │
    ▼
┌─────────────────┐
│ 获取文件锁      │
│ lockState =     │
│   SYNC_LOCKED   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 执行文件复制    │
│ Downloads_Local │
│    → EXTERNAL   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 释放文件锁      │
│ lockState =     │
│   UNLOCKED      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 更新状态:       │
│ isDirty = false │
│ location = BOTH │
└─────────────────┘
```

---

## 11. 数据模型与存储

### 11.1 ObjectBox 配置

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/objectbox/objectbox-swift-spm.git", from: "5.1.0")
]

// 初始化 Store
let store = try Store(directoryPath: Paths.database.path)
```

### 11.2 FileEntry 实体

```swift
// objectbox: entity
class FileEntry: Entity, Identifiable {
    var id: Id = 0

    // === 路径信息 ===

    /// 虚拟路径 (相对于 ~/Downloads)
    // objectbox: index
    var virtualPath: String = ""

    /// Downloads_Local 路径
    var localPath: String?

    /// EXTERNAL 路径
    var externalPath: String?

    // === 状态信息 ===

    /// 文件位置状态 (0-3)
    // objectbox: index
    var locationRaw: Int = 0

    var location: FileLocation {
        get { FileLocation(rawValue: locationRaw) ?? .notExists }
        set { locationRaw = newValue.rawValue }
    }

    /// 同步锁定状态 (0-1)
    var lockStateRaw: Int = 0

    var lockState: LockState {
        get { LockState(rawValue: lockStateRaw) ?? .unlocked }
        set { lockStateRaw = newValue.rawValue }
    }

    /// 是否为脏数据 (待同步)
    // objectbox: index
    var isDirty: Bool = false

    // === 文件属性 ===

    /// 文件大小 (bytes)
    var size: Int64 = 0

    /// 文件校验和 (SHA256)
    var checksum: String?

    /// 是否为目录
    var isDirectory: Bool = false

    // === 时间戳 ===

    /// 创建时间
    var createdAt: Date = Date()

    /// 最后修改时间
    // objectbox: index
    var modifiedAt: Date = Date()

    /// 最后访问时间 (用于 LRU)
    // objectbox: index
    var accessedAt: Date = Date()

    /// 最后同步时间
    var syncedAt: Date?

    // === 初始化 ===

    required init() {}
}
```

### 11.3 SyncHistory 实体

```swift
// objectbox: entity
class SyncHistory: Entity, Identifiable {
    var id: Id = 0

    /// 同步会话 ID
    var sessionId: String = ""

    /// 同步方向
    var directionRaw: Int = 0

    /// 文件虚拟路径
    var virtualPath: String = ""

    /// 文件大小
    var size: Int64 = 0

    /// 同步状态
    var statusRaw: Int = 0

    /// 开始时间
    var startedAt: Date = Date()

    /// 完成时间
    var completedAt: Date?

    /// 错误信息
    var errorMessage: String?

    required init() {}
}
```

### 11.4 数据库管理器

```swift
class DatabaseManager {
    static let shared = DatabaseManager()

    private(set) var store: Store!
    private(set) var fileEntryBox: Box<FileEntry>!
    private(set) var syncHistoryBox: Box<SyncHistory>!

    private init() {}

    func initialize() throws {
        let dbPath = Paths.database.path

        // 确保目录存在
        try FileManager.default.createDirectory(
            atPath: dbPath,
            withIntermediateDirectories: true
        )

        // 初始化 ObjectBox Store
        store = try Store(directoryPath: dbPath)

        // 获取 Box
        fileEntryBox = store.box(for: FileEntry.self)
        syncHistoryBox = store.box(for: SyncHistory.self)

        Logger.info("ObjectBox initialized at \(dbPath)")
    }

    // MARK: - FileEntry 操作

    func getFileEntry(virtualPath: String) -> FileEntry? {
        do {
            let query = try fileEntryBox.query {
                FileEntry.virtualPath == virtualPath
            }.build()
            return try query.findFirst()
        } catch {
            return nil
        }
    }

    func saveFileEntry(_ entry: FileEntry) throws {
        try fileEntryBox.put(entry)
    }

    func getDirtyFiles() -> [FileEntry] {
        do {
            let query = try fileEntryBox.query {
                FileEntry.isDirty == true
            }.build()
            return try query.find()
        } catch {
            return []
        }
    }

    func getFilesForEviction(limit: Int) -> [FileEntry] {
        do {
            let query = try fileEntryBox.query {
                FileEntry.locationRaw == FileLocation.both.rawValue &&
                FileEntry.isDirty == false
            }
            .ordered(by: FileEntry.accessedAt)
            .build()
            return try query.find(limit: limit)
        } catch {
            return []
        }
    }

    // MARK: - 统计

    func getLocalStorageUsage() -> Int64 {
        do {
            let query = try fileEntryBox.query {
                FileEntry.locationRaw == FileLocation.localOnly.rawValue ||
                FileEntry.locationRaw == FileLocation.both.rawValue
            }.build()
            let entries = try query.find()
            return entries.reduce(0) { $0 + $1.size }
        } catch {
            return 0
        }
    }

    func getFileCount(location: FileLocation) -> Int {
        do {
            let query = try fileEntryBox.query {
                FileEntry.locationRaw == location.rawValue
            }.build()
            return try query.count()
        } catch {
            return 0
        }
    }
}
```

---

## 13. 冲突解决机制

### 13.1 冲突检测时机

冲突检测**仅在同步时**进行，不进行实时监控。

```
同步开始
    │
    ▼
读取 EXTERNAL 文件元数据
    │
    ▼
比对 LOCAL 与 EXTERNAL 的 modifiedAt
    │
    ├── LOCAL 更新 & EXTERNAL 未变 → 正常同步
    │
    ├── LOCAL 未变 & EXTERNAL 更新 → 外部修改 (见 5.2 状态转换)
    │
    └── 双方都更新 → 冲突！
```

### 13.2 冲突解决策略

**核心原则: LOCAL 覆盖 EXTERNAL**

| 冲突类型 | 处理方式 |
|----------|----------|
| 双端都修改 | LOCAL 覆盖 EXTERNAL，EXTERNAL 原文件生成备份 |
| LOCAL 修改 + EXTERNAL 删除 | LOCAL 覆盖（重新创建 EXTERNAL 文件） |
| LOCAL 删除 + EXTERNAL 修改 | LOCAL 已删除，EXTERNAL 保持（不同步删除） |

### 13.3 备份文件机制

**命名规则:**
```
原文件: document.pdf
备份文件: document.pdf.conflict-2026-01-21-103045
```

**备份文件特性:**
- 存放位置: 与原文件同目录
- 可见性: 隐藏文件（以 `.conflict-` 后缀标识）
- **不出现在 VFS 目录列表中**（不记录在 FileEntry 中）
- 用户通过 UI 管理界面查看和处理

### 13.4 冲突处理流程

```
检测到冲突 (LOCAL 和 EXTERNAL 都修改)
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: 生成备份文件名                                           │
│   backupName = "document.pdf.conflict-2026-01-21-103045"        │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: 重命名 EXTERNAL 文件为备份                               │
│   mv EXTERNAL/document.pdf → EXTERNAL/document.pdf.conflict-... │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: 复制 LOCAL 到 EXTERNAL                                   │
│   cp LOCAL/document.pdf → EXTERNAL/document.pdf                  │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 4: 记录冲突事件 (用于 UI 显示)                               │
│   ConflictRecord {                                               │
│     virtualPath: "document.pdf"                                  │
│     backupPath: "document.pdf.conflict-2026-01-21-103045"       │
│     conflictAt: Date()                                          │
│     localModifiedAt: ...                                        │
│     externalModifiedAt: ...                                     │
│   }                                                              │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 5: 更新 FileEntry                                           │
│   entry.isDirty = false                                          │
│   entry.location = .both                                         │
│   entry.syncedAt = Date()                                        │
└─────────────────────────────────────────────────────────────────┘
```

### 13.5 冲突管理 UI

用户可通过应用 UI 管理冲突文件：

| 功能 | 说明 |
|------|------|
| 查看冲突列表 | 显示所有未处理的冲突记录 |
| 预览对比 | 查看当前文件和备份文件的差异 |
| 恢复备份 | 用备份文件覆盖当前文件 |
| 删除备份 | 确认当前文件正确，删除备份 |
| 批量清理 | 删除所有备份文件 |

```swift
// ConflictRecord 实体
class ConflictRecord: Entity {
    var id: Id = 0
    var syncPairId: UUID = UUID()
    var virtualPath: String = ""
    var backupFileName: String = ""
    var conflictAt: Date = Date()
    var localModifiedAt: Date = Date()
    var externalModifiedAt: Date = Date()
    var resolved: Bool = false
    var resolvedAt: Date?
}
```

---

## 14. 多路同步架构

### 14.1 SyncPair 管理

每个同步对独立配置和管理：

```swift
class SyncPairManager {
    private var pairs: [UUID: SyncPair] = [:]
    private var mountedPairs: [UUID: VFSMount] = [:]

    /// 添加同步对
    func addPair(_ pair: SyncPair) throws {
        // 验证路径不冲突
        guard !hasConflictingPaths(pair) else {
            throw DMSAError.pathConflict
        }
        pairs[pair.id] = pair
    }

    /// 挂载同步对
    func mount(_ pairId: UUID) throws {
        guard let pair = pairs[pairId] else { return }

        // 1. 准备 LOCAL_DIR
        try prepareLocalDir(pair)

        // 2. 创建 FUSE 挂载
        let mount = try VFSMount(pair: pair)
        try mount.mount()

        mountedPairs[pairId] = mount
    }

    /// 检查 EXTERNAL_DIR 可访问性
    func checkExternalAccessibility(_ pairId: UUID) -> Bool {
        guard let pair = pairs[pairId] else { return false }
        return FileManager.default.isReadableFile(atPath: pair.externalDir.path)
    }
}
```

### 14.2 FileEntry 与同步对关联

```swift
class FileEntry: Entity {
    // ... 其他字段 ...

    /// 所属同步对 ID
    var syncPairId: UUID = UUID()

    /// 根据 syncPairId 获取完整路径
    func localPath(in pair: SyncPair) -> URL {
        pair.localDir.appendingPathComponent(virtualPath)
    }

    func externalPath(in pair: SyncPair) -> URL {
        pair.externalDir.appendingPathComponent(virtualPath)
    }
}
```

### 14.3 独立配额管理

每个同步对有独立的本地配额：

```swift
struct SyncPair {
    // ... 其他字段 ...

    /// 本地配额 (bytes)，0 表示不限制
    var localQuotaBytes: Int64

    /// 当前使用量
    func currentUsage() -> Int64 {
        DatabaseManager.shared.getLocalUsage(syncPairId: id)
    }

    /// 可用空间
    func availableSpace() -> Int64 {
        if localQuotaBytes == 0 {
            // 无配额限制，返回磁盘可用空间
            return getDiskFreeSpace(localDir)
        }
        return max(0, localQuotaBytes - currentUsage())
    }
}
```

### 14.4 配置示例

```json
{
    "version": "3.0",
    "syncPairs": [
        {
            "id": "uuid-1",
            "name": "Downloads",
            "localDir": "~/.Downloads_Local",
            "externalDir": "/Volumes/BACKUP/Downloads",
            "targetDir": "~/Downloads",
            "localQuotaGB": 50,
            "enabled": true
        },
        {
            "id": "uuid-2",
            "name": "Documents",
            "localDir": "~/.Documents_Local",
            "externalDir": "/Volumes/NAS/Documents",
            "targetDir": "~/Documents",
            "localQuotaGB": 100,
            "enabled": true
        }
    ],
    "sync": {
        "autoSync": true,
        "syncIntervalMinutes": 30,
        "debounceSeconds": 5,
        "syncPriority": "fifo"
    }
}
```

---

## 15. 目录处理

### 15.1 目录同步

**空目录也需要同步:**

```swift
func syncDirectory(_ virtualPath: String, pair: SyncPair) throws {
    let localPath = pair.localDir.appendingPathComponent(virtualPath)
    let externalPath = pair.externalDir.appendingPathComponent(virtualPath)

    // 确保 EXTERNAL 目录存在
    try FileManager.default.createDirectory(
        at: externalPath,
        withIntermediateDirectories: true
    )

    // 同步目录属性（权限、时间戳）
    let attrs = try FileManager.default.attributesOfItem(atPath: localPath.path)
    try FileManager.default.setAttributes(attrs, ofItemAtPath: externalPath.path)
}
```

### 15.2 目录淘汰

**目录淘汰前递归检查子文件:**

```swift
func canEvictDirectory(_ entry: FileEntry) -> Bool {
    // 目录本身没有 isDirty 状态
    guard entry.isDirectory else { return false }

    // 查询所有子文件
    let children = try fileEntryBox.query {
        FileEntry.virtualPath.startsWith(entry.virtualPath + "/") &&
        FileEntry.syncPairId == entry.syncPairId
    }.build().find()

    // 任何子文件是 LOCAL_ONLY 或 isDirty，整个目录不能淘汰
    for child in children {
        if child.location == .localOnly || child.isDirty {
            return false
        }
    }

    return true
}
```

### 15.3 目录重命名

**重命名触发所有子文件的 virtualPath 更新:**

```swift
func renameDirectory(from oldPath: String, to newPath: String, pair: SyncPair) throws {
    // 1. 重命名本地目录
    let oldLocalPath = pair.localDir.appendingPathComponent(oldPath)
    let newLocalPath = pair.localDir.appendingPathComponent(newPath)
    try FileManager.default.moveItem(at: oldLocalPath, to: newLocalPath)

    // 2. 更新所有子文件的 virtualPath
    try store.runInTransaction {
        let children = try fileEntryBox.query {
            FileEntry.virtualPath.startsWith(oldPath + "/") &&
            FileEntry.syncPairId == pair.id
        }.build().find()

        for child in children {
            child.virtualPath = child.virtualPath.replacingOccurrences(
                of: oldPath + "/",
                with: newPath + "/"
            )
            try fileEntryBox.put(child)
        }

        // 3. 更新目录自身的 virtualPath
        if let dirEntry = getEntry(oldPath, pair: pair) {
            dirEntry.virtualPath = newPath
            dirEntry.isDirty = true  // 标记需要同步
            try fileEntryBox.put(dirEntry)
        }
    }

    // 4. 调度同步（会同步重命名到 EXTERNAL）
    syncScheduler.scheduleDirtySync(newPath, pair: pair)
}
```

---

## 16. 大文件处理

### 16.1 配置参数

```swift
struct LargeFileConfig {
    /// 大文件阈值 (bytes)，默认 1GB
    var thresholdBytes: Int64 = 1_073_741_824

    /// 分块大小 (bytes)，默认 64MB
    var chunkSizeBytes: Int64 = 67_108_864

    /// 是否启用断点续传
    var enableResume: Bool = true

    /// 校验方式
    var checksumAlgorithm: ChecksumAlgorithm = .sha256
}

enum ChecksumAlgorithm {
    case crc32      // 快速，适合小文件
    case sha256     // 安全，适合大文件
}
```

### 16.2 分块校验

```swift
struct FileChunk: Codable {
    let index: Int
    let offset: Int64
    let size: Int64
    let checksum: String
}

/// 计算大文件的分块校验
func calculateChunkedChecksum(_ path: URL, chunkSize: Int64) throws -> [FileChunk] {
    let fileHandle = try FileHandle(forReadingFrom: path)
    defer { try? fileHandle.close() }

    var chunks: [FileChunk] = []
    var offset: Int64 = 0
    var index = 0

    while let data = try fileHandle.read(upToCount: Int(chunkSize)), !data.isEmpty {
        let checksum = data.sha256()
        chunks.append(FileChunk(
            index: index,
            offset: offset,
            size: Int64(data.count),
            checksum: checksum
        ))
        offset += Int64(data.count)
        index += 1
    }

    return chunks
}
```

### 16.3 断点续传

```swift
/// FileEntry 扩展字段用于断点续传
extension FileEntry {
    /// 已传输的字节数
    var transferredBytes: Int64

    /// 分块校验信息 (JSON)
    var chunksJson: String?

    /// 续传时解析分块信息
    var chunks: [FileChunk]? {
        guard let json = chunksJson else { return nil }
        return try? JSONDecoder().decode([FileChunk].self, from: json.data(using: .utf8)!)
    }
}

/// 续传逻辑
func resumeSync(_ entry: FileEntry, pair: SyncPair) throws {
    guard let chunks = entry.chunks else {
        // 无分块信息，从头开始
        try fullSync(entry, pair: pair)
        return
    }

    let localPath = entry.localPath(in: pair)
    let externalPath = entry.externalPath(in: pair)

    // 找到需要续传的起始块
    let startChunkIndex = Int(entry.transferredBytes / config.chunkSizeBytes)

    // 验证已传输部分的完整性
    for i in 0..<startChunkIndex {
        let chunk = chunks[i]
        let externalChunkData = try readChunk(externalPath, chunk: chunk)
        if externalChunkData.sha256() != chunk.checksum {
            // 校验失败，从此块重新开始
            entry.transferredBytes = chunk.offset
            break
        }
    }

    // 继续传输
    try syncFromOffset(entry, pair: pair, offset: entry.transferredBytes)
}
```

---

## 17. 权限与特殊文件

### 17.1 文件权限同步

```swift
/// 同步文件权限
func syncPermissions(from source: URL, to destination: URL) throws {
    let attrs = try FileManager.default.attributesOfItem(atPath: source.path)

    // 同步的属性
    var syncAttrs: [FileAttributeKey: Any] = [:]

    if let permissions = attrs[.posixPermissions] {
        syncAttrs[.posixPermissions] = permissions
    }

    if let owner = attrs[.ownerAccountID] {
        syncAttrs[.ownerAccountID] = owner
    }

    if let group = attrs[.groupOwnerAccountID] {
        syncAttrs[.groupOwnerAccountID] = group
    }

    // 尝试设置权限（可能因文件系统限制失败）
    do {
        try FileManager.default.setAttributes(syncAttrs, ofItemAtPath: destination.path)
    } catch {
        // exFAT/NTFS 不支持 Unix 权限，忽略错误
        Logger.warning("Cannot sync permissions to \(destination.path): \(error)")
    }
}
```

### 17.2 符号链接处理

```swift
/// 同步符号链接本身（不解析）
func syncSymlink(from source: URL, to destination: URL) throws {
    // 读取链接目标
    let linkTarget = try FileManager.default.destinationOfSymbolicLink(atPath: source.path)

    // 删除已存在的目标
    if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
    }

    // 创建符号链接
    try FileManager.default.createSymbolicLink(
        atPath: destination.path,
        withDestinationPath: linkTarget
    )
}
```

### 17.3 扩展属性 (xattr) 同步

```swift
import Darwin

/// 同步扩展属性
func syncExtendedAttributes(from source: URL, to destination: URL) throws {
    // 列出所有扩展属性
    let names = try listXattrs(source.path)

    for name in names {
        // 读取属性值
        let value = try getXattr(source.path, name: name)

        // 写入目标（忽略不支持的文件系统错误）
        do {
            try setXattr(destination.path, name: name, value: value)
        } catch {
            Logger.warning("Cannot sync xattr '\(name)' to \(destination.path)")
        }
    }
}

private func listXattrs(_ path: String) throws -> [String] {
    let length = listxattr(path, nil, 0, 0)
    guard length > 0 else { return [] }

    var buffer = [CChar](repeating: 0, count: length)
    listxattr(path, &buffer, length, 0)

    return String(cString: buffer).split(separator: "\0").map(String.init)
}
```

---

## 18. EXTERNAL 断开处理

### 18.1 断开检测

```swift
class ExternalMonitor {
    private var timer: Timer?

    /// 开始监控 EXTERNAL 可访问性
    func startMonitoring(_ pair: SyncPair, interval: TimeInterval = 5) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkAccessibility(pair)
        }
    }

    private func checkAccessibility(_ pair: SyncPair) {
        let wasConnected = isConnected(pair.id)
        let nowConnected = FileManager.default.isReadableFile(atPath: pair.externalDir.path)

        if wasConnected && !nowConnected {
            // 断开
            handleDisconnection(pair)
        } else if !wasConnected && nowConnected {
            // 重新连接
            handleReconnection(pair)
        }
    }
}
```

### 18.2 同步中断处理

```swift
/// 处理同步中断
func handleSyncInterruption(_ entry: FileEntry, pair: SyncPair) {
    // 1. 标记同步状态为暂停
    entry.syncStatus = .paused
    entry.syncPausedAt = Date()
    try? fileEntryBox.put(entry)

    // 2. 记录已传输的字节数（用于断点续传）
    // (已在 syncEngine 中更新)

    // 3. 通知用户
    NotificationCenter.default.post(
        name: .externalDisconnected,
        object: nil,
        userInfo: [
            "pairId": pair.id,
            "interruptedFile": entry.virtualPath
        ]
    )

    // 4. 显示弹窗
    AlertManager.show(
        title: "同步中断",
        message: "外部目录 '\(pair.name)' 已断开连接，文件 '\(entry.virtualPath)' 的同步已暂停。",
        style: .warning
    )
}
```

### 18.3 EXTERNAL_ONLY 文件访问

```swift
/// 访问 EXTERNAL_ONLY 文件时的处理
func accessExternalOnlyFile(_ entry: FileEntry, pair: SyncPair) -> Result<URL, VFSError> {
    // 检查 EXTERNAL 是否可访问
    guard FileManager.default.isReadableFile(atPath: pair.externalDir.path) else {
        // 不可访问，显示提示
        AlertManager.show(
            title: "文件不可用",
            message: "文件 '\(entry.virtualPath)' 仅存在于外部目录，但外部目录当前不可访问。\n\n请连接 '\(pair.name)' 后重试。",
            style: .warning
        )

        return .failure(.externalOffline)
    }

    // 可访问，返回路径
    return .success(entry.externalPath(in: pair))
}
```

### 18.4 重新连接时的恢复

```swift
/// EXTERNAL 重新连接时的处理
func handleReconnection(_ pair: SyncPair) {
    // 1. 处理待删除文件
    processPendingExternalDeletes(pair)

    // 2. 恢复暂停的同步
    resumePausedSyncs(pair)

    // 3. 检查 EXTERNAL 变更
    checkExternalChanges(pair)

    // 4. 通知用户
    NotificationCenter.default.post(
        name: .externalReconnected,
        object: nil,
        userInfo: ["pairId": pair.id]
    )
}

/// 恢复暂停的同步
func resumePausedSyncs(_ pair: SyncPair) {
    let paused = try? fileEntryBox.query {
        FileEntry.syncStatus == SyncStatus.paused.rawValue &&
        FileEntry.syncPairId == pair.id
    }.build().find()

    for entry in paused ?? [] {
        entry.syncStatus = .pending
        try? fileEntryBox.put(entry)
        syncScheduler.scheduleDirtySync(entry.virtualPath, pair: pair)
    }
}
```

---

## 19. 应用生命周期

### 19.1 启动流程

```
应用启动
    │
    ▼
┌─────────────────────────────────────────┐
│ 1. 初始化数据库 (ObjectBox)              │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│ 2. 加载配置文件                          │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│ 3. 恢复未完成的操作                       │
│   - 未完成的删除 (deletePhase > 0)       │
│   - 暂停的同步 (syncStatus = paused)     │
│   - 待同步的脏文件 (isDirty = true)       │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│ 4. 对每个同步对:                          │
│   a. 检查版本文件                         │
│   b. 如需重建文件树                       │
│   c. 挂载 FUSE                           │
│   d. 开始监控 EXTERNAL 可访问性           │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│ 5. 启动定时同步                          │
└─────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────┐
│ 6. 应用就绪                              │
└─────────────────────────────────────────┘
```

### 19.2 正常退出流程

```swift
func applicationWillTerminate() {
    // 1. 停止接受新的文件操作
    for (_, mount) in mountedPairs {
        mount.setReadOnly(true)
    }

    // 2. 等待正在进行的写入完成（最多 30 秒）
    waitForPendingWrites(timeout: 30)

    // 3. 停止所有同步任务
    syncScheduler.stopAll()

    // 4. 卸载所有 FUSE 挂载点
    for (_, mount) in mountedPairs {
        try? mount.unmount()
    }

    // 5. 关闭数据库
    DatabaseManager.shared.close()

    Logger.info("Application terminated gracefully")
}

/// 等待正在进行的写入完成
func waitForPendingWrites(timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        let pendingCount = lockManager.activeWriteCount()
        if pendingCount == 0 {
            break
        }
        Logger.info("Waiting for \(pendingCount) pending writes...")
        Thread.sleep(forTimeInterval: 0.5)
    }
}
```

### 19.3 崩溃恢复

由于 isDirty 和 deletePhase 等状态实时持久化到数据库，崩溃后重启会自动恢复：

```swift
func recoverFromCrash() {
    Logger.info("Checking for crash recovery...")

    // 1. 恢复未完成的删除
    recoverPendingDeletes()

    // 2. 恢复未完成的同步
    recoverPendingSyncs()

    // 3. 检查文件完整性
    checkFileIntegrity()

    Logger.info("Crash recovery completed")
}

/// 检查文件完整性
func checkFileIntegrity() {
    // 查找正在写入的文件（可能不完整）
    let inProgress = try? fileEntryBox.query {
        FileEntry.writeInProgress == true
    }.build().find()

    for entry in inProgress ?? [] {
        // 检查本地文件是否存在且完整
        if let localPath = entry.localPath,
           FileManager.default.fileExists(atPath: localPath) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: localPath)
            let actualSize = attrs?[.size] as? Int64 ?? 0

            if actualSize != entry.size {
                // 文件不完整，标记为需要重新同步
                Logger.warning("Incomplete file detected: \(entry.virtualPath)")
                entry.isDirty = true
                entry.writeInProgress = false
                try? fileEntryBox.put(entry)
            }
        }
    }
}
```

---

## 20. 错误处理

### 20.1 VFS 错误类型

```swift
enum VFSError: Error, LocalizedError {
    // 文件操作错误
    case fileNotFound(String)
    case permissionDenied(String)
    case fileBusy(String)           // 文件被锁定
    case readFailed(String)
    case writeFailed(String)
    case copyFailed(String)

    // 空间错误
    case insufficientSpace
    case quotaExceeded

    // 连接错误
    case externalOffline
    case mountFailed(String)

    // 数据错误
    case checksumMismatch
    case metadataCorrupted
    case databaseError(String)

    var posixErrorCode: Int32 {
        switch self {
        case .fileNotFound: return -ENOENT
        case .permissionDenied: return -EACCES
        case .fileBusy: return -EBUSY
        case .insufficientSpace, .quotaExceeded: return -ENOSPC
        case .externalOffline: return -ENODEV
        default: return -EIO
        }
    }

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "文件不存在: \(path)"
        case .permissionDenied(let path): return "权限拒绝: \(path)"
        case .fileBusy(let path): return "文件正在同步: \(path)"
        case .insufficientSpace: return "本地空间不足"
        case .quotaExceeded: return "超出存储配额"
        case .externalOffline: return "外置硬盘未连接"
        case .mountFailed(let msg): return "挂载失败: \(msg)"
        case .checksumMismatch: return "文件校验失败"
        case .metadataCorrupted: return "元数据损坏"
        case .databaseError(let msg): return "数据库错误: \(msg)"
        default: return nil
        }
    }
}
```

### 12.2 错误恢复策略

| 错误类型 | 恢复策略 |
|----------|----------|
| `fileNotFound` | 检查 EXTERNAL，如有则更新元数据 |
| `fileBusy` | 等待或提示用户稍后重试 |
| `insufficientSpace` | 触发紧急淘汰，或提示用户 |
| `externalOffline` | 使用 Downloads_Local 数据 |
| `checksumMismatch` | 删除本地副本，标记为 EXTERNAL_ONLY |
| `databaseError` | 尝试重建索引 |

---

## 13. 性能优化

### 13.1 读取优化

1. **本地优先**: 优先从 Downloads_Local 读取
2. **零拷贝**: EXTERNAL_ONLY 直接重定向，不产生副本
3. **预读取**: 读取目录时预先加载元数据
4. **批量查询**: 使用 ObjectBox 批量查询减少 I/O

### 13.2 写入优化

1. **始终本地写入**: 写入直接到 Downloads_Local
2. **写入合并**: 短时间内多次写入合并为一次同步
3. **防抖机制**: 5 秒防抖，避免频繁同步
4. **惰性淘汰**: 仅在空间不足时触发淘汰

### 13.3 存储层优化

1. **索引优化**: 关键字段添加 ObjectBox 索引
2. **事务批处理**: 批量操作使用事务
3. **延迟加载**: 大字段延迟加载

### 13.4 关键指标

| 指标 | 目标值 |
|------|--------|
| 本地文件读取延迟 | < 1ms |
| EXTERNAL 直接读取延迟 | < 5ms (取决于硬盘) |
| 写入延迟 | < 5ms |
| 目录列表合并 | < 10ms |
| 淘汰决策时间 | < 50ms |
| 数据库查询 | < 1ms |

---

## 23. 特权助手工具 (SMJobBless)

### 23.1 设计背景

DMSA 需要执行特权操作来保护 LOCAL_DIR 和 EXTERNAL_DIR，防止用户直接访问绕过 VFS 层。使用 Apple 官方推荐的 **SMJobBless** 机制实现特权分离。

**需要特权操作的场景:**

| 操作 | 原因 | 权限 |
|------|------|------|
| `chflags uchg` | 锁定目录，防止修改 | root |
| `chflags nouchg` | 解锁目录，允许 DMSA 操作 | root |
| 目录 ACL 设置 | 精细权限控制 | root |
| FUSE 挂载点创建 | 系统级挂载 | root (部分场景) |

### 23.2 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                     DMSA.app (普通用户权限)                   │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   VFSCore   │  │ SyncEngine  │  │ PrivilegedClient    │  │
│  └─────────────┘  └─────────────┘  └──────────┬──────────┘  │
│                                               │              │
└───────────────────────────────────────────────┼──────────────┘
                                                │ XPC 通信
                                                ▼
┌─────────────────────────────────────────────────────────────┐
│              com.ttttt.dmsa.helper (root 权限)               │
│                      LaunchDaemon                            │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                 DMSAHelperProtocol                   │    │
│  │                                                     │    │
│  │  • lockDirectory(path:)      → chflags uchg         │    │
│  │  • unlockDirectory(path:)    → chflags nouchg       │    │
│  │  • setACL(path:, rules:)     → chmod +a             │    │
│  │  • removeACL(path:)          → chmod -a             │    │
│  │  • getDirectoryStatus(path:) → 检查锁定状态           │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 23.3 XPC 协议定义

```swift
// DMSAHelperProtocol.swift (共享)
import Foundation

/// 特权助手协议
@objc protocol DMSAHelperProtocol {

    /// 锁定目录 (chflags uchg)
    /// - Parameters:
    ///   - path: 目录路径
    ///   - reply: 结果回调 (success, errorMessage)
    func lockDirectory(_ path: String,
                      withReply reply: @escaping (Bool, String?) -> Void)

    /// 解锁目录 (chflags nouchg)
    func unlockDirectory(_ path: String,
                        withReply reply: @escaping (Bool, String?) -> Void)

    /// 设置 ACL 规则
    /// - Parameters:
    ///   - path: 目录路径
    ///   - deny: 是否为拒绝规则
    ///   - permissions: 权限列表 (如 ["delete", "write", "append"])
    ///   - user: 用户名 (如 "everyone")
    func setACL(_ path: String,
               deny: Bool,
               permissions: [String],
               user: String,
               withReply reply: @escaping (Bool, String?) -> Void)

    /// 移除所有 ACL 规则
    func removeACL(_ path: String,
                  withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取目录保护状态
    /// - Returns: (isLocked, hasACL, errorMessage)
    func getDirectoryStatus(_ path: String,
                           withReply reply: @escaping (Bool, Bool, String?) -> Void)

    /// 获取 Helper 版本
    func getVersion(withReply reply: @escaping (String) -> Void)
}
```

### 23.4 Helper 实现

```swift
// DMSAHelper/main.swift
import Foundation

class HelperTool: NSObject, NSXPCListenerDelegate, DMSAHelperProtocol {

    static let version = "1.0.0"

    // MARK: - 目录锁定

    func lockDirectory(_ path: String,
                      withReply reply: @escaping (Bool, String?) -> Void) {
        // 验证路径安全性
        guard isPathAllowed(path) else {
            reply(false, "Path not allowed: \(path)")
            return
        }

        let result = runCommand("/usr/bin/chflags", ["uchg", path])
        reply(result.success, result.error)
    }

    func unlockDirectory(_ path: String,
                        withReply reply: @escaping (Bool, String?) -> Void) {
        guard isPathAllowed(path) else {
            reply(false, "Path not allowed: \(path)")
            return
        }

        let result = runCommand("/usr/bin/chflags", ["nouchg", path])
        reply(result.success, result.error)
    }

    // MARK: - ACL 管理

    func setACL(_ path: String,
               deny: Bool,
               permissions: [String],
               user: String,
               withReply reply: @escaping (Bool, String?) -> Void) {
        guard isPathAllowed(path) else {
            reply(false, "Path not allowed: \(path)")
            return
        }

        // 构建 ACL 规则: chmod +a "everyone deny delete,write,append"
        let ruleType = deny ? "deny" : "allow"
        let perms = permissions.joined(separator: ",")
        let rule = "\(user) \(ruleType) \(perms)"

        let result = runCommand("/bin/chmod", ["+a", rule, path])
        reply(result.success, result.error)
    }

    func removeACL(_ path: String,
                  withReply reply: @escaping (Bool, String?) -> Void) {
        guard isPathAllowed(path) else {
            reply(false, "Path not allowed: \(path)")
            return
        }

        // 移除所有 ACL: chmod -N
        let result = runCommand("/bin/chmod", ["-N", path])
        reply(result.success, result.error)
    }

    // MARK: - 状态查询

    func getDirectoryStatus(_ path: String,
                           withReply reply: @escaping (Bool, Bool, String?) -> Void) {
        // 检查 uchg 标志
        let lsResult = runCommand("/bin/ls", ["-lO", path])
        let isLocked = lsResult.output?.contains("uchg") ?? false

        // 检查 ACL
        let aclResult = runCommand("/bin/ls", ["-le", path])
        let hasACL = aclResult.output?.contains("0:") ?? false

        reply(isLocked, hasACL, nil)
    }

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(Self.version)
    }

    // MARK: - 安全验证

    /// 验证路径是否在允许操作的范围内
    private func isPathAllowed(_ path: String) -> Bool {
        let allowedPrefixes = [
            NSHomeDirectory() + "/Downloads_Local",
            NSHomeDirectory() + "/Downloads",
            "/Volumes/"  // 外部硬盘
        ]

        return allowedPrefixes.contains { path.hasPrefix($0) }
    }

    /// 执行命令
    private func runCommand(_ command: String,
                           _ arguments: [String]) -> (success: Bool,
                                                      output: String?,
                                                      error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8)
            let error = String(data: errorData, encoding: .utf8)

            return (process.terminationStatus == 0, output, error)
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    // MARK: - XPC Listener Delegate

    func listener(_ listener: NSXPCListener,
                 shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // 验证连接来源
        guard verifyConnection(newConnection) else {
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: DMSAHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()

        return true
    }

    /// 验证连接是否来自 DMSA.app
    private func verifyConnection(_ connection: NSXPCConnection) -> Bool {
        // 验证代码签名
        let requirement = "identifier \"com.ttttt.dmsa\" and anchor apple generic"
        var code: SecCode?
        var staticCode: SecStaticCode?

        SecCodeCopySelf([], &code)
        // 实际实现需要验证 connection.auditToken

        return true  // 简化示例
    }
}

// 启动 XPC 服务
let delegate = HelperTool()
let listener = NSXPCListener(machServiceName: "com.ttttt.dmsa.helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
```

### 23.5 客户端封装

```swift
// Services/PrivilegedClient.swift
import Foundation
import ServiceManagement

/// 特权操作客户端
class PrivilegedClient {

    static let shared = PrivilegedClient()

    private let helperIdentifier = "com.ttttt.dmsa.helper"
    private var connection: NSXPCConnection?

    // MARK: - Helper 安装

    /// 安装特权助手 (首次运行时调用)
    func installHelper() throws {
        // macOS 13+ 使用 SMAppService
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
            try service.register()
        } else {
            // 旧版本使用 SMJobBless
            var authRef: AuthorizationRef?
            let status = AuthorizationCreate(nil, nil, [], &authRef)

            guard status == errAuthorizationSuccess, let auth = authRef else {
                throw DMSAError.authorizationFailed
            }

            var error: Unmanaged<CFError>?
            let success = SMJobBless(
                kSMDomainSystemLaunchd,
                helperIdentifier as CFString,
                auth,
                &error
            )

            AuthorizationFree(auth, [])

            if !success {
                throw error?.takeRetainedValue() ?? DMSAError.helperInstallFailed
            }
        }
    }

    /// 检查 Helper 是否已安装
    func isHelperInstalled() -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "\(helperIdentifier).plist")
            return service.status == .enabled
        } else {
            // 检查 LaunchDaemon plist 是否存在
            let plistPath = "/Library/LaunchDaemons/\(helperIdentifier).plist"
            return FileManager.default.fileExists(atPath: plistPath)
        }
    }

    // MARK: - XPC 连接

    /// 获取 XPC 代理
    private func getHelper() throws -> DMSAHelperProtocol {
        if connection == nil {
            connection = NSXPCConnection(machServiceName: helperIdentifier,
                                        options: .privileged)
            connection?.remoteObjectInterface = NSXPCInterface(with: DMSAHelperProtocol.self)
            connection?.invalidationHandler = { [weak self] in
                self?.connection = nil
            }
            connection?.resume()
        }

        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
            Logger.error("XPC error: \(error)")
        }) as? DMSAHelperProtocol else {
            throw DMSAError.xpcConnectionFailed
        }

        return proxy
    }

    // MARK: - 公开接口

    /// 锁定目录
    func lockDirectory(_ path: String) async throws {
        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.lockDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.operationFailed(error ?? "Unknown"))
                }
            }
        }
    }

    /// 解锁目录
    func unlockDirectory(_ path: String) async throws {
        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.unlockDirectory(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.operationFailed(error ?? "Unknown"))
                }
            }
        }
    }

    /// 保护目录 (chflags uchg + ACL deny)
    func protectDirectory(_ path: String) async throws {
        let helper = try getHelper()

        // 1. 设置 uchg 标志
        try await lockDirectory(path)

        // 2. 设置 ACL 拒绝规则
        return try await withCheckedThrowingContinuation { continuation in
            helper.setACL(path,
                         deny: true,
                         permissions: ["delete", "write", "append", "writeattr", "writeextattr"],
                         user: "everyone") { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.operationFailed(error ?? "Unknown"))
                }
            }
        }
    }

    /// 解除目录保护
    func unprotectDirectory(_ path: String) async throws {
        let helper = try getHelper()

        // 1. 移除 ACL
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            helper.removeACL(path) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.operationFailed(error ?? "Unknown"))
                }
            }
        }

        // 2. 移除 uchg 标志
        try await unlockDirectory(path)
    }

    /// 获取目录保护状态
    func getDirectoryStatus(_ path: String) async throws -> (isLocked: Bool, hasACL: Bool) {
        let helper = try getHelper()

        return try await withCheckedThrowingContinuation { continuation in
            helper.getDirectoryStatus(path) { isLocked, hasACL, error in
                if let error = error {
                    continuation.resume(throwing: DMSAError.operationFailed(error))
                } else {
                    continuation.resume(returning: (isLocked, hasACL))
                }
            }
        }
    }
}
```

### 23.6 配置文件

#### Helper Info.plist

```xml
<!-- DMSAHelper/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ttttt.dmsa.helper</string>
    <key>CFBundleName</key>
    <string>DMSAHelper</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>SMAuthorizedClients</key>
    <array>
        <string>identifier "com.ttttt.dmsa" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: xxx"</string>
    </array>
</dict>
</plist>
```

#### Helper LaunchDaemon plist

```xml
<!-- com.ttttt.dmsa.helper.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ttttt.dmsa.helper</string>
    <key>MachServices</key>
    <dict>
        <key>com.ttttt.dmsa.helper</key>
        <true/>
    </dict>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/com.ttttt.dmsa.helper</string>
    </array>
</dict>
</plist>
```

#### 主应用 Info.plist 添加

```xml
<!-- DMSAApp/Info.plist 添加 -->
<key>SMPrivilegedExecutables</key>
<dict>
    <key>com.ttttt.dmsa.helper</key>
    <string>identifier "com.ttttt.dmsa.helper" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: xxx"</string>
</dict>
```

### 23.7 安装流程

```
┌─────────────────────────────────────────────────────────────┐
│                      首次启动流程                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ 检查 Helper 状态 │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
     ┌────────────────┐           ┌────────────────┐
     │   已安装且正常   │           │  未安装或过期   │
     └───────┬────────┘           └───────┬────────┘
             │                            │
             │                            ▼
             │                  ┌─────────────────┐
             │                  │ 显示权限请求弹窗  │
             │                  │ "DMSA 需要安装   │
             │                  │  特权助手..."    │
             │                  └────────┬────────┘
             │                           │
             │                           ▼
             │                  ┌─────────────────┐
             │                  │ 用户输入管理员密码 │
             │                  └────────┬────────┘
             │                           │
             │                           ▼
             │                  ┌─────────────────┐
             │                  │  SMJobBless 安装  │
             │                  │  → /Library/     │
             │                  │  PrivilegedHelper│
             │                  │  Tools/          │
             │                  └────────┬────────┘
             │                           │
             └───────────┬───────────────┘
                         │
                         ▼
               ┌─────────────────┐
               │ 保护 LOCAL_DIR   │
               │ (chflags uchg)   │
               └────────┬────────┘
                        │
                        ▼
               ┌─────────────────┐
               │ 启动 VFS 服务    │
               └─────────────────┘
```

### 23.8 安全考量

| 安全点 | 措施 |
|--------|------|
| **代码签名验证** | Helper 验证主应用的代码签名 |
| **路径白名单** | 仅允许操作 LOCAL_DIR、TARGET_DIR、/Volumes/ |
| **最小权限** | Helper 仅暴露必要的特权操作 |
| **XPC 通信加密** | macOS 自动加密 XPC 通道 |
| **审计日志** | 所有特权操作记录到系统日志 |
| **沙箱兼容** | 主应用可保持沙箱，通过 XPC 调用特权操作 |

### 23.9 与 VFS 集成

```swift
// VFSCore.swift 集成示例

class VFSCore {
    private let privilegedClient = PrivilegedClient.shared

    /// VFS 启动时保护目录
    func start() async throws {
        // 确保 Helper 已安装
        if !privilegedClient.isHelperInstalled() {
            try privilegedClient.installHelper()
        }

        // 保护 LOCAL_DIR
        for syncPair in config.syncPairs {
            try await privilegedClient.protectDirectory(syncPair.localDir.path)
        }

        // 挂载 FUSE
        try mountFUSE()
    }

    /// VFS 停止时解除保护
    func stop() async throws {
        // 卸载 FUSE
        try unmountFUSE()

        // 解除 LOCAL_DIR 保护
        for syncPair in config.syncPairs {
            try await privilegedClient.unprotectDirectory(syncPair.localDir.path)
        }
    }

    /// 同步操作前临时解锁
    func performSyncOperation(_ operation: () async throws -> Void) async throws {
        let path = currentSyncPair.localDir.path

        // 解锁
        try await privilegedClient.unlockDirectory(path)

        defer {
            // 重新锁定
            Task {
                try? await privilegedClient.lockDirectory(path)
            }
        }

        // 执行同步操作
        try await operation()
    }
}
```

### 23.10 目录保护矩阵

| 目录 | 保护方式 | 用户可见性 | 用户可操作性 |
|------|----------|------------|--------------|
| **LOCAL_DIR** | chflags uchg + ACL deny | 隐藏 (chflags hidden) | 完全阻止 |
| **EXTERNAL_DIR** | ACL deny write | 可见 (只读) | 禁止写入 |
| **TARGET_DIR** | FUSE 挂载 | 可见 | 通过 VFS 操作 |

**最终效果:**
- 用户只能通过 `~/Downloads` (TARGET_DIR) 访问文件
- `~/Downloads_Local` (LOCAL_DIR) 完全隐藏且锁定
- 外部硬盘上的 `Downloads` 可见但只读
- 所有写入操作通过 VFS 路由到正确位置

---

## 附录

### A. FUSE 回调函数映射

| FUSE 回调 | VFS 组件 | 功能 |
|-----------|----------|------|
| `open()` | ReadRouter | 打开文件，确定数据来源 |
| `read()` | ReadRouter | 读取文件数据 |
| `write()` | WriteRouter | 写入文件数据 |
| `create()` | WriteRouter | 创建新文件 |
| `unlink()` | DeleteRouter | 删除文件 |
| `rename()` | MetadataManager | 重命名文件 |
| `getattr()` | MergeEngine | 获取文件属性 |
| `readdir()` | MergeEngine | 读取目录内容 (智能合并) |
| `mkdir()` | WriteRouter | 创建目录 |
| `rmdir()` | DeleteRouter | 删除目录 |
| `release()` | ReadRouter | 关闭文件 |
| `fsync()` | WriteRouter | 同步文件数据 |

### B. 目录结构

```
~/
├── Downloads/                      # FUSE 挂载点 (虚拟目录)
│   └── (智能合并视图)
│
├── Downloads_Local/                # 本地热数据存储
│   ├── file1.pdf                   # 本地文件 (可淘汰)
│   ├── file2.doc                   # 新文件 (isDirty)
│   └── subdir/
│
└── Library/
    └── Application Support/
        └── DMSA/
            ├── config.json         # 配置文件
            └── Database/           # ObjectBox 数据库
                ├── data.mdb
                └── lock.mdb

/Volumes/BACKUP/                    # 外置硬盘 (完整数据)
└── Downloads/
    ├── file1.pdf
    ├── file3.zip
    └── file4.mp4
```

### C. 配置文件示例 (v3.0)

```json
{
    "version": "3.0",
    "syncPairs": [
        {
            "id": "550e8400-e29b-41d4-a716-446655440001",
            "name": "Downloads",
            "localDir": "~/.Downloads_Local",
            "externalDir": "/Volumes/BACKUP/Downloads",
            "targetDir": "~/Downloads",
            "localQuotaGB": 50,
            "enabled": true
        },
        {
            "id": "550e8400-e29b-41d4-a716-446655440002",
            "name": "Documents",
            "localDir": "~/.Documents_Local",
            "externalDir": "/Volumes/NAS/Documents",
            "targetDir": "~/Documents",
            "localQuotaGB": 100,
            "enabled": true
        }
    ],
    "sync": {
        "autoSync": true,
        "syncIntervalMinutes": 30,
        "debounceSeconds": 5,
        "syncPriority": "fifo",
        "direction": "local_to_external"
    },
    "eviction": {
        "enabled": true,
        "reserveGB": 5,
        "maxEvictPerRound": 100,
        "minFileAgeDays": 7
    },
    "largeFile": {
        "thresholdMB": 1024,
        "chunkSizeMB": 64,
        "enableResume": true,
        "checksumAlgorithm": "sha256"
    },
    "conflict": {
        "strategy": "local_wins",
        "backupPrefix": ".conflict-",
        "autoCleanDays": 0
    }
}
```

### D. FileEntry 完整字段 (v3.0)

```swift
class FileEntry: Entity {
    var id: Id = 0

    // 路径与同步对
    var syncPairId: UUID = UUID()
    var virtualPath: String = ""
    var localPath: String?
    var externalPath: String?

    // 状态
    var locationRaw: Int = 0          // FileLocation
    var lockStateRaw: Int = 0         // LockState
    var syncStatusRaw: Int = 0        // SyncStatus
    var isDirty: Bool = false
    var isDirectory: Bool = false
    var isSymlink: Bool = false

    // 删除相关
    var deletePhase: Int = 0          // 0=未删除, 1-3=删除阶段
    var deleteRequestedAt: Date?
    var pendingExternalDelete: Bool = false

    // 文件属性
    var size: Int64 = 0
    var checksum: String?
    var permissions: Int = 0o644

    // 时间戳
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var accessedAt: Date = Date()
    var syncedAt: Date?
    var syncPausedAt: Date?

    // 大文件续传
    var transferredBytes: Int64 = 0
    var chunksJson: String?

    // 写入状态
    var writeInProgress: Bool = false
}
```

### E. 参考资料

- [FUSE-T](https://www.fuse-t.org/) - 推荐的 FUSE 实现
- [FUSE-T GitHub Wiki](https://github.com/macos-fuse-t/fuse-t/wiki)
- [ObjectBox Swift](https://swift.objectbox.io/) - 数据库文档
- [ObjectBox GitHub](https://github.com/objectbox/objectbox-swift)
- [macFUSE](https://macfuse.github.io/) - 备选方案

---

*文档版本: 3.1 | 最后更新: 2026-01-24*

**v3.1 变更记录:**
- 新增第 23 章：SMJobBless 特权助手工具
- 完整的 XPC 协议设计 (DMSAHelperProtocol)
- Helper Tool 实现 (目录锁定、ACL 管理)
- 客户端封装 (PrivilegedClient)
- 配置文件模板 (Info.plist, LaunchDaemon plist)
- 安装流程和安全考量
- VFS 集成示例
- 目录保护矩阵

**v3.0 变更记录:**
- 多路同步架构 (SyncPair)
- 单向同步 (LOCAL → EXTERNAL)
- 新增 DELETED 状态
- 完整删除流程 (三阶段)
- 冲突解决机制 (LOCAL 优先 + 备份)
- 大文件处理 (分块校验 + 断点续传)
- 权限/符号链接/xattr 同步
- EXTERNAL 断开处理
- 应用生命周期管理
- 文件系统保护机制
