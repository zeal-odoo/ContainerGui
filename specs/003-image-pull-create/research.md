# Research: 拉取镜像与创建容器

## Decision 1: 使用当前官方 CLI 的固定命令形状

**Decision**: 兼容基线固定为本机已验证的 Apple Container CLI 1.3.1：

- 镜像列表：`container image list --format json`
- 镜像详情：`container image inspect <reference>`
- 镜像拉取：`container image pull --progress none [--platform <platform>] <reference>`
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
