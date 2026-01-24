# FUSE-T 集成指南

> 此文档说明如何在 DMSA 项目中集成 FUSE-T

---

## 1. 安装 FUSE-T

### 1.1 使用 Homebrew (推荐)

```bash
# 添加 FUSE-T tap
brew tap macos-fuse-t/homebrew-cask

# 安装 FUSE-T
brew install --cask fuse-t
```

### 1.2 手动安装

1. 下载最新版本: https://github.com/macos-fuse-t/fuse-t/releases
2. 运行 PKG 安装程序
3. 重启系统 (如果需要)

### 1.3 验证安装

```bash
# 检查 FUSE-T 是否安装
ls -la /Library/Frameworks/FUSE-T.framework

# 或检查 kext
kextstat | grep fuse
```

---

## 2. Xcode 项目配置

### 2.1 添加 Framework 搜索路径

在 Build Settings 中添加:

```
FRAMEWORK_SEARCH_PATHS = /Library/Frameworks
HEADER_SEARCH_PATHS = /usr/local/include/fuse /opt/homebrew/include/fuse
LIBRARY_SEARCH_PATHS = /usr/local/lib /opt/homebrew/lib
```

### 2.2 添加链接器标志

```
OTHER_LDFLAGS = -lfuse-t
```

或使用 Framework:

```
OTHER_LDFLAGS = -framework FUSE-T
```

### 2.3 添加桥接头文件

创建 `DMSAApp-Bridging-Header.h`:

```c
#ifndef DMSAApp_Bridging_Header_h
#define DMSAApp_Bridging_Header_h

// FUSE-T headers
#define FUSE_USE_VERSION 26
#include <fuse.h>

#endif
```

---

## 3. C 桥接代码

### 3.1 创建 FUSE 操作回调

创建 `fuse_callbacks.c`:

```c
#define FUSE_USE_VERSION 26
#include <fuse.h>
#include <string.h>
#include <errno.h>

// 前向声明 Swift 回调
extern int swift_getattr(const char *path, struct stat *stbuf);
extern int swift_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                         off_t offset, struct fuse_file_info *fi);
extern int swift_open(const char *path, struct fuse_file_info *fi);
extern int swift_read(const char *path, char *buf, size_t size, off_t offset,
                      struct fuse_file_info *fi);
extern int swift_write(const char *path, const char *buf, size_t size, off_t offset,
                       struct fuse_file_info *fi);
extern int swift_create(const char *path, mode_t mode, struct fuse_file_info *fi);
extern int swift_unlink(const char *path);
extern int swift_mkdir(const char *path, mode_t mode);
extern int swift_rmdir(const char *path);
extern int swift_rename(const char *from, const char *to);
extern int swift_truncate(const char *path, off_t size);
extern int swift_release(const char *path, struct fuse_file_info *fi);

// FUSE 操作结构
static struct fuse_operations dmsa_operations = {
    .getattr  = swift_getattr,
    .readdir  = swift_readdir,
    .open     = swift_open,
    .read     = swift_read,
    .write    = swift_write,
    .create   = swift_create,
    .unlink   = swift_unlink,
    .mkdir    = swift_mkdir,
    .rmdir    = swift_rmdir,
    .rename   = swift_rename,
    .truncate = swift_truncate,
    .release  = swift_release,
};

// 启动 FUSE
int dmsa_fuse_main(int argc, char *argv[]) {
    return fuse_main(argc, argv, &dmsa_operations, NULL);
}

// 获取 FUSE 上下文中的私有数据
void* dmsa_get_context() {
    struct fuse_context *ctx = fuse_get_context();
    return ctx ? ctx->private_data : NULL;
}
```

### 3.2 创建头文件

创建 `fuse_callbacks.h`:

```c
#ifndef FUSE_CALLBACKS_H
#define FUSE_CALLBACKS_H

int dmsa_fuse_main(int argc, char *argv[]);
void* dmsa_get_context(void);

#endif
```

---

## 4. Swift 实现

### 4.1 导出 Swift 回调

在 Swift 中实现 C 回调:

```swift
import Foundation

// 全局 VFS 实例引用
private var currentFileSystem: VFSFileSystem?

// 设置当前文件系统
func setCurrentFileSystem(_ fs: VFSFileSystem?) {
    currentFileSystem = fs
}

// C 回调实现
@_cdecl("swift_getattr")
func swift_getattr(_ path: UnsafePointer<CChar>, _ stbuf: UnsafeMutablePointer<stat>) -> Int32 {
    guard let fs = currentFileSystem else { return -ENOENT }

    let pathStr = String(cString: path)

    // 同步等待异步结果
    var result: FUSEStatResult?
    let semaphore = DispatchSemaphore(value: 0)

    Task {
        result = await fs.getattr(pathStr)
        semaphore.signal()
    }

    semaphore.wait()

    if let stat = result?.stat {
        stbuf.pointee = stat
        return 0
    }
    return result?.errno ?? -ENOENT
}

// ... 其他回调类似实现
```

---

## 5. 使用说明

### 5.1 启动 VFS

```swift
// 在 AppDelegate 中
func applicationDidFinishLaunching(_ notification: Notification) {
    Task {
        do {
            try await VFSCore.shared.startAll()
        } catch {
            Logger.shared.error("VFS 启动失败: \(error)")
        }
    }
}
```

### 5.2 停止 VFS

```swift
func applicationWillTerminate(_ notification: Notification) {
    Task {
        try? await VFSCore.shared.stopAll()
    }
}
```

---

## 6. 调试

### 6.1 启用 FUSE 调试输出

```swift
var options = FUSEMountOptions()
options.debug = true
options.foreground = true
```

### 6.2 查看挂载状态

```bash
mount | grep fuse
df -h | grep fuse
```

### 6.3 手动卸载

```bash
umount ~/Downloads
# 或
diskutil unmount ~/Downloads
```

---

## 7. 常见问题

### Q: FUSE-T 未找到

确保:
1. FUSE-T 已正确安装
2. Framework 搜索路径正确
3. 系统扩展已批准 (系统偏好设置 → 安全性与隐私)

### Q: 挂载失败

检查:
1. 挂载点目录是否存在且为空
2. 是否有权限访问挂载点
3. 系统日志: `log show --predicate 'subsystem == "com.apple.fuse"' --last 5m`

### Q: 性能问题

优化:
1. 使用多线程模式 (不设置 singleThread)
2. 增加内核缓存
3. 减少元数据操作

---

## 8. 文件清单

```
Services/VFS/
├── FUSEBridge.swift        # FUSE-T Swift 包装器
├── VFSFileSystem.swift     # FUSE 操作实现
├── VFSCore.swift           # VFS 核心管理
├── MergeEngine.swift       # 智能合并引擎
├── ReadRouter.swift        # 读取路由
├── WriteRouter.swift       # 写入路由
├── LockManager.swift       # 同步锁
├── VFSError.swift          # 错误类型
└── FUSE_SETUP.md           # 本文档
```

---

## 9. 备选方案: macFUSE

如果无法使用 FUSE-T，可以使用 macFUSE:

1. 下载: https://osxfuse.github.io/
2. 配置类似，但链接 `-losxfuse` 或 `-framework macFUSE`

注意: macFUSE 需要禁用 SIP 或使用系统扩展

---

*文档版本: 1.0 | 最后更新: 2026-01-24*
