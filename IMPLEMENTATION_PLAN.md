# Delt MACOS Sync App (DMSA) 代码实施计划

> 版本: 2.0 | 更新日期: 2026-01-20

---

## 目录

1. [实施概览](#1-实施概览)
2. [阶段一: 基础架构 (P0-Foundation)](#2-阶段一-基础架构-p0-foundation)
3. [阶段二: 核心功能 (P0-Core)](#3-阶段二-核心功能-p0-core)
4. [阶段三: VFS 实现 (P0-VFS)](#4-阶段三-vfs-实现-p0-vfs)
5. [阶段四: 增强功能 (P1)](#5-阶段四-增强功能-p1)
6. [阶段五: 完善功能 (P2)](#6-阶段五-完善功能-p2)
7. [文件清单](#7-文件清单)
8. [依赖关系图](#8-依赖关系图)
9. [测试计划](#9-测试计划)
10. [风险与缓解](#10-风险与缓解)

---

## 1. 实施概览

### 1.1 实施原则

| 原则 | 说明 |
|------|------|
| 增量交付 | 每个阶段产出可运行的版本 |
| 先核心后增强 | 优先实现同步核心，再添加 VFS |
| 测试驱动 | 关键模块编写单元测试 |
| 文档同步 | 代码变更同步更新文档 |

### 1.2 技术栈确认

```
语言:        Swift 5.5+
最低版本:    macOS 11.0 (Big Sur)
UI 框架:     SwiftUI
数据库:      ObjectBox Swift 1.9+
同步引擎:    rsync (系统内置)
文件监控:    FSEvents / Endpoint Security
构建工具:    Swift Package Manager
```

### 1.3 阶段总览

```
┌─────────────────────────────────────────────────────────────────────┐
│                         实施阶段总览                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  阶段一 ─────▶ 阶段二 ─────▶ 阶段三 ─────▶ 阶段四 ─────▶ 阶段五     │
│  基础架构      核心功能      VFS实现      增强功能      完善功能      │
│                                                                      │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │
│  │项目结构  │  │配置系统  │  │ES扩展   │  │FSEvents │  │统计面板  │   │
│  │基础模型  │  │硬盘管理  │  │读写路由  │  │进度UI   │  │高级过滤  │   │
│  │日志系统  │  │同步引擎  │  │缓存管理  │  │异常保护  │  │导入导出  │   │
│  │菜单栏   │  │基础UI    │  │元数据   │  │自启动   │  │图表展示  │   │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘   │
│                                                                      │
│  MVP ◀────────────────────────────────▶│◀─────────────────────────▶│
│       核心可用版本                        增强版本                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. 阶段一: 基础架构 (P0-Foundation)

### 2.1 目标

搭建项目基础框架，实现最小可运行的菜单栏应用。

### 2.2 任务清单

| 任务ID | 任务 | 输出文件 | 依赖 |
|--------|------|----------|------|
| F-01 | 创建 SPM 项目结构 | `Package.swift` | - |
| F-02 | 配置 Info.plist | `Info.plist` | F-01 |
| F-03 | 配置 Entitlements | `*.entitlements` | F-01 |
| F-04 | 实现应用入口 | `main.swift` | F-01 |
| F-05 | 实现 AppDelegate 框架 | `AppDelegate.swift` | F-04 |
| F-06 | 实现日志系统 | `Logger.swift` | F-01 |
| F-07 | 实现基础菜单栏 | `MenuBarManager.swift` | F-05 |
| F-08 | 定义错误类型 | `Errors.swift` | F-01 |
| F-09 | 定义常量 | `Constants.swift` | F-01 |
| F-10 | 集成 ObjectBox | `Package.swift` 更新 | F-01 |

### 2.3 详细实施

#### F-01: 创建 SPM 项目结构

```
DMSA/
├── Package.swift
├── Sources/
│   └── DMSA/
│       ├── main.swift
│       ├── App/
│       │   └── AppDelegate.swift
│       ├── Core/
│       ├── Services/
│       ├── Models/
│       ├── UI/
│       └── Utils/
├── Tests/
│   └── DMSATests/
└── Resources/
    ├── Info.plist
    └── DMSA.entitlements
```

**Package.swift:**

```swift
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "DMSA",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "DMSA", targets: ["DMSA"])
    ],
    dependencies: [
        .package(url: "https://github.com/objectbox/objectbox-swift", from: "1.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "DMSA",
            dependencies: [
                .product(name: "ObjectBox", package: "objectbox-swift"),
            ],
            path: "Sources/DMSA",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DMSATests",
            dependencies: ["DMSA"],
            path: "Tests/DMSATests"
        ),
    ]
)
```

#### F-06: 日志系统

**Logger.swift:**

```swift
import Foundation
import os.log

/// 日志管理器
final class Logger {
    static let shared = Logger()

    private let subsystem = "com.ttttt.dmsa"
    private let logFileURL: URL
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.ttttt.dmsa.logger")

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    private init() {
        // 日志目录
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DMSA")

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        logFileURL = logsDir.appendingPathComponent("app.log")

        // 创建或打开日志文件
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = FileHandle(forWritingAtPath: logFileURL.path)
        fileHandle?.seekToEndOfFile()

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    func log(_ message: String, level: Level = .info, file: String = #file, line: Int = #line) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let fileName = (file as NSString).lastPathComponent
            let timestamp = self.dateFormatter.string(from: Date())
            let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(message)\n"

            // 控制台输出
            print(logMessage, terminator: "")

            // 文件输出
            if let data = logMessage.data(using: .utf8) {
                self.fileHandle?.write(data)
            }
        }
    }

    func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .debug, file: file, line: line)
    }

    func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .info, file: file, line: line)
    }

    func warn(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .warn, file: file, line: line)
    }

    func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }
}

// 全局快捷方法
func log(_ message: String) {
    Logger.shared.info(message)
}
```

#### F-07: 基础菜单栏

**MenuBarManager.swift:**

```swift
import Cocoa

/// 菜单栏管理器
final class MenuBarManager {
    private var statusItem: NSStatusItem!

    weak var delegate: MenuBarDelegate?

    init() {
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                                   accessibilityDescription: "DMSA")
        }

        updateMenu()
    }

    func updateMenu() {
        let menu = NSMenu()

        // 状态区域
        let statusItem = NSMenuItem(title: "⚪ 未连接外置硬盘", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        // 操作区域
        let syncItem = NSMenuItem(title: "立即同步", action: #selector(handleSync), keyEquivalent: "s")
        syncItem.target = self
        syncItem.isEnabled = false
        menu.addItem(syncItem)

        let openItem = NSMenuItem(title: "打开 Downloads", action: #selector(handleOpenDownloads), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let logItem = NSMenuItem(title: "查看日志", action: #selector(handleOpenLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        // 设置与退出
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(handleSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    func updateIcon(connected: Bool) {
        if let button = statusItem.button {
            let symbolName = connected ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "DMSA")
        }
    }

    // MARK: - Actions

    @objc private func handleSync() {
        delegate?.menuBarDidRequestSync()
    }

    @objc private func handleOpenDownloads() {
        let downloadsPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        NSWorkspace.shared.open(downloadsPath)
    }

    @objc private func handleOpenLog() {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DMSA/app.log")
        NSWorkspace.shared.open(logPath)
    }

    @objc private func handleSettings() {
        delegate?.menuBarDidRequestSettings()
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}

protocol MenuBarDelegate: AnyObject {
    func menuBarDidRequestSync()
    func menuBarDidRequestSettings()
}
```

### 2.4 验收标准

- [ ] 应用可编译运行
- [ ] 菜单栏图标正常显示
- [ ] 日志正常输出到文件
- [ ] 基础菜单项可点击

---

## 3. 阶段二: 核心功能 (P0-Core)

### 3.1 目标

实现配置系统、硬盘管理、同步引擎，完成基础同步功能。

### 3.2 任务清单

| 任务ID | 任务 | 输出文件 | 依赖 |
|--------|------|----------|------|
| C-01 | 定义配置数据模型 | `Models/Config.swift` | F-10 |
| C-02 | 实现配置管理器 | `Services/ConfigManager.swift` | C-01 |
| C-03 | 定义 ObjectBox 实体 | `Models/Entities/*.swift` | F-10 |
| C-04 | 实现数据库管理器 | `Services/DatabaseManager.swift` | C-03 |
| C-05 | 实现硬盘管理器 | `Services/DiskManager.swift` | C-02 |
| C-06 | 实现 rsync 封装 | `Services/RsyncWrapper.swift` | F-06 |
| C-07 | 实现同步引擎 | `Services/SyncEngine.swift` | C-04, C-06 |
| C-08 | 实现同步调度器 | `Services/SyncScheduler.swift` | C-07 |
| C-09 | 实现文件过滤器 | `Services/FileFilter.swift` | C-02 |
| C-10 | 实现基础设置 UI | `UI/SettingsView.swift` | C-02 |
| C-11 | 集成磁盘事件监听 | `AppDelegate.swift` 更新 | C-05 |
| C-12 | 实现通知管理器 | `Services/NotificationManager.swift` | F-06 |

### 3.3 详细实施

#### C-01: 配置数据模型

**Models/Config.swift:**

```swift
import Foundation

/// 应用配置
struct AppConfig: Codable {
    var version: String = "2.0"
    var general: GeneralConfig = GeneralConfig()
    var disks: [DiskConfig] = []
    var syncPairs: [SyncPairConfig] = []
    var filters: FilterConfig = FilterConfig()
    var cache: CacheConfig = CacheConfig()
    var monitoring: MonitoringConfig = MonitoringConfig()
    var notifications: NotificationConfig = NotificationConfig()
    var logging: LoggingConfig = LoggingConfig()
    var ui: UIConfig = UIConfig()
}

struct GeneralConfig: Codable {
    var launchAtLogin: Bool = false
    var showInDock: Bool = false
    var checkForUpdates: Bool = true
    var language: String = "system"
}

struct DiskConfig: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var mountPath: String
    var priority: Int = 0
    var enabled: Bool = true
    var fileSystem: String = "auto"

    var isConnected: Bool {
        FileManager.default.fileExists(atPath: mountPath)
    }
}

struct SyncPairConfig: Codable, Identifiable {
    var id: String = UUID().uuidString
    var diskId: String
    var localPath: String
    var externalRelativePath: String
    var direction: SyncDirection = .localToExternal
    var createSymlink: Bool = true
    var enabled: Bool = true
    var excludePatterns: [String] = []

    /// 计算外置硬盘完整路径
    func externalFullPath(diskMountPath: String) -> String {
        return (diskMountPath as NSString).appendingPathComponent(externalRelativePath)
    }
}

enum SyncDirection: String, Codable, CaseIterable {
    case localToExternal = "local_to_external"
    case externalToLocal = "external_to_local"
    case bidirectional = "bidirectional"

    var displayName: String {
        switch self {
        case .localToExternal: return "本地 → 外置"
        case .externalToLocal: return "外置 → 本地"
        case .bidirectional: return "双向同步"
        }
    }
}

struct FilterConfig: Codable {
    var excludePatterns: [String] = [
        ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
        "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
        "Thumbs.db", "desktop.ini",
        "*.part", "*.crdownload", "*.download"
    ]
    var includePatterns: [String] = ["*"]
    var maxFileSize: Int64? = nil
    var minFileSize: Int64? = nil
    var excludeHidden: Bool = false
}

struct CacheConfig: Codable {
    var maxCacheSize: Int64 = 10 * 1024 * 1024 * 1024  // 10 GB
    var reserveBuffer: Int64 = 500 * 1024 * 1024       // 500 MB
    var evictionCheckInterval: Int = 300               // 5 分钟
    var autoEvictionEnabled: Bool = true
    var evictionStrategy: String = "modified_time"
}

struct MonitoringConfig: Codable {
    var enabled: Bool = true
    var debounceSeconds: Int = 5
    var batchSize: Int = 100
    var watchSubdirectories: Bool = true
}

struct NotificationConfig: Codable {
    var enabled: Bool = true
    var showOnDiskConnect: Bool = true
    var showOnDiskDisconnect: Bool = true
    var showOnSyncStart: Bool = false
    var showOnSyncComplete: Bool = true
    var showOnSyncError: Bool = true
    var soundEnabled: Bool = true
}

struct LoggingConfig: Codable {
    var level: String = "info"
    var maxFileSize: Int = 10 * 1024 * 1024  // 10 MB
    var maxFiles: Int = 5
    var logPath: String = "~/Library/Logs/DMSA/app.log"
}

struct UIConfig: Codable {
    var showProgressWindow: Bool = true
    var menuBarStyle: String = "icon"
    var theme: String = "system"
}
```

#### C-02: 配置管理器

**Services/ConfigManager.swift:**

```swift
import Foundation

/// 配置管理器
final class ConfigManager {
    static let shared = ConfigManager()

    private let configURL: URL
    private let backupURL: URL
    private var _config: AppConfig

    var config: AppConfig {
        get { _config }
        set {
            _config = newValue
            saveConfig()
        }
    }

    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DMSA")

        // 确保目录存在
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        configURL = appSupport.appendingPathComponent("config.json")
        backupURL = appSupport.appendingPathComponent("config.backup.json")

        _config = AppConfig()
        loadConfig()
    }

    private func loadConfig() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            Logger.shared.info("配置文件不存在，使用默认配置")
            saveConfig() // 创建默认配置
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            _config = try decoder.decode(AppConfig.self, from: data)
            Logger.shared.info("配置加载成功")

            // 备份配置
            try? data.write(to: backupURL)
        } catch {
            Logger.shared.error("配置加载失败: \(error.localizedDescription)")
            loadBackupConfig()
        }
    }

    private func loadBackupConfig() {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            Logger.shared.warn("备份配置不存在，使用默认配置")
            return
        }

        do {
            let data = try Data(contentsOf: backupURL)
            _config = try JSONDecoder().decode(AppConfig.self, from: data)
            Logger.shared.info("从备份恢复配置成功")
        } catch {
            Logger.shared.error("备份配置也损坏: \(error.localizedDescription)")
        }
    }

    private func saveConfig() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(_config)
            try data.write(to: configURL)
            Logger.shared.debug("配置保存成功")
        } catch {
            Logger.shared.error("配置保存失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 便捷方法

    func getDisk(byId id: String) -> DiskConfig? {
        return config.disks.first { $0.id == id }
    }

    func getConnectedDisks() -> [DiskConfig] {
        return config.disks.filter { $0.enabled && $0.isConnected }
    }

    func getSyncPairs(forDiskId diskId: String) -> [SyncPairConfig] {
        return config.syncPairs.filter { $0.diskId == diskId && $0.enabled }
    }

    func getHighestPriorityConnectedDisk() -> DiskConfig? {
        return getConnectedDisks().sorted { $0.priority < $1.priority }.first
    }
}
```

#### C-05: 硬盘管理器

**Services/DiskManager.swift:**

```swift
import Cocoa

/// 硬盘管理器
final class DiskManager {
    static let shared = DiskManager()

    private let workspace = NSWorkspace.shared
    private let configManager = ConfigManager.shared

    var onDiskConnected: ((DiskConfig) -> Void)?
    var onDiskDisconnected: ((DiskConfig) -> Void)?

    private init() {
        registerNotifications()
    }

    private func registerNotifications() {
        let nc = workspace.notificationCenter

        nc.addObserver(
            self,
            selector: #selector(handleDiskMount(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(handleDiskWillUnmount(_:)),
            name: NSWorkspace.willUnmountNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(handleDiskUnmount(_:)),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
    }

    @objc private func handleDiskMount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        Logger.shared.info("硬盘挂载: \(devicePath)")

        // 查找匹配的配置硬盘
        if let disk = configManager.config.disks.first(where: { devicePath.contains($0.name) && $0.enabled }) {
            Logger.shared.info("目标硬盘 \(disk.name) 已连接")

            // 延迟执行，等待挂载稳定
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.onDiskConnected?(disk)
            }
        }
    }

    @objc private func handleDiskWillUnmount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        Logger.shared.info("硬盘即将卸载: \(devicePath)")
    }

    @objc private func handleDiskUnmount(_ notification: Notification) {
        guard let devicePath = notification.userInfo?["NSDevicePath"] as? String else { return }
        Logger.shared.info("硬盘已卸载: \(devicePath)")

        if let disk = configManager.config.disks.first(where: { devicePath.contains($0.name) }) {
            Logger.shared.info("目标硬盘 \(disk.name) 已断开")
            onDiskDisconnected?(disk)
        }
    }

    /// 检查初始状态
    func checkInitialState() {
        Logger.shared.info("检查硬盘初始状态...")

        for disk in configManager.config.disks where disk.enabled {
            if disk.isConnected {
                Logger.shared.info("硬盘 \(disk.name) 已连接")
                onDiskConnected?(disk)
            } else {
                Logger.shared.info("硬盘 \(disk.name) 未连接")
            }
        }
    }

    /// 获取硬盘信息
    func getDiskInfo(at path: String) -> (total: Int64, available: Int64)? {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            let total = attrs[.systemSize] as? Int64 ?? 0
            let available = attrs[.systemFreeSize] as? Int64 ?? 0
            return (total, available)
        } catch {
            Logger.shared.error("获取硬盘信息失败: \(error.localizedDescription)")
            return nil
        }
    }
}
```

#### C-06: rsync 封装

**Services/RsyncWrapper.swift:**

```swift
import Foundation

/// rsync 同步结果
struct RsyncResult {
    let success: Bool
    let output: String
    let filesTransferred: Int
    let bytesTransferred: Int64
    let errorMessage: String?
}

/// rsync 同步选项
struct RsyncOptions {
    var archive: Bool = true           // -a
    var verbose: Bool = true           // -v
    var delete: Bool = true            // --delete
    var checksum: Bool = false         // --checksum
    var dryRun: Bool = false           // -n
    var progress: Bool = true          // --progress
    var excludePatterns: [String] = []
    var partial: Bool = true           // --partial (断点续传)
}

/// rsync 封装器
final class RsyncWrapper {

    static let shared = RsyncWrapper()

    private let rsyncPath = "/usr/bin/rsync"

    private init() {}

    /// 执行同步
    func sync(
        source: String,
        destination: String,
        options: RsyncOptions = RsyncOptions(),
        progressHandler: ((String) -> Void)? = nil
    ) async throws -> RsyncResult {

        var arguments: [String] = []

        if options.archive { arguments.append("-a") }
        if options.verbose { arguments.append("-v") }
        if options.delete { arguments.append("--delete") }
        if options.checksum { arguments.append("--checksum") }
        if options.dryRun { arguments.append("-n") }
        if options.progress { arguments.append("--progress") }
        if options.partial { arguments.append("--partial") }

        for pattern in options.excludePatterns {
            arguments.append("--exclude=\(pattern)")
        }

        // 确保路径以 / 结尾
        let sourcePath = source.hasSuffix("/") ? source : source + "/"
        let destPath = destination.hasSuffix("/") ? destination : destination + "/"

        arguments.append(sourcePath)
        arguments.append(destPath)

        Logger.shared.info("rsync 参数: \(arguments.joined(separator: " "))")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: rsyncPath)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            var outputData = Data()
            var errorData = Data()

            // 读取输出
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                outputData.append(data)

                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    progressHandler?(str)
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                errorData.append(handle.availableData)
            }

            process.terminationHandler = { proc in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                let success = proc.terminationStatus == 0

                let result = RsyncResult(
                    success: success,
                    output: output,
                    filesTransferred: self.parseFilesCount(output),
                    bytesTransferred: self.parseBytesTransferred(output),
                    errorMessage: success ? nil : errorOutput
                )

                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parseFilesCount(_ output: String) -> Int {
        // 解析 "Number of files transferred: X"
        if let range = output.range(of: "Number of files transferred: "),
           let endRange = output[range.upperBound...].range(of: "\n") {
            let numStr = output[range.upperBound..<endRange.lowerBound]
            return Int(numStr.trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    private func parseBytesTransferred(_ output: String) -> Int64 {
        // 解析 "Total transferred file size: X bytes"
        if let range = output.range(of: "Total transferred file size: "),
           let endRange = output[range.upperBound...].range(of: " bytes") {
            let numStr = output[range.upperBound..<endRange.lowerBound]
                .replacingOccurrences(of: ",", with: "")
            return Int64(numStr.trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }
}
```

#### C-07: 同步引擎

**Services/SyncEngine.swift:**

```swift
import Foundation

/// 同步任务
struct SyncTask {
    let id: String
    let syncPair: SyncPairConfig
    let disk: DiskConfig
    let direction: SyncDirection
    let createdAt: Date
}

/// 同步引擎
final class SyncEngine {

    static let shared = SyncEngine()

    private let rsync = RsyncWrapper.shared
    private let configManager = ConfigManager.shared
    private let dbManager: DatabaseManager

    var onSyncProgress: ((String, Double) -> Void)?
    var onSyncComplete: ((SyncTask, RsyncResult) -> Void)?

    private init() {
        dbManager = DatabaseManager.shared
    }

    /// 执行同步任务
    func execute(_ task: SyncTask) async throws -> RsyncResult {
        Logger.shared.info("开始同步任务: \(task.syncPair.localPath) <-> \(task.disk.name)")

        let localPath = (task.syncPair.localPath as NSString).expandingTildeInPath
        let externalPath = task.syncPair.externalFullPath(diskMountPath: task.disk.mountPath)

        // 确保目录存在
        try ensureDirectoryExists(externalPath)

        // 构建 rsync 选项
        var options = RsyncOptions()
        options.excludePatterns = configManager.config.filters.excludePatterns + task.syncPair.excludePatterns
        options.delete = task.direction != .bidirectional

        // 确定源和目标
        let (source, destination) = determineSourceAndDestination(
            localPath: localPath,
            externalPath: externalPath,
            direction: task.direction
        )

        // 记录同步开始
        let history = createSyncHistory(task: task, status: .inProgress)

        let startTime = Date()

        do {
            let result = try await rsync.sync(
                source: source,
                destination: destination,
                options: options
            ) { [weak self] progress in
                self?.onSyncProgress?(task.id, 0.5) // 简化进度
            }

            // 更新历史记录
            updateSyncHistory(
                history,
                status: result.success ? .completed : .failed,
                filesCount: result.filesTransferred,
                totalSize: result.bytesTransferred,
                duration: Date().timeIntervalSince(startTime),
                errorMessage: result.errorMessage
            )

            Logger.shared.info("同步完成: \(result.filesTransferred) 文件, \(formatBytes(result.bytesTransferred))")

            onSyncComplete?(task, result)

            return result

        } catch {
            Logger.shared.error("同步失败: \(error.localizedDescription)")

            updateSyncHistory(
                history,
                status: .failed,
                errorMessage: error.localizedDescription
            )

            throw error
        }
    }

    private func determineSourceAndDestination(
        localPath: String,
        externalPath: String,
        direction: SyncDirection
    ) -> (source: String, destination: String) {
        switch direction {
        case .localToExternal:
            return (localPath, externalPath)
        case .externalToLocal:
            return (externalPath, localPath)
        case .bidirectional:
            // 双向同步：比较修改时间，以较新的为源
            let localMtime = getDirectoryMtime(localPath)
            let externalMtime = getDirectoryMtime(externalPath)

            if localMtime >= externalMtime {
                return (localPath, externalPath)
            } else {
                return (externalPath, localPath)
            }
        }
    }

    private func getDirectoryMtime(_ path: String) -> Date {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.modificationDate] as? Date ?? .distantPast
    }

    private func ensureDirectoryExists(_ path: String) throws {
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true
            )
            Logger.shared.info("创建目录: \(path)")
        }
    }

    private func createSyncHistory(task: SyncTask, status: SyncStatus) -> SyncHistory {
        let history = SyncHistory()
        history.startedAt = Date()
        history.direction = task.direction
        history.status = status
        history.diskId = task.disk.id
        history.syncPairId = task.syncPair.id

        dbManager.saveSyncHistory(history)
        return history
    }

    private func updateSyncHistory(
        _ history: SyncHistory,
        status: SyncStatus,
        filesCount: Int = 0,
        totalSize: Int64 = 0,
        duration: TimeInterval = 0,
        errorMessage: String? = nil
    ) {
        history.completedAt = Date()
        history.status = status
        history.filesCount = filesCount
        history.totalSize = totalSize
        history.errorMessage = errorMessage

        dbManager.saveSyncHistory(history)
    }
}

// MARK: - Helpers

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
```

### 3.4 验收标准

- [ ] 配置文件正确读写
- [ ] 硬盘插拔事件正确触发
- [ ] rsync 同步正常执行
- [ ] 同步历史记录到数据库
- [ ] 设置界面可修改配置

---

## 4. 阶段三: VFS 实现 (P0-VFS)

### 4.1 目标

实现虚拟文件系统层，基于 Endpoint Security 框架拦截文件操作。

### 4.2 任务清单

| 任务ID | 任务 | 输出文件 | 依赖 |
|--------|------|----------|------|
| V-01 | 创建 System Extension 结构 | `Extension/` 目录 | C-* |
| V-02 | 配置 Extension entitlements | `Extension.entitlements` | V-01 |
| V-03 | 实现 ES Client 初始化 | `Extension/ESClient.swift` | V-02 |
| V-04 | 实现事件订阅 | `Extension/EventSubscriber.swift` | V-03 |
| V-05 | 实现读取路由器 | `Core/ReadRouter.swift` | V-04 |
| V-06 | 实现写入路由器 | `Core/WriteRouter.swift` | V-04 |
| V-07 | 实现元数据管理器 | `Core/MetadataManager.swift` | C-04 |
| V-08 | 实现缓存管理器 | `Services/CacheManager.swift` | V-07 |
| V-09 | 实现 VFS 核心 | `Core/VFSCore.swift` | V-05, V-06 |
| V-10 | 实现扩展安装器 | `Services/ExtensionInstaller.swift` | V-01 |
| V-11 | 主应用与扩展通信 | `Services/ExtensionBridge.swift` | V-09 |

### 4.3 详细实施

#### V-03: ES Client 初始化

**Extension/ESClient.swift:**

```swift
import Foundation
import EndpointSecurity

/// Endpoint Security Client
final class ESClient {

    private var client: OpaquePointer?
    private let eventHandler: (es_message_t) -> Void

    init(eventHandler: @escaping (es_message_t) -> Void) throws {
        self.eventHandler = eventHandler

        var newClient: OpaquePointer?

        let result = es_new_client(&newClient) { [weak self] client, message in
            self?.eventHandler(message.pointee)
        }

        guard result == ES_NEW_CLIENT_RESULT_SUCCESS else {
            throw ESError.clientCreationFailed(result)
        }

        self.client = newClient
    }

    deinit {
        if let client = client {
            es_delete_client(client)
        }
    }

    /// 订阅事件
    func subscribe(events: [es_event_type_t]) throws {
        guard let client = client else {
            throw ESError.clientNotInitialized
        }

        let result = es_subscribe(client, events, UInt32(events.count))

        guard result == ES_RETURN_SUCCESS else {
            throw ESError.subscriptionFailed(result)
        }
    }

    /// 响应授权请求
    func respond(message: UnsafePointer<es_message_t>, result: es_auth_result_t, cache: Bool = false) {
        guard let client = client else { return }
        es_respond_auth_result(client, message, result, cache)
    }
}

enum ESError: Error {
    case clientCreationFailed(es_new_client_result_t)
    case clientNotInitialized
    case subscriptionFailed(es_return_t)
}
```

#### V-05: 读取路由器

**Core/ReadRouter.swift:**

```swift
import Foundation

/// 读取结果
enum ReadResult {
    case local(String)          // 从 LOCAL 读取
    case external(String)       // 从 EXTERNAL 读取
    case notFound               // 文件不存在
    case offlineError           // 硬盘离线
}

/// 读取路由器
final class ReadRouter {

    private let metadataManager: MetadataManager
    private let cacheManager: CacheManager
    private let diskManager: DiskManager

    init(
        metadataManager: MetadataManager,
        cacheManager: CacheManager,
        diskManager: DiskManager
    ) {
        self.metadataManager = metadataManager
        self.cacheManager = cacheManager
        self.diskManager = diskManager
    }

    /// 解析读取路径
    func resolveReadPath(_ virtualPath: String) -> ReadResult {
        guard let fileEntry = metadataManager.getFileEntry(virtualPath: virtualPath) else {
            return .notFound
        }

        switch fileEntry.location {
        case .localOnly, .both:
            // 文件在 LOCAL，直接返回
            metadataManager.updateAccessTime(virtualPath)
            return .local(fileEntry.localPath ?? virtualPath)

        case .externalOnly:
            // 文件仅在 EXTERNAL
            guard diskManager.isExternalConnected else {
                return .offlineError
            }

            // 从 EXTERNAL 拉取到 LOCAL
            if let localPath = pullToLocal(fileEntry) {
                return .local(localPath)
            } else {
                return .offlineError
            }

        case .notExists:
            return .notFound
        }
    }

    /// 从 EXTERNAL 拉取文件到 LOCAL
    private func pullToLocal(_ fileEntry: FileEntry) -> String? {
        guard let externalPath = fileEntry.externalPath else {
            return nil
        }

        let localPath = cacheManager.localPathFor(fileEntry.virtualPath)

        do {
            // 确保目录存在
            let localDir = (localPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: localDir,
                withIntermediateDirectories: true
            )

            // 复制文件
            try FileManager.default.copyItem(atPath: externalPath, toPath: localPath)

            // 更新元数据
            metadataManager.updateFileLocation(
                virtualPath: fileEntry.virtualPath,
                location: .both,
                localPath: localPath
            )

            Logger.shared.info("拉取到 LOCAL: \(fileEntry.virtualPath)")

            return localPath

        } catch {
            Logger.shared.error("拉取失败: \(error.localizedDescription)")
            return nil
        }
    }
}
```

#### V-06: 写入路由器

**Core/WriteRouter.swift:**

```swift
import Foundation

/// 脏文件记录
struct DirtyFile {
    let virtualPath: String
    let localPath: String
    let createdAt: Date
    var modifiedAt: Date
    var syncAttempts: Int = 0
    var lastSyncError: String?
}

/// 写入路由器
final class WriteRouter {

    private let metadataManager: MetadataManager
    private let cacheManager: CacheManager
    private let syncScheduler: SyncScheduler

    private var dirtyQueue: [String: DirtyFile] = [:]
    private let queue = DispatchQueue(label: "com.ttttt.dmsa.writeRouter")
    private let debounceInterval: TimeInterval = 5.0

    init(
        metadataManager: MetadataManager,
        cacheManager: CacheManager,
        syncScheduler: SyncScheduler
    ) {
        self.metadataManager = metadataManager
        self.cacheManager = cacheManager
        self.syncScheduler = syncScheduler
    }

    /// 处理写入请求 (Write-Back 策略)
    func handleWrite(_ virtualPath: String, data: Data) -> Bool {
        let localPath = cacheManager.localPathFor(virtualPath)

        // 1. 写入 LOCAL
        do {
            let localDir = (localPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: localDir,
                withIntermediateDirectories: true
            )

            try data.write(to: URL(fileURLWithPath: localPath))

        } catch {
            Logger.shared.error("写入 LOCAL 失败: \(error.localizedDescription)")
            return false
        }

        // 2. 更新元数据
        metadataManager.updateFileEntry(
            virtualPath: virtualPath,
            location: .localOnly,
            localPath: localPath,
            isDirty: true,
            size: Int64(data.count),
            modifiedAt: Date()
        )

        // 3. 加入脏文件队列
        queue.async { [weak self] in
            self?.addToDirtyQueue(virtualPath: virtualPath, localPath: localPath)
        }

        Logger.shared.debug("写入成功 (Write-Back): \(virtualPath)")
        return true
    }

    private func addToDirtyQueue(virtualPath: String, localPath: String) {
        let now = Date()

        if var existing = dirtyQueue[virtualPath] {
            existing.modifiedAt = now
            dirtyQueue[virtualPath] = existing
        } else {
            dirtyQueue[virtualPath] = DirtyFile(
                virtualPath: virtualPath,
                localPath: localPath,
                createdAt: now,
                modifiedAt: now
            )
        }

        // 调度同步 (防抖)
        scheduleSyncDebounced()
    }

    private var syncTimer: DispatchWorkItem?

    private func scheduleSyncDebounced() {
        syncTimer?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushDirtyQueue()
        }

        syncTimer = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func flushDirtyQueue() {
        let filesToSync = Array(dirtyQueue.values)

        guard !filesToSync.isEmpty else { return }

        Logger.shared.info("开始同步 \(filesToSync.count) 个脏文件")

        // 触发同步调度器
        syncScheduler.scheduleDirtyFilesSync(filesToSync)
    }

    /// 标记文件同步完成
    func markSynced(_ virtualPath: String) {
        queue.async { [weak self] in
            self?.dirtyQueue.removeValue(forKey: virtualPath)
            self?.metadataManager.markClean(virtualPath)
        }
    }

    /// 获取脏文件列表
    func getDirtyFiles() -> [DirtyFile] {
        return queue.sync { Array(dirtyQueue.values) }
    }
}
```

#### V-08: 缓存管理器

**Services/CacheManager.swift:**

```swift
import Foundation

/// 缓存管理器
final class CacheManager {

    static let shared = CacheManager()

    private let configManager = ConfigManager.shared
    private let cacheBaseURL: URL
    private let fileManager = FileManager.default

    private init() {
        cacheBaseURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DMSA/LocalCache")

        try? fileManager.createDirectory(at: cacheBaseURL, withIntermediateDirectories: true)
    }

    /// 获取虚拟路径对应的 LOCAL 路径
    func localPathFor(_ virtualPath: String) -> String {
        let relativePath = virtualPath
            .replacingOccurrences(of: "~/", with: "")
            .replacingOccurrences(of: fileManager.homeDirectoryForCurrentUser.path + "/", with: "")

        return cacheBaseURL.appendingPathComponent(relativePath).path
    }

    /// 计算当前缓存大小
    func calculateCacheSize() -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(
            at: cacheBaseURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        return totalSize
    }

    /// 执行缓存淘汰
    func enforceSpaceLimit() {
        let config = configManager.config.cache
        let currentSize = calculateCacheSize()

        guard currentSize > config.maxCacheSize else {
            Logger.shared.debug("缓存大小正常: \(formatBytes(currentSize))")
            return
        }

        Logger.shared.info("缓存超限，开始淘汰: \(formatBytes(currentSize)) > \(formatBytes(config.maxCacheSize))")

        // 获取可淘汰文件 (非 dirty，已同步到 EXTERNAL)
        let evictableFiles = getEvictableFiles()

        var freedSpace: Int64 = 0
        let targetFree = currentSize - config.maxCacheSize + config.reserveBuffer

        for file in evictableFiles {
            guard freedSpace < targetFree else { break }

            do {
                try fileManager.removeItem(atPath: file.localPath)
                freedSpace += file.size

                // 更新元数据
                DatabaseManager.shared.updateFileLocation(
                    virtualPath: file.virtualPath,
                    location: .externalOnly
                )

                Logger.shared.info("淘汰: \(file.virtualPath), 释放 \(formatBytes(file.size))")

            } catch {
                Logger.shared.error("淘汰失败: \(error.localizedDescription)")
            }
        }

        Logger.shared.info("淘汰完成，释放空间: \(formatBytes(freedSpace))")
    }

    /// 获取可淘汰文件列表 (按修改时间排序)
    private func getEvictableFiles() -> [FileEntry] {
        return DatabaseManager.shared.getEvictableFiles()
            .sorted { $0.modifiedAt < $1.modifiedAt }
    }

    /// 定期检查空间
    func startEvictionTimer() {
        let interval = TimeInterval(configManager.config.cache.evictionCheckInterval)

        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.enforceSpaceLimit()
        }
    }
}
```

### 4.4 验收标准

- [ ] System Extension 正确安装
- [ ] ES 事件正确拦截
- [ ] 读取路由正确 (LOCAL 优先，按需拉取)
- [ ] 写入路由正确 (Write-Back 策略)
- [ ] 缓存淘汰按修改时间执行

---

## 5. 阶段四: 增强功能 (P1)

### 5.1 目标

添加文件监控、完整 GUI、异常保护、开机自启动。

### 5.2 任务清单

| 任务ID | 任务 | 输出文件 | 依赖 |
|--------|------|----------|------|
| E-01 | 实现 FSEvents 监控 | `Services/FileWatcher.swift` | C-* |
| E-02 | 实现同步进度 UI | `UI/SyncProgressView.swift` | C-07 |
| E-03 | 实现同步历史 UI | `UI/SyncHistoryView.swift` | C-04 |
| E-04 | 实现完整设置 UI | `UI/SettingsView.swift` 扩展 | C-10 |
| E-05 | 实现异常检测 | `Services/HealthChecker.swift` | V-* |
| E-06 | 实现恢复向导 | `UI/RecoveryWizard.swift` | E-05 |
| E-07 | 实现 LaunchAgent 管理 | `Services/LaunchAgentManager.swift` | C-02 |
| E-08 | 实现深色模式支持 | UI 样式更新 | E-02, E-03 |

### 5.3 验收标准

- [ ] 文件变化实时触发同步
- [ ] 进度窗口正确显示
- [ ] 历史列表正确展示
- [ ] 异常断开自动恢复
- [ ] 开机自启动可配置

---

## 6. 阶段五: 完善功能 (P2)

### 6.1 目标

完善统计、高级过滤、配置迁移。

### 6.2 任务清单

| 任务ID | 任务 | 输出文件 | 依赖 |
|--------|------|----------|------|
| P-01 | 实现统计聚合 | `Services/StatisticsManager.swift` | C-04 |
| P-02 | 实现统计图表 | `UI/StatisticsView.swift` | P-01 |
| P-03 | 实现高级过滤规则 | `Services/AdvancedFilter.swift` | C-09 |
| P-04 | 实现过滤预设 | `UI/FilterPresetsView.swift` | P-03 |
| P-05 | 实现配置导出 | `Services/ConfigExporter.swift` | C-02 |
| P-06 | 实现配置导入 | `Services/ConfigImporter.swift` | C-02 |
| P-07 | 性能优化 | 全局优化 | 全部 |

### 6.3 验收标准

- [ ] 统计面板数据正确
- [ ] 图表正确渲染
- [ ] 高级过滤规则生效
- [ ] 配置导入导出正常

---

## 7. 文件清单

### 7.1 完整文件结构

```
DMSA/
├── Package.swift
│
├── Sources/
│   └── DMSA/
│       │
│       ├── main.swift                           # F-04
│       │
│       ├── App/
│       │   └── AppDelegate.swift                # F-05, C-11
│       │
│       ├── Core/
│       │   ├── VFSCore.swift                    # V-09
│       │   ├── ReadRouter.swift                 # V-05
│       │   ├── WriteRouter.swift                # V-06
│       │   └── MetadataManager.swift            # V-07
│       │
│       ├── Services/
│       │   ├── ConfigManager.swift              # C-02
│       │   ├── DatabaseManager.swift            # C-04
│       │   ├── DiskManager.swift                # C-05
│       │   ├── RsyncWrapper.swift               # C-06
│       │   ├── SyncEngine.swift                 # C-07
│       │   ├── SyncScheduler.swift              # C-08
│       │   ├── FileFilter.swift                 # C-09
│       │   ├── CacheManager.swift               # V-08
│       │   ├── NotificationManager.swift        # C-12
│       │   ├── ExtensionInstaller.swift         # V-10
│       │   ├── ExtensionBridge.swift            # V-11
│       │   ├── FileWatcher.swift                # E-01
│       │   ├── HealthChecker.swift              # E-05
│       │   ├── LaunchAgentManager.swift         # E-07
│       │   ├── StatisticsManager.swift          # P-01
│       │   ├── AdvancedFilter.swift             # P-03
│       │   ├── ConfigExporter.swift             # P-05
│       │   └── ConfigImporter.swift             # P-06
│       │
│       ├── Models/
│       │   ├── Config.swift                     # C-01
│       │   ├── Errors.swift                     # F-08
│       │   └── Entities/
│       │       ├── FileEntry.swift              # C-03
│       │       ├── SyncHistory.swift            # C-03
│       │       ├── DiskConfigEntity.swift       # C-03
│       │       ├── SyncPairEntity.swift         # C-03
│       │       └── SyncStatistics.swift         # C-03
│       │
│       ├── UI/
│       │   ├── MenuBarManager.swift             # F-07
│       │   ├── SettingsView.swift               # C-10, E-04
│       │   ├── SyncProgressView.swift           # E-02
│       │   ├── SyncHistoryView.swift            # E-03
│       │   ├── RecoveryWizard.swift             # E-06
│       │   ├── StatisticsView.swift             # P-02
│       │   └── FilterPresetsView.swift          # P-04
│       │
│       ├── Utils/
│       │   ├── Logger.swift                     # F-06
│       │   ├── Constants.swift                  # F-09
│       │   └── Extensions.swift
│       │
│       └── Resources/
│           ├── Info.plist                       # F-02
│           └── DMSA.entitlements                # F-03
│
├── Extension/
│   ├── main.swift                               # V-01
│   ├── ESClient.swift                           # V-03
│   ├── EventSubscriber.swift                    # V-04
│   ├── Info.plist                               # V-01
│   └── Extension.entitlements                   # V-02
│
└── Tests/
    └── DMSATests/
        ├── ConfigManagerTests.swift
        ├── SyncEngineTests.swift
        ├── CacheManagerTests.swift
        └── RsyncWrapperTests.swift
```

### 7.2 文件数量统计

| 类别 | 文件数 |
|------|--------|
| 核心层 (Core) | 4 |
| 服务层 (Services) | 17 |
| 数据模型 (Models) | 7 |
| UI 层 | 7 |
| 工具类 (Utils) | 3 |
| Extension | 5 |
| 测试 | 4 |
| 配置文件 | 4 |
| **总计** | **51** |

---

## 8. 依赖关系图

```
┌─────────────────────────────────────────────────────────────────────┐
│                         依赖关系图                                    │
└─────────────────────────────────────────────────────────────────────┘

                              AppDelegate
                                   │
                    ┌──────────────┼──────────────┐
                    ▼              ▼              ▼
              MenuBarManager  DiskManager   ConfigManager
                    │              │              │
                    │              │              │
                    ▼              ▼              ▼
              ┌─────┴─────────────┬┴──────────────┴─────┐
              │                   │                     │
              ▼                   ▼                     ▼
        SyncScheduler      NotificationManager   DatabaseManager
              │                                        │
              ▼                                        │
         SyncEngine ◀──────────────────────────────────┘
              │
       ┌──────┴──────┐
       ▼             ▼
  RsyncWrapper   FileFilter


                         VFS 层依赖

                           VFSCore
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
         ReadRouter     WriteRouter    MetadataManager
              │               │               │
              └───────┬───────┴───────────────┘
                      ▼
               CacheManager
                      │
                      ▼
              DatabaseManager


                    Extension 依赖

                      ESClient
                         │
                         ▼
                  EventSubscriber
                         │
                         ▼
                  ExtensionBridge ◀────▶ VFSCore
```

---

## 9. 测试计划

### 9.1 单元测试

| 模块 | 测试文件 | 测试重点 |
|------|----------|----------|
| ConfigManager | `ConfigManagerTests.swift` | 配置读写、默认值、损坏恢复 |
| SyncEngine | `SyncEngineTests.swift` | 同步方向、冲突处理 |
| CacheManager | `CacheManagerTests.swift` | 淘汰算法、空间计算 |
| RsyncWrapper | `RsyncWrapperTests.swift` | 参数构建、结果解析 |
| ReadRouter | `ReadRouterTests.swift` | 路由逻辑、离线处理 |
| WriteRouter | `WriteRouterTests.swift` | Write-Back、脏队列 |

### 9.2 集成测试

| 场景 | 测试内容 |
|------|----------|
| 硬盘热插拔 | 插入/拔出时的状态转换和同步触发 |
| 大文件同步 | 1GB+ 文件的同步性能和断点续传 |
| 并发写入 | 多进程同时写入同一目录 |
| 崩溃恢复 | 同步中断后的数据一致性 |
| 配置迁移 | 从 v1.0 配置升级到 v2.0 |

### 9.3 性能基准

| 指标 | 目标 |
|------|------|
| 启动时间 | < 2 秒 |
| 内存占用 (空闲) | < 50 MB |
| 同步吞吐量 | ≥ 90% rsync 原生性能 |
| 文件监控延迟 | < 1 秒 |
| 缓存淘汰效率 | 1000 文件 < 5 秒 |

---

## 10. 风险与缓解

### 10.1 技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| Endpoint Security 审批 | 无法使用 VFS | 准备 FSEvents fallback 方案 |
| ObjectBox 兼容性 | 数据库问题 | 使用稳定版本，准备 Core Data 备选 |
| rsync 权限问题 | 同步失败 | 明确权限要求，提供授权引导 |
| System Extension 签名 | 无法分发 | 获取开发者证书，准备公证流程 |

### 10.2 进度风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| VFS 复杂度超预期 | 延期 | 先完成核心同步，VFS 作为增强 |
| UI 适配工作量 | 延期 | 使用系统组件，减少自定义 |
| 测试覆盖不足 | 质量问题 | 关键路径优先测试 |

### 10.3 缓解策略

```
风险等级定义:
  高 = 影响核心功能，必须解决
  中 = 影响用户体验，建议解决
  低 = 影响边缘功能，可延后

应对原则:
  1. 高风险项优先处理
  2. 准备 B 计划
  3. 定期评估风险状态
  4. 及时沟通调整
```

---

## 附录: 命名规范

### 文件命名

| 类型 | 格式 | 示例 |
|------|------|------|
| Swift 文件 | PascalCase | `ConfigManager.swift` |
| 测试文件 | *Tests.swift | `ConfigManagerTests.swift` |
| 资源文件 | PascalCase | `Info.plist` |

### 代码命名

| 类型 | 格式 | 示例 |
|------|------|------|
| 类/结构体 | PascalCase | `SyncEngine` |
| 协议 | PascalCase + able/ing | `Syncable` |
| 方法/属性 | camelCase | `performSync()` |
| 常量 | camelCase | `maxRetryCount` |
| 枚举值 | camelCase | `.localToExternal` |

---

*文档维护: 实施进度更新时同步此文档*
