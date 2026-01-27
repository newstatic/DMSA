# 三、启动流程总览

> 返回 [目录](00_README.md) | 上一节: [02_配置管理](02_配置管理.md)

---

```mermaid
flowchart TB
    subgraph Phase1["阶段 1: 环境初始化"]
        A[launchd 启动进程] --> B[设置环境变量]
        B --> C[预加载 macFUSE]
        C --> D[初始化日志系统]
        D --> E[创建必要目录]
        E --> F[注册信号处理器]
    end

    subgraph Phase2["阶段 2: XPC 优先启动 ⭐"]
        F --> G["状态 = STARTING"]
        G --> H[创建 ServiceDelegate]
        H --> I[创建 ServiceImplementation]
        I --> J[创建 XPC 监听器]
        J --> K["listener.resume()"]
        K --> L["状态 = XPC_READY"]
    end

    subgraph Phase2b["阶段 2.5: 配置加载"]
        L --> L1[加载配置文件]
        L1 --> L2{配置有效?}
        L2 -->|否| L3[处理配置问题]
        L3 --> L4[使用修正后配置]
        L2 -->|是| L4
        L4 --> L5[缓存配置状态通知]
    end

    subgraph Phase3["阶段 3: VFS 预挂载"]
        L5 --> M["状态 = VFS_MOUNTING"]
        M --> N[准备挂载点目录]
        N --> O["挂载 FUSE (indexReady=false)"]
        O --> P[保护后端目录]
        P --> Q["状态 = VFS_BLOCKED"]
    end

    subgraph Phase4["阶段 4: 索引构建"]
        Q --> R["状态 = INDEXING"]
        R --> S[扫描 LOCAL_DIR]
        S --> T[扫描 EXTERNAL_DIR]
        T --> U[合并索引并保存]
        U --> V["indexReady = true"]
        V --> W["状态 = READY"]
    end

    subgraph Phase5["阶段 5: 完全就绪"]
        W --> X[启动同步调度器]
        X --> Y[启动淘汰检查器]
        Y --> Z["状态 = RUNNING"]
        Z --> AA["发送所有缓存的通知"]
        AA --> AB["RunLoop.main.run()"]
    end

    L -.->|App 可连接| APP((App))
    Q -.->|访问返回 EBUSY| USER((用户))
    W -.->|VFS 可正常访问| USER
```

---

## 阶段说明

| 阶段 | 状态值 | 说明 | 详细文档 |
|------|--------|------|----------|
| 阶段 1 | STARTING (0) | 环境初始化，加载 macFUSE | - |
| 阶段 2 | XPC_READY (1) | XPC 监听器启动，App 可连接 | [06_XPC优先启动](06_XPC优先启动.md) |
| 阶段 2.5 | XPC_READY (1) | 配置加载和验证 | [02_配置管理](02_配置管理.md) |
| 阶段 3 | VFS_BLOCKED (3) | VFS 挂载但拒绝访问 | [07_VFS预挂载机制](07_VFS预挂载机制.md) |
| 阶段 4 | INDEXING (4) | 构建文件索引 | [08_索引构建流程](08_索引构建流程.md) |
| 阶段 5 | RUNNING (6) | 完全就绪，启动调度器 | [12_完整启动时序](12_完整启动时序.md) |

---

> 下一节: [04_XPC通信与通知](04_XPC通信与通知.md)
