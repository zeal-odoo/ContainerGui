# Quickstart: 拉取镜像与创建容器

## Safety boundary

- 自动化验证不得真实拉取镜像、创建容器或启动容器。
- 真实写操作只在用户单独明确授权、目标和参数均已展示后执行。
- 本指南的默认完成门禁是模拟命令测试、HTTP 契约测试、浏览器可见表单和真实只读镜像回读。

## Prerequisites

```bash
cd "/Volumes/LaCie/Container Gui"
/usr/local/bin/container --version
/usr/local/bin/container system status --format json
```

预期 CLI 为 `1.3.1` 且系统状态可读取。

## Automated verification

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

重点验证：

- 镜像列表和详情 1.3.1 JSON 夹具解析。
- 拉取命令只能是固定的 `image pull --progress none` 参数数组。
- 创建命令只包含允许字段，且选项位于镜像参数之前。
- 无效名称、镜像、平台、CPU、内存、端口、环境变量和参数不会调用执行器。
- 环境变量值不出现在 Operation、ProblemDetail 或浏览器状态中。
- 拉取后缺少镜像、创建后缺少容器、可选启动后未运行均不能显示成功。
- 现有容器读取、指标、启停和日志测试保持通过。

## Read-only live verification

```bash
CONTAINER_GUI_LIVE_READONLY=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift test --filter ReadOnlyCLISmokeTests
```

该测试可增加镜像列表/详情读取，但不得调用 pull、create 或 start。

## Local browser verification

在未占用端口启动当前构建：

```bash
CONTAINER_GUI_PORT=8788 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift run ContainerGUI
```

打开 `http://127.0.0.1:8788/`，确认：

1. 镜像区域显示本机镜像名称、摘要、平台和大小。
2. “拉取镜像”对话框包含完整地址、Docker Hub、GHCR 三种仓库输入方式，以及可选目标架构。
3. Docker Hub 的 `postgres:latest` 提交为 `docker.io/library/postgres:latest`；GHCR 的
   `owner/image:tag` 提交为 `ghcr.io/owner/image:tag`。
4. “创建容器”对话框包含名称、镜像、CPU、内存、端口、环境变量、进程参数和创建后启动。
5. 本地镜像名称可用于创建表单建议。
6. 无效输入显示逐字段中文错误，未发出写请求。
7. 不提交任何真实拉取或创建操作。

## Mutation acceptance with explicit authorization only

若用户之后单独授权真实写操作，验收必须记录：

1. 完整镜像引用或容器名称及所有非秘密参数。
2. 写操作前的镜像或容器权威列表。
3. 202 Operation 和轮询到的终态。
4. CLI 退出状态。
5. 独立 `image inspect` 或容器列表回读。
6. 若创建后启动，最终必须额外回读运行中状态。

任何缺失回读、目标冲突、超时或部分成功均不得声明完成。
