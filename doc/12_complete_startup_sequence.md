# 十二、完整启动时序

> 返回 [目录](00_README.md) | 上一节: [11_热数据淘汰流程](11_热数据淘汰流程.md)

---

```mermaid
sequenceDiagram
    participant L as launchd
    participant M as main.swift
    participant SM as StateManager
    participant NQ as NotificationQueue
    participant CFG as ConfigManager
    participant XPC as XPC Listener
    participant VFS as VFSManager
    participant IDX as IndexBuilder
    participant APP as DMSA.app

    L->>M: 启动进程
    M->>SM: setState(STARTING)
    M->>SM: setComponent(XPC, starting)

    Note over M: 环境初始化
    M->>M: 设置环境变量
    M->>M: 预加载 macFUSE
    M->>M: 初始化日志

    M->>XPC: 创建 XPC 监听器
    XPC->>XPC: resume()
    M->>SM: setComponent(XPC, ready)
    M->>SM: setState(XPC_READY)
    M->>NQ: enqueue(xpcReady)

    Note over M: 配置加载
    M->>CFG: loadConfig()
    CFG->>CFG: 验证配置
    alt 配置有问题
        CFG->>NQ: enqueue(configStatus: patched)
    end
    M->>SM: setComponent(Config, ready)

    Note over M: VFS 挂载
    M->>SM: setState(VFS_MOUNTING)
    M->>SM: setComponent(VFS, starting)
    M->>VFS: autoMount()
    VFS->>VFS: 创建挂载点
    VFS->>VFS: FUSE mount (indexReady=false)
    VFS->>VFS: 保护后端目录
    M->>SM: setComponent(VFS, ready)
    M->>SM: setState(VFS_BLOCKED)
    M->>NQ: enqueue(vfsMounted)

    Note over APP: App 此时启动并连接
    APP->>XPC: 连接请求
    XPC-->>APP: 接受连接
    APP->>SM: getFullState()
    SM-->>APP: VFS_BLOCKED + 组件状态
    XPC->>NQ: dequeueAll()
    NQ-->>XPC: 缓存的通知列表
    XPC-->>APP: 补发所有缓存通知

    Note over M: 索引构建
    M->>SM: setState(INDEXING)
    M->>SM: setComponent(Index, starting)
    M->>IDX: buildIndex()
    IDX->>IDX: 扫描 LOCAL_DIR
    IDX->>NQ: enqueue(indexProgress: 30%)
    NQ-->>APP: indexProgress 通知
    IDX->>IDX: 扫描 EXTERNAL_DIR
    IDX->>NQ: enqueue(indexProgress: 70%)
    NQ-->>APP: indexProgress 通知
    IDX->>IDX: 合并并保存

    IDX->>VFS: indexReady = true
    M->>SM: setComponent(Index, ready)
    M->>SM: setState(READY)
    M->>NQ: enqueue(indexReady)
    NQ-->>APP: indexReady 通知

    APP->>VFS: ls ~/Downloads
    VFS-->>APP: 文件列表

    Note over M: 启动调度器
    M->>SM: setComponent(Sync, ready)
    M->>SM: setComponent(Eviction, ready)
    M->>SM: setState(RUNNING)
    M->>NQ: enqueue(serviceReady)
    NQ-->>APP: serviceReady 通知

    Note over APP: 服务完全就绪
```

---

## 启动时间参考

| 阶段 | 耗时 | 说明 |
|------|------|------|
| 环境初始化 | ~50ms | 设置环境变量、加载 macFUSE |
| XPC 启动 | ~50ms | 创建监听器并启动 |
| 配置加载 | ~50ms | 读取、验证配置 |
| VFS 挂载 | ~100ms | FUSE 挂载、保护目录 |
| 索引构建 | ~1-10s | 取决于文件数量 |
| 调度器启动 | ~50ms | 启动同步和淘汰调度 |
| **总计** | **~2-12s** | - |

---

> 下一节: [13_App端交互流程](13_App端交互流程.md)
