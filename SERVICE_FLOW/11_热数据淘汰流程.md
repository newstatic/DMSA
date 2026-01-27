# 十一、热数据淘汰流程

> 返回 [目录](00_README.md) | 上一节: [10_冲突处理流程](10_冲突处理流程.md)

---

## 11.1 淘汰机制概述

```mermaid
flowchart LR
    subgraph Purpose["淘汰目的"]
        P1["释放 LOCAL_DIR 空间"]
        P2["保留热数据"]
        P3["冷数据仅存 EXTERNAL"]
    end

    subgraph Strategy["淘汰策略"]
        S1["LRU (最近最少使用)"]
        S2["仅淘汰 BOTH 状态文件"]
        S3["保护脏文件 (未同步)"]
        S4["保护最近访问文件"]
    end

    P1 --> S1
    P2 --> S2
    P3 --> S3
    P3 --> S4
```

## 11.2 淘汰触发条件

```mermaid
flowchart TD
    subgraph Triggers["触发条件"]
        T1["定时检查<br/>(evictionInterval, 默认 600s)"]
        T2["空间阈值触发<br/>(LOCAL_DIR 使用 > threshold)"]
        T3["写入时触发<br/>(写入前空间不足)"]
        T4["手动触发<br/>(App 调用 triggerEviction)"]
    end

    T1 --> A[检查 LOCAL_DIR 空间]
    T2 --> A
    T3 --> B[紧急淘汰]
    T4 --> A

    A --> C{使用率 > 阈值?}
    C -->|是| D[开始淘汰流程]
    C -->|否| E[跳过本次检查]

    B --> F[淘汰直到腾出所需空间]

    subgraph Thresholds["阈值配置"]
        TH1["eviction.threshold: 10GB (默认)"]
        TH2["eviction.targetFree: 5GB (目标剩余)"]
        TH3["eviction.minAge: 3600s (最小保留时间)"]
        TH4["eviction.batchSize: 100 (批量处理)"]
    end
```

## 11.3 淘汰候选文件筛选

```mermaid
flowchart TD
    A[获取所有 LOCAL 文件] --> B{文件状态检查}

    B --> C{location == BOTH?}
    C -->|否| C1["跳过: 仅存在于 LOCAL"]
    C -->|是| D{isDirty == false?}

    D -->|否| D1["跳过: 脏文件未同步"]
    D -->|是| E{lastAccessTime < minAge?}

    E -->|否| E1["跳过: 最近访问过"]
    E -->|是| F{EXTERNAL 文件存在?}

    F -->|否| F1["跳过: EXTERNAL 已删除"]
    F -->|是| G{EXTERNAL 内容一致?}

    G -->|否| G1["跳过: 内容不一致<br/>需要重新同步"]
    G -->|是| H["加入候选列表"]

    H --> I[按 lastAccessTime 排序]
    I --> J["最久未访问的排在前面"]

    style C1 fill:#FF6B6B
    style D1 fill:#FF6B6B
    style E1 fill:#FFA500
    style F1 fill:#FF6B6B
    style G1 fill:#FFA500
    style H fill:#90EE90
```

## 11.4 淘汰主流程

```mermaid
flowchart TD
    A[淘汰开始] --> A1["组件状态: Eviction = busy"]

    A1 --> B[计算需要释放的空间]
    B --> B1["needToFree = currentUsed - targetFree"]

    B1 --> C[获取淘汰候选文件]
    C --> D{候选列表为空?}

    D -->|是| E["无可淘汰文件<br/>发送警告通知"]
    D -->|否| F[按 LRU 排序]

    F --> G[遍历候选文件]

    G --> H{已释放 >= 需要释放?}
    H -->|是| Z["淘汰完成"]
    H -->|否| I{还有候选文件?}

    I -->|否| J["部分淘汰<br/>空间仍不足"]
    I -->|是| K[处理单个文件]

    subgraph EvictOneFile["单文件淘汰"]
        K --> L{再次验证 EXTERNAL 存在?}
        L -->|否| L1["跳过该文件"]
        L -->|是| M{比较文件哈希}

        M -->|不一致| M1["标记需要重新同步<br/>跳过该文件"]
        M -->|一致| N["删除 LOCAL 文件"]

        N --> O{删除成功?}
        O -->|否| O1["记录错误<br/>继续下一个"]
        O -->|是| P["更新索引状态"]

        P --> P1["location = externalOnly"]
        P1 --> P2["清除 localPath"]
        P2 --> Q["累加已释放空间"]
    end

    L1 --> G
    M1 --> G
    O1 --> G
    Q --> R["发送淘汰进度通知"]
    R --> G

    Z --> Z1["更新淘汰统计"]
    Z1 --> ZV["更新版本文件"]

    subgraph VersionUpdate["版本更新"]
        ZV --> ZV1["重新计算 LOCAL directoryVersion"]
        ZV1 --> ZV2["写入 LOCAL version.json"]
    end

    ZV2 --> Z2["组件状态: Eviction = ready"]
    Z2 --> Z3["缓存通知: evictionCompleted"]

    J --> J1["组件状态: Eviction = ready"]
    J1 --> JV["更新版本文件 (部分)"]
    JV --> J2["缓存通知: evictionPartial"]

    style N fill:#FFD700
    style Z fill:#90EE90
    style J fill:#FFA500
    style ZV fill:#87CEEB
    style JV fill:#87CEEB
```

## 11.5 淘汰安全检查

```mermaid
flowchart TD
    A[删除 LOCAL 文件前] --> B{安全检查}

    subgraph SafetyChecks["安全检查项"]
        B --> C1{文件是否被打开?}
        B --> C2{文件是否正在写入?}
        B --> C3{文件是否有脏标记?}
        B --> C4{EXTERNAL 是否可访问?}
        B --> C5{EXTERNAL 文件完整性?}
    end

    C1 -->|是| D1["跳过: 文件正在使用"]
    C2 -->|是| D2["跳过: 正在写入"]
    C3 -->|是| D3["跳过: 未同步"]
    C4 -->|否| D4["跳过: EXTERNAL 离线"]
    C5 -->|否| D5["跳过: EXTERNAL 文件损坏"]

    C1 -->|否| E1[通过]
    C2 -->|否| E2[通过]
    C3 -->|否| E3[通过]
    C4 -->|是| E4[通过]
    C5 -->|是| E5[通过]

    E1 & E2 & E3 & E4 & E5 --> F["所有检查通过"]
    F --> G["允许删除"]

    style D1 fill:#FF6B6B
    style D2 fill:#FF6B6B
    style D3 fill:#FF6B6B
    style D4 fill:#FF6B6B
    style D5 fill:#FF6B6B
    style G fill:#90EE90
```

## 11.6 淘汰后文件访问

```mermaid
flowchart TD
    A["用户访问已淘汰文件<br/>location = externalOnly"] --> B{"VFS read 请求"}

    B --> C{EXTERNAL 已连接?}

    C -->|否| D["返回 -ENOENT 或 -EIO"]
    D --> D1["Finder 显示: 文件不可用"]

    C -->|是| E["直接从 EXTERNAL 读取"]
    E --> F{读取成功?}

    F -->|是| G["返回数据给用户"]
    F -->|否| H["返回错误"]

    subgraph OptionalRecall["可选: 按需召回"]
        G --> I{用户频繁访问?}
        I -->|是| J["考虑召回到 LOCAL"]
        J --> K["复制 EXTERNAL → LOCAL"]
        K --> L["更新 location = BOTH"]
    end

    style E fill:#90EE90
    style D fill:#FF6B6B
```

## 11.7 淘汰配置

```mermaid
flowchart TB
    subgraph EvictionConfig["淘汰配置项"]
        EC1["enabled: Bool = true"]
        EC2["threshold: Int64 = 10GB"]
        EC3["targetFree: Int64 = 5GB"]
        EC4["checkInterval: TimeInterval = 600"]
        EC5["minAge: TimeInterval = 3600"]
        EC6["batchSize: Int = 100"]
        EC7["verifyBeforeDelete: Bool = true"]
        EC8["recallOnFrequentAccess: Bool = false"]
        EC9["recallThreshold: Int = 5"]
    end

    subgraph Explanation["配置说明"]
        E1["enabled: 是否启用自动淘汰"]
        E2["threshold: LOCAL 空间达到此值触发淘汰"]
        E3["targetFree: 淘汰目标，保持此空间可用"]
        E4["checkInterval: 定时检查间隔"]
        E5["minAge: 文件最少存活时间"]
        E6["batchSize: 每批处理文件数"]
        E7["verifyBeforeDelete: 删除前验证 EXTERNAL"]
        E8["recallOnFrequentAccess: 是否启用按需召回"]
        E9["recallThreshold: 访问多少次后召回"]
    end

    EC1 --> E1
    EC2 --> E2
    EC3 --> E3
    EC4 --> E4
    EC5 --> E5
    EC6 --> E6
    EC7 --> E7
    EC8 --> E8
    EC9 --> E9
```

## 11.8 淘汰 XPC 接口

```mermaid
flowchart LR
    subgraph EvictionAPIs["淘汰相关 XPC 接口"]
        A1["getEvictionStatus(syncPairId)<br/>→ EvictionStatus"]
        A2["triggerEviction(syncPairId)<br/>→ Bool"]
        A3["cancelEviction(syncPairId)<br/>→ Bool"]
        A4["getEvictionCandidates(syncPairId, limit)<br/>→ [FileEntry]"]
        A5["setEvictionConfig(syncPairId, config)<br/>→ Bool"]
        A6["getEvictionStatistics(syncPairId)<br/>→ EvictionStatistics"]
        A7["excludeFromEviction(syncPairId, paths)<br/>→ Bool"]
        A8["recallFile(syncPairId, path)<br/>→ Bool"]
    end

    subgraph Descriptions["接口说明"]
        D1["获取当前淘汰状态"]
        D2["手动触发淘汰"]
        D3["取消正在进行的淘汰"]
        D4["预览将被淘汰的文件"]
        D5["更新淘汰配置"]
        D6["获取淘汰统计信息"]
        D7["排除指定文件不被淘汰"]
        D8["手动召回已淘汰文件到 LOCAL"]
    end

    A1 --> D1
    A2 --> D2
    A3 --> D3
    A4 --> D4
    A5 --> D5
    A6 --> D6
    A7 --> D7
    A8 --> D8
```

---

> 下一节: [12_完整启动时序](12_完整启动时序.md)
