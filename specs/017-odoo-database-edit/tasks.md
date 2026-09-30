# Tasks: Edit an existing Odoo database endpoint

## Phase 1 - Setup

- [X] T001 Define approved no-migration scope and contracts in `specs/017-odoo-database-edit/`.
- [X] T002 Verify the requirements checklist, design documents, and repository ignore rules.

## Phase 2 - Foundations

- [X] T003 Write failing isolated-file and input-validation tests in `Tests/ContainerGUITests/Unit/OdooDatabaseTests.swift`.
- [X] T004 Implement bounded endpoint models, byte-preserving host editor, and fixed guest helper in `Sources/ContainerGUI/{Domain,Operations,CLI}/`.

## Phase 3 - US1: Edit the endpoint

- [X] T005 Write failing service/API tests for privacy, readback, stale revisions, replay, locks, and stopped-internal restrictions in `Tests/ContainerGUITests/Contract/OdooDatabaseAPITests.swift`.
- [X] T006 Implement the standalone service and routes; share the existing coordinator and register in `Sources/ContainerGUI/App/AppFactory.swift`.
- [X] T007 Write failing frontend session tests in `Tests/Frontend/OdooDatabaseTests.mjs`.
- [X] T008 Add the bilingual detail-screen editor in `Sources/ContainerGUI/Resources/Public/`, preserving drafts and rejecting late responses.

## Phase 4 - US2: Choose PostgreSQL

- [X] T009 Test and implement observed PostgreSQL address autofill in `odoo-database.js`; no connection probe or automatic save.

## Phase 5 - Verify and deliver

- [X] T010 Run focused and full regression tests, read-only browser checks, and record results in `specs/017-odoo-database-edit/validation.md`.
- [X] T011 Increment `Sources/ContainerGUI/App/AppVersion.swift` to 2.25.0, document usage, deploy only the GUI, and independently verify version and unchanged business containers.
- [X] T012 Review the focused diff, run `git diff --check`, and create one local commit excluding existing user changes. Do not push or publish.

## Dependencies and execution

T001 -> T002 -> T003 -> T004 -> T005 -> T006 -> T007 -> T008 -> T009 -> T010 -> T011 -> T012.
Tests precede their implementation. Work is sequential; no additional agents are needed. Both stories share one configuration editor and one operation lock, so they must not be implemented as unrelated file-editing paths.

Each story is independently testable with isolated fixtures. Final real-environment checks are read-only except deployment of the GUI itself; no migration, configuration save, or container lifecycle action is permitted during validation.
