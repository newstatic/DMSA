# DMSA v3.x → v4.0 系统架构迁移实施方案

> 版本: 1.0 | 创建日期: 2026-01-24
> 状态: 实施规划

---

## 目录

1. [迁移概述](#1-迁移概述)
2. [现状分析](#2-现状分析)
3. [目标架构](#3-目标架构)
4. [迁移阶段](#4-迁移阶段)
5. [详细实施步骤](#5-详细实施步骤)
6. [代码变更清单](#6-代码变更清单)
7. [测试计划](#7-测试计划)
8. [回滚方案](#8-回滚方案)
9. [风险评估](#9-风险评估)

---

## 1. 迁移概述

### 1.1 迁移目标

将 DMSA 从 **单体应用架构 (v3.x)** 迁移至 **四进程服务架构 (v4.0)**。

| 维度 | 当前 (v3.x) | 目标 (v4.0) |
|------|-------------|-------------|
| **进程模型** | 单体 (GUI + VFS + Sync 同进程) | 四进程 (GUI / VFS / Sync / Helper) |
| **服务运行** | GUI 退出则服务停止 | LaunchDaemon 持久运行 |
| **权限模型** | 用户权限 + Helper 辅助 | VFS/Sync 以 root 运行 |
| **故障隔离** | GUI 崩溃全部停止 | 各组件独立恢复 |

### 1.2 迁移原则

1. **渐进式迁移**: 分阶段实施，每阶段可独立验证
2. **向后兼容**: 保留旧配置格式支持
3. **零数据丢失**: 迁移过程保证数据完整性
4. **可回滚**: 每个阶段都有回滚点

### 1.3 预估工作量

| 阶段 | 主要工作 | 复杂度 |
|------|---------|--------|
| Phase 1: 基础设施 | XPC 协议、共享代码提取 | 中 |
| Phase 2: VFS Service | VFS 独立进程化 | 高 |
| Phase 3: Sync Service | Sync 独立进程化 | 高 |
| Phase 4: GUI 重构 | XPC 客户端集成 | 中 |
| Phase 5: 部署集成 | 安装/升级流程 | 低 |

---

## 2. 现状分析

### 2.1 当前代码结构

```
DMSAApp/DMSAApp/
├── App/
│   ├── AppDelegate.swift          # 主入口，包含所有初始化
│   └── main.swift
├── Services/
│   ├── DatabaseManager.swift       # 数据库 (需共享)
│   ├── SyncEngine.swift            # 同步调度 (移至 Sync Service)
│   ├── SyncScheduler.swift         # 调度器 (移至 Sync Service)
│   ├── DiskManager.swift           # 硬盘监控 (GUI 保留)
│   ├── FSEventsMonitor.swift       # 文件监控 (移至 Sync Service)
│   ├── NotificationManager.swift   # 通知 (GUI 保留)
│   ├── PermissionManager.swift     # 权限 (GUI 保留)
│   ├── PrivilegedClient.swift      # XPC 客户端 (重构扩展)
│   ├── TreeVersionManager.swift    # 版本管理 (移至 VFS Service)
│   ├── Sync/
│   │   ├── NativeSyncEngine.swift  # 核心同步 (移至 Sync Service)
│   │   ├── FileScanner.swift       # 文件扫描 (移至 Sync Service)
│   │   ├── DiffEngine.swift        # 差异计算 (移至 Sync Service)
│   │   ├── FileCopier.swift        # 文件复制 (移至 Sync Service)
│   │   └── ConflictResolver.swift  # 冲突解决 (移至 Sync Service)
│   └── VFS/
│       ├── VFSCore.swift           # VFS 核心 (移至 VFS Service)
│       ├── DMSAFileSystem.swift    # FUSE 实现 (移至 VFS Service)
│       ├── FUSEManager.swift       # FUSE 管理 (移至 VFS Service)
│       ├── MergeEngine.swift       # 合并引擎 (移至 VFS Service)
│       ├── ReadRouter.swift        # 读路由 (移至 VFS Service)
│       ├── WriteRouter.swift       # 写路由 (移至 VFS Service)
│       └── LockManager.swift       # 锁管理 (移至 VFS Service)
├── Models/                          # 大部分共享
└── UI/                              # GUI 保留
```

### 2.2 当前问题

| 问题 | 影响 | 优先级 |
|------|------|--------|
| GUI 退出 VFS 卸载 | 用户文件不可访问 | P0 |
| VFS 用户态权限受限 | 某些操作失败 | P1 |
| Sync 与 GUI 耦合 | 后台同步不可靠 | P1 |
| 单点故障 | 崩溃影响全部功能 | P2 |

### 2.3 现有代码量统计

| 模块 | 文件数 | 代码行数 | 迁移目标 |
|------|--------|---------|---------|
| Services/VFS | 13 | ~4,500 | VFS Service |
| Services/Sync | 8 | ~4,000 | Sync Service |
| Services/其他 | 10 | ~2,000 | GUI / 共享 |
| Models | 14 | ~2,000 | 共享 |
| UI | 35 | ~5,500 | GUI |
| Utils | 4 | ~850 | 共享 |
| Helper | 3 | ~500 | 保持 |

---

## 3. 目标架构

### 3.1 进程分布

```
┌─────────────────────────────────────────────────────────────────────┐
│                         目标架构 (v4.0)                               │
└─────────────────────────────────────────────────────────────────────┘

用户态:
┌───────────────────────────────────────────────────────────────────────┐
│                       DMSA.app (菜单栏应用)                             │
│   - 用户权限运行                                                       │
│   - 只负责 UI 和状态显示                                               │
│   - 通过 XPC 与服务通信                                                │
│                                                                       │
│   代码:                                                               │
│   ├── App/ (AppDelegate, main)                                       │
│   ├── UI/ (所有视图)                                                  │
│   ├── XPCClients/ (VFSClient, SyncClient, HelperClient) [新增]       │
│   └── Services/ (ConfigManager, NotificationManager, DiskManager)    │
└───────────────────────────────────────────────────────────────────────┘
                                    │
                            XPC 通信 (NSXPCConnection)
                                    │
系统态:                              ▼
┌───────────────────────────────────────────────────────────────────────┐
│                     LaunchDaemons (root 权限)                          │
│                                                                       │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌───────────────┐ │
│  │ com.ttttt.dmsa.vfs  │  │ com.ttttt.dmsa.sync │  │ .dmsa.helper  │ │
│  │                     │  │                     │  │               │ │
│  │ 代码:               │  │ 代码:               │  │ 代码:         │ │
│  │ ├── main.swift     │  │ ├── main.swift     │  │ (现有代码)     │ │
│  │ ├── VFSService*    │  │ ├── SyncService*   │  │               │ │
│  │ └── Services/VFS/* │  │ └── Services/Sync/*│  │               │ │
│  └─────────────────────┘  └─────────────────────┘  └───────────────┘ │
│                                                                       │
│  共享层:                                                              │
│  ├── SharedModels/ (Config, FileEntry, SyncHistory, etc.)            │
│  ├── SharedUtils/ (Logger, Constants, Errors, PathValidator)         │
│  └── SharedProtocols/ (VFSServiceProtocol, SyncServiceProtocol)      │
└───────────────────────────────────────────────────────────────────────┘
```

### 3.2 新增文件清单

```
DMSAApp/
├── DMSAApp/                           # 主应用 (瘦身后)
│   ├── XPCClients/                    [新增目录]
│   │   ├── VFSClient.swift            [新增] VFS 服务 XPC 客户端
│   │   ├── SyncClient.swift           [新增] Sync 服务 XPC 客户端
│   │   └── HelperClient.swift         [重命名] 原 PrivilegedClient.swift
│   └── Services/                      [精简]
│       └── (移除 VFS/* 和 Sync/*)
│
├── DMSAVFSService/                    [新增 Target]
│   ├── main.swift                     [新增] XPC 服务入口
│   ├── VFSServiceDelegate.swift       [新增] NSXPCListenerDelegate
│   ├── VFSServiceProtocol.swift       [新增] XPC 协议
│   ├── Info.plist                     [新增]
│   ├── Entitlements                   [新增]
│   └── Services/                      [从主应用移动]
│       └── VFS/
│           ├── VFSCore.swift
│           ├── DMSAFileSystem.swift
│           ├── FUSEManager.swift
│           ├── MergeEngine.swift
│           ├── ReadRouter.swift
│           ├── WriteRouter.swift
│           ├── LockManager.swift
│           └── ...
│
├── DMSASyncService/                   [新增 Target]
│   ├── main.swift                     [新增] XPC 服务入口
│   ├── SyncServiceDelegate.swift      [新增] NSXPCListenerDelegate
│   ├── SyncServiceProtocol.swift      [新增] XPC 协议
│   ├── Info.plist                     [新增]
│   ├── Entitlements                   [新增]
│   └── Services/                      [从主应用移动]
│       └── Sync/
│           ├── NativeSyncEngine.swift
│           ├── FileScanner.swift
│           ├── DiffEngine.swift
│           ├── FileCopier.swift
│           ├── ConflictResolver.swift
│           ├── SyncScheduler.swift    [移动]
│           └── FSEventsMonitor.swift  [移动]
│
├── DMSAShared/                        [新增 Framework/静态库]
│   ├── Models/
│   │   ├── Config.swift
│   │   ├── FileEntry.swift
│   │   ├── SyncHistory.swift
│   │   └── ...
│   ├── Protocols/
│   │   ├── VFSServiceProtocol.swift
│   │   ├── SyncServiceProtocol.swift
│   │   └── HelperProtocol.swift
│   ├── Utils/
│   │   ├── Logger.swift
│   │   ├── Constants.swift
│   │   ├── Errors.swift
│   │   └── PathValidator.swift
│   └── Database/
│       └── DatabaseManager.swift
│
└── Resources/
    ├── com.ttttt.dmsa.vfs.plist       [新增] VFS LaunchDaemon 配置
    └── com.ttttt.dmsa.sync.plist      [新增] Sync LaunchDaemon 配置
```

---

## 4. 迁移阶段

### Phase 概览

```
┌────────────────────────────────────────────────────────────────────────┐
│                          迁移时间线                                      │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Phase 1          Phase 2          Phase 3          Phase 4    Phase 5│
│  ════════         ════════         ════════         ════════   ═══════│
│  基础设施          VFS Service      Sync Service     GUI 重构   部署    │
│                                                                        │
│  ┌──────┐        ┌──────┐        ┌──────┐        ┌──────┐   ┌──────┐ │
│  │共享库 │───────▶│VFS   │───────▶│Sync  │───────▶│XPC   │──▶│安装包│ │
│  │XPC协议│        │独立化│        │独立化│        │客户端│   │测试  │ │
│  └──────┘        └──────┘        └──────┘        └──────┘   └──────┘ │
│                                                                        │
│  可回滚 ✓         可回滚 ✓         可回滚 ✓         可回滚 ✓   可回滚 ✓ │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 5. 详细实施步骤

### Phase 1: 基础设施准备

#### 1.1 创建 DMSAShared Framework

**目标**: 提取可共享代码到独立模块

```bash
# 创建目录结构
mkdir -p DMSAApp/DMSAShared/{Models,Protocols,Utils,Database}
```

**步骤**:

1. **创建 Xcode Framework Target**
   - Product Name: `DMSAShared`
   - Type: Framework
   - Language: Swift

2. **移动共享模型** (Models/)
   ```swift
   // 需移动的文件:
   - Config.swift
   - FileEntry.swift
   - SyncHistory.swift
   - SyncStatistics.swift
   - NotificationRecord.swift
   - DiskConfigEntity.swift
   - SyncPairEntity.swift
   - Sync/SyncProgress.swift
   - Sync/SyncPlan.swift
   - Sync/ConflictInfo.swift
   - Sync/FileMetadata.swift
   ```

3. **移动工具类** (Utils/)
   ```swift
   // 需移动的文件:
   - Logger.swift
   - Constants.swift
   - Errors.swift
   - PathValidator.swift
   ```

4. **移动数据库管理** (Database/)
   ```swift
   // 需移动的文件:
   - DatabaseManager.swift
   ```

5. **更新访问级别**
   - 所有共享类/结构添加 `public` 修饰符
   - 所有共享协议添加 `public` 修饰符

#### 1.2 定义 XPC 协议

**VFSServiceProtocol.swift**:
```swift
import Foundation

/// VFS 服务 XPC 协议
@objc public protocol VFSServiceProtocol {

    // MARK: - 挂载管理

    func mount(syncPairId: String,
               localDir: String,
               externalDir: String,
               targetDir: String,
               withReply reply: @escaping (Bool, String?) -> Void)

    func unmount(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void)

    func getMountStatus(syncPairId: String,
                        withReply reply: @escaping (Bool, String?) -> Void)

    func getAllMounts(withReply reply: @escaping ([[String: Any]]) -> Void)

    // MARK: - 文件状态

    func getFileStatus(virtualPath: String,
                       syncPairId: String,
                       withReply reply: @escaping ([String: Any]?) -> Void)

    // MARK: - 配置更新

    func updateExternalPath(syncPairId: String,
                            newPath: String,
                            withReply reply: @escaping (Bool, String?) -> Void)

    func setReadOnly(syncPairId: String,
                     readOnly: Bool,
                     withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 生命周期

    func prepareForShutdown(withReply reply: @escaping (Bool) -> Void)

    func getVersion(withReply reply: @escaping (String) -> Void)
}
```

**SyncServiceProtocol.swift**:
```swift
import Foundation

/// Sync 服务 XPC 协议
@objc public protocol SyncServiceProtocol {

    // MARK: - 同步控制

    func syncNow(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void)

    func syncFile(virtualPath: String,
                  syncPairId: String,
                  withReply reply: @escaping (Bool, String?) -> Void)

    func pauseSync(syncPairId: String,
                   withReply reply: @escaping (Bool, String?) -> Void)

    func resumeSync(syncPairId: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 状态查询

    func getSyncStatus(syncPairId: String,
                       withReply reply: @escaping ([String: Any]) -> Void)

    func getPendingQueue(syncPairId: String,
                         withReply reply: @escaping ([[String: Any]]) -> Void)

    func getSyncProgress(syncPairId: String,
                         withReply reply: @escaping ([String: Any]?) -> Void)

    func getSyncHistory(syncPairId: String,
                        limit: Int,
                        withReply reply: @escaping ([[String: Any]]) -> Void)

    // MARK: - 配置

    func updateSyncConfig(syncPairId: String,
                          config: [String: Any],
                          withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - 硬盘事件

    func diskConnected(diskName: String,
                       mountPoint: String,
                       withReply reply: @escaping (Bool) -> Void)

    func diskDisconnected(diskName: String,
                          withReply reply: @escaping (Bool) -> Void)

    // MARK: - 生命周期

    func getVersion(withReply reply: @escaping (String) -> Void)
}
```

#### 1.3 配置 Framework 依赖

在 `DMSAApp.xcodeproj` 中:
- 添加 DMSAShared 为 DMSAApp 的 Embedded Framework
- 配置 Build Phases: Link Binary With Libraries

**验收标准**:
- [ ] DMSAShared.framework 编译成功
- [ ] DMSAApp 成功链接 DMSAShared
- [ ] 现有功能不受影响

---

### Phase 2: VFS Service 独立化

#### 2.1 创建 VFS Service Target

1. **新建 Command Line Tool Target**
   - Product Name: `com.ttttt.dmsa.vfs`
   - Type: Command Line Tool
   - Language: Swift

2. **配置 Info.plist**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ttttt.dmsa.vfs</string>
    <key>CFBundleName</key>
    <string>DMSA VFS Service</string>
    <key>CFBundleVersion</key>
    <string>4.0</string>
    <key>SMAuthorizedClients</key>
    <array>
        <string>identifier "com.ttttt.dmsa" and anchor apple generic and certificate leaf[subject.OU] = "9QGKH6ZBPG"</string>
    </array>
</dict>
</plist>
```

3. **创建 Entitlements**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

#### 2.2 实现 VFS Service 入口

**DMSAVFSService/main.swift**:
```swift
import Foundation
import DMSAShared

/// VFS Service 入口点
@main
class VFSServiceMain {
    static func main() {
        // 设置日志
        Logger.shared.info("VFS Service 启动")

        // 创建 XPC 监听器
        let delegate = VFSServiceDelegate()
        let listener = NSXPCListener(machServiceName: "com.ttttt.dmsa.vfs")
        listener.delegate = delegate
        listener.resume()

        Logger.shared.info("VFS Service XPC 监听器已启动")

        // 运行主循环
        RunLoop.main.run()
    }
}
```

**DMSAVFSService/VFSServiceDelegate.swift**:
```swift
import Foundation
import DMSAShared

/// VFS Service XPC 委托
class VFSServiceDelegate: NSObject, NSXPCListenerDelegate {

    private let vfsCore = VFSCore.shared

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {

        // 验证连接来源
        guard verifyConnection(newConnection) else {
            Logger.shared.error("拒绝未授权连接: PID \(newConnection.processIdentifier)")
            return false
        }

        // 配置连接
        newConnection.exportedInterface = NSXPCInterface(with: VFSServiceProtocol.self)
        newConnection.exportedObject = VFSServiceImplementation()

        newConnection.invalidationHandler = {
            Logger.shared.info("XPC 连接已断开")
        }

        newConnection.resume()
        return true
    }

    private func verifyConnection(_ connection: NSXPCConnection) -> Bool {
        // 验证代码签名
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(
            nil,
            [kSecGuestAttributeAudit: connection.auditToken as CFTypeRef],
            [],
            &code
        )

        guard status == errSecSuccess, let code = code else {
            return false
        }

        // 验证签名要求
        var requirement: SecRequirement?
        let requirementString = """
            identifier "com.ttttt.dmsa" and anchor apple generic
            """

        SecRequirementCreateWithString(requirementString as CFString, [], &requirement)

        guard let requirement = requirement else {
            return false
        }

        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
```

**DMSAVFSService/VFSServiceImplementation.swift**:
```swift
import Foundation
import DMSAShared

/// VFS Service XPC 协议实现
class VFSServiceImplementation: NSObject, VFSServiceProtocol {

    private let vfsCore = VFSCore.shared

    // MARK: - 挂载管理

    func mount(syncPairId: String,
               localDir: String,
               externalDir: String,
               targetDir: String,
               withReply reply: @escaping (Bool, String?) -> Void) {

        Logger.shared.info("收到挂载请求: \(syncPairId)")

        Task {
            do {
                try await vfsCore.mount(
                    syncPairId: syncPairId,
                    localDir: localDir,
                    externalDir: externalDir,
                    targetDir: targetDir
                )
                reply(true, nil)
            } catch {
                Logger.shared.error("挂载失败: \(error)")
                reply(false, error.localizedDescription)
            }
        }
    }

    func unmount(syncPairId: String,
                 withReply reply: @escaping (Bool, String?) -> Void) {

        Task {
            do {
                try await vfsCore.unmount(syncPairId: syncPairId)
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func getMountStatus(syncPairId: String,
                        withReply reply: @escaping (Bool, String?) -> Void) {

        let isMounted = vfsCore.isMounted(syncPairId: syncPairId)
        reply(isMounted, nil)
    }

    func getAllMounts(withReply reply: @escaping ([[String: Any]]) -> Void) {
        let mounts = vfsCore.getAllMounts().map { $0.toDictionary() }
        reply(mounts)
    }

    // MARK: - 文件状态

    func getFileStatus(virtualPath: String,
                       syncPairId: String,
                       withReply reply: @escaping ([String: Any]?) -> Void) {

        Task {
            if let status = await vfsCore.getFileStatus(
                virtualPath: virtualPath,
                syncPairId: syncPairId
            ) {
                reply(status.toDictionary())
            } else {
                reply(nil)
            }
        }
    }

    // MARK: - 配置更新

    func updateExternalPath(syncPairId: String,
                            newPath: String,
                            withReply reply: @escaping (Bool, String?) -> Void) {

        Task {
            do {
                try await vfsCore.updateExternalPath(
                    syncPairId: syncPairId,
                    newPath: newPath
                )
                reply(true, nil)
            } catch {
                reply(false, error.localizedDescription)
            }
        }
    }

    func setReadOnly(syncPairId: String,
                     readOnly: Bool,
                     withReply reply: @escaping (Bool, String?) -> Void) {

        vfsCore.setReadOnly(syncPairId: syncPairId, readOnly: readOnly)
        reply(true, nil)
    }

    // MARK: - 生命周期

    func prepareForShutdown(withReply reply: @escaping (Bool) -> Void) {
        Task {
            await vfsCore.prepareForShutdown()
            reply(true)
        }
    }

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply("4.0.0")
    }
}
```

#### 2.3 移动 VFS 代码

从 `DMSAApp/Services/VFS/` 移动到 `DMSAVFSService/Services/VFS/`:

| 原路径 | 新路径 |
|--------|--------|
| `Services/VFS/VFSCore.swift` | `DMSAVFSService/Services/VFS/VFSCore.swift` |
| `Services/VFS/DMSAFileSystem.swift` | `DMSAVFSService/Services/VFS/DMSAFileSystem.swift` |
| `Services/VFS/FUSEManager.swift` | `DMSAVFSService/Services/VFS/FUSEManager.swift` |
| `Services/VFS/MergeEngine.swift` | `DMSAVFSService/Services/VFS/MergeEngine.swift` |
| `Services/VFS/ReadRouter.swift` | `DMSAVFSService/Services/VFS/ReadRouter.swift` |
| `Services/VFS/WriteRouter.swift` | `DMSAVFSService/Services/VFS/WriteRouter.swift` |
| `Services/VFS/LockManager.swift` | `DMSAVFSService/Services/VFS/LockManager.swift` |
| `Services/VFS/VFSFileSystem.swift` | `DMSAVFSService/Services/VFS/VFSFileSystem.swift` |
| `Services/VFS/FUSEBridge.swift` | `DMSAVFSService/Services/VFS/FUSEBridge.swift` |
| `Services/VFS/VFSError.swift` | `DMSAVFSService/Services/VFS/VFSError.swift` |
| `Services/TreeVersionManager.swift` | `DMSAVFSService/Services/TreeVersionManager.swift` |

#### 2.4 修改 VFSCore 适配

**VFSCore.swift 修改**:
```swift
// 移除 GUI 相关依赖
// 添加 notify_post 通知机制

import Foundation
import DMSAShared

public class VFSCore {
    public static let shared = VFSCore()

    // 添加服务间通知
    func notifyFileWritten(_ virtualPath: String, syncPairId: String) {
        // 写入共享状态文件
        let stateURL = Constants.sharedStateURL
        var state = loadSharedState()
        state["lastWrittenPath"] = virtualPath
        state["lastWrittenSyncPair"] = syncPairId
        state["lastWrittenTime"] = Date().timeIntervalSince1970
        saveSharedState(state)

        // 发送 notify 通知
        notify_post("com.ttttt.dmsa.notification.fileWritten")
    }
}
```

#### 2.5 创建 LaunchDaemon 配置

**Resources/com.ttttt.dmsa.vfs.plist**:
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
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>/var/root</string>
    </dict>
</dict>
</plist>
```

**验收标准**:
- [ ] VFS Service 独立编译成功
- [ ] LaunchDaemon 配置正确
- [ ] XPC 通信正常
- [ ] FUSE 挂载在服务进程中运行
- [ ] GUI 退出后 VFS 继续运行

---

### Phase 3: Sync Service 独立化

#### 3.1 创建 Sync Service Target

与 VFS Service 类似，创建 `com.ttttt.dmsa.sync` Target。

#### 3.2 实现 Sync Service 入口

**DMSASyncService/main.swift**:
```swift
import Foundation
import DMSAShared

@main
class SyncServiceMain {
    static func main() {
        Logger.shared.info("Sync Service 启动")

        let delegate = SyncServiceDelegate()
        let listener = NSXPCListener(machServiceName: "com.ttttt.dmsa.sync")
        listener.delegate = delegate
        listener.resume()

        // 启动定时调度器
        SyncScheduler.shared.start()

        // 注册 VFS 写入通知监听
        setupVFSNotificationObserver()

        Logger.shared.info("Sync Service 已就绪")
        RunLoop.main.run()
    }

    static func setupVFSNotificationObserver() {
        var token: Int32 = 0
        notify_register_dispatch(
            "com.ttttt.dmsa.notification.fileWritten",
            &token,
            DispatchQueue.global(qos: .utility)
        ) { _ in
            // 读取共享状态
            if let state = loadSharedState(),
               let path = state["lastWrittenPath"] as? String,
               let syncPairId = state["lastWrittenSyncPair"] as? String {
                SyncScheduler.shared.scheduleSync(for: path, syncPairId: syncPairId)
            }
        }
    }
}
```

#### 3.3 移动 Sync 代码

从主应用移动到 DMSASyncService:

| 原路径 | 新路径 |
|--------|--------|
| `Services/Sync/NativeSyncEngine.swift` | `DMSASyncService/Services/Sync/NativeSyncEngine.swift` |
| `Services/Sync/FileScanner.swift` | `DMSASyncService/Services/Sync/FileScanner.swift` |
| `Services/Sync/DiffEngine.swift` | `DMSASyncService/Services/Sync/DiffEngine.swift` |
| `Services/Sync/FileCopier.swift` | `DMSASyncService/Services/Sync/FileCopier.swift` |
| `Services/Sync/ConflictResolver.swift` | `DMSASyncService/Services/Sync/ConflictResolver.swift` |
| `Services/SyncScheduler.swift` | `DMSASyncService/Services/SyncScheduler.swift` |
| `Services/FSEventsMonitor.swift` | `DMSASyncService/Services/FSEventsMonitor.swift` |
| `Services/SyncEngine.swift` | `DMSASyncService/Services/SyncEngine.swift` |

#### 3.4 创建 LaunchDaemon 配置

**Resources/com.ttttt.dmsa.sync.plist**:
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

**验收标准**:
- [ ] Sync Service 独立编译成功
- [ ] 定时同步正常运行
- [ ] 接收 VFS 写入通知
- [ ] GUI 退出后同步继续

---

### Phase 4: GUI 重构

#### 4.1 创建 XPC 客户端

**DMSAApp/XPCClients/VFSClient.swift**:
```swift
import Foundation
import DMSAShared

/// VFS 服务 XPC 客户端
public class VFSClient {
    public static let shared = VFSClient()

    private var connection: NSXPCConnection?
    private let connectionLock = NSLock()

    private init() {}

    // MARK: - 连接管理

    private func getConnection() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let existing = connection, existing.isValid {
            return existing
        }

        let newConnection = NSXPCConnection(machServiceName: "com.ttttt.dmsa.vfs")
        newConnection.remoteObjectInterface = NSXPCInterface(with: VFSServiceProtocol.self)

        newConnection.invalidationHandler = { [weak self] in
            self?.connectionLock.lock()
            self?.connection = nil
            self?.connectionLock.unlock()
            Logger.shared.warning("VFS Service 连接已断开")
        }

        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    private func getProxy() -> VFSServiceProtocol? {
        return getConnection().remoteObjectProxyWithErrorHandler { error in
            Logger.shared.error("VFS Service 调用失败: \(error)")
        } as? VFSServiceProtocol
    }

    // MARK: - 公开方法

    public func mount(syncPairId: String,
                      localDir: String,
                      externalDir: String,
                      targetDir: String) async throws {

        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.mount(
                syncPairId: syncPairId,
                localDir: localDir,
                externalDir: externalDir,
                targetDir: targetDir
            ) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.vfsError(error ?? "未知错误"))
                }
            }
        }
    }

    public func unmount(syncPairId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.unmount(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.vfsError(error ?? "未知错误"))
                }
            }
        }
    }

    public func getMountStatus(syncPairId: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            getProxy()?.getMountStatus(syncPairId: syncPairId) { mounted, _ in
                continuation.resume(returning: mounted)
            }
        }
    }

    public func getAllMounts() async -> [[String: Any]] {
        return await withCheckedContinuation { continuation in
            getProxy()?.getAllMounts { mounts in
                continuation.resume(returning: mounts)
            }
        }
    }
}
```

**DMSAApp/XPCClients/SyncClient.swift**:
```swift
import Foundation
import DMSAShared

/// Sync 服务 XPC 客户端
public class SyncClient {
    public static let shared = SyncClient()

    private var connection: NSXPCConnection?
    private let connectionLock = NSLock()

    private init() {}

    private func getConnection() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let existing = connection, existing.isValid {
            return existing
        }

        let newConnection = NSXPCConnection(machServiceName: "com.ttttt.dmsa.sync")
        newConnection.remoteObjectInterface = NSXPCInterface(with: SyncServiceProtocol.self)

        newConnection.invalidationHandler = { [weak self] in
            self?.connectionLock.lock()
            self?.connection = nil
            self?.connectionLock.unlock()
        }

        newConnection.resume()
        connection = newConnection
        return newConnection
    }

    private func getProxy() -> SyncServiceProtocol? {
        return getConnection().remoteObjectProxyWithErrorHandler { error in
            Logger.shared.error("Sync Service 调用失败: \(error)")
        } as? SyncServiceProtocol
    }

    // MARK: - 同步控制

    public func syncNow(syncPairId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.syncNow(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.syncError(error ?? "未知错误"))
                }
            }
        }
    }

    public func pauseSync(syncPairId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.pauseSync(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.syncError(error ?? "未知错误"))
                }
            }
        }
    }

    public func resumeSync(syncPairId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            getProxy()?.resumeSync(syncPairId: syncPairId) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: DMSAError.syncError(error ?? "未知错误"))
                }
            }
        }
    }

    // MARK: - 状态查询

    public func getSyncStatus(syncPairId: String) async -> [String: Any] {
        return await withCheckedContinuation { continuation in
            getProxy()?.getSyncStatus(syncPairId: syncPairId) { status in
                continuation.resume(returning: status)
            }
        }
    }

    public func getSyncProgress(syncPairId: String) async -> [String: Any]? {
        return await withCheckedContinuation { continuation in
            getProxy()?.getSyncProgress(syncPairId: syncPairId) { progress in
                continuation.resume(returning: progress)
            }
        }
    }

    public func getSyncHistory(syncPairId: String, limit: Int) async -> [[String: Any]] {
        return await withCheckedContinuation { continuation in
            getProxy()?.getSyncHistory(syncPairId: syncPairId, limit: limit) { history in
                continuation.resume(returning: history)
            }
        }
    }

    // MARK: - 硬盘事件

    public func diskConnected(diskName: String, mountPoint: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            getProxy()?.diskConnected(diskName: diskName, mountPoint: mountPoint) { success in
                continuation.resume(returning: success)
            }
        }
    }

    public func diskDisconnected(diskName: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            getProxy()?.diskDisconnected(diskName: diskName) { success in
                continuation.resume(returning: success)
            }
        }
    }
}
```

#### 4.2 更新 AppDelegate

**AppDelegate.swift 修改**:
```swift
import Cocoa
import DMSAShared

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarManager: MenuBarManager?
    private var diskManager: DiskManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 初始化日志
        Logger.shared.info("DMSA v4.0 启动 (GUI)")

        // 检查并安装系统服务
        Task {
            await ensureServicesInstalled()
        }

        // 初始化菜单栏
        menuBarManager = MenuBarManager()

        // 初始化硬盘监控 (用于通知服务)
        diskManager = DiskManager()
        diskManager?.delegate = self
        diskManager?.startMonitoring()

        Logger.shared.info("DMSA GUI 初始化完成")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.info("DMSA GUI 退出 (服务继续运行)")
    }

    private func ensureServicesInstalled() async {
        // 检查 VFS Service
        let vfsVersion = await VFSClient.shared.getVersion()
        if vfsVersion == nil {
            Logger.shared.warning("VFS Service 未安装，提示用户安装")
            await showServiceInstallPrompt()
        }

        // 检查 Sync Service
        let syncVersion = await SyncClient.shared.getVersion()
        if syncVersion == nil {
            Logger.shared.warning("Sync Service 未安装，提示用户安装")
            await showServiceInstallPrompt()
        }
    }

    private func showServiceInstallPrompt() async {
        // 显示安装提示对话框
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "需要安装系统服务"
            alert.informativeText = "DMSA 需要安装系统服务才能正常运行。点击安装后需要输入管理员密码。"
            alert.addButton(withTitle: "安装")
            alert.addButton(withTitle: "稍后")

            if alert.runModal() == .alertFirstButtonReturn {
                Task {
                    await self.installServices()
                }
            }
        }
    }

    private func installServices() async {
        do {
            // 使用 SMAppService (macOS 13+) 或 SMJobBless 安装
            try await ServiceInstaller.install()
            Logger.shared.info("系统服务安装成功")
        } catch {
            Logger.shared.error("系统服务安装失败: \(error)")
        }
    }
}

// MARK: - DiskManagerDelegate

extension AppDelegate: DiskManagerDelegate {

    func diskDidMount(name: String, mountPoint: String) {
        Task {
            // 通知 Sync Service
            _ = await SyncClient.shared.diskConnected(diskName: name, mountPoint: mountPoint)

            // 通知 VFS Service 更新路径
            if let syncPair = ConfigManager.shared.getSyncPair(forDisk: name) {
                try? await VFSClient.shared.updateExternalPath(
                    syncPairId: syncPair.id,
                    newPath: mountPoint + "/" + syncPair.externalSubpath
                )
            }
        }
    }

    func diskDidUnmount(name: String) {
        Task {
            _ = await SyncClient.shared.diskDisconnected(diskName: name)
        }
    }
}
```

#### 4.3 更新 UI 视图

**更新 SyncProgressView.swift**:
```swift
// 将直接调用 SyncEngine 改为通过 SyncClient

struct SyncProgressView: View {
    @State private var progress: SyncProgress?

    var body: some View {
        // ... UI 代码
    }

    private func loadProgress() {
        Task {
            if let progressData = await SyncClient.shared.getSyncProgress(syncPairId: syncPairId) {
                progress = SyncProgress(from: progressData)
            }
        }
    }
}
```

**更新 DashboardView.swift**:
```swift
// 将直接调用 VFSCore 改为通过 VFSClient

struct DashboardView: View {
    @State private var mounts: [MountInfo] = []

    var body: some View {
        // ... UI 代码
    }

    private func loadMounts() {
        Task {
            let mountsData = await VFSClient.shared.getAllMounts()
            mounts = mountsData.map { MountInfo(from: $0) }
        }
    }
}
```

**验收标准**:
- [ ] GUI 通过 XPC 与服务通信
- [ ] 所有 UI 功能正常
- [ ] GUI 退出不影响服务

---

### Phase 5: 部署集成

#### 5.1 更新 Info.plist (主应用)

```xml
<key>SMPrivilegedExecutables</key>
<dict>
    <key>com.ttttt.dmsa.vfs</key>
    <string>identifier "com.ttttt.dmsa.vfs" and anchor apple generic</string>
    <key>com.ttttt.dmsa.sync</key>
    <string>identifier "com.ttttt.dmsa.sync" and anchor apple generic</string>
    <key>com.ttttt.dmsa.helper</key>
    <string>identifier "com.ttttt.dmsa.helper" and anchor apple generic</string>
</dict>
```

#### 5.2 创建服务安装器

**DMSAApp/Services/ServiceInstaller.swift**:
```swift
import Foundation
import ServiceManagement

/// 系统服务安装器
class ServiceInstaller {

    static func install() async throws {
        if #available(macOS 13.0, *) {
            try await installWithSMAppService()
        } else {
            try installWithSMJobBless()
        }
    }

    @available(macOS 13.0, *)
    private static func installWithSMAppService() async throws {
        // VFS Service
        let vfsService = SMAppService.daemon(plistName: "com.ttttt.dmsa.vfs.plist")
        try await vfsService.register()

        // Sync Service
        let syncService = SMAppService.daemon(plistName: "com.ttttt.dmsa.sync.plist")
        try await syncService.register()

        // Helper Service
        let helperService = SMAppService.daemon(plistName: "com.ttttt.dmsa.helper.plist")
        try await helperService.register()
    }

    private static func installWithSMJobBless() throws {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authRef)

        guard status == errSecSuccess, let auth = authRef else {
            throw ServiceInstallerError.authorizationFailed
        }

        defer { AuthorizationFree(auth, []) }

        var error: Unmanaged<CFError>?

        // 安装各个服务
        for service in ["com.ttttt.dmsa.vfs", "com.ttttt.dmsa.sync", "com.ttttt.dmsa.helper"] {
            let success = SMJobBless(
                kSMDomainSystemLaunchd,
                service as CFString,
                auth,
                &error
            )

            if !success {
                throw ServiceInstallerError.installFailed(service, error?.takeRetainedValue())
            }
        }
    }

    static func uninstall() async throws {
        if #available(macOS 13.0, *) {
            let vfsService = SMAppService.daemon(plistName: "com.ttttt.dmsa.vfs.plist")
            try await vfsService.unregister()

            let syncService = SMAppService.daemon(plistName: "com.ttttt.dmsa.sync.plist")
            try await syncService.unregister()
        }
    }
}

enum ServiceInstallerError: Error {
    case authorizationFailed
    case installFailed(String, CFError?)
}
```

#### 5.3 配置 Build Phases

在 Xcode 中为主应用配置:

1. **Copy Files Phase** (Destination: `Contents/Library/LaunchServices`)
   - `com.ttttt.dmsa.vfs`
   - `com.ttttt.dmsa.sync`
   - `com.ttttt.dmsa.helper`

2. **Copy Files Phase** (Destination: `Contents/Resources`)
   - `com.ttttt.dmsa.vfs.plist`
   - `com.ttttt.dmsa.sync.plist`
   - `com.ttttt.dmsa.helper.plist`

#### 5.4 创建迁移工具

**DMSAApp/Services/MigrationManager.swift**:
```swift
import Foundation
import DMSAShared

/// v3.x → v4.0 迁移管理器
class MigrationManager {

    static func checkAndMigrate() async throws {
        let currentVersion = UserDefaults.standard.string(forKey: "lastVersion") ?? "3.x"

        if currentVersion.hasPrefix("3.") {
            Logger.shared.info("检测到 v3.x，开始迁移...")
            try await migrateFromV3()
        }

        UserDefaults.standard.set("4.0", forKey: "lastVersion")
    }

    private static func migrateFromV3() async throws {
        // 1. 备份配置
        let configURL = Constants.configURL
        let backupURL = configURL.deletingLastPathComponent().appendingPathComponent("config.v3.backup.json")
        try? FileManager.default.copyItem(at: configURL, to: backupURL)

        // 2. 迁移配置格式 (如有变化)
        // 当前 v3 和 v4 配置格式兼容，无需转换

        // 3. 迁移数据库 (如 schema 变化)
        // 当前 schema 兼容

        // 4. 清理旧服务 (如果存在)
        // 卸载旧的单一 Helper

        Logger.shared.info("迁移完成")
    }
}
```

**验收标准**:
- [ ] 安装包正确打包所有组件
- [ ] 首次启动提示安装服务
- [ ] 服务正确安装到系统
- [ ] 从 v3.x 升级正常

---

## 6. 代码变更清单

### 6.1 新增文件

| 文件 | 所属模块 | 说明 |
|------|----------|------|
| `DMSAShared/` (目录) | Framework | 共享代码模块 |
| `DMSAVFSService/main.swift` | VFS Service | 服务入口 |
| `DMSAVFSService/VFSServiceDelegate.swift` | VFS Service | XPC 委托 |
| `DMSAVFSService/VFSServiceImplementation.swift` | VFS Service | 协议实现 |
| `DMSASyncService/main.swift` | Sync Service | 服务入口 |
| `DMSASyncService/SyncServiceDelegate.swift` | Sync Service | XPC 委托 |
| `DMSASyncService/SyncServiceImplementation.swift` | Sync Service | 协议实现 |
| `DMSAApp/XPCClients/VFSClient.swift` | GUI | VFS 客户端 |
| `DMSAApp/XPCClients/SyncClient.swift` | GUI | Sync 客户端 |
| `DMSAApp/Services/ServiceInstaller.swift` | GUI | 服务安装器 |
| `DMSAApp/Services/MigrationManager.swift` | GUI | 迁移工具 |
| `Resources/com.ttttt.dmsa.vfs.plist` | 部署 | VFS LaunchDaemon |
| `Resources/com.ttttt.dmsa.sync.plist` | 部署 | Sync LaunchDaemon |

### 6.2 移动文件

| 原路径 | 新路径 |
|--------|--------|
| `Models/*` | `DMSAShared/Models/*` |
| `Utils/Logger.swift` | `DMSAShared/Utils/Logger.swift` |
| `Utils/Constants.swift` | `DMSAShared/Utils/Constants.swift` |
| `Utils/Errors.swift` | `DMSAShared/Utils/Errors.swift` |
| `Utils/PathValidator.swift` | `DMSAShared/Utils/PathValidator.swift` |
| `Services/DatabaseManager.swift` | `DMSAShared/Database/DatabaseManager.swift` |
| `Services/VFS/*` | `DMSAVFSService/Services/VFS/*` |
| `Services/TreeVersionManager.swift` | `DMSAVFSService/Services/TreeVersionManager.swift` |
| `Services/Sync/*` | `DMSASyncService/Services/Sync/*` |
| `Services/SyncEngine.swift` | `DMSASyncService/Services/SyncEngine.swift` |
| `Services/SyncScheduler.swift` | `DMSASyncService/Services/SyncScheduler.swift` |
| `Services/FSEventsMonitor.swift` | `DMSASyncService/Services/FSEventsMonitor.swift` |

### 6.3 修改文件

| 文件 | 修改内容 |
|------|---------|
| `AppDelegate.swift` | 移除直接服务调用，改用 XPC 客户端 |
| `Info.plist` | 添加 `SMPrivilegedExecutables` |
| `VFSCore.swift` | 添加 notify 通知机制 |
| `SyncScheduler.swift` | 添加 notify 监听 |
| `UI/Views/*.swift` | 改用 XPC 客户端获取数据 |

### 6.4 删除文件

| 文件 | 原因 |
|------|------|
| `Services/PrivilegedClient.swift` | 重命名为 `HelperClient.swift` |

---

## 7. 测试计划

### 7.1 单元测试

| 测试项 | 测试内容 |
|--------|---------|
| XPC 协议序列化 | 所有参数类型正确序列化/反序列化 |
| VFSClient | 所有方法正确调用 XPC |
| SyncClient | 所有方法正确调用 XPC |
| PathValidator | 路径白名单/黑名单验证 |

### 7.2 集成测试

| 测试项 | 测试内容 |
|--------|---------|
| VFS 挂载 | 服务进程中正确挂载 FUSE |
| 文件读写 | 通过 VFS 读写文件 |
| 同步触发 | VFS 写入 → Sync 同步 |
| 硬盘连接 | GUI 检测 → 通知服务 |

### 7.3 端到端测试

| 场景 | 预期结果 |
|------|---------|
| GUI 退出 | VFS 保持挂载，同步继续 |
| VFS 服务崩溃 | 自动重启，重新挂载 |
| Sync 服务崩溃 | 自动重启，恢复队列 |
| 系统重启 | 服务自动启动，VFS 自动挂载 |

### 7.4 性能测试

| 测试项 | 指标 |
|--------|------|
| XPC 调用延迟 | < 10ms |
| 文件读取延迟 | < 原架构 +5% |
| 内存占用 | 各进程 < 50MB |

---

## 8. 回滚方案

### 8.1 Phase 回滚

每个 Phase 完成后创建 Git Tag:

```bash
git tag v4.0-phase1-complete
git tag v4.0-phase2-complete
git tag v4.0-phase3-complete
git tag v4.0-phase4-complete
git tag v4.0-release
```

### 8.2 服务回滚

```bash
# 停止新服务
sudo launchctl bootout system /Library/LaunchDaemons/com.ttttt.dmsa.vfs.plist
sudo launchctl bootout system /Library/LaunchDaemons/com.ttttt.dmsa.sync.plist

# 删除新服务
sudo rm /Library/PrivilegedHelperTools/com.ttttt.dmsa.vfs
sudo rm /Library/PrivilegedHelperTools/com.ttttt.dmsa.sync
sudo rm /Library/LaunchDaemons/com.ttttt.dmsa.vfs.plist
sudo rm /Library/LaunchDaemons/com.ttttt.dmsa.sync.plist

# 恢复旧版本
# 从备份恢复配置
mv ~/Library/Application\ Support/DMSA/config.v3.backup.json \
   ~/Library/Application\ Support/DMSA/config.json

# 安装旧版本 DMSA v3.x
```

### 8.3 数据回滚

配置文件自动备份到 `config.v3.backup.json`，数据库 schema 兼容无需回滚。

---

## 9. 风险评估

### 9.1 技术风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| XPC 通信不稳定 | 功能异常 | 低 | 添加重连机制 |
| FUSE 在 root 下行为不同 | VFS 异常 | 中 | 充分测试 |
| 服务间状态同步问题 | 数据不一致 | 中 | 使用共享数据库 |
| macOS 版本兼容性 | 部分用户无法使用 | 低 | 支持 11.0+ |

### 9.2 业务风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| 用户不愿授权安装服务 | 无法使用 | 低 | 详细说明必要性 |
| 升级后配置丢失 | 用户体验差 | 低 | 自动备份+迁移 |

### 9.3 安全风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| XPC 连接被劫持 | 权限提升 | 极低 | 代码签名验证 |
| 路径遍历攻击 | 系统文件被修改 | 极低 | 路径白名单 |

---

## 附录

### A. 命令速查

```bash
# 查看服务状态
sudo launchctl list | grep dmsa

# 手动启动服务
sudo launchctl bootstrap system /Library/LaunchDaemons/com.ttttt.dmsa.vfs.plist

# 手动停止服务
sudo launchctl bootout system /Library/LaunchDaemons/com.ttttt.dmsa.vfs.plist

# 查看服务日志
tail -f ~/Library/Logs/DMSA/vfs.log
tail -f ~/Library/Logs/DMSA/sync.log

# 重置服务
sudo launchctl kickstart -k system/com.ttttt.dmsa.vfs
```

### B. 参考文档

- [SYSTEM_ARCHITECTURE.md](./SYSTEM_ARCHITECTURE.md) - 目标架构设计
- [VFS_DESIGN.md](./VFS_DESIGN.md) - VFS 详细设计
- [CLAUDE.md](./CLAUDE.md) - 项目记忆文档

---

*文档版本: 1.0 | 创建日期: 2026-01-24*
