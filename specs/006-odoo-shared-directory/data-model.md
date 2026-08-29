# Data Model: Odoo 与通用共享目录

## SharedDirectoryConfiguration

单次创建请求中可选的一个本机目录挂载。

| Field | Type | Required | Validation |
|---|---|---:|---|
| `hostPath` | String | yes | 1...4096；绝对路径；不是 `/`；无 NUL、换行、逗号或 `.`/`..` 路径段；当前服务可见且为目录 |
| `containerPath` | String | yes | 1...4096；绝对路径；不是 `/`；无 NUL、换行、逗号或 `.`/`..` 路径段 |

Rules:

- 请求对象缺失时不创建挂载。
- 挂载固定为读写；首期没有 `readOnly` 或多项数组。
- 官方 Odoo 镜像要求 `containerPath == "/mnt/extra-addons"`。
- 安全操作摘要只包含 `configured=true` 与 `containerPath`，不包含 `hostPath`。

## OdooDatabaseConfiguration

仅 Docker Hub 官方 Odoo 镜像允许的数据库端点。

| Field | Type | Required | Validation |
|---|---|---:|---|
| `host` | String | yes | 1...255；主机名、IPv4 或 IPv6；无空白、控制符、URL 路径或参数字符 |
| `port` | Integer | yes | 1...65535；默认 5432 |

Rules:

- 官方 Odoo 表单默认创建 `{host: "db", port: 5432}`。
- 非 Odoo 镜像携带该对象时请求无效。
- 存在该对象时，普通 `environment` 不得再包含 `HOST` 或 `PORT`。
- CLI 转换为两个独立参数值：`HOST=<host>` 与 `PORT=<port>`。
- 安全操作摘要只记录 `odooDatabaseConfigured=true`，不记录地址或端口值。

## ImageClassification

由创建请求的 `image` 派生，不单独持久化。

| Value | Repository match | UI and validation behavior |
|---|---|---|
| `officialOdoo` | `odoo` or `docker.io/library/odoo`, with optional tag/digest | fixed addons target; database fields visible and allowed |
| `generic` | every other valid image reference | editable default `/workspace`; Odoo database object rejected |

## ContainerCreateRequest changes

现有请求新增两个向后兼容的可选字段：

- `sharedDirectory: SharedDirectoryConfiguration?`
- `odooDatabase: OdooDatabaseConfiguration?`

缺省解码为 `nil`。现有名称、镜像、CPU、内存、端口、环境变量、进程参数、启动和 SSH 校验保持不变。

## Validation order

1. 验证现有创建字段与镜像引用。
2. 从已验证镜像引用派生镜像类别。
3. 若有共享目录，验证路径格式、宿主机存在性及 Odoo 固定目标。
4. 若有 Odoo 数据库配置，验证镜像类别、地址、端口和环境变量冲突。
5. 聚合所有字段错误并在任何 CLI 进程前返回。
6. 通过后构造固定 CLI 参数，执行创建，并使用现有容器列表回读验证结果。
