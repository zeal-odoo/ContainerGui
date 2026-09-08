# Research

- Decision: 使用 Energy Model 的能量增量与单调采样时间计算估算瓦数，严格识别 mJ/uJ/nJ/J。读取功耗不需模型参与。
- Evidence: 2026-09-08，本机 M4 Max/macOS 26.6.2 普通用户 IOReport 样本可读取 ANE mJ；合成 AI 推理期间每约一秒增加约 2450–2600 mJ。Fast-Die CE 全桶零，即无有效计算使用率。Cluster ACT 即使低能耗也可能很高，不能替代使用率。
- Alternative rejected: powermetrics 在本机明确要求 superuser；不新增权限提升。能量/峰值功率比值不是真实计算利用率。
- Scope: 整机所有应用，不归因 GUI、AI worker 或容器；仅验证当前机器，不保证所有 Mac。
- Compatibility: IOReport 是未公开接口，动态符号、通道或单位缺失时明确不可用。通过固定绝对系统库路径加载，不接受浏览器路径参数。
- Primary references inspected: 本机 `/usr/bin/powermetrics --help` 的估算功耗说明；[SoCMetrics](https://github.com/GoodOlClint/swift-soc-metrics)（无 root、私有 API 兼容风险）；[aneperf](https://github.com/tmc/aneperf/tree/c85c98f56cb95d32ee5c1e9bb3f143902c1111cc)（计数器接口与指标差异）。独立实现，不复制未授权仓库源码。
