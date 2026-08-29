# Tasks: SSH 快速配置

**Input**: Design documents from `/specs/004-ssh-quick-config/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/openapi.yaml, quickstart.md

**Tests**: 本功能遵循项目宪章的强制 TDD；每个故事先增加失败测试，再做最小实现。

**Organization**: 任务按用户故事分组，每个故事都有独立验收边界。

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 确认现有 Swift 项目边界和版本化测试资源位置。

- [X] T001 Verify Swift, universal and secret patterns remain covered in `.gitignore`
- [X] T002 Add a sanitized Apple Container CLI 1.3.1 SSH-labelled detail fixture in `Tests/ContainerGUITests/Fixtures/CLI/1.3.1/ssh-container-detail.json`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 建立共享的 SSH 创建、标签和状态模型测试入口；完成前不进入界面实现。

- [X] T003 Add failing shared SSH model and label parsing tests in `Tests/ContainerGUITests/Unit/SSHQuickConfigTests.swift`
- [X] T004 Implement the minimal SSH request, metadata and status entities in `Sources/ContainerGUI/Domain/SSHModels.swift`

**Checkpoint**: SSH 结构化数据和固定标签契约可由单元测试独立验证。

---

## Phase 3: User Story 1 - 一键配置密钥 SSH (Priority: P1) 🎯 MVP

**Goal**: 创建表单只接收端口、用户名、公钥，自动生成受控 SSH 容器配置并启动。

**Independent Test**: 使用固定执行器提交一个合法 SSH 请求，确认唯一写命令只含回环 22/tcp、固定标签、
固定入口点/脚本和保留环境变量；浏览器表单无需任何安装命令即可构造同一结构化请求。

### Tests for User Story 1

- [X] T005 [P] [US1] Add failing fixed CLI argument and automatic-start tests in `Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift`
- [X] T006 [P] [US1] Add failing SSH create HTTP contract and safe-summary tests in `Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift`
- [X] T007 [P] [US1] Add failing SSH form, file picker and request-shape asset tests in `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift`

### Implementation for User Story 1

- [X] T008 [US1] Extend create request validation and safe summaries with optional SSH settings in `Sources/ContainerGUI/Domain/ContainerCreationModels.swift`
- [X] T009 [US1] Generate only the fixed SSH labels, loopback publish, reserved environment and bootstrap arguments in `Sources/ContainerGUI/CLI/ContainerCLIClient.swift`
- [X] T010 [US1] Add the accessible SSH preset fields and key-file input in `Sources/ContainerGUI/Resources/Public/index.html`
- [X] T011 [US1] Implement SSH toggle, `.pub` reading, client validation and structured request building in `Sources/ContainerGUI/Resources/Public/app.js`
- [X] T012 [US1] Style the compact SSH preset without changing unrelated layout in `Sources/ContainerGUI/Resources/Public/app.css`
- [X] T013 [US1] Run the US1 unit, contract and browser tests covering `Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift`, `Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift` and `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift`

**Checkpoint**: 用户可在 60 秒内配置并提交密钥 SSH，不输入任何命令文本。

---

## Phase 4: User Story 2 - 自定义端口并在重启后恢复 (Priority: P2)

**Goal**: 标签和主进程配置在同一容器启停后保留，详情显示独立于容器状态的 SSH 就绪与连接命令。

**Independent Test**: 解析带标签的 1.3.1 详情，模拟停止/运行状态和 SSH 横幅检查，确认端口/用户/命令
不变且只有有效 `SSH-` 横幅返回 ready。

### Tests for User Story 2

- [X] T014 [P] [US2] Extend fixture parsing and restart-semantics tests in `Tests/ContainerGUITests/Unit/SSHQuickConfigTests.swift`
- [X] T015 [P] [US2] Add failing ready, initializing, stopped, failed and unconfigured API tests in `Tests/ContainerGUITests/Contract/SSHStatusAPITests.swift`
- [X] T016 [P] [US2] Add failing SSH detail status and copy-command asset tests in `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift`

### Implementation for User Story 2

- [X] T017 [US2] Parse only valid trusted SSH labels into container summaries in `Sources/ContainerGUI/CLI/CLIModels.swift` and `Sources/ContainerGUI/Domain/ContainerModels.swift`
- [X] T018 [US2] Implement a bounded `SSH-` loopback banner probe behind a replaceable protocol in `Sources/ContainerGUI/SSH/LoopbackSSHReadinessChecker.swift`
- [X] T019 [US2] Implement the container-derived SSH status endpoint in `Sources/ContainerGUI/Web/SSHStatusRoutes.swift`
- [X] T020 [US2] Register the live readiness checker without changing generic read-test routing in `Sources/ContainerGUI/App/AppFactory.swift`
- [X] T021 [US2] Render and refresh SSH status, connection command and copy action in `Sources/ContainerGUI/Resources/Public/index.html` and `Sources/ContainerGUI/Resources/Public/app.js`
- [X] T022 [US2] Run the US2 unit, contract and browser tests covering `Tests/ContainerGUITests/Unit/SSHQuickConfigTests.swift`, `Tests/ContainerGUITests/Contract/SSHStatusAPITests.swift` and `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift`

**Checkpoint**: 同一容器重启后连接信息不变，运行状态不会被误报为 SSH 已就绪。

---

## Phase 5: User Story 3 - 安全校验与可理解错误 (Priority: P3)

**Goal**: 所有冲突和非法 SSH 输入在 CLI 前被拒绝，完整公钥不进入任何可见回读。

**Independent Test**: 提交低位/重复端口、root/非法用户名、坏公钥、保留环境变量、进程参数冲突和未启动
请求，确认执行器零调用；编码详情和 Operation 后确认完整公钥不存在。

### Tests for User Story 3

- [X] T023 [P] [US3] Add failing negative validation and no-CLI-execution cases in `Tests/ContainerGUITests/Unit/SSHQuickConfigTests.swift` and `Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift`
- [X] T024 [P] [US3] Add failing embedded environment redaction coverage in `Tests/ContainerGUITests/Unit/ContainerCLIReadTests.swift`
- [X] T025 [P] [US3] Add failing field-error and disabled-conflict browser assertions in `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift`

### Implementation for User Story 3

- [X] T026 [US3] Complete server-side cross-field SSH validation in `Sources/ContainerGUI/Domain/ContainerCreationModels.swift`
- [X] T027 [US3] Redact sensitive `KEY=value` entries nested in configuration arrays in `Sources/ContainerGUI/Domain/JSONValue.swift`
- [X] T028 [US3] Complete matching client-side SSH field errors and conflict prevention in `Sources/ContainerGUI/Resources/Public/app.js`
- [X] T029 [US3] Run the US3 negative and redaction tests covering `Tests/ContainerGUITests/Unit/SSHQuickConfigTests.swift`, `Tests/ContainerGUITests/Unit/ContainerCLIReadTests.swift` and `Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift`

**Checkpoint**: 无效请求不触发 CLI，完整公钥不出现在可见状态。

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 完成版本、文档、全量回归、只读实机和 Git 门禁。

- [X] T030 Update user-facing bilingual SSH usage and restart notes in `README.md`
- [X] T031 Increment the GUI version and version test to 2.5.0 in `Sources/ContainerGUI/App/AppVersion.swift` and `Tests/ContainerGUITests/Unit/AppVersionTests.swift`
- [X] T032 Mark completed implementation tasks and validate every scenario in `specs/004-ssh-quick-config/tasks.md` and `specs/004-ssh-quick-config/quickstart.md`
- [X] T033 Run the full Swift suite and read-only CLI smoke tests for `Package.swift` without mutating any real container
- [X] T034 Browser-check the visible v2.5.0 form and existing-container detail at `Sources/ContainerGUI/Resources/Public/index.html` without submitting a create request
- [X] T035 Create one versioned feature commit and push `main` to the configured GitHub remote using the complete working tree for `specs/004-ssh-quick-config/`

---

## Phase 7: Browser Key Generation & Keep-Alive Preset

**Purpose**: 让没有现成密钥的用户可从 GUI 完成 SSH 准备，并免除普通基础镜像的重复进程参数输入。

- [X] T036 Add failing asset and OpenSSH compatibility tests in `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift` and `Tests/Frontend/SSHKeyGeneratorTests.mjs`
- [X] T037 Implement dependency-free browser-local RSA-3072 generation in `Sources/ContainerGUI/Resources/Public/ssh-key-generator.js`
- [X] T038 Add one-click private-key download and public-key autofill to `Sources/ContainerGUI/Resources/Public/index.html` and `Sources/ContainerGUI/Resources/Public/app.js`
- [X] T039 Add the fixed keep-alive checkbox and SSH conflict behavior in `Sources/ContainerGUI/Resources/Public/index.html` and `Sources/ContainerGUI/Resources/Public/app.js`
- [X] T040 Update bilingual usage, safety boundaries and feature decisions in `README.md` and `specs/004-ssh-quick-config/`
- [X] T041 Increment the GUI version and version test to 2.6.0 in `Sources/ContainerGUI/App/AppVersion.swift` and `Tests/ContainerGUITests/Unit/AppVersionTests.swift`
- [X] T042 Run full Swift, Node, read-only CLI and non-mutating browser verification
- [X] T043 Commit the complete v2.6.0 update, push `main`, restart the local GUI and read back the deployed version

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup has no dependency.
- Foundational depends on Setup and blocks all stories.
- US1 depends on Foundational and is the MVP.
- US2 depends on SSH metadata created by US1, but its status endpoint is independently testable with fixtures and a stub checker.
- US3 depends on the US1 request surface and can be verified independently with negative inputs.
- Polish depends on all selected stories.

### Within Each User Story

- Tests must be written and observed failing before implementation.
- Domain validation precedes CLI argument generation.
- CLI/route behavior precedes browser integration.
- The story-specific test set must pass before starting the next story.

### Parallel Opportunities

- Different failing test files marked `[P]` can be authored independently before implementation.
- US2 route contract tests and browser asset tests are independent.
- US3 redaction and browser validation tests touch different files.
- Production files shared by stories are deliberately sequential to avoid conflicting edits.

## Parallel Example: User Story 1

```text
Task T005: CLI fixed-argument tests in ImageAndCreationCLITests.swift
Task T006: HTTP contract tests in ResourceMutationAPITests.swift
Task T007: Browser asset tests in ResourceMutationAssetTests.swift
```

## Implementation Strategy

### MVP First

1. Complete T001-T004.
2. Write and observe T005-T007 fail.
3. Complete T008-T012 and pass T013.
4. Stop here if only structured one-click creation is needed.

### Incremental Delivery

1. Add US1 structured creation.
2. Add US2 authoritative metadata, readiness and restart-visible status.
3. Add US3 negative validation and complete redaction.
4. Finish the original SSH feature as one v2.5.0 logical update.
5. Add browser-local key generation and the keep-alive GUI preset as one v2.6.0 logical update.

## Notes

- `[P]` means different files with no incomplete same-file dependency.
- No test may submit a real container mutation.
- Fixed bootstrap text is application-owned; no user value is interpolated into it.
- Every completed task must be marked `[X]` before final reporting.
