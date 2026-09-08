# ANE power validation — 2026-09-08

## Scope and environment

- Apple M4 Max, 128 GiB RAM, macOS 26.6.2; ordinary user, no sudo/helper install.
- Apple `container CLI version 1.3.1` (a9a62e2). GUI 2.21.0 → 2.22.0.
- All product edits, tests and artifacts belong to this feature. No GitHub push, tag or PKG release.

## Automated checks

- Tests first: backend initial build failed on missing ANE types; four slow-read timing tests later failed (15 assertions) before completion-time timestamps fixed them. Frontend new cases initially failed before implementation.
- `CONTAINER_GUI_ANE_SMOKE=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter ANEPower`: **21/21 passed**, including native smoke and ten reader construction/destruction cycles.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`: **285 tests, 0 failures, 4 opt-in skipped**. Native ANE smoke was explicitly exercised separately above.
- `node --test Tests/Frontend/*.mjs`: **65/65 passed**, including 12 new ANE cases.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release`: passed (50.49 s).
- Independent read-only review found no must-fix items in the final Swift/CF/API/frontend diff. Private ABI compatibility beyond this machine remains unverified.

## Real hardware and API

- Native Energy Model `ANE` / `mJ` cumulative readings valid; idle unchanged 439883 → 439883, producing ready 0 W in a 1.177491 s window, not a missing-value substitute.
- Temporary GUI on port 8797 returned first `sampling` with explicit nulls, then `ready`. Correct `Cache-Control: no-store` and other security headers. Wrong Host and cross-origin requests both returned 403.
- Three bounded synthetic-log inference requests exercised hardware under load. A separate process ran the already-installed pinned model; no user logs or container mutations were used. API estimated power rose to about 2.47–2.59 W; maximum observed 2.586818 W. Browser displayed **2.50 W** with `utilizationPercent: null` and visible unavailable utilization. These are whole-host readings, not proof of per-process attribution.
- Synthetic worker exited 0 after three replies. No remaining `--ai-log-worker` process. AI status remains `enabled:false, phase:off`; ANE polling does not load the model.

## Browser acceptance (Playwright)

- Chinese/light 1440px: complete independent ANE panel, scope/estimate/unavailable labels; document width 1425 <= viewport 1440.
- English/dark 390px: readable two-column ANE summary and wrapped descriptions; document width 375 <= viewport 390, no horizontal overflow.
- Injected only ANE HTTP 503 in the test browser: old watts cleared, safe read error and `Sample window —` shown; unroute restored live watts. Expected 503 console errors were from this injection. An initial assertion used the wrong English unavailable label and was corrected by reading the actual state; no product change was needed.
- Navigating to local images for 5.5 s issued **0 ANE requests**; returning resumed values with an honest 7.4 s window. Hidden/aborted/late response and timeout cases additionally covered by Node tests.
- First full-page screenshot timed out; bounded viewport screenshots succeeded and were visually inspected.
- Screenshots: [Chinese desktop](../../output/playwright/ane-power-zh-desktop.png), [English mobile/dark](../../output/playwright/ane-power-en-mobile.png), [Unavailable state](../../output/playwright/ane-power-zh-panel.png).

## Installed runtime readback and cleanup

- `scripts/install-launch-agent.sh` built and installed user-level GUI 2.22.0. Production `/api/v1` reports 2.22.0; `/api/v1/system/ane` returns ready, finite watts, null/unavailable utilization. Production browser was revisited to confirm the panel.
- Installed binary and app.js byte-compared with the verified release/source resources. No model worker active after installation.
- Temporary 8797 server stopped; browser returned to production 8787. Other user browser tabs left untouched.
- `odoo19` and `postgres-odoo-apple` remain running with their original start times, 2026-09-05T07:09:12Z and 2026-09-05T07:09:19Z respectively. No container restarts, changes or deletions.
- Final gate: scoped diff review, `git diff --check`, version increment and focused local commit; no remote publication.
