# Validation: AI analysis history v2.23.0

Date: 2026-09-08. Scope: local implementation and deployment only; no GitHub push, tag or PKG release.

## Automated checks

- Red-first store/service, HTTP and frontend tests failed on the missing history implementation before the feature was added.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`: 296 tests, 4 opt-in tests skipped, 0 failures. The skipped checks require a model download, native ANE smoke testing, live CLI smoke testing or an external registry request.
- `node --test Tests/Frontend/*.mjs`: 72 passed, 0 failures.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release --product ContainerGUI`: passed.
- `git diff --check`: passed.

The history tests use isolated, canonical private temporary directories and synthetic log/model output. They verify persistence after reopening the store, survival after disabling AI, no archival for cancelled work, unchanged-evidence deduplication, nonfatal save failures, 1,001-to-1,000 eviction, 10-item paging, precise deletion and redaction. Directory/ancestor symlinks, record symlinks, hard links, corrupt or oversized JSON, loose permissions and invalid API fields are rejected. History HTTP requests retain Host/Origin validation and `no-store`; read-only history does not start a worker or read fresh container logs. Frontend tests cover stale responses, target switching, export contents, confirmation cancellation, failed requests and localization.

The new asynchronous save initially exposed a lifecycle-test race: publishing the current result before the save completed allowed a caller to request another analysis while the phase was still `analysing`. The result is now published after archival completes (or reports its own failure) and after a second generation/enabled check. The regression suite passes with that ordering.

## Browser evidence

Headed Playwright against a separate loopback GUI on port 8797 used 12 explicitly labelled synthetic records. The AI switch stayed off throughout. No model was downloaded or loaded, and no real container log content was used for these history scenarios.

- Chinese/light desktop at 1440px: expanded answer and redacted evidence, literal `<example>` text, JSON export, 10 records on page 1 and 2 on page 2.
- The downloaded JSON was read back and matched the selected fixture's UUID, container, version, answer and evidence.
- Cancelling deletion retained 12 records. Confirming deletion removed the selected synthetic record and the list read back 11.
- English/dark at 390px: translated controls, wrapping actions and pagination; document scroll width was 375px, within the viewport. Previously generated analysis text was preserved rather than translated again.
- A mocked HTTP 503 produced a visible retryable error and removed stale rows. Removing the mock and refreshing loaded the real empty history while AI remained off.
- Desktop and narrow-screen screenshots were opened and visually inspected:
  - [Chinese expanded history](../../output/playwright/ai-history-zh-panel.png)
  - [English narrow-screen history](../../output/playwright/ai-history-en-mobile.png)

The mock routes were removed before testing the installed GUI. No synthetic records were written to the real history directory, and no real history was deleted.

## Local deployment readback

`scripts/install-launch-agent.sh` installed the release binary and resources into the local `versions/2.23.0` directory and restarted only the GUI/watchdog LaunchAgents. Installed binary and history script were byte-compared with the build/source.

- `GET http://127.0.0.1:8787/api/v1`: `Container GUI`, `2.23.0`.
- AI status: `enabled: false`, `phase: off`, model already installed, no worker PID.
- History GET: `items: []`, `page: 1`, `pageSize: 10`, `retentionLimit: 1000`, `total: 0`. Passive empty reads did not create the history folder.
- Official `container list --format json` readback: existing `odoo19` and `postgres-odoo-apple` remained running; neither was restarted or otherwise changed.
- The unmocked browser at port 8787 displayed the new history entry, a truthful empty state and “已关闭 · 模型未运行”. [Live empty state](../../output/playwright/ai-history-live-empty.png)
- The temporary GUI on port 8797 was terminated and its listener was confirmed absent.

## Boundaries

This validates the persistence and UI integration with controlled model output, not a fresh real-model inference-quality run. Earlier discarded in-memory analyses cannot be recovered. Records contain bounded redacted excerpts (not full continuous logs), and automatic redaction can miss secrets; users must review exports before sharing. The globally newest 1,000 records are retained, so anything needed longer should be exported.
