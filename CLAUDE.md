# DMSA 项目记忆文档

> 此文档供 Claude Code 跨会话持续参考，保持项目上下文记忆。
> 详细会话记录见 `CLAUDE_SESSIONS.md`。
> 版本: 5.3 | 更新日期: 2026-01-28

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
| "Service" | `DMSAService` 统一后台服务 (root 权限) |
| "XPC" | App 与 Service 的通信机制 |
| "ServiceClient" | App 端 XPC 客户端 `ServiceClient.swift` |
| "pbxproj_tool" | Xcode 项目管理工具 `pbxproj_tool.rb` (Ruby)，支持 list/add/remove/check/fix/smart-fix |
| "smart-fix" | pbxproj_tool 智能修复命令，自动检测并添加缺失文件 |

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
| **当前版本** | 4.9 |
| **最后更新** | 2026-01-28 |

---

## 技术栈速查

```
语言: Swift 5.5+
框架: Cocoa, Foundation, SwiftUI
VFS: macFUSE 5.1.3+ (C libfuse wrapper)
存储: ObjectBox (高性能嵌入式数据库)
同步: 原生 Swift 同步引擎
构建: Xcode / Swift Package Manager
平台: macOS (arm64 / x86_64)
类型: 菜单栏应用 (LSUIElement)
架构: 双进程 (App + Service)
```

---

## 核心架构 (v4.8 - 纯 UI 架构 + 分布式通知)

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
| **DMSA.app** | 主应用 | 用户 | 纯 UI、状态显示、用户交互 |
| **DMSAService** | `com.ttttt.dmsa.service` | root | VFS + Sync + Privileged + 数据管理 |

### 架构优势

1. **GUI 退出不影响核心服务**: 统一服务继续运行，文件始终可访问
2. **简化 XPC 通信**: 只需一个 XPC 连接，减少复杂度
3. **root 权限运行**: 单一 LaunchDaemon 解决所有权限问题
4. **自动恢复**: launchd 自动重启崩溃的服务
5. **代码职责清晰**: App = UI，Service = 业务逻辑

---

## 核心目录结构

```
DMSA/
├── DMSAApp/
│   ├── DMSAApp.xcodeproj/         # Xcode 项目
│   ├── DMSAApp/                    # 主应用 (纯 UI)
│   │   ├── App/AppDelegate.swift   # 生命周期管理
│   │   ├── Models/                 # 数据模型
│   │   ├── Services/               # 10 个服务文件
│   │   │   ├── ServiceClient.swift # XPC 客户端 (核心)
│   │   │   ├── ConfigManager.swift
│   │   │   ├── DiskManager.swift
│   │   │   └── VFS/FUSEManager.swift
│   │   ├── UI/                     # SwiftUI 界面
│   │   └── Utils/                  # 工具类
│   │
│   ├── DMSAService/                # 统一服务 (业务逻辑)
│   │   ├── main.swift
│   │   ├── ServiceImplementation.swift
│   │   ├── VFS/                    # VFS 模块
│   │   ├── Sync/                   # 同步模块
│   │   ├── Data/                   # 数据管理
│   │   ├── Monitor/                # 文件/磁盘监控
│   │   └── Privileged/             # 特权操作
│   │
│   └── DMSAShared/                 # 共享代码
│       ├── Protocols/              # XPC 协议
│       ├── Models/                 # 共享模型
│       └── Utils/                  # 共享工具
│
├── CLAUDE.md                       # 本文档 (项目记忆)
├── CLAUDE_SESSIONS.md              # 详细会话记录归档
├── README.md                       # 项目介绍
└── OBJECTBOX_SETUP.md              # ObjectBox 集成指南
```

---

## 关键文件速查

### 主应用 (DMSAApp) - 10 个服务文件

| 文件 | 用途 |
|------|------|
| `ServiceClient.swift` | **XPC 客户端** (核心，所有业务通过此调用) |
| `ConfigManager.swift` | 配置管理 |
| `DatabaseManager.swift` | 内存缓存 (数据从 Service 获取) |
| `DiskManager.swift` | 磁盘事件 + UI 回调 |
| `AlertManager.swift` | UI 弹窗 |
| `VFS/FUSEManager.swift` | macFUSE 检测/安装引导 |

### 统一服务 (DMSAService)

| 文件 | 用途 |
|------|------|
| `ServiceImplementation.swift` | XPC 协议实现 |
| `VFS/VFSManager.swift` | VFS Actor，FUSE 挂载管理 |
| `VFS/EvictionManager.swift` | LRU 淘汰管理 |
| `Sync/SyncManager.swift` | 同步调度 |
| `Sync/NativeSyncEngine.swift` | 同步引擎核心 |
| `Data/ServiceDatabaseManager.swift` | 数据库管理 |

### 共享代码 (DMSAShared)

| 文件 | 用途 |
|------|------|
| `DMSAServiceProtocol.swift` | 统一 XPC 协议 |
| `Constants.swift` | 全局常量 |

---

## 核心流程

**智能合并 (readdir):**
```
TARGET_DIR = LOCAL_DIR ∪ EXTERNAL_DIR (两端文件的并集)
```

**读取流程 (零拷贝):**
```
读取请求 → LOCAL_DIR 有? → 是 → 从 LOCAL_DIR 读取
                ↓ 否
        EXTERNAL_DIR 有? → 是 → 直接重定向读取
                ↓ 否
        返回错误
```

**写入流程 (Write-Back):**
```
写入请求 → 写入 LOCAL_DIR → 标记 isDirty → 返回成功
                                    ↓ (异步)
                           EXTERNAL 连接? → 同步 → 清除 isDirty
```

**淘汰流程 (LRU):**
```
空间不足 → 获取候选文件 (BOTH + 非脏 + 按访问时间排序)
              ↓
    验证 EXTERNAL 存在 → 删除 LOCAL 文件 → 更新状态
```

---

## 运行命令

```bash
# Xcode 编译
cd /Users/ttttt/Documents/xcodeProjects/DMSA/DMSAApp
xcodebuild -scheme DMSAApp -configuration Release

# 查看日志
tail -f ~/Library/Logs/DMSA/app.log
```

---

## 配置路径

| 用途 | 路径 |
|------|------|
| 配置文件 | `~/Library/Application Support/DMSA/config.json` |
| 数据库 | `~/Library/Application Support/DMSA/Database/` |
| 日志 | `~/Library/Logs/DMSA/app.log` |
| LaunchDaemon | `/Library/LaunchDaemons/com.ttttt.dmsa.service.plist` |

---

## 记忆采集流程

> **触发方式**: 用户说"采集记忆"或类似指令时手动触发

### 采集步骤

1. **总结当前会话**
   - 回顾本次对话的所有内容
   - 提取完成的任务、修改的文件、关键代码

2. **提取知识点**
   - 实现思路和设计决策 (为什么这样做)
   - 遇到的问题和解决方案
   - 新增的术语映射

3. **读取会话属性**
   - 执行 `ls -lt ~/.claude/projects/-Users-ttttt-Documents-xcodeProjects-DMSA/*.jsonl | head -1` 获取当前会话文件
   - 从文件名提取 Session ID (前 8 位)
   - 记录日期

4. **检查合并条件**
   - 查看现有会话记录
   - 判断是否有同功能的历史会话可以合并
   - 合并规则见下方"会话合并策略"

5. **更新记忆文件**
   - 更新会话索引表
   - 更新详细会话记录 (写入 `CLAUDE_SESSIONS.md`)
   - 更新快速上下文表 (如有新术语)

6. **完成后通知用户**
   - 直接修改文件，完成后告知用户已采集

**异常处理:** 如果采集失败，告知用户具体错误，不做部分修改

---

## 会话合并策略

**合并原则**: 以"功能"为单位合并，同一功能的多次会话合并为一条记录

**合并规则:**
1. **同功能判定**: 修改相同模块/实现相同功能的会话视为同功能
2. **时间跨度**: 可以跨天合并，只要是同一功能
3. **合并后**: 不保留原始会话的单独记录，合并为一条

**内容合并规则:**
- 任务列表: 合并去重
- 问题与解决: 全部保留
- 修改文件: 合并去重
- 关键代码: 保留最终版本

---

## 采集检查清单

- [ ] 会话索引表已更新
- [ ] 详细记录包含实现思路
- [ ] 详细记录包含遇到的问题与解决方案
- [ ] 检查是否有可合并的同功能会话
- [ ] 快速上下文表已更新 (如有新术语)

---

## 会话记录

> 详细记录见: `CLAUDE_SESSIONS.md`

### 会话索引表

| Session ID | 日期 | 标题 | 摘要 |
|------------|------|------|------|
| 505f841a | 2026-01-24 | v4.5编译修复 | 修复类型错误、恢复ConfigManager、添加共享模型 |
| eae6e63e | 2026-01-26 | 代码签名修复 | 修复 Service Team ID、macFUSE Library Validation |
| 2a099f6b | 2026-01-26 | C FUSE Wrapper | libfuse C 实现，修复权限和保护问题 |
| e4bd3c09 | 2026-01-27 | MD 文档清理 | 删除 13 个过时文档，保留 4 个核心文档 |
| 50877371 | 2026-01-27 | SERVICE_FLOW 文档体系 | 创建 19 个流程文档，完整架构设计 |
| 50877371 | 2026-01-27 | v4.9 代码修改 (P0-P3) | 状态管理/VFS阻塞/通知/错误码/启动检查/冲突检测/日志格式 |
| 50877371 | 2026-01-27 | UI 设计规范 | 21_UI设计规范.md + HTML 原型 |
| 4f263311 | 2026-01-27 | App 修改计划 + P0-P2 修复 | 代码审查 + App 端 P0-P2 问题修复 |
| 4f263311 | 2026-01-27 | UI 文件清理 + pbxproj 工具 | 删除 14 个旧 UI 文件 + 创建 Xcode 项目管理工具 |
| 4f263311 | 2026-01-28 | Ruby xcodeproj 迁移 | Python pbxproj 有 bug，切换到 Ruby xcodeproj |
| 7ec270c8 | 2026-01-28 | DMSAApp 编译修复 | 修复 P0 类型错误，SyncStatus 枚举修复，Color 扩展 |
| 7ec270c8 | 2026-01-28 | pbxproj_tool 完善 | Ruby 编码修复 + smart-fix 智能修复命令 |
| 7ec270c8 | 2026-01-28 | UI + App 功能核对 | 生成 27_UI核对报告.md + 28_App功能核对报告.md |
| 7ec270c8 | 2026-01-28 | i18n 修复 + 清理 | 添加 150+ 缺失本地化键，删除 78 个未使用键 |
| 7ec270c8 | 2026-01-28 | 磁盘状态同步修复 | DashboardView 与 DisksPage 状态不同步问题 |
| 7ec270c8 | 2026-01-28 | 文件级同步/淘汰记录 | ServiceSyncFileRecord 实体 + XPC + UI 展示 |
| c2bc39ee | 2026-02-02 | 编译/i18n/解码修复 | pbxproj 路径修复、PBXVariantGroup 修复、SyncHistory CodingKeys 映射修复 |

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

## 注意事项

1. **首次设置**:
   - 检测 ~/Downloads 是否存在
   - 存在则重命名为 ~/Downloads_Local
   - 创建 FUSE 挂载点 ~/Downloads

2. **权限要求**:
   - macFUSE 5.1.3+ (从 https://macfuse.github.io/ 下载)
   - 完全磁盘访问权限 (TCC)

3. **设计原则**:
   - App 只做 UI，不包含任何业务逻辑
   - Service 是大脑，所有同步、VFS、数据管理都在 Service
   - XPC 是桥梁，App 通过 ServiceClient 与 Service 通信

---


**预期行为说明:**
- DMSAShared 文件在两个 target 中出现两次是**正常的** (共享代码)
- 产物文件 (.app, .service) 不存在是**正常的** (编译后才生成)

---

*文档维护: 每次会话结束时更新会话索引表，详细记录写入 CLAUDE_SESSIONS.md*
