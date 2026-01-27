# 十四、分布式通知

> 返回 [目录](00_README.md) | 上一节: [13_App端交互流程](13_App端交互流程.md)

---

```mermaid
flowchart TB
    subgraph Notifications["通知事件"]
        N1["stateChanged"]
        N2["xpcReady"]
        N3["configStatus"]
        N4["configConflict"]
        N5["vfsMounted"]
        N6["indexProgress"]
        N7["indexReady"]
        N8["serviceReady"]
        N9["serviceError"]
        N10["componentError"]
    end

    subgraph Triggers["触发条件"]
        T1["全局状态变更"]
        T2["XPC 监听器启动"]
        T3["配置加载/修补"]
        T4["检测到配置冲突"]
        T5["VFS 挂载完成"]
        T6["索引进度更新"]
        T7["索引完成"]
        T8["服务完全就绪"]
        T9["全局错误"]
        T10["组件错误"]
    end

    subgraph Data["携带数据"]
        D1["oldState, newState, timestamp"]
        D2["version, protocolVersion"]
        D3["isPatched, patchedFields"]
        D4["conflicts[], requiresUserAction"]
        D5["syncPairIds, mountPoints"]
        D6["progress, phase, scannedFiles, errors"]
        D7["totalFiles, totalSize, duration"]
        D8["完整 ServiceFullState"]
        D9["errorCode, errorMessage, context"]
        D10["component, errorCode, errorMessage, recoverable"]
    end

    N1 --- T1 --- D1
    N2 --- T2 --- D2
    N3 --- T3 --- D3
    N4 --- T4 --- D4
    N5 --- T5 --- D5
    N6 --- T6 --- D6
    N7 --- T7 --- D7
    N8 --- T8 --- D8
    N9 --- T9 --- D9
    N10 --- T10 --- D10
```

## 通知类型详情

| 通知类型 | 触发条件 | 携带数据 |
|----------|----------|----------|
| stateChanged | 全局状态变更 | oldState, newState, timestamp |
| xpcReady | XPC 监听器启动 | version, protocolVersion |
| configStatus | 配置加载/修补 | isPatched, patchedFields |
| configConflict | 检测到配置冲突 | conflicts[], requiresUserAction |
| vfsMounted | VFS 挂载完成 | syncPairIds, mountPoints |
| indexProgress | 索引进度更新 | progress, phase, scannedFiles, errors |
| indexReady | 索引完成 | totalFiles, totalSize, duration |
| serviceReady | 服务完全就绪 | 完整 ServiceFullState |
| serviceError | 全局错误 | errorCode, errorMessage, context |
| componentError | 组件错误 | component, errorCode, errorMessage, recoverable |

---

> 下一节: [15_错误处理](15_错误处理.md)
