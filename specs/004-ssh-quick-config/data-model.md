# Data Model: SSH 快速配置

## SSHCreateConfiguration

创建容器请求中的可选、只写 SSH 设置。

| Field | Type | Rules |
|---|---|---|
| hostPort | Int | 1024...65535；不得与 `ports[].hostPort` 重复 |
| username | String | `^[a-z_][a-z0-9_-]{0,31}$`；不得为 `root` |
| publicKey | String | 单行、1...4096；受支持类型 + 可解码 Base64 主体；不回显 |

当 `ssh` 非空时：

- `startAfterCreate` 必须为 `true`。
- `arguments` 必须为空。
- `environment` 不得包含保留名称 `CONTAINER_GUI_SSH_USER` 或
  `CONTAINER_GUI_SSH_AUTHORIZED_KEY`。
- 命令额外发布 `127.0.0.1:hostPort:22/tcp`。

## ContainerSSHMetadata

从容器当前配置标签派生的非秘密数据。

| Field | Type | Rules |
|---|---|---|
| host | String | 固定 `127.0.0.1`，不从标签或请求读取 |
| hostPort | Int | 已验证的 1024...65535 标签值 |
| username | String | 已验证的非 root 安全用户名标签值 |
| connectionCommand | String | 派生为 `ssh -p hostPort username@127.0.0.1` |

固定标签：

- `io.github.zeal-odoo.container-gui.ssh.enabled=true`
- `io.github.zeal-odoo.container-gui.ssh.host-port=<port>`
- `io.github.zeal-odoo.container-gui.ssh.username=<username>`

任何缺失或非法标签都使 `ContainerSSHMetadata` 为空，不会触发端口探测。

## ContainerSSHState

| Value | Meaning |
|---|---|
| notConfigured | 容器没有一组完整、有效的 SSH 标签 |
| stopped | 已配置，但容器不是运行中或错误状态 |
| initializing | 容器运行中，但尚未收到有效 SSH 协议横幅 |
| ready | 容器运行中，且回环映射端口在超时内返回 `SSH-` 横幅 |
| failed | 容器当前为错误状态 |

状态转换：

```text
notConfigured

configured + created/stopped -> stopped
stopped -> starting -> initializing -> ready
ready -> stopped
initializing -> failed (container error or create/start Operation failure)
ready -> failed (container error)
```

页面每次刷新重新读取，不持久化该派生状态。

## ContainerSSHStatus

| Field | Type | Rules |
|---|---|---|
| containerId | String | 当前详情回读的精确 ID |
| state | ContainerSSHState | 必填 |
| connection | ContainerSSHMetadata? | 已配置时存在 |
| observedAt | Date | 本次详情与横幅检查完成时间 |

## ContainerCreateRequest extension

现有字段保持不变，新增：

| Field | Type | Default |
|---|---|---|
| ssh | SSHCreateConfiguration? | `null` |

未提供 `ssh` 时，命令形状与 v2.4.0 完全一致。

## Safe request summary

启用 SSH 的创建摘要示例：

```json
{
  "name": "demo-ssh",
  "image": "docker.io/library/ubuntu:26.04",
  "ports": [],
  "environmentNames": [],
  "argumentCount": 0,
  "startAfterCreate": true,
  "ssh": {
    "host": "127.0.0.1",
    "hostPort": 2222,
    "username": "dev",
    "publicKeyType": "ssh-ed25519",
    "publicKeyFingerprint": "SHA256:..."
  }
}
```

完整公钥和保留环境变量值不得进入摘要、Operation、ProblemDetail 或详情 JSON。

## Restart semantics

容器的入口点固定为幂等 SSH 初始化脚本。停止容器只终止主进程；根文件系统、容器标签、端口发布、
`authorized_keys` 和 `/etc/ssh/ssh_host_*` 仍属于同一容器。下一次 `container start <id>` 重新执行脚本：

1. 已安装的 sshd 不重复安装。
2. 用户和授权文件更新为当前容器配置中的保留环境值。
3. `ssh-keygen -A` 只生成缺失主机密钥。
4. 配置校验通过后重新 `exec sshd -D -e`。

删除并重新创建容器是新资源，不承诺保留服务器主机密钥。
