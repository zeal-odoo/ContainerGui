# Quickstart Validation: 容器存储容量

## 1. 目标自动化测试

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter ContainerMetricsTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter ContainerMetricsAPITests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter ContainerMetricsAssetTests
node --test Tests/Frontend/*.mjs
```

预期：容量解析、溢出与异常拒绝、固定只读命令、单容器失败隔离、HTTP JSON 以及概览/详情静态资源测试全部通过；测试不执行真实容器写操作。

## 2. 完整回归

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
node --test Tests/Frontend/*.mjs
git diff --check
```

预期：所有既有容器、镜像、SSH、Odoo、控制与浏览器测试继续通过。

## 3. 只读真实 CLI 回读

```bash
container --version
container stats --no-stream --format json
container exec <running-container-id> df -kP /
```

预期：CLI 版本记录为当前受支持版本；容量命令返回根文件系统的 1024 字节块总量、已用量和可用量。不得执行 start、stop、restart、delete 或其他写操作。

## 4. 浏览器验收

打开 `http://127.0.0.1:8787/#main`，验证：

1. 顶部版本显示 GUI v2.10.0。
2. 容器概览出现“存储”列；运行中容器显示百分比和“已用 / 总容量”。
3. 打开同一容器详情，出现“根文件系统”且数值与概览一致。
4. 停止容器显示“未运行”；不触发任何真实生命周期操作。
5. 浏览器控制台无新增错误，现有控制、镜像和远程搜索区域仍可见。

## 5. API 只读回读

```bash
curl -sS http://127.0.0.1:8787/api/v1
curl -sS http://127.0.0.1:8787/api/v1/containers/metrics
```

预期：应用版本为 2.10.0；每个运行中容器指标包含 `rootFilesystem`，有效结果为 `ready`，单容器查询失败为 `unavailable`。
