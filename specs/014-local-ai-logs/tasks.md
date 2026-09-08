# Tasks: Optional local AI log analysis

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/api.md, quickstart.md.
**Tests**: Required, tests before code; synthetic fixtures before live readonly checks.

## Phase 1: Setup

- [X] T001 Create and validate feature documents in specs/014-local-ai-logs/.
- [X] T002 Verify existing ignore rules in .gitignore exclude .build model/testing artifacts; establish fixed native worker/API contracts.

## Phase 2: Foundational

- [X] T003 Research exact CoreML shapes, tokenizer and model revision in specs/014-local-ai-logs/research.md; resolve native implementation feasibility.
- [X] T004 [P] Write failing tokenizer/model protocol tests in Tests/ContainerGUITests/Unit/QwenTokenizerTests.swift.
- [X] T005 [P] Write failing model verification/download tests in Tests/ContainerGUITests/Unit/AIModelStoreTests.swift.
- [X] T006 [P] Write failing lifecycle/redaction/service contracts in Tests/ContainerGUITests/Unit/AILogServiceTests.swift.

## Phase 3: US1 Local analysis

**Goal**: Fixed model loads locally and renders bounded advisory results.
**Independent test**: Synthetic known failure produces relevant real-model answer; API/UI fixtures pass.

- [X] T007 [P] [US1] Implement fixed model store/download manifest in Sources/ContainerGUI/AI/AIModelStore.swift and AIModelCatalog.swift.
- [X] T008 [P] [US1] Implement native tokenizer/CoreML worker in Sources/ContainerGUI/AI/QwenTokenizer.swift, QwenLogModel.swift and AILogWorker.swift.
- [X] T009 [US1] Implement parent service and safe prompt evidence in Sources/ContainerGUI/AI/AILogService.swift and AILogEvidence.swift.
- [X] T010 [US1] Implement APIs and entry wiring in Sources/ContainerGUI/Web/AILogRoutes.swift, App/AppFactory.swift and executable entry.
- [X] T011 [P] [US1] Add failing UI tests in Tests/Frontend/AILogTests.mjs then bilingual UI in Resources/Public/ai-logs.js and existing HTML/CSS/i18n/app hooks.
- [X] T012 [US1] Run actual-model smoke and record quality/load/footprint in specs/014-local-ai-logs/validation.md.

## Phase 4: US2 Verified shutdown

**Goal**: Disabled means no model process remains, not hidden UI.
**Independent test**: Mock unresponsive child and actual generation cancellation; repeat toggles.

- [X] T013 [US2] Implement bounded verified termination and stale generation guards in Sources/ContainerGUI/AI/AIWorkerProcess.swift and AILogService.swift.
- [X] T014 [US2] Test loading/generation disable, EOF, lease, rapid toggles in Tests/ContainerGUITests/Unit/AIWorkerProcessTests.swift and AILogServiceTests.swift.

## Phase 5: US3 Resources and safety

**Goal**: Low-memory/corrupt/hostile input fails safely without breaking GUI.
**Independent test**: Memory gate, one inference, fixed downloads, injection/oversize fixtures.

- [X] T015 [US3] Test API Host/Origin and validation in Tests/ContainerGUITests/Contract/AILogAPITests.swift; verify download corruption and bounds in AIModelStoreTests.swift.
- [X] T016 [US3] Validate plain-text output, evidence redaction, finite queues/input/output and available-memory failure handling in Sources/ContainerGUI/AI/ and Resources/Public/ai-logs.js.

## Final Phase: Integration and handoff

- [X] T017 Update bilingual usage/limitations/attribution in README.md and specs/014-local-ai-logs/validation.md.
- [X] T018 Run full Swift/Node tests and browser lifecycle/localization/narrow-layout checks; verify running container states unchanged.
- [X] T019 Increment Sources/ContainerGUI/App/AppVersion.swift to2.21.0, inspect diff, run git diff --check and create focused local commit; no push.

## Dependencies & Execution

Setup and research precede implementation. Tests precede their components. After test contracts, native worker, fixed installer and UI fixtures can run in parallel in separate files. US1 integration depends on real worker feasibility; US2 shares service but has independently testable child fixtures. US3 validates all failure boundaries. Final integration waits for all stories. Main owns service/API/wiring/spec/version, worker lane owns inference/tokenizer, installer lane owns fixed downloads, UI lane owns frontend. No shared-file reverts or extra services.
