# Implementation Plan: Apple Container Web GUI

**Branch**: `main` | **Date**: 2026-08-29 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-container-web-gui/spec.md`

## Summary

构建一个只监听本机回环地址的轻量 Swift Web 服务，为 Apple `container` CLI 提供中文浏览器
管理界面。后端以安全参数数组调用官方 CLI，结构化查询统一解析 JSON，变更成功后重新读取权威
状态；浏览器通过版本化 JSON API 完成状态查看、启停、日志、创建、删除和系统恢复。首个可交付
切片仅包含系统健康、容器列表/详情、启动/停止和日志。

## Technical Context

<!--
  ACTION REQUIRED: Replace the content in this section with the technical details
  for the project. The structure here is presented in advisory capacity to guide
  the iteration process.
-->

**Language/Version**: Swift 6.3.3 with strict concurrency checks

**Primary Dependencies**: Hummingbird 2.26.x (`Hummingbird`, `HummingbirdTesting`), Foundation
`Process`, Swift Service Lifecycle and Swift Log through Hummingbird; no ORM or frontend framework

**Storage**: No database. In-memory operation/idempotency records with bounded TTL; static files packaged
as SwiftPM resources; diagnostic logs go to standard logging only

**Testing**: Swift Testing for unit/contract tests, HummingbirdTesting for in-process HTTP tests, fixture-
driven CLI adapter tests, optional explicitly enabled read-only live CLI smoke tests

**Target Platform**: Apple Silicon Mac running macOS 26; local browser; Apple `container` CLI 1.3.1 is
the first verified compatibility baseline

**Project Type**: Single Swift executable web service with packaged static browser assets

**Performance Goals**: For up to 100 containers, health/list/detail requests complete within 2 seconds
at p95 when the CLI is responsive; state changes are visible within 5 seconds after the CLI state changes;
support up to 8 simultaneous log streams without unbounded buffering

**Constraints**: Bind only `127.0.0.1`; one local user; no arbitrary command execution; no persistent
container-state cache; JSON command output capped at 16 MiB; request bodies capped at 64 KiB; query
commands time out after 5 seconds; per-target mutations are serialized; secrets are never logged or echoed

**Scale/Scope**: One Mac, one service process, one active user, up to 100 containers and 1,000 retained
operation summaries (15-minute TTL). MVP implements User Stories 1-2; User Stories 3-4 are later increments

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Design evidence | Result |
|------|-----------------|--------|
| Official CLI is the only source of truth | `ContainerCLIClient` owns all reads; no database; every mutation performs a new list/inspect/status read | PASS |
| Local-first and safe mutations | Host is fixed to `127.0.0.1`; same-origin mutation middleware, argument allowlist, idempotency keys, target confirmation and no force-delete | PASS |
| Test-first and replaceable command adapter | `CommandExecuting` boundary accepts deterministic stdout/stderr/exit/timeout fixtures; live tests are read-only and opt-in | PASS |
| Independently acceptable increments | Routes, services, tests and UI are grouped by US1-US4; MVP ends after US2 | PASS |
| Simplicity, observability and compatibility | One executable, static assets, no database/build chain; structured operation logs and startup version probe | PASS |

**Pre-research gate result**: PASS. No constitutional exception is required.

## Project Structure

### Documentation (this feature)

```text
specs/001-container-web-gui/
├── plan.md              # This file ($speckit-plan command output)
├── research.md          # Phase 0 output ($speckit-plan command)
├── data-model.md        # Phase 1 output ($speckit-plan command)
├── quickstart.md        # Phase 1 output ($speckit-plan command)
├── contracts/
│   └── openapi.yaml     # Versioned browser/backend contract
└── tasks.md             # Phase 2 output ($speckit-tasks command - NOT created by $speckit-plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
Package.swift
Sources/ContainerGUI/
├── main.swift
├── App/
│   ├── AppConfiguration.swift
│   └── AppFactory.swift
├── CLI/
│   ├── CommandExecuting.swift
│   ├── FoundationProcessExecutor.swift
│   ├── ContainerCLIClient.swift
│   ├── CLIModels.swift
│   └── CLIError.swift
├── Domain/
│   ├── ContainerModels.swift
│   ├── OperationModels.swift
│   ├── RunConfiguration.swift
│   └── JSONValue.swift
├── Operations/
│   └── OperationCoordinator.swift
├── Web/
│   ├── APIRoutes.swift
│   ├── ErrorMiddleware.swift
│   ├── SafetyMiddleware.swift
│   └── LogEventStream.swift
└── Resources/Public/
    ├── index.html
    ├── app.css
    └── app.js

Tests/ContainerGUITests/
├── Fixtures/CLI/1.3.1/
├── Unit/
├── Contract/
├── Integration/
└── Browser/
```

**Structure Decision**: 使用一个 SwiftPM executable target 和一个 test target。浏览器资源作为
SwiftPM resource 随同二进制分发，不创建独立前端工程或构建链。目录仅按稳定职责划分；不增加
数据库、repository 层或插件系统。

## Phase Design

### Phase A - Foundation

建立 SwiftPM 工程、固定回环监听、配置/错误模型、安全中间件、可替换命令执行器、CLI 路径与
版本探测、JSON 大小/超时边界，以及仅包含壳层的静态页面。完成条件是所有基础失败夹具和 HTTP
错误契约测试通过，且不会调用真实写命令。

### Phase B - MVP (US1 + US2)

实现系统健康、容器列表/详情、手动和 5 秒轮询刷新、启动、正常停止、尾部日志及 SSE 跟随。
每次变更由 `OperationCoordinator` 按目标串行化并使用 `Idempotency-Key` 去重，完成后通过新 CLI
进程回读。完成条件是 P1/P2 全部契约、浏览器流程和只读实机冒烟测试通过。

### Phase C - Lifecycle (US3)

实现受约束的运行配置、预览校验、后台 run 进度、已停止容器删除和目标确认。环境变量值只存在
于当前请求内存，不进入操作摘要。MVP 不支持 `--force`、任意参数或任意命令。

### Phase D - System Recovery (US4)

实现系统状态恢复：先使用明确禁止自动安装内核的启动模式；只有检测到缺少内核并收到独立确认后，
才允许安装模式。命令退出后必须重新执行健康检查。系统停止仍不在当前功能范围。

## Post-Design Constitution Check

Phase 1 设计仍满足全部五项原则。API 合同未暴露原始命令入口，数据模型无持久状态副本，操作模型
包含确认、幂等、串行和回读字段，quickstart 将真实写操作与自动化验证分开。结果：**PASS**。

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitutional violations.
