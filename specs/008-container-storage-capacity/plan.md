# Implementation Plan: 容器存储容量

**Branch**: `main` | **Date**: 2026-08-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-container-storage-capacity/spec.md`

## Summary

在现有容器概览与详情中增加根文件系统的使用率和“已用 / 总容量”。Swift 服务在现有资源指标读取后，针对每个运行中容器并行执行固定、只读的容量查询，解析为字节值并附加到同一指标快照。单容器查询失败降级为“暂不可用”，停止容器显示“未运行”，不影响列表、CPU、内存或其他容器。

## Technical Context

**Language/Version**: Swift 6.3.3（Package 使用 Swift tools 6.1）；原生 HTML、CSS、JavaScript

**Primary Dependencies**: Hummingbird 2.26；Foundation `Process` 命令适配器；Apple Container CLI 1.3.1

**Storage**: 无持久化；容量仅存在于当前资源指标响应和浏览器内存状态

**Testing**: XCTest、HummingbirdTesting、版本化命令输出夹具、Node 前端逻辑测试、只读真实 CLI 与浏览器验收

**Target Platform**: Apple Silicon，macOS 15+（当前验证环境 macOS 26）

**Project Type**: 单 Swift B/S 服务与无构建步骤的静态浏览器界面

**Performance Goals**: 页面保持五秒自动刷新；多个运行中容器的容量查询并行执行，完整资源快照不超过现有五秒上限

**Constraints**: 仅绑定 `127.0.0.1`；固定参数数组且不执行 shell；读取失败按单容器隔离；不把镜像大小、卷或宿主机目录当作根文件系统容量

**Scale/Scope**: 单用户本机管理、数十个容器；本次不含磁盘配额设置、历史曲线、容量告警、卷容量或宿主机实际占用统计

## Constitution Check

*GATE: Phase 0 前检查，并在 Phase 1 设计完成后复查。*

| 原则 | 设计证据 | 结果 |
|---|---|---|
| 官方 CLI 是唯一事实来源 | 容器列表、运行状态和容量均通过当前官方 CLI 的只读命令读取，不建立影子状态 | PASS |
| 本机优先与安全变更 | 仅扩展现有 GET 指标；容量命令参数固定，不接收浏览器命令或 shell 文本 | PASS |
| 测试先行和可替换命令适配器 | 先增加容量解析、失败隔离、API 和静态资源测试，再实现 | PASS |
| 可独立验收的增量交付 | 作为现有资源指标的独立增量，不改变生命周期控制或其他功能 | PASS |
| 简洁、可观察、可兼容 | 复用现有指标端点、命令执行器和五秒刷新，不增加服务、数据库或前端工具链 | PASS |
| 版本与 Git 门禁 | 向后兼容的新功能递增 MINOR 至 2.10.0，完整验证后单独提交并推送 | PASS |

Phase 1 复查：数据模型只增加一个根文件系统容量对象；契约保持同一路径并向后兼容扩展；并行查询使用固定参数且单项失败不扩大。全部门禁继续通过，无宪章例外。

## Project Structure

### Documentation (this feature)

```text
specs/008-container-storage-capacity/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── openapi.yaml
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/ContainerGUI/
├── App/AppVersion.swift
├── CLI/
│   ├── CLIModels.swift
│   └── ContainerCLIClient.swift
├── Domain/ContainerMetricsModels.swift
└── Resources/Public/
    ├── index.html
    ├── app.css
    └── app.js

Tests/ContainerGUITests/
├── Unit/
│   ├── AppVersionTests.swift
│   └── ContainerMetricsTests.swift
├── Contract/ContainerMetricsAPITests.swift
├── Browser/ContainerMetricsAssetTests.swift
├── Integration/ReadOnlyCLISmokeTests.swift
└── Fixtures/CLI/1.3.1/metrics/
```

**Structure Decision**: 保留现有单 Swift Package 和 CLI、Domain、Web、静态资源分层；容量是现有资源指标模型的最小扩展，不新增端点或抽象层。

## Complexity Tracking

无宪章违规，不需要复杂度例外。
