# Apple Container update reminder — v2.24.0

Date: 2026-09-13

## Scope and acceptance

- Separate from the Container GUI application updater.
- Read-only `GET /api/v1/container-update-check`; installed CLI version comes from a refreshed local version probe, not request input.
- Fixed official `apple/container` GitHub latest-release endpoint. Stable versions only, numeric version comparison, bounded response and timeout, repository-specific release URL validation.
- Successful checks cached for five minutes per installed version; concurrent release requests coalesced.
- Open visible pages check on load and every six hours; failed checks retry after 30 minutes. Returning to a visible page checks whether an attempt is due.
- Manual sidebar action, bilingual non-modal update banner and explicit official release link. No automatic download, installation, engine restart, or claims that a newly discovered engine is already compatible.
- No background macOS notification when the browser page is closed.

## Verification

- Regression tests first failed because the Apple repository selector did not exist; implementation then passed.
- `swift test` using Xcode Swift 6.3.3: 310 tests, four opt-in tests skipped, zero failures.
- `node --test Tests/Frontend/*Tests.mjs`: 81 passed.
- Live development server: GUI 2.24.0; update endpoint returned installed/latest 1.4.1, `updateAvailable=false`, official Apple release URL.
- Browser: real manual check, automatic newer-release discovery via isolated response fixture, correct release link, English translation, failure message without losing a known update, recovery to real up-to-date state.
- Visual inspection: desktop Chinese update banner; 390px English dark/reduced-motion layout. The simulated newer-version responses were removed/isolated to the test browser and never installed on the live service.
- HTTP 502 console entry was deliberately produced by the failure fixture; normal real checks completed successfully.

This record is not a GitHub release or PKG publication authorization.
