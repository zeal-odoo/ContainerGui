# US2 control-and-logs verification

Date: 2026-08-29 (Asia/Tokyo)

## Automated result

- Full suite: PASS, 50 tests, 0 failures; the opt-in live test is skipped by default
- Command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`
- JavaScript syntax: PASS with `node --check Sources/ContainerGUI/Resources/Public/app.js`
- Live read-only compatibility: PASS, 1 test, 0 failures, 0.367 seconds
- Live command: `CONTAINER_GUI_LIVE_READONLY=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter ReadOnlyCLISmokeTests`

Fixture-backed coverage includes exact-ID start/stop/log command arrays, absence of shell/`--all`/`--force`,
10-second graceful stop, non-zero/timeout/unchanged readback handling, idempotent replay/conflict, per-target
serialization, operation polling, invalid UTF-8 replacement, SSE keepalive/drop/end events, eight-session limiting,
bounded buffering and child-process termination after disconnect.

## Read-only browser result

- CLI/service: `container` 1.3.1, healthy; two existing containers observed, one running and one stopped
- Stopped detail: exactly one `启动容器` action and no `正常停止` action
- Running detail: exactly one `正常停止` action and no `启动容器` action
- Recent/follow log controls are enabled after exact-ID detail readback
- Confirmation dialog remained closed; no control or log button was clicked
- After continued five-second polling: health remained `系统正常`, count remained 2, selected detail remained stable
- Fresh browser console: 0 errors, 0 warnings
- Screenshot: `output/playwright/us2-dashboard.png`

The first browser observation exposed one intermittent health timeout caused by repeated version probes. The
client now coalesces and caches the process-wide installation probe; a concurrent-read test proves one
`container --version` invocation, and the clean follow-up polling session produced no console errors.

## Acceptance boundary

No real container was started, stopped, created, deleted or otherwise mutated. T041 remains open because its
second half requires explicit authorization of a disposable container. The fake-executor half and the real
read-only browser checks are complete; this document must be extended with independent CLI before/after
readbacks if that live mutation is later authorized.
