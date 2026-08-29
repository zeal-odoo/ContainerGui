# Phase 1 Data Model: 容器存储容量

## ContainerRootFilesystemUsage

提供给客户端的单容器根文件系统容量结果。

| 字段 | 类型 | 约束/含义 |
|---|---|---|
| `state` | `ready \| unavailable` | `ready` 时所有数值必须存在且合法；`unavailable` 时不得伪造零值 |
| `usedBytes` | `UInt64?` | 根文件系统已用字节；不得大于总容量 |
| `capacityBytes` | `UInt64?` | 根文件系统可见总字节；`ready` 时必须大于零 |
| `availableBytes` | `UInt64?` | 根文件系统可用字节；不得大于总容量 |
| `usagePercent` | `Double?` | `usedBytes / capacityBytes × 100`；必须有限且位于 0...100 |

## ContainerResourceUsage 增量

现有 CPU 与内存指标条目新增：

| 字段 | 类型 | 约束/含义 |
|---|---|---|
| `rootFilesystem` | `ContainerRootFilesystemUsage` | 每个实际 API 条目必须提供；单容器失败时为 `unavailable` |

现有 `containerId`、CPU、内存与 `observedAt` 语义不变。

## 容量状态转换

```text
运行中 + 有效容量输出 ──> ready（展示使用率与已用 / 总容量）
运行中 + 命令失败/超时/无工具/格式无效 ──> unavailable（展示暂不可用）
停止或尚未运行 ──> 不进入资源指标条目，由列表状态展示未运行
下一轮有效读取 ──> 从 unavailable 恢复为 ready
```

容量结果不持久化。每个自动刷新周期都以当前运行状态和当前根文件系统读取为准。
