# Tasks: root 公钥 SSH 登录

**Input**: Design documents from `/specs/005-root-ssh-key-login/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/openapi.yaml, quickstart.md

**Tests**: 项目宪章要求测试先行；每个行为变更先补失败测试，再做最小实现。

**Organization**: Tasks are grouped by user story so each story remains independently testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可在不同文件上并行完成，且不依赖同阶段未完成任务
- **[Story]**: 对应 spec.md 中的用户故事

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: 建立当前绿色基线并锁定受影响文件，不创建新架构。

- [x] T001 Run the existing SSH, container-create, browser-resource, API-contract, and version baselines covering `Tests/ContainerGUITests/Unit/SSHQuickConfigTests.swift`, `Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift`, `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift`, `Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift`, and `Tests/ContainerGUITests/Unit/AppVersionTests.swift`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 现有 SSH 快速配置、标签回读和静态表单已提供全部基础设施。

**Checkpoint**: No new database, route, service, or abstraction is required; proceed with story tests first.

---

## Phase 3: User Story 1 - 显式启用 root 公钥登录 (Priority: P1) 🎯 MVP

**Goal**: 用户显式勾选 root 仅公钥登录后，服务端接受受控 root 身份、生成安全引导配置，并显示 root 连接命令。

**Independent Test**: 用模拟创建请求提交 `loginAsRoot=true`、`username=root` 和有效公钥，确认 CLI 形状只含固定回环发布和固定脚本，API 不泄露公钥，root 标签派生 `ssh -p <port> root@127.0.0.1`。

### Tests for User Story 1

- [x] T002 [P] [US1] Add failing root selection, identity validation, safe-summary, metadata, and bootstrap security tests in `Tests/ContainerGUITests/Unit/SSHQuickConfigTests.swift`
- [x] T003 [P] [US1] Add a failing root SSH CLI argument-shape test in `Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift`
- [x] T004 [P] [US1] Add a failing explicit-root API acceptance and public-key non-disclosure test in `Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift`
- [x] T005 [P] [US1] Add failing root checkbox, warning, disabled username, and structured request assertions in `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift`

### Implementation for User Story 1

- [x] T006 [US1] Add backward-compatible `loginAsRoot`, root/standard identity validation, safe-summary metadata, root label readback, and the fixed root authorized-key/bootstrap branch in `Sources/ContainerGUI/Domain/SSHModels.swift`
- [x] T007 [US1] Add the default-off root public-key control and warning in `Sources/ContainerGUI/Resources/Public/index.html`, then submit the explicit root mode without password or private-key fields from `Sources/ContainerGUI/Resources/Public/app.js`

**Checkpoint**: Explicit root mode is functional in model, CLI, API, and visible GUI tests; ordinary mode remains to be proven independently.

---

## Phase 4: User Story 2 - 保持普通用户安全默认值 (Priority: P2)

**Goal**: root 继续默认关闭，旧请求和普通用户名行为不变，切换 root 后可恢复原用户名。

**Independent Test**: 省略 `loginAsRoot` 的旧请求仍创建普通用户；普通模式提交 `root` 被拒绝；GUI 打开时 root 未选中，勾选/取消后恢复此前普通用户名，关闭 SSH 会清除 root 模式。

### Tests for User Story 2

- [x] T008 [P] [US2] Add failing omitted-field compatibility and implicit-root rejection tests in `Tests/ContainerGUITests/Unit/SSHQuickConfigTests.swift` and `Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift`
- [x] T009 [P] [US2] Add failing default-off, SSH-disabled, and normal-username restoration assertions in `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift`

### Implementation for User Story 2

- [x] T010 [US2] Preserve and restore the ordinary username across root-mode toggles, clear root mode when SSH is disabled, and retain old-request defaults in `Sources/ContainerGUI/Resources/Public/app.js` and `Sources/ContainerGUI/Domain/SSHModels.swift`

**Checkpoint**: Standard-user and root-user modes are both independently testable and cannot be selected accidentally.

---

## Phase 5: User Story 3 - 重启后继续使用同一 root 连接 (Priority: P3)

**Goal**: root 授权文件、仅公钥策略、端口、标签和连接身份在容器启停及 GUI 刷新后保持一致。

**Independent Test**: 对同一固定 root 配置模拟创建、停止、再次启动和标签详情回读，确认引导脚本每次都幂等写回 root 配置，且连接命令不变。

### Tests for User Story 3

- [x] T011 [P] [US3] Add restart-idempotence and repeated root-label readback regression tests in `Tests/ContainerGUITests/Unit/SSHQuickConfigTests.swift` and `Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift`

### Implementation for User Story 3

- [x] T012 [US3] Ensure the root branch rewrites `/root/.ssh/authorized_keys` and the fixed `sshd_config` fragment on every entrypoint invocation while reusing host keys and unchanged labels in `Sources/ContainerGUI/Domain/SSHModels.swift`

**Checkpoint**: All three stories pass without mutating a real container.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: 完成版本、全量验证、只读运行态回读与 Git 门禁。

- [x] T013 [P] Update the expected and runtime application version from 2.6.1 to 2.7.0 in `Tests/ContainerGUITests/Unit/AppVersionTests.swift` first and then `Sources/ContainerGUI/App/AppVersion.swift`
- [x] T014 Run the full Swift and frontend suites documented in `specs/005-root-ssh-key-login/quickstart.md` and confirm all prior container/image/SSH tests pass
- [x] T015 Perform the non-mutating live CLI and browser checks from `specs/005-root-ssh-key-login/quickstart.md`, including visible GUI v2.7.0 and root control state at `127.0.0.1:8787`
- [x] T016 Review `git diff`, create one scoped feature commit containing `specs/005-root-ssh-key-login/`, source, tests, and v2.7.0, then push `main` to the configured GitHub remote

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: starts immediately and establishes a green baseline.
- **Foundational (Phase 2)**: no new code; confirms existing infrastructure is sufficient.
- **US1 (Phase 3)**: starts after baseline; tests T002-T005 must fail before T006-T007.
- **US2 (Phase 4)**: depends on the explicit mode field from US1; tests T008-T009 precede T010.
- **US3 (Phase 5)**: depends on the root bootstrap and label parsing from US1; T011 precedes T012.
- **Polish (Phase 6)**: depends on all stories; version test precedes version implementation, then full validation and one Git commit.

### User Story Dependency Graph

```text
US1 explicit root mode
├──> US2 safe ordinary defaults
└──> US3 restart persistence
US2 + US3 ──> full validation and release
```

### Parallel Opportunities

- T002, T003, T004, and T005 touch separate test files and can be prepared in parallel before implementation.
- T008 and T009 cover server/API versus browser files and can be prepared in parallel.
- T013 can be prepared while documentation validation is reviewed, but runtime version changes only after its test fails.
- No source tasks that edit `SSHModels.swift` or `app.js` should run concurrently.

## Parallel Example: User Story 1

```text
Task: T002 add SSH domain/bootstrap tests
Task: T003 add CLI shape test
Task: T004 add API contract test
Task: T005 add browser resource test
```

## Implementation Strategy

### MVP First

1. Run T001 baseline.
2. Write and observe failures for T002-T005.
3. Implement T006-T007.
4. Run the US1 focused tests before continuing.

### Incremental Delivery

1. US1 adds explicit root public-key mode.
2. US2 proves the secure default and ordinary-user compatibility.
3. US3 proves restart/readback semantics without real mutations.
4. Phase 6 bumps v2.7.0, validates all behavior, deploys locally, commits once, and pushes.

## Notes

- Every task has an exact file path or validation artifact.
- Automated tests use fixed executors/resources and must not change real containers.
- The user’s “every update increments version and uses Git” rule is satisfied by T013-T016 as one logical feature update.
