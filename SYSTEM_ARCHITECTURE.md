# DMSA 系统架构设计 v4.0

> 版本: 4.0 | 更新日期: 2026-01-24
> 基于最佳架构原则重新设计

---

## 目录

1. [设计原则](#1-设计原则)
2. [架构概览](#2-架构概览)
3. [进程架构](#3-进程架构)
4. [服务层设计](#4-服务层设计)
5. [通信机制](#5-通信机制)
6. [安全模型](#6-安全模型)
7. [数据流设计](#7-数据流设计)
8. [部署架构](#8-部署架构)
9. [故障恢复](#9-故障恢复)
10. [迁移路径](#10-迁移路径)

---

## 1. 设计原则

### 1.1 核心原则

| 原则 | 说明 | 实现方式 |
|------|------|----------|
| **关注点分离** | 不同功能运行在不同进程 | GUI/VFS/Sync/Helper 四进程架构 |
| **最小权限** | 每个组件只拥有必要权限 | LaunchDaemon 以 root 运行，GUI 以用户权限运行 |
| **服务化** | 核心功能作为系统服务运行 | VFS 和 Sync 作为 LaunchDaemon |
| **故障隔离** | 单个组件崩溃不影响其他 | 进程间通过 XPC 松耦合 |
| **持久运行** | 核心服务独立于 GUI 生命周期 | LaunchDaemon 开机自启 |

### 1.2 旧架构问题

```
旧架构 (v3.x):
┌─────────────────────────────────────────────────┐
│              DMSA.app (单体应用)                  │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌───────┐ │
│  │   GUI   │ │   VFS   │ │  Sync   │ │Helper │ │
│  │         │ │  (FUSE) │ │ Engine  │ │Client │ │
│  └─────────┘ └─────────┘ └─────────┘ └───────┘ │
└─────────────────────────────────────────────────┘
                     │
              XPC 通信 (特权操作)
                     ▼
┌─────────────────────────────────────────────────┐
│        com.ttttt.dmsa.helper (LaunchDaemon)     │
│              仅用于目录保护                        │
└─────────────────────────────────────────────────┘

问题:
1. GUI 退出 → VFS 卸载 → 用户文件不可访问
2. GUI 崩溃 → 所有功能停止
3. VFS 在用户态运行，权限受限
4. 同步引擎与 GUI 耦合，无法后台持续运行
5. Helper 功能单一，仅用于目录保护
```

### 1.3 新架构目标

```
新架构 (v4.0):

优势:
1. GUI 退出 → VFS/Sync 继续运行 → 文件始终可访问
2. 任意组件崩溃 → 其他组件不受影响
3. VFS 作为系统服务，可使用 root 权限挂载
4. 同步服务独立运行，支持后台持续同步
5. 统一的系统服务架构，更易于维护
```

---

## 2. 架构概览

### 2.1 四进程架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                         用户态 (User Space)                          │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    DMSA.app (菜单栏应用)                        │  │
│  │                       普通用户权限                              │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────┐   │  │
│  │  │   GUI   │  │Settings │  │ Status  │  │  XPC Clients    │   │  │
│  │  │ Manager │  │  View   │  │ Display │  │ (VFS/Sync/Help) │   │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                    │                                 │
│                            XPC 通信 │                                 │
│                                    ▼                                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                       系统态 (System Space)                          │
│                        LaunchDaemons (root)                         │
│                                                                      │
│  ┌───────────────────┐  ┌───────────────────┐  ┌─────────────────┐  │
│  │ com.ttttt.dmsa.   │  │ com.ttttt.dmsa.   │  │ com.ttttt.dmsa. │  │
│  │     vfs           │  │     sync          │  │     helper      │  │
│  │                   │  │                   │  │                 │  │
│  │  • FUSE 挂载管理   │  │  • 文件同步引擎   │  │  • 目录保护      │  │
│  │  • 智能合并       │  │  • 定时调度       │  │  • ACL 管理      │  │
│  │  • 读写路由       │  │  • 冲突解决       │  │  • 权限控制      │  │
│  │  • 访问控制       │  │  • 断点续传       │  │                 │  │
│  └───────────────────┘  └───────────────────┘  └─────────────────┘  │
│           │                      │                      │           │
│           └──────────────────────┼──────────────────────┘           │
│                                  │                                   │
│                           XPC 服务间通信                              │
│                                  │                                   │
│                                  ▼                                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                     共享数据层                                  │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐    │  │
│  │  │  ObjectBox  │  │ Config.json │  │ ~/Downloads_Local/  │    │  │
│  │  │  数据库      │  │  配置文件    │  │   .FUSE/db.json    │    │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        内核态 (Kernel Space)                         │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                     macFUSE 内核扩展                            │  │
│  │                  (或 FUSE-T NFS 服务)                           │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 组件职责

| 组件 | 进程标识 | 权限 | 职责 |
|------|----------|------|------|
| **DMSA.app** | 主应用 | 用户 | GUI、状态显示、配置管理、用户交互 |
| **VFS Service** | `com.ttttt.dmsa.vfs` | root | FUSE 挂载、读写路由、智能合并、访问控制 |
| **Sync Service** | `com.ttttt.dmsa.sync` | root | 文件同步、定时调度、冲突解决、断点续传 |
| **Helper Service** | `com.ttttt.dmsa.helper` | root | 目录保护、ACL 管理、权限修改 |

---

## 3. 进程架构

### 3.1 DMSA.app (GUI 进程)

```swift
// 主应用架构
DMSA.app/
├── App/
│   ├── AppDelegate.swift          // 应用生命周期
│   └── main.swift                 // 入口点
├── UI/
│   ├── MenuBarManager.swift       // 菜单栏管理
│   ├── Views/                     // SwiftUI 视图
│   │   ├── MainView.swift
│   │   ├── Settings/
│   │   ├── History/
│   │   └── ...
│   └── Components/                // UI 组件
├── XPCClients/
│   ├── VFSClient.swift            // VFS 服务客户端
│   ├── SyncClient.swift           // Sync 服务客户端
│   └── HelperClient.swift         // Helper 服务客户端
├── Models/
│   ├── AppConfig.swift            // 配置模型
│   └── ViewModels/                // 视图模型
└── Services/
    ├── ConfigManager.swift        // 配置管理 (读写配置文件)
    └── NotificationManager.swift  // 通知管理
```

**特点:**
- 轻量级 GUI 进程
- 仅负责用户交互和状态显示
- 通过 XPC 与系统服务通信
- 可安全退出，不影响核心功能

### 3.2 VFS Service (虚拟文件系统服务)

```swift
// VFS 服务架构
com.ttttt.dmsa.vfs/
├── main.swift                     // XPC 服务入口
├── VFSServiceProtocol.swift       // XPC 协议定义
├── VFSServiceDelegate.swift       // XPC 委托实现
├── Core/
│   ├── VFSCore.swift              // FUSE 操作入口
│   ├── MergeEngine.swift          // 智能合并引擎
│   ├── ReadRouter.swift           // 读取路由
│   ├── WriteRouter.swift          // 写入路由
│   └── DeleteRouter.swift         // 删除路由
├── FUSE/
│   ├── FUSEManager.swift          // macFUSE 管理
│   └── DMSAFileSystem.swift       // FUSE 回调实现
├── Storage/
│   ├── FileEntryStore.swift       // 文件索引存储
│   └── TreeVersionManager.swift   // 版本管理
└── Security/
    └── AccessController.swift     // 访问控制
```

**LaunchDaemon 配置 (`/Library/LaunchDaemons/com.ttttt.dmsa.vfs.plist`):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ttttt.dmsa.vfs</string>
    <key>BundleIdentifier</key>
    <string>com.ttttt.dmsa.vfs</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/com.ttttt.dmsa.vfs</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>com.ttttt.dmsa.vfs</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>UserName</key>
    <string>root</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
```

### 3.3 Sync Service (同步服务)

```swift
// Sync 服务架构
com.ttttt.dmsa.sync/
├── main.swift                     // XPC 服务入口
├── SyncServiceProtocol.swift      // XPC 协议定义
├── SyncServiceDelegate.swift      // XPC 委托实现
├── Engine/
│   ├── NativeSyncEngine.swift     // 同步引擎核心
│   ├── FileScanner.swift          // 文件扫描器
│   ├── DiffEngine.swift           // 差异计算引擎
│   ├── FileCopier.swift           // 文件复制器
│   └── ConflictResolver.swift     // 冲突解决器
├── Scheduler/
│   ├── SyncScheduler.swift        // 同步调度器
│   ├── DirtyQueue.swift           // 脏数据队列
│   └── TimerManager.swift         // 定时器管理
├── Storage/
│   ├── SyncStateManager.swift     // 同步状态管理
│   └── HistoryRecorder.swift      // 历史记录
└── Monitor/
    ├── DiskMonitor.swift          // 硬盘监控
    └── FSEventsMonitor.swift      // 文件系统事件监控
```

**LaunchDaemon 配置 (`/Library/LaunchDaemons/com.ttttt.dmsa.sync.plist`):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ttttt.dmsa.sync</string>
    <key>BundleIdentifier</key>
    <string>com.ttttt.dmsa.sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/com.ttttt.dmsa.sync</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>com.ttttt.dmsa.sync</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>UserName</key>
    <string>root</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
```

### 3.4 Helper Service (特权助手服务)

保持现有设计，专注于目录保护操作:

```swift
// Helper 服务架构
com.ttttt.dmsa.helper/
├── main.swift                     // XPC 服务入口
├── HelperProtocol.swift           // XPC 协议定义
├── HelperTool.swift               // 实现
└── Security/
    └── PathValidator.swift        // 路径安全验证
```

---

## 4. 服务层设计

### 4.1 VFS 服务协议

```swift
/// VFS 服务 XPC 协议
@objc public protocol VFSServiceProtocol {

    // MARK: - 挂载管理

    /// 挂载 VFS
    /// - Parameters:
    ///   - syncPairId: 同步对 ID
    ///   - localDir: 本地目录路径
    ///   - externalDir: 外部目录路径
    ///   - targetDir: 挂载点路径
    func mount(syncPairId: String,
               localDir: String,
               externalDir: String,
               targetDir: String,
               withReply reply: @escaping (Bool, String?) -> Void)

    /// 卸载 VFS
    func unmount(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void)

    /// 获取挂载状态
    func getMountStatus(syncPairId: String,
                        withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 状态查询

    /// 获取所有挂载点状态
    func getAllMounts(withReply reply: @escaping ([[String: Any]]) -> Void)

    /// 获取文件状态
    func getFileStatus(virtualPath: String,
                       syncPairId: String,
                       withReply reply: @escaping ([String: Any]?) -> Void)

    // MARK: - 配置更新

    /// 更新 EXTERNAL 路径 (硬盘重新连接时)
    func updateExternalPath(syncPairId: String,
                            newPath: String,
                            withReply reply: @escaping (Bool, String?) -> Void)

    /// 设置只读模式
    func setReadOnly(syncPairId: String,
                     readOnly: Bool,
                     withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 生命周期

    /// 准备关闭 (等待写入完成)
    func prepareForShutdown(withReply reply: @escaping (Bool) -> Void)

    /// 获取版本
    func getVersion(withReply reply: @escaping (String) -> Void)
}
```

### 4.2 Sync 服务协议

```swift
/// Sync 服务 XPC 协议
@objc public protocol SyncServiceProtocol {

    // MARK: - 同步控制

    /// 立即同步指定同步对
    func syncNow(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void)

    /// 同步单个文件
    func syncFile(virtualPath: String,
                  syncPairId: String,
                  withReply reply: @escaping (Bool, String?) -> Void)

    /// 暂停同步
    func pauseSync(syncPairId: String,
                   withReply reply: @escaping (Bool, String?) -> Void)

    /// 恢复同步
    func resumeSync(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 状态查询

    /// 获取同步状态
    func getSyncStatus(syncPairId: String,
                       withReply reply: @escaping ([String: Any]) -> Void)

    /// 获取待同步队列
    func getPendingQueue(syncPairId: String,
                         withReply reply: @escaping ([[String: Any]]) -> Void)

    /// 获取同步进度
    func getSyncProgress(syncPairId: String,
                         withReply reply: @escaping ([String: Any]?) -> Void)

    /// 获取同步历史
    func getSyncHistory(syncPairId: String,
                        limit: Int,
                        withReply reply: @escaping ([[String: Any]]) -> Void)

    // MARK: - 配置

    /// 更新同步配置
    func updateSyncConfig(syncPairId: String,
                          config: [String: Any],
                          withReply reply: @escaping (Bool, String?) -> Void)

    /// 注册进度回调
    func registerProgressCallback(syncPairId: String,
                                  callbackId: String,
                                  withReply reply: @escaping (Bool) -> Void)

    // MARK: - 硬盘事件

    /// 通知硬盘已连接
    func diskConnected(diskName: String,
                       mountPoint: String,
                       withReply reply: @escaping (Bool) -> Void)

    /// 通知硬盘已断开
    func diskDisconnected(diskName: String,
                          withReply reply: @escaping (Bool) -> Void)

    // MARK: - 生命周期

    /// 获取版本
    func getVersion(withReply reply: @escaping (String) -> Void)
}
```

### 4.3 服务间协作

```
┌─────────────────────────────────────────────────────────────────────┐
│                          协作流程示例                                 │
└─────────────────────────────────────────────────────────────────────┘

文件写入流程:
┌──────────┐     写入请求      ┌──────────┐
│  用户    │ ───────────────▶ │   VFS    │
│ (Finder) │                  │ Service  │
└──────────┘                  └────┬─────┘
                                   │
                    1. 写入到 LOCAL_DIR
                    2. 标记 isDirty
                    3. 返回成功
                                   │
                                   │  通知写入完成
                                   ▼
                             ┌──────────┐
                             │  Sync    │
                             │ Service  │
                             └────┬─────┘
                                  │
                   4. 加入同步队列 (防抖)
                   5. 异步同步到 EXTERNAL
                                  │
                                  ▼
                          [ EXTERNAL_DIR ]

硬盘连接流程:
┌──────────┐   检测到硬盘      ┌──────────┐
│  系统    │ ───────────────▶ │ DMSA.app │
│ (IOKit) │                   │          │
└──────────┘                  └────┬─────┘
                                   │
                                   │ diskConnected()
                                   ▼
                             ┌──────────┐
                             │  Sync    │
                             │ Service  │
                             └────┬─────┘
                                  │
                   1. 恢复待同步队列
                   2. 开始增量同步
                                  │
                                  │ updateExternalPath()
                                  ▼
                             ┌──────────┐
                             │   VFS    │
                             │ Service  │
                             └────┬─────┘
                                  │
                   3. 更新合并视图
                   4. 启用 EXTERNAL 读取路由
```

---

## 5. 通信机制

### 5.1 XPC 通信拓扑

```
                              ┌─────────────┐
                              │  DMSA.app   │
                              │   (GUI)     │
                              └──────┬──────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
                    ▼                ▼                ▼
              ┌──────────┐    ┌──────────┐    ┌──────────┐
              │   VFS    │    │   Sync   │    │  Helper  │
              │ Service  │    │ Service  │    │ Service  │
              └────┬─────┘    └────┬─────┘    └──────────┘
                   │               │
                   └───────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │ 服务间通信    │
                    │ (XPC Notify) │
                    └──────────────┘
```

### 5.2 通知机制 (服务间)

使用 `notify_post` / `notify_register_dispatch` 进行轻量级服务间通知:

```swift
// 通知名称定义
enum DMSANotification {
    static let fileWritten = "com.ttttt.dmsa.notification.fileWritten"
    static let syncCompleted = "com.ttttt.dmsa.notification.syncCompleted"
    static let diskConnected = "com.ttttt.dmsa.notification.diskConnected"
    static let diskDisconnected = "com.ttttt.dmsa.notification.diskDisconnected"
    static let configChanged = "com.ttttt.dmsa.notification.configChanged"
}

// VFS Service 发送写入通知
func notifyFileWritten(_ virtualPath: String) {
    // 写入共享状态
    sharedState.lastWrittenPath = virtualPath
    // 发送通知
    notify_post(DMSANotification.fileWritten)
}

// Sync Service 监听写入通知
func setupNotificationObserver() {
    var token: Int32 = 0
    notify_register_dispatch(
        DMSANotification.fileWritten,
        &token,
        DispatchQueue.main
    ) { [weak self] _ in
        self?.handleFileWritten()
    }
}
```

### 5.3 共享数据

使用共享容器存储跨进程数据:

```
~/Library/Group Containers/group.com.ttttt.dmsa/
├── config.json              # 共享配置
├── shared_state.json        # 运行时状态
├── Database/                # ObjectBox 数据库
│   └── ...
└── Logs/                    # 共享日志
    ├── vfs.log
    ├── sync.log
    └── helper.log
```

---

## 6. 安全模型

### 6.1 权限分层

```
┌─────────────────────────────────────────────────────────────────────┐
│                          权限模型                                    │
└─────────────────────────────────────────────────────────────────────┘

                    ┌─────────────────────┐
                    │      root           │
                    │  (最高权限)          │
                    └──────────┬──────────┘
                               │
       ┌───────────────────────┼───────────────────────┐
       ▼                       ▼                       ▼
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│ VFS Service  │       │ Sync Service │       │Helper Service│
│              │       │              │       │              │
│ • FUSE 挂载   │       │ • 文件读写   │       │ • chflags    │
│ • 所有文件访问 │       │ • 目录遍历   │       │ • ACL 修改   │
│ • 元数据管理   │       │ • 外置硬盘访问│       │ • 权限修改   │
└──────────────┘       └──────────────┘       └──────────────┘

                    ┌─────────────────────┐
                    │    普通用户          │
                    │   (受限权限)         │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │      DMSA.app        │
                    │                      │
                    │ • UI 显示             │
                    │ • 配置读写            │
                    │ • XPC 客户端调用      │
                    │ • 无直接文件系统访问   │
                    └──────────────────────┘
```

### 6.2 XPC 安全验证

每个服务验证连接来源:

```swift
// 服务端验证
func listener(_ listener: NSXPCListener,
              shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {

    // 获取连接进程信息
    let pid = newConnection.processIdentifier
    let auditToken = newConnection.auditToken

    // 验证代码签名
    guard verifyCodeSignature(auditToken: auditToken) else {
        Logger.error("拒绝未签名连接: PID \(pid)")
        return false
    }

    // 验证是否为授权应用
    guard isAuthorizedClient(auditToken: auditToken) else {
        Logger.error("拒绝未授权连接: PID \(pid)")
        return false
    }

    return true
}

/// 验证代码签名
private func verifyCodeSignature(auditToken: audit_token_t) -> Bool {
    var code: SecCode?
    let status = SecCodeCopyGuestWithAttributes(
        nil,
        [kSecGuestAttributeAudit: Data(bytes: &auditToken, count: MemoryLayout<audit_token_t>.size) as CFData],
        [],
        &code
    )

    guard status == errSecSuccess, let code = code else {
        return false
    }

    // 验证签名要求
    var requirement: SecRequirement?
    let requirementString = """
        identifier "com.ttttt.dmsa" and anchor apple generic and \
        certificate leaf[subject.OU] = "9QGKH6ZBPG"
        """

    SecRequirementCreateWithString(requirementString as CFString, [], &requirement)

    guard let requirement = requirement else {
        return false
    }

    return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
}
```

### 6.3 路径安全

所有服务执行路径白名单验证:

```swift
/// 路径安全验证器
struct PathValidator {

    /// 允许操作的路径前缀
    private static let allowedPrefixes: [String] = [
        NSHomeDirectory() + "/Downloads_Local",
        NSHomeDirectory() + "/Downloads",
        NSHomeDirectory() + "/Documents_Local",
        NSHomeDirectory() + "/Documents",
        "/Volumes/"  // 外置硬盘
    ]

    /// 禁止操作的路径
    private static let forbiddenPaths: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/etc",
        "/var",
        "/Library/System",
        "/private"
    ]

    /// 验证路径是否允许操作
    static func isAllowed(_ path: String) -> Bool {
        let resolvedPath = (path as NSString).standardizingPath

        // 检查禁止路径
        for forbidden in forbiddenPaths {
            if resolvedPath.hasPrefix(forbidden) {
                return false
            }
        }

        // 检查允许路径
        for allowed in allowedPrefixes {
            if resolvedPath.hasPrefix(allowed) {
                return true
            }
        }

        return false
    }
}
```

---

## 7. 数据流设计

### 7.1 读取流程

```
用户读取 ~/Downloads/file.pdf
                │
                ▼
┌─────────────────────────────────────────────────┐
│              VFS Service (FUSE)                 │
│                                                 │
│  1. 接收 FUSE read 回调                          │
│  2. 查询 FileEntry 获取文件位置                    │
│  3. 根据位置状态路由:                              │
│     • LOCAL_ONLY/BOTH → 从 LOCAL_DIR 读取        │
│     • EXTERNAL_ONLY → 从 EXTERNAL_DIR 读取       │
│  4. 更新 accessedAt (LRU 时间戳)                  │
│  5. 返回文件内容                                  │
│                                                 │
└─────────────────────────────────────────────────┘
                │
                ▼
          [ 文件内容 ]
```

### 7.2 写入流程

```
用户写入 ~/Downloads/file.pdf
                │
                ▼
┌─────────────────────────────────────────────────┐
│              VFS Service (FUSE)                 │
│                                                 │
│  1. 接收 FUSE write 回调                         │
│  2. 检查本地空间 (触发 LRU 淘汰)                   │
│  3. 写入到 LOCAL_DIR                             │
│  4. 更新 FileEntry (isDirty=true)               │
│  5. 发送 fileWritten 通知                        │
│  6. 返回写入成功                                  │
│                                                 │
└────────────────────┬────────────────────────────┘
                     │
                     │ notify_post(fileWritten)
                     ▼
┌─────────────────────────────────────────────────┐
│              Sync Service                       │
│                                                 │
│  1. 收到 fileWritten 通知                        │
│  2. 查询脏文件队列                                │
│  3. 应用防抖策略 (5秒)                            │
│  4. 如果 EXTERNAL 在线:                          │
│     • 同步文件到 EXTERNAL                        │
│     • 更新 FileEntry (isDirty=false)            │
│  5. 如果 EXTERNAL 离线:                          │
│     • 保留在待同步队列                            │
│                                                 │
└─────────────────────────────────────────────────┘
```

### 7.3 目录列表流程

```
用户列出 ~/Downloads/
                │
                ▼
┌─────────────────────────────────────────────────┐
│              VFS Service (FUSE)                 │
│                                                 │
│  1. 接收 FUSE readdir 回调                       │
│  2. 调用 MergeEngine.merge()                    │
│     a. 列出 LOCAL_DIR 内容                       │
│     b. 列出 EXTERNAL_DIR 内容 (如果在线)          │
│     c. 合并去重: LOCAL ∪ EXTERNAL               │
│  3. 返回合并后的目录列表                          │
│                                                 │
└─────────────────────────────────────────────────┘
                │
                ▼
    [ 合并的目录列表 ]
```

---

## 8. 部署架构

### 8.1 安装包结构

```
DMSA.pkg/
├── DMSA.app                                    # 主应用
│   └── Contents/
│       ├── MacOS/DMSA
│       ├── Library/
│       │   └── LaunchServices/
│       │       ├── com.ttttt.dmsa.vfs          # VFS 服务二进制
│       │       ├── com.ttttt.dmsa.sync         # Sync 服务二进制
│       │       └── com.ttttt.dmsa.helper       # Helper 服务二进制
│       └── Info.plist                          # SMPrivilegedExecutables
│
├── Scripts/
│   ├── preinstall                              # 安装前脚本
│   └── postinstall                             # 安装后脚本
│
└── Resources/
    ├── com.ttttt.dmsa.vfs.plist                # VFS LaunchDaemon 配置
    ├── com.ttttt.dmsa.sync.plist               # Sync LaunchDaemon 配置
    └── com.ttttt.dmsa.helper.plist             # Helper LaunchDaemon 配置
```

### 8.2 安装流程

```
安装 DMSA.pkg
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ 1. 复制 DMSA.app 到 /Applications/                                │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ 2. 首次启动 DMSA.app                                              │
│    用户点击"安装系统服务"                                           │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ 3. SMJobBless / SMAppService 安装服务                              │
│    系统提示管理员密码授权                                           │
│                                                                   │
│    安装文件:                                                       │
│    • /Library/PrivilegedHelperTools/com.ttttt.dmsa.vfs           │
│    • /Library/PrivilegedHelperTools/com.ttttt.dmsa.sync          │
│    • /Library/PrivilegedHelperTools/com.ttttt.dmsa.helper        │
│    • /Library/LaunchDaemons/com.ttttt.dmsa.vfs.plist             │
│    • /Library/LaunchDaemons/com.ttttt.dmsa.sync.plist            │
│    • /Library/LaunchDaemons/com.ttttt.dmsa.helper.plist          │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ 4. launchctl bootstrap 启动服务                                   │
│    • VFS Service 挂载虚拟文件系统                                  │
│    • Sync Service 开始监控同步                                     │
│    • Helper Service 保护目录                                       │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│ 5. 配置向导                                                       │
│    • 设置同步对                                                    │
│    • 配置本地存储配额                                               │
│    • 完成首次设置                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 8.3 启动顺序

```
系统启动
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 1. launchd 启动 LaunchDaemons                   │
│    顺序: helper → vfs → sync                    │
└─────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 2. com.ttttt.dmsa.helper 就绪                   │
│    • 等待 XPC 请求                               │
└─────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 3. com.ttttt.dmsa.vfs 启动                      │
│    • 加载配置                                    │
│    • 调用 Helper 保护目录                         │
│    • 挂载所有配置的 VFS                           │
│    • 就绪，等待文件操作                           │
└─────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 4. com.ttttt.dmsa.sync 启动                     │
│    • 加载配置和同步状态                           │
│    • 恢复未完成的同步任务                         │
│    • 启动定时同步调度器                           │
│    • 监听硬盘连接事件                             │
└─────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 5. 用户登录                                      │
│    • DMSA.app 可选启动 (LaunchAgent)             │
│    • 连接已运行的服务                             │
│    • 显示状态菜单栏图标                           │
└─────────────────────────────────────────────────┘
```

---

## 9. 故障恢复

### 9.1 服务崩溃恢复

```
┌─────────────────────────────────────────────────────────────────────┐
│                        故障恢复策略                                   │
└─────────────────────────────────────────────────────────────────────┘

场景 1: VFS Service 崩溃
─────────────────────────
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 1. launchd 检测到进程退出                         │
│    (KeepAlive: SuccessfulExit = false)          │
└─────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 2. launchd 自动重启 VFS Service                  │
└─────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 3. VFS Service 恢复流程:                         │
│    a. 加载配置                                   │
│    b. 检查之前的挂载状态                          │
│    c. 重新挂载 VFS                               │
│    d. 从 ObjectBox 恢复文件索引                   │
│    e. 检查 .FUSE/db.json 版本                    │
│    f. 如需要则重建索引                            │
└─────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 4. 用户透明恢复                                  │
│    (中断的文件操作可能失败，需重试)                │
└─────────────────────────────────────────────────┘


场景 2: Sync Service 崩溃
─────────────────────────
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 1. launchd 自动重启                              │
└─────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 2. Sync Service 恢复流程:                        │
│    a. 加载配置                                   │
│    b. 从 ObjectBox 恢复同步状态                   │
│    c. 恢复 isDirty 文件队列                      │
│    d. 恢复暂停的同步任务                          │
│    e. 继续定时同步调度                            │
└─────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 3. 数据不丢失                                    │
│    (脏数据在 ObjectBox 中持久化)                  │
└─────────────────────────────────────────────────┘


场景 3: GUI 退出/崩溃
───────────────────
    │
    ▼
┌─────────────────────────────────────────────────┐
│ VFS 和 Sync 服务继续运行                          │
│ • 文件系统正常访问                                │
│ • 同步继续进行                                   │
│ • 用户重新打开 GUI 即可查看状态                    │
└─────────────────────────────────────────────────┘
```

### 9.2 数据一致性保证

```swift
// 原子性写入保证
class AtomicWriter {

    /// 原子写入文件
    static func write(_ data: Data, to path: URL) throws {
        // 1. 写入临时文件
        let tempPath = path.appendingPathExtension("tmp")
        try data.write(to: tempPath)

        // 2. 同步到磁盘
        let fd = open(tempPath.path, O_RDONLY)
        if fd >= 0 {
            fsync(fd)
            close(fd)
        }

        // 3. 原子重命名
        try FileManager.default.moveItem(at: tempPath, to: path)
    }
}

// 数据库事务保证
class DatabaseManager {

    func updateFileEntry(_ entry: FileEntry, changes: (FileEntry) -> Void) throws {
        try store.runInTransaction {
            changes(entry)
            try fileEntryBox.put(entry)
        }
    }
}
```

---

## 10. 迁移路径

### 10.1 从 v3.x 迁移到 v4.0

```
┌─────────────────────────────────────────────────────────────────────┐
│                        迁移步骤                                       │
└─────────────────────────────────────────────────────────────────────┘

Phase 1: 准备
─────────────
1. 备份现有配置
   ~/Library/Application Support/DMSA/ → ~/DMSA_Backup/

2. 停止现有 DMSA.app
   退出应用，卸载现有 Helper

Phase 2: 安装新版本
─────────────────
3. 安装 DMSA v4.0.pkg

4. 首次启动安装系统服务
   授权安装 VFS/Sync/Helper 三个 LaunchDaemons

Phase 3: 数据迁移
───────────────
5. 迁移工具自动执行:
   a. 检测旧配置格式
   b. 转换为新格式
   c. 迁移 ObjectBox 数据库 (如需升级 schema)
   d. 验证迁移完整性

6. 重新挂载 VFS
   使用新的服务架构重新挂载

Phase 4: 验证
──────────
7. 验证文件访问正常
8. 验证同步功能正常
9. 删除备份 (可选)
```

### 10.2 回滚方案

```
如果迁移失败:

1. 停止新服务
   sudo launchctl bootout system /Library/LaunchDaemons/com.ttttt.dmsa.*.plist

2. 卸载新版本
   删除 /Library/PrivilegedHelperTools/com.ttttt.dmsa.*
   删除 /Library/LaunchDaemons/com.ttttt.dmsa.*.plist

3. 恢复备份
   mv ~/DMSA_Backup/* ~/Library/Application Support/DMSA/

4. 安装旧版本
   运行 DMSA v3.x 安装包
```

---

## 附录

### A. 术语表

| 术语 | 说明 |
|------|------|
| **VFS** | Virtual File System，虚拟文件系统 |
| **FUSE** | Filesystem in Userspace，用户态文件系统 |
| **XPC** | macOS 跨进程通信机制 |
| **LaunchDaemon** | macOS 系统级后台服务 |
| **LaunchAgent** | macOS 用户级后台服务 |
| **SMJobBless** | macOS 安装特权 Helper 的 API |
| **SMAppService** | macOS 13+ 管理后台服务的 API |

### B. 参考文档

- [Apple Developer: Creating a Privileged Helper](https://developer.apple.com/documentation/servicemanagement/updating_your_app_package_installer_to_use_the_new_service_management_api)
- [macFUSE Documentation](https://macfuse.github.io/)
- [XPC Services Programming Guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)

---

*文档维护: 每次架构变更时更新*
