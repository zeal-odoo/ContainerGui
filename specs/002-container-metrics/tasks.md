---

description: "容器 CPU 与内存指标的依赖顺序实现任务"
---

# Tasks: 容器 CPU 与内存指标

**Input**: `/specs/002-container-metrics/` 下的 spec、plan、research、data-model、contracts 和 quickstart
**Tests**: 宪章要求测试先行；真实环境验证仅执行只读命令。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可在不同文件上并行，不依赖未完成任务
- **[US1]**: 对应“查看容器资源使用情况”用户故事

## Phase 1: Setup

**Purpose**: 固化 Apple Container CLI 1.3.1 的统计输入契约。

- [X] T001 [US1] 在 `Tests/ContainerGUITests/Fixtures/CLI/1.3.1/metrics/` 增加首样本、连续样本、多核、空数组、负值和缺失 ID 的 JSON 夹具

---

## Phase 2: Tests First

**Purpose**: 在实现前建立可复现的失败证据。

> 必须先运行这些测试并确认因指标能力缺失而失败。

- [X] T002 [P] [US1] 在 `Tests/ContainerGUITests/Unit/ContainerMetricsTests.swift` 添加解析校验、首样本、连续 CPU 差值、多核、计数器复位、零内存上限、缓存淘汰和固定命令参数测试
- [X] T003 [P] [US1] 在 `Tests/ContainerGUITests/Contract/ContainerMetricsAPITests.swift` 添加 `/api/v1/containers/metrics` 成功、采样状态、错误 envelope 和静态路由优先级契约测试
- [X] T004 [P] [US1] 在 `Tests/ContainerGUITests/Browser/ContainerMetricsAssetTests.swift` 添加 CPU/内存表头、五秒并行刷新、格式化、采样中、未运行和暂不可用的静态资源测试

**Checkpoint**: T002-T004 已按预期失败，证明测试确实覆盖尚未实现的能力。

---

## Phase 3: User Story 1 - 查看容器资源使用情况 (Priority: P1) 🎯 MVP

**Goal**: 概览和详情展示当前 CPU 与内存，且首样本、非运行状态和统计失败均安全降级。

**Independent Test**: 使用固定样本验证两个连续快照后 CPU/内存计算正确，打开页面验证运行中、
未运行、采样中和失败状态；列表和详情在统计失败时仍可使用。

### Backend implementation

- [X] T005 [US1] 在 `Sources/ContainerGUI/Domain/ContainerMetricsModels.swift` 实现资源样本、API 模型、有限百分比计算、计数器复位处理和有界上一样本 actor
- [X] T006 [US1] 在 `Sources/ContainerGUI/CLI/CLIModels.swift` 与 `Sources/ContainerGUI/CLI/ContainerCLIClient.swift` 实现严格 JSON 解析、`ContainerMetricsReading` 协议和固定 `stats --no-stream --format json` 只读调用
- [X] T007 [US1] 在 `Sources/ContainerGUI/Web/ContainerMetricsRoutes.swift` 实现只读指标端点，并验证错误继续由 `ErrorMiddleware` 安全映射
- [X] T008 [US1] 在 `Sources/ContainerGUI/App/AppFactory.swift` 注册指标路由，同时保持现有只实现 `ContainerReading` 的测试替身兼容

### Frontend implementation

- [X] T009 [P] [US1] 在 `Sources/ContainerGUI/Resources/Public/index.html` 增加可访问的 CPU 与内存列
- [X] T010 [US1] 在 `Sources/ContainerGUI/Resources/Public/app.js` 并行读取指标、按最新运行状态匹配 ID，并在概览和详情渲染数值及采样/未运行/暂不可用状态
- [X] T011 [P] [US1] 在 `Sources/ContainerGUI/Resources/Public/app.css` 增加紧凑指标主次文本样式和响应式表格宽度

### Story verification

- [X] T012 [US1] 在 `Tests/ContainerGUITests/Integration/ReadOnlyCLISmokeTests.swift` 扩展显式启用的真实 CLI 1.3.1 指标冒烟测试，确认只执行读取
- [X] T013 [US1] 运行指标单元、HTTP 契约与静态资源测试，修复至全部通过并执行 `git diff --check`

**Checkpoint**: User Story 1 可单独运行和验收，且不依赖历史图表或其他资源模块。

---

## Phase 4: Final Validation and Git Evidence

**Purpose**: 证明既有能力未回归、真实 CLI 和浏览器可见结果均符合规格。

- [X] T014 [US1] 按 `specs/002-container-metrics/quickstart.md` 运行全量 XCTest 与显式只读真实 CLI 冒烟测试
- [X] T015 [US1] 在临时 8788 服务执行 API 连续样本和浏览器关键流程验证，确认不打断用户当前 8787 服务
- [X] T016 [US1] 检查 `git status`、`git diff --check` 和最终差异，创建聚焦本地 Git 提交且不推送

---

## Dependencies & Execution Order

```text
T001
 ├─> T002 ─┐
 ├─> T003 ─┼─> T005 -> T006 -> T007 -> T008 -> T010 -> T012 -> T013 -> T014 -> T015 -> T016
 └─> T004 ─┘                    ├─> T009 ─┘
                               └─> T011 ─┘
```

- T002、T003、T004 修改不同测试文件，可并行编写，但都必须在实现前失败。
- T009 与 T011 修改不同静态资源，可在后端完成后并行；T010 汇合数据和显示逻辑。
- T014-T016 必须顺序执行，完成声明以测试、真实只读回读、浏览器可见结果和 Git 提交共同为准。

## Implementation Strategy

1. 先固定 CLI 样本和三层失败测试。
2. 用最小后端切片完成解析、派生计算和独立 API。
3. 用现有五秒刷新机制加入列表与详情显示，不引入前端构建链。
4. 依次完成模拟测试、真实只读验证、临时端口浏览器验证和本地 Git 提交。
