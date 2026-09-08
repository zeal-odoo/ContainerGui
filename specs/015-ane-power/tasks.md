# Tasks: 整机 ANE 估算功耗

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/api.md

## Phase 1: Setup

- [x] T001 确认用户口径和规格质量于 specs/015-ane-power/spec.md、checklists/requirements.md。

## Phase 2: Foundation

- [x] T002 定义只读边界和接口于 specs/015-ane-power/plan.md、contracts/api.md；核对 .gitignore 和私有 API 降级。

## Phase 3: US1 — 准确功耗 (MVP)

Goal: 显示独立实时瓦数。Independent test: 固定能量差/时间的读数精确且没有百分比转换。

- [x] T003 [P] [US1] 先添加并运行 Tests/ContainerGUITests/Unit/ANEPowerTests.swift 的采样/换算/缓存失败用例。
- [x] T004 [P] [US1] 先添加并运行 Tests/Frontend/ANEPowerTests.mjs 的显示/范围/独立刷新失败用例。
- [x] T005 [US1] 在 Sources/ContainerGUI/Domain/ANEPower.swift 和 Infrastructure/IOReportANEEnergyReader.swift 实现被动串行读取。
- [x] T006 [US1] 在 Tests/ContainerGUITests/Contract/ANEPowerAPITests.swift 先测 null/安全/隔离，再接入 Web/ANEPowerRoutes.swift 和 App/AppFactory.swift。
- [x] T007 [US1] 在 Sources/ContainerGUI/Resources/Public/{app.js,app.css,index.html,i18n.js} 接入独立指标和可见页面刷新。

## Phase 4: US2 — 兼容与失败

Goal: 不伪造数据，不干扰其他功能。Independent test: 故障清旧值/恢复与本地化。

- [x] T008 [P] [US2] 在 Tests/ContainerGUITests/Unit/ANEPowerTests.swift 覆盖缺失、重复、单位、重置、过期及无效窗口并实现降级。
- [x] T009 [P] [US2] 在 Tests/Frontend/ANEPowerTests.mjs 覆盖失败清旧值、零值、双语和隐藏恢复。

## Phase 5: Polish

- [x] T010 在 README.md 更新双语 ANE 说明并将 App/AppVersion.swift 及对应版本测试/资源递增到 2.22.0。
- [x] T011 完成 quickstart.md 的全套测试、真实只读接口、浏览器桌面/390px验证，记录 specs/015-ane-power/validation.md。
- [x] T012 审核本任务差异及 git diff --check，部署回读并创建包含版本号的聚焦本地提交。

## Dependencies & Parallel Execution

T001 → T002 → US1 → US2 → Polish。US1 可并行进行后端 T003/T005 与前端 T004/T007；US2 两套测试相互独立。所有代码变更先有失败测试，最终共用全套回归。后端 agent 持有 SwiftPM 构建锁，主代理不并发运行 SwiftPM。

## Implementation Strategy

先验证有效指标纵向切片，再验证兼容降级，最后浏览器与运行服务回读。无 GitHub 发布任务。
