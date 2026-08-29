# Data Model: 拉取镜像与创建容器

## ImagePlatform

一个镜像变体的平台标识。

| Field | Type | Rules |
|---|---|---|
| os | String | 必填；当前只接受 `linux` |
| architecture | String | 必填；`arm64` 或 `amd64` |
| variant | String? | 可选；只允许字母、数字、点、下划线和短横线 |

显示值为 `os/architecture[/variant]`。

## ImageSummary

本机权威镜像或镜像索引的规范化摘要。

| Field | Type | Rules |
|---|---|---|
| id | String | 必填；CLI 返回的内容标识 |
| name | String | 必填；CLI 规范化镜像名称 |
| digest | String | 必填；`sha256:` 加 64 位十六进制 |
| platforms | [ImagePlatform] | 可为空；过滤 `unknown/unknown` 证明变体 |
| sizeBytes | UInt64 | 所有可用变体大小之和；不得溢出 |
| observedAt | Date | 权威读取时间 |

## ImageList

| Field | Type | Rules |
|---|---|---|
| items | [ImageSummary] | 最多 1000 项；名称和 ID 分别唯一 |
| observedAt | Date | 本次完整列表观测时间 |

## ImagePullRequest

| Field | Type | Rules |
|---|---|---|
| reference | String | 1...512；匹配受控镜像引用字符集；无空白、控制符或前导 `-` |
| platform | String? | 空或 `linux/arm64`、`linux/amd64`，可带安全 variant |

浏览器中的仓库快捷选择不是 API 字段。选择 Docker Hub 时，短官方镜像补全为
`docker.io/library/<image>`，带命名空间的镜像补全为 `docker.io/<namespace>/<image>`。未选择快捷仓库时，
完整 OCI 引用原样提交。
若输入已含与所选项不同的仓库主机，页面在发出请求前拒绝。

### State transition

`queued -> running -> verifying -> succeeded|failed`

`running` 执行拉取；`verifying` 使用原引用读取详情并检查可选平台；只有匹配才成功。

## ImagePullProgress

镜像拉取期间由 CLI `--progress plain` 的完整行解析，并作为 `Operation.progress` 的可选字段返回。

| Field | Type | Rules |
|---|---|---|
| phase | ImagePullProgressPhase | `fetching`、`unpacking` 或 `verifying` |
| percentComplete | Int | 0...100；按 CLI `[当前阶段/总阶段]` 与阶段百分比计算，Operation 内单调不倒退 |
| completedUnits | Int? | CLI 提供 Blob 计数时返回，非负 |
| totalUnits | Int? | CLI 提供 Blob 总数时返回，正数 |
| updatedAt | Date | 本次进度观测时间 |

无法解析的输出行被忽略；尚无百分比时 Operation 可以没有 progress，页面使用原生不确定进度条。
命令退出成功后进入 `verifying`，进度设为 100%，但只有权威镜像回读匹配后 Operation 才能成功。

## PortMapping

| Field | Type | Rules |
|---|---|---|
| hostPort | Int | 1024...65535；同一请求中唯一；GUI 不使用 root 权限 |
| containerPort | Int | 1...65535 |
| protocol | String | `tcp` 或 `udp`，默认 `tcp` |

命令参数始终由服务规范化为 `127.0.0.1:hostPort:containerPort/protocol`；SSH 的典型映射为
`127.0.0.1:2222:22/tcp`，但镜像仍需自行安装并运行 SSH 服务。

## EnvironmentEntry

| Field | Type | Rules |
|---|---|---|
| name | String | `^[A-Za-z_][A-Za-z0-9_]*$`；同一请求中唯一 |
| value | String | 0...4096；只写，不进入响应、摘要或错误 |

## ContainerCreateRequest

| Field | Type | Rules |
|---|---|---|
| name | String | 1...128；`^[A-Za-z0-9][A-Za-z0-9._-]*$` |
| image | String | 与 ImagePullRequest.reference 相同规则 |
| cpus | Double? | 空或有限正数，最大 1024 |
| memoryMiB | Int? | 空或 1...1048576；命令中转换为 `nM` |
| ports | [PortMapping] | 最多 32 项 |
| environment | [EnvironmentEntry] | 最多 64 项 |
| arguments | [String] | 最多 64 项；每项 0...4096 且无 NUL |
| startAfterCreate | Bool | 默认 `false` |

### State transition

不自动启动：

`queued -> running(create) -> verifying(created/stopped readback) -> succeeded|failed`

创建后启动：

`queued -> running(create) -> verifying(created/stopped readback) -> running(start) -> verifying(running readback) -> succeeded|failed`

实现可在同一操作内部记录阶段，但对外 Operation.state 保持现有枚举；任何阶段失败都终止后续阶段。

## Operation extensions

### OperationKind

新增：

- `pullImage`
- `createContainer`

### OperationTarget

新增 `image(reference)`；容器创建使用 `container(name)`，与已有按容器 ID 的锁共享同一目标空间。

### OperationReadback

新增可选 `observedImage`。镜像拉取成功时必须存在；容器创建沿用 `observedContainer`。

## Safe summaries

### Pull image

```json
{"reference":"docker.io/library/postgres:latest","platform":"linux/arm64"}
```

### Create container

```json
{
  "name":"demo-postgres",
  "image":"postgres:latest",
  "cpus":2,
  "memoryMiB":2048,
  "ports":["127.0.0.1:15432:5432/tcp"],
  "environmentNames":["POSTGRES_PASSWORD"],
  "argumentCount":0,
  "startAfterCreate":false
}
```

环境变量值永远不进入安全摘要。

## RemoteRegistry

远程镜像来源枚举：

- `dockerHub`

## RemoteRepositorySummary

| Field | Type | Rules |
|---|---|---|
| registry | RemoteRegistry | 必填 |
| repository | String | 注册表内规范路径；Docker 官方镜像包含 `library/` |
| reference | String | 不含标签的完整 `docker.io/...` 引用 |
| name | String | 用于显示的仓库或 package 名称 |
| namespace | String | Docker 命名空间 |
| description | String? | 可选；净化为纯文本，最多 2048 字符 |
| isOfficial | Bool? | Docker Hub 可用 |
| starCount | Int? | 上游可用时返回，非负 |
| pullCount | Int? | 上游可用时返回，非负 |
| updatedAt | Date? | 上游可用时返回 |

## RemoteTagSummary

| Field | Type | Rules |
|---|---|---|
| name | String | 确切标签；1...256；不允许空白、控制符、`/` 或前导 `-` |
| reference | String | `RemoteRepositorySummary.reference + ":" + name` |
| digest | String? | 上游可用时为 `sha256:` 摘要 |
| sizeBytes | UInt64? | 上游可用时为非负值 |
| updatedAt | Date? | 上游可用时返回 |

## RemoteRepositoryPage

| Field | Type | Rules |
|---|---|---|
| items | [RemoteRepositorySummary] | 最多 20 项 |
| page | Int | 1...500 |
| pageSize | Int | 固定 20 |
| totalCount | Int? | Docker Hub 可用 |
| hasNextPage | Bool | 由计数或受信 Link header 推导；客户端自行构造下一页 URL |
| observedAt | Date | 本次远程读取时间 |

## RemoteTagPage

字段与 `RemoteRepositoryPage` 相同，但 `items` 为 `[RemoteTagSummary]`。`pageSize=20` 表示 Docker Hub
每页的 tag 数量，整个上游响应受 2 MiB 上限约束。

## Remote query validation

### Docker Hub repository search

| Field | Rules |
|---|---|
| registry | 必须为 `dockerHub` |
| query | 去除首尾空白后 1...128；不得包含控制符 |
| page | 可选，默认 1，范围 1...500 |

### Tag browse

Docker Hub 要求规范的 `<namespace>/<repository>`。
所有值只参与固定路径模板和百分号编码，调用方不能传入主机、scheme 或完整 URL。

## Remote error mapping

| Code | HTTP | Retryable | Meaning |
|---|---:|---|---|
| REGISTRY_RATE_LIMITED | 429 | true | 上游限流；保留安全的重试提示 |
| REGISTRY_UNAVAILABLE | 502 | true | 上游超时、不可达或返回无效 JSON |

远程对象只保存在请求和浏览器当前状态中，不写入数据库。选择标签只产生完整镜像引用并回填已有
`ImagePullRequest` 表单；不会创建 Operation，也不会调用 Apple Container CLI。
