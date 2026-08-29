# Quickstart Validation: 容器 CPU 与内存指标

## 1. 自动化测试

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

预期：解析、CPU 差值、内存比例、HTTP 契约、静态资源与既有控制/日志测试全部通过；测试不会修改
真实容器。

## 2. 只读真实 CLI 冒烟测试

```bash
CONTAINER_GUI_LIVE_READONLY=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift test --filter ReadOnlyCLISmokeTests
```

预期：探测 CLI 1.3.1、读取系统、列表和统计 JSON；不执行 start、stop、delete 或 prune。

## 3. 启动临时验证服务

为避免影响已占用 8787 的开发服务，使用 8788：

```bash
CONTAINER_GUI_PORT=8788 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift run ContainerGUI
```

打开 `http://127.0.0.1:8788/`，验证：

1. 运行中容器的内存立即显示“已用 / 上限”和百分比。
2. 首次 CPU 样本显示“采样中”，下一个五秒刷新后显示百分比。
3. CPU 口径允许超过 100%，页面不钳制多核负载。
4. 已停止容器显示“未运行”，不显示先前值。
5. 手动制造统计端点失败时，容器列表和详情仍保持可用，指标显示“暂不可用”。

## 4. API 只读回读

```bash
curl -sS http://127.0.0.1:8788/api/v1/containers/metrics
```

连续读取两次（间隔至少一个刷新周期），首个快照可为 `sampling`，后续连续样本应为 `ready`。
所有命令均为只读验证。
