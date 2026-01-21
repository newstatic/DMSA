# Delt MACOS Sync App (DMSA)

> 版本: 2.0 | macOS 菜单栏应用

智能同步本地目录与外置硬盘，支持虚拟文件系统、多硬盘、多目录、双向同步。

## 核心特性

| 特性 | 描述 |
|------|------|
| 🔄 虚拟文件系统 | 基于 Endpoint Security 的双后端存储架构 |
| 💾 多硬盘支持 | 配置多个外置硬盘，支持优先级 |
| 📁 多目录同步 | Downloads、Documents、Desktop 等可自由配置 |
| ↔️ 双向同步 | 本地→外置、外置→本地、双向三种模式 |
| 📊 智能缓存 | LOCAL 缓存 + 自动淘汰策略 |
| 🔍 文件监控 | FSEvents 实时监控文件变化 |
| 📈 统计面板 | 同步历史、数据统计、趋势图表 |

## 系统架构

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
│    ┌──────────┬──────────┬──────────┐          │
│    │ 读取路由器 │ 写入路由器 │ 元数据管理 │          │
│    └──────────┴──────────┴──────────┘          │
└─────────────────────────────────────────────────┘
                        │
            ┌───────────┴───────────┐
            ▼                       ▼
┌───────────────────┐   ┌───────────────────┐
│    LOCAL 后端      │   │   EXTERNAL 后端    │
│    ~/Library/     │   │   /Volumes/BACKUP/ │
│    Application    │   │   Downloads/       │
│    Support/...    │   │                    │
│    LocalCache/    │   │   - 完整数据存储    │
│                   │   │   - 主存储源        │
│    - 热数据缓存    │   │   - 可能离线       │
│    - LRU 淘汰策略  │   │                    │
└───────────────────┘   └───────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│             数据持久层 (ObjectBox)                │
│    ┌──────────┬──────────┬──────────┐          │
│    │ 文件索引  │ 同步状态  │ 配置数据  │          │
│    └──────────┴──────────┴──────────┘          │
└─────────────────────────────────────────────────┘
```

## 技术栈

| 组件 | 技术方案 |
|------|----------|
| 文件系统监控 | Endpoint Security Framework |
| 数据存储 | ObjectBox Swift |
| 同步引擎 | rsync + 自定义逻辑 |
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

### 最小配置示例

```json
{
  "version": "2.0",
  "disks": [
    {
      "id": "uuid-1",
      "name": "BACKUP",
      "mountPath": "/Volumes/BACKUP"
    }
  ],
  "syncPairs": [
    {
      "id": "uuid-a",
      "diskId": "uuid-1",
      "localPath": "~/Downloads",
      "externalRelativePath": "Downloads",
      "direction": "local_to_external"
    }
  ]
}
```

### 同步方向

| 值 | 说明 |
|----|------|
| `local_to_external` | 本地 → 外置硬盘 |
| `external_to_local` | 外置硬盘 → 本地 |
| `bidirectional` | 双向同步 |

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

1. **System Extension 批准**
   - 系统偏好设置 → 安全性与隐私 → 通用 → 允许系统扩展

2. **完全磁盘访问权限**
   - 系统偏好设置 → 安全性与隐私 → 隐私 → 完全磁盘访问权限

3. **Endpoint Security**
   - 需要 Apple Developer Program 会员资格
   - 需要 `com.apple.developer.endpoint-security.client` entitlement

## 日志位置

```
~/Library/Logs/DMSA/app.log
```

## 目录结构

```
~/Library/Application Support/DMSA/
├── LocalCache/                # LOCAL 缓存目录
│   └── Downloads/             # 映射 ~/Downloads
├── Database/                  # ObjectBox 数据库
│   └── objectbox/
├── Logs/                      # 日志目录
└── config.json                # 配置文件
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

1. 首次运行需要授予系统扩展权限和完全磁盘访问权限
2. 外置硬盘格式为 exFAT/NTFS 时不支持符号链接功能
3. 同步使用 rsync，支持增量同步和断点续传
4. LOCAL 缓存会根据配置自动淘汰旧文件

---

*Delt MACOS Sync App (DMSA) | 版本 2.0 | 更新日期: 2026-01-20*
