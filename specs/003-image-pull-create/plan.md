# Implementation Plan: 拉取镜像与创建容器

**Branch**: `main` | **Date**: 2026-08-29 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-image-pull-create/spec.md`

## Summary

在现有单 Swift 服务和静态浏览器界面中增加权威镜像列表、异步镜像拉取和受控容器创建。
后端只调用 Apple Container CLI 1.3.1 的固定参数数组：结构化读取镜像列表/详情，拉取后按
请求引用检查镜像详情，创建后按名称回读容器；可选启动只在创建回读成功后执行。现有操作协调器
扩展镜像目标和两种操作类型，环境变量值只进入子进程参数，不进入操作摘要、响应或错误。

## Technical Context

**Language/Version**: Swift 6.1；原生 HTML、CSS、JavaScript
**Primary Dependencies**: Hummingbird 2.26；Foundation `Process` 命令适配器；Apple Container CLI 1.3.1
**Storage**: 无持久化；复用内存操作记录和幂等键，终态按现有 TTL 清理
**Testing**: XCTest、HummingbirdTesting、版本化 CLI JSON 夹具、浏览器资源测试；真实环境仅执行只读回读
**Target Platform**: Apple Silicon，macOS 15+（当前验证环境 macOS 26）
**Project Type**: 单 Swift B/S 服务与无构建步骤的静态浏览器界面
**Performance Goals**: 写请求 1 秒内返回可轮询操作；底层命令结束后 2 秒内显示回读；只读列表不被写操作阻塞
**Constraints**: 仅绑定 `127.0.0.1`；不执行 shell；端口只发布到回环地址；秘密值不进入可见状态；自动化不得执行真实写操作
**Scale/Scope**: 单用户本机管理、数十个容器和镜像；每个请求最多 32 个端口、64 个环境变量和 64 个进程参数

## Constitution Check

*GATE: Phase 0 前检查，并在 Phase 1 设计完成后复查。*

| 原则 | 设计证据 | 结果 |
|---|---|---|
| 官方 CLI 是唯一事实来源 | 镜像使用 `image list/inspect` 回读；容器使用最新列表回读；无数据库 | PASS |
| 本机优先与安全变更 | 固定参数数组；回环端口；禁止任意命令和高级危险选项 | PASS |
| 测试先行和可替换命令适配器 | 先增加 1.3.1 夹具、命令形状、契约和浏览器测试；真实写入禁止 | PASS |
| 可独立验收的增量交付 | 拉取镜像和创建容器是两个可独立测试的纵向切片 | PASS |
| 简洁、可观察、可兼容 | 复用单服务、静态页面、执行器和操作协调器；不增加存储或前端工具链 | PASS |

Phase 1 复查：接口仅增加镜像读取及两种白名单变更；秘密字段为只写且安全摘要只保留变量名；
数据模型不持久化；所有成功路径要求权威回读。全部门禁继续通过，无宪章例外。

## Project Structure

### Documentation (this feature)

```text
specs/003-image-pull-create/
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
│   ├── ImageModels.swift
│   ├── ContainerCreationModels.swift
│   └── OperationModels.swift
├── Operations/
│   ├── OperationCoordinator.swift
│   └── ResourceMutationServices.swift
├── Web/
│   └── ResourceMutationRoutes.swift
└── Resources/Public/
    ├── index.html
    ├── app.css
    └── app.js

Tests/ContainerGUITests/
├── Unit/ImageAndCreationCLITests.swift
├── Contract/ResourceMutationAPITests.swift
├── Browser/ResourceMutationAssetTests.swift
├── Integration/ReadOnlyCLISmokeTests.swift
└── Fixtures/CLI/1.3.1/resources/
```

**Structure Decision**: 保留现有单 Swift Package 和 CLI、Domain、Operations、Web、静态资源分层；
新模型和路由按本功能聚合，避免修改已稳定的容器读取、指标和日志切片。

## Complexity Tracking

无宪章违规，不需要复杂度例外。
