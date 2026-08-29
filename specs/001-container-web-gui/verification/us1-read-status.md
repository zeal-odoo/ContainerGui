# US1 read-status verification

Date: 2026-08-29 (Asia/Tokyo)

## Automated result

- Focused fixture/parser/API/asset suite: PASS, 10 tests, 0 failures
- Opt-in live read-only test: PASS, 1 test, 0 failures, 0.429 seconds
- Live command: `CONTAINER_GUI_LIVE_READONLY=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter ReadOnlyCLISmokeTests`
- Real mutations: none

## Independent CLI and API readback

- CLI version: `container CLI version 1.3.1 (build: release, commit: a9a62e2)`
- CLI JSON shape confirmed at 12:25 JST: list items contain outer `id`, `configuration`, and `status`
- GUI health observed at `2026-08-29T03:34:15Z`: compatibility `supported`, version `1.3.1`, service `healthy`
- GUI list observed at `2026-08-29T03:34:15Z`: 2 containers, 1 running, 1 stopped
- The live test independently re-ran version, system status, full list, and the first exact-ID inspect

## Browser result

- Chromium page title and Chinese semantic landmarks: PASS
- Loading, empty and error states are mutually hidden after fixing the author-CSS `hidden` override
- Manual refresh control, five-second visible-page refresh, search, exact detail navigation and redacted raw panel: PASS
- Browser console after favicon correction: 0 errors, 0 warnings
- Security headers visible on the static page: CSP, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, no CORS header
- Screenshot: `output/playwright/us1-dashboard.png`

US1 is accepted as an independently usable read-only slice. Start/stop and log controls remain disabled until US2.
