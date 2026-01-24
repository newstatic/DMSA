# DMSAHelper Xcode 项目配置指南

> 此文档说明如何在 Xcode 中配置 SMJobBless 特权助手

---

## 1. 创建 Helper Target

### 1.1 在 Xcode 中添加新 Target

1. 打开 `DMSAApp.xcodeproj`
2. File → New → Target
3. 选择 **macOS → Command Line Tool**
4. 配置:
   - Product Name: `com.ttttt.dmsa.helper`
   - Bundle Identifier: `com.ttttt.dmsa.helper`
   - Language: Swift

### 1.2 添加源文件

将以下文件添加到新 Target:
- `DMSAHelper/DMSAHelper/main.swift`
- `DMSAHelper/DMSAHelper/HelperTool.swift`
- `DMSAHelper/DMSAHelper/DMSAHelperProtocol.swift`

### 1.3 配置 Info.plist

1. 将 `DMSAHelper/DMSAHelper/Info.plist` 设置为 Helper Target 的 Info.plist
2. Build Settings → Packaging → Info.plist File: `DMSAHelper/DMSAHelper/Info.plist`

---

## 2. 配置代码签名

### 2.1 Helper 签名要求

Helper 必须使用开发者证书签名:
- Development: "Apple Development: xxx"
- Distribution: "Developer ID Application: xxx"

### 2.2 Build Settings

```
PRODUCT_NAME = com.ttttt.dmsa.helper
PRODUCT_BUNDLE_IDENTIFIER = com.ttttt.dmsa.helper
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Apple Development / Developer ID Application
INFOPLIST_FILE = DMSAHelper/DMSAHelper/Info.plist
CODE_SIGN_ENTITLEMENTS = DMSAHelper/DMSAHelper/DMSAHelper.entitlements
```

---

## 3. 配置主应用

### 3.1 更新主应用 Info.plist

在 `DMSAApp/DMSAApp/Info.plist` 中添加:

```xml
<key>SMPrivilegedExecutables</key>
<dict>
    <key>com.ttttt.dmsa.helper</key>
    <string>identifier "com.ttttt.dmsa.helper" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: *" or certificate leaf[subject.CN] = "Developer ID Application: *"</string>
</dict>
```

### 3.2 添加 Copy Files Phase

1. 选择主应用 Target
2. Build Phases → 添加 "Copy Files"
3. 配置:
   - Destination: `Wrapper`
   - Subpath: `Contents/Library/LaunchServices`
   - 添加 `com.ttttt.dmsa.helper` 产品

---

## 4. 构建顺序

### 4.1 设置依赖

1. 主应用 Target → Build Phases → Dependencies
2. 添加 `com.ttttt.dmsa.helper` Target

### 4.2 构建顺序

Xcode 会自动按依赖顺序构建:
1. 先构建 Helper
2. 再构建主应用 (包含复制 Helper 到 LaunchServices)

---

## 5. 安装路径

SMJobBless 会将 Helper 安装到:
```
/Library/PrivilegedHelperTools/com.ttttt.dmsa.helper
```

LaunchDaemon plist 会安装到:
```
/Library/LaunchDaemons/com.ttttt.dmsa.helper.plist
```

---

## 6. 调试

### 6.1 查看 Helper 日志

```bash
tail -f /var/log/dmsa-helper.log
```

### 6.2 检查 Helper 状态

```bash
# macOS 13+
sudo launchctl print system/com.ttttt.dmsa.helper

# 旧版
sudo launchctl list | grep dmsa
```

### 6.3 手动卸载 Helper

```bash
sudo launchctl unload /Library/LaunchDaemons/com.ttttt.dmsa.helper.plist
sudo rm /Library/PrivilegedHelperTools/com.ttttt.dmsa.helper
sudo rm /Library/LaunchDaemons/com.ttttt.dmsa.helper.plist
```

---

## 7. 常见问题

### Q: Helper 安装失败

检查:
1. 代码签名是否正确
2. SMAuthorizedClients 和 SMPrivilegedExecutables 是否匹配
3. 主应用是否有管理员权限请求

### Q: XPC 连接失败

检查:
1. Mach 服务名是否一致
2. Helper 是否正在运行
3. 代码签名验证是否通过

### Q: Permission denied

确保:
1. Helper 以 root 权限运行
2. 路径在白名单内
3. 目录存在

---

## 8. 文件清单

```
DMSAHelper/
├── DMSAHelper/
│   ├── main.swift           # 入口点
│   ├── HelperTool.swift     # XPC 服务实现
│   ├── DMSAHelperProtocol.swift  # 共享协议
│   ├── Info.plist           # Helper 配置
│   └── DMSAHelper.entitlements   # 权限
├── Resources/
│   └── com.ttttt.dmsa.helper.plist  # LaunchDaemon
└── SETUP.md                 # 本文档
```

---

*文档版本: 1.0 | 最后更新: 2026-01-24*
