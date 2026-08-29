# Quickstart: root 公钥 SSH 登录

## Safety boundary

- 自动验证不得修改现有 `ubuntu-26.04`、`postgres-odoo-apple` 或其他真实容器。
- root 登录选项默认关闭，且只允许公钥；服务端不接收 root 密码或任何私钥。
- 真实 CLI 验证限于版本、系统状态、容器列表和详情等只读操作。
- 真正创建 root SSH 容器必须由用户另行确认准确名称、镜像、端口和公钥。

## Prerequisites

```bash
cd /path/to/ContainerGui
/usr/local/bin/container --version
/usr/local/bin/container system status --format json
```

预期兼容基线为 Apple Container CLI 1.3.1。

## Automated verification

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcrun swift test
node --test Tests/Frontend/*.mjs
```

必须验证：

1. `loginAsRoot=true` 只与 `username=root` 组合通过；省略或关闭该字段时 `root` 在 CLI 前被拒绝。
2. root 创建命令继续只发布 `127.0.0.1:<port>:22/tcp`，标签和保留环境变量中的有效用户名为 `root`。
3. 固定脚本对 root 使用 `/root/.ssh/authorized_keys`，不创建 root 用户、不设置可用密码，并写入 `PermitRootLogin prohibit-password`。
4. 固定脚本继续禁用密码、键盘交互、挑战响应和空密码认证；普通用户分支继续写入 `PermitRootLogin no`。
5. root 标签能回读为 `ssh -p <port> root@127.0.0.1`，非法用户名标签仍不会触发端口探测。
6. API 接受显式 root 请求并在安全摘要中记录选择，但响应、Operation 和详情不出现完整公钥。
7. 创建表单新增默认关闭的 root 选项；只有 SSH 开启时可选，勾选后用户名固定为 root，取消后恢复原普通用户名。
8. 浏览器提交 root 模式时带 `loginAsRoot: true`，普通模式带 `false` 或采用同等缺省语义，且无密码/私钥字段。
9. 现有普通用户 SSH、非 SSH 创建、保持运行、镜像和容器管理测试全部通过。
10. 应用版本严格为 v2.7.0。

## Read-only live verification

```bash
CONTAINER_GUI_LIVE_READONLY=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/usr/bin/xcrun swift test --filter ReadOnlyCLISmokeTests
```

该步骤不得调用 `create`、`start`、`stop`、`delete`、`exec` 或镜像拉取。

## Local browser verification

在当前构建启动后打开 `http://127.0.0.1:8787/`，只做非提交检查：

1. 顶栏显示 GUI v2.7.0。
2. 打开“创建容器”，确认 SSH 和 root 两个选项都默认关闭。
3. 开启 SSH 后，root 选项可用；普通用户名仍为当前默认值。
4. 勾选 root 后，用户名显示 `root` 且不可编辑，页面提示高权限及密码登录仍禁用。
5. 取消 root 后，普通用户名恢复；关闭 SSH 后 root 自动取消并禁用。
6. 生成密钥只在浏览器填入公钥并下载私钥，不发送创建 POST。
7. 取消对话框，不点击真实“创建容器”。

## Mutation acceptance with explicit authorization only

用户另行授权后，使用明确的新容器名、可安装 OpenSSH 的镜像、未占用高位端口和测试密钥验收：

1. 在 GUI 中启用 SSH 与 root 公钥登录，记录创建前容器列表和端口占用。
2. 创建后等待状态为“可连接”，使用页面命令及对应私钥登录；确认 `id -u` 为 `0`。
3. 尝试密码和键盘交互认证，确认均被拒绝。
4. 正常停止并再次启动同一容器，确认连接命令和服务器主机指纹不变，同一私钥恢复连接。
5. 回读配置、Operation 和详情，确认完整公钥与私钥均未暴露。
6. 是否删除验收容器由用户单独确认，不自动清理。
