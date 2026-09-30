# Tasks: Unified container connections

**Input**: `specs/018-container-connections/` design documents. Tests required by constitution/spec. One focused feature commit after all verification; no publication.

## Phase 1: Setup

- [X] T001 Inspect working tree and preserve unrelated Tests/Frontend/ContainerAddressTests.mjs.
- [X] T002 Complete research/design and requirements gate in specs/018-container-connections/plan.md and checklists/requirements.md.

## Phase 2: Foundation

- [X] T003 Write failing bounded file safety/validation tests in Tests/ContainerGUITests/Unit/ContainerConnectionTests.swift.
- [X] T004 Define endpoint models and reusable safe host-data transforms in Sources/ContainerGUI/Domain/ContainerConnectionModels.swift and Operations/OdooConfigurationFile.swift.

## Phase 3: US1 - Universal entry (P1)

Goal: every container can open an honest connection view. Independent test: unrelated/stopped/unsafe fixtures return restrictions with no mutation.

- [X] T005 [P] [US1] Write failing API recognition/unsupported tests in Tests/ContainerGUITests/Contract/ContainerConnectionAPITests.swift.
- [X] T006 [P] [US1] Write failing universal-entry/late-response/draft tests in Tests/Frontend/ContainerConnectionTests.mjs.
- [X] T007 [US1] Implement unified read service, routes and shared wiring in Sources/ContainerGUI/Operations/ContainerConnectionService.swift, Web/ContainerControlRoutes.swift and App/AppFactory.swift.
- [X] T008 [US1] Add universal dialog/entry and bilingual limitations in Sources/ContainerGUI/Resources/Public/app.js, index.html, odoo-database.js and i18n.js.

## Phase 4: US2 - Database endpoint (P2)

Goal: literal DB settings and Odoo remain safe. Independent test: fixture save preserves secrets/bytes and replay dispatches once.

- [X] T009 [US2] Write failing dotenv/Odoo delegate/idempotency/revision/lock tests in Tests/ContainerGUITests/Unit/ContainerConnectionTests.swift and Contract/ContainerConnectionAPITests.swift.
- [X] T010 [US2] Implement dotenv parsing and save/readback coordination in Sources/ContainerGUI/Operations/ConnectionDocument.swift, ContainerConnectionService.swift and Domain/OperationModels.swift.
- [X] T011 [US2] Implement captured endpoint saves and observed PostgreSQL fill in Sources/ContainerGUI/Resources/Public/odoo-database.js with Tests/Frontend/ContainerConnectionTests.mjs.

## Phase 5: US3 - Gateway backend (P2)

Goal: edit one direct Nginx target. Independent test: other ports/routes/bytes unchanged, single-file inode retained, unsafe forms rejected.

- [X] T012 [US3] Write failing Nginx grammar/multi-endpoint/inode/state/template tests in Tests/ContainerGUITests/Unit/ContainerConnectionTests.swift and Contract/ContainerConnectionAPITests.swift.
- [X] T013 [US3] Implement direct URL selection, stopped single-file save and readback in Sources/ContainerGUI/Operations/ConnectionDocument.swift, OdooConfigurationFile.swift and ContainerConnectionService.swift.
- [X] T014 [US3] Verify backend selector and backend-specific UI labels in Tests/Frontend/ContainerConnectionTests.mjs and Sources/ContainerGUI/Resources/Public/odoo-database.js.

## Phase 6: Verification and delivery

- [X] T015 Update bilingual README.md and Sources/ContainerGUI/App/AppVersion.swift to 2.26.0.
- [X] T016 Run full Swift/tracked frontend suites and release build; record outcomes in specs/018-container-connections/quickstart.md.
- [ ] T017 Validate local GUI read-only and unchanged business states/config hashes per specs/018-container-connections/quickstart.md.
- [X] T018 Review focused diff, run git diff --check and commit owned files with AppVersion.swift; record local commit outcome in final response.

T017 partial: universal entry, bilingual unsupported view, service health, baseline states and configuration hashes verified; mounted configuration IO waits at macOS directory open. User has been asked to review any removable-volume consent prompt. Do not save or restart business containers to finish acceptance.

## Dependencies and execution

Setup → Foundation → US1 → US2/US3 → verification. US2 and US3 share code but each has isolated acceptance fixtures. Tests are written and observed failing before implementation; prior passed checks repeat only after relevant edits. Main agent owns implementation.

Parallel examples: US1 API and frontend tests are separate files; US2 file fixtures and frontend draft tests can run together; US3 grammar tests and selector tests can run together. No extra implementation agents required.

Implementation strategy: complete universal read-only slice first, then database and backend writes in isolated fixtures, then full regression/build and real read-only UI verification. Do not apply actual address fixes as a test.
