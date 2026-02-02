# 九、文件同步流程

> 返回 [目录](00_README.md) | 上一节: [08_索引构建流程](08_索引构建流程.md)

---

## 9.1 同步方向与策略

```mermaid
flowchart LR
    subgraph Direction["同步方向"]
        D1["单向同步: LOCAL → EXTERNAL"]
        D2["LOCAL 是热数据 (用户写入)"]
        D3["EXTERNAL 是冷数据 (备份存储)"]
    end

    subgraph Strategy["同步策略"]
        S1["增量同步: 只同步变更文件"]
        S2["脏文件标记: isDirty = true"]
        S3["定时触发: 每 N 分钟检查"]
        S4["事件触发: 磁盘连接时立即同步"]
    end

    D1 --> S1
    D2 --> S2
    D3 --> S3
    D3 --> S4
```

## 9.2 同步触发条件

```mermaid
flowchart TD
    subgraph Triggers["同步触发条件"]
        T1["定时触发<br/>(syncInterval, 默认 300s)"]
        T2["磁盘连接触发<br/>(diskConnected 事件)"]
        T3["手动触发<br/>(App 调用 syncNow)"]
        T4["文件关闭触发<br/>(写入完成后)"]
        T5["阈值触发<br/>(脏文件数 > N)"]
    end

    T1 --> A[检查脏文件队列]
    T2 --> A
    T3 --> A
    T4 --> B[单文件同步]
    T5 --> A

    A --> C{队列非空?}
    C -->|是| D[开始批量同步]
    C -->|否| E[跳过本次同步]

    B --> F[同步单个文件]
```

## 9.3 同步主流程

```mermaid
flowchart TD
    A[同步开始] --> A1["组件状态: Sync = busy"]

    A1 --> B{EXTERNAL_DIR 已连接?}
    B -->|否| C["跳过同步<br/>保持脏文件标记"]
    B -->|是| D[获取脏文件列表]

    D --> E{列表为空?}
    E -->|是| F["无需同步<br/>组件状态: Sync = ready"]
    E -->|否| G[按优先级排序]

    G --> H["优先级规则:<br/>1. 小文件优先<br/>2. 最近修改优先<br/>3. 用户标记优先"]

    H --> I[遍历脏文件]

    I --> J{还有文件?}
    J -->|否| Z["同步完成"]
    J -->|是| K[处理单个文件]

    subgraph SyncOneFile["单文件同步"]
        K --> L{LOCAL 文件存在?}
        L -->|否| L1["清除脏标记<br/>(文件已删除)"]
        L -->|是| M{EXTERNAL 文件存在?}

        M -->|否| N["新文件: 直接复制"]
        M -->|是| O{检查冲突}

        O -->|无冲突| P["覆盖: 复制 LOCAL → EXTERNAL"]
        O -->|有冲突| Q["进入冲突处理流程"]

        N --> R[复制文件]
        P --> R
        Q --> R

        R --> S{复制成功?}
        S -->|是| T["清除脏标记<br/>更新索引"]
        S -->|否| U["记录错误<br/>保持脏标记"]
    end

    L1 --> J
    T --> V["发送进度通知"]
    U --> V
    V --> J

    Z --> Z1["更新同步统计"]
    Z1 --> Z2["写入版本文件"]
    Z2 --> Z3["组件状态: Sync = ready"]
    Z3 --> Z4["缓存通知: syncCompleted"]

    style T fill:#90EE90
    style U fill:#FF6B6B
    style Q fill:#FFA500
```

## 9.4 脏文件管理

```mermaid
flowchart TD
    subgraph MarkDirty["标记为脏"]
        MD1["VFS write() 完成"]
        MD2["VFS create() 完成"]
        MD3["VFS rename() 完成"]
        MD4["VFS truncate() 完成"]
    end

    MD1 --> A["markFileDirty(path)"]
    MD2 --> A
    MD3 --> A
    MD4 --> A

    A --> B["更新数据库<br/>FileEntry.isDirty = true"]
    B --> C["添加到脏文件队列"]
    C --> D["记录脏时间戳"]

    subgraph ClearDirty["清除脏标记"]
        CD1["同步成功"]
        CD2["文件被删除"]
        CD3["手动清除"]
    end

    CD1 --> E["clearFileDirty(path)"]
    CD2 --> E
    CD3 --> E

    E --> F["更新数据库<br/>FileEntry.isDirty = false"]
    F --> G["从脏文件队列移除"]
```

## 9.5 同步状态结构

```mermaid
classDiagram
    class SyncStatus {
        +syncPairId: String
        +state: SyncState
        +progress: Double
        +currentFile: String?
        +processedFiles: Int
        +totalFiles: Int
        +processedBytes: Int64
        +totalBytes: Int64
        +errors: [SyncError]
        +startedAt: Date?
        +estimatedCompletion: Date?
    }

    class SyncState {
        <<enum>>
        idle
        preparing
        syncing
        paused
        completed
        failed
    }

    class SyncError {
        +filePath: String
        +errorCode: Int
        +errorMessage: String
        +timestamp: Date
        +retryCount: Int
    }

    class SyncStatistics {
        +totalSyncs: Int
        +successfulSyncs: Int
        +failedSyncs: Int
        +totalFilesSynced: Int64
        +totalBytesSynced: Int64
        +averageSyncDuration: TimeInterval
        +lastSyncAt: Date?
    }

    SyncStatus --> SyncState
    SyncStatus --> SyncError
```

## 9.6 同步进度通知

```mermaid
flowchart LR
    subgraph SyncProgress["SyncProgress 结构"]
        A["syncPairId: String"]
        B["state: SyncState"]
        C["progress: Double (0.0-1.0)"]
        D["currentFile: String?"]
        E["processedFiles: Int"]
        F["totalFiles: Int"]
        G["speed: Int64 (bytes/s)"]
        H["eta: TimeInterval?"]
        I["errors: [SyncError]"]
    end

    subgraph Notifications["通知类型"]
        N1["syncStarted"]
        N2["syncProgress"]
        N3["syncFileCompleted"]
        N4["syncFileFailed"]
        N5["syncCompleted"]
        N6["syncFailed"]
        N7["syncPaused"]
        N8["syncResumed"]
    end
```

---

> 下一节: [10_冲突处理流程](10_冲突处理流程.md)
