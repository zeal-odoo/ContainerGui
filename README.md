# Container GUI

面向 Apple `container` CLI 的轻量本机 Web 管理界面。Swift 服务仅监听
`127.0.0.1`，浏览器用于查看容器和镜像、拉取镜像、创建容器，以及执行经过约束的启停操作。

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
- 真实拉取、创建、启动或停止必须由用户在页面明确提交；自动化验证不会执行这些写操作。
- 当前 MVP 包含容器列表、CPU/内存指标、详情、安全启停、操作回读、日志、镜像列表与拉取，以及受控容器创建。
- 拉取表单提供 Docker Hub 快捷选择，并保留完整镜像地址输入。
- 首页直接显示全部本机镜像；远程区域按需分页搜索仓库和标签，选择标签只回填拉取表单，不会自动拉取。
- 创建表单只支持名称、镜像、CPU、内存、回环端口、环境变量、进程参数和可选启动；不接受任意 CLI 或 shell 文本。

设计与验收入口见 [基础功能规格](specs/001-container-web-gui/spec.md)、
[镜像与创建规格](specs/003-image-pull-create/spec.md) 和
[快速验证指南](specs/003-image-pull-create/quickstart.md)。
