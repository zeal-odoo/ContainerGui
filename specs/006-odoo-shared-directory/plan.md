# Implementation Plan: Odoo 与通用共享目录

**Branch**: `main` | **Date**: 2026-08-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-odoo-shared-directory/spec.md`

## Summary

扩展现有创建容器请求，为所有镜像增加至多一个可选的本机读写目录挂载。Swift 领域模型在任何 CLI 调用前验证本机绝对路径存在且为目录、容器目标安全，并以 Apple Container CLI 1.3.1 的结构化 `--mount type=bind,source=...,target=...` 参数传递。浏览器与服务端使用相同的精确官方 Odoo 镜像分类规则；官方 Odoo 镜像固定目标 `/mnt/extra-addons`，显示数据库地址和端口并映射为官方镜像支持的 `HOST`、`PORT` 环境配置；普通镜像使用可编辑的 `/workspace` 默认目标且拒绝 Odoo 专属字段。复用现有单服务、静态表单、异步操作与状态回读，不增加持久层、目录扫描、多挂载或凭据模型。

## Technical Context

**Language/Version**: Swift tools 6.1；原生 HTML、CSS、JavaScript

**Primary Dependencies**: Hummingbird 2.26；Foundation/CryptoKit；Apple Container CLI 1.3.1

**Storage**: 无数据库；挂载和 Odoo 数据库端点只存在于单次创建请求及容器的 CLI 配置中，不建立影子副本

**Testing**: XCTest、HummingbirdTesting、固定命令执行器、HTTP 契约测试、静态浏览器资源测试、Node 前端逻辑测试；真实 CLI 只读

**Target Platform**: Apple Silicon，macOS 15+（当前验证环境 macOS 26）

**Project Type**: 单 Swift B/S 服务与无构建步骤的静态浏览器界面

**Performance Goals**: 表单镜像切换即时更新；路径与端点校验在一次同步请求验证内完成；不增加轮询频率或额外网络请求

**Constraints**: 只允许一个读写挂载；不得扫描或创建本机目录；不得拼接 shell；不记录完整本机路径或结构化数据库值；自动化不得创建真实容器

**Scale/Scope**: 单用户本机管理、数十个容器；只扩展新建容器表单与现有创建 API，已有容器、多挂载、只读模式和数据库凭据不在范围

## Constitution Check

*GATE: Phase 0 前检查，并在 Phase 1 设计完成后复查。*

| 原则 | 设计证据 | 结果 |
|---|---|---|
| 官方 CLI 是唯一事实来源 | 挂载和环境配置只传给官方 CLI；创建结果继续通过容器列表独立回读 | PASS |
| 本机优先与安全变更 | 本机目录由用户明确输入且执行前校验；固定结构化参数；无 shell、远程监听或目录扫描 | PASS |
| 测试先行和可替换命令适配器 | 先增加领域校验、CLI 参数形状、HTTP 契约和浏览器行为失败测试；固定执行器不修改真实容器 | PASS |
| 可独立验收的增量交付 | 通用挂载、Odoo 模块预设、Odoo 数据库端点分别可独立验证 | PASS |
| 简洁、可观察、可兼容 | 复用一个请求模型、一个 CLI 路径和现有表单；未配置目录时保持旧行为；安全摘要只显示配置存在性和容器目标 | PASS |
| 版本与 Git 门禁 | 向后兼容新功能升至 GUI v2.8.0，全量验证后与规格、代码、测试形成单一提交并推送 | PASS |

Phase 1 复查：接口只增加两个可选结构化对象；旧请求缺省解码为空并保持原有 CLI 形状。官方 Odoo 识别使用精确仓库而非子串，浏览器可见性不是安全边界；服务端再次校验 Odoo 目标、数据库端点和环境变量冲突。本机目录只进行明确路径的存在性检查，不遍历目录内容；CLI 仍以参数数组执行，操作摘要不回显本机路径或数据库值。无宪章例外。

## Project Structure

### Documentation (this feature)

```text
specs/006-odoo-shared-directory/
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
├── App/
│   └── AppVersion.swift
├── CLI/
│   └── ContainerCLIClient.swift
├── Domain/
│   └── ContainerCreationModels.swift
└── Resources/Public/
    ├── index.html
    └── app.js

Tests/ContainerGUITests/
├── Unit/
│   ├── ImageAndCreationCLITests.swift
│   └── AppVersionTests.swift
├── Contract/
│   └── ResourceMutationAPITests.swift
└── Browser/
    └── ResourceMutationAssetTests.swift

Tests/Frontend/
└── OdooCreateFormTests.mjs
```

**Structure Decision**: 保留现有 Swift Package 与 Domain/CLI/Web/静态资源分层。新配置属于创建请求，不新建服务或持久层；可独立测试的镜像分类与表单派生逻辑放入一个无构建步骤的前端辅助模块，其他改动限制在现有模型、CLI 适配器、表单和相关测试。

## Complexity Tracking

无宪章违规，不需要复杂度例外。
