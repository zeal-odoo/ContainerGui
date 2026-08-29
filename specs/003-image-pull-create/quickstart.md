# Quickstart: 镜像浏览、拉取与创建容器

## Safety boundary

- 自动化验证不得真实拉取镜像、创建容器或启动容器。
- 远程注册表自动化只允许 GET，并使用固定夹具完成默认测试。
- 远程搜索仅访问 Docker Hub；其他 OCI 注册表通过完整镜像地址进入拉取流程。
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
- 拉取命令只能是固定的 `image pull --progress plain` 参数数组。
- plain 下载/解压行必须解析为单调 Operation 进度；无关行和分块边界不能导致错误百分比或拉取失败。
- 创建命令只包含允许字段，且选项位于镜像参数之前。
- 无效名称、镜像、平台、CPU、内存、端口、环境变量和参数不会调用执行器。
- 环境变量值不出现在 Operation、ProblemDetail 或浏览器状态中。
- 拉取后缺少镜像、创建后缺少容器、可选启动后未运行均不能显示成功。
- 现有容器读取、指标、启停和日志测试保持通过。
- Docker Hub 搜索、仓库规范化、标签分页和下一页判断使用固定 JSON 夹具。
- 非 Docker Hub 平台值、超长响应、无效页码和上游错误都不会变成不受控请求。
- 选择远程标签只回填拉取表单，不会自动提交写请求。

## Read-only live verification

```bash
CONTAINER_GUI_LIVE_READONLY=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift test --filter ReadOnlyCLISmokeTests
```

该测试可增加镜像列表/详情读取，但不得调用 pull、create 或 start。

Docker Hub 的真实只读探测是可选门禁：

```bash
CONTAINER_GUI_LIVE_REGISTRY_READONLY=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift test --filter RegistryReadOnlySmokeTests
```

## Local browser verification

在未占用端口启动当前构建：

```bash
CONTAINER_GUI_PORT=8788 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift run ContainerGUI
```

打开 `http://127.0.0.1:8788/`，确认：

1. 镜像区域显示本机镜像名称、摘要、平台和大小。
2. 本机镜像不分页，当前列表中的全部镜像直接展示。
3. 远程区域初始不请求注册表；输入 `postgres` 并点击搜索后分页展示 Docker Hub 仓库。
4. 选择 Docker Hub 仓库后分页展示确切标签；点击标签只打开并回填拉取对话框。
5. 镜像拉取 Operation 显示下载、解压、验证阶段及可访问的原生进度条；浏览器自动化只使用模拟对象
   或隔离测试 CLI，不提交真实拉取。
6. 本机镜像区域默认展开；“本机镜像”标题旁箭头向下。点击后内容隐藏且箭头向右，再次点击恢复；
   `aria-expanded` 和“收起/展开本机镜像”无障碍名称始终与可见状态一致，右侧不显示文字折叠按钮。
7. “拉取镜像”对话框只包含完整地址和 Docker Hub 两种输入方式，以及可选目标架构。
8. Docker Hub 的 `postgres:latest` 提交为 `docker.io/library/postgres:latest`；其他 OCI 注册表完整地址原样提交。
9. 页面不显示 GHCR 平台、owner 输入或 GitHub Token 配置。
10. “创建容器”对话框包含名称、镜像、CPU、内存、端口、环境变量、进程参数和创建后启动。
11. 本地镜像名称可用于创建表单建议。
12. 无效输入显示逐字段中文错误，未发出写请求。
13. 不提交任何真实拉取或创建操作。

## Mutation acceptance with explicit authorization only

若用户之后单独授权真实写操作，验收必须记录：

1. 完整镜像引用或容器名称及所有非秘密参数。
2. 写操作前的镜像或容器权威列表。
3. 202 Operation 和轮询到的终态。
4. CLI 退出状态。
5. 独立 `image inspect` 或容器列表回读。
6. 若创建后启动，最终必须额外回读运行中状态。

任何缺失回读、目标冲突、超时或部分成功均不得声明完成。
