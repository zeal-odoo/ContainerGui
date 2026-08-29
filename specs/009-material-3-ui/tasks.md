# Tasks: Material Design 3 界面视觉升级

**Input**: Design documents from `/specs/009-material-3-ui/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/ui-contract.md](./contracts/ui-contract.md)

**Tests**: 宪章要求测试先行；所有视觉契约先在静态资源测试中失败，再进行最小实现。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可在不同文件中独立处理
- **[Story]**: 对应规格的用户故事

## Phase 1: Setup

**Purpose**: 锁定官方视觉依据、范围和当前静态资源基线。

- [x] T001 核对 `specs/009-material-3-ui/spec.md`、`research.md`、`data-model.md`、`contracts/ui-contract.md` 和 `checklists/requirements.md` 均完整且无待澄清项
- [x] T002 记录 `Sources/ContainerGUI/Resources/Public/index.html`、`app.css`、`app.js` 的现有 DOM/行为边界并确认本次不改 API

---

## Phase 2: Foundational — 测试先行

**Purpose**: 在任何视觉实现前建立可自动验证的 Material 3 契约。

- [x] T003 [P] 在 `Tests/ContainerGUITests/Browser/Material3AssetTests.swift` 添加语义颜色、类型、形状和层级令牌断言
- [x] T004 [P] 在 `Tests/ContainerGUITests/Browser/Material3AssetTests.swift` 添加按钮、字段、弹窗、表格、状态、深色主题、减少动态效果和无远程资源断言
- [x] T005 运行 `swift test --filter Material3AssetTests` 并记录实现前预期失败

**Checkpoint**: 测试必须先因缺少新视觉契约失败。

---

## Phase 3: User Story 1 — Material 3 主仪表板 (Priority: P1) 🎯 MVP

**Goal**: 以统一的语义色彩、表面、类型和形状呈现顶部栏、状态、统计、容器列表与详情。

**Independent Test**: 在桌面宽度读取首页，现有任务入口不变，主次层级和状态一眼可辨。

- [x] T006 [US1] 在 `Sources/ContainerGUI/Resources/Public/app.css` 建立浅色 Material 3 颜色、类型、形状、层级与动效令牌
- [x] T007 [US1] 在 `Sources/ContainerGUI/Resources/Public/app.css` 升级 body、topbar、hero、health-card、stats、panel、table 和 detail-panel
- [x] T008 [US1] 在 `Sources/ContainerGUI/Resources/Public/app.css` 升级运行/停止/健康/警告/失败与资源指标视觉状态且保留文字语义
- [x] T009 [US1] 运行 `swift test --filter Material3AssetTests` 并确认主仪表板相关断言通过

**Checkpoint**: 扩展宽度的主仪表板形成完整、可独立验收的 Material 3 视觉切片。

---

## Phase 4: User Story 2 — 一致的交互控件与弹窗 (Priority: P2)

**Goal**: 搜索、按钮、表单、进度、日志和弹窗拥有一致可辨的状态反馈。

**Independent Test**: 仅用键盘遍历首页和打开的弹窗，焦点清晰，主要/次要/危险/禁用语义不混淆。

- [x] T010 [US2] 在 `Sources/ContainerGUI/Resources/Public/app.css` 升级主要、次要、危险、小型、图标和折叠按钮的 hover/focus/pressed/disabled 状态
- [x] T011 [US2] 在 `Sources/ContainerGUI/Resources/Public/app.css` 升级搜索、输入、选择、文本区、复选框、字段错误和 SSH/Odoo 分组表面
- [x] T012 [US2] 在 `Sources/ContainerGUI/Resources/Public/app.css` 升级 dialog、backdrop、toast、progress、operation-status、logs 和 raw detail 层级
- [x] T013 [US2] 在 `Sources/ContainerGUI/Resources/Public/index.html` 仅补充必要的 Material 3 主题元数据，保留全部现有 ID、文案和脚本入口
- [x] T014 [US2] 运行 `swift test --filter Material3AssetTests` 和 `node --test Tests/Frontend/*.mjs` 验证样式契约及既有行为

**Checkpoint**: 表单与有风险操作在不提交真实变更的前提下可独立浏览验收。

---

## Phase 5: User Story 3 — 自适应、深色与减少动态效果 (Priority: P3)

**Goal**: 扩展、紧凑宽度及浅色/深色系统主题下均保持可读可用。

**Independent Test**: 在扩展和紧凑视口、浅色和深色主题各读取页面，确认无整体横向溢出且状态清晰。

- [x] T015 [US3] 在 `Sources/ContainerGUI/Resources/Public/app.css` 完整映射深色 Material 3 语义令牌
- [x] T016 [US3] 在 `Sources/ContainerGUI/Resources/Public/app.css` 完善 1200/900/600px 自适应、局部表格滚动与操作区换行
- [x] T017 [US3] 在 `Sources/ContainerGUI/Resources/Public/app.css` 添加 `prefers-reduced-motion` 和不支持高级视觉效果时的稳健基础样式
- [x] T018 [US3] 运行 `swift test --filter Material3AssetTests` 确认主题、自适应和减少动态效果契约通过

**Checkpoint**: 三个用户故事的自动化视觉契约全部通过。

---

## Phase 6: Polish & Delivery Gates

**Purpose**: 版本、完整回归、真实浏览器与 Git 门禁。

- [x] T019 [P] 在 `Sources/ContainerGUI/App/AppVersion.swift` 与 `Tests/ContainerGUITests/Unit/AppVersionTests.swift` 将应用版本递增至 2.11.0
- [x] T020 运行完整 `swift test`、`node --test Tests/Frontend/*.mjs` 和 `git diff --check`
- [x] T021 只重启本机 Container GUI 服务并回读 `GET /api/v1` 的 2.11.0，不触发真实容器写操作
- [x] T022 在真实浏览器完成扩展/紧凑、浅色/深色、键盘焦点、折叠箭头和三个弹窗的只读可见验收，并检查 console warning/error
- [x] T023 将验证证据和状态回填 `specs/009-material-3-ui/spec.md` 与本任务清单
- [x] T024 创建一个包含规格、测试、视觉实现和版本的 Git 提交，推送 `origin/main` 并验证本地 HEAD 与远端一致

---

## Dependencies & Execution Order

- Phase 1 完成后才进入测试先行。
- T003–T005 阻塞所有视觉实现。
- US1 → US2 → US3 按共享 `app.css` 顺序执行，避免同文件并发冲突。
- T019 可与最终文档整理独立进行，但必须在完整测试和提交前完成。
- T024 依赖所有验证与文档回填完成。

## Implementation Strategy

1. 先以失败测试定义设计系统契约。
2. 先完成可单独验收的主仪表板，再覆盖交互控件与弹窗，最后补齐主题和断点。
3. 不修改 `app.js` 或后端；如视觉目标必须依赖行为变化，应暂停并更新规格。
4. 浏览器验收只执行读取、打开弹窗、焦点和折叠等非写操作，不提交真实容器变更。
