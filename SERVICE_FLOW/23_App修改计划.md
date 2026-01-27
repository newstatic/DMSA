# DMSA App 修改计划

> 版本: 1.0 | 创建日期: 2026-01-27
>
> 返回 [目录](00_README.md) | 上一节: [22_UI修改计划](22_UI修改计划.md)
>
> 本文档基于 `20_App启动与交互流程.md` 和 `22_UI修改计划.md` 的代码审查结果生成

---

## 一、代码审查总结

### 1.1 当前架构状态

**已完成的 UI 修改:**
- MainView.swift: 6 个导航标签页已实现 (dashboard, sync, conflicts, disks, settings, logs)
- 新组件已创建: StatusRing, ActionCard, StatCard, ActivityRow, ConflictCard
- 新页面已创建: SyncPage, ConflictsPage, DisksPage, SettingsPage
- MenuBarManager: 已添加 `menuBarDidRequestOpenTab` 委托方法

**当前 App 架构:**
```
AppDelegate
├── menuBarManager (MenuBarManager)
├── diskManager (DiskManager.shared)
├── alertManager (AlertManager.shared)
├── serviceClient (ServiceClient.shared)
├── serviceInstaller (ServiceInstaller.shared)
└── mainWindowController (MainWindowController)
```

### 1.2 与设计规范差异

| 设计规范要求 | 当前实现 | 状态 |
|-------------|---------|------|
| AppCoordinator 协调器 | 无，直接在 AppDelegate 中处理 | **待实现** |
| StateManager 状态管理 | AppUIState (简化版) | **需增强** |
| NotificationHandler | 在 ServiceClient 中处理 | **需分离** |
| 连接状态机管理 | 简单的重试逻辑 | **需增强** |
| 错误处理与恢复机制 | 基础错误提示 | **需完善** |
| 后台/前台切换处理 | 缺失 | **待实现** |

### 1.3 关键差异分析

**1. 缺少 AppCoordinator**
```
设计规范:
AppDelegate → AppCoordinator → [ServiceClient, StateManager, MenuBarController]

当前实现:
AppDelegate → 直接管理所有组件
```

**2. 状态管理不完整**
```
设计规范 (StateManager):
- connectionState: ConnectionState
- serviceState: ServiceState
- componentStates: [String: ComponentState]
- uiState: UIState
- syncPairs: [SyncPairConfig]
- disks: [DiskConfig]
- indexProgress: IndexProgress?
- syncProgress: SyncProgress?
- lastError: AppError?
- pendingConflicts: Int
- statistics: AppStatistics?

当前实现 (AppUIState):
- syncStatus: SyncUIStatus
- conflictCount: Int
- isSyncing: Bool
- syncProgress: Double
- lastSyncTime: Date?
- connectedDiskCount: Int
- totalDiskCount: Int
- totalFiles: Int
```

**3. 缺少通知处理器**
```
设计规范:
NotificationHandler 负责:
- handleStateChanged
- handleIndexProgress
- handleSyncCompleted
- handleConflictDetected
- handleComponentError

当前实现:
ServiceClient.progressDelegate 处理所有通知
```

**4. MenuBarDelegate 不完整**
```
设计规范要求:
- menuBarDidRequestOpenTab (已实现)
- 但 AppDelegate 未实现此方法

当前实现:
extension AppDelegate: MenuBarDelegate {
    func menuBarDidRequestSync()
    func menuBarDidRequestSettings()
    func menuBarDidRequestToggleAutoSync()
    // 缺少: menuBarDidRequestOpenTab
}
```

---

## 二、修改计划概览

### 2.1 分阶段实施

```
Phase 1: 基础架构补全 (核心组件)
    ↓
Phase 2: 状态管理增强 (StateManager)
    ↓
Phase 3: 通知处理分离 (NotificationHandler)
    ↓
Phase 4: 生命周期完善 (后台/前台切换)
    ↓
Phase 5: 错误处理增强 (ErrorHandler)
```

### 2.2 优先级分配

| 优先级 | 内容 | 预计改动 | 影响范围 |
|-------|------|---------|---------|
| P0 | AppDelegate 补全 MenuBarDelegate | AppDelegate.swift | 低 |
| P0 | AppUIState 与 Service 状态同步 | MainView.swift, AppUIState | 中 |
| P1 | 创建 StateManager | 新建 StateManager.swift | 高 |
| P1 | MenuBarManager 与 AppUIState 集成 | MenuBarManager.swift | 中 |
| P2 | 创建 NotificationHandler | 新建 NotificationHandler.swift | 中 |
| P2 | 生命周期回调实现 | AppDelegate.swift | 中 |
| P3 | 创建 ErrorHandler | 新建 ErrorHandler.swift | 中 |
| P3 | 连接状态机增强 | ServiceClient.swift | 高 |
| P4 | 创建 AppCoordinator (可选) | 新建 AppCoordinator.swift | 高 |

---

## 三、Phase 0: 紧急修复

### 3.1 AppDelegate 补全 MenuBarDelegate

**问题:** MenuBarDelegate 协议已添加 `menuBarDidRequestOpenTab` 方法，但 AppDelegate 未实现。

**修改文件:** `AppDelegate.swift`

```swift
// 在 extension AppDelegate: MenuBarDelegate 中添加:
func menuBarDidRequestOpenTab(_ tab: MainView.MainTab) {
    mainWindowController?.showTab(tab)
}
```

### 3.2 AppUIState 状态同步

**问题:** AppUIState 与 Service 状态不同步，导致 UI 显示不准确。

**修改文件:** `MainView.swift`

```yaml
changes:
  - id: "state_sync_on_appear"
    description: "在 MainView 出现时同步状态"
    details:
      - 添加 .onAppear 调用状态同步
      - 设置定时刷新 (可选)

  - id: "state_binding_service"
    description: "绑定 ServiceClient 通知"
    details:
      - 让 AppUIState 实现 SyncProgressDelegate
      - 更新相关状态字段
```

**代码示例:**
```swift
// AppUIState 扩展
extension AppUIState: SyncProgressDelegate {
    func syncProgressDidUpdate(_ progress: SyncProgressData) {
        Task { @MainActor in
            self.isSyncing = progress.status == .syncing
            self.syncProgress = Double(progress.processedFiles) / Double(max(1, progress.totalFiles))
            // 更新其他字段...
        }
    }

    func syncStatusDidChange(syncPairId: String, status: SyncStatus, message: String?) {
        Task { @MainActor in
            switch status {
            case .idle:
                self.syncStatus = .ready
            case .syncing:
                self.syncStatus = .syncing
            case .paused:
                self.syncStatus = .paused
            case .error:
                self.syncStatus = .error(message ?? "同步错误")
            default:
                break
            }
        }
    }

    func serviceDidBecomeReady() {
        Task { @MainActor in
            self.syncStatus = .ready
        }
    }

    func configDidUpdate() {
        // 重新加载配置
    }
}
```

---

## 四、Phase 1: 状态管理增强

### 4.1 创建 StateManager

**新建文件:** `Services/StateManager.swift`

**职责:**
- 管理 App 全局状态
- 桥接 ServiceClient 通知到 UI
- 提供状态变化订阅机制

**结构:**
```swift
@MainActor
final class StateManager: ObservableObject {
    static let shared = StateManager()

    // MARK: - 连接状态
    @Published var connectionState: ConnectionState = .disconnected

    // MARK: - Service 状态
    @Published var serviceState: ServiceState = .unknown
    @Published var componentStates: [String: ComponentState] = [:]

    // MARK: - UI 状态
    @Published var uiState: UIState = .initializing

    // MARK: - 数据状态
    @Published var syncPairs: [SyncPairConfig] = []
    @Published var disks: [DiskConfig] = []

    // MARK: - 进度状态
    @Published var indexProgress: IndexProgress?
    @Published var syncProgress: SyncProgress?

    // MARK: - 错误状态
    @Published var lastError: AppError?
    @Published var pendingConflicts: Int = 0

    // MARK: - 统计
    @Published var statistics: AppStatistics?

    // MARK: - 状态计算属性
    var isReady: Bool {
        connectionState == .connected && serviceState == .running
    }

    var canSync: Bool {
        isReady && !disks.filter { $0.isConnected }.isEmpty
    }

    // MARK: - 状态更新方法
    func updateFromService(_ fullState: ServiceFullState) { ... }
    func handleNotification(_ type: NotificationType, data: Data) { ... }
}
```

### 4.2 状态枚举定义

**新建文件:** `Models/AppStates.swift`

```swift
// 连接状态
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case interrupted
    case failed(String)
}

// 服务状态
enum ServiceState: String, Codable {
    case unknown
    case starting
    case indexing
    case ready
    case running
    case stopping
    case error
}

// UI 状态
enum UIState: Equatable {
    case initializing
    case connecting
    case starting(progress: Double, phase: String)
    case ready
    case syncing(progress: SyncProgress)
    case evicting(progress: EvictionProgress)
    case error(AppError)
    case serviceUnavailable
}

// 组件状态
struct ComponentState: Codable {
    var name: String
    var status: String
    var lastUpdate: Date
    var errorMessage: String?
}

// 应用错误
struct AppError: Error, Equatable {
    var code: Int
    var message: String
    var severity: ErrorSeverity
    var isRecoverable: Bool
    var recoveryAction: String?
}

enum ErrorSeverity {
    case info
    case warning
    case critical
}
```

### 4.3 迁移 AppUIState 到 StateManager

**修改文件:** `MainView.swift`

```yaml
changes:
  - id: "replace_appuistate"
    description: "用 StateManager 替换 AppUIState"
    details:
      - 修改 MainView 使用 StateManager.shared
      - 更新所有绑定引用
      - 保留 AppUIState 作为兼容层 (可选)
```

---

## 五、Phase 2: 通知处理分离

### 5.1 创建 NotificationHandler

**新建文件:** `Services/NotificationHandler.swift`

**职责:**
- 处理所有 Service 通知
- 解析通知数据
- 分发到 StateManager
- 触发系统通知

**结构:**
```swift
@MainActor
final class NotificationHandler {
    private let stateManager: StateManager
    private let userNotificationCenter = UNUserNotificationCenter.current()

    init(stateManager: StateManager) {
        self.stateManager = stateManager
    }

    // MARK: - 通知处理
    func handleNotification(_ type: NotificationType, data: Data) {
        switch type {
        case .stateChanged:
            handleStateChanged(data)
        case .indexProgress:
            handleIndexProgress(data)
        case .indexReady:
            handleIndexReady(data)
        case .syncProgress:
            handleSyncProgress(data)
        case .syncCompleted:
            handleSyncCompleted(data)
        case .conflictDetected:
            handleConflictDetected(data)
        case .evictionProgress:
            handleEvictionProgress(data)
        case .componentError:
            handleComponentError(data)
        case .diskChanged:
            handleDiskChanged(data)
        }
    }

    // MARK: - 系统通知
    private func sendUserNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        userNotificationCenter.add(request)
    }
}
```

### 5.2 修改 ServiceClient

**修改文件:** `Services/ServiceClient.swift`

```yaml
changes:
  - id: "notification_delegation"
    description: "将通知处理委托给 NotificationHandler"
    details:
      - 修改 handleSyncProgress 等方法
      - 调用 NotificationHandler.handleNotification
      - 移除 progressDelegate (改用 NotificationHandler)
```

---

## 六、Phase 3: 生命周期完善

### 6.1 后台/前台切换处理

**修改文件:** `AppDelegate.swift`

```swift
// 添加生命周期回调
func applicationDidResignActive(_ notification: Notification) {
    Logger.shared.debug("App entering background")

    // 保存状态
    stateManager.saveToCache()

    // 暂停刷新定时器
    refreshTimer?.invalidate()
}

func applicationDidBecomeActive(_ notification: Notification) {
    Logger.shared.debug("App becoming active")

    // 同步状态
    Task {
        await syncState()
    }

    // 恢复刷新定时器
    startRefreshTimer()
}

func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    if !hasVisibleWindows {
        mainWindowController?.showWindow()
    }
    return true
}
```

### 6.2 退出流程完善

**修改文件:** `AppDelegate.swift`

```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // 检查是否有进行中的操作
    if stateManager.isSyncing {
        showTerminationConfirmation { response in
            switch response {
            case .cancel:
                break
            case .waitAndQuit:
                self.waitForSyncAndQuit()
            case .forceQuit:
                self.forceQuit()
            }
        }
        return .terminateCancel
    }

    return .terminateNow
}

private func showTerminationConfirmation(completion: @escaping (TerminationResponse) -> Void) {
    let alert = NSAlert()
    alert.messageText = "同步正在进行中"
    alert.informativeText = "是否等待同步完成后退出？"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "等待完成")
    alert.addButton(withTitle: "立即退出")
    alert.addButton(withTitle: "取消")

    let response = alert.runModal()
    switch response {
    case .alertFirstButtonReturn:
        completion(.waitAndQuit)
    case .alertSecondButtonReturn:
        completion(.forceQuit)
    default:
        completion(.cancel)
    }
}
```

---

## 七、Phase 4: 错误处理增强

### 7.1 创建 ErrorHandler

**新建文件:** `Services/ErrorHandler.swift`

**职责:**
- 错误分类与处理
- 自动恢复尝试
- 用户提示与引导

**结构:**
```swift
@MainActor
final class ErrorHandler {
    private let stateManager: StateManager

    init(stateManager: StateManager) {
        self.stateManager = stateManager
    }

    func handle(_ error: AppError) {
        // 记录日志
        Logger.shared.error("Error occurred: \(error)")

        // 更新状态
        stateManager.lastError = error

        // 根据严重程度处理
        switch error.severity {
        case .critical:
            showCriticalErrorAlert(error)
        case .warning:
            showWarningNotification(error)
        case .info:
            // 仅记录，不显示
            break
        }

        // 尝试自动恢复
        if error.isRecoverable {
            attemptAutoRecovery(error)
        }
    }

    private func attemptAutoRecovery(_ error: AppError) {
        Task {
            // 根据错误类型执行恢复
            switch error.code {
            case 1001: // 连接错误
                try? await reconnect()
            case 2001: // 同步错误
                // 等待后重试
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                // retry sync
            default:
                break
            }
        }
    }
}
```

### 7.2 错误码定义

**新建文件:** `Models/ErrorCodes.swift`

```swift
struct ErrorCodes {
    // 连接错误 (1xxx)
    static let connectionFailed = 1001
    static let connectionInterrupted = 1002
    static let connectionTimeout = 1003

    // 同步错误 (2xxx)
    static let syncFailed = 2001
    static let syncConflict = 2002
    static let syncTimeout = 2003

    // 配置错误 (3xxx)
    static let configInvalid = 3001
    static let configSaveFailed = 3002

    // 磁盘错误 (4xxx)
    static let diskNotFound = 4001
    static let diskAccessDenied = 4002
    static let diskFull = 4003

    // 权限错误 (5xxx)
    static let permissionDenied = 5001
    static let serviceNotAuthorized = 5002
}
```

---

## 八、Phase 5: 连接状态机增强 (可选)

### 8.1 连接状态机

**修改文件:** `Services/ServiceClient.swift`

```swift
// 添加连接状态机
actor XPCConnectionManager {
    private var connection: NSXPCConnection?
    private var state: ConnectionState = .disconnected
    private var retryCount = 0
    private let maxRetries = 3
    private let retryDelays: [TimeInterval] = [1, 2, 5] // 递增延迟

    func connect() async throws -> DMSAServiceProtocol {
        switch state {
        case .connected:
            guard let proxy = connection?.remoteObjectProxy as? DMSAServiceProtocol else {
                throw ConnectionError.invalidProxy
            }
            return proxy

        case .connecting:
            // 等待现有连接
            return try await waitForConnection()

        case .disconnected, .failed, .interrupted:
            return try await establishConnection()
        }
    }

    private func handleInterruption() {
        state = .interrupted

        // 自动重连
        Task {
            for i in 0..<maxRetries {
                try? await Task.sleep(nanoseconds: UInt64(retryDelays[min(i, retryDelays.count - 1)] * 1_000_000_000))

                do {
                    _ = try await establishConnection()
                    return
                } catch {
                    Logger.shared.warning("Reconnect attempt \(i + 1) failed")
                }
            }

            state = .failed("Max retries exceeded")
        }
    }
}
```

---

## 九、文件变更清单

### 9.1 新建文件

```
Services/
├── StateManager.swift          # 状态管理器
├── NotificationHandler.swift   # 通知处理器
├── ErrorHandler.swift          # 错误处理器
└── AppCoordinator.swift        # 应用协调器 (可选)

Models/
├── AppStates.swift             # 状态枚举定义
└── ErrorCodes.swift            # 错误码定义
```

### 9.2 修改文件

```
App/AppDelegate.swift           # 生命周期、MenuBarDelegate
Services/ServiceClient.swift    # 连接状态机、通知委托
UI/Views/MainView.swift         # 状态绑定
UI/MenuBarManager.swift         # 状态同步
```

### 9.3 可删除文件

```
(暂无，等新架构稳定后再清理)
```

---

## 十、实施顺序

### 10.1 推荐顺序

```
Step 1: Phase 0 (紧急修复)
├── 修复 AppDelegate.menuBarDidRequestOpenTab
└── 测试菜单栏导航功能

Step 2: Phase 1 (状态管理)
├── 创建 AppStates.swift
├── 创建 StateManager.swift
├── 修改 MainView 使用 StateManager
└── 测试状态同步

Step 3: Phase 2 (通知处理)
├── 创建 NotificationHandler.swift
├── 修改 ServiceClient 通知委托
└── 测试通知流程

Step 4: Phase 3 (生命周期)
├── 添加后台/前台切换处理
├── 添加退出确认流程
└── 测试生命周期

Step 5: Phase 4 (错误处理)
├── 创建 ErrorCodes.swift
├── 创建 ErrorHandler.swift
└── 测试错误恢复

Step 6: Phase 5 (连接增强) - 可选
├── 实现连接状态机
└── 测试重连机制
```

### 10.2 依赖关系

```
AppStates.swift ─────────────────────┐
                                     │
                                     ▼
StateManager.swift ◄──────── NotificationHandler.swift
      │                              │
      │                              │
      ▼                              ▼
MainView.swift                ServiceClient.swift
      │                              │
      │                              │
      ▼                              ▼
MenuBarManager.swift          ErrorHandler.swift
      │
      │
      ▼
AppDelegate.swift
```

---

## 十一、验收标准

### 11.1 功能验收

- [ ] 菜单栏点击 "打开仪表盘/磁盘/冲突" 正常跳转
- [ ] 状态栏图标根据 Service 状态正确变化
- [ ] 同步进度实时更新到 UI
- [ ] 磁盘连接/断开正确更新状态
- [ ] 后台切换后前台恢复状态正确
- [ ] 退出时有进行中操作正确提示
- [ ] 错误发生时有正确提示和恢复选项

### 11.2 代码质量验收

- [ ] 所有新代码遵循 Swift 编码规范
- [ ] 关键方法有文档注释
- [ ] 无循环引用和内存泄漏
- [ ] 所有 @MainActor 标注正确
- [ ] 无强制解包 (除非有充分理由)

### 11.3 性能验收

- [ ] 状态更新延迟 < 100ms
- [ ] 无 UI 卡顿
- [ ] 内存占用稳定

---

## 十二、附录

### A. 当前代码问题清单

| 问题 | 位置 | 严重程度 | 修复阶段 |
|------|------|----------|----------|
| menuBarDidRequestOpenTab 未实现 | AppDelegate.swift:357-372 | 高 | Phase 0 |
| AppUIState 不完整 | MainView.swift:6-55 | 中 | Phase 1 |
| 通知处理散落在 ServiceClient | ServiceClient.swift:145-224 | 中 | Phase 2 |
| 缺少后台/前台切换处理 | AppDelegate.swift | 中 | Phase 3 |
| 错误只是简单弹窗 | AppDelegate.swift:246-265 | 低 | Phase 4 |
| 连接重试逻辑简单 | ServiceClient.swift:339-364 | 低 | Phase 5 |

### B. 设计规范参考

- 20_App启动与交互流程.md: 架构设计
- 21_UI设计规范.md: UI 组件规范
- 22_UI修改计划.md: UI 修改清单

---

*文档版本: 1.0 | 最后更新: 2026-01-27*
