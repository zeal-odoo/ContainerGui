# Container GUI

## 项目介绍 / Project Introduction

**中文**：Container GUI 是面向 Apple `container` CLI 的轻量级本机 B/S 管理界面。后端使用 Swift 与
Hummingbird，前端使用无需构建的原生 HTML、CSS 和 JavaScript。它可查看容器与 CPU/内存状态、管理日志、
浏览、拉取和安全删除镜像、创建容器，并执行经过精确确认和 CLI 状态回读的启动、停止与安全删除操作。
创建 Debian/Ubuntu 容器时还可一键配置仅公钥 SSH、自定义回环主机端口、在浏览器本地生成 SSH 密钥，
并在详情中复制连接命令。普通容器也可通过一个 GUI 选项保持运行，无需手写 shell 参数。

**English**: Container GUI is a lightweight, local browser-based management interface for Apple's `container` CLI.
Its backend is built with Swift and Hummingbird, while the frontend uses build-free HTML, CSS, and JavaScript. It
provides container and CPU/memory monitoring, logs, safe image browsing, pulling and deletion, container creation, and constrained
start, stop, and safe deletion workflows verified against authoritative CLI readbacks. New Debian/Ubuntu containers can also use
one-click, public-key-only SSH with a custom loopback host port, browser-local key generation, and a copyable connection
command. A GUI preset can also keep ordinary containers running without manually entering shell arguments.

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
node --test Tests/Frontend/SSHKeyGeneratorTests.mjs
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

## 一键 SSH / One-click SSH

**中文**：在“创建容器”中打开“启用 SSH（仅公钥登录）”，填写宿主机端口（默认 `2222`）、
非 root 用户名（默认 `dev`），再粘贴公钥、选择 `.pub` 文件，或点击“生成 SSH 密钥”。浏览器会在本机
生成 RSA-3072 密钥对，自动填入公钥，并仅下载一次私钥；私钥不会上传到 Swift 服务，也不会由 GUI 保存。
下载后先执行 `chmod 600 ~/Downloads/<私钥文件名>`。GUI 会固定绑定到
`127.0.0.1:<宿主机端口>`，自动安装并启动 OpenSSH；服务端不接收私钥、密码或自定义安装命令。
当前自动安装仅支持能以 root 运行 `apt-get` 的 Debian/Ubuntu 系镜像。状态显示“可连接”后，可使用：

```bash
ssh -i ~/Downloads/<私钥文件名> -p 2222 dev@127.0.0.1
```

停止并重新启动**同一个容器**时，端口、用户名、授权公钥和 SSH 主机密钥均保留，SSH 会随容器恢复；
删除并重建容器则视为新主机，主机指纹可能改变。现有普通容器不会被自动改造，需要用 SSH 选项重新创建。

**English**: In “Create Container,” enable “SSH (public key only),” choose a host port (default `2222`),
enter a non-root username (default `dev`), then paste a public key, select a `.pub` file, or click “Generate SSH Key.”
The browser creates an RSA-3072 key pair locally, fills the public key, and downloads the private key once. The private
key is never uploaded to the Swift service or stored by the GUI; run `chmod 600` on the downloaded file before use.
The GUI binds only to `127.0.0.1:<host-port>` and installs/starts OpenSSH without the server accepting private keys,
passwords, or custom setup commands.
Automatic setup currently supports Debian/Ubuntu-family images that can run `apt-get` as root. Once the status is “Ready,”
use the displayed command. Stopping and starting the same container preserves its port, user, authorized key, and SSH host keys;
deleting and recreating it creates a new SSH host whose fingerprint may change. Existing ordinary containers are not modified.

## 保持普通容器运行 / Keep an ordinary container running

**中文**：对于 Ubuntu 等默认命令会立即退出、且不启用 SSH 的普通容器，在创建表单勾选“保持容器运行”即可。
GUI 会固定发送 `/bin/bash`、`-lc`、`exec sleep infinity` 三个进程参数，因此无需每次手写。PostgreSQL、Nginx
等镜像已经有常驻主进程时不要勾选。启用 SSH 后该选项会自动关闭并禁用，因为 `sshd` 已经是常驻主进程。

**English**: For an ordinary non-SSH container whose default command exits immediately, such as a plain Ubuntu image,
enable “Keep container running” in the create form. The GUI sends the fixed arguments `/bin/bash`, `-lc`, and
`exec sleep infinity`; you do not need to type them. Leave this off for images such as PostgreSQL or Nginx that already
have a long-running default process. SSH mode disables this preset because `sshd` is already the persistent main process.

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
- 创建表单只支持名称、镜像、CPU、内存、回环端口、环境变量、受控保持运行预设、进程参数和可选启动；主机端口必须为
  `1024...65535`（例如 SSH 使用 `2222:22/tcp`），不接受任意 CLI 或 shell 文本。
- SSH 快捷配置由服务端固定生成安装和启动参数，只允许自定义高位宿主端口、非 root 用户名和公钥；
  SSH 就绪状态必须通过回环端口的 `SSH-` 协议横幅确认。
- 删除只对已停止或已创建的单个精确目标开放，必须二次确认；不提供 `--all` 或 `--force`，成功必须
  由删除后的权威容器列表确认。
- 镜像删除同样不提供 `--all` 或 `--force`，成功必须由删除后的权威镜像列表确认。

设计与验收入口见 [基础功能规格](specs/001-container-web-gui/spec.md)、
[镜像与创建规格](specs/003-image-pull-create/spec.md) 和
[SSH 快速配置规格](specs/004-ssh-quick-config/spec.md)。对应验证指南见
[镜像与创建](specs/003-image-pull-create/quickstart.md) 和
[SSH 快速配置](specs/004-ssh-quick-config/quickstart.md)。
