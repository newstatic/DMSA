# Delt MACOS Sync App (DMSA) 项目记忆文档

> 此文档供 Claude Code 跨会话持续参考，保持项目上下文记忆。
> 版本: 2.0 | 更新日期: 2026-01-20
> 项目简称: DMSA

---

## 快速上下文

当用户提到以下内容时的参考:

| 用户说 | 指的是 |
|--------|--------|
| "应用" / "DMSA" | macOS 菜单栏应用 `DMSA.app` |
| "同步" | rsync 增量同步，支持双向 |
| "硬盘" | 外置硬盘 (可配置多个，如 BACKUP、PORTABLE) |
| "VFS" | 虚拟文件系统层，基于 Endpoint Security |
| "LOCAL" | 本地缓存后端 `~/Library/Application Support/DMSA/LocalCache/` |
| "EXTERNAL" | 外置硬盘后端 `/Volumes/{DiskName}/` |
| "配置" | JSON 配置文件 `~/Library/Application Support/DMSA/config.json` |
| "数据库" | ObjectBox Swift 嵌入式数据库 |
| "日志" | `~/Library/Logs/DMSA/app.log` |
| "状态栏" | macOS 顶部菜单栏图标 |
| "编译" | `build.sh` 脚本或 `swift build` |
| "扩展" | System Extension (Endpoint Security) |
| "淘汰" | LOCAL 缓存空间管理，按修改时间淘汰旧文件 |
| "脏数据" | 已写入 LOCAL 但尚未同步到 EXTERNAL 的文件 |

**添加条件:**
- 用户多次用某个词指代特定文件/组件
- 新增了重要模块/功能
- 发现了容易混淆的概念

---

## 项目基本信息

| 属性 | 值 |
|------|-----|
| **项目名称** | Delt MACOS Sync App (DMSA) |
| **项目路径** | `/Users/ttttt/Downloads/DMSA` |
| **Bundle ID** | `com.ttttt.dmsa` |
| **Extension ID** | `com.ttttt.dmsa.extension` |
| **最低系统版本** | macOS 11.0 |
| **当前版本** | 2.0 |
| **最后更新** | 2026-01-20 |

---

## 技术栈速查

```
语言: Swift 5.5+
框架: Cocoa, Foundation, EndpointSecurity, SwiftUI
数据库: ObjectBox Swift
同步: rsync
构建: swiftc / Swift Package Manager
平台: macOS (arm64 / x86_64)
类型: 菜单栏应用 (LSUIElement) + System Extension
```

---

## 核心目录结构

```
DMSA/
├── DMSA/
│   ├── Sources/DMSA/
│   │   ├── main.swift              # 应用入口
│   │   ├── App/AppDelegate.swift   # 主逻辑 (状态栏、同步管理)
│   │   ├── Resources/Info.plist    # 应用配置
│   │   └── Resources/DMSA.entitlements
│
├── Extension/                       # System Extension (Endpoint Security)
│   ├── main.swift                  # Extension 入口
│   ├── Info.plist
│   └── Extension.entitlements
│
├── Core/                            # 核心层
│   ├── VFSCore.swift               # 虚拟文件系统核心
│   ├── ReadRouter.swift            # 读取路由器
│   ├── WriteRouter.swift           # 写入路由器
│   └── MetadataManager.swift       # 元数据管理
│
├── Services/                        # 服务层
│   ├── DiskManager.swift           # 硬盘管理
│   ├── SyncEngine.swift            # 同步引擎
│   ├── SyncScheduler.swift         # 同步调度器
│   ├── CacheManager.swift          # 缓存管理
│   └── RsyncWrapper.swift          # rsync 封装
│
├── Models/                          # ObjectBox 实体
│   ├── FileEntry.swift             # 文件索引
│   ├── SyncHistory.swift           # 同步历史
│   ├── DiskConfig.swift            # 硬盘配置
│   ├── SyncPairConfig.swift        # 同步对配置
│   └── SyncStatistics.swift        # 统计数据
│
├── UI/                              # SwiftUI 界面
│   ├── SettingsView.swift          # 设置窗口
│   ├── ProgressView.swift          # 进度窗口
│   └── HistoryView.swift           # 历史列表
│
├── Package.swift                   # SPM 配置
├── README.md                       # 使用说明
├── REQUIREMENTS.md                 # 需求规格
├── TECHNICAL.md                    # 技术架构
├── FLOWCHARTS.md                   # 流程图
├── CONFIGURATIONS.md               # 配置项文档
├── UI_DESIGN.md                    # UI/UX 设计文档
└── IMPLEMENTATION_PLAN.md          # 代码实施计划
```

---

## 运行命令

```bash
# 编译 (SPM)
cd /Users/ttttt/Downloads/DMSA/DMSA
swift build -c release

# 查看编译产物
ls .build/release/DMSA

# 运行
.build/release/DMSA

# 查看日志
tail -f ~/Library/Logs/DMSA/app.log
```

---

## 核心架构 (v2.0)

### 系统分层

```
┌─────────────────────────────────────────────────┐
│                   用户应用层                      │
│              (Finder, Safari, etc.)              │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│            虚拟文件系统层 (VFS)                   │
│           Endpoint Security Framework            │
└─────────────────────────────────────────────────┘
                        │
            ┌───────────┴───────────┐
            ▼                       ▼
┌───────────────────┐   ┌───────────────────┐
│    LOCAL 后端      │   │   EXTERNAL 后端    │
└───────────────────┘   └───────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│             数据持久层 (ObjectBox)                │
└─────────────────────────────────────────────────┘
```

### 文件位置状态

| 状态 | 说明 |
|------|------|
| `NOT_EXISTS` | 文件不存在 |
| `LOCAL_ONLY` | 仅在 LOCAL (待同步) |
| `EXTERNAL_ONLY` | 仅在 EXTERNAL (可拉取) |
| `BOTH` | 两端都有 (已同步) |

### 核心流程

**读取流程:**
```
读取请求 → 查 ObjectBox → LOCAL有? → 返回LOCAL路径
                          ↓ 无
                     EXTERNAL有? → 拉取到LOCAL → 返回
                          ↓ 无
                     返回错误
```

**写入流程 (Write-Back):**
```
写入请求 → 写入LOCAL → 标记dirty → 加入同步队列 → 返回成功
                                        ↓ (异步)
                               EXTERNAL连接? → rsync同步 → 清除dirty
```

---

## 关键文件速查

| 文件 | 用途 |
|------|------|
| `AppDelegate.swift` | 主逻辑: 状态栏、磁盘监听、初始化 |
| `VFSCore.swift` | 虚拟文件系统核心逻辑 |
| `ReadRouter.swift` | 读取路由: LOCAL/EXTERNAL选择 |
| `WriteRouter.swift` | 写入路由: Write-Back策略 |
| `CacheManager.swift` | LOCAL缓存空间管理、淘汰策略 |
| `SyncEngine.swift` | rsync同步执行 |
| `DiskManager.swift` | 硬盘挂载/卸载事件处理 |
| `FileEntry.swift` | ObjectBox文件索引实体 |
| `config.json` | 用户配置文件 |

---

## 代码结构

### 核心组件

| 组件 | 功能 |
|------|------|
| `VFSCore` | Endpoint Security 事件处理 |
| `ReadRouter` | 读取路由决策 |
| `WriteRouter` | 写入路由 + dirty 队列管理 |
| `CacheManager` | 缓存淘汰策略 (按修改时间) |
| `SyncEngine` | rsync 同步执行 |
| `SyncScheduler` | 同步任务调度 |
| `DiskManager` | 硬盘状态监控 |
| `MetadataManager` | 文件元数据管理 |

### ObjectBox 实体

| 实体 | 用途 |
|------|------|
| `FileEntry` | 文件索引 (路径、位置、dirty状态、大小、时间) |
| `SyncHistory` | 同步历史记录 |
| `DiskConfig` | 硬盘配置 |
| `SyncPairConfig` | 同步目录对配置 |
| `SyncStatistics` | 每日统计数据 |

### 关键方法

| 方法 | 位置 | 功能 |
|------|------|------|
| `resolveReadPath()` | ReadRouter | 解析读取路径 |
| `handleWrite()` | WriteRouter | 处理写入请求 |
| `enforceSpaceLimit()` | CacheManager | 执行缓存淘汰 |
| `performSync()` | SyncEngine | 执行 rsync 同步 |
| `handleDiskConnected()` | DiskManager | 硬盘连接处理 |
| `handleDiskDisconnected()` | DiskManager | 硬盘断开处理 |

---

## 配置路径

| 用途 | 路径 |
|------|------|
| 配置文件 | `~/Library/Application Support/DMSA/config.json` |
| 配置备份 | `~/Library/Application Support/DMSA/config.backup.json` |
| LOCAL缓存 | `~/Library/Application Support/DMSA/LocalCache/` |
| 数据库 | `~/Library/Application Support/DMSA/Data/` |
| 日志 | `~/Library/Logs/DMSA/app.log` |
| LaunchAgent | `~/Library/LaunchAgents/com.ttttt.dmsa.plist` |

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

1. **权限要求**:
   - System Extension 批准
   - 完全磁盘访问权限 (TCC)
   - Endpoint Security entitlement (需要 Apple Developer Program)

2. **硬盘格式**:
   - APFS/HFS+ 支持符号链接
   - exFAT/NTFS 仅支持同步，不支持符号链接

3. **缓存管理**:
   - 超过 maxCacheSize 时按修改时间淘汰
   - dirty 文件不会被淘汰

4. **Write-Back**:
   - 写入立即返回成功
   - 异步同步到 EXTERNAL
   - EXTERNAL 离线时队列等待

5. **日志位置**: `~/Library/Logs/DMSA/app.log`

---

## 会话记录

> 会话历史: 项目重构为 v2.0

### 会话索引表

| Session ID | 日期 | 标题 | 摘要 |
|------------|------|------|------|
| (初始化) | 2026-01-20 | 记忆文档初始化 | 创建 CLAUDE.md v1.0 |
| (重构) | 2026-01-20 | v2.0 架构设计 | 需求收集、技术设计、流程图、配置项 |
| (修正) | 2026-01-20 | 文档修正 | 更新 README/CLAUDE 到 v2.0，修正 ObjectBox URL，统一配置路径 |
| (实施) | 2026-01-20 | 核心代码实施 | 多Agent并行执行IMPLEMENTATION_PLAN.md，创建21个Swift源文件，编译通过 |
| (命名) | 2026-01-20 | 项目命名统一 | 重命名目录DownloadsSyncApp→DMSA，更新所有文档路径引用 |
| (UI设计) | 2026-01-20 | UI/UX设计文档 | 创建UI_DESIGN.md，规划菜单栏、设置窗口、进度窗口、历史窗口、首次向导 |

---

### 已完成的代码文件

```
Sources/DMSA/
├── main.swift                          # 应用入口
├── App/AppDelegate.swift               # 应用代理
├── Models/
│   ├── Config.swift                    # 配置数据模型
│   └── Entities/                       # 数据实体
│       ├── FileEntry.swift
│       ├── SyncHistory.swift
│       ├── SyncStatistics.swift
│       ├── DiskConfigEntity.swift
│       └── SyncPairEntity.swift
├── Services/
│   ├── ConfigManager.swift             # 配置管理
│   ├── DatabaseManager.swift           # 数据库管理 (JSON存储)
│   ├── DiskManager.swift               # 硬盘事件管理
│   ├── RsyncWrapper.swift              # rsync封装
│   ├── SyncEngine.swift                # 同步引擎
│   ├── SyncScheduler.swift             # 同步调度
│   ├── FileFilter.swift                # 文件过滤
│   └── NotificationManager.swift       # 通知管理
├── UI/
│   └── MenuBarManager.swift            # 菜单栏管理
├── Utils/
│   ├── Logger.swift                    # 日志系统
│   ├── Constants.swift                 # 常量定义
│   └── Errors.swift                    # 错误类型
└── Resources/
    ├── Info.plist                      # 应用配置
    └── DMSA.entitlements               # 权限配置
```

### 待实施的UI组件

根据 UI_DESIGN.md，下一步需要创建:
- Settings/ (7个设置页面)
- Progress/ (进度窗口)
- History/ (历史窗口)
- Wizard/ (首次向导5步)
- Components/ (可复用组件)

---

*文档维护: 每次会话结束时更新会话索引表*
