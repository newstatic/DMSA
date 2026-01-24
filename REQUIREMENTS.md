# Delt MACOS Sync App (DMSA) 需求规格文档

> 版本: 3.0 | 更新日期: 2026-01-21

---

## 1. 项目概述

### 1.1 产品定位

macOS 菜单栏应用，基于 FUSE 虚拟文件系统实现本地目录与外置硬盘的智能合并与同步。支持多同步对配置、单向同步 (LOCAL_DIR → EXTERNAL_DIR)、LRU 淘汰、零拷贝读取等高级功能。

### 1.2 目标用户

- 经常使用外置硬盘备份数据的 macOS 用户
- 需要在多个存储设备间保持数据同步的用户
- 希望自动化目录同步流程的用户

### 1.3 核心价值

| 价值点 | 描述 |
|--------|------|
| 透明访问 | 通过 FUSE 挂载点 (TARGET_DIR) 访问，智能合并 LOCAL_DIR 和 EXTERNAL_DIR |
| 零拷贝读取 | EXTERNAL_ONLY 文件直接重定向读取，不复制到本地 |
| 自动化 | 硬盘插入自动触发同步，无需手动操作 |
| 数据安全 | EXTERNAL_DIR 作为完整数据源，淘汰前验证备份存在 |
| 灵活配置 | 支持多同步对 (SyncPair)，每对独立配额 |

---

## 2. 功能需求

### 2.1 需求优先级定义

| 优先级 | 含义 | 交付阶段 |
|--------|------|----------|
| P0 | 核心功能，MVP 必须 | 阶段一 |
| P1 | 重要功能，增强体验 | 阶段二 |
| P2 | 完善功能，锦上添花 | 阶段三 |

---

### 2.2 P0 核心功能 (阶段一)

#### 2.2.1 多硬盘支持

| 需求ID | 需求描述 |
|--------|----------|
| P0-HD-01 | 支持配置多个外置硬盘 (名称、挂载路径) |
| P0-HD-02 | 硬盘优先级设置，多硬盘同时连接时选择优先级最高的 |
| P0-HD-03 | 硬盘状态实时检测 (已连接/未连接) |
| P0-HD-04 | 硬盘切换时自动处理同步逻辑 |

#### 2.2.2 多目录同步

| 需求ID | 需求描述 |
|--------|----------|
| P0-DIR-01 | 支持配置多个同步目录对 (本地路径 ↔ 外置路径) |
| P0-DIR-02 | 默认包含 Downloads，可添加 Documents、Desktop 等 |
| P0-DIR-03 | 每个目录对可独立启用/禁用 |
| P0-DIR-04 | 支持为不同硬盘配置不同的目录映射 |

#### 2.2.3 同步方向配置 (v3.0)

| 需求ID | 需求描述 |
|--------|----------|
| P0-SYNC-01 | **单向同步**: LOCAL_DIR → EXTERNAL_DIR (EXTERNAL 作为只读备份) |
| P0-SYNC-02 | 写入通过 TARGET_DIR 触发，先写 LOCAL_DIR，异步同步到 EXTERNAL_DIR |
| P0-SYNC-03 | EXTERNAL_DIR 新增文件显示为 EXTERNAL_ONLY，直接重定向读取 |
| P0-SYNC-04 | 同步前检查 EXTERNAL_DIR 可访问性 |

#### 2.2.4 文件过滤

| 需求ID | 需求描述 |
|--------|----------|
| P0-FILT-01 | 支持排除特定文件类型 (后缀名列表) |
| P0-FILT-02 | 默认排除列表: `.DS_Store`, `.Trash`, `*.tmp`, `*.swp`, `Thumbs.db` |
| P0-FILT-03 | 支持自定义排除规则 (glob 模式) |
| P0-FILT-04 | 排除规则可在 UI 中编辑 |

#### 2.2.5 基础 UI

| 需求ID | 需求描述 |
|--------|----------|
| P0-UI-01 | 菜单栏图标显示连接状态 |
| P0-UI-02 | 菜单显示: 硬盘状态、当前模式、手动同步、打开目录、设置、退出 |
| P0-UI-03 | 设置窗口: 硬盘管理、目录管理、过滤规则 |
| P0-UI-04 | 系统通知: 同步开始/完成/失败 |

#### 2.2.6 配置存储

| 需求ID | 需求描述 |
|--------|----------|
| P0-CFG-01 | 使用 JSON 文件存储配置 (`~/Library/Application Support/DMSA/config.json`) |
| P0-CFG-02 | 配置文件包含: 硬盘列表、目录映射、过滤规则、通用设置 |
| P0-CFG-03 | 配置变更立即生效 |
| P0-CFG-04 | 配置文件损坏时使用默认配置并提示用户 |

---

### 2.3 P1 增强功能 (阶段二)

#### 2.3.1 文件监控同步

| 需求ID | 需求描述 |
|--------|----------|
| P1-MON-01 | 使用 FSEvents 监控文件变化 |
| P1-MON-02 | 文件变化后触发增量同步 (防抖: 5秒) |
| P1-MON-03 | 可配置监控开关 (启用/禁用) |
| P1-MON-04 | 监控状态显示在菜单中 |

#### 2.3.2 完整 GUI

| 需求ID | 需求描述 |
|--------|----------|
| P1-GUI-01 | 设置窗口采用 SwiftUI 实现 |
| P1-GUI-02 | 同步进度实时显示 (文件名、进度条、速度) |
| P1-GUI-03 | 历史记录列表 (时间、文件数、大小、状态) |
| P1-GUI-04 | 窗口支持深色模式 |

#### 2.3.3 异常保护

| 需求ID | 需求描述 |
|--------|----------|
| P1-SAFE-01 | 同步采用事务机制: 临时目录 → 原子替换 |
| P1-SAFE-02 | 检测硬盘意外断开 (悬空链接检测) |
| P1-SAFE-03 | 异常断开时自动恢复本地目录 |
| P1-SAFE-04 | 恢复向导: 引导用户处理数据不一致 |
| P1-SAFE-05 | 同步前创建快照 (可选) |

#### 2.3.4 开机自启动

| 需求ID | 需求描述 |
|--------|----------|
| P1-AUTO-01 | 设置中提供开机启动开关 |
| P1-AUTO-02 | 使用 LaunchAgent 实现自启动 |
| P1-AUTO-03 | 启动时检查并修复状态不一致 |

---

### 2.4 P2 完善功能 (阶段三)

#### 2.4.1 同步统计

| 需求ID | 需求描述 |
|--------|----------|
| P2-STAT-01 | 记录每次同步的详细信息 (时间、文件列表、大小) |
| P2-STAT-02 | 统计面板: 总同步次数、总数据量、平均速度 |
| P2-STAT-03 | 图表展示: 同步频率趋势、数据量趋势 |
| P2-STAT-04 | 数据导出: CSV/JSON 格式 |

#### 2.4.2 高级过滤

| 需求ID | 需求描述 |
|--------|----------|
| P2-FILT-01 | 支持文件大小限制 (最大/最小) |
| P2-FILT-02 | 支持文件修改时间过滤 (N天内) |
| P2-FILT-03 | 支持正则表达式匹配 |
| P2-FILT-04 | 过滤规则预设 (开发、设计、文档等场景) |

#### 2.4.3 配置导入导出

| 需求ID | 需求描述 |
|--------|----------|
| P2-CFG-01 | 导出配置到文件 |
| P2-CFG-02 | 从文件导入配置 |
| P2-CFG-03 | 配置版本管理 |

---

## 3. 非功能需求

### 3.1 性能要求

| 需求ID | 需求描述 |
|--------|----------|
| NF-PERF-01 | 应用启动时间 < 2 秒 |
| NF-PERF-02 | 内存占用 < 50MB (空闲状态) |
| NF-PERF-03 | 同步速度不低于 rsync 原生性能的 90% |
| NF-PERF-04 | 文件监控响应延迟 < 1 秒 |

### 3.2 兼容性要求

| 需求ID | 需求描述 |
|--------|----------|
| NF-COMP-01 | 支持 macOS 11.0 (Big Sur) 及以上 |
| NF-COMP-02 | 支持 Intel 和 Apple Silicon |
| NF-COMP-03 | 支持 APFS、HFS+、exFAT 格式硬盘 (exFAT 不支持符号链接，仅同步) |

### 3.3 安全要求

| 需求ID | 需求描述 |
|--------|----------|
| NF-SEC-01 | 仅请求必要的系统权限 |
| NF-SEC-02 | 配置文件不存储敏感信息 |
| NF-SEC-03 | 日志中不记录文件内容 |

### 3.4 可靠性要求

| 需求ID | 需求描述 |
|--------|----------|
| NF-REL-01 | 崩溃后自动重启 (通过 LaunchAgent) |
| NF-REL-02 | 同步中断后支持断点续传 |
| NF-REL-03 | 数据一致性检查 (可选 checksum 校验) |

---

## 4. 数据结构设计

### 4.1 配置文件结构 (v3.0)

```json
{
  "version": "3.0",
  "general": {
    "launchAtLogin": true,
    "showNotifications": true,
    "logLevel": "info"
  },
  "syncPairs": [
    {
      "id": "uuid-a",
      "localDir": "~/Downloads_Local",
      "externalDir": "/Volumes/BACKUP/Downloads",
      "targetDir": "~/Downloads",
      "localQuotaGB": 50,
      "enabled": true
    },
    {
      "id": "uuid-b",
      "localDir": "~/Documents_Local",
      "externalDir": "/Volumes/NAS/Documents",
      "targetDir": "~/Documents",
      "localQuotaGB": 100,
      "enabled": true
    }
  ],
  "filters": {
    "excludePatterns": [
      ".DS_Store",
      ".Trash",
      "*.tmp",
      "*.swp",
      "Thumbs.db",
      "*.part",
      "*.crdownload"
    ],
    "maxFileSize": null,
    "minFileSize": null
  },
  "monitoring": {
    "enabled": true,
    "debounceSeconds": 5
  },
  "eviction": {
    "enabled": true,
    "reserveGB": 5,
    "maxEvictPerRound": 100,
    "minFileAgeDays": 7
  }
}
```

### 4.2 文件位置状态 (v3.0)

| 状态 | 含义 |
|----|------|
| `LOCAL_ONLY` | 仅在 LOCAL_DIR，待同步到 EXTERNAL_DIR |
| `EXTERNAL_ONLY` | 仅在 EXTERNAL_DIR，直接重定向读取 |
| `BOTH` | 两端都有，已同步 |
| `DELETED` | 外部被删除，拒绝访问 |

### 4.3 同步历史记录结构 (v3.0)

```json
{
  "id": "uuid",
  "timestamp": "2026-01-20T10:30:00Z",
  "syncPairId": "uuid-a",
  "status": "success",
  "filesCount": 42,
  "totalSize": 1073741824,
  "duration": 15.5,
  "syncedFiles": [],
  "errors": []
}
```

---

## 5. 用户界面设计

### 5.1 菜单栏图标状态

| 状态 | 图标 | 描述 |
|------|------|------|
| 空闲 - 未连接 | ○ (空心) | 无外置硬盘连接 |
| 空闲 - 已连接 | ● (实心) | 外置硬盘已连接 |
| 同步中 | ◐ (旋转) | 正在执行同步 |
| 错误 | ⚠ (警告) | 发生错误需要关注 |

### 5.2 菜单结构

```
┌─────────────────────────────────┐
│ ● BACKUP 已连接                  │  ← 硬盘状态
│ ○ PORTABLE 未连接                │
├─────────────────────────────────┤
│ 📁 Downloads → BACKUP           │  ← 当前模式
│ 📁 Documents → 本地             │
├─────────────────────────────────┤
│ ↻ 立即同步                ⌘S    │  ← 操作
│ 📊 同步历史              ⌘H    │
│ 📂 打开 Downloads        ⌘O    │
│ 📄 查看日志              ⌘L    │
├─────────────────────────────────┤
│ ⚙ 设置...               ⌘,    │
│ ✕ 退出                   ⌘Q    │
└─────────────────────────────────┘
```

### 5.3 设置窗口 Tab 结构

| Tab | 内容 |
|-----|------|
| 通用 | 开机启动、通知设置、日志级别 |
| 硬盘 | 硬盘列表管理、优先级调整 |
| 目录 | 同步目录对管理、方向配置 |
| 过滤 | 排除规则编辑、预设选择 |
| 监控 | 文件监控开关、防抖时间 |
| 统计 | 同步历史、数据统计、图表 |

---

## 6. 实施计划

### 6.1 阶段一: 核心功能 (P0)

**目标**: 实现多硬盘、多目录、可配置的基础同步功能

| 任务 | 描述 |
|------|------|
| 1.1 | 重构配置系统: JSON 存储 + ConfigManager |
| 1.2 | 实现多硬盘管理: DiskManager |
| 1.3 | 实现多目录同步: SyncPairManager |
| 1.4 | 实现同步方向配置 |
| 1.5 | 实现文件过滤系统 |
| 1.6 | 实现设置窗口 (SwiftUI) |
| 1.7 | 更新菜单栏显示 |
| 1.8 | 测试与修复 |

### 6.2 阶段二: 增强功能 (P1)

**目标**: 添加文件监控、完整 GUI、异常保护

| 任务 | 描述 |
|------|------|
| 2.1 | 实现 FSEvents 文件监控 |
| 2.2 | 实现同步进度 UI |
| 2.3 | 实现同步历史列表 |
| 2.4 | 实现异常检测与恢复 |
| 2.5 | 实现开机自启动管理 |
| 2.6 | 测试与修复 |

### 6.3 阶段三: 完善功能 (P2)

**目标**: 完善统计、高级过滤、配置迁移

| 任务 | 描述 |
|------|------|
| 3.1 | 实现完整统计面板 |
| 3.2 | 实现统计图表 |
| 3.3 | 实现高级过滤规则 |
| 3.4 | 实现配置导入导出 |
| 3.5 | 性能优化 |
| 3.6 | 最终测试与发布 |

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| exFAT 不支持符号链接 | 部分硬盘无法使用链接切换功能 | 检测文件系统，exFAT 时仅同步不创建链接 |
| 大文件同步中断 | 数据不完整 | 使用 rsync --partial，支持断点续传 |
| 配置文件损坏 | 无法正常启动 | 配置校验 + 默认回退 + 备份机制 |
| 硬盘意外断开 | 悬空链接导致写入失败 | 定时检查链接有效性 + 快速恢复 |

---

## 8. 附录

### 8.1 默认排除文件列表

```
.DS_Store
.Trash
.Spotlight-V100
.fseventsd
*.tmp
*.temp
*.swp
*.swo
*~
Thumbs.db
desktop.ini
*.part
*.crdownload
*.download
```

### 8.2 参考资料

- [FUSE-T](https://www.fuse-t.org/) - 推荐的 FUSE 实现
- [macFUSE](https://macfuse.github.io/) - 备选 FUSE 实现
- [ObjectBox Swift](https://docs.objectbox.io/swift) - 数据存储
- [FSEvents 编程指南](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/)
- [SwiftUI 文档](https://developer.apple.com/documentation/swiftui/)
- [LaunchAgent 配置](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)

---

*文档维护: 需求变更时更新此文档并记录版本 | v3.0 | 2026-01-21*
