# Tasks: 拉取镜像与创建容器

**Input**: Design documents from `/specs/003-image-pull-create/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/openapi.yaml, quickstart.md

**Tests**: 宪章和 FR-019 要求 TDD；所有写操作测试必须使用夹具与模拟执行器。

**Organization**: 任务按用户故事组织，US1 和 US2 均可独立验收。

## Phase 1: Setup (Shared Test Fixtures)

**Purpose**: 固定 Apple Container CLI 1.3.1 的镜像与资源变更契约。

- [X] T001 [P] Add sanitized image list and inspect fixtures in Tests/ContainerGUITests/Fixtures/CLI/1.3.1/resources/images-list.json and Tests/ContainerGUITests/Fixtures/CLI/1.3.1/resources/image-inspect.json
- [X] T002 [P] Add pull/create success, nonzero, timeout and readback fixture cases in Tests/ContainerGUITests/Fixtures/CLI/1.3.1/resources/mutation-cases.json

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: 建立两个故事共享的校验模型、操作目标和安全摘要边界。

- [X] T003 [P] Add failing validation and secret-redaction tests for shared request models in Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift
- [X] T004 [P] Add failing image-target locking and readback tests in Tests/ContainerGUITests/Unit/OperationCoordinatorTests.swift
- [X] T005 Implement ImagePlatform, ImageSummary, ImagePullRequest, PortMapping, EnvironmentEntry and ContainerCreateRequest validation in Sources/ContainerGUI/Domain/ImageModels.swift and Sources/ContainerGUI/Domain/ContainerCreationModels.swift
- [X] T006 Extend operation kinds, image targets and observed-image readback without changing existing encodings in Sources/ContainerGUI/Domain/OperationModels.swift
- [X] T007 Add image-read and resource-mutation protocols plus separate pull timeout configuration in Sources/ContainerGUI/CLI/ContainerCLIClient.swift and Sources/ContainerGUI/App/AppConfiguration.swift

**Checkpoint**: 共享模型可独立编码、校验和测试，环境变量值不会进入安全摘要。

---

## Phase 3: User Story 1 - 拉取容器镜像 (Priority: P1) 🎯 MVP

**Goal**: 显示本机权威镜像列表，提交镜像拉取并用详情回读验证成功。

**Independent Test**: 只启用镜像夹具和模拟执行器，验证列表、拉取、重复提交、平台匹配、超时、非零退出和回读缺失；现有容器 API 仍通过。

### Tests for User Story 1

- [X] T008 [P] [US1] Add failing image JSON parser and fixed pull-command tests in Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift
- [X] T009 [P] [US1] Add failing GET /api/v1/images and POST /api/v1/images/pull contract tests in Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift
- [X] T010 [P] [US1] Add failing accessible image table, pull dialog and operation-status asset tests in Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift

### Implementation for User Story 1

- [X] T011 [US1] Parse CLI 1.3.1 image list and inspect JSON with unknown-field tolerance and required-field rejection in Sources/ContainerGUI/CLI/CLIModels.swift
- [X] T012 [US1] Implement listImages, inspectImage and pullImage using fixed argument arrays and authoritative readback in Sources/ContainerGUI/CLI/ContainerCLIClient.swift
- [X] T013 [US1] Implement idempotent pull orchestration, image locking and safe request summaries in Sources/ContainerGUI/Operations/ResourceMutationServices.swift
- [X] T014 [US1] Register image list and pull routes with existing safety middleware and operation polling in Sources/ContainerGUI/Web/ResourceMutationRoutes.swift and Sources/ContainerGUI/App/AppFactory.swift
- [X] T015 [US1] Add the image table, pull dialog, field errors and polling UI in Sources/ContainerGUI/Resources/Public/index.html, Sources/ContainerGUI/Resources/Public/app.css and Sources/ContainerGUI/Resources/Public/app.js
- [X] T016 [US1] Run focused unit, contract and browser tests and record the independent story result in specs/003-image-pull-create/verification-us1.md

**Checkpoint**: US1 可独立显示和拉取镜像，任何成功状态都有镜像回读。

---

## Phase 4: User Story 2 - 创建容器 (Priority: P2)

**Goal**: 用受控常用参数创建容器，可选在创建回读后启动，并显示最终容器状态。

**Independent Test**: 使用现有镜像和容器夹具，验证最小/完整创建参数、同名冲突、幂等重放、秘密不回显、创建回读缺失和可选启动状态不匹配。

### Tests for User Story 2

- [X] T017 [P] [US2] Add failing fixed create-command, option-order and invalid-input no-execution tests in Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift
- [X] T018 [P] [US2] Add failing POST /api/v1/containers idempotency, conflict, redaction, readback and optional-start contract tests in Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift
- [X] T019 [P] [US2] Add failing accessible create dialog, local-image suggestions, loopback-port and secret-field asset tests in Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift

### Implementation for User Story 2

- [X] T020 [US2] Implement the fixed create argument builder and post-create container readback in Sources/ContainerGUI/CLI/ContainerCLIClient.swift
- [X] T021 [US2] Implement create and optional-start orchestration with hashed idempotency fingerprint and secret-free summaries in Sources/ContainerGUI/Operations/ResourceMutationServices.swift
- [X] T022 [US2] Decode, validate and register POST /api/v1/containers in Sources/ContainerGUI/Web/ResourceMutationRoutes.swift and Sources/ContainerGUI/App/AppFactory.swift
- [X] T023 [US2] Add the create dialog, line-based inputs, validation feedback and final refresh in Sources/ContainerGUI/Resources/Public/index.html, Sources/ContainerGUI/Resources/Public/app.css and Sources/ContainerGUI/Resources/Public/app.js
- [X] T024 [US2] Run focused unit, contract and browser tests and record the independent story result in specs/003-image-pull-create/verification-us2.md

**Checkpoint**: US1 与 US2 均可独立运行；创建不会暴露秘密或开放非回环端口。

---

## Phase 5: Polish & Cross-Cutting Validation

**Purpose**: 完成兼容性、回归和文档门禁，不执行真实写操作。

- [X] T025 Extend the opt-in read-only smoke test with image list and inspect checks in Tests/ContainerGUITests/Integration/ReadOnlyCLISmokeTests.swift
- [X] T026 Run the full Swift suite, explicit read-only live test, browser form/readback verification and diff checks described in specs/003-image-pull-create/quickstart.md
- [X] T027 Mark implementation status and verification evidence in specs/003-image-pull-create/spec.md, specs/003-image-pull-create/tasks.md, specs/003-image-pull-create/verification-us1.md and specs/003-image-pull-create/verification-us2.md

---

## Phase 6: Registry Shortcuts

**Purpose**: 在不改变固定 CLI 命令边界的前提下，为镜像拉取提供 Docker Hub 与 GHCR 快捷选择。

- [X] T028 [US1] Add failing browser asset tests for Docker Hub/GHCR choices, architecture wording and resolved-reference submission in Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift
- [X] T029 [US1] Add registry selection, deterministic Docker Hub/GHCR reference resolution and field feedback in Sources/ContainerGUI/Resources/Public/index.html and Sources/ContainerGUI/Resources/Public/app.js
- [X] T030 [US1] Update registry shortcut rules and verification steps in specs/003-image-pull-create/spec.md, specs/003-image-pull-create/research.md, specs/003-image-pull-create/data-model.md, specs/003-image-pull-create/contracts/openapi.yaml and specs/003-image-pull-create/quickstart.md
- [X] T031 [US1] Run focused, full, explicit read-only CLI, browser resolver and diff validation, and record both the result and the live-pull boundary incident in specs/003-image-pull-create/verification-us1.md

---

## Dependencies & Execution Order

### Phase Dependencies

- Phase 1 has no dependencies.
- Phase 2 depends on Phase 1 and blocks both user stories.
- US1 and US2 both depend on Phase 2; implementation proceeds P1 then P2 for this single-agent run.
- Phase 5 depends on both stories.

### User Story Dependencies

- **US1**: No dependency on US2; uses image-specific models and routes.
- **US2**: Does not require a newly pulled image; it can use any existing reference. It reuses shared validation and operation infrastructure only.

### Within Each User Story

- Failing tests precede implementation.
- Domain/CLI behavior precedes orchestration and routes.
- Routes precede static UI integration.
- Each checkpoint must pass before the next story begins.

### Parallel Opportunities

- T001 and T002 touch separate fixture files.
- T003 and T004 touch separate unit-test files.
- Within US1, T008-T010 touch separate test files.
- Within US2, T017-T019 touch separate test files.

## Parallel Example: User Story 1

```text
T008: Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift
T009: Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift
T010: Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift
```

## Implementation Strategy

### MVP First

1. Complete shared fixtures and models.
2. Implement US1 image list and pull.
3. Stop and independently validate US1.
4. Implement US2 create and optional start.
5. Run all cross-cutting gates and commit the complete feature.

### Safety Rules

- Never run real `container image pull`, `container create` or `container start` during automated validation.
- Use only fixed CLI 1.3.1 fixtures for write paths.
- Real mutation acceptance remains a separate user-authorized step after implementation.
