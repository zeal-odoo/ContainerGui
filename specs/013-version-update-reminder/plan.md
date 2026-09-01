# Implementation Plan: Version Update Reminder

**Branch**: `main` | **Date**: 2026-09-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/013-version-update-reminder/spec.md`

## Summary

Add a non-blocking update check for the fixed public ContainerGui GitHub repository. The Swift service obtains and validates the latest stable Release through a bounded, no-redirect HTTP request and returns a small same-origin summary. The static browser UI checks automatically at most once per 24 hours, provides an always-available manual check, presents bilingual Material 3 feedback, and opens only the validated official GitHub Release page after an explicit user action. After tests and package validation, replace the existing `v2.17.0` tag and Release without rewriting `main` history.

## Technical Context

**Language/Version**: Swift 6.1; native HTML, CSS, and JavaScript

**Primary Dependencies**: Hummingbird 2.26+, Foundation `URLSession`, existing Material 3 static assets

**Storage**: Browser `localStorage` for a single last-automatic-check timestamp; no server database or release cache

**Testing**: XCTest unit, HTTP contract, and browser asset tests; Node.js client-logic tests where isolation is useful; live localhost HTTP/browser smoke; PKG extraction and checksum validation

**Target Platform**: Apple Silicon macOS 15+ with Apple `container` CLI 1.3.1 baseline

**Project Type**: Single Swift localhost web service with bundled static browser UI

**Performance Goals**: Dashboard becomes usable without waiting for GitHub; update result normally appears within 5 seconds; one automatic outbound check per 24 hours per browser profile

**Constraints**: Bind only to `127.0.0.1`; fixed GitHub repository and HTTPS release path; 5-second timeout; 128 KiB response limit; redirects disabled; no automatic download, installer execution, or container mutation

**Scale/Scope**: One local user, one latest-release request, one update dialog, Chinese and English

## Constitution Check

### Pre-design gate

- **Official CLI as source of truth**: PASS. The feature does not read or mutate container state and leaves all existing CLI readback behavior unchanged.
- **Local-first and safe changes**: PASS. The browser calls a same-origin read-only route; the server calls one fixed HTTPS host; the user must explicitly choose the external link.
- **Test first**: PASS. Unit, contract, and asset tests are scheduled before implementation; no real container writes are used.
- **Independent increment**: PASS. Update discovery remains optional and cannot block existing dashboard stories.
- **Simple architecture**: PASS. No database, frontend build chain, updater daemon, or installer executor is introduced.
- **Version increment rule**: EXCEPTION. The previous packaging-only commit already displays `2.17.0`, while the user explicitly directed that this feature replace the existing public `2.17.0`. The application therefore remains `2.17.0` for this commit. Impact is limited to the one release correction; `main` history remains append-only and the old public tag/Release is replaced only after the new package passes validation. Normal strict version increments resume with the next logical update. A different `2.18.0` version was rejected because it directly conflicts with the user's assigned release number.

### Post-design gate

The design keeps the exception limited to release numbering. All runtime, security, test, UI, packaging, and Git tracking gates remain satisfied and are represented by executable tasks.

## Project Structure

### Documentation (this feature)

```text
specs/013-version-update-reminder/
├── checklists/requirements.md
├── contracts/update-check-api.md
├── data-model.md
├── plan.md
├── quickstart.md
├── research.md
├── spec.md
└── tasks.md
```

### Source Code (repository root)

```text
Sources/ContainerGUI/
├── App/
│   ├── AppConfiguration.swift
│   ├── AppFactory.swift
│   └── AppVersion.swift
├── Domain/
│   ├── ProblemDetail.swift
│   └── UpdateModels.swift
├── Update/
│   └── GitHubReleaseChecker.swift
├── Web/
│   └── UpdateCheckRoutes.swift
└── Resources/Public/
    ├── app.css
    ├── app.js
    ├── i18n.js
    ├── index.html
    └── update-check.js

Tests/ContainerGUITests/
├── Browser/UpdateReminderAssetTests.swift
├── Contract/UpdateCheckAPITests.swift
└── Unit/GitHubReleaseCheckerTests.swift

Tests/Frontend/
└── UpdateCheckTests.mjs
```

**Structure Decision**: Keep the existing executable target and static UI. Add one small domain model, one release client, and one read-only route; integrate UI through the existing dialog, toast, localization, and motion primitives.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| New commit keeps application version `2.17.0` instead of strictly incrementing | The user explicitly assigned this feature to `2.17.0` and ordered replacement of the earlier release with that tag | Publishing `2.18.0` would satisfy normal governance but contradict the explicit requested release identity; rewriting the existing commit would make history less safe |
