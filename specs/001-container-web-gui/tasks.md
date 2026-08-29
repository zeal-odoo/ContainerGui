---

description: "Implementation tasks for the Apple Container Web GUI"
---

# Tasks: Apple Container Web GUI

**Input**: Design documents from `specs/001-container-web-gui/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/openapi.yaml`,
`quickstart.md`

**Tests**: Required by the project constitution. In each phase, write the named tests first, run them to
confirm the intended failure, then perform only the implementation needed to pass.

**Organization**: Tasks are grouped by user story so each slice can be demonstrated and accepted separately.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it owns different files and has no unmet dependency in the phase.
- **[Story]**: Maps the task to a user story from `spec.md`.
- Every task names its exact target file or files.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the minimal Swift package and static resource layout without feature behavior.

- [X] T001 Create the Swift 6 executable/test targets, Hummingbird 2.26 dependency, strict concurrency settings, and copied Public resource rule in `Package.swift`
- [X] T002 [P] Ignore only local/build artifacts (`.DS_Store`, `.build/`, `.swiftpm/`, `.env`) in `.gitignore`
- [X] T003 [P] Document prerequisites, local-only boundary, build/test/run commands, and non-production status in `README.md`
- [X] T004 [P] Create the accessible Chinese application shell and no-build asset entry points in `Sources/ContainerGUI/Resources/Public/index.html`, `Sources/ContainerGUI/Resources/Public/app.css`, and `Sources/ContainerGUI/Resources/Public/app.js`

**Checkpoint**: `swift package describe` resolves one executable and one test target; no service or real CLI command runs yet.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the safe process, error, operation and HTTP foundation required by every story.

**CRITICAL**: No user-story implementation begins until T020 passes.

### Failing tests first

- [X] T005 [P] Write failing tests for fixed loopback host, allowed port range, body/output limits, timeouts, and CLI path configuration in `Tests/ContainerGUITests/Unit/AppConfigurationTests.swift`
- [X] T006 [P] Write failing tests for concurrent stdout/stderr draining, timeout, cancellation, invalid UTF-8 preservation, output limits, and exit capture in `Tests/ContainerGUITests/Unit/FoundationProcessExecutorTests.swift`
- [X] T007 [P] Write failing tests for missing/non-executable CLI, version 1.3.1 support, unsupported major/minor versions, and unrecognized version text in `Tests/ContainerGUITests/Unit/CLIVersionResolverTests.swift`
- [X] T008 [P] Write failing tests for stable problem codes, Chinese safe messages, diagnostic IDs, field errors, and secret-free encoding in `Tests/ContainerGUITests/Unit/ProblemDetailTests.swift`
- [X] T009 [P] Write failing tests for idempotency replay/conflict, per-target serialization, global mutation limit, legal state transitions, TTL eviction, and mandatory readback in `Tests/ContainerGUITests/Unit/OperationCoordinatorTests.swift`
- [X] T010 [P] Write failing HTTP tests for same-origin JSON mutation enforcement, missing/mismatched Origin, request-size limit, no CORS, CSP, frame and content-sniffing headers in `Tests/ContainerGUITests/Contract/SafetyMiddlewareTests.swift`

### Minimal implementation

- [X] T011 Implement immutable `127.0.0.1` binding, port/limit/timeout constants, and startup validation in `Sources/ContainerGUI/App/AppConfiguration.swift`
- [X] T012 [P] Implement recursive Codable JSON, problem envelopes, diagnostic IDs, and case-insensitive secret redaction in `Sources/ContainerGUI/Domain/JSONValue.swift` and `Sources/ContainerGUI/Domain/ProblemDetail.swift`
- [X] T013 [P] Define typed `CommandRequest`, `CommandResult`, streaming events, cancellation and the injectable `CommandExecuting` protocol in `Sources/ContainerGUI/CLI/CommandExecuting.swift`
- [X] T014 Implement the bounded asynchronous `Foundation.Process` runner with separate stdout/stderr drains, timeout and cooperative termination in `Sources/ContainerGUI/CLI/FoundationProcessExecutor.swift`
- [X] T015 Implement executable resolution, 1.3.1 compatibility classification and typed CLI-to-problem error mapping in `Sources/ContainerGUI/CLI/CLIError.swift` and `Sources/ContainerGUI/CLI/CLIVersionResolver.swift`
- [X] T016 [P] Implement secret-free operation, target, state and readback models in `Sources/ContainerGUI/Domain/OperationModels.swift`
- [X] T017 Implement the actor-isolated idempotency store, per-target locks, four-process limiter, state machine and TTL eviction in `Sources/ContainerGUI/Operations/OperationCoordinator.swift`
- [X] T018 Implement problem conversion, same-origin/body-limit safety checks and response security headers in `Sources/ContainerGUI/Web/ErrorMiddleware.swift` and `Sources/ContainerGUI/Web/SafetyMiddleware.swift`
- [X] T019 Compose dependency injection, static resource serving, base API group and structured secret-free logging in `Sources/ContainerGUI/App/AppFactory.swift` and `Sources/ContainerGUI/main.swift`
- [X] T020 Run `swift test` and make all Phase 2 tests pass without weakening assertions or invoking any real mutation; record the command/result in `specs/001-container-web-gui/verification/foundation.md`

**Checkpoint**: The service can start locally and serve its static shell; fake executors prove safety, limits and errors.

---

## Phase 3: User Story 1 - 一眼看清运行状态 (Priority: P1)

**Goal**: Display tool/service health, all containers and a redacted container detail sourced from fresh CLI reads.

**Independent Test**: With only fixture-backed queries, the user can distinguish healthy/stopped/missing service
states, see a mixed or empty list, open one detail and refresh to a changed authoritative snapshot.

### Failing tests first

- [X] T021 [P] [US1] Add sanitized CLI 1.3.1 fixtures `system-healthy.json`, `system-stopped.json`, `system-unregistered.json`, `system-nonzero.json`, `containers-mixed.json`, `containers-empty.json`, `container-detail.json`, `containers-unknown-fields.json`, `containers-missing-id.json`, and `containers-malformed.txt` in `Tests/ContainerGUITests/Fixtures/CLI/1.3.1/`
- [X] T022 [US1] Write failing parser/normalization tests against every US1 fixture, including unknown-field tolerance and redaction, in `Tests/ContainerGUITests/Unit/ContainerCLIReadTests.swift`
- [X] T023 [P] [US1] Write failing OpenAPI-aligned tests for `GET /system/health`, `GET /containers`, `GET /containers/{id}`, empty state and error envelopes in `Tests/ContainerGUITests/Contract/ContainerReadAPITests.swift`
- [X] T024 [P] [US1] Write failing asset contract tests for Chinese labels, semantic landmarks, keyboard-focusable refresh/detail controls and loading/empty/error regions in `Tests/ContainerGUITests/Browser/DashboardAssetTests.swift`

### Implementation

- [X] T025 [P] [US1] Implement `CLIInstallation`, `SystemHealth`, `ContainerSummary`, `ContainerDetail`, state normalization and redacted raw detail models in `Sources/ContainerGUI/Domain/ContainerModels.swift`
- [X] T026 [US1] Implement the typed `--version`, `system status --format json`, `list --all --format json`, and `inspect` methods with 5-second/16-MiB bounds in `Sources/ContainerGUI/CLI/ContainerCLIClient.swift` and `Sources/ContainerGUI/CLI/CLIModels.swift`
- [X] T027 [US1] Implement US1 health/list/detail routes and exact problem/status mappings in `Sources/ContainerGUI/Web/ContainerReadRoutes.swift`
- [X] T028 [US1] Implement dashboard rendering, five-second visible-page refresh, manual refresh, detail/raw panels and accessible state regions in `Sources/ContainerGUI/Resources/Public/index.html`, `Sources/ContainerGUI/Resources/Public/app.css`, and `Sources/ContainerGUI/Resources/Public/app.js`
- [X] T029 [US1] Add opt-in real CLI version/status/list/detail read-only compatibility coverage guarded by `CONTAINER_GUI_LIVE_READONLY=1` in `Tests/ContainerGUITests/Integration/ReadOnlyCLISmokeTests.swift`
- [X] T030 [US1] Execute all US1 tests plus the read-only quickstart comparison and record page/CLI timestamps, version and results in `specs/001-container-web-gui/verification/us1-read-status.md`

**Checkpoint**: US1 is independently usable as a read-only GUI and no container mutation route exists.

---

## Phase 4: User Story 2 - 控制现有容器并查看日志 (Priority: P2)

**Goal**: Safely start/stop one existing container, poll operation verification and view bounded recent/live logs.

**Independent Test**: A fake executor and one explicitly disposable live container complete start, log and stop;
every success contains a new authoritative readback and a disconnected log stream terminates its child process.

### Failing tests first

- [X] T031 [P] [US2] Add sanitized control cases to `Tests/ContainerGUITests/Fixtures/CLI/1.3.1/control/control-cases.json` and byte-stream samples to `Tests/ContainerGUITests/Fixtures/CLI/1.3.1/control/logs-invalid-utf8.bin` and `Tests/ContainerGUITests/Fixtures/CLI/1.3.1/control/logs-oversized.txt` for success, stderr, timeout, unchanged/external state, disconnect and backpressure scenarios
- [X] T032 [US2] Write failing command-shape and readback tests proving exact IDs, no shell/`--all`/`--force`, 10-second graceful stop and success-after-verification only in `Tests/ContainerGUITests/Unit/ContainerCLIControlTests.swift`
- [X] T033 [P] [US2] Write failing contract tests for start/stop acceptance, target confirmation, idempotent replay/conflict, same-target conflict and operation polling in `Tests/ContainerGUITests/Contract/ContainerControlAPITests.swift`
- [X] T034 [P] [US2] Write failing tests for recent logs, SSE log/warning/end events, 15-second keepalive, eight-session limit, bounded backpressure and disconnect cancellation in `Tests/ContainerGUITests/Contract/ContainerLogsAPITests.swift`
- [X] T035 [P] [US2] Write failing asset contract tests for legal-action visibility, target confirmation modal, disabled duplicate submit, operation progress and reconnectable log viewer in `Tests/ContainerGUITests/Browser/ContainerControlAssetTests.swift`

### Implementation

- [X] T036 [US2] Implement typed start, graceful stop, recent-log and follow-log CLI methods without raw argument entry in `Sources/ContainerGUI/CLI/ContainerCLIClient.swift`
- [X] T037 [US2] Implement operation creation, idempotent lookup, polling and final readback route support in `Sources/ContainerGUI/Web/OperationRoutes.swift`
- [X] T038 [US2] Implement bounded SSE encoding, replacement of invalid UTF-8, keepalive/drop/end events and disconnect cleanup in `Sources/ContainerGUI/Web/LogEventStream.swift`
- [X] T039 [US2] Implement state-gated start/stop and recent/follow log endpoints from the OpenAPI contract in `Sources/ContainerGUI/Web/ContainerControlRoutes.swift`
- [X] T040 [US2] Add start/stop confirmation, operation polling, recent log display, follow/reconnect/stop controls and error differentiation in `Sources/ContainerGUI/Resources/Public/index.html`, `Sources/ContainerGUI/Resources/Public/app.css`, and `Sources/ContainerGUI/Resources/Public/app.js`
- [ ] T041 [US2] Run all US2 fake tests, then perform the explicitly authorized disposable-container browser flow from `quickstart.md` and record independent CLI readbacks in `specs/001-container-web-gui/verification/us2-control-logs.md`

**Checkpoint**: US1 + US2 form the minimum usable MVP. Stop here for first product review before lifecycle work.

---

## Phase 5: User Story 3 - 安全创建和删除容器 (Priority: P3)

**Goal**: Preview and run a constrained container configuration, then delete only an explicitly confirmed stopped target.

**Independent Test**: A known disposable image is previewed without secret values, run once, stopped and deleted;
the final authoritative list confirms absence and unrelated containers are unchanged.

### Failing tests first

- [ ] T042 [P] [US3] Write failing boundary/property tests for image/name, 32 ports, 128 unique environment names, absolute mounts, read-only defaults, CPU/memory bounds and secret-free preview in `Tests/ContainerGUITests/Unit/RunConfigurationTests.swift`
- [ ] T043 [P] [US3] Write failing exact argument-array tests for deterministic `run --detach` construction, no raw arguments, no logged environment values, returned-ID parsing and no-force delete in `Tests/ContainerGUITests/Unit/ContainerCLILifecycleTests.swift`
- [ ] T044 [P] [US3] Write failing contract tests for preview, validation field errors, run idempotency/progress, running-delete rejection, exact target confirmation and absence readback in `Tests/ContainerGUITests/Contract/ContainerLifecycleAPITests.swift`
- [ ] T045 [P] [US3] Write failing asset contract tests for form labels/constraints, secret handling, normalized preview/warnings and delete confirmation in `Tests/ContainerGUITests/Browser/ContainerLifecycleAssetTests.swift`

### Implementation

- [ ] T046 [US3] Implement `RunConfiguration`, `PortMapping`, `EnvironmentEntry`, `Mount` and secret-free `RunPreview` validation models in `Sources/ContainerGUI/Domain/RunConfiguration.swift`
- [ ] T047 [US3] Implement deterministic safe run-argument construction and redacted request summaries in `Sources/ContainerGUI/CLI/RunCommandBuilder.swift`
- [ ] T048 [US3] Implement bounded background run plus stopped-only non-force delete and mandatory list/inspect readback in `Sources/ContainerGUI/CLI/ContainerCLIClient.swift`
- [ ] T049 [US3] Implement preview, run and delete endpoints with validation, warnings, idempotency and exact target checks in `Sources/ContainerGUI/Web/ContainerLifecycleRoutes.swift`
- [ ] T050 [US3] Implement the accessible run form, preview step, progress, field errors, secret clearing and stopped-only delete flow in `Sources/ContainerGUI/Resources/Public/index.html`, `Sources/ContainerGUI/Resources/Public/app.css`, and `Sources/ContainerGUI/Resources/Public/app.js`
- [ ] T051 [US3] Run all US3 tests and the explicitly authorized disposable lifecycle flow, then record final list readback and unaffected-resource evidence in `specs/001-container-web-gui/verification/us3-lifecycle.md`

**Checkpoint**: US3 is independently accepted; force delete and advanced CLI flags remain unavailable.

---

## Phase 6: User Story 4 - 恢复容器系统服务 (Priority: P4)

**Goal**: Start stopped container services safely, separating ordinary start from confirmed kernel installation.

**Independent Test**: In an isolated service-stopped environment, the page starts the system without an interactive
prompt, or requests a separate install confirmation and verifies final health; exit zero without health fails.

### Failing tests first

- [ ] T052 [P] [US4] Write failing command/readback tests for `--disable-kernel-install`, confirmed `--enable-kernel-install`, timeouts, non-zero output and exit-zero/unhealthy status in `Tests/ContainerGUITests/Unit/ContainerCLISystemStartTests.swift`
- [ ] T053 [P] [US4] Write failing contract tests for ordinary start, `system:install-kernel` confirmation, idempotency/conflict, progress and final health in `Tests/ContainerGUITests/Contract/SystemStartAPITests.swift`
- [ ] T054 [P] [US4] Write failing asset contract tests for stopped-service recovery, installation impact warning, separate confirmation and diagnostic failure state in `Tests/ContainerGUITests/Browser/SystemRecoveryAssetTests.swift`

### Implementation

- [ ] T055 [US4] Implement ordinary and confirmed-kernel system-start methods plus final structured health readback in `Sources/ContainerGUI/CLI/ContainerCLIClient.swift`
- [ ] T056 [US4] Implement the system-start route, reserved system operation lock and confirmation rules in `Sources/ContainerGUI/Web/SystemRoutes.swift`
- [ ] T057 [US4] Implement the recovery panel, progress polling, install warning/confirmation and final health display in `Sources/ContainerGUI/Resources/Public/index.html`, `Sources/ContainerGUI/Resources/Public/app.css`, and `Sources/ContainerGUI/Resources/Public/app.js`
- [ ] T058 [US4] Run all US4 fake tests and an explicitly authorized isolated recovery test, recording CLI exit and independent health readback in `specs/001-container-web-gui/verification/us4-system-recovery.md`

**Checkpoint**: All four stories are independently functional; system stop and first-time product installation remain out of scope.

---

## Phase 7: Polish & Cross-Cutting Verification

**Purpose**: Prove contract alignment, security, bounded behavior and handoff quality without expanding scope.

- [ ] T059 [P] Add a route/schema parity test covering every path and stable error code in `contracts/openapi.yaml` in `Tests/ContainerGUITests/Contract/OpenAPIParityTests.swift`
- [ ] T060 [P] Add regression tests for 100-container response timing, 16-MiB output rejection, 64-KiB request rejection, operation cap/TTL and log-buffer drops in `Tests/ContainerGUITests/Integration/BoundedResourceTests.swift`
- [ ] T061 [P] Add whole-response secret scans for fixtures, logs, operation summaries, problems and redacted raw details in `Tests/ContainerGUITests/Integration/SecretLeakTests.swift`
- [ ] T062 Update actual build/run, troubleshooting, compatibility and explicit live-write authorization instructions after implementation in `README.md` and `specs/001-container-web-gui/quickstart.md`
- [ ] T063 Run the complete clean-checkout quickstart, `swift test`, opt-in read-only live tests and browser acceptance; record versions, counts, timings and remaining out-of-scope items in `specs/001-container-web-gui/verification/final.md`

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001-T004)**: no prior dependency.
- **Foundational (T005-T020)**: depends on Setup and blocks every user story.
- **US1 (T021-T030)**: depends on Foundational; no dependency on later stories.
- **US2 (T031-T041)**: depends on Foundational and reuses US1 container identity/detail UI. It may be coded in
  parallel after Foundation, but final acceptance T041 requires US1 list/detail navigation.
- **US3 (T042-T051)**: depends on Foundational and uses the Operation contract; acceptance requires the US1 list
  and US2 normal-stop behavior.
- **US4 (T052-T058)**: depends on Foundational and Operation contract; its fake tests can proceed independently,
  while live acceptance requires an isolated environment.
- **Polish (T059-T063)**: run after all stories selected for the release. For MVP review, run applicable checks after US2.

### Within each story

1. Add fixtures and tests; run the focused test command and confirm the expected failure.
2. Implement domain models and command client behavior.
3. Implement API routes and server-side safety/readback.
4. Implement the browser slice.
5. Run focused automated tests.
6. Perform only the explicitly authorized manual/live scenario and record independent readback.

### Parallel opportunities

- T002, T003 and T004 can run in parallel after T001 establishes package paths.
- Foundation test files T005-T010 can be authored in parallel; model/protocol tasks T012, T013 and T016 own
  separate files and can follow in parallel.
- In each story, the `[P]` test tasks own separate files and can be authored simultaneously before implementation.
- US3 validation/model work and US4 fake command research may start after Foundation, but shared edits to
  `ContainerCLIClient.swift` and browser assets must be serialized.

## Parallel Example: User Story 1

```text
Task T021: Add sanitized CLI fixtures under Tests/ContainerGUITests/Fixtures/CLI/1.3.1/
Task T023: Add read API contract tests in Tests/ContainerGUITests/Contract/ContainerReadAPITests.swift
Task T024: Add dashboard asset tests in Tests/ContainerGUITests/Browser/DashboardAssetTests.swift
```

After T021 completes, T022 consumes those fixtures. After the failing tests are confirmed, T025 and T026 establish
the model/client, then T027 and T028 complete the API/browser slice.

## Implementation Strategy

### Reviewable read-only slice

1. Complete Setup and Foundation.
2. Complete US1.
3. Stop and demonstrate the read-only dashboard before enabling mutation routes.

### Minimum usable MVP

1. Accept US1.
2. Complete and accept US2 on a disposable container.
3. Run T059-T063 only for the implemented US1/US2 surface.
4. Stop for product review. Do not silently continue into create/delete or system installation behavior.

### Incremental delivery

1. Foundation -> safe local service.
2. US1 -> read-only dashboard.
3. US2 -> usable management MVP.
4. US3 -> basic container lifecycle.
5. US4 -> system recovery.

Each checkpoint retains the local-only, no-arbitrary-command and post-mutation-readback boundaries.

## Task Summary

| Area | Tasks |
|------|------:|
| Setup | 4 |
| Foundation | 16 |
| US1 | 10 |
| US2 | 11 |
| US3 | 10 |
| US4 | 7 |
| Polish | 5 |
| **Total** | **63** |
