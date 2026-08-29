# Research: root 公钥 SSH 登录

## Decision 1: 用显式布尔字段表达 root 授权

**Decision**: SSH 创建对象增加 `loginAsRoot` 布尔字段，缺省为 `false`。只有 `loginAsRoot=true` 且 `username=root` 时才接受 root；普通模式仍拒绝 `root`。

**Rationale**: 单看用户名无法区分用户明确选择与误填。显式字段让 GUI、API 校验、操作摘要和测试都能证明高权限选择，同时缺省值保持既有请求兼容。

**Alternatives considered**:

- 只允许把用户名输入为 `root`：没有单独的高权限确认，容易误操作。
- 新增完全独立的 root SSH 接口：重复现有创建流程和校验，复杂度不必要。
- 只在浏览器保存复选框、不发送服务端：服务端无法建立安全边界。

## Decision 2: root 模式复用现有身份字段和标签

**Decision**: root 模式把有效登录身份固定为 `root`，继续通过现有用户环境变量和用户名标签传递/回读；不新增 root 专用标签。容器详情从用户名标签派生 `root@127.0.0.1` 命令。

**Rationale**: 端口、标签、状态探测和重启恢复已经围绕“有效 SSH 身份”工作。`root` 是唯一特殊身份，用同一字段即可完整表达，不需要并行元数据或数据库。

**Alternatives considered**:

- 增加 root 专用标签：与用户名标签重复，可能产生矛盾状态。
- 从授权文件猜测 root 模式：需要额外容器读取并泄露配置边界。
- 浏览器记住 root 选择：刷新和服务重启后会丢失。

## Decision 3: root 授权文件使用固定系统目录

**Decision**: root 分支不创建用户，固定使用 `/root`，以 root 所有权和 `0700/0600` 权限创建 `.ssh/authorized_keys`。普通用户分支继续解析账户主目录并保持原行为。

**Rationale**: root 是系统既有账户，创建或重命名它没有意义。固定系统目录减少解析失败面，并让引导脚本在每次容器启动时幂等重写相同授权文件。

**Alternatives considered**:

- 对 root 也调用 `useradd`：账户已存在，会失败且没有价值。
- 使用可配置 root 主目录：扩大输入和路径注入面。
- 启动后再通过额外命令写公钥：增加竞态和新的写操作接口。

## Decision 4: 保持账户可用于公钥，但密码永远不可认证

**Decision**: root 分支把 shadow 密码字段设为 OpenSSH 文档建议的非锁定、不可用于密码认证值 `NP`；同时写入 `PermitRootLogin prohibit-password`、`PasswordAuthentication no`、`KbdInteractiveAuthentication no`、`ChallengeResponseAuthentication no` 和 `PermitEmptyPasswords no`。不询问、保存或显示 root 密码。

**Rationale**: 本机 `sshd(8)` 文档说明锁定账户会在认证方式之前被拒绝，并建议需要保留公钥认证时使用 `NP` 一类非锁定值。`NP` 不是可用密码散列；配合多层 SSH 配置可允许公钥并阻断密码路径。

**Alternatives considered**:

- 保留 Ubuntu 默认的 `!` 锁定字段：可能连公钥也被账户可访问性检查拒绝。
- 设置随机 root 密码：虽然不显示，仍不符合“不设置 root 密码”的用户目标。
- 删除密码字段：依赖空密码安全配置，误配置时风险更高。

## Decision 5: root 选项在 GUI 中默认关闭并锁定用户名

**Decision**: SSH 区域新增复选框。勾选时保存当前普通用户名、把显示与请求身份固定为 `root` 并禁用用户名输入；取消时恢复本次表单保存的普通用户名。关闭 SSH 时 root 选项自动清除并禁用。

**Rationale**: 用户能清楚看到当前登录身份，且不会出现“勾选 root 但提交另一个用户名”的歧义。恢复原值避免反复切换时丢失输入。

**Alternatives considered**:

- 隐藏用户名字段：用户可能看不出最终连接身份。
- 保持用户名可编辑但忽略其值：界面与提交行为不一致。
- 默认启用 root：违反最小权限和现有安全默认值。

## Decision 6: 只做模拟写操作验证

**Decision**: 自动测试覆盖请求解码、双端校验、CLI 参数形状、脚本文本、标签回读和浏览器行为。真实环境只读回读现有服务、版本与容器状态；不把现有 `ubuntu-26.04` 改成 root，也不自动创建新的 root 容器。

**Rationale**: 用户授权开发功能，不等于授权替换现有容器身份或生成新的高权限运行实例。固定执行器和资源测试足以证明代码路径，真实变更需要另行指明目标。

**Alternatives considered**:

- 自动重建现有 SSH 容器：会中断用户连接并改变主机指纹。
- 自动创建后删除测试容器：仍会安装软件、占用端口且清理有失败风险。
- 只检查页面文本：无法证明服务端安全校验和引导脚本。
