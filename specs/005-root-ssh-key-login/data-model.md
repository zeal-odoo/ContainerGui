# Data Model: root 公钥 SSH 登录

## SSHCreateConfiguration

现有创建请求中的可选、只写 SSH 设置增加一个显式高权限字段。

| Field | Type | Rules |
|---|---|---|
| hostPort | Int | 1024...65535；不得与 `ports[].hostPort` 重复 |
| username | String | 普通模式为安全非 root 用户名；root 模式必须恰好为 `root` |
| publicKey | String | 单行、1...4096；受支持类型与可解码 Base64 主体；不回显 |
| loginAsRoot | Bool | 缺省 `false`；只有显式为 `true` 才允许 `username=root` |

身份校验矩阵：

| loginAsRoot | username | Result |
|---|---|---|
| false / omitted | valid standard user | accepted |
| false / omitted | root | rejected |
| true | root | accepted |
| true | any other value | rejected |

安全摘要可记录 `loginAsRoot`、有效用户名、端口、公钥类型和指纹，但不得包含完整公钥。

## ContainerSSHConnection

结构不变，用户名标签现在接受安全普通用户名或精确的 `root`。

| Field | Type | Rules |
|---|---|---|
| host | String | 固定 `127.0.0.1` |
| hostPort | Int | 1024...65535 |
| username | String | 安全普通用户名或 `root` |
| connectionCommand | String | 派生为 `ssh -p hostPort username@127.0.0.1` |

root 示例：

```json
{
  "host": "127.0.0.1",
  "hostPort": 2001,
  "username": "root",
  "connectionCommand": "ssh -p 2001 root@127.0.0.1"
}
```

## SSH bootstrap identity state

```text
validated standard user
  -> create/reuse user
  -> resolve home
  -> write user authorized_keys
  -> PermitRootLogin no

validated root user
  -> reuse root
  -> fixed /root home
  -> write root authorized_keys
  -> non-password shadow marker
  -> PermitRootLogin prohibit-password
```

两个分支都继续禁用密码、键盘交互、挑战响应和空密码认证，只允许标签中的单一用户，并以 `sshd -D` 作为主进程。每次容器启动重复执行幂等配置，所以授权文件和策略在重启后恢复。

## ContainerCreateRequest compatibility

`ssh.loginAsRoot` 缺省为 `false`，因此旧客户端省略该字段时保持普通用户语义。未提供 `ssh` 时，非 SSH 创建请求完全不变。

## Browser form state

| State | SSH enabled | root selected | username input |
|---|---:|---:|---|
| SSH disabled | false | false and disabled | disabled, normal value retained |
| standard SSH | true | false | enabled, normal value |
| root SSH | true | true | disabled, visible value `root` |

从 root SSH 返回 standard SSH 时恢复本次打开表单前保存的普通用户名；关闭对话框不持久化此状态。
