# Delt MACOS Sync App (DMSA) 配置项文档

> 版本: 2.0 | 更新日期: 2026-01-20

---

## 目录

1. [配置文件结构](#1-配置文件结构)
2. [通用配置](#2-通用配置)
3. [硬盘配置](#3-硬盘配置)
4. [同步对配置](#4-同步对配置)
5. [过滤规则配置](#5-过滤规则配置)
6. [缓存配置](#6-缓存配置)
7. [监控配置](#7-监控配置)
8. [通知配置](#8-通知配置)
9. [日志配置](#9-日志配置)
10. [UI 配置](#10-ui-配置)
11. [完整配置示例](#11-完整配置示例)
12. [配置校验规则](#12-配置校验规则)

---

## 1. 配置文件结构

### 1.1 文件位置

| 文件 | 路径 | 用途 |
|------|------|------|
| 主配置文件 | `~/Library/Application Support/DMSA/config.json` | 所有用户配置 |
| 默认配置 | 应用内置 | 配置损坏时的回退 |
| 配置备份 | `~/Library/Application Support/DMSA/config.backup.json` | 自动备份 |

### 1.2 顶层结构

```json
{
  "version": "2.0",
  "general": { ... },
  "disks": [ ... ],
  "syncPairs": [ ... ],
  "filters": { ... },
  "cache": { ... },
  "monitoring": { ... },
  "notifications": { ... },
  "logging": { ... },
  "ui": { ... }
}
```

---

## 2. 通用配置

### 2.1 配置项列表

| 配置项 | 类型 | 默认值 | 说明 | 必填 |
|--------|------|--------|------|------|
| `launchAtLogin` | Boolean | `false` | 开机自启动 | 否 |
| `showInDock` | Boolean | `false` | 是否在 Dock 显示 | 否 |
| `checkForUpdates` | Boolean | `true` | 自动检查更新 | 否 |
| `language` | String | `"system"` | 界面语言 | 否 |

### 2.2 JSON 结构

```json
{
  "general": {
    "launchAtLogin": false,
    "showInDock": false,
    "checkForUpdates": true,
    "language": "system"
  }
}
```

### 2.3 配置项详解

#### `launchAtLogin`

| 属性 | 值 |
|------|-----|
| 类型 | Boolean |
| 默认值 | `false` |
| 可选值 | `true` / `false` |
| 说明 | 是否在系统登录时自动启动应用 |
| 实现方式 | LaunchAgent (`~/Library/LaunchAgents/com.ttttt.dmsa.plist`) |

#### `showInDock`

| 属性 | 值 |
|------|-----|
| 类型 | Boolean |
| 默认值 | `false` |
| 可选值 | `true` / `false` |
| 说明 | 是否在 Dock 栏显示应用图标 |
| 注意 | 菜单栏应用通常设为 false (LSUIElement) |

#### `language`

| 属性 | 值 |
|------|-----|
| 类型 | String |
| 默认值 | `"system"` |
| 可选值 | `"system"` / `"zh-Hans"` / `"zh-Hant"` / `"en"` |
| 说明 | 界面显示语言 |

---

## 3. 硬盘配置

### 3.1 配置项列表

| 配置项 | 类型 | 默认值 | 说明 | 必填 |
|--------|------|--------|------|------|
| `id` | String | - | 唯一标识符 (UUID) | 是 |
| `name` | String | - | 硬盘名称 (显示在 /Volumes/) | 是 |
| `mountPath` | String | - | 完整挂载路径 | 是 |
| `priority` | Integer | `0` | 优先级 (越小越优先) | 否 |
| `enabled` | Boolean | `true` | 是否启用 | 否 |
| `fileSystem` | String | `"auto"` | 文件系统类型 | 否 |

### 3.2 JSON 结构

```json
{
  "disks": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "BACKUP",
      "mountPath": "/Volumes/BACKUP",
      "priority": 1,
      "enabled": true,
      "fileSystem": "auto"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "name": "PORTABLE",
      "mountPath": "/Volumes/PORTABLE",
      "priority": 2,
      "enabled": true,
      "fileSystem": "auto"
    }
  ]
}
```

### 3.3 配置项详解

#### `id`

| 属性 | 值 |
|------|-----|
| 类型 | String (UUID v4) |
| 格式 | `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx` |
| 说明 | 硬盘的唯一标识符，用于关联同步对 |
| 生成方式 | 添加硬盘时自动生成 |

#### `name`

| 属性 | 值 |
|------|-----|
| 类型 | String |
| 约束 | 1-255 字符，不能包含 `/` |
| 说明 | 硬盘在 Finder 中显示的名称 |
| 示例 | `"BACKUP"`, `"My External Drive"` |

#### `mountPath`

| 属性 | 值 |
|------|-----|
| 类型 | String |
| 格式 | 绝对路径，通常为 `/Volumes/{name}` |
| 说明 | 硬盘挂载后的完整路径 |
| 校验 | 必须以 `/Volumes/` 开头 |

#### `priority`

| 属性 | 值 |
|------|-----|
| 类型 | Integer |
| 默认值 | `0` |
| 范围 | 0-999 |
| 说明 | 当多个硬盘同时连接时，优先使用数值最小的硬盘 |

#### `fileSystem`

| 属性 | 值 |
|------|-----|
| 类型 | String |
| 默认值 | `"auto"` |
| 可选值 | `"auto"` / `"apfs"` / `"hfs+"` / `"exfat"` / `"ntfs"` |
| 说明 | 指定文件系统类型，`auto` 表示自动检测 |
| 影响 | exFAT/NTFS 不支持符号链接，将自动禁用链接功能 |

---

## 4. 同步对配置

### 4.1 配置项列表

| 配置项 | 类型 | 默认值 | 说明 | 必填 |
|--------|------|--------|------|------|
| `id` | String | - | 唯一标识符 (UUID) | 是 |
| `diskId` | String | - | 关联的硬盘 ID | 是 |
| `localPath` | String | - | 本地目录路径 | 是 |
| `externalRelativePath` | String | - | 外置硬盘相对路径 | 是 |
| `direction` | String | `"local_to_external"` | 同步方向 | 是 |
| `createSymlink` | Boolean | `true` | 是否创建符号链接 | 否 |
| `enabled` | Boolean | `true` | 是否启用 | 否 |
| `excludePatterns` | Array | `[]` | 本同步对专属排除规则 | 否 |

### 4.2 JSON 结构

```json
{
  "syncPairs": [
    {
      "id": "660e8400-e29b-41d4-a716-446655440000",
      "diskId": "550e8400-e29b-41d4-a716-446655440000",
      "localPath": "~/Downloads",
      "externalRelativePath": "Downloads",
      "direction": "local_to_external",
      "createSymlink": true,
      "enabled": true,
      "excludePatterns": []
    },
    {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "diskId": "550e8400-e29b-41d4-a716-446655440000",
      "localPath": "~/Documents",
      "externalRelativePath": "Documents",
      "direction": "bidirectional",
      "createSymlink": false,
      "enabled": true,
      "excludePatterns": ["*.tmp"]
    }
  ]
}
```

### 4.3 配置项详解

#### `localPath`

| 属性 | 值 |
|------|-----|
| 类型 | String |
| 格式 | 绝对路径，支持 `~` 展开 |
| 示例 | `"~/Downloads"`, `"/Users/user/Documents"` |
| 校验 | 路径必须存在或可创建 |

#### `externalRelativePath`

| 属性 | 值 |
|------|-----|
| 类型 | String |
| 格式 | 相对于硬盘挂载点的相对路径 |
| 示例 | `"Downloads"`, `"Backup/Documents"` |
| 说明 | 完整路径 = `{disk.mountPath}/{externalRelativePath}` |

#### `direction`

| 属性 | 值 |
|------|-----|
| 类型 | String (枚举) |
| 默认值 | `"local_to_external"` |
| 可选值 | 见下表 |

| 值 | 说明 |
|----|------|
| `"local_to_external"` | 本地 → 外置硬盘 (单向) |
| `"external_to_local"` | 外置硬盘 → 本地 (单向) |
| `"bidirectional"` | 双向同步 (以修改时间较新者为准) |

#### `createSymlink`

| 属性 | 值 |
|------|-----|
| 类型 | Boolean |
| 默认值 | `true` |
| 说明 | 硬盘连接后是否将本地目录替换为指向外置硬盘的符号链接 |
| 限制 | 仅 APFS/HFS+ 文件系统支持 |

---

## 5. 过滤规则配置

### 5.1 配置项列表

| 配置项 | 类型 | 默认值 | 说明 | 必填 |
|--------|------|--------|------|------|
| `excludePatterns` | Array | 见默认值 | 全局排除模式列表 | 否 |
| `includePatterns` | Array | `["*"]` | 全局包含模式列表 | 否 |
| `maxFileSize` | Integer | `null` | 最大文件大小 (bytes) | 否 |
| `minFileSize` | Integer | `null` | 最小文件大小 (bytes) | 否 |
| `excludeHidden` | Boolean | `false` | 排除隐藏文件 | 否 |

### 5.2 JSON 结构

```json
{
  "filters": {
    "excludePatterns": [
      ".DS_Store",
      ".Trash",
      ".Spotlight-V100",
      ".fseventsd",
      "*.tmp",
      "*.temp",
      "*.swp",
      "*.swo",
      "*~",
      "Thumbs.db",
      "desktop.ini",
      "*.part",
      "*.crdownload",
      "*.download",
      "node_modules",
      ".git",
      "__pycache__"
    ],
    "includePatterns": ["*"],
    "maxFileSize": null,
    "minFileSize": null,
    "excludeHidden": false
  }
}
```

### 5.3 配置项详解

#### `excludePatterns`

| 属性 | 值 |
|------|-----|
| 类型 | Array of String |
| 格式 | glob 模式 |
| 说明 | 匹配这些模式的文件/目录将被排除 |

**支持的 glob 模式:**

| 模式 | 说明 | 示例 |
|------|------|------|
| `*` | 匹配任意字符 (不含 /) | `*.tmp` 匹配 `file.tmp` |
| `**` | 匹配任意目录层级 | `**/node_modules` |
| `?` | 匹配单个字符 | `file?.txt` |
| `[abc]` | 匹配字符集 | `file[123].txt` |
| `[a-z]` | 匹配字符范围 | `file[a-z].txt` |

#### `maxFileSize` / `minFileSize`

| 属性 | 值 |
|------|-----|
| 类型 | Integer 或 null |
| 单位 | bytes |
| 默认值 | `null` (不限制) |
| 示例 | `1073741824` (1GB) |

**常用大小参考:**

| 大小 | bytes 值 |
|------|----------|
| 1 MB | 1048576 |
| 10 MB | 10485760 |
| 100 MB | 104857600 |
| 1 GB | 1073741824 |
| 10 GB | 10737418240 |

### 5.4 默认排除列表

```json
[
  ".DS_Store",
  ".Trash",
  ".Spotlight-V100",
  ".fseventsd",
  ".TemporaryItems",
  ".Trashes",
  ".vol",
  "*.tmp",
  "*.temp",
  "*.swp",
  "*.swo",
  "*~",
  "Thumbs.db",
  "desktop.ini",
  "*.part",
  "*.crdownload",
  "*.download",
  "*.partial"
]
```

---

## 6. 缓存配置

### 6.1 配置项列表

| 配置项 | 类型 | 默认值 | 说明 | 必填 |
|--------|------|--------|------|------|
| `maxCacheSize` | Integer | `10737418240` | LOCAL 缓存最大空间 (10GB) | 否 |
| `reserveBuffer` | Integer | `524288000` | 预留缓冲空间 (500MB) | 否 |
| `evictionCheckInterval` | Integer | `300` | 淘汰检查间隔 (秒) | 否 |
| `autoEvictionEnabled` | Boolean | `true` | 启用自动淘汰 | 否 |
| `evictionStrategy` | String | `"modified_time"` | 淘汰策略 | 否 |

### 6.2 JSON 结构

```json
{
  "cache": {
    "maxCacheSize": 10737418240,
    "reserveBuffer": 524288000,
    "evictionCheckInterval": 300,
    "autoEvictionEnabled": true,
    "evictionStrategy": "modified_time"
  }
}
```

### 6.3 配置项详解

#### `maxCacheSize`

| 属性 | 值 |
|------|-----|
| 类型 | Integer |
| 单位 | bytes |
| 默认值 | `10737418240` (10 GB) |
| 最小值 | `1073741824` (1 GB) |
| 最大值 | 无限制 (建议不超过可用空间的 50%) |
| 说明 | LOCAL 缓存目录允许的最大占用空间 |

**预设值参考:**

| 描述 | 值 |
|------|-----|
| 小 (1 GB) | `1073741824` |
| 中 (5 GB) | `5368709120` |
| 大 (10 GB) | `10737418240` |
| 超大 (50 GB) | `53687091200` |
| 不限制 | `null` |

#### `evictionStrategy`

| 属性 | 值 |
|------|-----|
| 类型 | String (枚举) |
| 默认值 | `"modified_time"` |
| 可选值 | 见下表 |

| 值 | 说明 |
|----|------|
| `"modified_time"` | 按修改时间排序，最旧的先淘汰 |
| `"access_time"` | 按访问时间排序 (LRU) |
| `"size_first"` | 优先淘汰大文件 |

---

## 7. 监控配置

### 7.1 配置项列表

| 配置项 | 类型 | 默认值 | 说明 | 必填 |
|--------|------|--------|------|------|
| `enabled` | Boolean | `true` | 启用文件监控 | 否 |
| `debounceSeconds` | Integer | `5` | 变化后等待时间 (秒) | 否 |
| `batchSize` | Integer | `100` | 批量处理文件数 | 否 |
| `watchSubdirectories` | Boolean | `true` | 监控子目录 | 否 |

### 7.2 JSON 结构

```json
{
  "monitoring": {
    "enabled": true,
    "debounceSeconds": 5,
    "batchSize": 100,
    "watchSubdirectories": true
  }
}
```

### 7.3 配置项详解

#### `debounceSeconds`

| 属性 | 值 |
|------|-----|
| 类型 | Integer |
| 单位 | 秒 |
| 默认值 | `5` |
| 范围 | 1-300 |
| 说明 | 文件变化后等待此时间再触发同步，防止频繁同步 |

**推荐值:**

| 场景 | 推荐值 |
|------|--------|
| 实时性要求高 | 1-2 秒 |
| 一般使用 | 5 秒 |
| 降低系统负载 | 30-60 秒 |

---

## 8. 通知配置

### 8.1 配置项列表

| 配置项 | 类型 | 默认值 | 说明 | 必填 |
|--------|------|--------|------|------|
| `enabled` | Boolean | `true` | 启用系统通知 | 否 |
| `showOnDiskConnect` | Boolean | `true` | 硬盘连接时通知 | 否 |
| `showOnDiskDisconnect` | Boolean | `true` | 硬盘断开时通知 | 否 |
| `showOnSyncStart` | Boolean | `false` | 同步开始时通知 | 否 |
| `showOnSyncComplete` | Boolean | `true` | 同步完成时通知 | 否 |
| `showOnSyncError` | Boolean | `true` | 同步错误时通知 | 否 |
| `soundEnabled` | Boolean | `true` | 通知声音 | 否 |

### 8.2 JSON 结构

```json
{
  "notifications": {
    "enabled": true,
    "showOnDiskConnect": true,
    "showOnDiskDisconnect": true,
    "showOnSyncStart": false,
    "showOnSyncComplete": true,
    "showOnSyncError": true,
    "soundEnabled": true
  }
}
```

---

## 9. 日志配置

### 9.1 配置项列表

| 配置项 | 类型 | 默认值 | 说明 | 必填 |
|--------|------|--------|------|------|
| `level` | String | `"info"` | 日志级别 | 否 |
| `maxFileSize` | Integer | `10485760` | 单个日志文件最大大小 (10MB) | 否 |
| `maxFiles` | Integer | `5` | 保留的日志文件数量 | 否 |
| `logPath` | String | 见默认值 | 日志文件路径 | 否 |

### 9.2 JSON 结构

```json
{
  "logging": {
    "level": "info",
    "maxFileSize": 10485760,
    "maxFiles": 5,
    "logPath": "~/Library/Logs/DMSA/app.log"
  }
}
```

### 9.3 配置项详解

#### `level`

| 属性 | 值 |
|------|-----|
| 类型 | String (枚举) |
| 默认值 | `"info"` |
| 可选值 | 见下表 |

| 级别 | 说明 | 包含内容 |
|------|------|----------|
| `"debug"` | 调试 | 所有日志 |
| `"info"` | 信息 | info + warn + error |
| `"warn"` | 警告 | warn + error |
| `"error"` | 错误 | 仅 error |

---

## 10. UI 配置

### 10.1 配置项列表

| 配置项 | 类型 | 默认值 | 说明 | 必填 |
|--------|------|--------|------|------|
| `showProgressWindow` | Boolean | `true` | 同步时显示进度窗口 | 否 |
| `menuBarStyle` | String | `"icon"` | 菜单栏显示样式 | 否 |
| `theme` | String | `"system"` | 界面主题 | 否 |

### 10.2 JSON 结构

```json
{
  "ui": {
    "showProgressWindow": true,
    "menuBarStyle": "icon",
    "theme": "system"
  }
}
```

### 10.3 配置项详解

#### `menuBarStyle`

| 属性 | 值 |
|------|-----|
| 类型 | String (枚举) |
| 默认值 | `"icon"` |
| 可选值 | 见下表 |

| 值 | 说明 |
|----|------|
| `"icon"` | 仅显示图标 |
| `"icon_text"` | 图标 + 状态文字 |
| `"text"` | 仅状态文字 |

#### `theme`

| 属性 | 值 |
|------|-----|
| 类型 | String (枚举) |
| 默认值 | `"system"` |
| 可选值 | `"system"` / `"light"` / `"dark"` |

---

## 11. 完整配置示例

### 11.1 最小配置

```json
{
  "version": "2.0",
  "disks": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "BACKUP",
      "mountPath": "/Volumes/BACKUP"
    }
  ],
  "syncPairs": [
    {
      "id": "660e8400-e29b-41d4-a716-446655440000",
      "diskId": "550e8400-e29b-41d4-a716-446655440000",
      "localPath": "~/Downloads",
      "externalRelativePath": "Downloads",
      "direction": "local_to_external"
    }
  ]
}
```

### 11.2 完整配置

```json
{
  "version": "2.0",
  "general": {
    "launchAtLogin": true,
    "showInDock": false,
    "checkForUpdates": true,
    "language": "system"
  },
  "disks": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "BACKUP",
      "mountPath": "/Volumes/BACKUP",
      "priority": 1,
      "enabled": true,
      "fileSystem": "auto"
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "name": "PORTABLE",
      "mountPath": "/Volumes/PORTABLE",
      "priority": 2,
      "enabled": true,
      "fileSystem": "auto"
    }
  ],
  "syncPairs": [
    {
      "id": "660e8400-e29b-41d4-a716-446655440000",
      "diskId": "550e8400-e29b-41d4-a716-446655440000",
      "localPath": "~/Downloads",
      "externalRelativePath": "Downloads",
      "direction": "local_to_external",
      "createSymlink": true,
      "enabled": true,
      "excludePatterns": []
    },
    {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "diskId": "550e8400-e29b-41d4-a716-446655440000",
      "localPath": "~/Documents",
      "externalRelativePath": "Documents",
      "direction": "bidirectional",
      "createSymlink": false,
      "enabled": true,
      "excludePatterns": ["*.tmp", ".git"]
    },
    {
      "id": "660e8400-e29b-41d4-a716-446655440002",
      "diskId": "550e8400-e29b-41d4-a716-446655440000",
      "localPath": "~/Desktop",
      "externalRelativePath": "Desktop",
      "direction": "bidirectional",
      "createSymlink": false,
      "enabled": false,
      "excludePatterns": []
    }
  ],
  "filters": {
    "excludePatterns": [
      ".DS_Store",
      ".Trash",
      ".Spotlight-V100",
      ".fseventsd",
      ".TemporaryItems",
      "*.tmp",
      "*.temp",
      "*.swp",
      "*.swo",
      "*~",
      "Thumbs.db",
      "desktop.ini",
      "*.part",
      "*.crdownload",
      "*.download",
      "node_modules",
      ".git",
      "__pycache__",
      "*.pyc"
    ],
    "includePatterns": ["*"],
    "maxFileSize": null,
    "minFileSize": null,
    "excludeHidden": false
  },
  "cache": {
    "maxCacheSize": 10737418240,
    "reserveBuffer": 524288000,
    "evictionCheckInterval": 300,
    "autoEvictionEnabled": true,
    "evictionStrategy": "modified_time"
  },
  "monitoring": {
    "enabled": true,
    "debounceSeconds": 5,
    "batchSize": 100,
    "watchSubdirectories": true
  },
  "notifications": {
    "enabled": true,
    "showOnDiskConnect": true,
    "showOnDiskDisconnect": true,
    "showOnSyncStart": false,
    "showOnSyncComplete": true,
    "showOnSyncError": true,
    "soundEnabled": true
  },
  "logging": {
    "level": "info",
    "maxFileSize": 10485760,
    "maxFiles": 5,
    "logPath": "~/Library/Logs/DMSA/app.log"
  },
  "ui": {
    "showProgressWindow": true,
    "menuBarStyle": "icon",
    "theme": "system"
  }
}
```

---

## 12. 配置校验规则

### 12.1 必填字段校验

| 路径 | 校验规则 |
|------|----------|
| `version` | 必须存在且为 "2.0" |
| `disks` | 必须存在且为非空数组 |
| `disks[].id` | 必须为有效 UUID |
| `disks[].name` | 必须为非空字符串 |
| `disks[].mountPath` | 必须以 `/Volumes/` 开头 |
| `syncPairs` | 必须存在且为非空数组 |
| `syncPairs[].id` | 必须为有效 UUID |
| `syncPairs[].diskId` | 必须引用存在的 disk.id |
| `syncPairs[].localPath` | 必须为有效路径 |
| `syncPairs[].direction` | 必须为有效枚举值 |

### 12.2 类型校验

| 字段 | 期望类型 | 错误处理 |
|------|----------|----------|
| Boolean 字段 | `true` / `false` | 非法值使用默认值 |
| Integer 字段 | 整数 | 非法值使用默认值 |
| String 字段 | 字符串 | 非法值使用默认值 |
| Array 字段 | 数组 | 非法值使用空数组 |

### 12.3 关联校验

| 校验项 | 规则 |
|--------|------|
| diskId 引用 | syncPair.diskId 必须在 disks 中存在 |
| 路径唯一性 | 同一 disk 下的 localPath 不能重复 |
| UUID 唯一性 | 所有 id 必须全局唯一 |

### 12.4 错误处理策略

```
配置加载流程:
1. 读取配置文件
   ├─ 成功 → 解析 JSON
   └─ 失败 → 使用默认配置 + 提示用户

2. 解析 JSON
   ├─ 成功 → 执行校验
   └─ 失败 → 使用默认配置 + 提示用户

3. 执行校验
   ├─ 全部通过 → 使用配置
   ├─ 部分失败 → 使用有效部分 + 默认值补充 + 警告
   └─ 关键字段缺失 → 使用默认配置 + 提示用户

4. 自动备份
   └─ 成功加载后备份到 config.backup.json
```

---

## 附录: 配置项速查表

| 配置路径 | 类型 | 默认值 | 说明 |
|----------|------|--------|------|
| `version` | String | `"2.0"` | 配置版本 |
| `general.launchAtLogin` | Boolean | `false` | 开机自启动 |
| `general.showInDock` | Boolean | `false` | Dock显示 |
| `general.checkForUpdates` | Boolean | `true` | 检查更新 |
| `general.language` | String | `"system"` | 界面语言 |
| `disks[].id` | String | - | 硬盘UUID |
| `disks[].name` | String | - | 硬盘名称 |
| `disks[].mountPath` | String | - | 挂载路径 |
| `disks[].priority` | Integer | `0` | 优先级 |
| `disks[].enabled` | Boolean | `true` | 是否启用 |
| `disks[].fileSystem` | String | `"auto"` | 文件系统 |
| `syncPairs[].id` | String | - | 同步对UUID |
| `syncPairs[].diskId` | String | - | 关联硬盘 |
| `syncPairs[].localPath` | String | - | 本地路径 |
| `syncPairs[].externalRelativePath` | String | - | 外置相对路径 |
| `syncPairs[].direction` | String | `"local_to_external"` | 同步方向 |
| `syncPairs[].createSymlink` | Boolean | `true` | 创建符号链接 |
| `syncPairs[].enabled` | Boolean | `true` | 是否启用 |
| `filters.excludePatterns` | Array | 见文档 | 排除模式 |
| `filters.maxFileSize` | Integer | `null` | 最大文件大小 |
| `filters.minFileSize` | Integer | `null` | 最小文件大小 |
| `filters.excludeHidden` | Boolean | `false` | 排除隐藏文件 |
| `cache.maxCacheSize` | Integer | `10737418240` | 缓存大小限制 |
| `cache.reserveBuffer` | Integer | `524288000` | 预留缓冲 |
| `cache.evictionCheckInterval` | Integer | `300` | 淘汰检查间隔 |
| `cache.autoEvictionEnabled` | Boolean | `true` | 自动淘汰 |
| `cache.evictionStrategy` | String | `"modified_time"` | 淘汰策略 |
| `monitoring.enabled` | Boolean | `true` | 启用监控 |
| `monitoring.debounceSeconds` | Integer | `5` | 防抖秒数 |
| `monitoring.batchSize` | Integer | `100` | 批量大小 |
| `notifications.enabled` | Boolean | `true` | 启用通知 |
| `notifications.showOnDiskConnect` | Boolean | `true` | 连接通知 |
| `notifications.showOnSyncComplete` | Boolean | `true` | 完成通知 |
| `notifications.showOnSyncError` | Boolean | `true` | 错误通知 |
| `notifications.soundEnabled` | Boolean | `true` | 通知声音 |
| `logging.level` | String | `"info"` | 日志级别 |
| `logging.maxFileSize` | Integer | `10485760` | 日志文件大小 |
| `logging.maxFiles` | Integer | `5` | 保留文件数 |
| `ui.showProgressWindow` | Boolean | `true` | 显示进度窗口 |
| `ui.menuBarStyle` | String | `"icon"` | 菜单栏样式 |
| `ui.theme` | String | `"system"` | 界面主题 |

---

*文档维护: 配置项变更时更新此文档*
