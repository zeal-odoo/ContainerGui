# Quickstart: SSH 快速配置

## Safety boundary

- 默认自动化不得创建、启动、停止或删除真实容器，也不得占用用户指定的 SSH 端口。
- 不读取或上传私钥；测试公钥必须为固定无效用途夹具。
- 真实 CLI 验证仅执行版本、系统状态、容器列表和详情等只读命令。
- 真实 SSH 容器验收必须由用户另行明确授权具体名称、镜像、端口和公钥。

## Prerequisites

```bash
cd /path/to/ContainerGui
/usr/local/bin/container --version
/usr/local/bin/container system status --format json
```

预期兼容基线为 Apple Container CLI 1.3.1。

## Automated verification

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

必须验证：

1. 合法 SSH 请求通过，非法端口、root/非法用户名、无效公钥、保留环境变量、进程参数冲突和未自动启动在 CLI 前失败。
2. SSH 创建命令只增加固定回环 `22/tcp` 发布、固定标签、固定入口点、固定脚本和两个保留环境参数。
3. 用户名、公钥和端口不插入脚本文本，完整公钥不出现在安全摘要、Operation 或脱敏详情。
4. CLI 1.3.1 SSH 夹具能解析端口与用户名；破损标签不会产生 SSH 元数据或端口探测。
5. 已配置运行中容器只有在替换检查器返回有效横幅时为 `ready`；停止、初始化、错误和未配置状态分别正确。
6. 页面启用 SSH 后显示默认 2222/dev、公钥粘贴和 `.pub` 文件选择，自动启用创建后启动并禁用进程参数。
7. 页面逐字段校验端口冲突、用户名和公钥；请求对象不包含任意命令字段。
8. 详情显示 SSH 状态、连接命令和复制按钮；未配置容器不显示该区域。
9. 未启用 SSH 的 v2.4.0 创建命令形状和全部现有测试保持不变。
10. 应用版本严格为 v2.5.0。

## Read-only live verification

```bash
CONTAINER_GUI_LIVE_READONLY=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift test --filter ReadOnlyCLISmokeTests
```

该步骤不得调用 `create`、`start`、`stop`、`delete`、`exec` 或镜像拉取。

## Local browser verification

在独立 GUI 端口运行当前构建：

```bash
CONTAINER_GUI_PORT=8788 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift run ContainerGUI
```

打开 `http://127.0.0.1:8788/`，只做非提交检查：

1. 顶栏显示 GUI v2.5.0。
2. 打开“创建容器”，确认“启用 SSH（仅公钥登录）”默认关闭。
3. 启用后默认显示端口 2222、用户名 dev、公钥文本区和 `.pub` 文件选择。
4. 启用后“创建并验证后启动容器”自动勾选且不可取消，进程参数清空并禁用。
5. 输入低位/越界/与普通映射重复的端口、root 用户或非法公钥时，显示相应中文字段错误且不发出 POST。
6. 取消对话框，不点击真实“创建容器”提交。
7. 现有未配置 SSH 的容器详情不显示 SSH 连接区域。

## Mutation acceptance with explicit authorization only

用户另行授权后，使用一个明确的新名称、可安装 OpenSSH 的镜像、未占用高位端口和测试公钥验收：

1. 记录创建前容器列表和端口占用。
2. GUI 创建并轮询 Operation；首次安装期间必须显示“初始化中”，不得提前显示“可连接”。
3. 状态变为“可连接”后，使用页面复制的命令和对应私钥登录，确认密码与 root 登录不可用。
4. GUI 正常停止并再次启动同一容器，确认连接命令和服务器主机指纹不变，状态恢复为“可连接”。
5. 读取容器详情和日志，确认完整公钥未回显。
6. 是否删除验收容器由用户单独确认，不自动清理。
