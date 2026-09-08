# Tasks: 本机 AI 分析历史

**Input**: `specs/016-ai-log-history/`；spec、plan、research、data-model、contracts已完成。

## Phase 1: Setup

- [x] T001 核对干净工作区、私有存储与生命周期边界并完成 `specs/016-ai-log-history/plan.md`。

## Phase 2: Foundational

- [x] T002 核对 `.gitignore`、宪章与 `specs/016-ai-log-history/checklists/requirements.md`；不新增依赖。

## Phase 3: US1 - 保存与关闭后回看

**Goal / Independent test**: 合成分析在关闭模型和重建store后仍可读，取消不写入，失败明确提示。

- [x] T003 [US1] 在 `Tests/ContainerGUITests/Unit/AILogHistoryTests.swift` 和 `AILogServiceTests.swift` 先写持久化/脱敏/取消/保存失败测试并确认失败。
- [x] T004 [US1] 实现 `Sources/ContainerGUI/AI/AILogHistoryStore.swift` 的有限记录、安全写入和独立读取。
- [x] T005 [US1] 在 `Sources/ContainerGUI/AI/AILogService.swift` 和 `App/AppFactory.swift` 接入成功保存与独立历史状态。

## Phase 4: US2 - 浏览和导出

**Goal / Independent test**: 11条合成记录分页10+1，关闭AI浏览导出，不串用容器内容。

- [x] T006 [US2] 在 `Tests/ContainerGUITests/Contract/AILogAPITests.swift` 和 `Tests/Frontend/AILogHistoryTests.mjs` 编写分页、导出、空/错误状态与迟到响应失败测试。
- [x] T007 [US2] 在 `Sources/ContainerGUI/Web/AILogRoutes.swift` 实现独立分页列表。
- [x] T008 [US2] 实现 `Sources/ContainerGUI/Resources/Public/ai-log-history.js` 和现有 `index.html`/`app.css`/`ai-logs.js`/`i18n.js` 的历史界面、导出与中英文。

## Phase 5: US3 - 安全保留和清理

**Goal / Independent test**: 1001条只留1000；删除取消不提交、确认后精确删除；不安全文件不读写。

- [x] T009 [US3] 在 `Tests/ContainerGUITests/Unit/AILogHistoryTests.swift`、HTTP和前端测试补上容量、路径/权限/异常文件与确认删除测试。
- [x] T010 [US3] 在 `Sources/ContainerGUI/AI/AILogHistoryStore.swift`、`Web/AILogRoutes.swift` 和 `Resources/Public/ai-log-history.js` 实现精确保留与删除。

## Phase 6: Verification / Polish

- [x] T011 更新 `README.md` 中英文说明及 `Sources/ContainerGUI/App/AppVersion.swift`、资源版本和版本测试到2.23.0。
- [x] T012 完整测试、release构建和实际浏览器验证，在 `specs/016-ai-log-history/validation.md` 记录证据。
- [x] T013 仅本机 GUI 部署、状态回读、`git diff --check` 和聚焦本地提交；不发布。

## Dependencies & Parallel Opportunities

T001→T002→US1→US2→US3→验证。US1存储/生命周期测试、US2接口/前端测试、US3后端安全/前端确认测试均可分文件并行；本轮顺序实现，研究已通过计划阶段的只读 agent 独立核对。每个故事先失败测试再最小实现。

## Implementation Strategy

MVP为US1持久化；随后被动列表/导出，再接确认删除。整个用户请求作为一个兼容新功能提交，版本2.23.0。
