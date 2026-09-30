# Validation guide

Existing Swift/Node toolchains required. Writes use temporary fixtures; never run external management scripts or click Save on actual configurations.

1. `env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ContainerConnection` and `node --test Tests/Frontend/ContainerConnectionTests.mjs`: universal entry, DB edits, one-of-many Nginx edits, invalid/stale/unsafe rejection.
2. `env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`; run `git ls-files -z 'Tests/Frontend/*Tests.mjs' | xargs -0 node --test Tests/Frontend/ContainerConnectionTests.mjs` (exclude preview fixtures and untracked ContainerAddressTests.mjs).
3. `env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release`; install only GUI launch agent for local validation, never restart business containers.
4. Open Odoo, BettaFish, Nginx and unsupported details/configuration. Verify bilingual roles, endpoint selection, disabled-save reasons; edit/cancel drafts only, never save actual settings.
5. Compare real config hashes/CLI states before/after. Record results, `git diff --check`, version 2.26.0 and one focused local commit. No push/PKG.

## Results: 2026-10-01

- Tests were observed failing before implementation. Added parser regression fixtures for multiline secrets/escaped directives and launch-command fixtures for unrelated Nginx configuration/echoed dotenv setup; corrected recognition and verified the regression tests pass.
- Full Swift suite: 336 tests, 4 opt-in tests skipped, zero failures. Full tracked frontend suite plus the new connection tests: 95 passed, zero failures. Existing Odoo API/session tests remain passing.
- The default Command Line Tools lacked XCTest; the command-scoped `DEVELOPER_DIR` uses the installed Xcode toolchain without changing global developer settings.
- Release build passed; GUI-only launch-agent installation passed. Live interface reads GUI v2.26.0 / container 1.5.0, with healthy system and responsive monitoring while configuration IO waits.
- Read-only browser checks confirmed the entry on all 8 real container details, unsupported PostgreSQL configuration with disabled save, and Chinese/English dialog copy. No actual Save, database probe or business lifecycle action was performed.
- Real mounted BettaFish/Odoo configuration reads remain pending at the macOS directory-open step (confirmed by process sampling); the user's system permission response is awaited. Full mounted-config UI checks, backend selection and live draft-refresh checks remain pending. Fixture/session tests cover those behaviors; do not claim full live acceptance until the system read is released.
- All 8 business containers retained baseline running states/start times/images; SHA-256 of the three inspected BettaFish/Nginx/MiroFish host files matched the pre-implementation baseline. Only the GUI service was replaced.
- Preserve the unrelated untracked `Tests/Frontend/ContainerAddressTests.mjs`; no GitHub push or PKG publication.
