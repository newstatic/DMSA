# FSKit Migration Plan

> DMSA: macFUSE → FSKit 完整迁移方案
> 方案 B: ~/Downloads → /Volumes/DMSA (symlink)
> 版本: 1.0 | 日期: 2026-02-03

---

## 一、执行摘要

将 DMSA 从 macFUSE (C libfuse) 迁移到 Apple 原生 FSKit 框架，彻底移除第三方内核扩展依赖。

**核心变更：**
- 挂载点从 `~/Downloads` 改为 `/Volumes/DMSA`
- 创建 symlink: `~/Downloads → /Volumes/DMSA`
- 完全使用 Swift 实现 VFS 层（删除 C 代码）
- 新增 App Extension target: `DMSAFSExtension.appex`

---

## 二、架构对比

### 2.1 当前架构 (macFUSE)

```
┌─────────────────────────────────────────────────────────────┐
│                        User Space                            │
│                                                              │
│  DMSAService (LaunchDaemon, root)                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  VFSManager.swift                                    │    │
│  │       ↓                                              │    │
│  │  FUSEFileSystem.swift (Swift wrapper)               │    │
│  │       ↓                                              │    │
│  │  fuse_wrapper.c (1527 lines, C libfuse)             │    │
│  └─────────────────────────────────────────────────────┘    │
│                          ↓                                   │
└──────────────────────────┼───────────────────────────────────┘
                           ↓
┌──────────────────────────┼───────────────────────────────────┐
│                    Kernel Space                              │
│                          ↓                                   │
│  macFUSE.kext (third-party kernel extension)                │
│                          ↓                                   │
│  VFS Layer → Mount at ~/Downloads                           │
└──────────────────────────────────────────────────────────────┘
```

### 2.2 目标架构 (FSKit)

```
┌─────────────────────────────────────────────────────────────┐
│                        User Space                            │
│                                                              │
│  DMSAFSExtension.appex (App Extension, sandboxed)           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  DMSAFileSystem.swift  (FSUnaryFileSystem)          │    │
│  │       ↓                                              │    │
│  │  DMSAVolume.swift      (FSVolume + all *Operations) │    │
│  │       ↓                                              │    │
│  │  DMSAItem.swift        (FSItem wrapper)             │    │
│  └─────────────────────────────────────────────────────┘    │
│                          ↓ XPC                               │
│  DMSAService (LaunchDaemon, root)                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  VFSManager.swift (orchestrates extension)           │    │
│  │  EvictionManager.swift (no fuse_wrapper calls)       │    │
│  │  Index, Sync, Database (unchanged)                   │    │
│  └─────────────────────────────────────────────────────┘    │
│                          ↓                                   │
└──────────────────────────┼───────────────────────────────────┘
                           ↓
┌──────────────────────────┼───────────────────────────────────┐
│                    Kernel Space (Apple)                      │
│                          ↓                                   │
│  FSKit.framework (system built-in, no kext)                 │
│                          ↓                                   │
│  VFS Layer → Mount at /Volumes/DMSA                         │
└──────────────────────────────────────────────────────────────┘

Symlink: ~/Downloads → /Volumes/DMSA
```

---

## 三、文件变更清单

### 3.1 删除的文件 (2 files)

| 文件 | 行数 | 说明 |
|------|------|------|
| `DMSAService/VFS/fuse_wrapper.c` | 1527 | C FUSE 实现，完全删除 |
| `DMSAService/VFS/fuse_wrapper.h` | 162 | C 头文件，完全删除 |

### 3.2 新增的文件 (5 files)

| 文件 | 说明 |
|------|------|
| `DMSAFSExtension/DMSAFileSystem.swift` | FSUnaryFileSystem 子类，扩展入口 |
| `DMSAFSExtension/DMSAVolume.swift` | FSVolume 子类 + 所有 Operations 协议 |
| `DMSAFSExtension/DMSAItem.swift` | FSItem 封装，文件/目录元数据 |
| `DMSAFSExtension/Info.plist` | Extension 配置 |
| `DMSAFSExtension/DMSAFSExtension.entitlements` | FSKit 权限 |

### 3.3 重构的文件 (6 files)

| 文件 | 变更范围 | 说明 |
|------|----------|------|
| `DMSAService/VFS/VFSManager.swift` | **大幅重构** | 挂载流程、symlink 管理、路径常量 |
| `DMSAService/VFS/FUSEFileSystem.swift` | **删除或重写** | C 桥接层不再需要，改为 FSKit 通信 |
| `DMSAService/VFS/EvictionManager.swift` | **中等修改** | 移除 `fuse_wrapper_mark/unmark_evicting()` 调用 |
| `DMSAApp/Services/VFS/FUSEManager.swift` | **删除** | macFUSE 检测不再需要 |
| `DMSAShared/Utils/Constants.swift` | **小幅修改** | 路径常量更新 |
| `DMSAApp.xcodeproj/project.pbxproj` | **修改** | 添加新 target，移除 C 文件 |

---

## 四、实现细节

### 4.1 DMSAFileSystem.swift (扩展入口)

```swift
import FSKit

@main
final class DMSAFileSystem: FSUnaryFileSystem, FSUnaryFileSystemOperations {

    required init() {
        super.init()
    }

    // MARK: - FSUnaryFileSystemOperations

    func probeResource(_ resource: FSResource,
                       replyHandler: @escaping (FSProbeResult?, Error?) -> Void) {
        // DMSA 是虚拟文件系统，不检测物理设备
        // 直接返回 recognized
        let result = FSProbeResult(result: .recognized, name: "DMSA")
        replyHandler(result, nil)
    }

    func loadResource(_ resource: FSResource,
                      options: FSTaskOptions,
                      replyHandler: @escaping (FSVolume?, Error?) -> Void) {
        // 创建并返回 DMSAVolume 实例
        let volume = DMSAVolume(
            volumeID: FSVolumeIdentifier(),
            volumeName: "DMSA"
        )
        replyHandler(volume, nil)
    }

    func unloadResource(_ resource: FSResource,
                        options: FSTaskOptions,
                        replyHandler: @escaping (Error?) -> Void) {
        replyHandler(nil)
    }

    func didFinishLoading() {
        // 初始化完成后的回调
        print("[DMSAFileSystem] Extension loaded")
    }
}
```

### 4.2 DMSAVolume.swift (核心逻辑)

```swift
import FSKit

final class DMSAVolume: FSVolume {

    // Backend directories
    private var localDir: String = ""
    private var externalDir: String?
    private var isExternalOnline: Bool = false

    // Eviction exclude set (replaces C g_evicting)
    private var evictingPaths: Set<String> = []
    private let evictingLock = NSLock()

    // Index ready state (replaces C g_state.index_ready)
    private var indexReady: Bool = false

    // MARK: - Initialization

    override init(volumeID: FSVolumeIdentifier, volumeName: String) {
        super.init(volumeID: volumeID, volumeName: volumeName)
        loadConfiguration()
    }

    private func loadConfiguration() {
        // Load from ServiceConfigManager via XPC or shared config
        // Set localDir, externalDir, etc.
    }

    // MARK: - Path Resolution (Smart Merge)

    private func resolveActualPath(for virtualPath: String) -> String? {
        let relativePath = virtualPath.hasPrefix("/")
            ? String(virtualPath.dropFirst())
            : virtualPath

        // Check eviction exclude list
        evictingLock.lock()
        let isEvicting = evictingPaths.contains(virtualPath)
        evictingLock.unlock()

        // If not evicting, check LOCAL first
        if !isEvicting {
            let localPath = (localDir as NSString).appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: localPath) {
                return localPath
            }
        }

        // Then check EXTERNAL
        if isExternalOnline, let extDir = externalDir {
            let externalPath = (extDir as NSString).appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: externalPath) {
                return externalPath
            }
        }

        return nil
    }

    // MARK: - Eviction Support

    func markEvicting(_ virtualPath: String) {
        evictingLock.lock()
        evictingPaths.insert(virtualPath)
        evictingLock.unlock()
    }

    func unmarkEvicting(_ virtualPath: String) {
        evictingLock.lock()
        evictingPaths.remove(virtualPath)
        evictingLock.unlock()
    }
}

// MARK: - FSVolumeOperations

extension DMSAVolume: FSVolume.Operations {

    func lookupItem(name: FSFileName,
                    inDirectory directory: FSItem,
                    replyHandler: @escaping (FSItem?, FSItemAttributes?, Error?) -> Void) {
        // Block access if index not ready
        guard indexReady else {
            replyHandler(nil, nil, POSIXError(.EBUSY))
            return
        }

        let virtualPath = buildVirtualPath(directory: directory, name: name)
        guard let actualPath = resolveActualPath(for: virtualPath) else {
            replyHandler(nil, nil, POSIXError(.ENOENT))
            return
        }

        // Get attributes
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: actualPath) else {
            replyHandler(nil, nil, POSIXError(.EIO))
            return
        }

        let item = DMSAItem(virtualPath: virtualPath)
        let fsAttrs = buildFSItemAttributes(from: attrs)

        replyHandler(item, fsAttrs, nil)
    }

    func enumerateDirectory(_ directory: FSItem,
                            startingAt cookie: FSDirectoryCookie,
                            verifier: FSDirectoryVerifier,
                            attributes: FSItemGetAttributesRequest?,
                            packer: FSDirectoryEntryPacker,
                            replyHandler: @escaping (FSDirectoryVerifier?, Error?) -> Void) {
        // Smart Merge: LOCAL ∪ EXTERNAL
        guard indexReady else {
            replyHandler(nil, POSIXError(.EBUSY))
            return
        }

        var seenNames: Set<String> = []
        let virtualPath = (directory as? DMSAItem)?.virtualPath ?? "/"

        // Enumerate LOCAL
        let localPath = buildLocalPath(for: virtualPath)
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: localPath) {
            for name in contents {
                if shouldExclude(name: name) { continue }
                if seenNames.contains(name) { continue }
                seenNames.insert(name)

                let entry = FSFileName(string: name)
                _ = packer.addEntry(name: entry, attributes: nil, cookie: FSDirectoryCookie())
            }
        }

        // Enumerate EXTERNAL (if online)
        if isExternalOnline, let extDir = externalDir {
            let externalPath = buildExternalPath(for: virtualPath)
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: externalPath) {
                for name in contents {
                    if shouldExclude(name: name) { continue }
                    if seenNames.contains(name) { continue }
                    seenNames.insert(name)

                    let entry = FSFileName(string: name)
                    _ = packer.addEntry(name: entry, attributes: nil, cookie: FSDirectoryCookie())
                }
            }
        }

        replyHandler(verifier, nil)
    }

    func createItem(name: FSFileName,
                    type: FSItemType,
                    inDirectory directory: FSItem,
                    attributes: FSItemSetAttributesRequest?,
                    replyHandler: @escaping (FSItem?, FSItemAttributes?, Error?) -> Void) {
        // Always create in LOCAL
        let virtualPath = buildVirtualPath(directory: directory, name: name)
        let localPath = buildLocalPath(for: virtualPath)

        // Ensure parent exists
        let parentPath = (localPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentPath,
                                                  withIntermediateDirectories: true)

        switch type {
        case .regular:
            FileManager.default.createFile(atPath: localPath, contents: nil)
        case .directory:
            try? FileManager.default.createDirectory(atPath: localPath,
                                                      withIntermediateDirectories: false)
        default:
            replyHandler(nil, nil, POSIXError(.EINVAL))
            return
        }

        let item = DMSAItem(virtualPath: virtualPath)
        let attrs = FSItemAttributes()  // Build from file
        replyHandler(item, attrs, nil)
    }

    func removeItem(_ item: FSItem,
                    name: FSFileName,
                    fromDirectory directory: FSItem,
                    replyHandler: @escaping (Error?) -> Void) {
        let virtualPath = (item as? DMSAItem)?.virtualPath ?? ""

        // Delete from LOCAL
        let localPath = buildLocalPath(for: virtualPath)
        try? FileManager.default.removeItem(atPath: localPath)

        // Delete from EXTERNAL (if online)
        if isExternalOnline, let _ = externalDir {
            let externalPath = buildExternalPath(for: virtualPath)
            try? FileManager.default.removeItem(atPath: externalPath)
        }

        replyHandler(nil)
    }

    func renameItem(_ item: FSItem,
                    inDirectory sourceDirectory: FSItem,
                    named sourceName: FSFileName,
                    toDirectory destinationDirectory: FSItem,
                    newName destinationName: FSFileName,
                    overItem: FSItem?,
                    replyHandler: @escaping (FSItem?, FSItemAttributes?, Error?) -> Void) {
        // Rename in LOCAL, then EXTERNAL
        // Similar to fuse_wrapper.c dmsa_rename
        // ...
        replyHandler(nil, nil, nil)
    }
}

// MARK: - FSVolumeReadWriteOperations

extension DMSAVolume: FSVolume.ReadWriteOperations {

    func readFromFile(_ item: FSItem,
                      offset: UInt64,
                      length: Int,
                      intoBuffer buffer: UnsafeMutableRawBufferPointer,
                      replyHandler: @escaping (Int, Error?) -> Void) {
        guard let dmsaItem = item as? DMSAItem else {
            replyHandler(0, POSIXError(.EINVAL))
            return
        }

        guard let actualPath = resolveActualPath(for: dmsaItem.virtualPath) else {
            replyHandler(0, POSIXError(.ENOENT))
            return
        }

        guard let handle = FileHandle(forReadingAtPath: actualPath) else {
            replyHandler(0, POSIXError(.EIO))
            return
        }
        defer { try? handle.close() }

        try? handle.seek(toOffset: offset)
        guard let data = try? handle.read(upToCount: length) else {
            replyHandler(0, POSIXError(.EIO))
            return
        }

        data.copyBytes(to: buffer)
        replyHandler(data.count, nil)
    }

    func writeToFile(_ item: FSItem,
                     offset: UInt64,
                     fromBuffer buffer: UnsafeRawBufferPointer,
                     replyHandler: @escaping (Int, Error?) -> Void) {
        guard let dmsaItem = item as? DMSAItem else {
            replyHandler(0, POSIXError(.EINVAL))
            return
        }

        // Write always goes to LOCAL
        let localPath = buildLocalPath(for: dmsaItem.virtualPath)

        // If file only exists in EXTERNAL, copy to LOCAL first
        if !FileManager.default.fileExists(atPath: localPath) {
            if let externalPath = buildExternalPath(for: dmsaItem.virtualPath),
               FileManager.default.fileExists(atPath: externalPath) {
                try? FileManager.default.copyItem(atPath: externalPath, toPath: localPath)
            }
        }

        guard let handle = FileHandle(forWritingAtPath: localPath) else {
            replyHandler(0, POSIXError(.EIO))
            return
        }
        defer { try? handle.close() }

        try? handle.seek(toOffset: offset)
        let data = Data(buffer)
        try? handle.write(contentsOf: data)

        replyHandler(data.count, nil)
    }
}

// MARK: - FSVolumeOpenCloseOperations

extension DMSAVolume: FSVolume.OpenCloseOperations {

    func openItem(_ item: FSItem,
                  modes: FSOpenModes,
                  replyHandler: @escaping (Error?) -> Void) {
        // Open validation
        replyHandler(nil)
    }

    func closeItem(_ item: FSItem,
                   modes: FSOpenModes,
                   replyHandler: @escaping (Error?) -> Void) {
        // Close cleanup
        replyHandler(nil)
    }
}

// MARK: - FSVolumeXAttributes

extension DMSAVolume: FSVolume.XAttributes {

    func getXattr(item: FSItem,
                  name: String,
                  replyHandler: @escaping (Data?, Error?) -> Void) {
        guard let dmsaItem = item as? DMSAItem,
              let actualPath = resolveActualPath(for: dmsaItem.virtualPath) else {
            replyHandler(nil, POSIXError(.ENOENT))
            return
        }

        // Read xattr
        let data = try? (actualPath as NSString).extendedAttribute(forName: name)
        replyHandler(data, nil)
    }

    func setXattr(item: FSItem,
                  name: String,
                  value: Data,
                  policy: FSXattrPolicy,
                  replyHandler: @escaping (Error?) -> Void) {
        // Set xattr on LOCAL
        guard let dmsaItem = item as? DMSAItem else {
            replyHandler(POSIXError(.EINVAL))
            return
        }

        let localPath = buildLocalPath(for: dmsaItem.virtualPath)
        try? (localPath as NSString).setExtendedAttribute(value, forName: name)
        replyHandler(nil)
    }

    func listXattrs(item: FSItem,
                    replyHandler: @escaping ([String]?, Error?) -> Void) {
        guard let dmsaItem = item as? DMSAItem,
              let actualPath = resolveActualPath(for: dmsaItem.virtualPath) else {
            replyHandler(nil, POSIXError(.ENOENT))
            return
        }

        let names = try? (actualPath as NSString).extendedAttributeNames()
        replyHandler(names, nil)
    }

    func removeXattr(item: FSItem,
                     name: String,
                     replyHandler: @escaping (Error?) -> Void) {
        guard let dmsaItem = item as? DMSAItem else {
            replyHandler(POSIXError(.EINVAL))
            return
        }

        let localPath = buildLocalPath(for: dmsaItem.virtualPath)
        try? (localPath as NSString).removeExtendedAttribute(forName: name)
        replyHandler(nil)
    }
}
```

### 4.3 DMSAItem.swift

```swift
import FSKit

/// FSItem wrapper for DMSA virtual files
final class DMSAItem: FSItem {
    let virtualPath: String

    init(virtualPath: String) {
        self.virtualPath = virtualPath
        super.init()
    }
}
```

### 4.4 VFSManager.swift 变更要点

```swift
// ================== 主要变更 ==================

// 1. 挂载点改为 /Volumes/DMSA
private let fskitMountPoint = "/Volumes/DMSA"

// 2. mount() 新增 symlink 管理
func mount(...) async throws {
    // ... 现有逻辑 ...

    // Step 5: FSKit mount (替换 FUSEFileSystem)
    let fsExtension = DMSAFSExtension()
    try await fsExtension.mount(at: fskitMountPoint)

    // Step 6: Create symlink ~/Downloads → /Volumes/DMSA
    let symlinkPath = targetDir  // ~/Downloads
    let fm = FileManager.default

    // Remove existing directory/symlink
    if fm.fileExists(atPath: symlinkPath) {
        try fm.removeItem(atPath: symlinkPath)
    }

    // Create symlink
    try fm.createSymbolicLink(atPath: symlinkPath,
                               withDestinationPath: fskitMountPoint)

    // ... 后续步骤 ...
}

// 3. unmount() 移除 symlink
func unmount(...) async throws {
    // Remove symlink first
    let symlinkPath = mountPoint.targetDir
    try? FileManager.default.removeItem(atPath: symlinkPath)

    // Restore original directory
    try FileManager.default.createDirectory(atPath: symlinkPath,
                                             withIntermediateDirectories: true)

    // FSKit unmount
    // ...
}

// 4. 移除 protectBackendDir 对 EXTERNAL 的保护
// FSKit 在 /Volumes 下，用户自然不会直接访问
```

### 4.5 EvictionManager.swift 变更

```swift
// ================== 删除的代码 ==================

// 删除所有 fuse_wrapper_mark_evicting / fuse_wrapper_unmark_evicting 调用
// 改为通过 DMSAVolume 的 Swift 方法

// BEFORE:
entry.virtualPath.withCString { cstr in
    fuse_wrapper_mark_evicting(cstr)
}

// AFTER:
await volume.markEvicting(entry.virtualPath)

// ================== 新增 DMSAVolume 引用 ==================

private weak var volume: DMSAVolume?

func setVolume(_ vol: DMSAVolume) {
    self.volume = vol
}
```

### 4.6 Constants.swift 变更

```swift
public enum Paths {
    // 新增 FSKit 挂载点
    public static var fskitMountPoint: URL {
        URL(fileURLWithPath: "/Volumes/DMSA")
    }

    // virtualDownloads 变为 symlink 目标
    public static var virtualDownloads: URL {
        userHome.appendingPathComponent("Downloads")
        // 实际指向 /Volumes/DMSA
    }
}
```

---

## 五、App Extension 配置

### 5.1 Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ttttt.dmsa.fsextension</string>
    <key>CFBundleDisplayName</key>
    <string>DMSA File System</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.fskit.filesystem</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).DMSAFileSystem</string>
    </dict>
    <key>FSFilesystemType</key>
    <string>dmsa</string>
    <key>FSFilesystemOperatingMode</key>
    <string>unary</string>
    <key>FSPersonalities</key>
    <dict>
        <key>DMSA</key>
        <dict>
            <key>FSPersonalityName</key>
            <string>DMSA Smart Merge Volume</string>
            <key>FSPersonalityUsageDescription</key>
            <string>Virtual filesystem merging local cache and external storage</string>
        </dict>
    </dict>
</dict>
</plist>
```

### 5.2 Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.fskit.allow-unprobed-loading</key>
    <true/>
    <key>com.apple.developer.fskit.non-local</key>
    <true/>
    <key>com.apple.developer.fskit.local</key>
    <true/>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

---

## 六、Xcode Project 变更

### 6.1 新增 Target: DMSAFSExtension

```
DMSAApp/
├── DMSAApp.xcodeproj/
├── DMSAApp/
├── DMSAService/
├── DMSAShared/
└── DMSAFSExtension/           # 新增
    ├── DMSAFileSystem.swift
    ├── DMSAVolume.swift
    ├── DMSAItem.swift
    ├── Info.plist
    └── DMSAFSExtension.entitlements
```

### 6.2 Build Settings

- **Deployment Target**: macOS 15.4+ (FSKit 最低版本)
- **Swift Language Version**: 5.9+
- **Frameworks**: FSKit.framework (Weak Link)

### 6.3 移除的文件

从 DMSAService target 移除：
- `VFS/fuse_wrapper.c`
- `VFS/fuse_wrapper.h`

从 DMSAApp target 移除：
- `Services/VFS/FUSEManager.swift`

---

## 七、迁移步骤

### Phase 1: 准备工作

1. [ ] 创建 `DMSAFSExtension` target
2. [ ] 添加 FSKit.framework
3. [ ] 配置 entitlements 和 Info.plist

### Phase 2: 核心实现

4. [ ] 实现 `DMSAFileSystem.swift`
5. [ ] 实现 `DMSAVolume.swift` (所有 Operations)
6. [ ] 实现 `DMSAItem.swift`
7. [ ] 添加 Extension ↔ Service XPC 通信

### Phase 3: 重构现有代码

8. [ ] 修改 `VFSManager.swift` - 挂载流程 + symlink 管理
9. [ ] 修改 `EvictionManager.swift` - 移除 C 调用
10. [ ] 修改 `Constants.swift` - 路径更新
11. [ ] 删除 `FUSEFileSystem.swift` 或重写为 FSKit 桥接
12. [ ] 删除 `FUSEManager.swift` (App 端)

### Phase 4: 清理

13. [ ] 删除 `fuse_wrapper.c` 和 `fuse_wrapper.h`
14. [ ] 更新 pbxproj 移除 C 文件引用
15. [ ] 移除 macFUSE 相关检测代码

### Phase 5: 测试

16. [ ] 单元测试 FSKit Volume Operations
17. [ ] 集成测试 Smart Merge 逻辑
18. [ ] 测试 symlink 行为 (Finder, Safari 下载等)
19. [ ] 测试卸载后 symlink 恢复

---

## 八、风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| symlink 在部分 App 中失效 | 高 | 测试主流应用 (Safari, Chrome, Finder) |
| FSKit 性能较差 | 中 | 等待 Apple 优化，或限制大文件操作 |
| 卷未挂载时 symlink 悬空 | 中 | 应用启动时检测并处理 |
| Spotlight 不索引 /Volumes | 低 | 可通过 mdutil 配置 |
| App Sandbox 限制 Extension | 中 | 确保正确的 entitlements |

---

## 九、回滚方案

如果 FSKit 迁移失败，可回滚到 macFUSE：

1. 保留 `fuse_wrapper.c/h` 在 git 历史中
2. 恢复 `FUSEFileSystem.swift` 和 `FUSEManager.swift`
3. 移除 DMSAFSExtension target
4. 还原 `VFSManager.swift` 和 `EvictionManager.swift`
5. 还原 `Constants.swift` 路径

---

## 十、参考资料

- [FSKit Apple Documentation](https://developer.apple.com/documentation/fskit)
- [FSKitSample (KhaosT)](https://github.com/KhaosT/FSKitSample)
- [FSKit API Surface (xcode16.3)](https://github.com/dotnet/macios/wiki/FSKit-macOS-xcode16.3-b1)
- [macFUSE FSKit Backend](https://macfuse.github.io/)
- DMSA 现有 FUSE 实现: `DMSAApp/DMSAService/VFS/`

---

*文档版本: 1.0 | 创建日期: 2026-02-03 | 作者: Claude*
