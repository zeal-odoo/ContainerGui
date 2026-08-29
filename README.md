# Container GUI

## 项目介绍 / Project Introduction

**中文**：Container GUI 是面向 Apple `container` CLI 的轻量级本机 B/S 管理界面。后端使用 Swift 与
Hummingbird，前端使用无需构建的原生 HTML、CSS 和 JavaScript。它可查看容器与 CPU/内存状态、管理日志、
浏览、拉取和安全删除镜像、创建容器，并执行经过精确确认和 CLI 状态回读的启动、停止与安全删除操作。

**English**: Container GUI is a lightweight, local browser-based management interface for Apple's `container` CLI.
Its backend is built with Swift and Hummingbird, while the frontend uses build-free HTML, CSS, and JavaScript. It
provides container and CPU/memory monitoring, logs, safe image browsing, pulling and deletion, container creation, and constrained
start, stop, and safe deletion workflows verified against authoritative CLI readbacks.

Swift 服务仅监听 `127.0.0.1`，不提供远程管理入口。

> 当前状态：开发中，不用于生产授权。默认测试不会修改真实容器。

## 环境要求

- Apple Silicon Mac，macOS 26
- Swift 6.1 或更高版本
- Apple `container` CLI 1.3.1（首个验证基线）

## 构建与测试

```bash
swift package resolve
swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

当前机器的独立 Command Line Tools 不含 XCTest；测试命令因此显式使用完整 Xcode。

## 本机运行

```bash
swift run ContainerGUI
open http://127.0.0.1:8787
```

端口可通过 `CONTAINER_GUI_PORT` 调整，但监听地址固定为 `127.0.0.1`。第一版
不允许局域网或互联网访问，也不提供任意 CLI/shell 命令入口。

Docker Hub 公开搜索无需额外配置。其他 OCI 仓库可在拉取表单中输入完整镜像地址。

## 验证边界

- 普通 `swift test` 只使用固定夹具和假命令执行器。
- 设置 `CONTAINER_GUI_LIVE_READONLY=1` 后，可运行真实 CLI 只读兼容性测试。
- 设置 `CONTAINER_GUI_LIVE_REGISTRY_READONLY=1` 后，可运行 Docker Hub GET-only 搜索与标签测试。
- 真实拉取、创建、启动、停止或删除必须由用户在页面明确提交；自动化验证不会执行这些写操作。
- 当前 MVP 包含容器列表、CPU/内存指标、详情、安全启停与删除、操作回读、日志、镜像列表与拉取，以及受控容器创建。
- 拉取表单提供 Docker Hub 快捷选择，并保留完整镜像地址输入。
- 镜像拉取显示 Apple Container CLI 提供的真实下载、解压和验证进度，不按时间伪造百分比。
- 本机镜像区域默认展开，可用标题旁的向下/向右箭头展开或收起；提交拉取或创建时会自动展开以显示操作状态。
- 首页直接显示全部本机镜像；远程区域按需分页搜索仓库和标签，选择标签只回填拉取表单，不会自动拉取。
- 未被容器引用的普通本机镜像可精确确认后删除；被引用镜像和 Apple `vminit` 系统镜像受到保护。
- 创建表单只支持名称、镜像、CPU、内存、回环端口、环境变量、进程参数和可选启动；主机端口必须为
  `1024...65535`（例如 SSH 使用 `2222:22/tcp`），不接受任意 CLI 或 shell 文本。
- 删除只对已停止或已创建的单个精确目标开放，必须二次确认；不提供 `--all` 或 `--force`，成功必须
  由删除后的权威容器列表确认。
- 镜像删除同样不提供 `--all` 或 `--force`，成功必须由删除后的权威镜像列表确认。

设计与验收入口见 [基础功能规格](specs/001-container-web-gui/spec.md)、
[镜像与创建规格](specs/003-image-pull-create/spec.md) 和
[快速验证指南](specs/003-image-pull-create/quickstart.md)。
