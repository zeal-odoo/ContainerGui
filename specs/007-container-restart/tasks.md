# Tasks: 容器重启

**Input**: Design documents from `/specs/007-container-restart/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/openapi.yaml`

**Tests**: 本功能要求测试先行，所有自动化测试必须使用 stub 或静态资源检查，不得重启真实容器。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可在不同文件中并行执行
- **[Story]**: 对应的用户故事
- 每项任务均包含精确文件路径

## Phase 1: Setup

**Purpose**: 固定当前基线和功能范围。

- [x] T001 核对当前分支、干净基线、Apple container CLI 能力与 GUI 版本，记录于 `specs/007-container-restart/research.md`
- [x] T002 验证 `specs/007-container-restart/spec.md`、`plan.md`、`data-model.md`、`contracts/openapi.yaml` 与 `quickstart.md` 无占位符并满足宪章门禁

---

## Phase 2: Foundational Tests

**Purpose**: 先建立失败的重启契约与浏览器资产测试。

- [x] T003 [P] [US1] 在 `Tests/ContainerGUITests/Contract/ContainerControlAPITests.swift` 增加运行中容器重启的接受、stop→start 顺序与最终运行状态测试
- [x] T004 [P] [US1] 在 `Tests/ContainerGUITests/Browser/ContainerControlAssetTests.swift` 增加运行中重启按钮、确认文案和 restart 请求形状测试
- [x] T005 [US1] 运行 `ContainerControlAPITests` 与 `ContainerControlAssetTests`，确认新增测试在实现前失败

**Checkpoint**: 失败测试可以复现缺少重启能力。

---

## Phase 3: User Story 1 - 重启运行中的容器 (Priority: P1) 🎯 MVP

**Goal**: 用户确认后，在一个受控操作中正常停止并重新启动运行中的容器。

**Independent Test**: stub 容器严格记录 stop→start，操作最终成功且回读为 running；浏览器资源包含运行中重启入口。

- [x] T006 [US1] 在 `Sources/ContainerGUI/Domain/OperationModels.swift` 增加 `restartContainer` 操作类型
- [x] T007 [US1] 在 `Sources/ContainerGUI/Web/ContainerControlRoutes.swift` 增加需要确认目标与 UUID 幂等键的重启路由
- [x] T008 [US1] 在 `Sources/ContainerGUI/Web/OperationRoutes.swift` 实现同一操作和目标锁内的正常停止→启动编排与最终 running 回读
- [x] T009 [US1] 在 `Sources/ContainerGUI/Resources/Public/app.js` 仅为运行中容器增加“重启容器”按钮、明确中断确认和现有操作轮询刷新
- [x] T010 [US1] 运行目标 Swift 测试并确认用户故事 1 全部通过

**Checkpoint**: 运行中容器具备可独立验收的重启纵向切片。

---

## Phase 4: User Story 2 - 清楚处理重启失败 (Priority: P2)

**Goal**: 停止失败、启动失败、状态不匹配、重复和冲突请求均安全失败且不虚报成功。

**Independent Test**: stub 分别注入各阶段失败，验证停止失败不调用启动、启动失败保留实际状态、幂等重放不重复执行。

- [x] T011 [US2] 在 `Tests/ContainerGUITests/Contract/ContainerControlAPITests.swift` 增加错误确认、停止目标、停止失败短路、启动失败、幂等重放和目标冲突测试
- [x] T012 [US2] 在 `Sources/ContainerGUI/Web/OperationRoutes.swift` 完成分阶段失败映射、实际状态回读和无虚假成功处理
- [x] T013 [US2] 运行目标契约测试并确认所有失败与冲突场景通过

**Checkpoint**: 重启所有已知失败路径均有确定且安全的结果。

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: 版本、全量回归、浏览器验收与 Git 交付。

- [x] T014 将 `Sources/ContainerGUI/App/AppVersion.swift` 从 `2.8.0` 递增到 `2.9.0`
- [x] T015 按 `specs/007-container-restart/quickstart.md` 运行全量 Swift、Node 和差异检查，并进行只读 CLI/API 回读
- [x] T016 在浏览器中验证运行中重启入口与确认弹窗后取消，不触发真实重启；记录可见验收结果
- [x] T017 将 `specs/007-container-restart/spec.md` 标记为已实现并勾选 `specs/007-container-restart/tasks.md` 全部任务
- [x] T018 将规格、代码、测试与版本作为一个逻辑提交推送到 `origin/main`，并核对本地 HEAD、远端 main 与工作区状态

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5。
- T003 与 T004 可在不同测试文件中并行，但 T005 必须等待两者完成。
- T006 → T007 → T008 → T009；T010 在实现完成后执行。
- T011 必须先于 T012 失败，T013 在 T012 后执行。
- T014-T018 必须在全部用户故事通过后执行。

## Implementation Strategy

1. 先让契约和浏览器资产测试准确失败。
2. 实现最小后端编排和单一运行中入口。
3. 补齐失败短路、幂等和冲突覆盖。
4. 递增版本，完成全量与浏览器安全验收。
5. 单一 Git 提交并验证远端，不对真实容器执行重启。
