# Implementation Plan: SSH 快速配置

**Branch**: `main` | **Date**: 2026-08-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-ssh-quick-config/spec.md`

## Summary

在现有创建容器对话框中增加可选 SSH 快速配置，用户只需选择高位宿主机端口、登录用户名和公钥；没有
现成密钥时可由浏览器本地生成并一次性下载私钥。普通非 SSH 容器可选择固定保持运行预设，无需重复输入
`/bin/bash`、`-lc`、`exec sleep infinity`。
浏览器提交结构化字段；Swift 服务完成双端校验后，生成固定的回环端口映射、非秘密标签、受控环境变量
和不可由用户修改的启动脚本。脚本在首次启动时安装 OpenSSH Server，创建密钥用户，禁用密码与 root
登录，并以 `sshd -D` 作为容器主进程，因此同一容器停止后重新启动会自动恢复 SSH。容器标签由 Apple
Container CLI 的列表/详情回读，页面据此重建连接命令；单独的回环 TCP 横幅探测只有收到 `SSH-` 横幅才
显示“可连接”。不增加数据库、前端构建链或真实写入自动化。

## Technical Context

**Language/Version**: Swift 6.1；原生 HTML、CSS、JavaScript

**Primary Dependencies**: Hummingbird 2.26；Foundation/CryptoKit；Darwin 非阻塞回环 socket；Apple Container CLI 1.3.1

**Storage**: 无数据库；SSH 端口与用户名写入容器标签，公钥写入容器配置的受控环境变量并在所有回读中脱敏

**Testing**: XCTest、HummingbirdTesting、CLI 1.3.1 JSON 夹具、可替换 SSH 就绪检查器、浏览器资源测试；真实 CLI 仅只读

**Target Platform**: Apple Silicon，macOS 15+（当前验证环境 macOS 26）

**Project Type**: 单 Swift B/S 服务与无构建步骤的静态浏览器界面

**Performance Goals**: 创建 POST 在 1 秒内返回 Operation；SSH 状态读取在 1 秒内返回；运行中容器每 5 秒刷新时完成一次最长 750ms 的横幅探测

**Constraints**: 服务与 SSH 发布端口仅绑定 `127.0.0.1`；浏览器不能提交 shell 或入口点；固定脚本不插值用户数据；公钥不进入操作摘要、日志或详情；自动化不得更改真实容器

**Scale/Scope**: 单用户本机管理、数十个容器；每个 SSH 容器一个端口和用户；首期支持 Debian/Ubuntu 系列镜像

## Constitution Check

*GATE: Phase 0 前检查，并在 Phase 1 设计完成后复查。*

| 原则 | 设计证据 | 结果 |
|---|---|---|
| 官方 CLI 是唯一事实来源 | SSH 元数据从当前容器标签回读；容器状态继续来自 CLI；横幅探测只证明服务就绪 | PASS |
| 本机优先与安全变更 | 固定回环地址；结构化字段；不可修改的脚本作为固定参数；用户值只经校验后的环境变量传入且不拼接 | PASS |
| 测试先行和可替换命令适配器 | 先增加请求、CLI 形状、标签解析、HTTP 和静态资源失败测试；就绪检查通过协议替换 | PASS |
| 可独立验收的增量交付 | 快速创建、重启恢复/状态、安全校验分别对应可独立验收故事 | PASS |
| 简洁、可观察、可兼容 | 复用单服务、操作协调器和静态表单；只增加小型领域模型、只读路由和 socket 检查器 | PASS |
| 版本与 Git 门禁 | 原始 SSH 功能为 GUI v2.5.0；浏览器密钥生成与保持运行预设统一升至 v2.6.0，并在全量验证后创建单一功能提交和推送 | PASS |

Phase 1 复查：接口只增加一个可选的结构化 `ssh` 对象和只读状态端点；无任意主机、命令、URL 或 shell
输入。固定启动脚本不拼接用户名、公钥或端口，所有用户值作为单独环境变量传递。公钥不写入标签，嵌入
环境数组的敏感值在详情解析阶段脱敏。状态端点只能探测从受信容器标签解析出的 `127.0.0.1` 高位端口，
不能作为任意端口扫描器。全部门禁继续通过，无宪章例外。

## Project Structure

### Documentation (this feature)

```text
specs/004-ssh-quick-config/
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
│   ├── AppFactory.swift
│   └── AppVersion.swift
├── CLI/
│   ├── CLIModels.swift
│   └── ContainerCLIClient.swift
├── Domain/
│   ├── ContainerCreationModels.swift
│   ├── ContainerModels.swift
│   ├── JSONValue.swift
│   └── SSHModels.swift
├── SSH/
│   └── LoopbackSSHReadinessChecker.swift
├── Web/
│   └── SSHStatusRoutes.swift
└── Resources/Public/
    ├── index.html
    ├── app.css
    └── app.js

Tests/ContainerGUITests/
├── Unit/
│   ├── ContainerCLIReadTests.swift
│   ├── ImageAndCreationCLITests.swift
│   └── SSHQuickConfigTests.swift
├── Contract/
│   ├── ResourceMutationAPITests.swift
│   └── SSHStatusAPITests.swift
├── Browser/ResourceMutationAssetTests.swift
└── Fixtures/CLI/1.3.1/ssh-container-detail.json
```

**Structure Decision**: 保留现有 Swift Package 和 Domain/CLI/Web/静态资源分层。SSH 请求与回读模型集中
在一个领域文件；固定 socket 横幅检查器独立于路由以便替换测试。现有创建服务、CLI 客户端和详情页面
只做本功能需要的精准扩展。

## Complexity Tracking

无宪章违规，不需要复杂度例外。
