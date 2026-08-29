# Phase 1 Data Model: 容器 CPU 与内存指标

## ContainerResourceSample

一次 CLI 统计输出中的原始、已校验样本，仅用于服务内部计算。

| 字段 | 类型 | 约束 |
|---|---|---|
| `containerID` | `String` | 必需且非空，映射 CLI `id` |
| `cpuUsageUsec` | `UInt64` | 必需，累计 CPU 微秒，不允许负数 |
| `memoryUsageBytes` | `UInt64` | 必需，不允许负数 |
| `memoryLimitBytes` | `UInt64` | 必需，不允许负数；零表示百分比未知 |
| `observedAt` | `Date` | 服务收到完整 CLI 快照的时间 |

未知 JSON 字段忽略；缺少任一必需字段、类型错误、空 ID、负数或根节点不是数组时，拒绝整个快照。

## ContainerResourceUsage

提供给 HTTP 客户端的单容器派生结果。

| 字段 | 类型 | 约束/含义 |
|---|---|---|
| `containerId` | `String` | 对应资源样本 ID |
| `cpuPercent` | `Double?` | 有连续合法样本时提供；可大于 100 |
| `cpuState` | `sampling \| ready` | `sampling` 时 `cpuPercent` 必须为空 |
| `memoryUsageBytes` | `UInt64` | 当前权威用量 |
| `memoryLimitBytes` | `UInt64` | 当前权威上限 |
| `memoryPercent` | `Double?` | 上限大于零时提供；必须有限且非负 |
| `observedAt` | `Date` | 当前样本时间 |

计算公式：

```text
elapsedWallUsec = current.observedAt - previous.observedAt（微秒）
cpuPercent = (current.cpuUsageUsec - previous.cpuUsageUsec) / elapsedWallUsec * 100
memoryPercent = current.memoryUsageBytes / current.memoryLimitBytes * 100
```

## ContainerMetricsSnapshot

一次 API 返回的完整指标集合。

| 字段 | 类型 | 约束 |
|---|---|---|
| `items` | `[ContainerResourceUsage]` | 仅含本次 CLI 返回的运行中容器；ID 唯一 |
| `observedAt` | `Date` | 本次快照共同观测时间 |

## 状态转换

```text
无上一样本 ──成功样本──> sampling
sampling/ready ──下一个连续样本──> ready
sampling/ready ──计数器下降或非正时间差──> sampling
sampling/ready ──本轮 ID 消失──> 删除上一样本
任意状态 ──CLI/解析失败──> API 失败；不发布部分结果
```

失败快照不会伪造数值。下一次成功快照仍可与最后一次成功样本比较；若容器已经从成功快照中消失，
其上一样本已删除。
