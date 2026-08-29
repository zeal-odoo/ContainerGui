# Container GUI

面向 Apple `container` CLI 的轻量本机 Web 管理界面。Swift 服务仅监听
`127.0.0.1`，浏览器用于查看容器状态、详情、日志以及执行经过约束的启停操作。

> 当前状态：开发中，不用于生产授权。默认测试不会修改真实容器。

## 环境要求

- Apple Silicon Mac，macOS 26
- Swift 6.1 或更高版本
- Apple `container` CLI 1.3.1（首个验证基线）

## 构建与测试

```bash
swift package resolve
swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

当前机器的独立 Command Line Tools 不含 XCTest；测试命令因此显式使用完整 Xcode。

## 本机运行

```bash
swift run ContainerGUI
open http://127.0.0.1:8787
```

端口可通过 `CONTAINER_GUI_PORT` 调整，但监听地址固定为 `127.0.0.1`。第一版
不允许局域网或互联网访问，也不提供任意 CLI/shell 命令入口。

## 验证边界

- 普通 `swift test` 只使用固定夹具和假命令执行器。
- 设置 `CONTAINER_GUI_LIVE_READONLY=1` 后，可运行真实 CLI 只读兼容性测试。
- 真实启动、停止或其他写操作必须针对明确的可丢弃容器另行授权。
- 当前 MVP 包含列表、详情、安全启停、操作回读、最近日志和 SSE 实时日志；创建和删除尚未实现。

设计与验收入口见 [功能规格](specs/001-container-web-gui/spec.md) 和
[快速验证指南](specs/001-container-web-gui/quickstart.md)。
