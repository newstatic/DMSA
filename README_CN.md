# DMSA - 下载文件管理与同步应用

<p align="center">
  <img src="doc/assets/icon.png" alt="DMSA 图标" width="128" height="128">
</p>

<p align="center">
  <strong>智能外置硬盘同步 + 虚拟文件系统</strong><br>
  macOS 菜单栏应用 | 双进程架构 | macFUSE VFS
</p>

<p align="center">
  <a href="https://github.com/newstatic/DMSA/releases/latest">
    <img src="https://img.shields.io/github/v/release/newstatic/DMSA?style=flat-square" alt="最新版本">
  </a>
  <img src="https://img.shields.io/badge/macOS-11.0+-blue?style=flat-square" alt="macOS 11.0+">
  <img src="https://img.shields.io/badge/Swift-5.5+-orange?style=flat-square" alt="Swift 5.5+">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT 许可证">
</p>

<p align="center">
  <a href="README.md">English</a> | 简体中文
</p>

---

## DMSA 是什么？

DMSA（Downloads Management & Sync App）创建一个**虚拟文件系统**，将本地存储与外置硬盘无缝合并。通过单一的 `~/Downloads` 文件夹访问所有文件——无论它们存储在本地还是外置硬盘上。

### 痛点问题

- 外置硬盘容量大但速度慢，而且不是随时连接
- 本地 SSD 速度快但空间有限
- 手动在本地和外置存储之间管理文件很繁琐
- 传统同步工具会复制所有内容，浪费空间

### 解决方案

DMSA 创建一个**智能虚拟层**：
- 在一个地方显示本地和外置硬盘的**所有文件**
- **直接读取**外置硬盘（无需复制）
- **优先写入本地**，然后后台同步到外置硬盘
- 空间不足时**自动清理**旧的本地文件
- **离线可用** —— 本地文件始终可访问

---

## 功能特性

### 🗂️ VFS 智能合并

你的 `~/Downloads` 文件夹变成本地 + 外置文件的**统一视图**：

```
~/Downloads (VFS 挂载点 - 你看到的)
    ├── project.zip      ← 仅本地（新文件）
    ├── movie.mp4        ← 仅外置（大文件）
    ├── document.pdf     ← 两边都有（已同步）
    └── photos/          ← 混合内容
```

实际存储位置：
```
~/Downloads_Local/           /Volumes/BACKUP/Downloads/
    ├── project.zip              ├── movie.mp4
    ├── document.pdf             ├── document.pdf
    └── photos/                  └── photos/
        └── recent.jpg               ├── recent.jpg
                                     └── archive.jpg
```

### ⚡ 零拷贝读取

当你打开一个仅存在于外置硬盘的文件：
- **无需复制** —— 直接从外置硬盘读取
- **无需等待** —— 元数据即时访问
- **不浪费空间** —— 大文件保留在外置硬盘

### ✍️ 写回同步

当你创建或修改文件：
1. **写入本地** —— 即时完成，无需等待外置硬盘
2. **标记为脏** —— 跟踪需要同步的文件
3. **后台同步** —— 连接外置硬盘时自动复制
4. **清除脏标记** —— 文件已安全备份

### 🧹 LRU 淘汰

当本地空间不足时：
1. 找到**同时存在**于本地和外置的文件
2. 按**最后访问时间**排序（最少使用的优先）
3. **删除本地副本** —— 文件仍可通过 VFS 从外置硬盘访问
4. **保留索引** —— 无需重新扫描

### 📊 增量索引

- **首次运行**：完整扫描外置硬盘，构建完整索引
- **后续运行**：仅扫描变更文件（快速启动）
- **批量写入**：每个数据库事务处理 10,000 条记录
- **50万+ 文件**：高效处理大型文件库

### 🔄 FUSE 恢复

- **睡眠/唤醒**：系统睡眠后自动重新挂载
- **崩溃恢复**：服务自动重启并重新挂载
- **信号处理**：SIGTERM/SIGHUP 优雅关闭

### 🔔 实时状态

- 菜单栏图标显示同步状态
- 大型操作的进度通知
- 应用内详细活动日志

---

## 系统架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                           用户空间                                    │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    DMSA.app (菜单栏应用)                        │  │
│  │                       普通用户权限                              │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────┐   │  │
│  │  │   GUI   │  │  设置   │  │  状态   │  │  ServiceClient  │   │  │
│  │  │  管理器  │  │  视图   │  │  显示   │  │   (统一 XPC)    │   │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                    │                                 │
│                         XPC 通道   │                                 │
│                                    ▼                                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                         系统空间 (root)                              │
│                        LaunchDaemon 服务                             │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │               com.ttttt.dmsa.service                           │  │
│  │                                                                │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐    │  │
│  │  │ VFSManager  │  │ SyncManager │  │     C libfuse       │    │  │
│  │  │  (Actor)    │  │   (Actor)   │  │      封装器         │    │  │
│  │  │             │  │             │  │                     │    │  │
│  │  │• FUSE 挂载  │  │• 文件同步   │  │• fuse_loop_mt()     │    │  │
│  │  │• 智能合并   │  │• 调度管理   │  │• 多线程             │    │  │
│  │  │• 读写路由   │  │• 冲突处理   │  │• 异步回调           │    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘    │  │
│  │                                                                │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐    │  │
│  │  │EvictionMgr │  │  ObjectBox  │  │  PrivilegedOps      │    │  │
│  │  │  淘汰管理   │  │   数据库    │  │   特权操作          │    │  │
│  │  │             │  │             │  │                     │    │  │
│  │  │• LRU 淘汰   │  │• 50万+ 文件 │  │• 目录保护           │    │  │
│  │  │• 空间管理   │  │• 批量写入   │  │• ACL 管理           │    │  │
│  │  │• 批量操作   │  │             │  │• 权限管理           │    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### 双进程设计

| 组件 | 进程 | 权限 | 职责 |
|------|------|------|------|
| **DMSA.app** | 主应用 | 用户 | 纯 UI、状态显示、用户交互 |
| **DMSAService** | LaunchDaemon | root | VFS + 同步 + 数据库 + 特权操作 |

**优势：**
- GUI 退出不影响文件访问
- 服务以 root 权限独立运行
- 通过 launchd 崩溃自动重启
- 关注点清晰分离

---

## 目录结构

| 路径 | 名称 | 描述 |
|------|------|------|
| `~/Downloads` | TARGET_DIR | VFS 挂载点 —— 用户访问入口 |
| `~/Downloads_Local` | LOCAL_DIR | 本地热数据缓存（隐藏） |
| `/Volumes/BACKUP/Downloads` | EXTERNAL_DIR | 外置硬盘完整数据 |

**流程示例：**

```
读取 movie.mp4（仅外置）：
  应用 → ~/Downloads/movie.mp4 → VFS → /Volumes/BACKUP/Downloads/movie.mp4

写入 new.txt：
  应用 → ~/Downloads/new.txt → VFS → ~/Downloads_Local/new.txt
                                   → 后台同步 → /Volumes/BACKUP/Downloads/new.txt

删除 old.zip：
  应用 → rm ~/Downloads/old.zip → VFS → 从 LOCAL_DIR 删除
                                      → 从 EXTERNAL_DIR 删除
                                      → 从索引移除
```

---

## 安装

### 系统要求

1. **macOS 11.0+**（Big Sur 或更高版本）
2. **macFUSE 5.1.3+** —— 从 https://macfuse.github.io/ 下载

### 安装 macFUSE

1. 从 https://macfuse.github.io/ 下载 macFUSE
2. 打开 DMG 并运行安装程序
3. 按提示重启 Mac
4. 前往**系统设置 > 隐私与安全性**，允许内核扩展

### 安装 DMSA

1. 从 [Releases](https://github.com/newstatic/DMSA/releases) 下载 `DMSA-x.x.dmg`
2. 打开 DMG，将 DMSA 拖到应用程序
3. 从应用程序启动 DMSA
4. 按提示授予**完全磁盘访问权限**：
   - 系统设置 > 隐私与安全性 > 完全磁盘访问权限
   - 添加 DMSA.app

### 首次运行

1. DMSA 会检测你的外置硬盘
2. 配置同步对（本地 ↔ 外置目录）
3. 首次索引可能需要几分钟（大容量硬盘）
4. 你的 `~/Downloads` 现在是智能 VFS 了！

---

## 配置

### 配置文件

`~/Library/Application Support/DMSA/config.json`

```json
{
  "syncPairs": [
    {
      "id": "...",
      "localDir": "/Users/you/Downloads_Local",
      "externalDir": "/Volumes/BACKUP/Downloads",
      "mountPoint": "/Users/you/Downloads"
    }
  ],
  "eviction": {
    "triggerThreshold": 5368709120,
    "targetFreeSpace": 10737418240,
    "maxFilesPerRun": 100
  }
}
```

### 淘汰设置

| 参数 | 默认值 | 描述 |
|------|--------|------|
| `triggerThreshold` | 5 GB | 本地缓存超过此值时开始淘汰 |
| `targetFreeSpace` | 10 GB | 淘汰后的目标可用空间 |
| `maxFilesPerRun` | 100 | 每次淘汰的最大文件数 |
| `minFileAge` | 1 小时 | 不淘汰最近访问的文件 |

---

## 日志

| 日志文件 | 描述 |
|----------|------|
| `~/Library/Logs/DMSA/app-YYYY-MM-DD.log` | 应用 UI 日志 |
| `~/Library/Logs/DMSA/service-YYYY-MM-DD.log` | 服务日志 |
| `~/Library/Logs/DMSA/fuse-YYYY-MM-DD.log` | FUSE C 层日志 |

日志每天轮转，保留 7 天。

---

## 技术栈

| 组件 | 技术 |
|------|------|
| 语言 | Swift 5.5+ |
| UI 框架 | SwiftUI + Cocoa |
| VFS | macFUSE + C libfuse 封装器 |
| 数据库 | ObjectBox Swift |
| IPC | XPC + DistributedNotificationCenter |
| 构建 | Xcode 14+ / Swift Package Manager |

---

## 从源码构建

```bash
# 克隆仓库
git clone https://github.com/newstatic/DMSA.git
cd DMSA

# 构建 Release 版本
cd DMSAApp
xcodebuild -scheme DMSAApp -configuration Release
xcodebuild -scheme com.ttttt.dmsa.service -configuration Release

# 或使用发布脚本
cd ..
./release.sh 2.0
```

---

## 故障排除

### VFS 未挂载

1. 检查 macFUSE 是否已安装：`kextstat | grep fuse`
2. 检查是否已授予完全磁盘访问权限
3. 查看日志：`tail -f ~/Library/Logs/DMSA/service-*.log`

### 文件未同步

1. 检查外置硬盘是否已连接
2. 检查磁盘权限
3. 在 DMSA 菜单栏查看同步状态

### 性能问题

1. 首次索引对于大容量硬盘（50万+ 文件）可能较慢
2. 后续启动使用增量索引（快速）
3. 检查淘汰是否正在运行：`~/Library/Logs/DMSA/service-*.log`

---

## 文档

详细文档位于 `doc/` 目录：

- `doc/00_README.md` —— 文档索引
- `doc/CLAUDE_SESSIONS.md` —— 开发历史
- `SERVICE_FLOW/` —— 架构和流程图

---

## 许可证

MIT 许可证 —— 详见 [LICENSE](LICENSE)。

---

## 致谢

- [macFUSE](https://macfuse.github.io/) —— macOS FUSE 实现
- [ObjectBox](https://objectbox.io/) —— 高性能嵌入式数据库
- [Claude](https://claude.ai/) —— AI 编程助手

---

<p align="center">
  <strong>DMSA v2.0</strong> | 2026-02-03<br>
  用 ❤️ 打造，让外置硬盘管理变得轻松
</p>
