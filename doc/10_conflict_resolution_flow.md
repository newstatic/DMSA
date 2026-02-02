# 十、冲突处理流程

> 返回 [目录](00_README.md) | 上一节: [09_文件同步流程](09_文件同步流程.md)

---

## 10.1 冲突检测

```mermaid
flowchart TD
    A[准备同步文件] --> B{EXTERNAL 文件存在?}

    B -->|否| C["无冲突: 新文件"]
    B -->|是| D[获取 EXTERNAL 文件信息]

    D --> E{比较修改时间}

    E -->|LOCAL.mtime > EXTERNAL.mtime| F["无冲突: LOCAL 更新"]
    E -->|LOCAL.mtime < EXTERNAL.mtime| G["检测到冲突!"]
    E -->|LOCAL.mtime == EXTERNAL.mtime| H{比较文件大小}

    H -->|大小相同| I{比较内容哈希}
    H -->|大小不同| G

    I -->|哈希相同| J["无冲突: 文件相同"]
    I -->|哈希不同| G

    G --> K["记录冲突信息"]
    K --> L["进入冲突解决流程"]

    style G fill:#FF6B6B
    style C fill:#90EE90
    style F fill:#90EE90
    style J fill:#90EE90
```

## 10.2 冲突类型

```mermaid
flowchart TB
    subgraph ConflictTypes["冲突类型"]
        CT1["BOTH_MODIFIED<br/>两端都有修改"]
        CT2["LOCAL_DELETED_EXTERNAL_MODIFIED<br/>本地删除，外部修改"]
        CT3["LOCAL_MODIFIED_EXTERNAL_DELETED<br/>本地修改，外部删除"]
        CT4["TYPE_MISMATCH<br/>类型不匹配 (文件/目录)"]
        CT5["PERMISSION_CONFLICT<br/>权限冲突"]
    end

    subgraph Detection["检测方式"]
        D1["比较 mtime"]
        D2["比较 size"]
        D3["比较 hash"]
        D4["比较 type"]
        D5["检查 exists"]
    end

    CT1 --> D1
    CT1 --> D2
    CT1 --> D3
    CT2 --> D5
    CT3 --> D5
    CT4 --> D4
```

## 10.3 冲突解决策略

```mermaid
flowchart TD
    A[检测到冲突] --> B{冲突解决策略}

    B -->|newerWins| C["较新文件胜出"]
    B -->|localWins| D["LOCAL 文件胜出"]
    B -->|externalWins| E["EXTERNAL 文件胜出"]
    B -->|keepBoth| F["保留两个版本"]
    B -->|manual| G["手动解决"]

    subgraph NewerWins["newerWins 策略"]
        C --> C1{LOCAL.mtime > EXTERNAL.mtime?}
        C1 -->|是| C2["复制 LOCAL → EXTERNAL"]
        C1 -->|否| C3["复制 EXTERNAL → LOCAL"]
    end

    subgraph LocalWins["localWins 策略"]
        D --> D1["直接覆盖 EXTERNAL"]
    end

    subgraph ExternalWins["externalWins 策略"]
        E --> E1["复制 EXTERNAL → LOCAL<br/>清除脏标记"]
    end

    subgraph KeepBoth["keepBoth 策略"]
        F --> F1["重命名 LOCAL 文件"]
        F1 --> F2["file.txt → file_conflict_20260127_1030.txt"]
        F2 --> F3["复制 EXTERNAL → LOCAL 原位置"]
        F3 --> F4["同步重命名后的文件到 EXTERNAL"]
    end

    subgraph Manual["manual 策略"]
        G --> G1["暂停同步"]
        G1 --> G2["添加到冲突队列"]
        G2 --> G3["通知 App"]
        G3 --> G4["等待用户决定"]
    end
```

## 10.4 冲突解决流程 (keepBoth)

```mermaid
flowchart TD
    A["冲突文件: ~/Downloads/report.docx"] --> B[生成冲突文件名]

    B --> C["report_conflict_20260127_103045.docx"]

    C --> D["重命名 LOCAL 文件"]
    D --> D1["~/Downloads_Local/report.docx<br/>→ report_conflict_20260127_103045.docx"]

    D1 --> E["复制 EXTERNAL → LOCAL"]
    E --> E1["/Volumes/DISK/Downloads/report.docx<br/>→ ~/Downloads_Local/report.docx"]

    E1 --> F["标记冲突文件为脏"]
    F --> F1["report_conflict_20260127_103045.docx<br/>isDirty = true"]

    F1 --> G["更新索引"]
    G --> G1["添加冲突文件到索引"]
    G1 --> G2["更新原文件索引"]

    G2 --> VU["更新版本文件"]

    subgraph VersionUpdate["版本更新"]
        VU --> VU1["重新计算 LOCAL directoryVersion"]
        VU1 --> VU2["写入 LOCAL version.json"]
    end

    VU2 --> H["下次同步时"]
    H --> H1["冲突文件同步到 EXTERNAL"]
    H1 --> H2["更新 EXTERNAL version.json"]

    H2 --> I["最终状态"]

    subgraph FinalState["最终状态"]
        I --> I1["LOCAL: report.docx 来自 EXTERNAL"]
        I --> I2["LOCAL: report_conflict_xxx.docx 原 LOCAL"]
        I --> I3["EXTERNAL: report.docx 原 EXTERNAL"]
        I --> I4["EXTERNAL: report_conflict_xxx.docx 同步后"]
    end

    style I1 fill:#90EE90
    style I2 fill:#FFD700
    style I3 fill:#90EE90
    style I4 fill:#FFD700
    style VU fill:#87CEEB
```

## 10.5 冲突解决流程 (manual)

```mermaid
sequenceDiagram
    participant Sync as SyncManager
    participant CQ as ConflictQueue
    participant NQ as NotificationQueue
    participant APP as DMSA.app
    participant User as 用户

    Sync->>Sync: 检测到冲突
    Sync->>CQ: addConflict(conflictInfo)
    Sync->>Sync: 跳过该文件，继续同步其他文件

    CQ->>NQ: enqueue(conflictDetected)
    NQ-->>APP: 冲突通知

    APP->>APP: 显示冲突提示
    APP->>User: "检测到文件冲突"

    User->>APP: 查看冲突详情
    APP->>CQ: getConflicts()
    CQ-->>APP: 冲突列表

    APP->>APP: 显示冲突列表
    APP->>User: 显示两个版本对比

    User->>APP: 选择解决方案
    Note over User,APP: keepLocal / keepExternal / keepBoth

    APP->>Sync: resolveConflict(path, resolution)
    Sync->>Sync: 执行解决方案
    Sync->>Sync: 更新索引

    Note over Sync: 版本更新
    Sync->>Sync: 重新计算 directoryVersion
    Sync->>Sync: 写入 version.json

    Sync->>CQ: removeConflict(path)
    Sync->>NQ: enqueue(conflictResolved)
    NQ-->>APP: 冲突已解决
```

## 10.6 冲突信息结构

```mermaid
classDiagram
    class ConflictInfo {
        +id: UUID
        +syncPairId: String
        +filePath: String
        +conflictType: ConflictType
        +localInfo: FileInfo
        +externalInfo: FileInfo
        +detectedAt: Date
        +autoResolution: Resolution?
        +userResolution: Resolution?
        +resolvedAt: Date?
        +status: ConflictStatus
    }

    class ConflictType {
        <<enum>>
        bothModified
        localDeletedExternalModified
        localModifiedExternalDeleted
        typeMismatch
        permissionConflict
    }

    class FileInfo {
        +path: String
        +size: Int64
        +mtime: Date
        +hash: String?
        +exists: Bool
        +type: FileType
    }

    class Resolution {
        <<enum>>
        keepLocal
        keepExternal
        keepBoth
        skip
        delete
    }

    class ConflictStatus {
        <<enum>>
        pending
        autoResolved
        userResolved
        skipped
    }

    ConflictInfo --> ConflictType
    ConflictInfo --> FileInfo
    ConflictInfo --> Resolution
    ConflictInfo --> ConflictStatus
```

## 10.7 冲突处理 XPC 接口

```mermaid
flowchart LR
    subgraph ConflictAPIs["冲突处理 XPC 接口"]
        A1["getConflicts(syncPairId)<br/>→ [ConflictInfo]"]
        A2["getConflictCount(syncPairId)<br/>→ Int"]
        A3["resolveConflict(id, resolution)<br/>→ Bool"]
        A4["resolveAllConflicts(syncPairId, resolution)<br/>→ Int"]
        A5["skipConflict(id)<br/>→ Bool"]
        A6["getConflictPreview(id)<br/>→ ConflictPreview"]
    end

    subgraph ConflictPreview["ConflictPreview 结构"]
        B1["localPreview: Data? (前 1KB)"]
        B2["externalPreview: Data? (前 1KB)"]
        B3["localFullPath: String"]
        B4["externalFullPath: String"]
        B5["canCompare: Bool"]
    end

    A6 --> B1
    A6 --> B2
    A6 --> B3
    A6 --> B4
    A6 --> B5
```

---

> 下一节: [11_热数据淘汰流程](11_热数据淘汰流程.md)
