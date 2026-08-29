# Research: 拉取镜像与创建容器

## Decision 1: 使用当前官方 CLI 的固定命令形状

**Decision**: 兼容基线固定为本机已验证的 Apple Container CLI 1.3.1：

- 镜像列表：`container image list --format json`
- 镜像详情：`container image inspect <reference>`
- 镜像拉取：`container image pull --progress plain [--platform <platform>] <reference>`
- 容器创建：`container create --name <name> [受控选项] -- <image> [参数...]`
- 容器回读：`container list --all --format json`

**Rationale**: 本机 `--help` 和只读 JSON 已验证，参数全部可作为独立数组元素传递；`--` 防止镜像后的
进程参数被重新解释为创建选项。拉取与创建输出无需作为成功事实，最终均由结构化只读命令验证。

**Alternatives considered**:

- 直接链接 Containerization 包：超出宪章边界且增加内部 API 兼容风险。
- 解析默认表格输出：字段和本地化不稳定，已有 JSON 可用。
- 解析拉取/创建 stdout 作为结果：不能证明最终资源状态，拒绝。

## Decision 2: 提供权威镜像列表并用 inspect 完成拉取回读

**Decision**: 页面读取规范化镜像摘要列表；拉取完成后使用原请求引用执行详情读取。详情解析为
名称、索引摘要、平台变体、各变体大小和观测时间。指定平台时至少有一个变体必须匹配。

**Rationale**: `image inspect postgres:latest` 能解析为规范化的
`docker.io/library/postgres:latest`，可避免自行实现 OCI 名称补全规则；摘要和平台来自运行时事实。

**Alternatives considered**:

- 只在完整列表中按输入字符串匹配：短名称与规范化名称不同，会产生假失败。
- 自行规范化 Docker Hub 短名称：重复实现注册表规则并容易与 CLI 漂移。
- 拉取退出码为零即成功：缺少权威回读，不满足宪章。

## Decision 3: 创建表单只覆盖常用且可安全验证的参数

**Decision**: 必填名称和镜像；可选 CPU 数、内存 MiB、回环端口映射、环境变量、逐行进程参数和
创建后启动。端口始终生成 `127.0.0.1:<host>:<container>/<protocol>`；不接受主机 IP、挂载、网络、
能力、DNS、内核、Rosetta、入口点、任意 flag 或 shell 文本。

**Rationale**: 这些字段覆盖常见服务容器，又能在不增加文件系统授权和主机网络暴露的情况下形成
轻量 MVP。逐字段模型可产生稳定验证错误和确定的参数数组。

**Alternatives considered**:

- 暴露原始参数文本：无法可靠区分参数与 shell，违反白名单原则。
- 首版支持所有 `container create` 选项：表单、校验和安全面过大。
- 使用“命令行字符串”解析引号：引入不必要的 shell 语义和歧义。

## Decision 4: 复用异步操作协调器

**Decision**: 增加 `pullImage`、`createContainer` 操作类型和镜像目标。POST 请求继续要求 UUID
幂等键并立即返回操作；同一镜像引用或容器名称串行，全局并发限制沿用现值。创建后启动是同一
操作内的第二阶段，只有创建回读通过后才能执行。

**Rationale**: 镜像下载耗时不可预测，HTTP 请求不应保持到下载结束；现有状态机已经区分执行与
验证并支持轮询、TTL 和安全错误。

**Alternatives considered**:

- 同步等待拉取完成：容易触发浏览器和代理超时。
- 为每类资源建立新队列：重复协调逻辑，增加状态不一致风险。
- 创建和启动拆成两个用户操作：无法提供用户期望的一次“创建后启动”流程。

## Decision 5: 环境变量值只写且幂等指纹使用摘要

**Decision**: 请求解码后，环境变量值只用于构造子进程参数。操作安全摘要只保留变量名；请求指纹
对规范化完整请求计算内存中的 SHA-256，不存储原始秘密。问题响应、回读和页面状态均不包含值。

**Rationale**: 幂等冲突必须区分值不同的请求，但宪章禁止把秘密写入操作记录或日志。固定摘要既能
比较又不可直接回显秘密。

**Alternatives considered**:

- 指纹直接拼接完整请求：秘密会长期存在于协调器记录。
- 指纹忽略环境变量值：不同配置可能被错误当作同一请求重放。
- 持久化加密秘密：本项目无需数据库，也不应承担凭据存储职责。

## Decision 6: 变更超时与读取超时分开

**Decision**: 镜像拉取使用单独的长变更超时；创建和可选启动使用受控变更超时；镜像列表、详情和
容器回读继续使用短查询超时。取消或超时终止对应 CLI 子进程，并将操作标记失败。

**Rationale**: 下载可能明显超过现有 30 秒变更超时，而只读回读应快速失败；分开后不会放宽健康、
列表和详情的响应边界。

**Alternatives considered**:

- 全部沿用 30 秒：正常大镜像容易被误判超时。
- 全局提高查询超时：会降低现有状态页面故障反馈速度。

## Decision 7: 静态页面使用两个受控对话框

**Decision**: 在现有仪表盘增加镜像区域、拉取镜像对话框和创建容器对话框；使用原生表单控件、
逐字段错误、禁用中的提交按钮和现有操作轮询。环境变量与进程参数使用逐行输入说明。

**Rationale**: 不增加前端构建链即可保持键盘可用和低复杂度；对话框避免把长表单永久挤入概览。

**Alternatives considered**:

- 单页暴露全部字段：降低容器列表可读性。
- 引入前端框架：当前交互规模不需要，违反简洁原则。

## Decision 8: 仓库选择只解析为完整镜像引用

**Decision**: 拉取表单增加 Docker Hub 和 GHCR 快捷选择，并把原有“平台”明确命名为“目标架构”。
Docker Hub 官方短名称解析到 `docker.io/library/`，命名空间镜像解析到 `docker.io/`；GHCR 要求
`owner/repository` 并解析到 `ghcr.io/`。未选择快捷项时仍接受完整镜像引用。

**Rationale**: 用户可以明确选择常用镜像仓库，同时后端继续只接收经过现有校验的单个完整引用，
无需新增凭据存储、注册表配置或 CLI 参数类型。

**Alternatives considered**:

- 把仓库作为新的后端 CLI 参数：`container image pull` 没有独立仓库参数，会重复表达目标。
- 自动尝试多个仓库：结果不确定，也可能把认证错误误判为镜像不存在。
- 在页面保存仓库凭据：超出本功能安全边界。

## Decision 9: Docker Hub 使用官方 JSON 端点分页搜索

**Decision**: 用户提交非空关键词后，请求
`https://hub.docker.com/v2/search/repositories/?query=<query>&page_size=20&page=<page>`；打开结果时请求
`/v2/namespaces/<namespace>/repositories/<repository>/tags?page_size=20&page=<page>`。官方短名称统一显示为
`docker.io/library/<name>`。服务自行计算下一页参数，不跟随上游返回的任意 URL。

**Rationale**: Docker Hub 当前端点提供总数、仓库摘要和分页标签，能满足“搜索全部匹配结果”而无需
抓取 HTML。固定主机、固定路径模板和页大小可防止服务成为任意 URL 代理。

**Alternatives considered**:

- 只在本机镜像列表中过滤：无法发现远程镜像。
- 抓取 Docker Hub 页面：结构不稳定且增加浏览器自动化依赖。
- 一次下载所有页：热门关键词可能有数万结果，会拖慢页面并放大限流风险。

## Decision 10: GHCR 使用用户或组织范围的 GitHub Packages API

**Decision**: GHCR 不做无范围的全站关键词搜索。用户明确选择 `user` 或 `organization` 并输入
owner；服务通过 `/users/<owner>/packages` 或 `/orgs/<owner>/packages` 分页读取 Token 有权访问的 container 包，
再通过对应 package versions 端点读取标签。只接受环境变量 `CONTAINER_GUI_GITHUB_TOKEN`，以 Bearer
header 发送，并固定 `X-GitHub-Api-Version: 2026-03-10`；Token 不进入响应、日志、Git 或浏览器。

**Rationale**: GitHub Packages REST API 的可枚举边界是用户或组织，官方 GitHub 搜索语法可用于网页
搜索但没有等价的公共全站包搜索 REST 契约。`visibility` 是可选过滤器，因此不发送该参数，保留
Token 对公开、私有和内部 package 的既有可读范围；明确 owner 范围能提供稳定分页和可测试行为。

**Alternatives considered**:

- 模拟 GitHub 网页的 package 搜索：不是稳定 API，容易受页面和登录状态影响。
- 要求用户在页面粘贴 Token：秘密会进入浏览器状态和请求日志，拒绝。
- 将 Token 写入配置文件：增加凭据生命周期和权限管理，首版不需要。

## Decision 11: 远程读取采用可注入的固定允许列表 HTTP 适配器

**Decision**: 使用 Foundation `URLSession` 实现 `RegistryHTTPTransport`，业务客户端只构造
`hub.docker.com` 和 `api.github.com` 的 HTTPS 请求。超时 5 秒、响应最大 2 MiB、页码 1...500、固定
每页 20 项。测试使用净化后的版本化 JSON 夹具和内存 transport，不进行真实写操作。

**Rationale**: 项目已有 Swift 单服务，Foundation 足以完成简单 GET；协议注入让 URL、header、分页、
错误和秘密保护都能在离线测试中验证。

**Alternatives considered**:

- 新增 HTTP 客户端依赖：本功能只有少量 GET，无需扩大依赖面。
- 服务接受完整上游 URL：会引入 SSRF 风险。
- 增加数据库缓存：单用户轻量工具首版没有必要，页面保留当前查询结果即可。

## Decision 12: 标签选择只回填，不自动拉取

**Decision**: 页面首次直接展示全部本机镜像；远程请求仅在用户点击搜索后发生。仓库和标签各自分页，
点击某个确切标签后将完整 `docker.io/...:<tag>` 或 `ghcr.io/...:<tag>` 引用回填到现有拉取对话框，
仍需用户再次确认并提交拉取。

**Rationale**: 远程结果与本机状态保持清晰分离；显式标签避免隐含 `latest`，二次确认维持写操作边界。

**Alternatives considered**:

- 选中仓库即拉取 `latest`：标签可能不存在，也属于未经确认的真实写操作。
- 搜索时同时加载每个仓库全部标签：会产生大量请求并容易触发限流。
- 对本机镜像分页：本机规模为数十项，增加交互但没有实际收益。

## Decision 13: 使用 CLI plain 输出提供真实拉取进度

**Decision**: 镜像拉取改用 `--progress plain`，通过现有流式进程执行器同时读取 stdout/stderr。只解析
`[阶段/总阶段] Fetching image` 与 `Unpacking image` 完整行，将 CLI 百分比换算为总体百分比并保证
Operation 内单调不倒退；命令成功退出后进入 100% 的验证阶段，最终成功仍取决于独立镜像回读。

**Rationale**: Apple Container CLI 1.3.1 已提供稳定的 plain 阶段输出；使用该事实数据可避免按时间伪造
百分比，同时复用现有 500ms Operation 轮询，无需增加 WebSocket、数据库或真实拉取测试。

**Alternatives considered**:

- 仅显示循环动画：无法回答已经完成多少，不满足用户要求。
- 按经过时间估算百分比：下载大小和网络速度未知，会产生虚假进度。
- 把 CLI 原始输出直接推到浏览器：扩大输出与转义边界，也会暴露不必要的诊断文本。

## Decision 14: 删除仅支持停止目标并以缺失回读验收

**Decision**: 容器详情只在 `stopped` 或 `created` 状态显示“删除容器”。提交必须携带精确确认目标和
幂等键；后端再次读取状态后，仅以参数数组 `delete <id>` 执行，不提供 `--all` 或 `--force`。退出为零后
重新读取完整容器列表，目标确实缺失才完成 Operation。

**Rationale**: 删除是不可恢复操作，运行中拒绝和双重状态检查可避免页面状态陈旧造成误删；缺失回读
保持官方 CLI 为唯一事实来源，也不会把接受请求或退出码误报为完成。

**Alternatives considered**:

- 自动停止后删除：把两个破坏性动作合并，扩大一次确认的影响，拒绝。
- 暴露 `--force`：可能直接终止运行中负载，不符合当前安全边界。
- 只刷新页面、不保存 Operation 回读：无法区分请求接受和实际删除，拒绝。
