# 五、状态管理器设计

> 返回 [目录](00_README.md) | 上一节: [04_XPC通信与通知](04_XPC通信与通知.md)

---

## 5.1 完整状态结构

```mermaid
classDiagram
    class ServiceStateManager {
        <<actor>>
        +shared: ServiceStateManager
        -globalState: ServiceState
        -componentStates: [String: ComponentStateInfo]
        -notificationQueue: NotificationQueue
        -xpcConnectionState: XPCConnectionState
        +setState(newState)
        +setComponentState(component, state, error?)
        +getFullState() ServiceFullState
        +waitForState(target) async
        +canPerform(operation) Bool
    }

    class ServiceFullState {
        +globalState: ServiceState
        +globalStateName: String
        +components: [String: ComponentStateInfo]
        +xpcConnection: XPCConnectionState
        +config: ConfigStatus
        +pendingNotifications: Int
        +startTime: Date
        +uptime: TimeInterval
        +lastError: ServiceError?
    }

    class ComponentStateInfo {
        +name: String
        +state: ComponentState
        +stateName: String
        +lastUpdated: Date
        +error: ComponentError?
        +metrics: ComponentMetrics?
    }

    class ComponentMetrics {
        +processedCount: Int
        +errorCount: Int
        +lastOperationDuration: TimeInterval
        +averageOperationDuration: TimeInterval
    }

    class ConfigStatus {
        +isValid: Bool
        +isPatched: Bool
        +patchedFields: [String]?
        +conflicts: [ConfigConflict]?
        +loadedAt: Date
    }

    class ConfigConflict {
        +type: String
        +affectedItems: [String]
        +resolution: String
        +requiresUserAction: Bool
    }

    ServiceStateManager --> ServiceFullState
    ServiceStateManager --> NotificationQueue
    ServiceFullState --> ComponentStateInfo
    ServiceFullState --> ConfigStatus
    ComponentStateInfo --> ComponentError
    ComponentStateInfo --> ComponentMetrics
    ConfigStatus --> ConfigConflict
```

## 5.2 组件状态定义

```mermaid
flowchart TB
    subgraph Components["服务组件"]
        C1["XPC: XPC 监听器"]
        C2["Config: 配置管理"]
        C3["VFS: 虚拟文件系统"]
        C4["Index: 索引管理"]
        C5["Sync: 同步引擎"]
        C6["Eviction: 淘汰管理"]
        C7["Database: 数据库"]
    end

    subgraph States["组件状态"]
        S1["notStarted"]
        S2["starting"]
        S3["ready"]
        S4["busy"]
        S5["paused"]
        S6["error"]
    end

    subgraph Errors["组件错误类型"]
        E1["XPC: 监听失败、连接验证失败"]
        E2["Config: 文件不存在、解析失败、验证失败"]
        E3["VFS: FUSE加载失败、挂载失败、权限不足"]
        E4["Index: 扫描失败、合并失败、保存失败"]
        E5["Sync: 源不可访问、目标不可写、冲突"]
        E6["Eviction: 空间不足、删除失败"]
        E7["Database: 打开失败、损坏、写入失败"]
    end

    C1 --> E1
    C2 --> E2
    C3 --> E3
    C4 --> E4
    C5 --> E5
    C6 --> E6
    C7 --> E7
```

## 5.3 组件状态转换

```mermaid
stateDiagram-v2
    [*] --> notStarted

    notStarted --> starting: 初始化
    starting --> ready: 初始化成功
    starting --> error: 初始化失败

    ready --> busy: 开始操作
    busy --> ready: 操作完成
    busy --> error: 操作失败

    ready --> paused: 暂停请求
    paused --> ready: 恢复请求

    error --> starting: 重试
    error --> notStarted: 重置

    note right of error: 记录错误详情
    note right of busy: 记录当前操作
```

## 5.4 组件错误详情

```mermaid
flowchart TD
    subgraph XPCErrors["XPC 错误"]
        XE1["E_XPC_LISTEN_FAILED<br/>code: 1001<br/>监听器启动失败"]
        XE2["E_XPC_CONNECTION_INVALID<br/>code: 1002<br/>连接验证失败"]
        XE3["E_XPC_TIMEOUT<br/>code: 1003<br/>调用超时"]
    end

    subgraph ConfigErrors["Config 错误"]
        CE1["E_CONFIG_NOT_FOUND<br/>code: 2001<br/>配置文件不存在"]
        CE2["E_CONFIG_PARSE_FAILED<br/>code: 2002<br/>JSON 解析失败"]
        CE3["E_CONFIG_INVALID<br/>code: 2003<br/>配置验证失败"]
        CE4["E_CONFIG_CONFLICT<br/>code: 2004<br/>配置冲突"]
    end

    subgraph VFSErrors["VFS 错误"]
        VE1["E_VFS_FUSE_NOT_INSTALLED<br/>code: 3001<br/>macFUSE 未安装"]
        VE2["E_VFS_FUSE_VERSION<br/>code: 3002<br/>macFUSE 版本过低"]
        VE3["E_VFS_MOUNT_FAILED<br/>code: 3003<br/>挂载失败"]
        VE4["E_VFS_PERMISSION<br/>code: 3004<br/>权限不足"]
        VE5["E_VFS_MOUNT_BUSY<br/>code: 3005<br/>挂载点被占用"]
    end

    subgraph IndexErrors["Index 错误"]
        IE1["E_INDEX_SCAN_FAILED<br/>code: 4001<br/>目录扫描失败"]
        IE2["E_INDEX_PERMISSION<br/>code: 4002<br/>目录访问权限不足"]
        IE3["E_INDEX_SAVE_FAILED<br/>code: 4003<br/>索引保存失败"]
    end

    subgraph SyncErrors["Sync 错误"]
        SE1["E_SYNC_SOURCE_UNAVAILABLE<br/>code: 5001<br/>源目录不可访问"]
        SE2["E_SYNC_TARGET_READONLY<br/>code: 5002<br/>目标只读"]
        SE3["E_SYNC_CONFLICT<br/>code: 5003<br/>文件冲突"]
        SE4["E_SYNC_DISK_FULL<br/>code: 5004<br/>磁盘空间不足"]
    end

    subgraph DatabaseErrors["Database 错误"]
        DE1["E_DB_OPEN_FAILED<br/>code: 6001<br/>数据库打开失败"]
        DE2["E_DB_CORRUPTED<br/>code: 6002<br/>数据库损坏"]
        DE3["E_DB_WRITE_FAILED<br/>code: 6003<br/>写入失败"]
    end
```

## 5.5 状态查询接口

```mermaid
sequenceDiagram
    participant App
    participant XPC as XPC Connection
    participant SM as StateManager
    participant SI as ServiceImpl

    App->>XPC: getFullState()
    XPC->>SI: getFullState(reply:)
    SI->>SM: getFullState()

    SM->>SM: 收集全局状态
    SM->>SM: 收集各组件状态
    SM->>SM: 收集配置状态
    SM->>SM: 收集错误信息

    SM-->>SI: ServiceFullState
    SI-->>XPC: Data (encoded)
    XPC-->>App: ServiceFullState

    Note over App: 解析状态<br/>更新 UI<br/>处理错误提示
```

---

> 下一节: [06_XPC优先启动](06_XPC优先启动.md)
