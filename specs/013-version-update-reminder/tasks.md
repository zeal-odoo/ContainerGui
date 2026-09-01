---

description: "Task list for the version update reminder and v2.17.0 replacement release"
---

# Tasks: Version Update Reminder

**Input**: Design documents from `/specs/013-version-update-reminder/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/update-check-api.md, quickstart.md

**Tests**: Required by the specification and project constitution. Each story's tests are written and observed failing before its implementation.

**Organization**: Tasks are grouped by independently testable user story, followed by the explicitly authorized release replacement.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm the repository baseline and feature artifacts without changing runtime behavior.

- [x] T001 Verify the clean Git baseline, active feature documents, existing ignore rules, current `2.17.0` release/tag, and packaging scripts in `.gitignore`, `.specify/feature.json`, `specs/013-version-update-reminder/`, and `scripts/build-pkg.sh`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish the same-origin update contract and its safe error vocabulary.

- [x] T002 [P] Add failing semantic-version, fixed-host, stable-release, response-limit, malformed-response, and failure-mapping tests in `Tests/ContainerGUITests/Unit/GitHubReleaseCheckerTests.swift`
- [x] T003 [P] Add a failing read-only update route contract test in `Tests/ContainerGUITests/Contract/UpdateCheckAPITests.swift`

**Checkpoint**: The missing release checker and route are demonstrated by failing tests before implementation.

---

## Phase 3: User Story 1 - Automatic newer-version reminder (Priority: P1) 🎯 MVP

**Goal**: Detect a newer stable public release without blocking or mutating the local dashboard and show a dismissible prompt at most once per 24 hours.

**Independent Test**: Load the dashboard against a newer release fixture and observe a prompt; repeat within 24 hours and observe no second automatic request or prompt.

### Tests for User Story 1

- [x] T004 [P] [US1] Add failing automatic-check, 24-hour throttle, URL validation, no-automatic-navigation, and Material 3 dialog assertions in `Tests/ContainerGUITests/Browser/UpdateReminderAssetTests.swift` and `Tests/Frontend/UpdateCheckTests.mjs`

### Implementation for User Story 1

- [x] T005 [US1] Implement semantic version parsing, validated release summaries, and the bounded injected GitHub release checker in `Sources/ContainerGUI/Domain/UpdateModels.swift` and `Sources/ContainerGUI/Update/GitHubReleaseChecker.swift`
- [x] T006 [US1] Implement the retryable update error, production limits, read-only endpoint, and router registration in `Sources/ContainerGUI/Domain/ProblemDetail.swift`, `Sources/ContainerGUI/App/AppConfiguration.swift`, `Sources/ContainerGUI/Web/UpdateCheckRoutes.swift`, and `Sources/ContainerGUI/App/AppFactory.swift`
- [x] T007 [US1] Implement the non-blocking automatic check, pure 24-hour/URL helper, browser record, update dialog, and existing Material 3/reduced-motion behavior in `Sources/ContainerGUI/Resources/Public/index.html`, `Sources/ContainerGUI/Resources/Public/update-check.js`, `Sources/ContainerGUI/Resources/Public/app.js`, and `Sources/ContainerGUI/Resources/Public/app.css`

**Checkpoint**: Automatic update discovery works independently while container routes remain usable during update failures.

---

## Phase 4: User Story 2 - Manual update check and GitHub action (Priority: P2)

**Goal**: Let the user check immediately, see clear available/current/failed states, and explicitly open only the official GitHub Release page.

**Independent Test**: Select the header action for newer, equal, and failed stub results and verify the button state, feedback, and official external target.

### Tests for User Story 2

- [x] T008 [US2] Extend failing browser assertions for the visible manual action, duplicate-request guard, current/failure feedback, `target="_blank"`, and `noopener noreferrer` in `Tests/ContainerGUITests/Browser/UpdateReminderAssetTests.swift`

### Implementation for User Story 2

- [x] T009 [US2] Implement manual checking, in-flight deduplication, current/failure toast feedback, dialog dismissal, and explicit official release navigation in `Sources/ContainerGUI/Resources/Public/app.js` and `Sources/ContainerGUI/Resources/Public/index.html`

**Checkpoint**: Manual checking works independently of the automatic interval and never starts an automatic download or installer.

---

## Phase 5: User Story 3 - Chinese and English update flow (Priority: P3)

**Goal**: Keep all update states understandable and live-translated in either existing interface language.

**Independent Test**: Display the update prompt in both interface languages and confirm the same version and official Release action are preserved while every label changes.

### Tests for User Story 3

- [x] T010 [US3] Add failing Chinese/English labels and state-preservation assertions in `Tests/ContainerGUITests/Browser/UpdateReminderAssetTests.swift` and `Tests/Frontend/I18nTests.mjs`

### Implementation for User Story 3

- [x] T011 [US3] Add update labels, statuses, version-message patterns, and accessibility text to `Sources/ContainerGUI/Resources/Public/i18n.js`, preserving the detected update summary across language changes in `Sources/ContainerGUI/Resources/Public/app.js`

**Checkpoint**: The same detected update state is fully localized without losing its version or Release action.

---

## Phase 6: Polish, Validation, and Replacement Release

**Purpose**: Prove the complete feature and replace the previously published `v2.17.0` only after a ready artifact exists.

- [x] T012 Update browser asset cache keys and bilingual update documentation while retaining the explicitly assigned application version in `Sources/ContainerGUI/Resources/Public/index.html`, `Sources/ContainerGUI/App/AppVersion.swift`, and the bilingual `README.md`
- [x] T013 Run targeted tests, frontend tests, full `swift test`, `git diff --check`, and spec quickstart checks documented in `specs/013-version-update-reminder/quickstart.md`
- [x] T014 Deploy the verified local binary with `scripts/install-launch-agent.sh` and confirm browser-visible update controls, `/api/v1` version `2.17.0`, update-route behavior, loopback listener, CLI `1.3.1`, and unchanged container state
- [x] T015 Build and verify `dist/ContainerGUI-2.17.0-arm64.pkg` and its SHA-256 using `scripts/build-pkg.sh`, package metadata inspection, extracted-runtime smoke, and checksum validation
- [x] T016 Create one focused Git commit, fast-forward push `main`, delete the old GitHub `v2.17.0` Release and tag, retag the new commit, and recreate the public bilingual Release with the verified PKG and checksum
- [x] T017 Download both replacement Release assets into a temporary directory and verify public visibility, tag target, package version, and published checksum

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup** has no dependency.
- **Foundational tests** depend on Setup and must fail before implementation.
- **US1** depends on the Foundational failing tests and supplies the shared checker/route.
- **US2** depends on US1's checker state but remains independently manually testable.
- **US3** depends only on the update UI state from US1/US2.
- **Validation and Release** depend on all stories; the GitHub Release must not be deleted before T015 passes.

### Parallel Opportunities

- T002 and T003 modify different test files and may be prepared independently.
- T004 is in a separate browser test file while T002/T003 are still failing, but all implementation remains sequential to preserve TDD evidence.
- Release asset verification in T017 begins only after T016 recreates the Release.

## Implementation Strategy

### MVP first

1. Complete T001-T007.
2. Verify automatic update discovery cannot block the dashboard.
3. Add manual control and localization through T008-T011.
4. Do not touch the current GitHub Release until the replacement PKG passes T015.

### Release safety

1. Preserve `main` history and create a new focused commit.
2. Build the replacement package before deleting any public asset.
3. Delete only the explicitly authorized `v2.17.0` Release and tag.
4. Immediately retag the new commit and recreate the public Release.
5. Verify the public assets from a fresh download before reporting completion.
