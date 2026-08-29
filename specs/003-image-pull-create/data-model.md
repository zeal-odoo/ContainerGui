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
`docker.io/library/<image>`，带命名空间的镜像补全为 `docker.io/<namespace>/<image>`；选择 GHCR 时，
要求输入 `owner/repository` 并补全为 `ghcr.io/<owner>/<repository>`。未选择快捷仓库时，引用原样提交。
若输入已含与所选项不同的仓库主机，页面在发出请求前拒绝。

### State transition

`queued -> running -> verifying -> succeeded|failed`

`running` 执行拉取；`verifying` 使用原引用读取详情并检查可选平台；只有匹配才成功。

## PortMapping

| Field | Type | Rules |
|---|---|---|
| hostPort | Int | 1...65535；同一请求中唯一 |
| containerPort | Int | 1...65535 |
| protocol | String | `tcp` 或 `udp`，默认 `tcp` |

命令参数始终由服务规范化为 `127.0.0.1:hostPort:containerPort/protocol`。

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
