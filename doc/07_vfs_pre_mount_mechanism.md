# 七、VFS 预挂载机制

> 返回 [目录](00_README.md) | 上一节: [06_XPC优先启动](06_XPC优先启动.md)

---

## 7.1 预挂载目的

```mermaid
flowchart LR
    subgraph 目的["预挂载的目的"]
        A["占位"]
        B["阻塞"]
        C["保护"]
    end

    A --> A1["立即挂载 ~/Downloads"]
    A1 --> A2["防止用户直接访问后端"]

    B --> B1["索引未完成时拒绝访问"]
    B1 --> B2["避免返回不完整数据"]

    C --> C1["挂载后保护 LOCAL_DIR"]
    C1 --> C2["挂载后保护 EXTERNAL_DIR"]
```

## 7.2 挂载流程详解

```mermaid
flowchart TD
    A["全局状态 = VFS_MOUNTING"] --> A1["组件状态: VFS = starting"]

    A1 --> B{配置中有 syncPairs?}
    B -->|否| B1["组件状态: VFS = ready (无挂载)"]
    B1 --> B2["跳转到 READY 状态"]

    B -->|是| C[遍历 syncPairs]

    C --> D{syncPair.enabled?}
    D -->|否| C
    D -->|是| E{对应 disk 配置存在?}

    E -->|否| E1["记录错误: disk 配置缺失"]
    E1 --> E2["跳过此 syncPair"]
    E2 --> C

    E -->|是| F{检查 TARGET_DIR 状态}

    F -->|已是 FUSE 挂载| G1[先卸载现有挂载]
    F -->|是符号链接| G2[删除符号链接]
    F -->|是有内容目录| G3[重命名为 LOCAL_DIR]
    F -->|是空目录| G4[删除空目录]
    F -->|不存在| G5[跳过]

    G1 & G2 & G3 & G4 & G5 --> H[创建挂载点目录]

    H --> I["创建 FUSEFileSystem 实例"]
    I --> I1["syncPairId"]
    I --> I2["localDir"]
    I --> I3["externalDir (可为 nil)"]
    I --> I4["targetDir"]
    I --> I5["indexReady = false ⚠️"]

    I1 & I2 & I3 & I4 & I5 --> J["执行 FUSE 挂载"]
    J --> K{挂载成功?}

    K -->|否| K1["组件状态: VFS = error"]
    K1 --> K2["记录错误: E_VFS_MOUNT_FAILED"]
    K2 --> K3["缓存错误通知"]
    K3 --> C

    K -->|是| L["mount(blocking: true)"]

    L --> M[保护后端目录]
    M --> M1["LOCAL_DIR: chmod 700"]
    M --> M2["LOCAL_DIR: ACL deny"]
    M --> M3["EXTERNAL_DIR: chmod 700"]
    M --> M4["EXTERNAL_DIR: ACL deny"]

    M1 & M2 & M3 & M4 --> N{还有更多 syncPairs?}
    N -->|是| C
    N -->|否| O["组件状态: VFS = ready"]

    O --> P["全局状态 = VFS_BLOCKED"]
    P --> Q["缓存通知: vfsMounted"]

    style I5 fill:#FFB6C1
    style P fill:#FFD700
    style K1 fill:#FF6B6B
```

## 7.3 阻塞状态访问处理

```mermaid
flowchart TD
    A["用户访问 ~/Downloads"] --> B{检查 indexReady}

    B -->|false| C["返回 -EBUSY"]
    B -->|true| D[正常处理请求]

    C --> C1["Finder: 显示资源忙"]
    C --> C2["ls: Resource busy"]
    C --> C3["cat: Resource busy"]

    D --> E{请求类型}
    E -->|readdir| F[合并 LOCAL + EXTERNAL]
    E -->|read| G[从 LOCAL 或 EXTERNAL 读取]
    E -->|write| H[写入 LOCAL 并标记脏]
    E -->|getattr| I[返回文件属性]

    subgraph 例外["唯一例外"]
        J["getattr '/' 根目录"]
        J --> K["始终允许，返回目录属性"]
    end

    style C fill:#FF6B6B
    style D fill:#90EE90
```

## 7.4 阻塞状态行为对照表

```mermaid
flowchart LR
    subgraph VFS_BLOCKED["VFS_BLOCKED 状态"]
        A1["readdir → EBUSY"]
        A2["read → EBUSY"]
        A3["write → EBUSY"]
        A4["getattr / → 允许"]
        A5["getattr /file → EBUSY"]
    end

    subgraph READY["READY 状态"]
        B1["readdir → 目录列表"]
        B2["read → 文件内容"]
        B3["write → 正常写入"]
        B4["getattr / → 允许"]
        B5["getattr /file → 文件属性"]
    end

    A1 -.->|索引完成后| B1
    A2 -.->|索引完成后| B2
    A3 -.->|索引完成后| B3
```

---

## 7.5 VFS 文件操作处理流程

当用户通过 `~/Downloads` (TARGET_DIR) 对文件进行操作时，VFS 层会拦截并处理这些操作。

### 7.5.1 操作类型总览

```mermaid
flowchart TD
    subgraph 用户操作["用户在 ~/Downloads 的操作"]
        O1["创建文件 (create/mknod)"]
        O2["写入文件 (write)"]
        O3["修改文件 (truncate/utimens)"]
        O4["删除文件 (unlink)"]
        O5["创建目录 (mkdir)"]
        O6["删除目录 (rmdir)"]
        O7["重命名 (rename)"]
        O8["读取文件 (read)"]
        O9["列出目录 (readdir)"]
    end

    subgraph 处理策略["VFS 处理策略"]
        S1["写入 LOCAL_DIR"]
        S2["标记 isDirty"]
        S3["触发异步同步"]
        S4["更新数据库"]
        S5["从 LOCAL/EXTERNAL 读取"]
        S6["合并目录列表"]
    end

    O1 --> S1
    O2 --> S1
    O3 --> S1
    O1 & O2 & O3 --> S2
    S2 --> S3
    O4 & O5 & O6 & O7 --> S4
    O8 --> S5
    O9 --> S6
```

### 7.5.2 创建新文件流程 (create)

```mermaid
flowchart TD
    A["用户创建文件<br/>~/Downloads/newfile.txt"] --> B{indexReady?}

    B -->|false| B1["返回 -EBUSY"]
    B -->|true| C["解析相对路径<br/>relPath = newfile.txt"]

    C --> D["构建 LOCAL 路径<br/>~/Downloads_Local/newfile.txt"]

    D --> E{父目录存在?}
    E -->|否| E1["创建父目录 (递归)"]
    E1 --> F
    E -->|是| F["创建文件"]

    F --> G{创建成功?}
    G -->|否| G1["返回错误码"]

    G -->|是| H["创建/更新 FileEntry"]
    H --> H1["path: relPath"]
    H --> H2["location: .localOnly"]
    H --> H3["isDirty: true ⚠️"]
    H --> H4["size: 0"]
    H --> H5["mtime: now"]
    H --> H6["accessTime: now"]

    H1 & H2 & H3 & H4 & H5 & H6 --> I["写入数据库"]

    I --> J["加入脏文件队列"]
    J --> K["触发同步调度检查"]
    K --> L["返回文件句柄"]

    style H3 fill:#FFB6C1
    style J fill:#FFD700
```

### 7.5.3 写入文件流程 (write)

```mermaid
flowchart TD
    A["用户写入文件<br/>write(fd, data, size, offset)"] --> B{indexReady?}

    B -->|false| B1["返回 -EBUSY"]
    B -->|true| C["获取文件路径"]

    C --> D{文件在 LOCAL?}

    D -->|否| D1["检查 EXTERNAL 是否存在"]
    D1 --> D2{存在?}
    D2 -->|否| D3["返回 -ENOENT"]
    D2 -->|是| D4["复制文件到 LOCAL (copy-on-write)"]
    D4 --> E

    D -->|是| E["写入 LOCAL 文件"]

    E --> F{写入成功?}
    F -->|否| F1["返回错误码"]

    F -->|是| G["更新 FileEntry"]
    G --> G1["size: 新大小"]
    G --> G2["mtime: now"]
    G --> G3["isDirty: true"]
    G --> G4["location: localOnly 或 both"]

    G1 & G2 & G3 & G4 --> H["更新数据库"]

    H --> I{之前是脏文件?}
    I -->|否| I1["加入脏文件队列"]
    I -->|是| I2["更新队列中的时间戳"]

    I1 & I2 --> J["返回写入字节数"]

    subgraph COW["Copy-on-Write 机制"]
        D4
        note["首次写入时从 EXTERNAL 复制到 LOCAL"]
    end

    style G3 fill:#FFB6C1
    style D4 fill:#87CEEB
```

### 7.5.4 修改文件属性流程 (truncate/utimens)

```mermaid
flowchart TD
    A["用户修改文件属性"] --> B{操作类型}

    B -->|truncate| C["截断文件大小"]
    B -->|utimens| D["修改时间戳"]
    B -->|chmod| E["修改权限"]

    C --> F{文件在 LOCAL?}
    D --> F
    E --> F

    F -->|否| F1["复制到 LOCAL (如果修改内容)"]
    F1 --> G
    F -->|是| G["执行属性修改"]

    G --> H{修改成功?}
    H -->|否| H1["返回错误码"]

    H -->|是| I["更新 FileEntry"]
    I --> I1["更新 size (truncate)"]
    I --> I2["更新 mtime"]
    I --> I3["isDirty: true"]

    I1 & I2 & I3 --> J["更新数据库"]
    J --> K["加入/更新脏文件队列"]
    K --> L["返回成功"]

    style I3 fill:#FFB6C1
```

### 7.5.5 删除文件流程 (unlink)

```mermaid
flowchart TD
    A["用户删除文件<br/>~/Downloads/file.txt"] --> B{indexReady?}

    B -->|false| B1["返回 -EBUSY"]
    B -->|true| C["查询 FileEntry"]

    C --> D{FileEntry 存在?}
    D -->|否| D1["返回 -ENOENT"]

    D -->|是| E{检查 location}

    E -->|localOnly| F["删除 LOCAL 文件"]
    E -->|externalOnly| G["标记为待删除"]
    E -->|both| H["删除 LOCAL + 标记 EXTERNAL 待删除"]

    F --> F1{删除成功?}
    F1 -->|是| F2["从数据库删除 FileEntry"]
    F1 -->|否| F3["返回错误码"]

    G --> G1["创建 DeletePending 记录"]
    G1 --> G2["FileEntry.pendingDelete = true"]
    G2 --> G3["从 VFS 视图隐藏"]

    H --> H1["删除 LOCAL 文件"]
    H1 --> H2["创建 DeletePending 记录"]
    H2 --> H3["等待同步时删除 EXTERNAL"]

    F2 --> I["从脏文件队列移除 (如有)"]
    G3 --> I
    H3 --> I

    I --> J["返回成功"]

    subgraph 延迟删除["延迟删除机制"]
        direction TB
        G1
        G2
        G3
        note2["EXTERNAL 文件在下次同步时删除"]
    end

    style G fill:#FFA500
    style H fill:#FFA500
```

### 7.5.6 删除待同步处理

```mermaid
flowchart TD
    A["同步调度器触发"] --> B["获取 DeletePending 列表"]

    B --> C{EXTERNAL 磁盘在线?}
    C -->|否| C1["跳过，等待下次"]

    C -->|是| D["遍历待删除文件"]

    D --> E{EXTERNAL 文件存在?}
    E -->|否| E1["清理 DeletePending 记录"]

    E -->|是| F["删除 EXTERNAL 文件"]
    F --> G{删除成功?}

    G -->|否| G1["记录错误，保留待删除状态"]
    G -->|是| H["清理 DeletePending 记录"]

    H --> I["从数据库删除 FileEntry"]
    E1 --> I

    I --> J{还有待删除文件?}
    J -->|是| D
    J -->|否| K["删除同步完成"]
```

### 7.5.7 创建目录流程 (mkdir)

```mermaid
flowchart TD
    A["用户创建目录<br/>~/Downloads/newdir"] --> B{indexReady?}

    B -->|false| B1["返回 -EBUSY"]
    B -->|true| C["解析路径"]

    C --> D{目录已存在?}
    D -->|是| D1["返回 -EEXIST"]

    D -->|否| E["在 LOCAL_DIR 创建目录"]
    E --> F{创建成功?}

    F -->|否| F1["返回错误码"]
    F -->|是| G["创建 FileEntry (目录)"]

    G --> G1["isDirectory: true"]
    G --> G2["location: .localOnly"]
    G --> G3["isDirty: true"]

    G1 & G2 & G3 --> H["写入数据库"]
    H --> I["返回成功"]

    style G3 fill:#FFB6C1
```

### 7.5.8 删除目录流程 (rmdir)

```mermaid
flowchart TD
    A["用户删除目录<br/>~/Downloads/dir"] --> B{indexReady?}

    B -->|false| B1["返回 -EBUSY"]
    B -->|true| C["查询目录 FileEntry"]

    C --> D{目录存在?}
    D -->|否| D1["返回 -ENOENT"]

    D -->|是| E{目录为空?}
    E -->|否| E1["返回 -ENOTEMPTY"]

    E -->|是| F{检查 location}

    F -->|localOnly| G["删除 LOCAL 目录"]
    F -->|externalOnly| H["标记待删除"]
    F -->|both| I["删除 LOCAL + 标记待删除"]

    G --> J["从数据库删除 FileEntry"]
    H --> K["创建 DeletePending"]
    I --> J
    I --> K

    J --> L["返回成功"]
    K --> L
```

### 7.5.9 重命名流程 (rename)

```mermaid
flowchart TD
    A["用户重命名<br/>oldpath → newpath"] --> B{indexReady?}

    B -->|false| B1["返回 -EBUSY"]
    B -->|true| C["解析源路径和目标路径"]

    C --> D{源文件存在?}
    D -->|否| D1["返回 -ENOENT"]

    D -->|是| E{目标已存在?}
    E -->|是| E1["删除目标 (覆盖)"]

    E -->|否| F{源文件 location?}
    E1 --> F

    F -->|localOnly| G["重命名 LOCAL 文件"]
    F -->|externalOnly| H["复制到 LOCAL 新位置"]
    F -->|both| I["重命名 LOCAL + 标记旧 EXTERNAL 待删除"]

    G --> J["更新 FileEntry.path"]
    H --> J1["创建新 FileEntry"]
    H --> J2["标记旧文件待删除"]
    I --> J
    I --> J2

    J --> K["isDirty: true"]
    J1 --> K

    K --> L["更新数据库"]
    L --> M["返回成功"]

    style K fill:#FFB6C1
```

### 7.5.10 读取文件流程 (read)

```mermaid
flowchart TD
    A["用户读取文件<br/>read(fd, buf, size, offset)"] --> B{indexReady?}

    B -->|false| B1["返回 -EBUSY"]
    B -->|true| C["获取文件 FileEntry"]

    C --> D{FileEntry 存在?}
    D -->|否| D1["返回 -ENOENT"]

    D -->|是| E{检查 location}

    E -->|localOnly| F["从 LOCAL 读取"]
    E -->|externalOnly| G{EXTERNAL 磁盘在线?}
    E -->|both| H["优先从 LOCAL 读取"]

    G -->|否| G1["返回 -EIO 或 -ENOENT"]
    G -->|是| G2["从 EXTERNAL 读取 (零拷贝)"]

    F --> I["读取数据"]
    G2 --> I
    H --> I

    I --> J["更新 accessTime"]
    J --> K["返回数据"]

    subgraph 零拷贝["零拷贝读取"]
        G2
        note3["直接从 EXTERNAL 读取，不复制到 LOCAL"]
    end

    style G2 fill:#90EE90
```

### 7.5.11 列出目录流程 (readdir)

```mermaid
flowchart TD
    A["用户列出目录<br/>ls ~/Downloads"] --> B{indexReady?}

    B -->|false| B1["返回 -EBUSY"]
    B -->|true| C["获取目录路径"]

    C --> D["查询数据库中该目录下的所有 FileEntry"]

    D --> E["过滤 pendingDelete = true 的条目"]

    E --> F["构建目录列表"]
    F --> F1[". (当前目录)"]
    F --> F2[".. (父目录)"]
    F --> F3["子文件和目录"]

    F1 & F2 & F3 --> G["返回目录列表"]

    subgraph 智能合并["智能合并视图"]
        direction TB
        H1["LOCAL_DIR 的文件"]
        H2["EXTERNAL_DIR 的文件"]
        H3["合并去重后的完整列表"]
        H1 --> H3
        H2 --> H3
    end

    note["用户看到的是 LOCAL ∪ EXTERNAL 的并集"]
```

### 7.5.12 文件操作与同步的关系

```mermaid
flowchart LR
    subgraph VFS层["VFS 文件操作"]
        V1["create"]
        V2["write"]
        V3["truncate"]
        V4["unlink"]
        V5["rename"]
    end

    subgraph 数据库["数据库更新"]
        D1["FileEntry 创建"]
        D2["FileEntry 更新"]
        D3["FileEntry 删除/标记"]
        D4["isDirty = true"]
    end

    subgraph 同步层["同步调度"]
        S1["脏文件队列"]
        S2["DeletePending 队列"]
        S3["定时同步检查"]
        S4["同步到 EXTERNAL"]
    end

    V1 --> D1
    V2 --> D2
    V3 --> D2
    V4 --> D3
    V5 --> D2

    D1 & D2 --> D4
    D4 --> S1
    D3 --> S2

    S1 --> S3
    S2 --> S3
    S3 --> S4
```

### 7.5.13 操作错误码对照表

| 操作 | 错误场景 | 返回码 | 说明 |
|------|----------|--------|------|
| 所有操作 | 索引未就绪 | `-EBUSY` | 等待索引完成 |
| create | 文件已存在 | `-EEXIST` | 文件名冲突 |
| create | 磁盘空间不足 | `-ENOSPC` | LOCAL 空间不足 |
| write | 文件不存在 | `-ENOENT` | 文件被删除 |
| write | 磁盘空间不足 | `-ENOSPC` | 触发紧急淘汰 |
| read | 文件不存在 | `-ENOENT` | 文件被删除 |
| read | EXTERNAL 离线 | `-EIO` | 仅外部文件时 |
| unlink | 文件不存在 | `-ENOENT` | - |
| rmdir | 目录不存在 | `-ENOENT` | - |
| rmdir | 目录非空 | `-ENOTEMPTY` | 需先删除内容 |
| rename | 源文件不存在 | `-ENOENT` | - |
| mkdir | 目录已存在 | `-EEXIST` | - |

---

> 下一节: [08_索引构建流程](08_索引构建流程.md)
