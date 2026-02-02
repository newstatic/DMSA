# 八、索引构建流程

> 返回 [目录](00_README.md) | 上一节: [07_VFS预挂载机制](07_VFS预挂载机制.md)

---

## 8.1 版本管理机制

### 8.1.1 版本文件结构

每个目录下存储版本文件 `.dmsa/version.json`：

```
LOCAL_DIR/                      # ~/Downloads_Local
└── .dmsa/
    └── version.json            # 本地目录版本文件

EXTERNAL_DIR/                   # /Volumes/DISK/Downloads
└── .dmsa/
    └── version.json            # 外部目录版本文件
```

### 8.1.2 版本文件内容

```swift
struct DirectoryVersion: Codable {
    let syncPairId: String          // 同步对 ID
    let source: String              // "local" 或 "external"
    let directoryVersion: String    // 目录内容版本 (基于文件树哈希)
    let dbVersion: String           // 数据库中对应的版本
    let fileCount: Int              // 文件数量
    let totalSize: Int64            // 总大小 (bytes)
    let lastIndexedAt: Date         // 最后索引时间
    let indexDuration: TimeInterval // 索引耗时
    let schemaVersion: Int          // 版本文件格式版本 (用于升级)
}
```

```mermaid
classDiagram
    class DirectoryVersion {
        +syncPairId: String
        +source: String
        +directoryVersion: String
        +dbVersion: String
        +fileCount: Int
        +totalSize: Int64
        +lastIndexedAt: Date
        +indexDuration: TimeInterval
        +schemaVersion: Int
        +toJSON() Data
        +fromJSON(Data) DirectoryVersion?
    }

    class VersionManager {
        <<actor>>
        +readVersion(directory) DirectoryVersion?
        +writeVersion(directory, version)
        +validateVersion(directory, dbVersion) VersionValidation
        +invalidateVersion(directory)
        +computeDirectoryHash(directory) String
    }

    class VersionValidation {
        <<enum>>
        valid
        mismatch
        missing
        corrupted
        schemaOutdated
    }

    VersionManager --> DirectoryVersion
    VersionManager --> VersionValidation
```

### 8.1.3 版本校验流程

```mermaid
flowchart TD
    A[开始版本校验] --> B{版本文件存在?}

    B -->|否| C["VersionValidation = missing"]
    C --> C1["需要全量构建"]

    B -->|是| D[读取版本文件]
    D --> E{JSON 解析成功?}

    E -->|否| F["VersionValidation = corrupted"]
    F --> F1["需要全量构建"]

    E -->|是| G{schemaVersion 匹配?}

    G -->|否| H["VersionValidation = schemaOutdated"]
    H --> H1["需要全量构建 (格式升级)"]

    G -->|是| I{syncPairId 匹配?}

    I -->|否| J["VersionValidation = mismatch"]
    J --> J1["需要全量构建 (不同同步对)"]

    I -->|是| K[从数据库获取 dbVersion]
    K --> L{directoryVersion == dbVersion?}

    L -->|否| M["VersionValidation = mismatch"]
    M --> M1["需要全量构建 (版本不一致)"]

    L -->|是| N["VersionValidation = valid"]
    N --> N1["跳过索引，使用缓存"]

    style C1 fill:#FFD700
    style F1 fill:#FFD700
    style H1 fill:#FFD700
    style J1 fill:#FFD700
    style M1 fill:#FFD700
    style N1 fill:#90EE90
```

---

## 8.2 索引构建主流程 (含版本检查)

```mermaid
flowchart TD
    A["全局状态 = INDEXING"] --> A1["组件状态: Index = starting"]

    A1 --> B[遍历已挂载的 syncPairs]

    B --> C{还有 syncPair?}
    C -->|否| Z["所有索引完成"]
    C -->|是| D["处理 syncPair"]

    D --> E["组件状态: Index = busy"]

    E --> V1["检查 LOCAL_DIR 版本"]

    subgraph VersionCheckLocal["LOCAL_DIR 版本检查"]
        V1 --> V2{版本文件存在?}
        V2 -->|否| V3["需要全量构建 LOCAL"]
        V2 -->|是| V4[读取版本文件]
        V4 --> V5{版本一致?}
        V5 -->|否| V3
        V5 -->|是| V6["跳过 LOCAL 扫描<br/>使用数据库缓存"]
    end

    V3 --> F["全量扫描 LOCAL_DIR"]
    V6 --> G

    subgraph ScanLocal["扫描 LOCAL_DIR"]
        F --> F1{LOCAL_DIR 存在?}
        F1 -->|否| F2["记录: 目录不存在"]
        F2 --> F3["跳过 LOCAL 扫描"]
        F1 -->|是| F4[递归遍历目录]
        F4 --> F5{访问权限正常?}
        F5 -->|否| F6["记录错误: E_INDEX_PERMISSION"]
        F5 -->|是| F7[记录文件信息]
        F7 --> F8["location = localOnly"]
        F8 --> F9["计算 directoryVersion"]
    end

    F3 --> G
    F6 --> G
    F9 --> G

    G{EXTERNAL_DIR 已连接?}
    G -->|否| H["跳过 EXTERNAL 扫描"]
    G -->|是| V10["检查 EXTERNAL_DIR 版本"]

    subgraph VersionCheckExternal["EXTERNAL_DIR 版本检查"]
        V10 --> V11{版本文件存在?}
        V11 -->|否| V12["需要全量构建 EXTERNAL"]
        V11 -->|是| V13[读取版本文件]
        V13 --> V14{版本一致?}
        V14 -->|否| V12
        V14 -->|是| V15["跳过 EXTERNAL 扫描<br/>使用数据库缓存"]
    end

    V12 --> I["全量扫描 EXTERNAL_DIR"]
    V15 --> J

    subgraph ScanExternal["扫描 EXTERNAL_DIR"]
        I --> I1{EXTERNAL_DIR 存在?}
        I1 -->|否| I2["记录: 目录不存在"]
        I2 --> I3["跳过 EXTERNAL 扫描"]
        I1 -->|是| I4[递归遍历目录]
        I4 --> I5{访问权限正常?}
        I5 -->|否| I6["记录错误: E_INDEX_PERMISSION"]
        I5 -->|是| I7[记录文件信息]
        I7 --> I8["location = externalOnly"]
        I8 --> I9["计算 directoryVersion"]
    end

    H --> J
    I3 --> J
    I6 --> J
    I9 --> J

    J[合并索引]

    subgraph Merge["合并逻辑"]
        J --> K["LOCAL ∩ EXTERNAL → both"]
        J --> L["仅 LOCAL → localOnly"]
        J --> M["仅 EXTERNAL → externalOnly"]
    end

    K & L & M --> N{保存到 ObjectBox}
    N -->|失败| N1["记录错误: E_INDEX_SAVE_FAILED"]
    N1 --> N2["重试 3 次"]
    N2 --> N3{重试成功?}
    N3 -->|否| N4["组件状态: Index = error"]
    N3 -->|是| O

    N -->|成功| O["生成新 dbVersion"]

    O --> W1["写入 LOCAL_DIR 版本文件"]
    W1 --> W2["写入 EXTERNAL_DIR 版本文件"]

    W2 --> P["设置 indexReady = true"]
    P --> Q["缓存通知: indexProgress"]

    Q --> C

    Z --> Z1["组件状态: Index = ready"]
    Z1 --> Z2["全局状态 = READY"]
    Z2 --> Z3["缓存通知: indexReady"]

    style V6 fill:#90EE90
    style V15 fill:#90EE90
    style P fill:#90EE90
    style Z2 fill:#90EE90
    style N4 fill:#FF6B6B
    style V3 fill:#FFD700
    style V12 fill:#FFD700
```

---

## 8.3 版本计算方法

```mermaid
flowchart TD
    A[计算目录版本] --> B[遍历目录所有文件]

    B --> C[收集文件信息]

    subgraph FileInfo["每个文件收集"]
        C --> C1["relativePath: 相对路径"]
        C --> C2["size: 文件大小"]
        C --> C3["mtime: 修改时间"]
    end

    C1 & C2 & C3 --> D["排序文件列表 (按路径)"]

    D --> E["拼接所有文件信息"]
    E --> E1["path1:size1:mtime1\\n"]
    E --> E2["path2:size2:mtime2\\n"]
    E --> E3["..."]

    E1 & E2 & E3 --> F["计算 SHA256 哈希"]
    F --> G["取前 16 位作为 directoryVersion"]

    G --> H["示例: a1b2c3d4e5f67890"]

    subgraph VersionFormat["版本格式"]
        H --> H1["16 位十六进制字符串"]
        H --> H2["基于文件树内容"]
        H --> H3["任何文件变更都会改变版本"]
    end
```

---

## 8.4 索引进度通知

```mermaid
flowchart LR
    subgraph Progress["IndexProgress 结构"]
        A["syncPairId: String"]
        B["phase: String"]
        C["scannedFiles: Int"]
        D["totalEstimate: Int?"]
        E["currentPath: String?"]
        F["progress: Double"]
        G["errors: [IndexError]?"]
        H["versionStatus: String"]
        I["skippedByCache: Bool"]
    end

    subgraph Phases["扫描阶段"]
        P1["version_check"]
        P2["scanning_local"]
        P3["scanning_external"]
        P4["merging"]
        P5["saving"]
        P6["writing_version"]
        P7["completed"]
        P8["failed"]
    end

    B --> P1
    B --> P2
    B --> P3
    B --> P4
    B --> P5
    B --> P6
    B --> P7
    B --> P8
```

---

## 8.5 各操作的版本更新策略

| 操作 | LOCAL 版本 | EXTERNAL 版本 | 更新时机 |
|------|------------|---------------|----------|
| **索引构建** | ✅ 更新 | ✅ 更新 | 构建完成后立即更新 |
| **文件同步** | ❌ 不变 | ✅ 更新 | 同步批次完成后更新 |
| **冲突解决 (keepLocal)** | ❌ 不变 | ✅ 更新 | 解决后立即更新 |
| **冲突解决 (keepExternal)** | ✅ 更新 | ❌ 不变 | 解决后立即更新 |
| **冲突解决 (keepBoth)** | ✅ 更新 | ✅ 更新 | 解决后立即更新 |
| **淘汰操作** | ✅ 更新 | ❌ 不变 | 淘汰批次完成后更新 |
| **VFS 写入** | ✅ 标记失效 | ❌ 不变 | 延迟更新 (下次同步时) |

---

> 下一节: [09_文件同步流程](09_文件同步流程.md)
