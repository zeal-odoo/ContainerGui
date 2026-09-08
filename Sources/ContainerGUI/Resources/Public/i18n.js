"use strict";

const ContainerGUII18n = (() => {
  const STORAGE_KEY = "container-gui-language";
  const supportedLanguages = new Set(["zh", "en"]);
  const english = Object.freeze({
    "跳到主要内容": "Skip to main content",
    "工作区导航": "Workspace navigation",
    "主要导航": "Main navigation",
    "本机工作区": "Local workspace",
    "容器": "Containers",
    "名称 / 镜像": "Name / Image",
    "CPU 配置": "CPU allocation",
    "100% 代表分配的全部 CPU 核心。": "100% represents all CPU cores allocated to the container.",
    "点击“创建容器”开始，状态会自动刷新。": "Select “Create container” to get started. Status refreshes automatically.",
    "Container GUI 首页": "Container GUI home",
    "正在读取 GUI 版本…": "Loading GUI version…",
    "正在检查 CLI…": "Checking CLI…",
    "检查更新": "Check for updates",
    "正在检查更新…": "Checking for updates…",
    "发现新版本": "Update available",
    "已有新的稳定版本可供下载。": "A newer stable version is available to download.",
    "当前版本": "Current version",
    "最新版本": "Latest version",
    "将打开官方 GitHub Release 页面；下载和安装 PKG 均由您确认。": "The official GitHub Release page will open. You choose whether to download and install the PKG.",
    "稍后提醒": "Remind me later",
    "前往 GitHub 下载 PKG": "Open GitHub to download the PKG",
    "当前已是最新版本": "Container GUI is up to date",
    "暂时无法检查更新，请稍后重试。": "Unable to check for updates right now. Try again later.",
    "本机容器控制台": "Local container console",
    "容器运行状态": "Container runtime status",
    "所有状态直接读取 Apple container CLI，不保存影子副本。": "All status is read directly from Apple container CLI; no shadow copy is stored.",
    "正在连接": "Connecting",
    "等待系统状态": "Waiting for system status",
    "容器统计": "Container statistics",
    "容器合计 · 占主机": "All containers · Host usage",
    "CPU 占主机": "Host CPU share",
    "内存占主机": "Host memory share",
    "容器 CPU 占主机比例": "Container CPU share of host capacity",
    "容器内存占主机比例": "Container memory share of host capacity",
    "等待完整 CPU 样本": "Waiting for a complete CPU sample",
    "等待完整内存样本": "Waiting for a complete memory sample",
    "统计不完整，等待下一次刷新": "Incomplete sample; waiting for next refresh",
    "每 5 秒刷新所有容器的合计，不受筛选影响。按容器内用量计算，不含虚拟机及系统服务开销。": "All containers, refreshed every 5 seconds regardless of filters. Based on in-container usage; excludes VM and system-service overhead.",
    "整机 ANE": "Host ANE",
    "估算功耗": "Estimated power",
    "计算使用率": "Compute utilization",
    "不可用": "Unavailable",
    "功耗不是计算使用率": "Power is not compute utilization",
    "包含本机所有应用，非 Container GUI 专属。容器页可见时每 5 秒刷新，不受 AI 开关影响。": "Includes all apps on this Mac, not just Container GUI. Refreshes every 5 seconds while the container view is visible, independently of the AI switch.",
    "等待两次有效采样": "Waiting for two valid samples",
    "采样窗口 —": "Sample window —",
    "此系统暂不支持 ANE 功耗读取": "ANE power readings are not supported on this system",
    "暂时无法读取 ANE 指标": "Unable to read ANE metrics right now",
    "ANE 样本无效，等待重新采样": "Invalid ANE sample; waiting for a new sample",
    "全部": "Total",
    "运行中": "Running",
    "已停止": "Stopped",
    "最后刷新": "Last refreshed",
    "容器管理区域": "Container management",
    "容器概览": "Container overview",
    "筛选容器": "Filter containers",
    "搜索名称、镜像或 ID": "Search name, image, or ID",
    "正在读取容器…": "Loading containers…",
    "还没有容器": "No containers yet",
    "可继续使用官方 CLI 创建容器，然后在这里刷新。": "You can create a container with the official CLI, then refresh it here.",
    "名称": "Name",
    "镜像": "Image",
    "状态": "Status",
    "内存": "Memory",
    "存储": "Storage",
    "地址": "Address",
    "操作": "Actions",
    "选择一个容器": "Select a container",
    "查看权威详情、受控操作和日志。": "View authoritative details, controlled actions, and logs.",
    "容器详情": "Container details",
    "关闭详情": "Close details",
    "SSH 连接": "SSH connection",
    "正在读取": "Loading",
    "复制命令": "Copy command",
    "首次启动会安装 SSH；显示“可连接”后再使用对应私钥登录。": "SSH is installed on first start. Wait for “Ready” before signing in with the matching private key.",
    "日志": "Logs",
    "最近日志": "Recent logs",
    "实时跟随": "Follow live",
    "尚未读取": "Not loaded",
    "容器日志输出": "Container log output",
    "日志将在这里显示": "Logs will appear here",
    "本地 AI 分析": "Local AI analysis",
    "分析历史": "Analysis history",
    "分析历史分页": "Analysis history pagination",
    "自动保存结果和脱敏日志；关闭 AI 后仍可查看。所有容器合计保留最近 1,000 条，超出清理最旧记录。脱敏可能遗漏，请在导出分享前检查。": "Results and redacted logs are saved locally and remain available with AI off. The latest 1,000 records across all containers are kept; older records are removed. Redaction may miss secrets; review before exporting or sharing.",
    "刷新历史": "Refresh history",
    "正在读取分析历史…": "Loading analysis history…",
    "暂无分析历史。完成 AI 分析后会自动保存。": "No analysis history yet. Completed AI analyses will be saved automatically.",
    "第 {page} / {pages} 页 · 共 {total} 条": "Page {page} of {pages} · {total} records",
    "导出 JSON": "Export JSON",
    "删除记录": "Delete record",
    "日志采样：{time}": "Logs observed at: {time}",
    "删除 {container} 在 {time} 的分析记录？此操作无法撤销。": "Delete the analysis for {container} at {time}? This cannot be undone.",
    "无法读取分析历史，请检查本机历史目录后重试。": "Analysis history could not be loaded. Check the local history directory and retry.",
    "删除记录失败，请刷新历史确认后重试。": "The record could not be deleted. Refresh history to check its status before retrying.",
    "分析结果未能保存到本机历史，请检查目录权限或磁盘空间；当前结果仍可查看。": "The analysis could not be saved to local history. Check directory permissions or disk space; the current result is still available.",
    "模型已安装": "Model installed",
    "按需下载": "Download on demand",
    "启用 AI": "Enable AI",
    "关闭 AI": "Turn off AI",
    "已关闭 · 模型未运行": "Off · Model is not running",
    "正在下载模型…": "Downloading model…",
    "正在加载模型…": "Loading model…",
    "已就绪 · 新日志将自动分析": "Ready · New logs are analysed automatically",
    "正在分析最近日志…": "Analysing recent logs…",
    "正在关闭 · 等待确认模型退出…": "Stopping · Waiting for verified model exit…",
    "AI 暂不可用": "AI is unavailable",
    "正在读取 AI 状态…": "Checking AI status…",
    "请确认首次模型下载": "Confirm the first model download",
    "AI 当前用于 {container}。关闭后可为此容器启用。": "AI is currently analysing {container}. Turn it off before enabling it for this container.",
    "正在核对下载大小…": "Checking download size…",
    "首次使用需下载 {size}（{bytes} 字节）。模型文件保留在本机。": "First use requires a {size} download ({bytes} bytes). Model files stay on this Mac.",
    "确认下载并启用": "Download and enable",
    "AI 模型下载进度": "AI model download progress",
    "日志仅在本机分析，不上传；会遮盖可识别的秘密，但可能有遗漏。": "Logs are analysed locally and are not uploaded. Recognisable secrets are redacted, but some may be missed.",
    "资源与兼容性": "Resources and compatibility",
    "关闭会结束模型进程，保留下载文件。系统缓存可能稍后回收。计算设备配置为 CPU + ANE；实际 ANE 执行及未测试机型尚未验证。": "Turning AI off ends its process and keeps downloaded files. System caches may be reclaimed later. Compute is configured for CPU + ANE; actual ANE execution and untested Macs are not verified.",
    "AI 的判断可能有误，请结合日志核实；建议不会自动执行。": "AI may be wrong; verify its conclusions against the logs. Suggestions are never executed automatically.",
    "本次分析的日志（已脱敏）": "Analysed logs (redacted)",
    "分析时间：{time}": "Analysed at: {time}",
    "另一项 AI 操作正在进行，请核对当前状态。": "Another AI operation is in progress. Check the current status.",
    "本地 AI 暂不可用，请稍后重试。": "Local AI is unavailable. Try again later.",
    "AI 请求失败，请重试。": "The AI request failed. Try again.",
    "关闭失败，尚未确认释放；请重试关闭。": "Shutdown failed; release is not verified. Try turning AI off again.",
    "暂无最近日志可供分析。": "There are no recent logs to analyse.",
    "可用内存不足，请关闭部分应用后重试。": "Not enough available memory. Close some apps and try again.",
    "模型正在处理另一项请求，请稍后重试。": "The model is handling another request. Try again shortly.",
    "模型返回了无效响应，请关闭 AI 后重试。": "The model returned an invalid response. Turn AI off and try again.",
    "模型进程已退出，请重新启用 AI。": "The model process exited. Enable AI again to retry.",
    "模型响应超时，请关闭 AI 后重试。": "The model response timed out. Turn AI off and try again.",
    "模型运行失败，请关闭 AI 后重试。": "The model failed to run. Turn AI off and try again.",
    "模型文件不可用，请检查安装状态。": "Model files are unavailable. Check the installation status.",
    "此模型与当前运行环境不兼容。": "This model is incompatible with the current runtime.",
    "未能生成有效分析，请稍后重试。": "No valid analysis was generated. Try again later.",
    "模型分析超时，请稍后重试。": "Model analysis timed out. Try again later.",
    "模型分词文件无效，请重新下载。": "The model tokenizer is invalid. Download the model again.",
    "无法分析日志，请检查容器状态后重试。": "Logs could not be analysed. Check the container status and try again.",
    "AI 操作已取消。": "The AI operation was cancelled.",
    "模型清单无效，请更新应用后重试。": "The model manifest is invalid. Update the app and try again.",
    "模型目录不符合安全要求，请检查本机模型目录。": "The model directory failed safety checks. Check the local model directory.",
    "磁盘空间不足，无法下载模型。": "There is not enough disk space to download the model.",
    "模型尚未安装，请确认下载后重试。": "The model is not installed. Confirm its download and try again.",
    "模型文件校验失败，请重新下载。": "Model verification failed. Download the model again.",
    "模型下载失败，请检查网络后重试。": "The model download failed. Check your connection and try again.",
    "重试": "Retry",
    "原始详情（已脱敏）": "Raw details (redacted)",
    "本机镜像": "Local images",
    "收起本机镜像": "Collapse local images",
    "展开本机镜像": "Expand local images",
    "创建容器": "Create container",
    "拉取镜像": "Pull image",
    "等待镜像拉取": "Waiting for image pull",
    "等待进度": "Waiting for progress",
    "镜像拉取进度": "Image pull progress",
    "正在读取镜像…": "Loading images…",
    "还没有本机镜像": "No local images yet",
    "可点击“拉取镜像”准备创建容器所需的镜像。": "Pull an image to prepare it for container creation.",
    "摘要": "Digest",
    "平台": "Platform",
    "大小": "Size",
    "读取时间": "Observed at",
    "本机镜像分页": "Local image pagination",
    "上一页": "Previous",
    "下一页": "Next",
    "搜索远程镜像": "Search remote images",
    "只读浏览，不会自动拉取": "Read-only browsing; images are not pulled automatically",
    "Docker Hub 搜索关键词": "Docker Hub search term",
    "例如 postgres": "For example, postgres",
    "搜索镜像": "Search images",
    "Docker Hub 按关键词搜索公开仓库；仓库与标签均每页显示 10 条。": "Search public Docker Hub repositories by keyword; repositories and tags show 10 items per page.",
    "仓库结果": "Repository results",
    "尚未搜索": "Not searched",
    "输入条件后点击“搜索镜像”。": "Enter a search term, then select “Search images”.",
    "仓库结果分页": "Repository result pagination",
    "镜像标签": "Image tags",
    "尚未选择仓库": "No repository selected",
    "选择一个仓库查看可用标签。": "Select a repository to view its available tags.",
    "镜像标签分页": "Image tag pagination",
    "填写常用参数。端口只会绑定到本机 127.0.0.1，默认创建后不启动。": "Enter common settings. Ports bind only to local 127.0.0.1, and the container is not started by default.",
    "容器名称": "Container name",
    "CPU 数（可选）": "CPU count (optional)",
    "内存 MiB（可选）": "Memory MiB (optional)",
    "端口映射（每行一项）": "Port mappings (one per line)",
    "格式为“主机端口:容器端口[/tcp|udp]”，主机地址固定为 127.0.0.1；主机端口范围为 1024...65535。": "Format: host-port:container-port[/tcp|udp]. The host address is fixed to 127.0.0.1 and host ports must be 1024...65535.",
    "目录映射": "Directory mapping",
    "本机共享目录": "Local shared directory",
    "用于本机与容器之间读写和传输文件；留空则不挂载。": "Read, write, and transfer files between the Mac and container; leave blank to disable the mount.",
    "本机目录（可选）": "Local directory (optional)",
    "请填写运行本服务的 Mac 上已存在目录的完整绝对路径。": "Enter the full absolute path of an existing directory on the Mac running this service.",
    "容器目录": "Container directory",
    "Odoo 自定义模块目录": "Odoo custom add-ons directory",
    "本机目录会读写映射到 Odoo 官方自定义模块目录 /mnt/extra-addons。": "The local directory is mounted read-write at the official Odoo custom add-ons path /mnt/extra-addons.",
    "Odoo 数据库连接": "Odoo database connection",
    "仅配置数据库地址与端口；数据库用户和密码仍可在下方环境变量中填写。": "Configure only the database address and port. Set the database user and password in the environment variables below.",
    "数据库地址": "Database address",
    "数据库端口": "Database port",
    "SSH 快速配置": "Quick SSH setup",
    "启用 SSH（仅公钥登录）": "Enable SSH (public key only)",
    "自动安装并启动 SSH，只绑定到 127.0.0.1；密码登录始终禁用。容器重启后会自动恢复。": "Install and start SSH automatically, bound only to 127.0.0.1. Password login stays disabled and SSH returns after container restarts.",
    "使用 root 登录（仅公钥）": "Sign in as root (public key only)",
    "高权限选项：公钥将授权给 root，密码登录保持禁用；未勾选时继续创建普通用户。": "Privileged option: authorize the key for root while password login stays disabled. Leave unchecked to create a regular user.",
    "宿主机端口": "Host port",
    "登录用户名": "Login username",
    "SSH 公钥": "SSH public key",
    "只粘贴 `.pub` 公钥；私钥不会也不应发送到本工具。": "Paste only a `.pub` public key. A private key is never required and must not be sent to this tool.",
    "或选择公钥文件": "Or choose a public key file",
    "读取结果会显示在上方，提交前仍可检查和修改。": "The result appears above and can be reviewed or edited before submission.",
    "生成 SSH 密钥对": "Generate SSH key pair",
    "密钥对只在当前浏览器生成；公钥自动填入，私钥只下载一次且不会上传或保存。": "The key pair is generated only in this browser. The public key is filled in automatically; the private key is downloaded once and is never uploaded or stored.",
    "环境变量（每行一项）": "Environment variables (one per line)",
    "POSTGRES_PASSWORD=仅用于本次请求": "POSTGRES_PASSWORD=used-only-for-this-request",
    "格式为 KEY=value；值只发送给 CLI，不进入操作摘要或页面回读。": "Format: KEY=value. Values are sent only to the CLI and are excluded from operation summaries and page readback.",
    "进程参数（每行一个参数）": "Process arguments (one per line)",
    "保持容器运行": "Keep container running",
    "适用于 Ubuntu 等没有常驻进程的镜像；GUI 固定使用 /bin/bash -lc 和 exec sleep infinity。启用 SSH 时无需选择。": "For images such as Ubuntu without a long-running process. The GUI uses /bin/bash -lc and exec sleep infinity. This is not needed when SSH is enabled.",
    "创建并验证后启动容器": "Start container after creation and verification",
    "取消": "Cancel",
    "拉取容器镜像": "Pull container image",
    "镜像会由 Apple container CLI 拉取，并在完成后重新读取详情验证。": "Apple container CLI pulls the image and reads it back for verification when complete.",
    "镜像仓库": "Image registry",
    "完整地址 / 自动识别": "Full address / auto-detect",
    "Docker Hub 可输入 postgres:latest；其他仓库请使用完整镜像地址。": "For Docker Hub, enter postgres:latest. Use a full image address for other registries.",
    "镜像引用": "Image reference",
    "postgres:latest 或 registry.example.com/owner/image:tag": "postgres:latest or registry.example.com/owner/image:tag",
    "目标架构（可选）": "Target architecture (optional)",
    "使用运行时默认平台": "Use runtime default platform",
    "开始拉取": "Start pull",
    "确认操作": "Confirm action",
    "确认目标": "Confirm target",
    "确认": "Confirm",
    "已创建": "Created",
    "正在停止": "Stopping",
    "异常": "Error",
    "未知": "Unknown",
    "系统正常": "System healthy",
    "启动 container": "Start container service",
    "正在启动 container…": "Starting container service…",
    "只启动系统服务，不会自动启动已停止的容器。": "Starts the system service only; stopped containers are not started automatically.",
    "请求必须为空 JSON 对象": "The request must be an empty JSON object",
    "服务已停止": "Service stopped",
    "服务未注册": "Service not registered",
    "服务异常": "Service degraded",
    "服务不可用": "Service unavailable",
    "状态未知": "Status unknown",
    "GUI 版本未知": "GUI version unknown",
    "未知版本": "Unknown version",
    "CLI 不可用": "CLI unavailable",
    "未返回服务版本": "No service version returned",
    "查看详情": "View details",
    "收起详情": "Collapse details",
    "没有符合筛选条件的容器。": "No containers match the filter.",
    "未运行": "Not running",
    "读取中": "Loading",
    "暂不可用": "Temporarily unavailable",
    "采样中": "Sampling",
    "等待下一样本": "Waiting for the next sample",
    "比例未知": "Percentage unknown",
    "删除镜像": "Delete image",
    "正在核对": "Checking",
    "系统镜像": "System image",
    "正在使用": "In use",
    "查看标签": "View tags",
    "官方镜像": "Official image",
    "选择标签": "Select tag",
    "没有找到匹配的远程镜像。": "No matching remote images found.",
    "该仓库当前没有可选择的标签。": "This repository currently has no selectable tags.",
    "正在搜索远程镜像…": "Searching remote images…",
    "正在读取镜像标签…": "Loading image tags…",
    "请输入 Docker Hub 搜索关键词。": "Enter a Docker Hub search term.",
    "连接失败": "Connection failed",
    "状态已从 CLI 刷新": "Status refreshed from the CLI",
    "正在读取…": "Loading…",
    "详情读取失败": "Failed to load details",
    "未配置": "Not configured",
    "容器已停止": "Container stopped",
    "初始化中": "Initializing",
    "可连接": "Ready",
    "启动失败": "Startup failed",
    "状态读取失败": "Failed to load status",
    "SSH 连接命令已复制": "SSH command copied",
    "无法自动复制，请手动选择命令": "Automatic copy failed; select the command manually",
    "完整标识": "Full identifier",
    "原始状态": "Raw status",
    "CPU 使用率": "CPU usage",
    "内存使用": "Memory usage",
    "根文件系统": "Root filesystem",
    "创建时间": "Created at",
    "重启容器": "Restart container",
    "正常停止": "Stop gracefully",
    "启动容器": "Start container",
    "当前状态不可操作": "No action available for the current state",
    "删除容器": "Delete container",
    "已停止跟随": "Live follow stopped",
    "确认启动": "Confirm start",
    "正常停止容器": "Stop container gracefully",
    "将发送正常停止请求并等待最多 10 秒，不会使用 --all 或 --force。": "Send a graceful stop request and wait up to 10 seconds. Neither --all nor --force is used.",
    "确认停止": "Confirm stop",
    "确认重启": "Confirm restart",
    "删除后无法恢复；只会删除当前已停止的精确目标，不会使用 --all 或 --force。": "Deletion cannot be undone. Only the exact stopped target is deleted; neither --all nor --force is used.",
    "确认删除": "Confirm deletion",
    "删除后无法恢复；只会删除当前精确镜像，不会使用 --all 或 --force。": "Deletion cannot be undone. Only the exact image is deleted; neither --all nor --force is used.",
    "确认删除镜像": "Confirm image deletion",
    "正在提交镜像删除…": "Submitting image deletion…",
    "正在提交操作…": "Submitting operation…",
    "已排队": "Queued",
    "正在执行 CLI 命令": "Running CLI command",
    "正在重新读取状态": "Reading status back",
    "已验证完成": "Verified",
    "操作失败": "Operation failed",
    "操作已取消": "Operation cancelled",
    "操作已完成并通过 CLI 回读验证": "Operation completed and passed CLI readback verification",
    "操作仍在进行，请稍后刷新查看。": "The operation is still running. Check again shortly.",
    "正在下载镜像层": "Downloading image layers",
    "正在解压镜像": "Unpacking image",
    "正在验证本机镜像": "Verifying local image",
    "镜像拉取完成": "Image pull complete",
    "镜像拉取失败": "Image pull failed",
    "镜像拉取已取消": "Image pull cancelled",
    "等待开始拉取": "Waiting to start pull",
    "正在准备镜像拉取": "Preparing image pull",
    "镜像引用格式无效": "Invalid image reference format",
    "镜像仓库无效": "Invalid image registry",
    "镜像地址与所选仓库不一致": "The image address does not match the selected registry",
    "目标架构必须为 Linux ARM64 或 AMD64": "Target architecture must be Linux ARM64 or AMD64",
    "请修正标出的字段。": "Correct the highlighted fields.",
    "正在提交拉取操作…": "Submitting image pull…",
    "镜像拉取已排队": "Image pull queued",
    "端口格式必须为 主机端口:容器端口[/tcp|udp]": "Port format must be host-port:container-port[/tcp|udp]",
    "主机端口必须使用 1024...65535；1024 以下需要 root 权限": "Host ports must be 1024...65535; ports below 1024 require root privileges",
    "端口必须在 1...65535 之间": "Ports must be between 1 and 65535",
    "主机端口不能重复": "Host ports must be unique",
    "环境变量格式必须为 KEY=value": "Environment variable format must be KEY=value",
    "环境变量名称格式无效": "Invalid environment variable name",
    "环境变量名称不能重复": "Environment variable names must be unique",
    "SSH 公钥必须是单行且不超过 4096 个字符": "The SSH public key must be one line and no longer than 4096 characters",
    "SSH 公钥格式无效，请粘贴单行公钥或选择 .pub 文件": "Invalid SSH public key. Paste one public-key line or select a .pub file",
    "SSH 公钥的 Base64 内容无效": "The SSH public key contains invalid Base64 data",
    "公钥文件过大": "The public key file is too large",
    "无法读取公钥文件": "Unable to read the public key file",
    "正在浏览器中生成密钥…": "Generating a key in the browser…",
    "密钥生成失败": "Key generation failed",
    "容器名称格式无效": "Invalid container name",
    "CPU 必须为 1...1024 的整数": "CPU count must be an integer from 1 to 1024",
    "内存必须为 1...1048576 MiB 的整数": "Memory must be an integer from 1 to 1048576 MiB",
    "进程参数数量或内容无效": "Invalid process argument count or content",
    "本机目录必须是安全的非根绝对路径": "The local directory must be a safe, non-root absolute path",
    "本机目录不存在或不是目录": "The local directory does not exist or is not a directory",
    "容器目录必须是安全的非根绝对路径": "The container directory must be a safe, non-root absolute path",
    "Odoo 自定义模块目录必须为 /mnt/extra-addons": "The Odoo custom add-ons directory must be /mnt/extra-addons",
    "数据库配置只适用于 Docker Hub 官方 Odoo 镜像": "Database settings are available only for the official Docker Hub Odoo image",
    "数据库地址格式无效": "Invalid database address",
    "数据库端口必须在 1...65535 之间": "The database port must be between 1 and 65535",
    "已使用 Odoo 数据库字段，环境变量不能重复定义 HOST 或 PORT": "HOST or PORT cannot be repeated in environment variables when Odoo database fields are used",
    "SSH 主机端口必须在 1024...65535 之间": "The SSH host port must be between 1024 and 65535",
    "SSH 主机端口不能与其他端口映射重复": "The SSH host port must not duplicate another port mapping",
    "选择 root 登录时，SSH 用户名必须为 root": "The SSH username must be root when root login is selected",
    "SSH 用户名必须为 1...32 位小写安全名称；root 需使用专用选项": "The SSH username must be a safe lowercase name of 1...32 characters; use the dedicated option for root",
    "环境变量使用了 SSH 快速配置的保留名称": "An environment variable uses a name reserved by quick SSH setup",
    "启用 SSH 时不能同时填写进程参数": "Process arguments cannot be set when SSH is enabled",
    "启用 SSH 时必须创建并启动容器": "A container with SSH enabled must be created and started",
    "正在提交创建操作…": "Submitting container creation…",
    "容器创建已排队": "Container creation queued",
    "该容器已有操作进行中，请等待完成。": "An operation is already running for this container. Wait for it to finish.",
    "目标状态已变化，请刷新后重试。": "The target state changed. Refresh and try again.",
    "CLI 执行超时，页面将保留当前状态。": "CLI execution timed out. The page will retain its current state.",
    "镜像平台请求过于频繁，请稍后重试。": "The registry is receiving too many requests. Try again later.",
    "镜像平台当前不可用，本机镜像不受影响。": "The registry is currently unavailable. Local images are unaffected.",
    "正在读取最近日志…": "Loading recent logs…",
    "最近日志（已截断）": "Recent logs (truncated)",
    "停止跟随": "Stop following",
    "正在重新连接实时日志…": "Reconnecting to live logs…",
    "正在连接实时日志…": "Connecting to live logs…",
    "正在实时跟随": "Following live logs",
    "实时日志连接中断，准备重连…": "Live log connection interrupted; preparing to reconnect…",
    "实时日志已断开，可点击“重新连接”。": "Live logs are disconnected. Select “Reconnect” to continue.",
    "重新连接": "Reconnect",
    "尚未跟随": "Not following",
    "［较早日志已从页面移除］": "[Older logs were removed from the page]",
    "当前浏览器不支持本地密钥生成": "This browser does not support local key generation",
    "无法导出 SSH 公钥": "Unable to export the SSH public key",
    "请求内容格式无效": "Invalid request body",
    "请求内容未通过校验。": "The request did not pass validation.",
    "容器命令执行失败。": "The container command failed.",
    "容器系统服务当前不可用。": "The container system service is currently unavailable.",
    "未找到指定镜像。": "The requested image was not found.",
    "Apple container 系统镜像不能删除。": "Apple container system images cannot be deleted.",
    "镜像仍被容器引用，请先删除相关容器。": "The image is still referenced by a container. Delete the related container first.",
    "发生内部错误。": "An internal error occurred."
  });

  const chinese = Object.freeze(Object.fromEntries(
    Object.entries(english).map(([source, target]) => [target, source])
  ));

  const patterns = Object.freeze([
    [/^已用 ([\d.]+) 核 \/ 主机 (\d+) 核$/, (_, used, total) => `${used} cores used / ${total} host cores`],
    [/^已更新 (.+)$/, (_, time) => `Updated ${time}`],
    [/^采样窗口 ([\d.]+) 秒$/, (_, seconds) => `Sample window ${seconds} s`],
    [/^当前版本 (.+) · 最新版本 (.+)$/, (_, current, latest) => `Current ${current} · Latest ${latest}`],
    [/^查看 (.+) 的详情$/, (_, name) => `View details for ${name}`],
    [/^收起 (.+) 的详情$/, (_, name) => `Collapse details for ${name}`],
    [/^删除镜像 (.+)$/, (_, name) => `Delete image ${name}`],
    [/^查看 (.+) 的标签$/, (_, name) => `View tags for ${name}`],
    [/^选择镜像标签 (.+)$/, (_, name) => `Select image tag ${name}`],
    [/^第 (\d+) 页$/, (_, page) => `Page ${page}`],
    [/^本页 (\d+) 条 · 共 (\d+) 条$/, (_, page, total) => `${page} on this page · ${total} total`],
    [/^本页 (\d+) 条$/, (_, page) => `${page} on this page`],
    [/^100% = (\d+) 核$/, (_, count) => `100% = ${count} ${count === "1" ? "core" : "cores"}`],
    [/^拉取 ([\d,.]+)$/, (_, count) => `${count} pulls`],
    [/^更新 (.+)$/, (_, time) => `Updated ${time}`],
    [/^摘要 (.+)$/, (_, digest) => `Digest ${digest}`],
    [/^请求失败（HTTP (\d+)）$/, (_, status) => `Request failed (HTTP ${status})`],
    [/^已选择标签 (.+)；确认后再开始拉取。$/, (_, tag) => `Tag ${tag} selected. Confirm before starting the pull.`],
    [/^公钥已填入，私钥已下载为 (.+)；使用前请执行 chmod 600。$/, (_, filename) => `The public key is filled in and the private key was downloaded as ${filename}. Run chmod 600 before use.`],
    [/^将启动“(.+)”，完成后会重新读取 CLI 状态。$/, (_, name) => `Start “${name}” and read the CLI state back when complete.`],
    [/^将正常停止“(.+)”并重新启动，期间服务会短暂中断。$/, (_, name) => `Gracefully stop and restart “${name}”. Its service will be briefly interrupted.`],
    [/^读取于 (.+)$/, (_, time) => `Loaded at ${time}`],
    [/^警告：(.+)$/, (_, message) => `Warning: ${message}`],
    [/^日志流已结束（退出码 (.+)）$/, (_, code) => `The log stream ended (exit code ${code})`],
    [/^已丢弃 (\d+) 个日志分片$/, (_, count) => `${count} log chunks were dropped`]
  ]);

  const originalText = new WeakMap();
  const originalAttributes = new WeakMap();
  let currentLanguage = "zh";

  function preferredLanguage(browserLanguage, savedLanguage) {
    if (supportedLanguages.has(savedLanguage)) return savedLanguage;
    return String(browserLanguage || "").toLowerCase().startsWith("zh") ? "zh" : "en";
  }

  function translateCore(value, language) {
    if (language === "zh") return chinese[value] || value;
    if (english[value]) return english[value];
    const coreCount = value.match(/^(\d+) 核$/);
    if (coreCount) return `${coreCount[1]} ${coreCount[1] === "1" ? "core" : "cores"}`;
    const problemWithCode = value.match(/^(.+)（([A-Z0-9_]+)）$/);
    if (problemWithCode) return `${translateCore(problemWithCode[1], "en")} (${problemWithCode[2]})`;
    for (const [pattern, replacement] of patterns) {
      const match = value.match(pattern);
      if (match) return replacement(...match);
    }
    return value.replace(/100% = (\d+) 核/g, (_, count) =>
      `100% = ${count} ${count === "1" ? "core" : "cores"}`
    );
  }

  function translate(value, language = currentLanguage) {
    if (typeof value !== "string" || !supportedLanguages.has(language)) return value;
    const match = value.match(/^(\s*)([\s\S]*?)(\s*)$/);
    if (!match || !match[2]) return value;
    return `${match[1]}${translateCore(match[2], language)}${match[3]}`;
  }

  function shouldSkipText(node) {
    return Boolean(node.parentElement?.closest("script, style, code, pre, textarea"));
  }

  function canonicalSource(current, source) {
    if (source === undefined) return current;
    return current === source || current === translate(source, "en") ? source : current;
  }

  function applyText(node) {
    if (shouldSkipText(node)) return;
    const current = node.nodeValue || "";
    let source = originalText.get(node);
    source = canonicalSource(current, source);
    originalText.set(node, source);
    const target = currentLanguage === "zh" ? source : translate(source, "en");
    if (current !== target) node.nodeValue = target;
  }

  function applyAttributes(element) {
    if (!(element instanceof Element)) return;
    const names = ["aria-label", "title", "placeholder", "data-empty-label"];
    let originals = originalAttributes.get(element);
    if (!originals) {
      originals = new Map();
      originalAttributes.set(element, originals);
    }
    for (const name of names) {
      if (!element.hasAttribute(name)) continue;
      const current = element.getAttribute(name) || "";
      let source = originals.get(name);
      source = canonicalSource(current, source);
      originals.set(name, source);
      const target = currentLanguage === "zh" ? source : translate(source, "en");
      if (current !== target) element.setAttribute(name, target);
    }
  }

  function apply(root = document) {
    if (typeof document === "undefined" || !root) return;
    if (root.nodeType === Node.TEXT_NODE) {
      applyText(root);
      return;
    }
    if (root.nodeType === Node.ELEMENT_NODE) applyAttributes(root);
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT);
    let node = walker.nextNode();
    while (node) {
      if (node.nodeType === Node.TEXT_NODE) applyText(node);
      else applyAttributes(node);
      node = walker.nextNode();
    }
  }

  function updateSwitch() {
    if (typeof document === "undefined") return;
    for (const button of document.querySelectorAll("#languageSwitch [data-language]")) {
      button.setAttribute("aria-pressed", String(button.dataset.language === currentLanguage));
    }
  }

  function setLanguage(language, { persist = true, announce = true } = {}) {
    if (!supportedLanguages.has(language)) return false;
    currentLanguage = language;
    if (typeof document !== "undefined") {
      document.documentElement.lang = language === "zh" ? "zh-Hans" : "en";
      updateSwitch();
      apply(document.body);
      if (persist) {
        try { globalThis.localStorage?.setItem(STORAGE_KEY, language); } catch { /* Storage may be disabled. */ }
      }
      if (announce) document.dispatchEvent(new CustomEvent("container-gui-language-change", { detail: { language } }));
    }
    return true;
  }

  function initialize() {
    let saved = null;
    try { saved = globalThis.localStorage?.getItem(STORAGE_KEY) || null; } catch { /* Storage may be disabled. */ }
    const language = preferredLanguage(globalThis.navigator?.language, saved);
    for (const button of document.querySelectorAll("#languageSwitch [data-language]")) {
      button.addEventListener("click", () => setLanguage(button.dataset.language));
    }
    setLanguage(language, { persist: false, announce: false });
    new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "characterData") applyText(mutation.target);
        else if (mutation.type === "attributes") applyAttributes(mutation.target);
        else for (const node of mutation.addedNodes) apply(node);
      }
    }).observe(document.body, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: ["aria-label", "title", "placeholder", "data-empty-label"]
    });
  }

  if (typeof document !== "undefined") initialize();

  return Object.freeze({
    apply,
    canonicalSource,
    language: () => currentLanguage,
    locale: () => currentLanguage === "zh" ? "zh-Hans" : "en",
    preferredLanguage,
    setLanguage,
    translate
  });
})();

globalThis.ContainerGUII18n = ContainerGUII18n;
