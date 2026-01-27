# DMSA UI 设计规范

> 版本: 2.0 | 更新日期: 2026-01-27
>
> 返回 [目录](00_README.md) | 上一节: [20_App启动与交互流程](20_App启动与交互流程.md)

---

## 目录

1. [设计原则](#一设计原则)
2. [设计系统](#二设计系统)
3. [状态栏组件](#三状态栏组件)
4. [菜单栏设计](#四菜单栏设计)
5. [主窗口设计](#五主窗口设计)
6. [左侧导航栏](#六左侧导航栏)
7. [仪表盘页面](#七仪表盘页面)
8. [同步详情页面](#八同步详情页面)
9. [冲突解决页面](#九冲突解决页面)
10. [磁盘管理页面](#十磁盘管理页面)
11. [设置页面](#十一设置页面)
12. [弹窗与通知](#十二弹窗与通知)
13. [响应式设计](#十三响应式设计)
14. [无障碍设计](#十四无障碍设计)
15. [组件规范](#十五组件规范)

---

## 一、设计原则

### 1.1 核心设计理念

DMSA 采用**单窗口 + 左侧导航**的设计模式，遵循以下设计理念：

**单窗口设计 (Single Window)**
所有功能集成在一个主窗口内，通过左侧导航切换不同页面。避免多窗口管理的复杂性，提供一致的用户体验。状态栏图标提供快速访问入口。

**即时反馈 (Immediate Feedback)**
每个用户操作都应获得即时视觉反馈。同步进度、操作结果、错误状态都需在适当位置清晰展示。

**渐进披露 (Progressive Disclosure)**
默认展示最常用功能（仪表盘），高级选项隐藏在设置页面。用户可根据需要逐层深入了解更多控制选项。

**一致性 (Consistency)**
遵循 macOS Human Interface Guidelines，使用系统原生控件和交互模式，让用户无需学习即可上手。

### 1.2 设计原则清单

```yaml
design_principles:
  - name: "可预见性"
    description: "用户应能预测操作的结果"
    implementation:
      - "操作前显示确认信息"
      - "破坏性操作使用红色警告"
      - "提供撤销机制"

  - name: "反馈性"
    description: "系统状态应始终可见"
    implementation:
      - "状态栏图标实时反映系统状态"
      - "长时操作显示进度指示"
      - "操作完成后提供确认反馈"

  - name: "容错性"
    description: "允许用户犯错并提供恢复路径"
    implementation:
      - "危险操作要求二次确认"
      - "提供清晰的错误说明"
      - "给出具体的修复建议"

  - name: "效率性"
    description: "为熟练用户提供快捷方式"
    implementation:
      - "支持键盘快捷键"
      - "记住用户偏好设置"
      - "一键完成常用操作"

  - name: "美观性"
    description: "界面简洁、平衡、专业"
    implementation:
      - "遵循 macOS 设计语言"
      - "使用 SF Symbols"
      - "保持视觉层次清晰"
```

---

## 二、设计系统

### 2.1 颜色系统

使用 macOS 系统语义颜色确保自动适配深色模式：

```yaml
color_system:
  semantic_colors:
    primary:
      light: "systemBlue"
      dark: "systemBlue"
      usage: "主要操作按钮、链接、选中状态"

    success:
      light: "systemGreen"
      dark: "systemGreen"
      usage: "成功状态、就绪状态、完成指示"

    warning:
      light: "systemYellow"
      dark: "systemYellow"
      usage: "警告状态、启动中、需要注意"

    error:
      light: "systemRed"
      dark: "systemRed"
      usage: "错误状态、危险操作、失败指示"

    neutral:
      light: "systemGray"
      dark: "systemGray"
      usage: "禁用状态、次要信息、占位符"

  text_colors:
    primary:
      light: "labelColor"
      dark: "labelColor"
      usage: "主要文本、标题"

    secondary:
      light: "secondaryLabelColor"
      dark: "secondaryLabelColor"
      usage: "辅助说明、描述文字"

    tertiary:
      light: "tertiaryLabelColor"
      dark: "tertiaryLabelColor"
      usage: "提示文字、占位符"

  background_colors:
    window:
      light: "windowBackgroundColor"
      dark: "windowBackgroundColor"

    control:
      light: "controlBackgroundColor"
      dark: "controlBackgroundColor"

    selected:
      light: "selectedContentBackgroundColor"
      dark: "selectedContentBackgroundColor"
```

### 2.2 图标系统

```yaml
icon_system:
  source: "SF Symbols 4.0+"
  weight: "regular"
  size_scale:
    small: 12
    medium: 16
    large: 20
    xlarge: 24

  status_bar_icons:
    connecting:
      symbol: "arrow.triangle.2.circlepath"
      color: "systemGray"
      animation: "pulse"

    starting:
      symbol: "hourglass"
      color: "systemYellow"
      animation: "rotate"

    ready:
      symbol: "checkmark.circle.fill"
      color: "systemGreen"
      animation: null

    syncing:
      symbol: "arrow.clockwise"
      color: "systemBlue"
      animation: "rotate"

    error:
      symbol: "exclamationmark.triangle.fill"
      color: "systemRed"
      animation: "pulse"

  menu_icons:
    sync: "arrow.clockwise"
    conflict: "exclamationmark.2"
    disk: "externaldrive"
    settings: "gear"
    log: "doc.text"
    about: "info.circle"
    quit: "power"
```

### 2.3 排版系统

```yaml
typography:
  font_family: "system"  # SF Pro on macOS

  styles:
    largeTitle:
      size: 26
      weight: "bold"
      lineHeight: 32
      usage: "关于窗口主标题"

    title1:
      size: 22
      weight: "semibold"
      lineHeight: 28
      usage: "窗口标题"

    title2:
      size: 17
      weight: "semibold"
      lineHeight: 22
      usage: "分组标题"

    title3:
      size: 15
      weight: "semibold"
      lineHeight: 20
      usage: "列表项标题"

    body:
      size: 13
      weight: "regular"
      lineHeight: 18
      usage: "正文内容"

    callout:
      size: 12
      weight: "regular"
      lineHeight: 16
      usage: "辅助说明"

    caption:
      size: 11
      weight: "regular"
      lineHeight: 14
      usage: "时间戳、状态文字"

    monospaced:
      size: 12
      weight: "regular"
      family: "SF Mono"
      usage: "文件路径、代码"
```

### 2.4 间距系统

```yaml
spacing:
  base_unit: 4  # 所有间距为 4 的倍数

  scale:
    xxs: 2
    xs: 4
    sm: 8
    md: 12
    lg: 16
    xl: 24
    xxl: 32

  component_spacing:
    menu_item_padding:
      horizontal: 16
      vertical: 8

    window_padding:
      top: 20
      bottom: 20
      horizontal: 24

    section_spacing: 24
    item_spacing: 12
    label_spacing: 4
```

---

## 三、状态栏组件

### 3.1 状态图标规范

状态栏图标是应用的主要视觉入口，需在 22x22 像素空间内清晰传达系统状态。

```yaml
status_bar:
  dimensions:
    width: 22
    height: 22
    icon_size: 18
    padding: 2

  states:
    - id: "initializing"
      icon: "circle.dotted"
      color: "systemGray"
      animation:
        type: "pulse"
        duration: 1.5
      tooltip: "DMSA 初始化中..."
      accessibility_label: "DMSA 正在初始化"

    - id: "connecting"
      icon: "arrow.triangle.2.circlepath"
      color: "systemGray"
      animation:
        type: "rotate"
        duration: 2.0
      tooltip: "连接服务中..."
      accessibility_label: "DMSA 正在连接后台服务"

    - id: "starting"
      icon: "hourglass"
      color: "systemYellow"
      animation:
        type: "bounce"
        duration: 1.0
      tooltip: "服务启动中 {progress}%"
      accessibility_label: "DMSA 服务正在启动，进度 {progress}%"

    - id: "ready"
      icon: "externaldrive.badge.checkmark"
      color: "systemGreen"
      animation: null
      tooltip: "DMSA 运行中"
      accessibility_label: "DMSA 运行正常"

    - id: "syncing"
      icon: "arrow.clockwise"
      color: "systemBlue"
      animation:
        type: "rotate"
        duration: 1.0
      tooltip: "同步中 {progress}%"
      accessibility_label: "DMSA 正在同步文件，进度 {progress}%"

    - id: "evicting"
      icon: "trash"
      color: "systemBlue"
      animation:
        type: "pulse"
        duration: 1.5
      tooltip: "清理中 {progress}%"
      accessibility_label: "DMSA 正在清理本地缓存"

    - id: "error"
      icon: "exclamationmark.triangle.fill"
      color: "systemRed"
      animation:
        type: "pulse"
        duration: 2.0
        repeat: 3
      tooltip: "发生错误 - 点击查看详情"
      accessibility_label: "DMSA 遇到错误，点击查看详情"

    - id: "serviceUnavailable"
      icon: "xmark.circle.fill"
      color: "systemRed"
      animation: null
      tooltip: "服务不可用"
      accessibility_label: "DMSA 后台服务不可用"
```

### 3.2 状态转换动画

```yaml
status_transitions:
  duration: 0.3
  timing: "easeInOut"

  rules:
    - from: ["initializing", "connecting"]
      to: "ready"
      animation: "fadeScale"
      celebrate: false

    - from: "starting"
      to: "ready"
      animation: "fadeScale"
      celebrate: true  # 短暂高亮

    - from: "ready"
      to: ["syncing", "evicting"]
      animation: "crossFade"

    - from: ["syncing", "evicting"]
      to: "ready"
      animation: "fadeScale"

    - from: "*"
      to: "error"
      animation: "shake"
      shake_count: 2
```

---

## 四、菜单栏设计

### 4.1 菜单结构

```yaml
menu_structure:
  sections:
    - id: "status"
      items:
        - id: "status_display"
          type: "custom_view"
          view: "StatusHeaderView"
          height: 60
          selectable: false
          content:
            - line1: "{状态图标} {状态文字}"
            - line2: "{统计信息} | {最后同步时间}"
          states:
            ready: "运行中 - {totalFiles} 个文件"
            syncing: "同步中... {progress}%"
            error: "错误: {errorMessage}"

    - id: "separator1"
      items: [{ type: "separator" }]

    - id: "actions"
      items:
        - id: "sync_now"
          type: "button"
          title: "立即同步"
          icon: "arrow.clockwise"
          shortcut: "⌘S"
          enabled_states: ["ready"]
          action: "triggerSync"

        - id: "view_conflicts"
          type: "button"
          title: "查看冲突"
          icon: "exclamationmark.2"
          badge: "{conflictCount}"
          badge_visible_when: "conflictCount > 0"
          shortcut: "⌘K"
          enabled_states: ["ready", "syncing"]
          action: "openConflictWindow"

    - id: "separator2"
      items: [{ type: "separator" }]

    - id: "management"
      items:
        - id: "disk_management"
          type: "button"
          title: "磁盘管理"
          icon: "externaldrive"
          shortcut: "⌘D"
          action: "openDiskManagement"

        - id: "settings"
          type: "button"
          title: "设置..."
          icon: "gear"
          shortcut: "⌘,"
          action: "openSettings"

    - id: "separator3"
      items: [{ type: "separator" }]

    - id: "info"
      items:
        - id: "view_logs"
          type: "button"
          title: "查看日志"
          icon: "doc.text"
          action: "openLogs"

        - id: "about"
          type: "button"
          title: "关于 DMSA"
          icon: "info.circle"
          action: "showAbout"

    - id: "separator4"
      items: [{ type: "separator" }]

    - id: "exit"
      items:
        - id: "quit"
          type: "button"
          title: "退出"
          icon: "power"
          shortcut: "⌘Q"
          action: "quitApp"
```

### 4.2 菜单项状态

```yaml
menu_item_states:
  normal:
    text_color: "labelColor"
    icon_color: "secondaryLabelColor"
    background: "transparent"

  hover:
    text_color: "labelColor"
    icon_color: "labelColor"
    background: "selectedContentBackgroundColor"

  disabled:
    text_color: "tertiaryLabelColor"
    icon_color: "tertiaryLabelColor"
    background: "transparent"
    opacity: 0.5

  highlighted:
    text_color: "white"
    icon_color: "white"
    background: "controlAccentColor"
```

### 4.3 状态头部视图

菜单顶部的自定义状态视图提供丰富的状态信息：

```yaml
status_header_view:
  layout:
    padding: { top: 12, bottom: 12, left: 16, right: 16 }
    height: 60

  components:
    icon:
      size: 32
      position: "left"
      margin_right: 12

    content:
      title:
        font: "title3"
        color: "labelColor"
      subtitle:
        font: "caption"
        color: "secondaryLabelColor"
        margin_top: 2

    progress:
      visible_when: "state in [syncing, starting, evicting]"
      type: "linear"
      height: 4
      position: "bottom"
      margin_top: 8
      color: "controlAccentColor"

  content_mapping:
    ready:
      title: "运行中"
      subtitle: "{totalFiles} 个文件 · {localSize} 本地缓存"

    syncing:
      title: "同步中..."
      subtitle: "{currentFile} · {progress}%"
      show_progress: true

    starting:
      title: "启动中..."
      subtitle: "{phase}"
      show_progress: true

    error:
      title: "发生错误"
      subtitle: "{errorMessage}"
      title_color: "systemRed"

    serviceUnavailable:
      title: "服务不可用"
      subtitle: "点击重试连接"
      clickable: true
```

---

## 五、主窗口设计

### 5.1 窗口规范

```yaml
main_window:
  dimensions:
    width: 900
    height: 600
    min_width: 720
    min_height: 480
    resizable: true

  style:
    type: "unified"  # macOS 统一窗口样式
    title_visibility: "hidden"  # 隐藏标题栏文字
    toolbar_style: "unified"
    title: "DMSA"

  layout:
    type: "sidebar_detail"  # 左侧导航 + 右侧内容
    sidebar_width:
      default: 220
      min: 180
      max: 280
    sidebar_resizable: true
```

### 5.2 窗口布局

```yaml
window_layout:
  structure:
    - component: "sidebar"
      position: "left"
      width: 220
      content: "NavigationSidebar"

    - component: "detail"
      position: "right"
      content: "ContentView"  # 根据导航选择动态切换

  divider:
    style: "thin"
    draggable: true
```

---

## 六、左侧导航栏

### 6.1 导航结构

```yaml
navigation_sidebar:
  style:
    background: "sidebarBackgroundColor"
    padding: { top: 12, bottom: 12, horizontal: 0 }

  sections:
    - id: "main"
      title: null  # 无标题的主导航组
      items:
        - id: "dashboard"
          icon: "gauge.with.dots.needle.33percent"
          title: "仪表盘"
          shortcut: "⌘1"
          badge: null

        - id: "sync"
          icon: "arrow.triangle.2.circlepath"
          title: "同步"
          shortcut: "⌘2"
          badge_binding: "sync.isActive ? '进行中' : null"
          badge_color: "systemBlue"

        - id: "conflicts"
          icon: "exclamationmark.2"
          title: "冲突"
          shortcut: "⌘3"
          badge_binding: "conflicts.count > 0 ? conflicts.count : null"
          badge_color: "systemOrange"

        - id: "disks"
          icon: "externaldrive"
          title: "磁盘"
          shortcut: "⌘4"
          badge: null

    - id: "separator1"
      type: "separator"

    - id: "secondary"
      title: null
      items:
        - id: "settings"
          icon: "gear"
          title: "设置"
          shortcut: "⌘,"
          badge: null

        - id: "logs"
          icon: "doc.text"
          title: "日志"
          shortcut: null
          badge: null
```

### 6.2 导航项样式

```yaml
navigation_item:
  layout:
    height: 32
    padding: { horizontal: 12, vertical: 6 }
    icon_size: 18
    icon_margin_right: 10
    corner_radius: 6

  states:
    normal:
      background: "transparent"
      icon_color: "secondaryLabelColor"
      text_color: "labelColor"
      font: "body"

    hover:
      background: "quaternaryLabelColor"
      icon_color: "labelColor"
      text_color: "labelColor"

    selected:
      background: "selectedContentBackgroundColor"
      icon_color: "controlAccentColor"
      text_color: "labelColor"
      font_weight: "medium"

    disabled:
      opacity: 0.4
      background: "transparent"

  badge:
    position: "trailing"
    min_width: 20
    height: 18
    corner_radius: 9
    font: "caption"
    font_weight: "medium"
    padding: { horizontal: 6 }
```

### 6.3 导航状态头部

在导航栏顶部显示当前服务状态：

```yaml
sidebar_header:
  layout:
    height: 60
    padding: { horizontal: 16, vertical: 12 }
    margin_bottom: 8

  components:
    - type: "hstack"
      spacing: 12
      alignment: "center"

      content:
        - type: "status_indicator"
          size: 36
          icon_binding: "uiState.statusIcon"
          color_binding: "uiState.statusColor"
          animation_binding: "uiState.iconAnimation"

        - type: "vstack"
          spacing: 2
          content:
            - type: "text"
              text: "DMSA"
              font: "title3"
              font_weight: "semibold"

            - type: "text"
              text_binding: "uiState.statusText"
              font: "caption"
              color: "secondaryLabelColor"

  status_mapping:
    ready:
      icon: "checkmark.circle.fill"
      color: "systemGreen"
      text: "运行中"

    syncing:
      icon: "arrow.clockwise"
      color: "systemBlue"
      text: "同步中..."
      animation: "rotate"

    error:
      icon: "exclamationmark.triangle.fill"
      color: "systemRed"
      text: "发生错误"

    serviceUnavailable:
      icon: "xmark.circle.fill"
      color: "systemGray"
      text: "服务不可用"
```

---

## 七、仪表盘页面

### 7.1 页面概述

仪表盘是应用的主页面，提供系统状态概览和快速操作入口。

```yaml
dashboard_page:
  layout:
    padding: { top: 24, bottom: 24, horizontal: 32 }
    max_width: 800  # 内容最大宽度

  sections:
    - id: "status_banner"
    - id: "quick_actions"
    - id: "storage_overview"
    - id: "recent_activity"
```

### 7.2 状态横幅

```yaml
status_banner:
  layout:
    padding: { vertical: 20, horizontal: 24 }
    background: "controlBackgroundColor"
    corner_radius: 12
    margin_bottom: 24

  components:
    - type: "hstack"
      spacing: 20
      alignment: "center"

      content:
        - type: "status_ring"
          size: 80
          icon_binding: "uiState.statusIcon"
          color_binding: "uiState.statusColor"
          progress_binding: "sync.isActive ? sync.progress : 1.0"
          animation_binding: "uiState.iconAnimation"

        - type: "vstack"
          spacing: 4
          content:
            - type: "text"
              text_binding: "uiState.statusTitle"
              font: "title1"

            - type: "text"
              text_binding: "uiState.statusSubtitle"
              font: "body"
              color: "secondaryLabelColor"

            - type: "spacer"
              height: 8

            - type: "hstack"
              spacing: 16
              content:
                - type: "stat_chip"
                  icon: "doc"
                  value_binding: "{stats.totalFiles}"
                  label: "文件"

                - type: "stat_chip"
                  icon: "externaldrive"
                  value_binding: "{stats.onlineDisks}/{stats.totalDisks}"
                  label: "磁盘"

                - type: "stat_chip"
                  icon: "clock"
                  value_binding: "stats.lastSyncTime"
                  label: "上次同步"

  status_mapping:
    ready:
      icon: "checkmark.circle.fill"
      color: "systemGreen"
      title: "一切正常"
      subtitle: "所有文件已同步"

    syncing:
      icon: "arrow.clockwise"
      color: "systemBlue"
      title: "正在同步"
      subtitle_binding: "{sync.processedFiles}/{sync.totalFiles} 文件 · {sync.progress}%"

    hasConflicts:
      icon: "exclamationmark.triangle.fill"
      color: "systemOrange"
      title: "有待处理的冲突"
      subtitle_binding: "{conflicts.count} 个文件需要解决"

    error:
      icon: "xmark.circle.fill"
      color: "systemRed"
      title: "发生错误"
      subtitle_binding: "errors.lastError"
```

### 7.3 快速操作

```yaml
quick_actions:
  layout:
    margin_bottom: 24

  components:
    - type: "section_header"
      title: "快速操作"

    - type: "hstack"
      spacing: 12

      content:
        - type: "action_card"
          icon: "arrow.clockwise"
          title: "立即同步"
          shortcut: "⌘S"
          enabled_binding: "!sync.isActive && disks.hasOnline"
          action: "triggerSync"

        - type: "action_card"
          icon: "externaldrive.badge.plus"
          title: "添加磁盘"
          action: "navigateToDisks"

        - type: "action_card"
          icon: "folder"
          title: "打开 Downloads"
          action: "openDownloadsFolder"

  action_card_style:
    layout:
      width: 140
      height: 100
      padding: 16
      corner_radius: 10
      background: "controlBackgroundColor"

    states:
      normal:
        icon_color: "controlAccentColor"
        background: "controlBackgroundColor"
      hover:
        background: "selectedContentBackgroundColor"
      disabled:
        opacity: 0.5
```

### 7.4 存储概览

```yaml
storage_overview:
  layout:
    margin_bottom: 24

  components:
    - type: "section_header"
      title: "存储"

    - type: "hstack"
      spacing: 16

      content:
        - type: "storage_card"
          title: "本地缓存"
          icon: "internaldrive"
          used_binding: "storage.localUsed"
          total_binding: "storage.localTotal"
          color: "systemBlue"

        - type: "storage_card"
          title: "外置磁盘"
          icon: "externaldrive"
          used_binding: "storage.externalUsed"
          total_binding: "storage.externalTotal"
          color: "systemGreen"
          visible_binding: "disks.hasOnline"

  storage_card_style:
    layout:
      flex: 1
      padding: 16
      corner_radius: 10
      background: "controlBackgroundColor"

    components:
      - type: "vstack"
        spacing: 12
        content:
          - type: "hstack"
            content:
              - type: "icon"
                size: 24
              - type: "spacer"
              - type: "text"
                text_binding: "{usedPercent}%"
                font: "title3"

          - type: "progress_bar"
            height: 8
            corner_radius: 4

          - type: "hstack"
            content:
              - type: "text"
                text_binding: "{used} / {total}"
                font: "caption"
                color: "secondaryLabelColor"
```

### 7.5 最近活动

```yaml
recent_activity:
  components:
    - type: "section_header"
      title: "最近活动"
      action:
        title: "查看全部"
        action: "navigateToLogs"

    - type: "activity_list"
      max_items: 5
      empty_state:
        icon: "clock"
        message: "暂无活动记录"

      item_template:
        layout:
          padding: { vertical: 10, horizontal: 12 }
          corner_radius: 8

        components:
          - type: "hstack"
            spacing: 12
            content:
              - type: "activity_icon"
                type_binding: "activity.type"
                size: 28

              - type: "vstack"
                spacing: 2
                content:
                  - type: "text"
                    text_binding: "activity.title"
                    font: "body"

                  - type: "text"
                    text_binding: "activity.subtitle"
                    font: "caption"
                    color: "secondaryLabelColor"

              - type: "spacer"

              - type: "text"
                text_binding: "activity.time"
                font: "caption"
                color: "tertiaryLabelColor"

  activity_types:
    sync_completed:
      icon: "checkmark.circle.fill"
      color: "systemGreen"
    sync_failed:
      icon: "xmark.circle.fill"
      color: "systemRed"
    conflict_detected:
      icon: "exclamationmark.triangle.fill"
      color: "systemOrange"
    disk_connected:
      icon: "externaldrive.badge.plus"
      color: "systemBlue"
    disk_disconnected:
      icon: "externaldrive.badge.minus"
      color: "systemGray"
```

---

## 八、同步详情页面

### 8.1 页面布局

同步页面在主窗口内显示，而非独立窗口。

```yaml
sync_page:
  layout:
    padding: { top: 24, bottom: 24, horizontal: 32 }
    max_width: 700

  sections:
    - id: "sync_status"
    - id: "progress"
    - id: "stats"
    - id: "current_file"
    - id: "errors"
    - id: "history"
```

### 8.2 同步状态头部

```yaml
sync_status_header:
  layout:
    padding: { vertical: 24, horizontal: 24 }
    background: "controlBackgroundColor"
    corner_radius: 12
    margin_bottom: 24

  components:
    - type: "hstack"
      alignment: "center"
      spacing: 20

      content:
        - type: "status_ring"
          size: 100
          icon_binding: "sync.statusIcon"
          color_binding: "sync.statusColor"
          progress_binding: "sync.progress"
          animation_binding: "sync.iconAnimation"

        - type: "vstack"
          spacing: 8
          content:
            - type: "text"
              text_binding: "sync.statusTitle"
              font: "title1"

            - type: "text"
              text_binding: "sync.statusSubtitle"
              font: "body"
              color: "secondaryLabelColor"

            - type: "spacer"
              height: 12

            - type: "hstack"
              spacing: 12
              content:
                - type: "button"
                  title_binding: "sync.isPaused ? '继续' : '暂停'"
                  icon_binding: "sync.isPaused ? 'play.fill' : 'pause.fill'"
                  style: "secondary"
                  visible_when: "sync.isActive"
                  action_binding: "sync.isPaused ? resumeSync : pauseSync"

                - type: "button"
                  title: "取消同步"
                  icon: "xmark"
                  style: "destructive"
                  visible_when: "sync.isActive"
                  action: "cancelSync"

                - type: "button"
                  title: "开始同步"
                  icon: "arrow.clockwise"
                  style: "primary"
                  visible_when: "!sync.isActive"
                  enabled_binding: "disks.hasOnline"
                  action: "startSync"

  status_mapping:
    idle:
      icon: "arrow.clockwise"
      color: "systemGray"
      title: "准备就绪"
      subtitle: "点击开始同步"

    preparing:
      icon: "hourglass"
      color: "systemYellow"
      title: "准备中..."
      subtitle: "扫描文件变更"

    syncing:
      icon: "arrow.clockwise"
      color: "systemBlue"
      title: "同步中"
      subtitle_binding: "{sync.processedFiles}/{sync.totalFiles} 文件"
      animation: "rotate"

    paused:
      icon: "pause.circle.fill"
      color: "systemOrange"
      title: "已暂停"
      subtitle: "点击继续同步"

    completed:
      icon: "checkmark.circle.fill"
      color: "systemGreen"
      title: "同步完成"
      subtitle_binding: "已同步 {sync.totalFiles} 个文件"

    failed:
      icon: "xmark.circle.fill"
      color: "systemRed"
      title: "同步失败"
      subtitle_binding: "{sync.failedFiles} 个文件失败"
```

### 8.3 统计卡片

```yaml
sync_stats_grid:
  layout:
    type: "grid"
    columns: 4
    spacing: 12
    margin_bottom: 24

  items:
    - id: "processed"
      icon: "doc.fill"
      label: "已处理"
      value_binding: "{sync.processedFiles}"
      subtitle_binding: "/ {sync.totalFiles}"
      color: "systemBlue"

    - id: "transferred"
      icon: "arrow.up.arrow.down"
      label: "已传输"
      value_binding: "{sync.transferredSize}"
      subtitle: null
      color: "systemGreen"

    - id: "speed"
      icon: "speedometer"
      label: "速度"
      value_binding: "{sync.speed}/s"
      subtitle: null
      color: "systemOrange"

    - id: "remaining"
      icon: "clock"
      label: "剩余"
      value_binding: "{sync.estimatedTime}"
      subtitle: null
      color: "systemPurple"

  stat_card_style:
    layout:
      padding: 16
      corner_radius: 10
      background: "controlBackgroundColor"

    components:
      - type: "vstack"
        spacing: 8
        content:
          - type: "hstack"
            content:
              - type: "icon"
                size: 20
              - type: "spacer"
          - type: "text"
            font: "title2"
            font_weight: "semibold"
          - type: "text"
            font: "caption"
            color: "secondaryLabelColor"
```

### 8.4 当前文件

```yaml
current_file_section:
  layout:
    margin_bottom: 24
    visible_when: "sync.currentFile != nil"

  components:
    - type: "section_header"
      title: "当前文件"

    - type: "file_card"
      layout:
        padding: 16
        background: "controlBackgroundColor"
        corner_radius: 10

      components:
        - type: "hstack"
          spacing: 12
          content:
            - type: "file_icon"
              extension_binding: "sync.currentFile.extension"
              size: 40

            - type: "vstack"
              spacing: 4
              content:
                - type: "text"
                  text_binding: "sync.currentFile.name"
                  font: "body"
                  font_weight: "medium"

                - type: "text"
                  text_binding: "sync.currentFile.path"
                  font: "caption"
                  color: "secondaryLabelColor"
                  truncation: "head"

            - type: "spacer"

            - type: "vstack"
              alignment: "trailing"
              spacing: 4
              content:
                - type: "text"
                  text_binding: "sync.currentFile.size"
                  font: "callout"

                - type: "text"
                  text_binding: "sync.currentFile.progress"
                  font: "caption"
                  color: "systemBlue"
```

### 8.5 错误列表

```yaml
sync_errors_section:
  layout:
    visible_when: "sync.errors.count > 0"
    margin_bottom: 24

  components:
    - type: "section_header"
      title: "失败的文件"
      badge: "{sync.errors.count}"
      badge_color: "systemRed"
      action:
        title: "重试全部"
        action: "retryAllFailed"

    - type: "error_list"
      max_height: 200
      item_template:
        layout:
          padding: { vertical: 10, horizontal: 12 }
          background: "controlBackgroundColor"
          corner_radius: 8
          margin_bottom: 8

        components:
          - type: "hstack"
            spacing: 10
            content:
              - type: "icon"
                icon: "xmark.circle.fill"
                size: 20
                color: "systemRed"

              - type: "vstack"
                spacing: 2
                content:
                  - type: "text"
                    text_binding: "error.fileName"
                    font: "body"

                  - type: "text"
                    text_binding: "error.reason"
                    font: "caption"
                    color: "systemRed"

              - type: "spacer"

              - type: "button"
                title: "重试"
                style: "inline"
                action: "retryFile"
```

### 8.6 同步历史

```yaml
sync_history_section:
  components:
    - type: "section_header"
      title: "同步历史"

    - type: "history_list"
      max_items: 10
      empty_state:
        icon: "clock"
        message: "暂无同步记录"

      item_template:
        layout:
          padding: { vertical: 12, horizontal: 0 }
          border_bottom: "separatorColor"

        components:
          - type: "hstack"
            spacing: 12
            content:
              - type: "icon"
                icon_binding: "history.statusIcon"
                color_binding: "history.statusColor"
                size: 24

              - type: "vstack"
                spacing: 2
                content:
                  - type: "text"
                    text_binding: "history.title"
                    font: "body"

                  - type: "text"
                    text_binding: "{history.fileCount} 个文件 · {history.size}"
                    font: "caption"
                    color: "secondaryLabelColor"

              - type: "spacer"

              - type: "text"
                text_binding: "history.time"
                font: "caption"
                color: "tertiaryLabelColor"
```

---

## 九、冲突解决页面

### 9.1 页面布局

```yaml
conflicts_page:
  layout:
    padding: { top: 24, bottom: 24, horizontal: 32 }

  sections:
    - id: "header"
    - id: "conflict_list"
```

### 9.2 页面头部

```yaml
conflicts_header:
  layout:
    margin_bottom: 24

  components:
    - type: "hstack"
      alignment: "center"
      content:
        - type: "vstack"
          spacing: 4
          content:
            - type: "text"
              text: "文件冲突"
              font: "title1"

            - type: "text"
              text_binding: "{conflicts.count} 个文件需要解决"
              font: "body"
              color: "secondaryLabelColor"

        - type: "spacer"

        - type: "menu_button"
          title: "全部解决"
          icon: "checkmark.circle"
          enabled_binding: "conflicts.count > 0"
          menu:
            - { title: "保留所有本地版本", action: "resolveAllLocal" }
            - { title: "保留所有外部版本", action: "resolveAllExternal" }
            - { title: "保留所有两者", action: "resolveAllBoth" }

    - type: "spacer"
      height: 16

    - type: "search_field"
      placeholder: "搜索冲突文件..."
      binding: "searchQuery"
```

### 9.3 冲突列表

```yaml
conflicts_list:
  layout:
    type: "list"
    selection: "single"

  empty_state:
    icon: "checkmark.seal.fill"
    icon_color: "systemGreen"
    title: "没有冲突"
    message: "所有文件都已正确同步"

  item_template:
    layout:
      padding: 16
      background: "controlBackgroundColor"
      corner_radius: 10
      margin_bottom: 12

    components:
      - type: "vstack"
        spacing: 12
        content:
          # 文件信息行
          - type: "hstack"
            spacing: 12
            content:
              - type: "file_icon"
                extension_binding: "conflict.extension"
                size: 40

              - type: "vstack"
                spacing: 2
                content:
                  - type: "text"
                    text_binding: "conflict.fileName"
                    font: "body"
                    font_weight: "medium"

                  - type: "text"
                    text_binding: "conflict.relativePath"
                    font: "caption"
                    color: "secondaryLabelColor"
                    truncation: "head"

          # 版本对比行
          - type: "hstack"
            spacing: 16
            content:
              - type: "version_card"
                title: "本地版本"
                icon: "laptopcomputer"
                color: "systemBlue"
                size_binding: "conflict.localSize"
                time_binding: "conflict.localModified"

              - type: "icon"
                icon: "arrow.left.arrow.right"
                size: 16
                color: "tertiaryLabelColor"

              - type: "version_card"
                title: "外部版本"
                icon: "externaldrive"
                color: "systemOrange"
                size_binding: "conflict.externalSize"
                time_binding: "conflict.externalModified"

          # 操作按钮行
          - type: "hstack"
            spacing: 8
            content:
              - type: "button"
                title: "保留本地"
                style: "secondary"
                action: "resolveKeepLocal"

              - type: "button"
                title: "保留外部"
                style: "secondary"
                action: "resolveKeepExternal"

              - type: "button"
                title: "保留两者"
                style: "secondary"
                action: "resolveKeepBoth"

              - type: "spacer"

              - type: "button"
                icon: "ellipsis"
                style: "borderless"
                menu:
                  - { title: "在 Finder 中显示本地文件", action: "revealLocal" }
                  - { title: "在 Finder 中显示外部文件", action: "revealExternal" }
                  - { type: "separator" }
                  - { title: "查看差异", action: "showDiff" }

  version_card_style:
    layout:
      flex: 1
      padding: 12
      corner_radius: 8
      background: "quaternaryLabelColor"

    components:
      - type: "hstack"
        spacing: 8
        content:
          - type: "icon"
            size: 16
          - type: "text"
            font: "caption"
            font_weight: "medium"
      - type: "spacer"
        height: 4
      - type: "text"
        font: "callout"
      - type: "text"
        font: "caption"
        color: "secondaryLabelColor"
```

---

## 十、磁盘管理页面

### 10.1 页面布局

```yaml
disks_page:
  layout:
    type: "master_detail"
    master_width: 240

  sections:
    - id: "disk_list"      # 左侧磁盘列表
    - id: "disk_detail"    # 右侧详情面板
```

### 10.2 磁盘列表

```yaml
disk_list_panel:
  layout:
    padding: { top: 16, bottom: 16, horizontal: 0 }
    background: "windowBackgroundColor"
    border_right: "separatorColor"

  components:
    - type: "header"
      layout:
        padding: { horizontal: 16, bottom: 12 }
      content:
        - type: "hstack"
          content:
            - type: "text"
              text: "磁盘"
              font: "title2"

            - type: "spacer"

            - type: "button"
              icon: "plus"
              style: "borderless"
              tooltip: "添加磁盘"
              action: "showAddDiskSheet"

    - type: "disk_list"
      empty_state:
        icon: "externaldrive.badge.plus"
        message: "点击 + 添加磁盘"

      item_template:
        layout:
          padding: { vertical: 10, horizontal: 16 }
          corner_radius: 8
          margin: { horizontal: 8 }

        states:
          normal:
            background: "transparent"
          hover:
            background: "quaternaryLabelColor"
          selected:
            background: "selectedContentBackgroundColor"

        components:
          - type: "hstack"
            spacing: 10
            content:
              - type: "status_dot"
                size: 8
                color_binding: "disk.isOnline ? systemGreen : systemGray"

              - type: "icon"
                icon: "externaldrive.fill"
                size: 24
                color_binding: "disk.isOnline ? labelColor : tertiaryLabelColor"

              - type: "vstack"
                spacing: 1
                content:
                  - type: "text"
                    text_binding: "disk.name"
                    font: "body"

                  - type: "text"
                    text_binding: "disk.isOnline ? '已连接' : '未连接'"
                    font: "caption"
                    color: "secondaryLabelColor"
```

### 10.3 磁盘详情面板

```yaml
disk_detail_panel:
  layout:
    padding: 32

  empty_state:
    icon: "externaldrive"
    icon_size: 64
    message: "选择一个磁盘查看详情"

  components:
    # 磁盘头部
    - type: "disk_header"
      layout:
        margin_bottom: 32

      components:
        - type: "hstack"
          spacing: 20
          content:
            - type: "disk_icon"
              size: 64
              online_binding: "disk.isOnline"

            - type: "vstack"
              spacing: 6
              content:
                - type: "text"
                  text_binding: "disk.name"
                  font: "largeTitle"

                - type: "badge"
                  text_binding: "disk.isOnline ? '已连接' : '未连接'"
                  color_binding: "disk.isOnline ? systemGreen : systemGray"

                - type: "text"
                  text_binding: "disk.mountPath ?? '—'"
                  font: "caption"
                  color: "secondaryLabelColor"

    # 存储空间
    - type: "section"
      title: "存储空间"
      visible_when: "disk.isOnline"
      margin_bottom: 24

      content:
        - type: "storage_bar"
          height: 24
          corner_radius: 6
          segments:
            - label: "同步文件"
              color: "systemBlue"
              value_binding: "disk.syncFilesSize"
            - label: "其他"
              color: "systemGray"
              value_binding: "disk.otherFilesSize"
            - label: "可用"
              color: "systemGray3"
              value_binding: "disk.freeSpace"

        - type: "spacer"
          height: 12

        - type: "hstack"
          content:
            - type: "text"
              text_binding: "{disk.usedSpace} 已用"
              font: "callout"
            - type: "spacer"
            - type: "text"
              text_binding: "{disk.totalSpace} 总计"
              font: "callout"
              color: "secondaryLabelColor"

    # 磁盘信息
    - type: "section"
      title: "信息"
      margin_bottom: 24

      content:
        - type: "info_grid"
          columns: 2
          row_spacing: 12
          items:
            - { label: "同步目录", value_binding: "disk.externalDir" }
            - { label: "目标目录", value_binding: "disk.targetDir" }
            - { label: "文件数量", value_binding: "{disk.fileCount} 个" }
            - { label: "总大小", value_binding: "disk.totalSize" }
            - { label: "上次同步", value_binding: "disk.lastSyncTime ?? '从未'" }
            - { label: "磁盘格式", value_binding: "disk.fileSystem ?? '—'" }

    # 操作按钮
    - type: "section"
      title: null

      content:
        - type: "hstack"
          spacing: 12
          content:
            - type: "button"
              title: "立即同步"
              icon: "arrow.clockwise"
              style: "primary"
              enabled_binding: "disk.isOnline"
              action: "syncDisk"

            - type: "button"
              title: "编辑"
              icon: "pencil"
              style: "secondary"
              action: "editDisk"

            - type: "spacer"

            - type: "button"
              title: "移除"
              style: "destructive"
              action: "removeDisk"
              confirm:
                title: "移除磁盘配置？"
                message: "这不会删除磁盘上的文件。"
```

### 10.4 添加磁盘弹窗

```yaml
add_disk_sheet:
  style: "sheet"
  width: 480

  components:
    - type: "sheet_header"
      title: "添加磁盘"

    - type: "form"
      padding: 24
      spacing: 20

      fields:
        - id: "disk_picker"
          type: "disk_selector"
          label: "选择磁盘"
          description: "选择要添加的外置磁盘"
          filter: "external_unmounted"
          binding: "newDisk.disk"

        - id: "name"
          type: "text_field"
          label: "显示名称"
          placeholder: "我的备份盘"
          binding: "newDisk.name"
          validation: { required: true, max_length: 50 }

        - id: "sync_dir"
          type: "path_picker"
          label: "同步目录"
          description: "磁盘上存储同步文件的目录"
          mode: "directory"
          base_path_binding: "newDisk.disk.mountPath"
          default_subpath: "Downloads"
          binding: "newDisk.externalDir"

    - type: "sheet_footer"
      content:
        - type: "button"
          title: "取消"
          style: "secondary"
          action: "dismissSheet"

        - type: "button"
          title: "添加"
          style: "primary"
          enabled_binding: "newDisk.isValid"
          action: "addDisk"
```

---

## 十一、设置页面

### 11.1 页面布局

设置页面采用分组列表形式，所有设置项按功能分组展示。

```yaml
settings_page:
  layout:
    padding: { top: 24, bottom: 24, horizontal: 32 }
    max_width: 600

  sections:
    - id: "general"
    - id: "sync"
    - id: "storage"
    - id: "advanced"
```

### 11.2 通用设置

```yaml
general_section:
  title: "通用"
  margin_bottom: 32

  items:
    - id: "launch_at_login"
      type: "toggle_row"
      icon: "power"
      title: "登录时启动"
      description: "开机后自动启动 DMSA"
      binding: "config.launchAtLogin"

    - id: "show_in_dock"
      type: "toggle_row"
      icon: "dock.rectangle"
      title: "在 Dock 中显示"
      description: "关闭后仅在菜单栏显示"
      binding: "config.showInDock"

    - id: "notifications"
      type: "toggle_row"
      icon: "bell"
      title: "启用通知"
      description: "同步完成、错误等事件发送通知"
      binding: "config.enableNotifications"

    - id: "notification_types"
      type: "multi_select_row"
      title: "通知类型"
      enabled_when: "config.enableNotifications"
      options:
        - { id: "sync_complete", label: "同步完成" }
        - { id: "conflict", label: "检测到冲突" }
        - { id: "error", label: "发生错误" }
        - { id: "disk", label: "磁盘连接/断开" }
      binding: "config.notificationTypes"
```

### 11.3 同步设置

```yaml
sync_section:
  title: "同步"
  margin_bottom: 32

  items:
    - id: "sync_interval"
      type: "slider_row"
      icon: "clock"
      title: "自动同步间隔"
      min: 60
      max: 3600
      step: 60
      format: "time"
      binding: "config.syncInterval"

    - id: "sync_on_connect"
      type: "toggle_row"
      icon: "bolt"
      title: "磁盘连接时自动同步"
      description: "外置磁盘插入后立即开始同步"
      binding: "config.syncOnDiskConnect"

    - id: "conflict_strategy"
      type: "picker_row"
      icon: "arrow.triangle.branch"
      title: "冲突处理策略"
      options:
        - { value: "ask", label: "每次询问" }
        - { value: "keep_local", label: "保留本地版本" }
        - { value: "keep_external", label: "保留外部版本" }
        - { value: "keep_both", label: "保留两者" }
      binding: "config.conflictStrategy"

    - id: "exclude_patterns"
      type: "list_row"
      icon: "slash.circle"
      title: "排除文件"
      description: "匹配的文件不会被同步"
      placeholder: "添加排除规则，如 *.tmp"
      binding: "config.excludePatterns"
```

### 11.4 存储设置

```yaml
storage_section:
  title: "存储"
  margin_bottom: 32

  items:
    - id: "storage_info"
      type: "info_card"
      content:
        - type: "hstack"
          spacing: 24
          content:
            - type: "stat_item"
              label: "本地缓存"
              value_binding: "storage.localSize"
            - type: "stat_item"
              label: "可用空间"
              value_binding: "storage.freeSpace"
            - type: "stat_item"
              label: "文件数"
              value_binding: "storage.totalFiles"

    - id: "auto_eviction"
      type: "toggle_row"
      icon: "trash"
      title: "自动清理缓存"
      description: "空间不足时自动清理旧文件"
      binding: "config.autoEviction"

    - id: "eviction_threshold"
      type: "slider_row"
      icon: "chart.bar"
      title: "空间阈值"
      description: "可用空间低于此值时触发清理"
      enabled_when: "config.autoEviction"
      min: 1
      max: 50
      unit: "GB"
      binding: "config.evictionThreshold"

    - id: "keep_days"
      type: "stepper_row"
      icon: "calendar"
      title: "最少保留天数"
      description: "最近访问的文件不会被清理"
      enabled_when: "config.autoEviction"
      min: 1
      max: 30
      unit: "天"
      binding: "config.evictionKeepDays"

    - id: "clear_cache"
      type: "button_row"
      title: "清理所有缓存"
      style: "destructive"
      action: "clearAllCache"
      confirm:
        title: "确认清理缓存？"
        message: "这将删除所有本地缓存文件。"
```

### 11.5 高级设置

```yaml
advanced_section:
  title: "高级"
  margin_bottom: 32

  items:
    - id: "log_level"
      type: "picker_row"
      icon: "doc.text"
      title: "日志级别"
      options:
        - { value: "debug", label: "调试" }
        - { value: "info", label: "信息" }
        - { value: "warn", label: "警告" }
        - { value: "error", label: "仅错误" }
      binding: "config.logLevel"

    - id: "diagnostics"
      type: "info_card"
      title: "诊断信息"
      content:
        - type: "info_grid"
          columns: 2
          items:
            - { label: "App 版本", value_binding: "app.version" }
            - { label: "Service 版本", value_binding: "service.version" }
            - { label: "macFUSE 版本", value_binding: "fuse.version" }
            - { label: "数据库大小", value_binding: "database.size" }

    - id: "maintenance_actions"
      type: "button_group"
      buttons:
        - title: "重建索引"
          icon: "arrow.clockwise"
          action: "rebuildIndex"
          confirm:
            title: "重建索引？"
            message: "这将扫描所有目录并重建文件索引。"

        - title: "导出日志"
          icon: "square.and.arrow.up"
          action: "exportLogs"

        - title: "打开支持文件夹"
          icon: "folder"
          action: "openSupportFolder"

    - id: "reset"
      type: "button_row"
      title: "重置所有设置"
      description: "恢复默认配置，不影响已同步的文件"
      style: "destructive"
      action: "resetConfig"
      confirm:
        title: "重置所有设置？"
        message: "所有设置将恢复为默认值。"
```

### 11.6 设置行组件样式

```yaml
settings_row_styles:
  toggle_row:
    layout:
      padding: { vertical: 12, horizontal: 16 }
      background: "controlBackgroundColor"
      corner_radius: 10
      margin_bottom: 8

    components:
      - type: "hstack"
        spacing: 12
        content:
          - type: "icon_circle"
            size: 32
            icon_size: 16
          - type: "vstack"
            spacing: 2
            content:
              - type: "text"
                font: "body"
              - type: "text"
                font: "caption"
                color: "secondaryLabelColor"
                visible_when: "description != nil"
          - type: "spacer"
          - type: "toggle"

  slider_row:
    layout:
      padding: { vertical: 12, horizontal: 16 }
      background: "controlBackgroundColor"
      corner_radius: 10
      margin_bottom: 8

    components:
      - type: "vstack"
        spacing: 12
        content:
          - type: "hstack"
            content:
              - type: "icon_circle"
                size: 32
              - type: "text"
                font: "body"
              - type: "spacer"
              - type: "text"
                font: "callout"
                color: "controlAccentColor"
          - type: "slider"
            height: 4

  picker_row:
    layout:
      padding: { vertical: 12, horizontal: 16 }
      background: "controlBackgroundColor"
      corner_radius: 10
      margin_bottom: 8

    components:
      - type: "hstack"
        spacing: 12
        content:
          - type: "icon_circle"
            size: 32
          - type: "text"
            font: "body"
          - type: "spacer"
          - type: "popup_button"
            width: 160
```

---

## 十二、弹窗与通知

### 12.1 确认对话框

```yaml
confirmation_dialogs:
  # 通用确认对话框模板
  template:
    width: 300
    style: "alert"

    components:
      - type: "icon"
        icon_binding: "dialog.icon"
        size: 48
        color_binding: "dialog.iconColor"
        alignment: "center"

      - type: "spacer"
        height: 16

      - type: "text"
        text_binding: "dialog.title"
        font: "title2"
        alignment: "center"

      - type: "spacer"
        height: 8

      - type: "text"
        text_binding: "dialog.message"
        font: "body"
        color: "secondaryLabelColor"
        alignment: "center"
        multiline: true

      - type: "spacer"
        height: 20

      - type: "hstack"
        spacing: 12
        alignment: "center"

        content:
          - type: "button"
            title_binding: "dialog.cancelTitle"
            style: "secondary"
            action: "cancel"

          - type: "button"
            title_binding: "dialog.confirmTitle"
            style_binding: "dialog.isDestructive ? 'destructive' : 'primary'"
            action: "confirm"

  # 具体对话框定义
  dialogs:
    quit_with_sync:
      icon: "arrow.clockwise"
      icon_color: "systemBlue"
      title: "同步正在进行中"
      message: "退出将取消当前同步操作。已同步的文件将保留。"
      cancel_title: "取消"
      confirm_title: "退出"
      is_destructive: false
      options:
        - id: "wait"
          title: "等待完成"
          description: "同步完成后自动退出"

    delete_disk:
      icon: "externaldrive.badge.minus"
      icon_color: "systemRed"
      title: "移除磁盘配置?"
      message: "这将停止此磁盘的同步，但不会删除磁盘上的文件。"
      cancel_title: "取消"
      confirm_title: "移除"
      is_destructive: true

    clear_cache:
      icon: "trash"
      icon_color: "systemRed"
      title: "清理所有缓存?"
      message: "这将删除所有本地缓存文件。外置磁盘上的原始文件不受影响。"
      cancel_title: "取消"
      confirm_title: "清理"
      is_destructive: true

    rebuild_index:
      icon: "arrow.clockwise"
      icon_color: "systemOrange"
      title: "重建索引?"
      message: "这将扫描所有同步目录并重建文件索引。此操作可能需要几分钟。"
      cancel_title: "取消"
      confirm_title: "重建"
      is_destructive: false
```

### 12.2 错误弹窗

```yaml
error_alerts:
  styles:
    critical:
      icon: "xmark.octagon.fill"
      icon_color: "systemRed"
      show_help_button: true

    warning:
      icon: "exclamationmark.triangle.fill"
      icon_color: "systemYellow"
      show_help_button: false

    info:
      icon: "info.circle.fill"
      icon_color: "systemBlue"
      show_help_button: false

  templates:
    connection_failed:
      style: "critical"
      title: "无法连接到后台服务"
      message: "DMSA 后台服务未响应。请检查服务是否正在运行。"
      actions:
        - title: "重试"
          action: "retryConnection"
          style: "primary"
        - title: "查看帮助"
          action: "openHelp"
          style: "secondary"
      help_url: "https://help.dmsa.app/connection"

    disk_full:
      style: "critical"
      title: "磁盘空间不足"
      message: "本地磁盘空间不足，无法完成同步。请清理空间或启用自动缓存管理。"
      actions:
        - title: "清理缓存"
          action: "clearCache"
          style: "primary"
        - title: "打开设置"
          action: "openStorageSettings"
          style: "secondary"

    sync_failed:
      style: "warning"
      title: "同步失败"
      message_binding: "{failedCount} 个文件同步失败。"
      actions:
        - title: "查看详情"
          action: "showSyncDetails"
          style: "primary"
        - title: "忽略"
          action: "dismiss"
          style: "secondary"

    permission_denied:
      style: "critical"
      title: "权限不足"
      message: "DMSA 没有访问所需文件的权限。请在系统偏好设置中授予完全磁盘访问权限。"
      actions:
        - title: "打开设置"
          action: "openPermissionSettings"
          style: "primary"
        - title: "稍后"
          action: "dismiss"
          style: "secondary"
```

### 12.3 系统通知

```yaml
system_notifications:
  categories:
    sync:
      identifier: "SYNC_NOTIFICATIONS"
      actions:
        - id: "view"
          title: "查看"
          options: ["foreground"]

    conflict:
      identifier: "CONFLICT_NOTIFICATIONS"
      actions:
        - id: "resolve"
          title: "解决"
          options: ["foreground"]
        - id: "later"
          title: "稍后"
          options: []

    error:
      identifier: "ERROR_NOTIFICATIONS"
      actions:
        - id: "view"
          title: "查看详情"
          options: ["foreground"]

  templates:
    sync_completed:
      category: "sync"
      title: "同步完成"
      body: "已同步 {fileCount} 个文件到 {diskName}"
      sound: "default"
      badge: null

    conflict_detected:
      category: "conflict"
      title: "检测到文件冲突"
      body: "{fileName} 在本地和外部磁盘上都有修改"
      sound: "default"
      badge: "+1"

    disk_disconnected:
      category: "error"
      title: "磁盘已断开"
      body: "{diskName} 已断开连接"
      sound: null
      badge: null

    error_occurred:
      category: "error"
      title: "发生错误"
      body: "{errorMessage}"
      sound: "default"
      badge: null
```

---

## 十三、响应式设计

### 13.1 窗口尺寸适配

```yaml
responsive_design:
  breakpoints:
    compact:
      max_width: 400
    regular:
      min_width: 401
      max_width: 600
    expanded:
      min_width: 601

  settings_window:
    compact:
      layout: "stacked_tabs"
      tab_position: "top"
    regular:
      layout: "sidebar"
      sidebar_width: 150
    expanded:
      layout: "sidebar"
      sidebar_width: 180

  conflict_window:
    compact:
      columns: ["file", "action"]
      hide_columns: ["local_modified", "external_modified"]
    regular:
      columns: "all"

  disk_management:
    compact:
      layout: "list_only"
      detail_style: "navigation"
    regular:
      layout: "master_detail"
      sidebar_width: 200
```

### 13.2 文本截断策略

```yaml
text_truncation:
  file_names:
    max_length: 40
    truncation: "middle"
    tooltip: "full_text"

  file_paths:
    max_length: 60
    truncation: "head"
    tooltip: "full_text"

  error_messages:
    max_lines: 3
    truncation: "tail"
    expandable: true
```

---

## 十四、无障碍设计

### 14.1 VoiceOver 支持

```yaml
accessibility:
  voiceover:
    status_bar:
      label: "DMSA 状态"
      value_binding: "uiState.accessibilityLabel"
      hint: "点击打开菜单"
      traits: ["button"]

    menu_items:
      sync_now:
        label: "立即同步"
        hint: "开始同步文件到外置磁盘"
        traits: ["button"]

      conflict_badge:
        label_binding: "{conflictCount} 个待解决的冲突"

    progress:
      label_binding: "同步进度 {progress} 百分比"
      traits: ["updatesFrequently"]

  reduce_motion:
    enabled_check: "NSReduceMotionEnabled"
    alternatives:
      rotating_icon: "static_icon"
      pulse_animation: "opacity_change"
      slide_transition: "fade_transition"

  increase_contrast:
    enabled_check: "NSIncreaseContrastEnabled"
    adjustments:
      border_width: "+1"
      text_color: "black_or_white"
      separator_opacity: 1.0
```

### 14.2 键盘导航

```yaml
keyboard_navigation:
  global_shortcuts:
    - keys: "⌘,"
      action: "openSettings"
      scope: "app"

    - keys: "⌘S"
      action: "syncNow"
      scope: "menu"

    - keys: "⌘K"
      action: "openConflicts"
      scope: "menu"

    - keys: "⌘D"
      action: "openDiskManagement"
      scope: "menu"

    - keys: "⌘Q"
      action: "quit"
      scope: "app"

  tab_order:
    settings_window:
      - "tab_bar"
      - "form_fields"
      - "action_buttons"

    conflict_window:
      - "search_field"
      - "conflict_list"
      - "resolve_button"

  focus_ring:
    style: "system"
    visible_when: "keyboard_navigation_active"
```

---

## 十五、组件规范

### 15.1 按钮样式

```yaml
button_styles:
  primary:
    background: "controlAccentColor"
    text_color: "white"
    corner_radius: 6
    padding: { horizontal: 16, vertical: 8 }
    font: "body"
    font_weight: "medium"
    min_width: 80

    states:
      normal: {}
      hover:
        background: "controlAccentColor.darker(10%)"
      pressed:
        background: "controlAccentColor.darker(20%)"
      disabled:
        background: "systemGray4"
        text_color: "systemGray"
        opacity: 0.6

  secondary:
    background: "controlBackgroundColor"
    text_color: "labelColor"
    border: "1px solid separatorColor"
    corner_radius: 6
    padding: { horizontal: 16, vertical: 8 }

    states:
      hover:
        background: "controlBackgroundColor.darker(5%)"
      pressed:
        background: "controlBackgroundColor.darker(10%)"

  destructive:
    background: "systemRed"
    text_color: "white"
    corner_radius: 6
    padding: { horizontal: 16, vertical: 8 }

    states:
      hover:
        background: "systemRed.darker(10%)"

  inline:
    background: "transparent"
    text_color: "controlAccentColor"
    padding: { horizontal: 8, vertical: 4 }
    font: "callout"

    states:
      hover:
        background: "controlAccentColor.opacity(0.1)"
```

### 15.2 表单控件

```yaml
form_controls:
  text_field:
    height: 28
    padding: { horizontal: 8, vertical: 4 }
    background: "controlBackgroundColor"
    border: "1px solid separatorColor"
    corner_radius: 4
    font: "body"

    states:
      focused:
        border: "2px solid controlAccentColor"
      error:
        border: "1px solid systemRed"

  toggle:
    width: 42
    height: 24
    animation_duration: 0.2

  slider:
    track_height: 4
    thumb_size: 18
    track_color: "separatorColor"
    fill_color: "controlAccentColor"

  dropdown:
    height: 28
    padding: { horizontal: 8, vertical: 4 }
    arrow_icon: "chevron.down"
    arrow_size: 10

  stepper:
    button_width: 24
    input_width: 60
```

### 15.3 列表样式

```yaml
list_styles:
  standard:
    row_height: 44
    separator: true
    separator_inset: { left: 16 }

  source_list:
    row_height: 32
    separator: false
    selection_style: "rounded"
    padding: { horizontal: 8 }

  grouped:
    section_header_height: 28
    section_header_font: "caption"
    section_header_color: "secondaryLabelColor"
    section_spacing: 16
```

### 15.4 进度指示器

```yaml
progress_indicators:
  linear:
    height: 6
    corner_radius: 3
    background: "separatorColor"
    fill: "controlAccentColor"
    animation: "smooth"

  circular:
    size: { small: 16, medium: 24, large: 32 }
    stroke_width: 2
    animation: "rotate"

  indeterminate:
    type: "bar"
    animation: "shimmer"
    duration: 1.5
```

---

## 附录

### A. 设计检查清单

```yaml
design_checklist:
  visual:
    - "使用系统语义颜色"
    - "适配深色模式"
    - "图标使用 SF Symbols"
    - "间距遵循 4px 网格"
    - "字体使用系统字体"

  interaction:
    - "每个操作有即时反馈"
    - "破坏性操作需确认"
    - "提供键盘快捷键"
    - "长时操作可取消"

  accessibility:
    - "VoiceOver 标签完整"
    - "支持键盘导航"
    - "支持减少动画"
    - "对比度符合 WCAG AA"

  performance:
    - "列表使用虚拟化"
    - "图片延迟加载"
    - "动画使用 GPU 加速"
```

### B. 颜色对照表

| 用途 | 浅色模式 | 深色模式 |
|------|----------|----------|
| 主要文字 | #000000D9 | #FFFFFFD9 |
| 次要文字 | #0000008C | #FFFFFF8C |
| 主色调 | #007AFF | #0A84FF |
| 成功 | #34C759 | #30D158 |
| 警告 | #FF9500 | #FF9F0A |
| 错误 | #FF3B30 | #FF453A |

### C. 图标参考

| 功能 | SF Symbol |
|------|-----------|
| 同步 | arrow.clockwise |
| 设置 | gear |
| 磁盘 | externaldrive |
| 冲突 | exclamationmark.2 |
| 成功 | checkmark.circle.fill |
| 错误 | xmark.circle.fill |
| 添加 | plus |
| 删除 | trash |

---

*文档版本: 2.0 | 最后更新: 2026-01-27*
