# Research: Odoo 与通用共享目录

## Decision 1: 使用 Apple Container 的显式 bind mount 参数

**Decision**: 创建命令使用单个参数值 `type=bind,source=<host>,target=<container>`；不添加 `readonly`，因此为读写挂载。

**Rationale**: 当前 Apple Container CLI 1.3.1 的 `container create --help` 明确支持 `--mount`，官方卷文档示例也使用 `source` 与 `target`。参数数组可保留空格并避免 shell 注入，符合项目命令边界。

**Alternatives considered**:

- `--volume host:container`：语义更短，但显式键值格式更易校验且与 CLI 帮助一致。
- 自动创建宿主机目录：会产生额外文件系统写入并可能掩盖拼写错误，因此拒绝。
- 多目录和只读开关：超出本次一个可读写交换目录的范围。

**Evidence**: [Apple Container volume documentation](https://github.com/apple/container/blob/main/docs/volumes.md)；本机 CLI 1.3.1 `container create --help`。

## Decision 2: 只识别 Docker Hub 官方 Odoo 仓库

**Decision**: Odoo 专属模式只接受仓库部分精确为 `odoo` 或 `docker.io/library/odoo` 的引用，包括标签或摘要；`owner/odoo`、`ghcr.io/.../odoo` 和名称中仅含 `odoo` 的镜像按普通镜像处理。

**Rationale**: 官方镜像的入口、环境变量和目录约定可验证；第三方镜像可能改变这些约定。精确匹配还能防止浏览器与服务端因模糊子串判断出现权限边界差异。

**Alternatives considered**:

- 任意名称包含 `odoo`：误报风险高，可能向无关镜像注入 `HOST`/`PORT`。
- inspect 每个镜像标签判断：需要新增请求和解析兼容面，且镜像标签不保证可信，首期不采用。
- 允许用户手动选择“Odoo 模式”：扩展性更强，但会把错误配置风险交给用户，当前官方镜像需求不需要。

## Decision 3: Odoo 自定义模块固定到官方目录

**Decision**: 官方 Odoo 镜像的共享目录目标固定 `/mnt/extra-addons`，浏览器不可编辑，服务端也要求完全一致。

**Rationale**: Odoo 官方镜像文档指定该目录用于挂载自定义 addons；当前本机 Odoo 19 镜像 inspect 也显示它被创建、归属 `odoo` 用户并声明为 volume。

**Alternatives considered**:

- 允许任意目标：容易挂载到未加入 addons_path 的目录，表面创建成功但模块不可见。
- 挂载到 `/usr/lib/python3/dist-packages/odoo/addons`：会覆盖镜像自带代码，风险过高。

**Evidence**: [Docker Official Image for Odoo](https://hub.docker.com/_/odoo)；本机 `docker.io/library/odoo:19.0-20260817` inspect。

## Decision 4: 数据库地址和端口使用官方环境契约

**Decision**: Odoo 表单默认 `HOST=db`、`PORT=5432`，用户可修改；创建时转换为 `HOST` 与 `PORT` 环境配置。结构化配置与普通环境变量中同名项不能并存。

**Rationale**: 官方 Odoo entrypoint 使用这两个环境变量配置 PostgreSQL 端点。结构化字段满足简单 GUI 需求，冲突校验避免参数顺序决定最终值。

**Alternatives considered**:

- 生成 Odoo 命令行 `--db_host`/`--db_port`：会与用户进程参数和镜像入口交织，重启语义更难解释。
- 同时增加用户和密码字段：用户未要求，且会扩大秘密处理范围；现有环境变量字段仍可满足需要。
- 非 Odoo 也显示字段：增加噪声并可能误注入，拒绝。

**Evidence**: [Docker Official Image for Odoo](https://hub.docker.com/_/odoo)。

## Decision 5: 路径在客户端提示、服务端权威校验

**Decision**: 浏览器做快速格式提示；Swift 服务端验证宿主机路径为非根绝对路径、无危险分隔内容、实际存在且为目录，容器目标为非根安全绝对路径。操作摘要只记录是否配置挂载和容器目标，不回显宿主机路径。

**Rationale**: 浏览器不能成为安全边界，也不能可靠取得服务所在 Mac 的目录绝对路径。服务端检查可在真实 CLI 变更前失败；摘要脱敏降低本机用户名和项目结构泄漏。

**Alternatives considered**:

- Web 目录选择器：浏览器通常不暴露可供服务端使用的真实绝对路径，不能满足此本机 B/S 架构。
- 只依赖 CLI 报错：错误发生更晚、字段定位更差。
- 扫描并提供目录列表：扩大本机信息暴露范围，不符合最小权限。
