# Implementation Plan: root 公钥 SSH 登录

**Branch**: `main` | **Date**: 2026-08-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-root-ssh-key-login/spec.md`

## Summary

在现有 SSH 快速配置中增加默认关闭的“使用 root 登录（仅公钥）”选项。浏览器以显式布尔字段表达高权限选择，root 模式固定提交 `root` 身份并禁用普通用户名输入；Swift 服务在任何 CLI 调用前同时校验选择字段、身份、端口与公钥。现有固定引导脚本增加 root 分支：直接写入 `/root/.ssh/authorized_keys`，把系统密码字段设为 OpenSSH 文档建议的不可用于密码认证值，启用 `PermitRootLogin prohibit-password`，并继续关闭全部密码和交互式认证。普通用户分支、回环端口、标签回读、SSH 就绪探测与重启恢复机制保持不变。不增加数据库、远程监听、任意命令输入或现有容器迁移。

## Technical Context

**Language/Version**: Swift tools 6.1；原生 HTML、CSS、JavaScript

**Primary Dependencies**: Hummingbird 2.26；Foundation/CryptoKit；Apple Container CLI 1.3.1

**Storage**: 无数据库；SSH 登录身份、端口继续写入容器标签，授权公钥只经受控环境变量进入容器并在回读中脱敏

**Testing**: XCTest、HummingbirdTesting、CLI 1.3.1 固定执行器/JSON 夹具、静态浏览器资源测试、Node 前端测试；真实 CLI 只读

**Target Platform**: Apple Silicon，macOS 15+（当前验证环境 macOS 26）

**Project Type**: 单 Swift B/S 服务与无构建步骤的静态浏览器界面

**Performance Goals**: 不增加额外 API 往返；创建校验保持同步完成；现有 5 秒状态刷新和 750ms SSH 横幅探测预算不变

**Constraints**: 服务与 SSH 发布端口仅绑定 `127.0.0.1`；root 选项默认关闭；不接收 root 密码或私钥；浏览器不能提交任意 shell；完整公钥不得进入摘要、日志或详情；自动化不得修改真实容器

**Scale/Scope**: 单用户本机管理、数十个容器；只扩展新建容器的现有 SSH 快速配置，已有容器迁移不在范围

## Constitution Check

*GATE: Phase 0 前检查，并在 Phase 1 设计完成后复查。*

| 原则 | 设计证据 | 结果 |
|---|---|---|
| 官方 CLI 是唯一事实来源 | root 身份沿用当前容器标签回读；状态与 SSH 就绪继续从 CLI 详情和本机协议横幅读取 | PASS |
| 本机优先与安全变更 | 只发布 `127.0.0.1`；显式 `loginAsRoot`；固定脚本；仅公钥；无密码、私钥或任意命令输入 | PASS |
| 测试先行和可替换命令适配器 | 先增加 root/普通模式领域、CLI 形状、HTTP 契约与浏览器失败测试，再做最小实现 | PASS |
| 可独立验收的增量交付 | root 创建、普通用户回归、重启恢复分别对应独立故事 | PASS |
| 简洁、可观察、可兼容 | 复用现有 SSH 模型、标签、状态端点和表单；只增加一个请求字段和一个脚本分支 | PASS |
| 版本与 Git 门禁 | 向后兼容新功能升至 GUI v2.7.0，全量验证后与规格、代码、测试一起形成单一提交并推送 | PASS |

Phase 1 复查：接口只增加默认值为 `false` 的结构化 `loginAsRoot` 字段；缺省请求继续走普通用户路径。root 选择必须与 `username=root` 同时成立，否则服务端在 CLI 前拒绝。引导脚本只根据已校验的保留环境变量在两个固定分支间选择，公钥仍不插入脚本文本。root 配置把密码字段设为不可认证值，并同时禁用密码、交互式和空密码认证；发布地址仍固定回环。无宪章例外。

## Project Structure

### Documentation (this feature)

```text
specs/005-root-ssh-key-login/
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
│   ├── ContainerCreationModels.swift
│   └── SSHModels.swift
└── Resources/Public/
    ├── index.html
    └── app.js

Tests/ContainerGUITests/
├── Unit/
│   ├── SSHQuickConfigTests.swift
│   ├── ImageAndCreationCLITests.swift
│   └── AppVersionTests.swift
├── Contract/
│   └── ResourceMutationAPITests.swift
└── Browser/
    └── ResourceMutationAssetTests.swift
```

**Structure Decision**: 保留现有 Swift Package 和 Domain/CLI/Web/静态资源分层。root 登录是现有 SSH 创建配置的一个显式模式，不创建新服务、持久层或抽象；修改限于 SSH 领域模型、固定引导脚本、现有表单、相关测试与版本文件。

## Complexity Tracking

无宪章违规，不需要复杂度例外。
