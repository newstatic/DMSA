# Xcode 项目配置更新指南

本指南说明如何将旧的三个服务 (VFS, Sync, Helper) 替换为统一的 DMSAService。

## 概述

**变更前:**
- `com.ttttt.dmsa.vfs` (VFS 服务)
- `com.ttttt.dmsa.sync` (同步服务)
- `com.ttttt.dmsa.helper` (特权助手)

**变更后:**
- `com.ttttt.dmsa.service` (统一服务)

## 步骤 1: 添加新的 DMSAService Target

1. 在 Xcode 中打开 `DMSAApp.xcodeproj`
2. 点击项目导航栏中的项目名称
3. 点击底部的 `+` 按钮添加新 target
4. 选择 **macOS** → **Command Line Tool**
5. 配置:
   - **Product Name**: `com.ttttt.dmsa.service`
   - **Bundle Identifier**: `com.ttttt.dmsa.service`
   - **Language**: Swift

## 步骤 2: 配置 DMSAService Target

选中新创建的 target，在 **Build Settings** 中配置:

### General
- **Deployment Target**: macOS 11.0

### Build Settings
```
PRODUCT_BUNDLE_IDENTIFIER = com.ttttt.dmsa.service
SWIFT_VERSION = 5.0
MACOSX_DEPLOYMENT_TARGET = 11.0
INFOPLIST_FILE = DMSAService/Resources/Info.plist
CODE_SIGN_ENTITLEMENTS = DMSAService/Resources/DMSAService.entitlements
FRAMEWORK_SEARCH_PATHS = $(inherited) /Library/Frameworks
LD_RUNPATH_SEARCH_PATHS = $(inherited) /Library/Frameworks
```

## 步骤 3: 添加源文件到 DMSAService Target

### 3.1 添加 DMSAService 目录

1. 右键项目导航栏 → **Add Files to "DMSAApp"...**
2. 选择 `DMSAApp/DMSAService` 目录
3. 勾选:
   - ☑️ Copy items if needed (取消勾选)
   - ☑️ Create groups
   - Target: 只勾选 `com.ttttt.dmsa.service`

### 3.2 需要添加的文件列表

DMSAService 目录下的所有 Swift 文件:
- `main.swift`
- `ServiceDelegate.swift`
- `ServiceImplementation.swift`
- `VFS/VFSManager.swift`
- `VFS/VFSFileSystem.swift`
- `Sync/SyncManager.swift`
- `Privileged/PrivilegedOperations.swift`

### 3.3 添加 DMSAShared 文件

DMSAService 需要访问共享代码，将以下文件添加到 DMSAService target:

**DMSAShared/Protocols:**
- `DMSAServiceProtocol.swift` ⭐ (新增)
- (其他协议文件可选)

**DMSAShared/Utils:**
- `Constants.swift`
- `Errors.swift`
- `Logger.swift`
- `PathValidator.swift`

**DMSAShared/Models:**
- `Config.swift`
- `FileEntry.swift`
- `SyncHistory.swift`
- `SharedState.swift`
- `Sync/SyncProgress.swift`

### 操作方法:
1. 在项目导航栏展开 DMSAShared
2. 选中需要的文件
3. 在右侧 **File Inspector** 中，找到 **Target Membership**
4. 勾选 `com.ttttt.dmsa.service`

## 步骤 4: 添加 ServiceClient 到主应用

1. 找到 `DMSAApp/Services/ServiceClient.swift`
2. 确保它被添加到 `DMSAApp` target (主应用)
3. 同时确保 `DMSAServiceProtocol.swift` 也添加到主应用 target

## 步骤 5: 更新主应用依赖

1. 选中 `DMSAApp` target
2. 找到 **Build Phases** → **Dependencies**
3. 移除:
   - `com.ttttt.dmsa.vfs`
   - `com.ttttt.dmsa.sync`
   - `com.ttttt.dmsa.helper`
4. 添加:
   - `com.ttttt.dmsa.service`

## 步骤 6: 更新 Copy Files Phase

1. 在 DMSAApp target 的 **Build Phases** 中
2. 找到或创建 **Copy Files** phase:
   - Destination: `Wrapper`
   - Subpath: `Contents/Library/LaunchServices`
3. 移除:
   - `com.ttttt.dmsa.vfs`
   - `com.ttttt.dmsa.sync`
   - `com.ttttt.dmsa.helper`
4. 添加:
   - `com.ttttt.dmsa.service`

## 步骤 7: 更新 Info.plist (主应用)

在主应用的 `Info.plist` 中更新 `SMPrivilegedExecutables`:

```xml
<key>SMPrivilegedExecutables</key>
<dict>
    <key>com.ttttt.dmsa.service</key>
    <string>identifier "com.ttttt.dmsa.service" and anchor apple generic</string>
</dict>
```

移除旧的条目:
- `com.ttttt.dmsa.vfs`
- `com.ttttt.dmsa.sync`
- `com.ttttt.dmsa.helper`

## 步骤 8: 编译验证

1. 选择 **Product** → **Clean Build Folder** (⇧⌘K)
2. 选择 `DMSAApp` scheme
3. 编译 (⌘B)
4. 检查是否有编译错误

## 步骤 9: 删除旧 Targets (可选)

确认新配置正常后，可以删除旧的 targets:

1. 选中项目
2. 右键点击旧 target → **Delete**
3. 删除:
   - `com.ttttt.dmsa.vfs`
   - `com.ttttt.dmsa.sync`
   - `com.ttttt.dmsa.helper`

## 文件位置参考

```
DMSAApp/
├── DMSAApp.xcodeproj/
├── DMSAApp/                    # 主应用
│   └── Services/
│       └── ServiceClient.swift  # 新增 XPC 客户端
├── DMSAService/                # 新增统一服务
│   ├── main.swift
│   ├── ServiceDelegate.swift
│   ├── ServiceImplementation.swift
│   ├── VFS/
│   ├── Sync/
│   ├── Privileged/
│   └── Resources/
│       ├── Info.plist
│       ├── DMSAService.entitlements
│       └── com.ttttt.dmsa.service.plist
└── DMSAShared/                 # 共享代码
    ├── Protocols/
    │   └── DMSAServiceProtocol.swift  # 新增
    ├── Utils/
    └── Models/
```

## 常见问题

### Q: 编译时找不到 DMSAServiceProtocol
A: 确保 `DMSAServiceProtocol.swift` 已添加到两个 targets:
   - `com.ttttt.dmsa.service`
   - `DMSAApp`

### Q: 找不到 Logger/Constants 等类型
A: 确保 DMSAShared 的文件已添加到 DMSAService target

### Q: macFUSE 相关错误
A: 检查 Framework Search Paths 是否包含 `/Library/Frameworks`

### Q: 签名错误
A: 在 **Signing & Capabilities** 中配置正确的 Team
