# Phase 0 Research: 容器 CPU 与内存指标

## 1. 权威统计命令

**Decision**: 使用固定参数数组 `container stats --no-stream --format json`，一次读取全部运行中容器。

**Rationale**:

- 当前本机 CLI 1.3.1 的帮助明确支持 `stats [<containers> ...]`、`--no-stream` 和 JSON 格式。
- 真实只读样本提供 `id`、`cpuUsageUsec`、`memoryUsageBytes`、`memoryLimitBytes` 等字段。
- Apple 文档说明 `stats` 用于监视 CPU 和内存，结构化格式适合机器解析。
- 不传容器 ID 可以形成同一观测批次，且不需要把任何浏览器输入传给 CLI。

**Alternatives considered**:

- 解析默认表格输出：拒绝；列宽、单位和本地化文本不如 JSON 稳定。
- 为每个容器分别执行命令：拒绝；会增加进程数、观测偏差和并发压力。
- 直接链接 Containerization 内部 API：拒绝；超出宪章和当前兼容边界。

## 2. CPU 百分比口径

**Decision**: 对同一容器的两个相邻权威样本计算
`(current.cpuUsageUsec - previous.cpuUsageUsec) / elapsedWallUsec * 100`。

**Rationale**:

- JSON 字段是累计 CPU 微秒，不是瞬时百分比；单个样本无法诚实计算 CPU 使用率。
- Apple 的表格语义是 100% 表示使用一个完整核心，因此多核工作负载可超过 100%。
- 使用服务端观测时间可让所有浏览器使用一致口径，也避免客户端保留原始计数器。

**Boundary behavior**:

- 首个样本、非正时间差、计数器下降或容器重新出现：`cpuState = sampling`，`cpuPercent = null`。
- 合法结果不钳制到 100%；只拒绝负值和非有限结果。

## 3. 内存百分比与异常边界

**Decision**: 保存原始字节数；当 `memoryLimitBytes > 0` 时计算
`memoryUsageBytes / memoryLimitBytes * 100`，否则百分比为空。

**Rationale**:

- 原始使用量和上限是 CLI 的权威值，应直接提供给界面格式化为 IEC 单位。
- 使用量高于限制可能代表瞬时或运行时语义，仍显示权威原始值和大于 100% 的比例，不静默修正。
- 零上限不得除零；缺失必需字段或负数使整个快照无效。

## 4. 采样状态与并发

**Decision**: 使用 actor 串行管理上一样本，并合并同一时刻的重叠读取；每次成功快照只保留本轮
返回 ID 的上一原始样本。

**Rationale**:

- 一个上一样本已足够计算 CPU，无需历史数据库或无限缓存。
- 清除本轮未返回 ID 可防止已停止、删除或重启容器显示陈旧指标。
- 合并重叠请求可避免页面取消、快速手动刷新或多个浏览器造成无界 CLI 进程。

## 5. HTTP 与界面降级

**Decision**: 新增 `GET /api/v1/containers/metrics`，与健康、列表和详情 API 分离；浏览器用
`Promise.allSettled` 并行刷新，指标失败仅把指标状态标记为暂不可用。

**Rationale**:

- 独立端点让较慢的统计命令不改变基础列表的成功契约。
- 页面可在列表成功后继续管理容器，并在下一个周期自动恢复指标。
- 运行状态仍由最新列表决定；非运行中容器永远显示“未运行”，不消费旧指标。

## Sources

- Apple Container, [Resource usage](https://github.com/apple/container/blob/main/docs/resource-usage.md)
- Apple Container, [Command reference](https://github.com/apple/container/blob/main/docs/command-reference.md)
- Apple Container, [How-to guide](https://github.com/apple/container/blob/main/docs/how-to.md)
- 本机 `container` CLI 1.3.1 的 `stats --help` 与只读 JSON 样本（2026-08-29）
