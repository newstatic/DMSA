# DMSA UI 修改计划

> 版本: 1.0 | 创建日期: 2026-01-27
>
> 返回 [目录](00_README.md) | 上一节: [21_UI设计规范](21_UI设计规范.md)

---

## 一、代码审查总结

### 1.1 当前架构概述

**当前实现:**
- 单窗口 + 左侧导航架构 (已实现)
- 使用 `NavigationView` + `List` 实现侧边栏
- 11 个导航标签页 (dashboard, general, disks, syncPairs, filters, notifications, notificationHistory, logs, history, statistics, advanced)
- 窗口尺寸: 750x500 (min) / 850x600 (ideal)

**主要文件:**
| 文件 | 职责 | 状态 |
|------|------|------|
| `MainView.swift` | 主窗口 + 导航 | 需重构 |
| `MenuBarManager.swift` | 状态栏菜单 | 需更新 |
| `DashboardView.swift` | 仪表盘 | 需重构 |
| `DiskSettingsView.swift` | 磁盘管理 | 需重构为 Master-Detail |
| `GeneralSettingsView.swift` | 通用设置 | 基本符合 |
| `SyncProgressView.swift` | 同步进度 | 需整合到同步页 |

### 1.2 与设计规范差异

| 设计规范要求 | 当前实现 | 差异说明 |
|-------------|---------|---------|
| 窗口尺寸 900x600 | 850x600 | 尺寸略小 |
| 侧边栏宽度 220px | 180px (min) | 宽度不足 |
| 6 个导航项 | 11 个导航项 | 导航过多需整合 |
| 侧边栏顶部状态头 | 无 | 缺失 |
| 仪表盘状态横幅 | 简单状态指示 | 需重构 |
| 状态环组件 | 无 | 缺失 |
| 磁盘页 Master-Detail | 普通列表 | 需重构 |
| 冲突解决页面 | 无 | 缺失 |
| 设置分组样式 | 普通列表 | 样式不符 |

### 1.3 现有组件可复用性

**可直接复用:**
- `SectionHeader` - 节标题组件
- `SettingRow` - 设置行组件
- `ToggleRow` / `CheckboxRow` - 开关组件
- `StorageBar` - 存储条组件
- `ButtonStyles` - 按钮样式
- `ProgressBar` - 进度条组件

**需修改后复用:**
- `DiskCard` - 需适配新样式
- `SyncProgressView` - 需整合到主窗口

**需新建:**
- `StatusRing` - 状态环组件
- `SidebarHeader` - 侧边栏状态头
- `ActionCard` - 快速操作卡片
- `StatCard` - 统计卡片
- `ActivityRow` - 活动记录行
- `ConflictCard` - 冲突卡片
- `VersionCard` - 版本对比卡片

---

## 二、修改计划概览

### 2.1 分阶段实施

```
Phase 1: 基础框架改造 (导航重构)
    ↓
Phase 2: 核心组件开发 (新组件)
    ↓
Phase 3: 页面重构 (6 个主页面)
    ↓
Phase 4: 交互完善 (动画 + 快捷键)
```

### 2.2 优先级分配

| 优先级 | 内容 | 预计改动 |
|-------|------|---------|
| P0 | 导航结构重构 | MainView.swift |
| P1 | 仪表盘重构 | DashboardView.swift + 新组件 |
| P2 | 同步页面实现 | 新建 SyncPage.swift |
| P2 | 磁盘页面重构 | DiskSettingsView.swift |
| P3 | 冲突页面实现 | 新建 ConflictsPage.swift |
| P3 | 设置页面整合 | 合并多个设置视图 |
| P4 | 菜单栏更新 | MenuBarManager.swift |
| P4 | 动画与交互 | 各组件 |

---

## 三、Phase 1: 基础框架改造

### 3.1 导航结构重构

**目标:** 将 11 个标签页整合为 6 个主导航项

**新导航结构:**
```swift
enum MainTab: String, CaseIterable {
    case dashboard    // 仪表盘 (首页)
    case sync         // 同步 (原同步相关功能)
    case conflicts    // 冲突 (新页面)
    case disks        // 磁盘 (原磁盘管理)
    case settings     // 设置 (合并所有设置)
    case logs         // 日志
}
```

**整合映射:**
| 原标签 | 新归属 |
|-------|--------|
| dashboard | dashboard |
| general | settings |
| disks | disks |
| syncPairs | settings (同步对子项) |
| filters | settings (过滤子项) |
| notifications | settings (通知子项) |
| notificationHistory | logs (或设置) |
| logs | logs |
| history | sync (同步历史) |
| statistics | dashboard (或设置) |
| advanced | settings (高级子项) |

### 3.2 MainView.swift 修改清单

```yaml
changes:
  - id: "nav_enum"
    description: "重构 MainTab 枚举"
    details:
      - 减少到 6 个主导航项
      - 添加 SF Symbols 图标映射
      - 添加快捷键映射 (⌘1-⌘4, ⌘,)
      - 添加 badge 绑定支持

  - id: "sidebar_width"
    description: "调整侧边栏宽度"
    details:
      - 默认宽度改为 220
      - 最小宽度改为 180
      - 最大宽度改为 280

  - id: "window_size"
    description: "调整窗口尺寸"
    details:
      - 默认尺寸改为 900x600
      - 最小尺寸改为 720x480

  - id: "sidebar_header"
    description: "添加侧边栏状态头"
    details:
      - 在 List 顶部添加 SidebarHeader 组件
      - 显示应用状态图标和文字
```

### 3.3 新建文件: SidebarHeader.swift

```swift
// 位置: UI/Components/SidebarHeader.swift
// 功能: 侧边栏顶部状态显示组件

struct SidebarHeader: View {
    @Binding var appState: AppState  // 绑定全局状态

    // 显示:
    // - 状态图标 (36px, 带动画)
    // - "DMSA" 标题
    // - 状态文字 (运行中/同步中/错误等)
}
```

---

## 四、Phase 2: 核心组件开发

### 4.1 新建组件列表

| 组件名 | 文件 | 用途 |
|-------|------|------|
| StatusRing | `StatusRing.swift` | 状态环 (带进度) |
| SidebarHeader | `SidebarHeader.swift` | 侧边栏状态头 |
| ActionCard | `ActionCard.swift` | 快速操作卡片 |
| StatCard | `StatCard.swift` | 统计数字卡片 |
| StatChip | `StatChip.swift` | 小型统计标签 |
| ActivityRow | `ActivityRow.swift` | 活动记录行 |
| ConflictCard | `ConflictCard.swift` | 冲突文件卡片 |
| VersionCard | `VersionCard.swift` | 版本对比卡片 |
| NavigationBadge | `NavigationBadge.swift` | 导航项徽章 |
| FileIcon | `FileIcon.swift` | 文件类型图标 |

### 4.2 StatusRing 组件规格

```yaml
StatusRing:
  props:
    size: CGFloat           # 外圈尺寸
    icon: String            # SF Symbol 名称
    color: Color            # 主题色
    progress: Double?       # 0-1 进度 (可选)
    animation: Animation?   # 图标动画

  states:
    ready:
      icon: "checkmark.circle.fill"
      color: "systemGreen"
    syncing:
      icon: "arrow.clockwise"
      color: "systemBlue"
      animation: "rotate"
    error:
      icon: "exclamationmark.triangle.fill"
      color: "systemRed"

  visual:
    - 外圈: 细线圆环 (背景色)
    - 进度: 彩色弧线 (从 12 点顺时针)
    - 图标: 居中显示, 可旋转动画
```

### 4.3 ActionCard 组件规格

```yaml
ActionCard:
  props:
    icon: String
    title: String
    shortcut: String?
    enabled: Bool
    action: () -> Void

  layout:
    width: 140
    height: 100
    padding: 16
    cornerRadius: 10

  states:
    normal:
      background: "controlBackgroundColor"
    hover:
      background: "selectedContentBackgroundColor"
    disabled:
      opacity: 0.5
```

### 4.4 StatCard 组件规格

```yaml
StatCard:
  props:
    icon: String
    label: String
    value: String
    subtitle: String?
    color: Color

  layout:
    padding: 16
    cornerRadius: 10
    background: "controlBackgroundColor"

  structure:
    - 顶部: 图标 (左对齐)
    - 中部: 数值 (大字)
    - 底部: 标签 (小字灰色)
```

---

## 五、Phase 3: 页面重构

### 5.1 仪表盘页面 (DashboardView)

**重构范围:** 完全重构

**新结构:**
```yaml
sections:
  - status_banner:
      - StatusRing (大号, 80px)
      - 状态标题 + 副标题
      - StatChip x3 (文件数/磁盘/上次同步)

  - quick_actions:
      - SectionHeader "快速操作"
      - ActionCard x3 (立即同步/添加磁盘/打开Downloads)

  - storage_overview:
      - SectionHeader "存储"
      - StorageCard x2 (本地缓存/外置磁盘)

  - recent_activity:
      - SectionHeader "最近活动" + "查看全部"链接
      - ActivityRow x5
```

**删除内容:**
- `syncControlSection` (移至同步页)
- `quickStatsSection` 时间范围选择器
- `DiskStatusCard` (改用新样式)

### 5.2 同步页面 (新建 SyncPage.swift)

**功能:** 同步控制 + 进度 + 历史

**结构:**
```yaml
sections:
  - sync_status_header:
      - StatusRing (100px)
      - 状态标题 + 副标题
      - 控制按钮 (暂停/取消/开始)

  - progress (同步中显示):
      - ProgressView (线性)
      - 当前文件信息

  - stats_grid:
      - StatCard x4 (已处理/已传输/速度/剩余时间)

  - current_file (同步中显示):
      - 文件图标 + 名称 + 路径
      - 单文件进度

  - errors (有错误时显示):
      - 错误列表 + 重试按钮

  - history:
      - 同步历史记录列表
```

### 5.3 冲突页面 (新建 ConflictsPage.swift)

**功能:** 冲突文件展示 + 解决操作

**结构:**
```yaml
sections:
  - header:
      - 标题 "文件冲突"
      - 副标题 "{n} 个文件需要解决"
      - 批量操作菜单
      - 搜索框

  - conflict_list:
      - ConflictCard (每个冲突文件):
          - 文件信息 (图标/名称/路径)
          - VersionCard x2 (本地 vs 外部)
          - 操作按钮 (保留本地/保留外部/保留两者)

  - empty_state (无冲突时):
      - 成功图标
      - "没有冲突" 文字
```

### 5.4 磁盘页面 (DiskSettingsView 重构)

**改造点:** 改为 Master-Detail 布局

**结构:**
```yaml
layout: "master_detail"
master_width: 240

master_panel (左侧):
  - header: "磁盘" + "+" 按钮
  - disk_list:
      - 状态点 + 图标 + 名称 + 连接状态

detail_panel (右侧):
  - empty_state (未选择)
  - disk_detail (已选择):
      - 磁盘图标 (64px) + 名称 + 状态徽章
      - 存储空间条 (分段显示)
      - 信息网格 (同步目录/目标目录/文件数等)
      - 操作按钮 (立即同步/编辑/移除)
```

### 5.5 设置页面 (合并重构)

**目标:** 将 general/syncPairs/filters/notifications/advanced 合并为分组列表

**结构:**
```yaml
sections:
  - general:
      title: "通用"
      items:
        - 登录时启动 (toggle)
        - 在 Dock 中显示 (toggle)
        - 启用通知 (toggle)
        - 通知类型 (multi-select)

  - sync:
      title: "同步"
      items:
        - 自动同步间隔 (slider)
        - 磁盘连接时自动同步 (toggle)
        - 冲突处理策略 (picker)
        - 排除文件 (list)

  - storage:
      title: "存储"
      items:
        - 存储信息卡片
        - 自动清理缓存 (toggle)
        - 空间阈值 (slider)
        - 最少保留天数 (stepper)
        - 清理所有缓存 (button)

  - advanced:
      title: "高级"
      items:
        - 日志级别 (picker)
        - 诊断信息卡片
        - 维护操作按钮组
        - 重置所有设置 (button)
```

### 5.6 日志页面 (LogView 保留)

**改动:** 样式微调，添加 SectionHeader

---

## 六、Phase 4: 交互完善

### 6.1 键盘快捷键

```yaml
global_shortcuts:
  - "⌘1": 仪表盘
  - "⌘2": 同步
  - "⌘3": 冲突
  - "⌘4": 磁盘
  - "⌘,": 设置
  - "⌘S": 开始同步 (在仪表盘/同步页)
  - "⌘R": 刷新

focus_navigation:
  - Tab: 在表单控件间移动
  - 方向键: 在列表中移动
  - Enter: 确认选择
  - Esc: 取消/关闭弹窗
```

### 6.2 动画效果

```yaml
animations:
  - sync_icon_rotate:
      type: "linear"
      duration: 1.0
      repeat: true
      trigger: "syncing"

  - progress_bar:
      type: "easeInOut"
      duration: 0.2

  - status_change:
      type: "spring"
      duration: 0.3

  - list_appear:
      type: "opacity + move"
      duration: 0.2
      stagger: 0.05
```

### 6.3 状态栏菜单更新

```yaml
MenuBarManager_changes:
  - 简化菜单项 (仅保留快速操作)
  - 更新图标逻辑:
      ready: "checkmark.circle.fill" (绿色)
      syncing: "arrow.clockwise" (旋转)
      error: "exclamationmark.triangle"
      paused: "pause.circle"
  - 移除磁盘状态详情 (在主窗口查看)
```

---

## 七、文件变更清单

### 7.1 新建文件

```
UI/Components/
├── StatusRing.swift          # 状态环组件
├── SidebarHeader.swift       # 侧边栏状态头
├── ActionCard.swift          # 快速操作卡片
├── StatCard.swift            # 统计卡片
├── StatChip.swift            # 小型统计标签
├── ActivityRow.swift         # 活动记录行
├── ConflictCard.swift        # 冲突文件卡片
├── VersionCard.swift         # 版本对比卡片
├── NavigationBadge.swift     # 导航徽章
└── FileIcon.swift            # 文件类型图标

UI/Views/
├── SyncPage.swift            # 同步页面 (新建)
├── ConflictsPage.swift       # 冲突页面 (新建)
└── SettingsPage.swift        # 设置页面 (合并后新建)
```

### 7.2 修改文件

```
UI/Views/MainView.swift           # 导航重构
UI/Views/Settings/DashboardView.swift  # 仪表盘重构
UI/Views/Settings/DiskSettingsView.swift  # Master-Detail
UI/MenuBarManager.swift           # 菜单简化
UI/Components/SectionHeader.swift # 样式微调
UI/Styles/ButtonStyles.swift      # 添加新样式
```

### 7.3 删除/废弃文件

```
(标记废弃，暂不删除)
UI/Views/Settings/GeneralSettingsView.swift  → 合并到 SettingsPage
UI/Views/Settings/SyncPairSettingsView.swift → 合并到 SettingsPage
UI/Views/Settings/FilterSettingsView.swift   → 合并到 SettingsPage
UI/Views/Settings/NotificationSettingsView.swift → 合并到 SettingsPage
UI/Views/Settings/AdvancedSettingsView.swift → 合并到 SettingsPage
UI/Views/Settings/StatisticsView.swift       → 合并到 DashboardView
UI/Views/History/HistoryView.swift           → 合并到 SyncPage
UI/Views/History/HistoryContentView.swift    → 合并到 SyncPage
```

---

## 八、实施顺序

### 8.1 推荐顺序

```
Week 1: Phase 1 + Phase 2 (部分)
├── Day 1-2: MainView 导航重构
├── Day 3-4: 新建核心组件 (StatusRing, ActionCard, StatCard)
└── Day 5: SidebarHeader + 集成测试

Week 2: Phase 2 (完成) + Phase 3 (部分)
├── Day 1-2: 完成剩余组件
├── Day 3-4: DashboardView 重构
└── Day 5: SyncPage 新建

Week 3: Phase 3 (完成)
├── Day 1-2: ConflictsPage 新建
├── Day 3-4: DiskSettingsView Master-Detail
└── Day 5: SettingsPage 合并

Week 4: Phase 4 + 测试
├── Day 1-2: 键盘快捷键 + 动画
├── Day 3: MenuBarManager 更新
├── Day 4-5: 集成测试 + Bug 修复
```

### 8.2 依赖关系

```
StatusRing ─────────────────────────┐
SidebarHeader ──────────────────────┤
ActionCard ─────────────────────────┼──→ DashboardView
StatCard ───────────────────────────┤
ActivityRow ────────────────────────┘

StatusRing ─────────────────────────┐
StatCard ───────────────────────────┼──→ SyncPage
ProgressBar (现有) ─────────────────┘

ConflictCard ───────────────────────┐
VersionCard ────────────────────────┼──→ ConflictsPage
FileIcon ───────────────────────────┘

MainView (重构后) ──────────────────→ 所有页面
```

---

## 九、验收标准

### 9.1 功能验收

- [ ] 导航切换流畅，无卡顿
- [ ] 侧边栏状态实时更新
- [ ] 同步控制按钮正常工作
- [ ] 冲突解决操作有效
- [ ] 磁盘详情正确显示
- [ ] 设置保存后立即生效
- [ ] 键盘快捷键全部可用

### 9.2 UI 验收

- [ ] 符合设计规范尺寸
- [ ] 颜色与规范一致
- [ ] 图标使用正确
- [ ] 动画流畅
- [ ] 响应式布局正常
- [ ] 深色模式适配

### 9.3 性能验收

- [ ] 窗口打开 < 500ms
- [ ] 导航切换 < 100ms
- [ ] 列表滚动 60fps
- [ ] 内存占用 < 100MB

---

*文档版本: 1.0 | 最后更新: 2026-01-27*
