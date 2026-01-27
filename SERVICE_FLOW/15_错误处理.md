# 十五、错误处理

> 返回 [目录](00_README.md) | 上一节: [14_分布式通知](14_分布式通知.md)

---

## 15.1 错误分类与处理

```mermaid
flowchart TD
    subgraph FatalErrors["致命错误 (无法恢复)"]
        F1["macFUSE 未安装"]
        F2["macFUSE 版本不兼容"]
        F3["系统权限不足"]
    end

    subgraph RecoverableErrors["可恢复错误"]
        R1["配置文件损坏"]
        R2["挂载点被占用"]
        R3["索引构建失败"]
        R4["数据库损坏"]
        R5["磁盘断开连接"]
    end

    subgraph WarningErrors["警告 (可继续运行)"]
        W1["部分目录无权限"]
        W2["配置字段缺失"]
        W3["配置有冲突"]
        W4["同步跳过文件"]
    end

    F1 --> FA["通知 App 引导安装<br/>服务进入 ERROR 状态"]
    F2 --> FA
    F3 --> FA

    R1 --> RA["使用备份/默认配置<br/>继续启动"]
    R2 --> RB["尝试卸载后重试<br/>最多 3 次"]
    R3 --> RC["重试索引<br/>最多 3 次"]
    R4 --> RD["重建数据库<br/>重新索引"]
    R5 --> RE["标记 EXTERNAL 离线<br/>继续使用 LOCAL"]

    W1 --> WA["记录警告<br/>跳过该目录"]
    W2 --> WB["使用默认值<br/>通知 App"]
    W3 --> WC["自动解决<br/>通知 App"]
    W4 --> WD["记录日志<br/>继续同步"]
```

## 15.2 错误恢复接口

```mermaid
flowchart LR
    subgraph Recovery["App 可调用的恢复方法"]
        M1["retryVFSMount(syncPairId)"]
        M2["rebuildIndex(syncPairId)"]
        M3["resetConfig()"]
        M4["rebuildDatabase()"]
        M5["resetService()"]
    end

    M1 --> R1["重新尝试 FUSE 挂载"]
    M2 --> R2["重新构建文件索引"]
    M3 --> R3["重置为默认配置"]
    M4 --> R4["重建 ObjectBox 数据库"]
    M5 --> R5["重置服务到初始状态"]
```

## 15.3 错误码汇总

| 错误码 | 名称 | 说明 | 可恢复 |
|--------|------|------|--------|
| 1001 | E_XPC_LISTEN_FAILED | XPC 监听器启动失败 | 否 |
| 1002 | E_XPC_CONNECTION_INVALID | XPC 连接验证失败 | 是 |
| 1003 | E_XPC_TIMEOUT | XPC 调用超时 | 是 |
| 2001 | E_CONFIG_NOT_FOUND | 配置文件不存在 | 是 |
| 2002 | E_CONFIG_PARSE_FAILED | JSON 解析失败 | 是 |
| 2003 | E_CONFIG_INVALID | 配置验证失败 | 是 |
| 2004 | E_CONFIG_CONFLICT | 配置冲突 | 是 |
| 3001 | E_VFS_FUSE_NOT_INSTALLED | macFUSE 未安装 | 否 |
| 3002 | E_VFS_FUSE_VERSION | macFUSE 版本过低 | 否 |
| 3003 | E_VFS_MOUNT_FAILED | 挂载失败 | 是 |
| 3004 | E_VFS_PERMISSION | 权限不足 | 否 |
| 3005 | E_VFS_MOUNT_BUSY | 挂载点被占用 | 是 |
| 4001 | E_INDEX_SCAN_FAILED | 目录扫描失败 | 是 |
| 4002 | E_INDEX_PERMISSION | 目录访问权限不足 | 否 |
| 4003 | E_INDEX_SAVE_FAILED | 索引保存失败 | 是 |
| 5001 | E_SYNC_SOURCE_UNAVAILABLE | 源目录不可访问 | 是 |
| 5002 | E_SYNC_TARGET_READONLY | 目标只读 | 是 |
| 5003 | E_SYNC_CONFLICT | 文件冲突 | 是 |
| 5004 | E_SYNC_DISK_FULL | 磁盘空间不足 | 是 |
| 6001 | E_DB_OPEN_FAILED | 数据库打开失败 | 是 |
| 6002 | E_DB_CORRUPTED | 数据库损坏 | 是 |
| 6003 | E_DB_WRITE_FAILED | 写入失败 | 是 |

---

> 下一节: [16_日志规范](16_日志规范.md)
