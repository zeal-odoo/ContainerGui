# Quickstart: 容器重启验证

## Prerequisites

- macOS 上可构建 Swift package。
- Apple `container` CLI 仅用于只读版本与状态核对。
- 不点击真实容器的重启确认按钮。

## 1. Contract and service tests

```bash
swift test --filter ContainerControlAPITests
```

Expected:

- 运行中目标接受 `POST /api/v1/containers/{id}/restart`。
- stub 记录严格的 stop → start 顺序。
- 停止失败时 start 计数为零。
- 启动失败和最终状态不匹配都产生 failed operation。
- 错误确认、停止状态、幂等冲突和同目标冲突均被拒绝。

## 2. Browser asset tests

```bash
swift test --filter ContainerControlAssetTests
```

Expected:

- 运行中容器渲染“重启容器”。
- 页面包含确认文案和 `restart` 请求。
- 停止容器仍只走启动/删除路径。

## 3. Full automated suite

```bash
swift test
node --test Tests/Frontend/*.mjs
git diff --check
```

Expected: all non-opt-in tests pass with no real container mutation.

## 4. Read-only live checks

```bash
/usr/local/bin/container --version
/usr/local/bin/container list --all --format json
curl -fsS http://127.0.0.1:8787/api/v1
```

Expected:

- CLI remains compatible.
- Current containers are only read, not restarted.
- API reports GUI version `2.9.0` after the updated service is launched.

## 5. Browser-visible acceptance

Open `http://127.0.0.1:8787/#main`, select a running container, and verify that “重启容器” appears beside “正常停止”. Open the confirmation dialog, verify the exact target and interruption message, then cancel. Select a stopped container and verify that restart is absent. Do not confirm a live restart during automated acceptance.
