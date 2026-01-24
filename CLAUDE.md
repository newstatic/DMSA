# Delt MACOS Sync App (DMSA) 项目记忆文档

> 此文档供 Claude Code 跨会话持续参考，保持项目上下文记忆。
> 版本: 4.4 | 更新日期: 2026-01-24
> 项目简称: DMSA

---

## 快速上下文

当用户提到以下内容时的参考:

| 用户说 | 指的是 |
|--------|--------|
| "应用" / "DMSA" | macOS 菜单栏应用 `DMSA.app` |
| "同步" | 原生增量同步，单向 LOCAL → EXTERNAL |
| "硬盘" | 外置硬盘 (可配置多个，如 BACKUP、PORTABLE) |
| "VFS" | 虚拟文件系统层，FUSE 挂载 |
| "LOCAL_DIR" | 本地热数据目录 `~/Downloads_Local`，用户不直接访问 |
| "EXTERNAL_DIR" | 外置硬盘后端 `/Volumes/{DiskName}/Downloads/`，完整数据源 |
| "TARGET_DIR" | VFS 挂载的 `~/Downloads`，用户唯一访问入口 |
| "Downloads_Local" | LOCAL_DIR 的别名 |
| "虚拟 Downloads" | TARGET_DIR 的别名 |
| "EXTERNAL" | EXTERNAL_DIR 的简称 |
| "配置" | JSON 配置文件 `~/Library/Application Support/DMSA/config.json` |
| "数据库" | ObjectBox 数据库 `~/Library/Application Support/DMSA/Database/` |
| "淘汰" | LRU 淘汰机制，基于访问时间清理本地缓存 |
| "版本文件" | `.FUSE/db.json`，存储文件树版本和元数据 |
| "树版本" | 文件树状态的版本号，用于检测变更 |
| "日志" | `~/Library/Logs/DMSA/app.log` |
| "状态栏" | macOS 顶部菜单栏图标 |
| "编译" | Xcode 编译或 `swift build` |
| "脏数据" | 已写入 LOCAL_DIR 但尚未同步到 EXTERNAL_DIR 的文件 |
| "智能合并" | TARGET_DIR 显示 LOCAL_DIR + EXTERNAL_DIR 的并集 |

**添加条件:**
- 用户多次用某个词指代特定文件/组件
- 新增了重要模块/功能
- 发现了容易混淆的概念

---

## 项目基本信息

| 属性 | 值 |
|------|-----|
| **项目名称** | Delt MACOS Sync App (DMSA) |
| **项目路径** | `/Users/ttttt/Documents/xcodeProjects/DMSA` |
| **Bundle ID** | `com.ttttt.dmsa` |
| **最低系统版本** | macOS 11.0 |
| **当前版本** | 4.2 |
| **最后更新** | 2026-01-24 |

---

## 技术栈速查

```
语言: Swift 5.5+
框架: Cocoa, Foundation, SwiftUI
VFS: macFUSE 5.1.3+ (使用 GMUserFileSystem)
存储: ObjectBox (高性能嵌入式数据库)
同步: 原生 Swift 同步引擎
构建: Xcode / Swift Package Manager
平台: macOS (arm64 / x86_64)
类型: 菜单栏应用 (LSUIElement)
```

---

## 核心架构 (v4.1 - 双进程统一服务架构)

### 系统分层

```
┌─────────────────────────────────────────────────────────────────────┐
│                         用户态 (User Space)                          │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    DMSA.app (菜单栏应用)                        │  │
│  │                       普通用户权限                              │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────┐   │  │
│  │  │   GUI   │  │Settings │  │ Status  │  │  ServiceClient  │   │  │
│  │  │ Manager │  │  View   │  │ Display │  │  (统一 XPC)     │   │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                    │                                 │
│                            XPC 通信 │                                 │
│                                    ▼                                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                       系统态 (System Space)                          │
│                        LaunchDaemon (root)                          │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │               com.ttttt.dmsa.service (统一服务)                 │  │
│  │                                                                │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐    │  │
│  │  │ VFSManager  │  │ SyncManager │  │ PrivilegedOperations│    │  │
│  │  │  (Actor)    │  │   (Actor)   │  │     (Static)        │    │  │
│  │  │             │  │             │  │                     │    │  │
│  │  │• FUSE 挂载   │  │• 文件同步   │  │• 目录保护           │    │  │
│  │  │• 智能合并   │  │• 定时调度    │  │• ACL 管理           │    │  │
│  │  │• 读写路由   │  │• 冲突解决    │  │• 权限控制           │    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### 双进程架构组件

| 组件 | 进程标识 | 权限 | 职责 |
|------|----------|------|------|
| **DMSA.app** | 主应用 | 用户 | GUI、状态显示、配置管理、用户交互 |
| **DMSAService** | `com.ttttt.dmsa.service` | root | VFS + Sync + Privileged 统一服务 |

### 架构优势 (v4.1)

1. **GUI 退出不影响核心服务**: 统一服务继续运行，文件始终可访问
2. **简化 XPC 通信**: 只需一个 XPC 连接，减少复杂度
3. **root 权限运行**: 单一 LaunchDaemon 解决所有权限问题
4. **自动恢复**: launchd 自动重启崩溃的服务
5. **资源共享**: VFS/Sync/Privileged 共享内存和上下文，性能更好
6. **统一配置**: 一处配置，避免多服务配置不同步问题

### 目录术语定义

| 术语 | 路径 | 说明 |
|------|------|------|
| **LOCAL_DIR** | `~/Downloads_Local` | 本地热数据缓存，用户不直接访问 |
| **EXTERNAL_DIR** | `/Volumes/{DiskName}/Downloads/` | 外部完整数据源 (Source of Truth) |
| **TARGET_DIR** | `~/Downloads` | FUSE 挂载点，用户唯一访问入口 |

**术语映射:**
```
~/Downloads         → TARGET_DIR   (用户看到的目标目录)
~/Downloads_Local   → LOCAL_DIR    (本地热数据缓存)
/Volumes/BACKUP/Downloads → EXTERNAL_DIR (外部完整备份)
```

### 文件位置状态 (v3.0)

| 状态 | 说明 |
|------|------|
| `NOT_EXISTS` | 文件不存在 |
| `LOCAL_ONLY` | 仅在 LOCAL_DIR (待同步) |
| `EXTERNAL_ONLY` | 仅在 EXTERNAL_DIR (可直接读取) |
| `BOTH` | 两端都有 (已同步) |
| `DELETED` | EXTERNAL_DIR 被外部删除，本地无数据 |

### 核心流程

**智能合并 (readdir):**
```
TARGET_DIR = LOCAL_DIR ∪ EXTERNAL_DIR
             (两端文件的并集)
```

**读取流程 (v3.0 零拷贝):**
```
读取请求 → 检查文件位置 → LOCAL_DIR 有? → 从 LOCAL_DIR 读取
                              ↓ 无
                     EXTERNAL_DIR 有? → 直接重定向读取 (不复制)
                              ↓ 无
                     返回错误
```

**淘汰流程 (LRU):**
```
写入触发空间检查 → 空间不足? → 查询可淘汰文件 (BOTH + 非脏 + 按访问时间排序)
                                    ↓
                             验证 EXTERNAL_DIR 存在? → 不存在则先同步 → 同步失败则跳过
                                    ↓ 存在
                             删除 LOCAL_DIR 文件 → 更新状态为 EXTERNAL_ONLY
```

**写入流程 (Write-Back):**
```
写入请求 → 写入 LOCAL_DIR → 标记 isDirty → 同步更新版本文件 → 返回成功
                                    ↓ (异步)
                           EXTERNAL_DIR 连接? → 同步 → 清除 isDirty
```

**启动时版本检查流程:**
```
启动 → 读取 LOCAL_DIR/.FUSE/db.json → 读取 EXTERNAL_DIR/.FUSE/db.json (如已连接)
                    ↓
     比对 ObjectBox 存储的版本 → 一致? → 直接使用缓存数据
                    ↓ 不一致或不存在
            触发文件树重建 → 更新版本文件 → 更新 ObjectBox
```

---

## 核心目录结构

```
DMSA/
├── DMSAApp/
│   ├── DMSAApp.xcodeproj/         # Xcode 项目 (含 DMSAService Target)
│   ├── DMSAApp/                    # 主应用
│   │   ├── App/AppDelegate.swift   # 主逻辑
│   │   ├── Models/                 # 数据模型
│   │   ├── Services/               # 服务层
│   │   │   ├── ServiceClient.swift # 统一 XPC 客户端 (新)
│   │   │   ├── Sync/               # 同步引擎
│   │   │   └── VFS/                # VFS 相关
│   │   ├── UI/                     # SwiftUI 界面
│   │   ├── Utils/                  # 工具类
│   │   └── Resources/              # 资源文件
│   │
│   ├── DMSAService/                # 统一服务 (新 - 替代三个旧服务)
│   │   ├── main.swift              # 入口点
│   │   ├── ServiceDelegate.swift   # NSXPCListener 委托
│   │   ├── ServiceImplementation.swift # XPC 协议实现
│   │   ├── VFS/                    # VFS 模块
│   │   │   ├── VFSManager.swift    # VFS Actor
│   │   │   └── VFSFileSystem.swift # FUSE 文件系统
│   │   ├── Sync/                   # 同步模块
│   │   │   └── SyncManager.swift   # Sync Actor
│   │   ├── Privileged/             # 特权操作模块
│   │   │   └── PrivilegedOperations.swift # 静态方法
│   │   └── Resources/
│   │       ├── Info.plist
│   │       ├── DMSAService.entitlements
│   │       └── com.ttttt.dmsa.service.plist
│   │
│   └── DMSAShared/                 # 共享代码
│       ├── Protocols/
│       │   └── DMSAServiceProtocol.swift # 统一 XPC 协议
│       ├── Models/
│       └── Utils/
│
├── CLAUDE.md                       # 本文档
├── VFS_DESIGN.md                   # VFS 设计文档
├── XCODE_PROJECT_UPDATE_GUIDE.md   # Xcode 配置指南 (新)
├── README.md                       # 使用说明
└── *.md                            # 其他文档
```

---

## 关键文件速查

### 主应用 (DMSAApp)

| 文件 | 用途 |
|------|------|
| `AppDelegate.swift` | 主逻辑: 状态栏、磁盘监听、初始化 |
| `ServiceClient.swift` | **统一 XPC 客户端** (v4.1 新增) |
| `FUSEManager.swift` | macFUSE 检测、版本验证、安装引导 |
| `DMSAFileSystem.swift` | GMUserFileSystem 委托实现 |
| `VFSCore.swift` | FUSE 操作入口，挂载/卸载管理 |
| `MergeEngine.swift` | 智能合并引擎 (目录列表合并) |
| `ReadRouter.swift` | 读取路由 |
| `WriteRouter.swift` | 写入路由，Write-Back 策略 |
| `LockManager.swift` | 文件锁管理 |
| `SyncEngine.swift` | 同步引擎 |
| `DiskManager.swift` | 硬盘挂载/卸载事件处理 |
| `FileEntry.swift` | 文件索引实体 |
| `config.json` | 用户配置文件 |
| `DMSAApp-Bridging-Header.h` | Objective-C 桥接头 (macFUSE) |
| `PathValidator.swift` | 路径安全验证工具 |

### 统一服务 (DMSAService) - v4.1 新增

| 文件 | 用途 |
|------|------|
| `main.swift` | 服务入口点，启动 XPC 监听 |
| `ServiceDelegate.swift` | NSXPCListenerDelegate 实现 |
| `ServiceImplementation.swift` | DMSAServiceProtocol 实现 |
| `VFS/VFSManager.swift` | VFS Actor，管理挂载点 |
| `VFS/VFSFileSystem.swift` | FUSE 文件系统实现 |
| `Sync/SyncManager.swift` | Sync Actor，文件同步调度 |
| `Privileged/PrivilegedOperations.swift` | 特权操作静态方法 |

### 共享代码 (DMSAShared)

| 文件 | 用途 |
|------|------|
| `DMSAServiceProtocol.swift` | **统一 XPC 协议** (v4.1 新增) |
| `Constants.swift` | 全局常量，包含 `serviceId` |
| `Errors.swift` | 错误类型定义 |
| `Logger.swift` | 日志工具 |

---

## 配置路径

| 用途 | 路径 |
|------|------|
| 配置文件 | `~/Library/Application Support/DMSA/config.json` |
| 配置备份 | `~/Library/Application Support/DMSA/config.backup.json` |
| 数据库 | `~/Library/Application Support/DMSA/Database/` |
| 日志 | `~/Library/Logs/DMSA/app.log` |
| LaunchAgent | `~/Library/LaunchAgents/com.ttttt.dmsa.plist` |

**注意:** 不再使用 `LocalCache` 目录，本地存储直接使用 `~/Downloads_Local`。

---

## 运行命令

```bash
# Xcode 编译
cd /Users/ttttt/Documents/xcodeProjects/DMSA/DMSAApp
xcodebuild -scheme DMSAApp -configuration Release

# 或者 SPM 编译
swift build -c release

# 查看日志
tail -f ~/Library/Logs/DMSA/app.log
```

---

## 菜单功能

| 菜单项 | 快捷键 | 功能 |
|--------|--------|------|
| 硬盘状态 | - | 显示各硬盘连接状态 |
| 模式显示 | - | 显示各目录当前指向 |
| 立即同步 | ⌘S | 触发手动同步 |
| 同步历史 | ⌘H | 打开历史列表 |
| 打开 Downloads | ⌘O | 打开 Downloads 目录 |
| 查看日志 | ⌘L | 打开日志文件 |
| 设置 | ⌘, | 打开设置窗口 |
| 退出 | ⌘Q | 退出应用 |

---

## 注意事项

1. **首次设置**:
   - 检测 ~/Downloads 是否存在
   - 存在则重命名为 ~/Downloads_Local
   - 创建 FUSE 挂载点 ~/Downloads
   - 挂载 VFS 开始智能合并

2. **权限要求**:
   - macFUSE 5.1.3+ (从 https://macfuse.github.io/ 下载)
   - 完全磁盘访问权限 (TCC)

3. **硬盘格式**:
   - APFS/HFS+ 完全支持
   - exFAT/NTFS 支持同步

4. **Write-Back**:
   - 写入立即返回成功（写入 Downloads_Local）
   - 异步同步到 EXTERNAL
   - EXTERNAL 离线时队列等待

5. **日志位置**: `~/Library/Logs/DMSA/app.log`

---

## 已知问题与修复记录

### UI 卡死问题 (2026-01-21 已修复)

**问题现象**: 点击同步后 UI 卡死

**根本原因**: 进度回调过于频繁

**修复方案**:
- 进度回调节流 100ms
- 日志批量刷新
- 异步数据加载

---

## 会话记录

### 会话索引表

| Session ID | 日期 | 标题 | 摘要 |
|------------|------|------|------|
| (初始化) | 2026-01-20 | 记忆文档初始化 | 创建 CLAUDE.md v1.0 |
| (重构) | 2026-01-20 | v2.0 架构设计 | 需求收集、技术设计 |
| (实施) | 2026-01-20 | 核心代码实施 | 创建21个Swift源文件 |
| (性能修复) | 2026-01-21 | UI卡死修复 | 进度回调节流 |
| (架构纠正) | 2026-01-21 | v2.1 架构纠正 | 移除 LocalCache，使用 Downloads_Local |
| (macFUSE集成) | 2026-01-24 | macFUSE 集成 | VFS 核心组件实现 |
| (Helper集成) | 2026-01-24 | DMSAHelper 集成 | SMJobBless 特权助手 Target |
| **(服务合并)** | **2026-01-24** | **v4.1 服务统一** | **VFS+Sync+Helper 合并为 DMSAService** |
| **(FUSE迁移)** | **2026-01-24** | **v4.2 FUSE服务迁移** | **FUSE挂载从DMSAApp移至DMSAService** |
| **(LRU淘汰)** | **2026-01-24** | **v4.3 EvictionManager** | **DMSAService中实现LRU淘汰机制** |
| **(架构清理)** | **2026-01-24** | **v4.4 业务逻辑迁移** | **全部业务逻辑迁移到DMSAService** |

---

### 架构变更记录 (v2.1)

**2026-01-21 架构纠正:**

| 变更项 | 旧设计 | 新设计 |
|--------|--------|--------|
| 本地存储 | `~/Library/.../LocalCache/` | `~/Downloads_Local` |
| 缓存管理 | CacheManager 管理淘汰 | 不需要，直接使用本地目录 |
| VFS 显示 | 单一来源路由 | 智能合并 (并集显示) |
| 首次设置 | 无 | 重命名 ~/Downloads → ~/Downloads_Local |

**已完成的代码清理 (2026-01-21):**

| 文件 | 操作 |
|------|------|
| `CacheManager.swift` | 已删除 |
| `CacheSettingsView.swift` | 已删除 |
| `Constants.swift` | 移除 `localCache`，添加 `downloadsLocal`、`virtualDownloads` |
| `ReadRouter.swift` | 改用 `Downloads_Local` 路径 |
| `WriteRouter.swift` | 改用 `Downloads_Local` 路径 |
| `NativeSyncEngine.swift` | 更新虚拟路径提取逻辑 |
| `SyncScheduler.swift` | 更新路径匹配逻辑 |
| `AdvancedSettingsView.swift` | 移除 LocalCache 清理代码 |
| `project.pbxproj` | 移除已删除文件的引用 |

---

### 已完成的代码文件

```
DMSAApp/DMSAApp/
├── main.swift
├── App/AppDelegate.swift
├── Models/
│   ├── Config.swift
│   └── Entities/
│       ├── FileEntry.swift
│       ├── SyncHistory.swift
│       └── ...
├── Services/
│   ├── DatabaseManager.swift
│   ├── DiskManager.swift
│   ├── SyncEngine.swift
│   ├── SyncScheduler.swift
│   └── Sync/
│       ├── NativeSyncEngine.swift
│       ├── FileScanner.swift
│       └── ...
├── UI/
│   ├── MenuBarManager.swift
│   └── Views/
│       └── ...
└── Utils/
    ├── Logger.swift
    ├── Constants.swift
    └── Errors.swift
```

### 已实现的 VFS 组件

| 组件 | 状态 | 说明 |
|------|------|------|
| `FUSEManager.swift` | ✅ 已实现 | macFUSE 检测、版本验证、安装引导 |
| `DMSAFileSystem.swift` | ✅ 已实现 | GMUserFileSystem 委托，实现所有 FUSE 回调 |
| `VFSCore.swift` | ✅ 已实现 | FUSE 操作入口，挂载/卸载管理 |
| `MergeEngine.swift` | ✅ 已实现 | 智能合并引擎 (目录列表合并) |
| `ReadRouter.swift` | ✅ 已实现 | 读取路由，支持从 Downloads_Local 或 EXTERNAL 读取 |
| `WriteRouter.swift` | ✅ 已实现 | 写入路由，Write-Back 策略 |
| `LockManager.swift` | ✅ 已实现 | 文件锁管理 |
| `VFSError.swift` | ✅ 已实现 | VFS 错误类型 |
| `VFSFileSystem.swift` | ✅ 已实现 | FUSEFileSystemOperations 协议实现 |
| `FUSEBridge.swift` | ✅ 已实现 | FUSE 结果类型和协议定义 |

---

### macFUSE 集成 (2026-01-24)

**集成方案:**
- 使用 macFUSE 5.1.3+ (非 FUSE-T，因 FUSE-T 服务器组件闭源)
- 通过 GMUserFileSystem 类挂载虚拟文件系统
- Objective-C 桥接头文件导入 macFUSE Framework

**启动时检测流程:**
```
启动 → FUSEManager.checkFUSEAvailability()
         ↓
    检查 /Library/Frameworks/macFUSE.framework 存在?
         ↓ 不存在
    显示安装引导对话框 → 打开 https://macfuse.github.io/
         ↓ 存在
    检查 Framework 完整性 (Headers/fuse.h, Versions/A/macFUSE)
         ↓ 不完整
    显示重新安装提示
         ↓ 完整
    检查版本 >= 4.0.0?
         ↓ 版本过旧
    显示更新建议
         ↓ 版本 OK
    尝试加载 Bundle 并验证 GMUserFileSystem 类
         ↓ 成功
    返回 .available(version)
```

**Xcode 配置:**
- Framework Search Paths: `/Library/Frameworks`
- LD_RUNPATH_SEARCH_PATHS: `/Library/Frameworks`
- Bridging Header: `DMSAApp/DMSAApp-Bridging-Header.h`

**DMSAFileSystem 委托方法:**
- 目录: `contentsOfDirectory`, `createDirectory`, `removeDirectory`
- 属性: `attributesOfItem`, `attributesOfFileSystem`
- 文件: `openFile`, `readFile`, `writeFile`, `truncateFile`, `createFile`, `removeItem`, `moveItem`
- 扩展属性: `extendedAttributeNames`, `value/set/removeExtendedAttribute`

---

### DMSAHelper 特权助手集成 (2026-01-24) - 已废弃

> ⚠️ **注意:** DMSAHelper 已被 DMSAService 统一服务取代 (v4.1)

**用途:** (历史记录)
- 保护 `~/Downloads_Local` 目录 (设置 uchg + ACL + hidden)
- 以 root 权限执行目录保护/解保护操作
- 通过 XPC 与主应用通信

---

### v4.1 统一服务架构 (2026-01-24)

**变更概要:**
将三个独立服务 (VFS, Sync, Helper) 合并为单一 DMSAService。

| 变更项 | v4.0 (旧) | v4.1 (新) |
|--------|-----------|-----------|
| 服务数量 | 3 个独立 LaunchDaemon | 1 个统一 LaunchDaemon |
| XPC 连接 | 3 个独立连接 | 1 个统一连接 |
| 服务标识 | `vfs`, `sync`, `helper` | `com.ttttt.dmsa.service` |
| 配置文件 | 3 个 plist | 1 个 plist |

**新建文件:**

| 文件 | 说明 |
|------|------|
| `DMSAService/main.swift` | 服务入口，启动 XPC 监听 |
| `DMSAService/ServiceDelegate.swift` | NSXPCListenerDelegate |
| `DMSAService/ServiceImplementation.swift` | 协议实现，调度 VFS/Sync/Privileged |
| `DMSAService/VFS/VFSManager.swift` | VFS Actor |
| `DMSAService/VFS/VFSFileSystem.swift` | FUSE 文件系统 |
| `DMSAService/Sync/SyncManager.swift` | Sync Actor |
| `DMSAService/Privileged/PrivilegedOperations.swift` | 特权静态方法 |
| `DMSAService/Resources/Info.plist` | Bundle 配置 |
| `DMSAService/Resources/DMSAService.entitlements` | 权限配置 |
| `DMSAService/Resources/com.ttttt.dmsa.service.plist` | LaunchDaemon 配置 |
| `DMSAShared/Protocols/DMSAServiceProtocol.swift` | 统一 XPC 协议 |
| `DMSAApp/Services/ServiceClient.swift` | 统一 XPC 客户端 |

**旧服务备份:**

| 目录 | 备份位置 |
|------|----------|
| `DMSAVFSService/` | `DMSAVFSService.backup/` |
| `DMSASyncService/` | `DMSASyncService.backup/` |
| `DMSAHelper/` | `DMSAHelper.backup/` |

**XPC 协议 (DMSAServiceProtocol):**

协议统一了所有 VFS、Sync、Privileged 操作:

```swift
@objc public protocol DMSAServiceProtocol {
    // VFS 操作
    func vfsMount(syncPairId: String, localDir: String, externalDir: String?, targetDir: String, withReply: ...)
    func vfsUnmount(syncPairId: String, withReply: ...)
    func vfsGetFileStatus(virtualPath: String, syncPairId: String, withReply: ...)
    // ... 更多 VFS 方法

    // 同步操作
    func syncNow(syncPairId: String, withReply: ...)
    func syncAll(withReply: ...)
    func syncGetProgress(syncPairId: String, withReply: ...)
    // ... 更多 Sync 方法

    // 特权操作
    func privilegedLockDirectory(_ path: String, withReply: ...)
    func privilegedProtectDirectory(_ path: String, withReply: ...)
    // ... 更多 Privileged 方法

    // 通用操作
    func getVersion(withReply: ...)
    func healthCheck(withReply: ...)
}
```

**Xcode 项目配置指南:**

详见 `XCODE_PROJECT_UPDATE_GUIDE.md`，主要步骤:
1. 添加 `com.ttttt.dmsa.service` Command Line Tool target
2. 配置 Build Settings (macFUSE Framework 路径等)
3. 添加 DMSAService 源文件到 target
4. 添加 DMSAShared 共享文件到 target
5. 配置 DMSAApp 依赖新 target
6. 配置 Copy Files Build Phase
7. 更新主应用 Info.plist (SMPrivilegedExecutables)

**Constants 更新:**

```swift
// 新增
public static let serviceId = "com.ttttt.dmsa.service"

public enum XPCService {
    public static let service = "com.ttttt.dmsa.service"

    // 已废弃
    @available(*, deprecated, message: "Use service instead")
    public static let vfs = "com.ttttt.dmsa.vfs"
    @available(*, deprecated, message: "Use service instead")
    public static let sync = "com.ttttt.dmsa.sync"
    @available(*, deprecated, message: "Use service instead")
    public static let helper = "com.ttttt.dmsa.helper"
}
```

---

### v4.2 FUSE 服务迁移 (2026-01-24)

**变更概要:**
将 macFUSE 挂载从 DMSAApp 移至 DMSAService，实现完全的服务端 FUSE 管理。

| 变更项 | v4.1 (旧) | v4.2 (新) |
|--------|-----------|-----------|
| FUSE 挂载位置 | DMSAApp 直接挂载 | DMSAService 通过 XPC 挂载 |
| DMSAFileSystem | DMSAApp/Services/VFS/ | 已删除 |
| FUSEFileSystem | DMSAService/VFS/VFSFileSystem.swift (模拟) | DMSAService/VFS/FUSEFileSystem.swift (实际) |
| VFSCore 调用方式 | 直接创建 DMSAFileSystem 实例 | 通过 ServiceClient.mountVFS() XPC 调用 |

**新建文件:**

| 文件 | 说明 |
|------|------|
| `DMSAService/VFS/FUSEFileSystem.swift` | macFUSE GMUserFileSystem 委托实现 |

**删除文件:**

| 文件 | 说明 |
|------|------|
| `DMSAApp/Services/VFS/DMSAFileSystem.swift` | 原 App 端 FUSE 实现 |
| `DMSAService/VFS/VFSFileSystem.swift` | 原模拟实现 |

**修改文件:**

| 文件 | 变更 |
|------|------|
| `DMSAService/VFS/VFSManager.swift` | 使用 FUSEFileSystem 替代 VFSFileSystem |
| `DMSAApp/Services/VFS/VFSCore.swift` | 改用 XPC 调用 serviceClient.mountVFS() |
| `DMSAShared/Utils/Errors.swift` | 添加 VFSError.externalOffline |

**架构优势:**

1. **GUI 退出不影响 FUSE**: 挂载由 DMSAService 管理，App 退出后文件系统继续可用
2. **权限统一**: FUSE 挂载在 root 服务中进行，避免权限问题
3. **简化 App 代码**: App 不再需要处理 FUSE 细节，只通过 XPC 交互

---

### v4.3 EvictionManager LRU 淘汰 (2026-01-24)

**变更概要:**
在 DMSAService 中实现 LRU (Least Recently Used) 淘汰机制，自动管理本地缓存空间。

**新建文件:**

| 文件 | 说明 |
|------|------|
| `DMSAService/VFS/EvictionManager.swift` | LRU 淘汰管理器 (actor) |

**修改文件:**

| 文件 | 变更 |
|------|------|
| `DMSAService/ServiceImplementation.swift` | 添加 EvictionManager 实例和 XPC 方法 |
| `DMSAShared/Protocols/DMSAServiceProtocol.swift` | 添加淘汰相关 XPC 协议方法 |
| `DMSAApp/Services/VFS/VFSCore.swift` | 集成 TreeVersionManager 版本检查 |

**EvictionManager 功能:**

| 功能 | 说明 |
|------|------|
| 自动淘汰 | 定时检查空间，低于阈值时自动触发淘汰 |
| 手动淘汰 | 支持按需淘汰指定文件 |
| LRU 排序 | 按访问时间排序，优先淘汰最久未访问的文件 |
| 安全检查 | 仅淘汰已同步到 EXTERNAL 的非脏文件 |
| 预取支持 | 支持从 EXTERNAL 预取文件到 LOCAL |

**淘汰流程:**
```
空间不足 → 获取候选文件 (BOTH + 非脏 + 非锁定)
              ↓
    按 accessedAt 排序 (最旧优先)
              ↓
    检查 EXTERNAL 存在? → 不存在则跳过
              ↓ 存在
    删除 LOCAL 文件 → 更新索引 → 释放空间
              ↓
    达到目标空间或处理完毕
```

**XPC 接口 (新增):**

```swift
// 触发淘汰
func evictionTrigger(syncPairId: String, targetFreeSpace: Int64, withReply: ...)
// 淘汰单个文件
func evictionEvictFile(virtualPath: String, syncPairId: String, withReply: ...)
// 预取文件
func evictionPrefetchFile(virtualPath: String, syncPairId: String, withReply: ...)
// 获取统计
func evictionGetStats(withReply: ...)
// 更新配置
func evictionUpdateConfig(triggerThreshold: Int64, targetFreeSpace: Int64, autoEnabled: Bool, withReply: ...)
```

**配置参数:**

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `triggerThreshold` | 5GB | 触发淘汰的可用空间阈值 |
| `targetFreeSpace` | 10GB | 淘汰目标可用空间 |
| `maxFilesPerRun` | 100 | 单次淘汰最大文件数 |
| `minFileAge` | 1小时 | 最小文件年龄 (防止淘汰新文件) |
| `checkInterval` | 5分钟 | 自动检查间隔 |

**同步集成:**
- TreeVersionManager 在 VFSCore.mount() 中启用
- 启动时自动检查版本文件，按需重建文件树

---

### v4.4 架构清理 - 业务逻辑全面迁移 (2026-01-24)

**变更概要:**
将 DMSAApp 中剩余的业务逻辑代码全面迁移到 DMSAService，App 端仅保留 UI 和 XPC 客户端。

| 维度 | v4.3 (旧) | v4.4 (新) |
|------|-----------|-----------|
| **DMSAApp 代码量** | ~8000 行 | ~2500 行 |
| **DMSAApp 职责** | UI + 部分业务逻辑 | 纯 UI 客户端 |
| **数据管理** | App 端持久化 | Service 端持久化 |
| **文件监控** | App 端 FSEvents | Service 端 FSEvents |

**Phase 1: 同步逻辑迁移**

已迁移到 `DMSAService/Sync/`:
- NativeSyncEngine.swift
- FileScanner.swift
- FileHasher.swift
- DiffEngine.swift
- FileCopier.swift
- ConflictResolver.swift
- SyncStateManager.swift

**Phase 2: VFS 代码清理**

已迁移到 `DMSAService/VFS/`:
- MergeEngine.swift
- ReadRouter.swift
- WriteRouter.swift
- LockManager.swift

**Phase 3: 数据管理迁移**

新建 `DMSAService/Data/`:
- ServiceDatabaseManager.swift - 完整数据库管理
- ServiceTreeVersionManager.swift - 文件树版本管理
- ServiceConfigManager.swift - 配置管理

App 端变更:
- DatabaseManager.swift → 仅内存缓存，通过 XPC 获取数据
- TreeVersionManager.swift → XPC 客户端包装

**Phase 4: 监控迁移**

新建 `DMSAService/Monitor/`:
- ServiceFSEventsMonitor.swift - 文件系统监控
- ServiceDiskMonitor.swift - 磁盘状态管理

App 端变更:
- DiskManager.swift → 精简为事件通知 + UI 回调

**Phase 5: AppDelegate 重构**

| 变更项 | 旧 | 新 |
|--------|-----|-----|
| 代码行数 | ~500 行 | ~320 行 |
| SyncEngine 依赖 | 直接调用 | 通过 XPC |
| 同步回调 | SyncEngineDelegate | 无 |
| 业务逻辑 | 混合 | 纯 UI |

**新增 XPC 协议方法:**

```swift
// 数据查询
func dataGetFileEntry(virtualPath: String, syncPairId: String, withReply: ...)
func dataGetAllFileEntries(syncPairId: String, withReply: ...)
func dataGetSyncHistory(limit: Int, withReply: ...)
func dataGetTreeVersion(syncPairId: String, source: String, withReply: ...)
func dataCheckTreeVersions(localDir: String, externalDir: String?, syncPairId: String, withReply: ...)
func dataRebuildTree(rootPath: String, syncPairId: String, source: String, withReply: ...)
func dataInvalidateTreeVersion(syncPairId: String, source: String, withReply: ...)
```

**DMSAService 最终目录结构:**

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

**DMSAApp 最终目录结构:**

```
DMSAApp/
├── App/
│   └── AppDelegate.swift          # ~320 行，纯生命周期管理
├── Services/
│   ├── ServiceClient.swift        # XPC 客户端
│   ├── ConfigManager.swift        # 配置管理
│   ├── DatabaseManager.swift      # 内存缓存
│   ├── DiskManager.swift          # 事件通知
│   ├── TreeVersionManager.swift   # XPC 包装
│   └── FUSEManager.swift          # macFUSE 检测
├── UI/
│   ├── MenuBarManager.swift
│   ├── AlertManager.swift
│   └── Views/
└── Utils/
    ├── Constants.swift
    └── Logger.swift
```

**架构优势:**

1. **App 退出无影响**: 所有核心功能在 Service 中运行
2. **代码职责清晰**: App = UI，Service = 业务逻辑
3. **维护更简单**: 业务逻辑集中在一处
4. **测试更容易**: Service 可独立测试

---

*文档维护: 每次会话结束时更新会话索引表*
