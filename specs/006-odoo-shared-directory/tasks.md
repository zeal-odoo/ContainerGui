# Tasks: Odoo 与通用共享目录

**Input**: Design documents from `/specs/006-odoo-shared-directory/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/openapi.yaml, quickstart.md

**Tests**: 本功能受宪章测试先行门禁约束；每个故事先添加失败测试，再做最小实现。

**Organization**: Tasks are grouped by user story so each story remains independently testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it touches a different file and has no incomplete dependency
- **[Story]**: Maps to the user story in `spec.md`
- Every task names its exact file path

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish a recorded clean baseline without changing real containers.

- [X] T001 Run the existing Swift and Node test suites and record baseline evidence in `specs/006-odoo-shared-directory/verification.md`
- [X] T002 Confirm the current CLI 1.3.1 mount contract and Odoo 19 image metadata using read-only commands, then record results in `specs/006-odoo-shared-directory/verification.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add the smallest shared request concepts and test seams needed by every story.

- [X] T003 [P] Add failing decoding, equality, safe-summary redaction, and backward-compatibility tests for optional `sharedDirectory` and `odooDatabase` fields in `Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift`
- [X] T004 [P] Add failing HTTP contract tests proving new values reach the stub manager but host paths and database endpoint values never appear in operation responses in `Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift`
- [X] T005 Add minimal optional shared-directory and Odoo-database request entities with default-nil decoding and redacted summaries in `Sources/ContainerGUI/Domain/ContainerCreationModels.swift`

**Checkpoint**: New optional objects decode safely, old request bodies remain valid, and response redaction is defined before CLI behavior changes.

---

## Phase 3: User Story 1 - 为任意容器共享本机目录 (Priority: P1) 🎯 MVP

**Goal**: Any image can receive one optional read-write host-directory mount with `/workspace` as the generic UI default.

**Independent Test**: Submit a generic-image request using a temporary host directory and confirm the fixed executor receives one bind mount; invalid, file, root, relative and absent paths fail before executor invocation; an omitted mount preserves the old command.

### Tests for User Story 1

- [X] T006 [P] [US1] Add failing path validation and exact `--mount` CLI argument tests using temporary directories in `Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift`
- [X] T007 [P] [US1] Add failing browser asset assertions for host path, editable generic target, `/workspace` default, help text and field-error routing in `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift`
- [X] T008 [P] [US1] Add failing HTTP test proving an invalid shared directory is rejected before the stub manager is called in `Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift`

### Implementation for User Story 1

- [X] T009 [US1] Implement absolute-path, dangerous-component and existing-directory validation in `Sources/ContainerGUI/Domain/ContainerCreationModels.swift`
- [X] T010 [US1] Emit one fixed read-write bind mount argument before the image and preserve the old command when absent in `Sources/ContainerGUI/CLI/ContainerCLIClient.swift`
- [X] T011 [US1] Add the generic shared-directory controls and accessible error targets to `Sources/ContainerGUI/Resources/Public/index.html`
- [X] T012 [US1] Build and validate `sharedDirectory` only when a host path is supplied, using generic `/workspace`, in `Sources/ContainerGUI/Resources/Public/app.js`

**Checkpoint**: The generic mount flow passes independently without any Odoo-specific configuration.

---

## Phase 4: User Story 2 - Odoo 自定义模块目录预设 (Priority: P1)

**Goal**: Exact official Odoo references switch the shared-directory purpose and force `/mnt/extra-addons`; similarly named images remain generic.

**Independent Test**: Exercise short, canonical, tagged and digested official references plus third-party lookalikes in Swift and Node tests; verify only official references produce the fixed addons target and Odoo UI state.

### Tests for User Story 2

- [X] T013 [P] [US2] Add failing official-reference and lookalike classification plus fixed-target server validation tests in `Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift`
- [X] T014 [P] [US2] Add failing pure frontend classification and derived form-mode tests in `Tests/Frontend/OdooCreateFormTests.mjs`
- [X] T015 [P] [US2] Extend browser asset assertions for the Odoo section label, fixed `/mnt/extra-addons` target and image-change listener in `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift`

### Implementation for User Story 2

- [X] T016 [US2] Implement exact official Odoo repository classification and fixed-target enforcement in `Sources/ContainerGUI/Domain/ContainerCreationModels.swift`
- [X] T017 [US2] Add a dependency-free shared frontend classification helper in `Sources/ContainerGUI/Resources/Public/odoo-create-form.js`
- [X] T018 [US2] Include the helper and add Odoo-specific directory labels and target state in `Sources/ContainerGUI/Resources/Public/index.html`
- [X] T019 [US2] Switch directory purpose and target safely when the selected image changes in `Sources/ContainerGUI/Resources/Public/app.js`

**Checkpoint**: Official Odoo custom addons behavior works while third-party and generic images remain unchanged.

---

## Phase 5: User Story 3 - 仅为 Odoo 配置数据库端点 (Priority: P2)

**Goal**: Only the official Odoo mode exposes and accepts database host/port and translates them to `HOST`/`PORT` without leaking values.

**Independent Test**: Submit a valid Odoo request and confirm fixed CLI env arguments; invalid host/port, non-Odoo requests and duplicate generic env names fail before executor invocation; UI fields are hidden for generic images.

### Tests for User Story 3

- [X] T020 [P] [US3] Add failing Odoo database validation, environment-conflict and CLI argument-order tests in `Tests/ContainerGUITests/Unit/ImageAndCreationCLITests.swift`
- [X] T021 [P] [US3] Add failing API rejection tests for non-Odoo, invalid endpoint and duplicate `HOST`/`PORT` requests in `Tests/ContainerGUITests/Contract/ResourceMutationAPITests.swift`
- [X] T022 [P] [US3] Add failing browser and frontend tests for Odoo-only visibility, `db:5432` defaults and structured request shape in `Tests/ContainerGUITests/Browser/ResourceMutationAssetTests.swift` and `Tests/Frontend/OdooCreateFormTests.mjs`

### Implementation for User Story 3

- [X] T023 [US3] Implement Odoo endpoint validation, non-Odoo rejection and `HOST`/`PORT` conflict handling in `Sources/ContainerGUI/Domain/ContainerCreationModels.swift`
- [X] T024 [US3] Emit validated Odoo `HOST` and `PORT` arguments without changing generic environments in `Sources/ContainerGUI/CLI/ContainerCLIClient.swift`
- [X] T025 [US3] Add the Odoo-only database host/port fieldset and errors in `Sources/ContainerGUI/Resources/Public/index.html`
- [X] T026 [US3] Derive visibility, validate endpoint fields and submit `odooDatabase` only for official Odoo images in `Sources/ContainerGUI/Resources/Public/app.js`

**Checkpoint**: All three stories pass independently, and database configuration cannot cross the Odoo image boundary.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Complete version, documentation, visible acceptance, and Git gates.

- [X] T027 [P] Update expected application version tests to 2.8.0 in `Tests/ContainerGUITests/Unit/AppVersionTests.swift`
- [X] T028 Set the application version to 2.8.0 in `Sources/ContainerGUI/App/AppVersion.swift`
- [X] T029 Run `swift test`, all `Tests/Frontend/*.mjs`, `git diff --check`, and read-only CLI checks; append results to `specs/006-odoo-shared-directory/verification.md`
- [X] T030 Start the updated service, inspect the generic and Odoo create-dialog states without submitting, and record visible version/field evidence in `specs/006-odoo-shared-directory/verification.md`
- [X] T031 Review the complete diff for scope, secrets and destructive commands, then create one semantic-versioned Git commit and push `main` to the configured GitHub origin

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependency and no mutation.
- **Foundational (Phase 2)**: Depends on Setup and blocks request-shape implementation.
- **US1 (Phase 3)**: Depends on Foundational; supplies the generic mount foundation.
- **US2 (Phase 4)**: Depends on US1 because it specializes the same mount target.
- **US3 (Phase 5)**: Depends on US2 because it reuses exact official Odoo classification.
- **Polish (Phase 6)**: Depends on all stories.

### User Story Dependencies

- **US1**: Independently usable after Foundational; no Odoo behavior required.
- **US2**: Extends US1 only by deriving the official Odoo target and label.
- **US3**: Uses the classification delivered by US2 but remains independently testable through endpoint requests.

### Within Each User Story

- Add and run failing tests before implementation.
- Domain validation precedes CLI and UI submission behavior.
- CLI shape and server contract pass before browser acceptance.
- Do not use the real create endpoint during automated or visual tests.

### Parallel Opportunities

- T003 and T004 touch separate test layers.
- T006, T007 and T008 define US1 failures in separate files.
- T013, T014 and T015 define US2 failures in Swift, Node and asset tests.
- T020, T021 and T022 define US3 failures in separate test layers.
- T027 can be prepared independently before T028, but the final full suite waits for both.

## Parallel Examples

### User Story 1

```text
T006: Unit tests for shared-directory validation and CLI shape
T007: Browser asset tests for generic controls
T008: HTTP pre-mutation rejection test
```

### User Story 2

```text
T013: Swift official-image classification tests
T014: Node derived form-mode tests
T015: Static asset integration assertions
```

### User Story 3

```text
T020: Domain and CLI endpoint tests
T021: HTTP boundary rejection tests
T022: Browser visibility and request-shape tests
```

## Implementation Strategy

### MVP First

1. Complete T001-T005.
2. Complete T006-T012 for the generic one-directory mount.
3. Stop and validate US1 without Odoo assumptions.

### Incremental Delivery

1. Add US2 exact Odoo addons behavior and re-run US1 regression.
2. Add US3 structured database endpoint and rejection boundary.
3. Bump v2.8.0 only after all stories pass.
4. Perform browser-only visual inspection, then create and push one commit.

## Notes

- All 31 tasks follow the required checkbox, sequential ID, optional `[P]`, story label and file-path format.
- Tests and browser validation must not submit a real create request.
- No task authorizes creating directories, containers, volumes or networks on the user's behalf.
- The only Git commit for this logical update includes specification, implementation, tests, verification and version bump.
