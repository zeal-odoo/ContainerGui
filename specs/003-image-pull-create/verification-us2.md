# US2 Verification: 创建容器

**Date**: 2026-08-29

## Result

PASS. 最小与完整创建参数、创建后可选启动、同名冲突、幂等重放、秘密脱敏和回读缺失均使用模拟执行器或 HTTP 夹具验证；未执行真实容器创建或启动。

## Evidence

- `node --check Sources/ContainerGUI/Resources/Public/app.js`: PASS
- Focused unit, contract, browser and existing API/UI regression suite: 32 tests, 0 failures
- Create command options precede `-- IMAGE [ARGUMENTS...]`; process arguments cannot be reinterpreted as CLI options
- Port arguments always use `127.0.0.1:host:container/protocol`
- Environment values are present only in the command request and absent from Operation responses
- Optional start is issued only after a created/stopped readback; final success requires running readback
- Exit zero without a named-container readback ends as failed with `targetAbsent=true`

## Final Gate

- Full Swift suite: 83 tests, 0 failures; 1 opt-in live test skipped by default
- Explicit read-only live CLI suite: 1 test, 0 failures
- Real browser against a temporary local service displayed the create dialog and local-image choices
- Invalid name, image, duplicate host port and malformed environment input produced inline errors and no mutation request
- No real container create or start was executed
