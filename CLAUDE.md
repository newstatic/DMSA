# Delt MACOS Sync App (DMSA) 项目记忆文档

> 此文档供 Claude Code 跨会话持续参考，保持项目上下文记忆。
> 版本: 3.1 | 更新日期: 2026-01-24
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
| **当前版本** | 3.0 |
| **最后更新** | 2026-01-21 |

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

## 核心架构 (v3.0)

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
│        TARGET_DIR ~/Downloads (FUSE 挂载)        │
│              智能合并显示                         │
└─────────────────────────────────────────────────┘
                        │
            ┌───────────┴───────────┐
            ▼                       ▼
┌───────────────────┐   ┌───────────────────┐
│     LOCAL_DIR      │   │   EXTERNAL_DIR    │
│  ~/Downloads_Local │   │ /Volumes/BACKUP/  │
│   (热数据缓存)      │   │ Downloads/ (完整) │
└───────────────────┘   └───────────────────┘
```

### 目录术语定义 (v3.0 统一)

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
│   ├── DMSAApp.xcodeproj/         # Xcode 项目
│   └── DMSAApp/
│       ├── App/AppDelegate.swift   # 主逻辑
│       ├── Models/                 # 数据模型
│       ├── Services/               # 服务层
│       │   ├── Sync/               # 同步引擎
│       │   └── VFS/                # VFS 相关
│       ├── UI/                     # SwiftUI 界面
│       ├── Utils/                  # 工具类
│       └── Resources/              # 资源文件
│
├── CLAUDE.md                       # 本文档
├── VFS_DESIGN.md                   # VFS 设计文档
├── README.md                       # 使用说明
└── *.md                            # 其他文档
```

---

## 关键文件速查

| 文件 | 用途 |
|------|------|
| `AppDelegate.swift` | 主逻辑: 状态栏、磁盘监听、初始化 |
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

*文档维护: 每次会话结束时更新会话索引表*
