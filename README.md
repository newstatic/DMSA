# DMSA - Downloads Management & Sync App

> 版本: 4.8 | macOS 菜单栏应用 | 双进程架构

智能同步本地目录与外置硬盘，通过 VFS 虚拟文件系统提供统一访问入口。

## 核心特性

- **VFS 智能合并** - ~/Downloads 显示本地+外置文件的并集
- **零拷贝读取** - 外置文件直接读取，不复制到本地
- **Write-Back 写入** - 写入本地，异步同步到外置
- **LRU 智能淘汰** - 自动管理本地缓存空间
- **实时通知** - DistributedNotificationCenter 推送同步进度

## 架构

```
┌─────────────────────────────────────────────────────────────────┐
│                      用户态 (User Space)                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              DMSA.app (菜单栏应用 - 普通用户权限)              │  │
│  │    GUI + 状态显示 + ServiceClient (XPC 客户端)              │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                │ XPC                            │
└────────────────────────────────┼────────────────────────────────┘
┌────────────────────────────────┼────────────────────────────────┐
│                      系统态 (root)                               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │         com.ttttt.dmsa.service (LaunchDaemon)              │  │
│  │    VFSManager + SyncManager + PrivilegedOperations        │  │
│  │    ObjectBox 数据库 + C libfuse wrapper                    │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 术语

| 术语 | 路径 | 说明 |
|------|------|------|
| TARGET_DIR | ~/Downloads | VFS 挂载点，用户访问入口 |
| LOCAL_DIR | ~/Downloads_Local | 本地热数据缓存 |
| EXTERNAL_DIR | /Volumes/BACKUP/Downloads | 外置硬盘完整数据 |

## 技术栈

| 组件 | 技术 |
|------|------|
| VFS | macFUSE + C libfuse wrapper |
| 数据库 | ObjectBox Swift |
| 同步 | 原生 Swift 增量同步 |
| IPC | XPC + DistributedNotificationCenter |
| UI | SwiftUI |

## 编译

```bash
cd DMSAApp
xcodebuild -scheme DMSAApp -configuration Release
xcodebuild -scheme com.ttttt.dmsa.service -configuration Release
```

## 权限要求

1. **macFUSE 5.1.3+** - https://macfuse.github.io/
2. **完全磁盘访问权限** - 系统设置 > 隐私与安全性

## 配置文件

`~/Library/Application Support/DMSA/config.json`

## 日志

`~/Library/Logs/DMSA/app.log`

---

*DMSA v4.8 | 2026-01-27*
