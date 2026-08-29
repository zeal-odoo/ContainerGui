# Tasks: 容器存储容量

**Input**: Design documents from `/specs/008-container-storage-capacity/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/openapi.yaml

**Tests**: 宪章要求测试先行；所有自动化测试必须使用固定输出或只读路径，不得改变真实容器。

**Organization**: 任务按用户故事组织，每个故事均有独立验收标准。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可在不同文件上并行完成
- **[Story]**: 对应 spec.md 用户故事
- 每项包含准确文件路径

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 准备版本化、只读的根文件系统容量输出样本。

- [x] T001 在 `Tests/ContainerGUITests/Fixtures/CLI/1.3.1/metrics/df-root-valid.txt` 与 `df-root-invalid.txt` 增加有效和无效容量输出夹具

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 确认现有指标模型、端点和静态资源测试边界可安全扩展。

- [x] T002 核对并保留 `Sources/ContainerGUI/CLI/ContainerCLIClient.swift` 的固定参数执行边界和 `Sources/ContainerGUI/Web/ContainerMetricsRoutes.swift` 的五秒整体超时
- [x] T003 核对 `.gitignore` 已覆盖 Swift 构建产物并在 `specs/008-container-storage-capacity/plan.md` 保持无新增依赖的结构决策

**Checkpoint**: 固定只读查询和现有刷新边界明确后进入用户故事。

---

## Phase 3: User Story 1 - 查看运行中容器的存储容量 (Priority: P1) 🎯 MVP

**Goal**: 在概览和详情显示根文件系统使用率及“已用 / 总容量”。

**Independent Test**: 固定有效容量输出经解析和 API 返回后，概览与详情显示相同数值。

### Tests for User Story 1 ⚠️

- [x] T004 [P] [US1] 在 `Tests/ContainerGUITests/Unit/ContainerMetricsTests.swift` 增加有效容量解析、精确字节换算和固定 `container exec <id> df -kP /` 命令测试，并先确认失败
- [x] T005 [P] [US1] 在 `Tests/ContainerGUITests/Contract/ContainerMetricsAPITests.swift` 增加 `rootFilesystem` JSON 契约断言，并先确认失败
- [x] T006 [P] [US1] 在 `Tests/ContainerGUITests/Browser/ContainerMetricsAssetTests.swift` 增加“存储”列、根文件系统详情和已用/总容量渲染断言，并先确认失败

### Implementation for User Story 1

- [x] T007 [US1] 在 `Sources/ContainerGUI/Domain/ContainerMetricsModels.swift` 与 `Sources/ContainerGUI/CLI/CLIModels.swift` 增加根文件系统容量模型、校验解析和使用率计算
- [x] T008 [US1] 在 `Sources/ContainerGUI/CLI/ContainerCLIClient.swift` 将每个运行中指标条目并行附加固定只读容量读取结果
- [x] T009 [US1] 在 `Sources/ContainerGUI/Resources/Public/index.html`、`app.js` 与 `app.css` 增加“存储”列和详情“根文件系统”，复用现有指标样式与响应式布局

**Checkpoint**: 有效运行中容器可在概览和详情一致显示容量。

---

## Phase 4: User Story 2 - 明确容量不可读取的状态 (Priority: P2)

**Goal**: 停止容器与单容器容量失败都有明确且隔离的降级状态。

**Independent Test**: 模拟停止、命令失败、无效输出和一个成功一个失败，验证“未运行/暂不可用”且其他指标不受影响。

### Tests for User Story 2 ⚠️

- [x] T010 [US2] 在 `Tests/ContainerGUITests/Unit/ContainerMetricsTests.swift` 增加零容量、溢出、缺列和单容器命令失败的拒绝与隔离测试，并先确认失败
- [x] T011 [US2] 在 `Tests/ContainerGUITests/Browser/ContainerMetricsAssetTests.swift` 增加“读取中”“未运行”“暂不可用”容量状态断言，并先确认失败

### Implementation for User Story 2

- [x] T012 [US2] 在 `Sources/ContainerGUI/CLI/ContainerCLIClient.swift` 与 `Sources/ContainerGUI/Resources/Public/app.js` 完成单容器失败隔离、停止状态和缺失数据降级逻辑

**Checkpoint**: 单容器错误不阻塞列表、CPU、内存和其他容器容量。

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: 完成版本、全量验证、运行态回读和文档证据。

- [x] T013 [P] 将 `Sources/ContainerGUI/App/AppVersion.swift` 和 `Tests/ContainerGUITests/Unit/AppVersionTests.swift` 的 GUI 版本递增至 2.10.0
- [x] T014 运行 `swift test`、`node --test Tests/Frontend/*.mjs` 与 `git diff --check`，并在 `specs/008-container-storage-capacity/spec.md` 记录验证证据和 Implemented 状态
- [x] T015 使用只读 CLI/API 与浏览器检查 2.10.0、“存储”列、详情容量及无控制台错误，并在 `specs/008-container-storage-capacity/spec.md` 记录实际回读
- [x] T016 将本次代码、测试和文档作为一个逻辑 Git 提交推送，并确认 `origin/main` 与本地 HEAD 一致且工作区干净

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: 可立即开始。
- **Foundational (Phase 2)**: 依赖 Setup，阻塞用户故事。
- **User Story 1 (Phase 3)**: 依赖 Foundational，是本次 MVP。
- **User Story 2 (Phase 4)**: 依赖 User Story 1 的容量模型与展示，但可独立验证降级行为。
- **Polish (Phase 5)**: 依赖两个故事完成。

### Within Each User Story

- 测试必须先编写并确认失败，再实现对应模型、命令读取与 UI。
- 模型与解析先于命令集成，命令集成先于浏览器最终验收。
- 不通过真实生命周期操作验证容量。

### Parallel Opportunities

- T004、T005、T006 位于不同测试文件，可并行编写。
- T013 的版本文件与容量实现文件不同，可在功能稳定后独立修改。
- Swift、Node 与差异检查可在实现完成后并行运行，但最终证据统一记录。

## Parallel Example: User Story 1

```text
Task: "在 Unit/ContainerMetricsTests.swift 增加容量解析和命令测试"
Task: "在 Contract/ContainerMetricsAPITests.swift 增加 JSON 契约断言"
Task: "在 Browser/ContainerMetricsAssetTests.swift 增加可见 UI 断言"
```

## Implementation Strategy

### MVP First

1. 完成 T001-T003。
2. 完成 T004-T006 并保留失败证据。
3. 完成 T007-T009，使有效容量从读取到 UI 形成闭环。
4. 独立验证 User Story 1 后再加入失败隔离。

### Incremental Delivery

1. 有效容量读取与展示 → 目标测试通过。
2. 异常和停止状态 → 隔离测试通过。
3. 版本、全量回归、浏览器只读验收 → Git 提交和推送。

## Notes

- 本次只读容量不等于宿主机实际占用或容器磁盘配额。
- 不新增容量配置、历史曲线、告警或卷统计。
- 完成任务后将对应复选框更新为 `[x]`。
