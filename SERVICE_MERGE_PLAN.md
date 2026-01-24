# DMSA 服务合并计划

> 将 VFS Service + Sync Service + Helper Service 合并为单一 DMSAService
> 创建日期: 2026-01-24
> 状态: 待执行

---

## 1. 背景与目标

### 1.1 当前架构 (4 进程)

```
┌─────────────────┐
│    DMSAApp      │  ← GUI 进程
└────────┬────────┘
         │ XPC
    ┌────┴────┬──────────┐
    ▼         ▼          ▼
┌───────┐ ┌───────┐ ┌────────┐
│  VFS  │ │ Sync  │ │ Helper │
│Service│ │Service│ │Service │
└───────┘ └───────┘ └────────┘
  独立进程   独立进程   独立进程(root)
```

**问题:**
- 3 个独立服务进程，架构复杂
- VFS 和 Sync 需要频繁 IPC 通信
- 部署和调试困难
- 资源占用较高

### 1.2 目标架构 (2 进程)

```
┌─────────────────┐
│    DMSAApp      │  ← GUI 进程 (SwiftUI)
└────────┬────────┘
         │ XPC (NSXPCConnection)
         ▼
┌─────────────────┐
│  DMSAService    │  ← 单一后台服务 (LaunchDaemon, root)
│  ├─ VFS 管理     │     Service ID: com.ttttt.dmsa.service
│  ├─ 同步引擎     │
│  └─ 特权操作     │
└─────────────────┘
```

**优势:**
- 只有 2 个进程，架构简单
- VFS↔Sync 直接函数调用，无 IPC 开销
- 部署更简单（单一 LaunchDaemon）
- root 权限可执行所有操作

---

## 2. Code Review 发现

### 2.1 各模块状态

| 模块 | 完成度 | 关键问题 |
|------|--------|----------|
| **VFS Service** | 60% | macFUSE 集成未完成；audit token 未实现 |
| **Sync Service** | 40% | 待处理任务无持久化；同步逻辑有竞态条件 |
| **Helper Service** | 85% | 生产就绪，ACL 检测依赖 ls 输出格式 |
| **Shared 模块** | 90% | 设计良好，XPC 协议清晰 |

### 2.2 严重问题 (必须修复)

| 问题 | 影响 | 位置 |
|------|------|------|
| macFUSE 集成未实现 | VFS 无法工作 | `VFSFileSystem.swift` |
| audit token 返回空值 | 生产环境连接验证失败 | `VFSServiceDelegate.swift:148-153` |
| Sync 任务不持久化 | 服务重启丢失所有 pending 任务 | `SyncManager.swift` |
| 重复代码 | 维护困难 | `HelperClient` vs `PrivilegedClient` |

### 2.3 中等问题 (建议修复)

| 问题 | 影响 | 位置 |
|------|------|------|
| ACL 检测依赖 ls 输出 | 不同 locale 可能失败 | `HelperTool.swift:272-273` |
| 用户白名单每次枚举 | 性能问题 | `HelperTool.swift:14-31` |
| Sync 脏文件竞态条件 | 可能丢失文件 | `SyncManager.swift:284-289` |
| 配置加载无重试 | 配置损坏时静默失败 | `SyncServiceImplementation.swift:17-30` |

---

## 3. 执行计划

### 阶段 1: 准备工作 (预计 2 小时)

#### 1.1 创建目录结构
```bash
mkdir -p DMSAApp/DMSAService/{VFS,Sync,Privileged}
```

#### 1.2 创建统一 XPC 协议
- 文件: `DMSAShared/Protocols/DMSAServiceProtocol.swift`
- 合并 VFSServiceProtocol + SyncServiceProtocol + HelperProtocol
- Service ID: `com.ttttt.dmsa.service`

#### 1.3 清理重复代码
- 删除: `DMSAApp/XPCClients/HelperClient.swift`
- 删除: `DMSAApp/XPCClients/VFSClient.swift`
- 删除: `DMSAApp/XPCClients/SyncClient.swift`
- 重命名: `PrivilegedClient.swift` → `ServiceClient.swift`

---

### 阶段 2: 合并服务代码 (预计 4 小时)

#### 2.1 创建服务入口
- 文件: `DMSAService/main.swift`
- 功能: 目录初始化、信号处理、XPC 监听器启动

```swift
// main.swift 骨架
import Foundation

let logger = Logger.forService("DMSAService")
logger.info("DMSAService 启动中...")

// 1. 创建目录
setupDirectories()

// 2. 信号处理
setupSignalHandlers()

// 3. XPC 监听
let delegate = ServiceDelegate()
let listener = NSXPCListener(machServiceName: Constants.XPCService.service)
listener.delegate = delegate
listener.resume()

// 4. 自动挂载 VFS
Task { await delegate.autoMount() }

// 5. 启动同步调度器
Task { await delegate.startScheduler() }

RunLoop.main.run()
```

#### 2.2 创建统一委托
- 文件: `DMSAService/ServiceDelegate.swift`
- 功能: XPC 连接管理、代码签名验证

#### 2.3 创建统一实现
- 文件: `DMSAService/ServiceImplementation.swift`
- 实现: `DMSAServiceProtocol`
- 集成: VFSManager + SyncManager + PrivilegedOperations

#### 2.4 迁移 VFS 核心
```
源文件:
  - DMSAVFSService/Services/VFS/VFSManager.swift
  - DMSAVFSService/Services/VFS/VFSFileSystem.swift

目标:
  - DMSAService/VFS/VFSManager.swift
  - DMSAService/VFS/VFSFileSystem.swift
```

#### 2.5 迁移 Sync 核心
```
源文件:
  - DMSASyncService/Services/Sync/SyncManager.swift

目标:
  - DMSAService/Sync/SyncManager.swift
```

#### 2.6 迁移 Helper 操作
```
源文件:
  - DMSAHelper/DMSAHelper/HelperTool.swift (提取特权操作逻辑)

目标:
  - DMSAService/Privileged/PrivilegedOperations.swift
```

---

### 阶段 3: 更新 Xcode 项目 (预计 2 小时)

#### 3.1 创建新 Target
- Target 名称: `com.ttttt.dmsa.service`
- 类型: Command Line Tool
- 部署目标: macOS 13.0

#### 3.2 删除旧 Targets
- `com.ttttt.dmsa.vfs`
- `com.ttttt.dmsa.sync`
- `com.ttttt.dmsa.helper`

#### 3.3 更新 DMSAApp 依赖
- 移除对旧 targets 的依赖
- 添加对 `com.ttttt.dmsa.service` 的依赖
- 更新 Build Phase: Copy Files

#### 3.4 创建 LaunchDaemon 配置
- 文件: `Resources/com.ttttt.dmsa.service.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ttttt.dmsa.service</string>
    <key>BundleIdentifier</key>
    <string>com.ttttt.dmsa.service</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/com.ttttt.dmsa.service</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>com.ttttt.dmsa.service</key>
        <true/>
    </dict>
    <key>UserName</key>
    <string>root</string>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>/var/log/dmsa-service.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/dmsa-service.log</string>
</dict>
</plist>
```

#### 3.5 更新 Info.plist
- 更新 `SMPrivilegedExecutables`:
```xml
<key>SMPrivilegedExecutables</key>
<dict>
    <key>com.ttttt.dmsa.service</key>
    <string>identifier "com.ttttt.dmsa.service" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: ..."</string>
</dict>
```

---

### 阶段 4: 修复关键问题 (预计 3 小时)

#### 4.1 实现 audit token 提取 (高优先级)
- 位置: `ServiceDelegate.swift`
- 方法: 使用 `xpc_connection_get_audit_token()` 或私有 API

```swift
// 正确的 audit token 获取
extension NSXPCConnection {
    var auditToken: audit_token_t {
        // 使用 Mirror 或 ObjC runtime 获取私有属性
        // 或使用 xpc_connection_get_audit_token (需要底层 XPC)
    }
}
```

#### 4.2 添加 Sync 任务持久化 (高优先级)
- 位置: `SyncManager.swift`
- 方案: 将 pending 任务写入 SQLite/JSON 文件
- 恢复: 服务启动时加载未完成任务

```swift
// 任务持久化
func persistPendingTasks() {
    let data = try JSONEncoder().encode(pendingTasks)
    try data.write(to: Constants.Paths.pendingTasksFile)
}

func loadPendingTasks() -> [SyncTask] {
    guard let data = try? Data(contentsOf: Constants.Paths.pendingTasksFile) else {
        return []
    }
    return (try? JSONDecoder().decode([SyncTask].self, from: data)) ?? []
}
```

#### 4.3 修复 ACL 检测 (中优先级)
- 位置: `PrivilegedOperations.swift`
- 方案: 使用 `acl_get_file()` syscall 替代解析 `ls` 输出

#### 4.4 缓存用户白名单 (中优先级)
- 位置: `PrivilegedOperations.swift`
- 方案: 启动时枚举一次，缓存结果

---

### 阶段 5: 清理 (预计 1 小时)

#### 5.1 删除旧服务目录
```bash
rm -rf DMSAApp/DMSAVFSService/
rm -rf DMSAApp/DMSASyncService/
rm -rf DMSAHelper/  # 保留 plist 作为参考
```

#### 5.2 更新 Constants.swift
```swift
enum XPCService {
    // 旧的 (删除)
    // static let vfs = "com.ttttt.dmsa.vfs"
    // static let sync = "com.ttttt.dmsa.sync"
    // static let helper = "com.ttttt.dmsa.helper"

    // 新的
    static let service = "com.ttttt.dmsa.service"
}
```

#### 5.3 删除旧协议文件
```bash
rm DMSAShared/Protocols/VFSServiceProtocol.swift
rm DMSAShared/Protocols/SyncServiceProtocol.swift
rm DMSAShared/Protocols/HelperProtocol.swift
```

#### 5.4 更新 CLAUDE.md
- 更新架构图
- 更新文件路径
- 添加合并记录

---

### 阶段 6: 验证 (预计 1 小时)

#### 6.1 编译验证
```bash
xcodebuild -scheme DMSAApp -configuration Debug build
xcodebuild -scheme "com.ttttt.dmsa.service" -configuration Debug build
```

#### 6.2 XPC 连接测试
- 启动服务
- 从主应用连接
- 验证代码签名验证

#### 6.3 功能测试
- [ ] VFS 挂载/卸载
- [ ] 文件同步
- [ ] 目录保护/解保护
- [ ] 磁盘连接/断开事件

---

## 4. 新文件结构

```
DMSAApp/
├── DMSAApp.xcodeproj/
├── DMSAService/                           # 新统一服务
│   ├── main.swift                         # 入口点
│   ├── ServiceDelegate.swift              # XPC 委托
│   ├── ServiceImplementation.swift        # 协议实现
│   ├── VFS/
│   │   ├── VFSManager.swift               # VFS 管理 (actor)
│   │   └── VFSFileSystem.swift            # FUSE 文件系统
│   ├── Sync/
│   │   └── SyncManager.swift              # 同步管理 (actor)
│   ├── Privileged/
│   │   └── PrivilegedOperations.swift     # 特权操作
│   ├── Info.plist
│   └── DMSAService.entitlements
│
├── DMSAShared/
│   ├── Protocols/
│   │   └── DMSAServiceProtocol.swift      # 统一 XPC 协议
│   ├── Models/
│   │   ├── Config.swift
│   │   ├── FileEntry.swift
│   │   ├── SharedState.swift
│   │   └── Sync/
│   │       ├── SyncHistory.swift
│   │       └── SyncProgress.swift
│   └── Utils/
│       ├── Constants.swift
│       ├── Logger.swift
│       ├── Errors.swift
│       └── PathValidator.swift
│
├── DMSAApp/
│   ├── App/
│   ├── Models/
│   ├── Services/
│   ├── UI/
│   ├── Utils/
│   └── XPCClients/
│       ├── ServiceClient.swift            # 统一 XPC 客户端
│       └── XPCClientTypes.swift           # 响应类型
│
└── Resources/
    └── com.ttttt.dmsa.service.plist       # LaunchDaemon 配置
```

---

## 5. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| macFUSE 集成复杂 | 高 | 优先完成 FUSE 挂载，其他功能后补 |
| 合并过程中编译错误 | 中 | 分步骤执行，每步验证编译 |
| XPC 协议不兼容 | 中 | 使用版本号，支持协议协商 |
| 数据丢失 | 高 | 合并前备份现有代码 |

---

## 6. 时间估算

| 阶段 | 预计时间 |
|------|----------|
| 阶段 1: 准备工作 | 2 小时 |
| 阶段 2: 合并服务代码 | 4 小时 |
| 阶段 3: 更新 Xcode 项目 | 2 小时 |
| 阶段 4: 修复关键问题 | 3 小时 |
| 阶段 5: 清理 | 1 小时 |
| 阶段 6: 验证 | 1 小时 |
| **总计** | **13 小时** |

---

## 7. 检查清单

### 合并前
- [ ] 备份现有代码 (`git stash` 或新分支)
- [ ] 确认所有 targets 当前可编译
- [ ] 记录当前服务 ID 和配置

### 合并中
- [ ] 阶段 1 完成
- [ ] 阶段 2 完成
- [ ] 阶段 3 完成
- [ ] 阶段 4 完成
- [ ] 阶段 5 完成

### 合并后
- [ ] 所有 targets 编译成功
- [ ] XPC 连接正常
- [ ] VFS 挂载/卸载正常
- [ ] 同步功能正常
- [ ] 特权操作正常
- [ ] 更新 CLAUDE.md

---

*文档版本: 1.0*
*最后更新: 2026-01-24*
