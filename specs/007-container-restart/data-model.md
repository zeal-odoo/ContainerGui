# Data Model: 容器重启

## Restart Request

一次面向精确容器标识的确认请求。

| Field | Type | Rules |
|---|---|---|
| containerId | String | 来自路径；沿用现有安全标识格式 |
| confirmationTarget | String | 必须与 `containerId` 完全一致 |
| idempotencyKey | UUID string | 必须存在；相同键与相同指纹重放同一操作 |

## Restart Operation

复用现有 `Operation`，增加 `restartContainer` 类型。

| Attribute | Meaning |
|---|---|
| kind | `restartContainer`，区别于单独启动或停止 |
| target | 单一容器目标，参与现有目标互斥 |
| state | queued → running → verifying → succeeded；任一阶段可进入 failed |
| safeRequestSummary | 仅包含容器标识、正常停止宽限时间和操作序列，不含秘密 |
| exitCode | 最后完成的变更阶段退出码；失败抛出时可为空 |
| readback | 可获得的实际容器摘要与是否满足最终运行状态 |

## State Transitions

```text
running container
  -> restart queued
  -> operation running
  -> graceful stop requested
  -> stopped readback required
  -> start requested
  -> running readback required
  -> operation verifying
  -> operation succeeded
```

失败分支：

- 前置状态不是 running：请求在创建操作前被拒绝。
- stop 抛错或回读不是 stopped：不调用 start，操作 failed。
- start 抛错或回读不是 running：操作 failed，并尽力附带实际状态。
- 同目标已有操作：请求被现有目标锁拒绝。

## Persistence

不新增持久化存储。操作沿用现有短期内存 TTL；容器最终状态始终来自 CLI。
