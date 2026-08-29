# Implementation Plan: 容器 CPU 与内存指标

**Branch**: `main` | **Date**: 2026-08-29 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-container-metrics/spec.md`

## Summary

在现有容器概览和详情中增加 CPU 使用率与内存用量、上限和百分比。Swift 服务通过
Apple `container stats --no-stream --format json` 获取结构化快照，用相邻权威样本的累计
CPU 时间差计算使用率，只在 actor 内保留上一样本；独立只读 API 将统计失败与现有列表、
详情隔离，原生 JavaScript 按现有五秒周期并行刷新并显示采样中、未运行和暂不可用状态。

## Technical Context

**Language/Version**: Swift 6.1；原生 HTML、CSS、JavaScript
**Primary Dependencies**: Hummingbird 2.26；Foundation `Process` 命令适配器；Apple Container CLI 1.3.1
**Storage**: 无持久化；仅 actor 内按运行中容器 ID 保存一个上一 CPU 样本
**Testing**: XCTest、HummingbirdTesting、版本化 CLI JSON 夹具、只读真实 CLI 冒烟测试、浏览器关键流程
**Target Platform**: Apple Silicon，macOS 15+（当前验证环境 macOS 26）
**Project Type**: 单 Swift B/S 服务与无构建步骤的静态浏览器界面
**Performance Goals**: 页面可见时每五秒更新；正常环境在两个刷新周期内显示 CPU 与内存
**Constraints**: 仅绑定 `127.0.0.1`；不执行 shell；不持久化指标；统计失败不得阻塞列表或详情；100% CPU 等于一个完整核心
**Scale/Scope**: 单用户本机管理、数十个容器；本次不含历史曲线、告警、网络、磁盘或资源限制编辑

## Constitution Check

*GATE: Phase 0 前检查，并在 Phase 1 设计完成后复查。*

| 原则 | 设计证据 | 结果 |
|---|---|---|
| 官方 CLI 是唯一事实来源 | 只调用官方 `container stats` JSON；不建立数据库 | PASS |
| 本机优先与安全变更 | 新能力只有 GET；参数为固定数组，不接受用户命令或 shell 文本 | PASS |
| 测试先行和可替换命令适配器 | 先增加 1.3.1 夹具、解析/计算/API/资源测试，再实现 | PASS |
| 可独立验收的增量交付 | 指标通过独立 API 和前端降级状态加入，不改变控制操作 | PASS |
| 简洁、可观察、可兼容 | 复用单服务、静态界面和既有执行器；只增加短期 actor 状态 | PASS |

Phase 1 复查：数据模型无持久层，契约仅增加只读端点，命令参数固定，错误与基础读取隔离；
全部门禁继续通过，无宪章例外。

## Project Structure

### Documentation (this feature)

```text
specs/002-container-metrics/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── openapi.yaml
└── tasks.md
```

### Source Code (repository root)

```text
Sources/ContainerGUI/
├── App/AppFactory.swift
├── CLI/
│   ├── CLIModels.swift
│   └── ContainerCLIClient.swift
├── Domain/
│   └── ContainerMetricsModels.swift
├── Web/
│   └── ContainerMetricsRoutes.swift
└── Resources/Public/
    ├── index.html
    ├── app.css
    └── app.js

Tests/ContainerGUITests/
├── Unit/ContainerMetricsTests.swift
├── Contract/ContainerMetricsAPITests.swift
├── Browser/ContainerMetricsAssetTests.swift
├── Integration/ReadOnlyCLISmokeTests.swift
└── Fixtures/CLI/1.3.1/metrics/
```

**Structure Decision**: 保留现有单 Swift Package 和按 CLI、Domain、Web、静态资源分层的结构；
指标是现有读取切片的增量，不引入新进程、数据库或前端工具链。

## Complexity Tracking

无宪章违规，不需要复杂度例外。
