# Implementation Plan: 容器重启

**Branch**: `main` | **Date**: 2026-08-30 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/007-container-restart/spec.md`

## Summary

为运行中的单个容器增加受控重启操作。现有 Apple `container` CLI 1.3.1 没有原生重启子命令，因此后端在同一个异步操作与目标锁中依次调用既有正常停止和启动能力；任何阶段失败或最终状态不是运行中都使整个操作失败。浏览器详情仅在运行状态显示重启按钮，要求明确确认，并沿用现有操作轮询与刷新机制。

## Technical Context

**Language/Version**: Swift 6.3.3，Swift tools 6.1，原生无构建步骤 JavaScript

**Primary Dependencies**: Hummingbird 2.26+、Foundation、HTTPTypes

**Storage**: N/A；操作仅使用现有短期内存记录，容器状态始终从 CLI 回读

**Testing**: XCTest、HummingbirdTesting、静态浏览器资源测试、Node 客户端纯函数测试

**Target Platform**: Apple Silicon macOS 15+，当前验证环境 macOS 26 与 Apple `container` CLI 1.3.1

**Project Type**: 本机单用户 Swift Web 服务与静态浏览器界面

**Performance Goals**: 重启请求在 1 秒内进入可轮询状态；完成后一个 5 秒刷新周期内显示最终状态

**Constraints**: 仅监听 `127.0.0.1`；不得拼接 shell、强制停止、批量操作、删除或重建；自动化测试不得重启真实容器

**Scale/Scope**: 单机单用户、单目标重启；不含批量、定时或自动重启策略

## Constitution Check

*GATE: Passed before Phase 0 research and re-checked after Phase 1 design.*

- **CLI 唯一事实来源**: PASS。重启完成必须以最终运行状态回读为准，页面和进程退出码均不单独构成成功。
- **本机优先与安全变更**: PASS。沿用 loopback、中间件、精确容器标识、参数数组和确认目标；没有 force、all、delete 或任意命令。
- **测试先行和可替换适配器**: PASS。先增加失败的 HTTP 与浏览器资产测试，使用 actor stub 验证停止和启动顺序，不触碰真实容器。
- **可独立验收增量**: PASS。功能是现有容器控制故事的独立纵向切片，不依赖镜像、SSH 或 Odoo 能力。
- **简洁、可观察、可兼容**: PASS。复用现有协调器、控制服务、轮询和刷新；只新增一个操作类型、一个路由和一个按钮。
- **版本与 Git 门禁**: PASS。向后兼容的新功能把 GUI 从 `2.8.0` 递增到 `2.9.0`，规格、代码、测试、版本和验证记录进入同一提交。
- **Phase 1 re-check**: PASS。接口、数据模型和验证方案未引入数据库、前端构建链、新进程执行面或真实测试写操作。

## Project Structure

### Documentation (this feature)

```text
specs/007-container-restart/
├── spec.md
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
├── Domain/OperationModels.swift
├── Web/ContainerControlRoutes.swift
├── Web/OperationRoutes.swift
└── Resources/Public/app.js

Tests/ContainerGUITests/
├── Contract/ContainerControlAPITests.swift
└── Browser/ContainerControlAssetTests.swift
```

**Structure Decision**: 保持现有单一 SwiftPM 可执行目标和静态资源结构。重启顺序属于 `ContainerControlService` 的操作编排，不扩展 CLI 命令适配器协议，因为所需的精确停止与启动能力已经存在且分别完成状态回读。

## Complexity Tracking

无宪章例外或额外复杂度。
