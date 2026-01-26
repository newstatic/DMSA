# VFS 修正计划

> 创建日期: 2026-01-26
> 问题: ~/Downloads 是符号链接而非 FUSE 挂载点

---

## 0. 修正概要

| 类别 | 修正内容 |
|------|----------|
| **代码修改** | `VFSManager.mount()` 需要检测并处理符号链接 |
| **代码修改** | `VFSFileSystemDelegate` 缺少 `fileCreated` 方法签名 |
| **运维操作** | 移除符号链接，重建挂载点目录 |
| **配置检查** | 确保 config.json 包含正确的同步对 |

---

## 1. 问题诊断

### 1.1 当前状态

```bash
$ ls -la ~/Downloads
lrwxr-xr-x@ 1 ttttt staff 25 Jan 24 15:17 /Users/ttttt/Downloads -> /Volumes/BACKUP/Downloads
```

**问题**: `~/Downloads` 是一个**符号链接**，直接指向外置硬盘，绕过了 VFS 层。

### 1.2 设计预期

根据 `VFS_DESIGN.md`，正确的架构应该是:

```
┌─────────────────────────────────────────────────────────────┐
│                    用户访问 ~/Downloads                       │
│                      (FUSE 挂载点)                           │
└─────────────────────────────────────────────────────────────┘
                              │
                       VFSManager 处理
                              │
                      ┌───────┴───────┐
                      ↓               ↓
              ~/Downloads_Local    /Volumes/BACKUP/Downloads
              (LOCAL_DIR 热数据)    (EXTERNAL_DIR 完整备份)
```

### 1.3 影响

| 影响项 | 说明 |
|--------|------|
| 智能合并失效 | 无法显示 LOCAL + EXTERNAL 的并集 |
| 本地缓存失效 | 所有读写直接到外置硬盘，性能差 |
| 离线不可用 | 外置硬盘断开后 ~/Downloads 无法访问 |
| LRU 淘汰失效 | 无法管理本地存储空间 |
| 同步功能失效 | 没有 LOCAL_DIR，无法执行 LOCAL → EXTERNAL 同步 |

---

## 2. 修正步骤

### 阶段 1: 诊断 (只读操作)

```bash
# 1.1 检查服务状态
sudo launchctl list | grep dmsa

# 1.2 检查服务日志
cat /var/log/dmsa-service.log
cat /var/log/dmsa-service.error.log

# 1.3 检查配置文件
cat ~/Library/Application\ Support/DMSA/config.json

# 1.4 检查 Downloads_Local 是否存在
ls -la ~/Downloads_Local

# 1.5 检查当前 FUSE 挂载
mount | grep -i fuse

# 1.6 检查 macFUSE 安装状态
ls -la /Library/Filesystems/macfuse.fs
kextstat | grep -i fuse
```

### 阶段 2: 准备工作

#### 2.1 确保外置硬盘已挂载

```bash
ls -la /Volumes/BACKUP/Downloads/
```

#### 2.2 创建 LOCAL_DIR (如果不存在)

```bash
# 检查是否存在
if [ ! -d ~/Downloads_Local ]; then
    mkdir -p ~/Downloads_Local
    echo "创建 ~/Downloads_Local"
fi
```

#### 2.3 备份当前符号链接信息

```bash
# 记录当前链接目标
readlink ~/Downloads > /tmp/downloads_link_backup.txt
echo "符号链接备份到: /tmp/downloads_link_backup.txt"
```

### 阶段 3: 移除符号链接

```bash
# 移除符号链接 (不会删除目标目录内容)
rm ~/Downloads
echo "符号链接已移除"
```

### 阶段 4: 创建 FUSE 挂载点

```bash
# 创建空目录作为挂载点
mkdir ~/Downloads
echo "挂载点目录已创建"
```

### 阶段 5: 配置同步对

确保配置文件 `~/Library/Application Support/DMSA/config.json` 包含正确的同步对:

```json
{
  "syncPairs": [
    {
      "id": "downloads-backup",
      "name": "Downloads",
      "localDir": "/Users/ttttt/Downloads_Local",
      "targetDir": "/Users/ttttt/Downloads",
      "diskId": "BACKUP",
      "externalRelativePath": "Downloads",
      "enabled": true,
      "localQuotaGB": 50
    }
  ],
  "disks": [
    {
      "id": "BACKUP",
      "name": "BACKUP",
      "mountPath": "/Volumes/BACKUP",
      "isConnected": true
    }
  ]
}
```

### 阶段 6: 启动/重启服务

```bash
# 如果服务未加载
sudo launchctl load /Library/LaunchDaemons/com.ttttt.dmsa.service.plist

# 如果服务已加载但需要重启
sudo launchctl kickstart -k system/com.ttttt.dmsa.service

# 验证服务状态
sudo launchctl list | grep dmsa
```

### 阶段 7: 验证修正结果

```bash
# 7.1 检查挂载状态
mount | grep Downloads

# 7.2 检查目录类型 (应该不是符号链接)
file ~/Downloads
ls -la ~/Downloads

# 7.3 检查服务日志确认挂载成功
tail -20 /var/log/dmsa-service.log

# 7.4 测试读写
echo "test" > ~/Downloads/test_vfs.txt
cat ~/Downloads/test_vfs.txt
rm ~/Downloads/test_vfs.txt
```

---

## 3. 验证清单

| 检查项 | 预期结果 | 命令 |
|--------|----------|------|
| 服务运行中 | PID 存在 | `sudo launchctl list \| grep dmsa` |
| FUSE 挂载存在 | 显示 DMSA 挂载 | `mount \| grep -i fuse` |
| ~/Downloads 不是链接 | "directory" | `file ~/Downloads` |
| ~/Downloads_Local 存在 | 目录存在 | `ls -d ~/Downloads_Local` |
| 配置包含同步对 | syncPairs 非空 | `cat config.json \| grep syncPairs` |
| 服务日志无错误 | "挂载成功" | `tail /var/log/dmsa-service.log` |

---

## 4. 回滚方案

如果修正失败，恢复到符号链接状态:

```bash
# 1. 停止服务
sudo launchctl unload /Library/LaunchDaemons/com.ttttt.dmsa.service.plist

# 2. 卸载 FUSE (如果已挂载)
umount ~/Downloads 2>/dev/null

# 3. 移除挂载点目录
rmdir ~/Downloads

# 4. 恢复符号链接
ln -s /Volumes/BACKUP/Downloads ~/Downloads

# 5. 验证
ls -la ~/Downloads
```

---

## 5. 根本原因分析

### 可能原因

1. **服务未正确安装**: LaunchDaemon plist 未复制到 `/Library/LaunchDaemons/`
2. **服务二进制未安装**: 可执行文件未复制到 `/Library/PrivilegedHelperTools/`
3. **配置文件为空**: 没有配置同步对，`autoMount()` 无操作
4. **macFUSE 未安装**: FUSE 框架不可用
5. **手动创建了符号链接**: 用户或脚本手动创建绕过了 VFS

### 需要检查的文件

| 文件 | 用途 | 检查命令 |
|------|------|----------|
| `/Library/LaunchDaemons/com.ttttt.dmsa.service.plist` | 服务定义 | `ls -la` |
| `/Library/PrivilegedHelperTools/com.ttttt.dmsa.service` | 服务二进制 | `ls -la` |
| `~/Library/Application Support/DMSA/config.json` | 应用配置 | `cat` |
| `/Library/Filesystems/macfuse.fs` | macFUSE 框架 | `ls -la` |

---

## 6. 长期预防

### 6.1 App 启动时检查

在 `AppDelegate.swift` 中添加启动检查:

```swift
func checkVFSStatus() {
    let downloadsPath = NSHomeDirectory() + "/Downloads"
    let fm = FileManager.default

    // 检查是否是符号链接
    if let attrs = try? fm.attributesOfItem(atPath: downloadsPath),
       attrs[.type] as? FileAttributeType == .typeSymbolicLink {
        // 警告用户
        showAlert("~/Downloads 是符号链接，VFS 未正确配置")
    }
}
```

### 6.2 服务启动时验证

在 `ServiceImplementation.autoMount()` 中添加:

```swift
// 检查目标目录是否是符号链接
if fm.isSymbolicLink(atPath: targetDir) {
    logger.error("目标目录是符号链接，需要先移除: \(targetDir)")
    // 可选: 自动修复
    try? fm.removeItem(atPath: targetDir)
    try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
}
```

---

## 7. 执行顺序总结

```
1. [诊断] 收集当前状态信息
      ↓
2. [准备] 确保 LOCAL_DIR 存在，备份链接信息
      ↓
3. [修正] 移除符号链接，创建挂载点目录
      ↓
4. [配置] 确保 config.json 正确配置同步对
      ↓
5. [启动] 加载/重启 DMSAService
      ↓
6. [验证] 检查挂载状态和功能
      ↓
7. [测试] 读写测试确认 VFS 工作正常
```

---

## 8. 代码修改

### 8.1 VFSManager.mount() 完整重构 ✅ 已完成

**文件**: `DMSAApp/DMSAService/VFS/VFSManager.swift`

**新流程** (5 个步骤):

```swift
// ============================================================
// 步骤 1: 检查 TARGET_DIR 状态并处理
// ============================================================

if fm.fileExists(atPath: targetDir) {
    let attrs = try? fm.attributesOfItem(atPath: targetDir)
    let fileType = attrs?[.type] as? FileAttributeType

    if fileType == .typeSymbolicLink {
        // 情况 A: 符号链接 → 移除
        try fm.removeItem(atPath: targetDir)

    } else if fileType == .typeDirectory {
        // 情况 B: 已是 FUSE 挂载点 → 报错
        if mountPoints.values.contains(where: { $0.targetDir == targetDir }) {
            throw VFSError.alreadyMounted(targetDir)
        }

        // 情况 C: 普通目录 → 重命名为 LOCAL_DIR
        if fm.fileExists(atPath: localDir) {
            // LOCAL_DIR 已存在 → 冲突错误
            throw VFSError.conflictingPaths(targetDir, localDir)
        }
        try fm.moveItem(atPath: targetDir, toPath: localDir)
    }
}

// ============================================================
// 步骤 2: 确保 LOCAL_DIR 存在
// ============================================================

if !fm.fileExists(atPath: localDir) {
    try fm.createDirectory(atPath: localDir, withIntermediateDirectories: true)
}

// ============================================================
// 步骤 3: 创建 FUSE 挂载点目录
// ============================================================

if !fm.fileExists(atPath: targetDir) {
    try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
}

// ============================================================
// 步骤 4: 检查 EXTERNAL_DIR 状态
// ============================================================

var isExternalOnline = false
if let extDir = externalDir {
    if fm.fileExists(atPath: extDir) {
        isExternalOnline = true
        logger.info("EXTERNAL_DIR 已就绪: \(extDir)")
    } else {
        logger.warning("EXTERNAL_DIR 未就绪 (外置硬盘未挂载?): \(extDir)")
    }
} else {
    logger.warning("未配置 EXTERNAL_DIR，仅使用本地存储")
}

// ============================================================
// 步骤 5: 创建并执行 FUSE 挂载
// ============================================================

// ... FUSE 挂载逻辑 ...
```

### 8.2 VFSFileSystemDelegate 协议补全 ✅ 已完成

**文件**: `DMSAApp/DMSAService/VFS/FUSEFileSystem.swift`

新增 `fileCreated` 方法到协议定义。

### 8.3 FUSEFileSystem 回调修正 ✅ 已完成

**文件**: `DMSAApp/DMSAService/VFS/FUSEFileSystem.swift`

`createFile` 和 `createDirectory` 现在调用 `fileCreated` 而不是 `fileWritten`。

### 8.4 新增 VFSError.conflictingPaths ✅ 已完成

**文件**: `DMSAApp/DMSAShared/Utils/Errors.swift`

新增错误类型处理 TARGET_DIR 和 LOCAL_DIR 都存在的情况。

---

## 9. 修正优先级

| 优先级 | 任务 | 原因 |
|--------|------|------|
| **P0** | 8.1 修改 VFSManager 检测符号链接 | 核心问题，不修复则无法正常挂载 |
| **P1** | 8.2 补全协议定义 | 编译警告，影响代码一致性 |
| **P1** | 8.3 修正回调方法 | 影响文件索引准确性 |
| **P2** | 运维操作 (第 2-7 节) | 如代码修改到位，可自动处理 |

---

## 10. 测试用例

### 10.1 符号链接检测测试

```bash
# 准备: 创建符号链接
ln -sf /Volumes/BACKUP/Downloads ~/Downloads

# 执行: 启动服务 (或手动触发 mount)
sudo launchctl kickstart -k system/com.ttttt.dmsa.service

# 验证: 符号链接应被移除，FUSE 应挂载成功
file ~/Downloads  # 预期: "directory"
mount | grep DMSA  # 预期: 显示挂载信息
```

### 10.2 数据迁移测试

```bash
# 准备: ~/Downloads 是普通目录且有文件
mkdir -p ~/Downloads
echo "test" > ~/Downloads/test.txt

# 执行: 启动服务
sudo launchctl kickstart -k system/com.ttttt.dmsa.service

# 验证: 文件应迁移到 LOCAL_DIR
ls ~/Downloads_Local/test.txt  # 预期: 文件存在
ls ~/Downloads/test.txt  # 预期: 通过 VFS 可见
```

---

*文档版本: 3.0 | 创建者: Claude Code | 更新: 完成所有代码修改，重构 mount() 流程*

---

## 11. 修改摘要

### 已完成的代码修改

| 文件 | 修改内容 |
|------|----------|
| `VFSManager.swift` | 重构 `mount()` 方法，5 步骤流程 |
| `FUSEFileSystem.swift` | 补全协议 + 修正回调 |
| `Errors.swift` | 新增 `conflictingPaths` 错误类型 |

### 新流程图

```
mount() 调用
    │
    ▼
┌─────────────────────────────────────┐
│ 步骤 1: 检查 TARGET_DIR             │
│  - 符号链接? → 移除                  │
│  - 已挂载? → 报错                    │
│  - 普通目录? → 重命名为 LOCAL_DIR    │
│    (如 LOCAL_DIR 已存在 → 冲突错误)  │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 步骤 2: 确保 LOCAL_DIR 存在          │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 步骤 3: 创建挂载点目录               │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 步骤 4: 检查 EXTERNAL_DIR            │
│  - 存在 → isExternalOnline = true   │
│  - 不存在 → 警告用户                 │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 步骤 5: 执行 FUSE 挂载               │
└─────────────────────────────────────┘
```

### 编译状态

**BUILD SUCCEEDED** ✅
