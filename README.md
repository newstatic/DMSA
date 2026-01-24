# Delt MACOS Sync App (DMSA)

> 版本: 3.0 | macOS 菜单栏应用

智能同步本地目录与外置硬盘，支持虚拟文件系统 (FUSE)、多硬盘、多目录配对。

## 核心特性

| 特性 | 描述 |
|------|------|
| 🔄 虚拟文件系统 | 基于 FUSE-T 的智能合并视图架构 |
| 💾 多硬盘支持 | 配置多个外置硬盘，支持优先级 |
| 📁 多目录同步 | Downloads、Documents、Desktop 等可自由配置 (SyncPair) |
| ➡️ 单向同步 | LOCAL_DIR → EXTERNAL_DIR (EXTERNAL 作为备份) |
| 📊 智能缓存 | LOCAL_DIR 缓存 + LRU 淘汰策略 |
| 🔍 文件监控 | FSEvents 实时监控文件变化 |
| 📈 统计面板 | 同步历史、数据统计、趋势图表 |
| 🛡️ 零拷贝读取 | EXTERNAL_ONLY 文件直接重定向读取，不复制到本地 |

## 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                         用户应用层                                │
│                    (Finder, Safari, etc.)                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 文件操作 (open, read, write...)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                TARGET_DIR (FUSE-T 挂载点)                        │
│                      ~/Downloads                                 │
│                    (用户唯一访问入口)                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ FUSE 回调
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     DMSA VFS 核心                                │
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
│       LOCAL_DIR          │     │      EXTERNAL_DIR        │
│   ~/Downloads_Local      │ ──▶ │   /Volumes/BACKUP/      │
│                          │同步  │   Downloads/            │
│   - 热数据缓存            │     │   - 完整数据源           │
│   - LRU 淘汰策略          │     │   - 只读备份            │
│   - 可能本地删除          │     │   - 可能离线            │
└─────────────────────────┘     └─────────────────────────┘
       ⬆ 禁止直接访问                  ⬆ 禁止直接访问
```

**术语映射:**
| 术语 | 路径示例 | 说明 |
|------|----------|------|
| **TARGET_DIR** | `~/Downloads` | FUSE 挂载点，用户唯一访问入口 |
| **LOCAL_DIR** | `~/Downloads_Local` | 本地热数据缓存 |
| **EXTERNAL_DIR** | `/Volumes/BACKUP/Downloads` | 外部完整数据源 (Source of Truth) |

## 技术栈

| 组件 | 技术方案 |
|------|----------|
| 虚拟文件系统 | FUSE-T (推荐) / macFUSE (备选) |
| 数据存储 | ObjectBox Swift |
| 同步引擎 | 原生 Swift 增量同步 |
| 文件监控 | FSEvents |
| UI 框架 | SwiftUI |
| 进程管理 | LaunchAgent |

## 编译方法

### 方法 1: 命令行编译

```bash
cd DMSA
chmod +x build.sh
./build.sh
```

### 方法 2: Swift Package Manager

```bash
cd DMSA
swift build -c release
```

### 方法 3: Xcode 编译

1. 打开 Xcode
2. File → Open → 选择项目目录
3. Build & Run

## 安装

```bash
# 复制到 Applications
cp -r build/DMSA.app /Applications/

# 启动
open /Applications/DMSA.app
```

## 配置文件

配置存储在 `~/Library/Application Support/DMSA/config.json`

### 最小配置示例 (v3.0)

```json
{
  "version": "3.0",
  "syncPairs": [
    {
      "id": "uuid-a",
      "localDir": "~/Downloads_Local",
      "externalDir": "/Volumes/BACKUP/Downloads",
      "targetDir": "~/Downloads",
      "localQuotaGB": 50,
      "enabled": true
    }
  ]
}
```

### 文件状态 (v3.0)

| 状态 | 说明 |
|----|------|
| `LOCAL_ONLY` | 仅在 LOCAL_DIR，待同步 |
| `EXTERNAL_ONLY` | 仅在 EXTERNAL_DIR，直接读取 |
| `BOTH` | 两端都有，已同步 |
| `DELETED` | 外部被删除，拒绝访问 |

### 同步方向

v3.0 仅支持**单向同步**: `LOCAL_DIR → EXTERNAL_DIR`

EXTERNAL_DIR 作为只读备份，不会反向同步到 LOCAL_DIR。

## 菜单功能

```
┌─────────────────────────────────┐
│ ● BACKUP 已连接                  │
│ ○ PORTABLE 未连接                │
├─────────────────────────────────┤
│ 📁 Downloads → BACKUP           │
│ 📁 Documents → 本地             │
├─────────────────────────────────┤
│ ↻ 立即同步                ⌘S    │
│ 📊 同步历史              ⌘H    │
│ 📂 打开 Downloads        ⌘O    │
│ 📄 查看日志              ⌘L    │
├─────────────────────────────────┤
│ ⚙ 设置...               ⌘,    │
│ ✕ 退出                   ⌘Q    │
└─────────────────────────────────┘
```

## 权限要求

1. **FUSE-T 安装**
   - 下载安装 [FUSE-T](https://www.fuse-t.org/)
   - 或使用 macFUSE 作为备选

2. **完全磁盘访问权限**
   - 系统偏好设置 → 安全性与隐私 → 隐私 → 完全磁盘访问权限

## 日志位置

```
~/Library/Logs/DMSA/app.log
```

## 目录结构

```
~/
├── Downloads/                      # TARGET_DIR: FUSE 挂载点 (用户唯一访问入口)
│   └── (智能合并视图)
│
├── Downloads_Local/                # LOCAL_DIR: 本地热数据存储
│   ├── file1.pdf                   # 可淘汰
│   ├── file2.doc                   # isDirty (待同步)
│   └── .FUSE/db.json               # 版本文件
│
└── Library/
    ├── Application Support/DMSA/
    │   ├── Database/               # ObjectBox 数据库
    │   └── config.json             # 配置文件
    └── Logs/DMSA/
        └── app.log                 # 日志文件

/Volumes/BACKUP/
└── Downloads/                      # EXTERNAL_DIR: 完整数据存储
    ├── file1.pdf                   # 已同步
    ├── file3.zip                   # EXTERNAL_ONLY
    └── .FUSE/db.json               # 版本文件
```

## 硬盘格式支持

| 格式 | 同步 | 符号链接 |
|------|------|----------|
| APFS | ✅ | ✅ |
| HFS+ | ✅ | ✅ |
| exFAT | ✅ | ❌ |
| NTFS | ✅ (只读) | ❌ |

## 文档

- [需求规格](REQUIREMENTS.md) - 功能需求与优先级
- [技术架构](TECHNICAL.md) - 系统设计与实现细节
- [流程图](FLOWCHARTS.md) - 所有业务流程图
- [配置项](CONFIGURATIONS.md) - 配置项详细说明

## 注意事项

1. 首次运行会将 `~/Downloads` 重命名为 `~/Downloads_Local`，然后在 `~/Downloads` 创建 FUSE 挂载点
2. 用户只能通过 TARGET_DIR (`~/Downloads`) 访问文件，禁止直接访问 LOCAL_DIR 和 EXTERNAL_DIR
3. EXTERNAL_ONLY 文件直接重定向读取，不会复制到本地（零拷贝）
4. 淘汰前会验证 EXTERNAL_DIR 存在该文件，不存在则先同步
5. 外置硬盘格式为 exFAT/NTFS 时不支持符号链接功能

---

*Delt MACOS Sync App (DMSA) | 版本 3.0 | 更新日期: 2026-01-21*
