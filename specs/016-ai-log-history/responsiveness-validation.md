# Large-log responsiveness: v2.23.1

Date: 2026-09-09. Local fix only; no GitHub push, tag or installer release.

## Reproduction and changes

Red-first tests reproduced two blocking paths with synthetic data:

1. Preparing 200,000 ordinary log lines (~6.4 MB) ran redaction expressions for every old line before discarding most of them. It took 5.09 seconds, and a concurrent AI status call waited 5.12 seconds on the same actor.
2. A 1,000-chunk log burst caused 1,000 immediate DOM writes and layout reads. The recent-log path did not apply any display-size limit.

The fix scans private-key boundaries across the input but applies redaction expressions only to the bounded recent candidate window (200 lines / 32 KiB for large input), and reuses the assignment expressions. AI preparation runs in a utility task with cancellation propagation rather than on the AI control actor. Previously saved excerpts of at most 6,144 bytes retain all their short lines for compatibility; a failing compatibility regression was added before correcting that case.

The UI retains a 64K-character display buffer, batches live DOM writes at 100 ms, bounds recent responses before insertion, flushes/cancels pending updates on stop/reset, and ignores log callbacks from a closed/previous stream. Existing truncation messages and literal-text rendering are retained. Container log files and analysis-history files are not rewritten or deleted by this fix.

## Automated results

- Full Swift suite: 300 tests, 4 opt-in tests skipped, 0 failures. Skipped checks require model download, native ANE, live CLI or external registry opt-in.
- Full frontend suite: 77 passed, 0 failures.
- Release build and `git diff --check`: passed.
- Same synthetic batch after the fix: 0.50 seconds preparation (0.47 seconds in the focused run); AI status during preparation returned in less than 1 ms. Simulated shutdown met the 1-second bound and left no result or worker PID.
- Private-key bodies spanning 50,000 lines remain excluded, including boundaries outside the candidate window. Secrets are still redacted, and previously saved 1,000-short-line evidence remains unchanged/readable.
- Frontend regressions verify one pending render per burst, bounded memory/text, truncation notices, literal text, stopping, and replacement without a late old batch.

Local raw test output is in ignored `.build/log-responsiveness-*.log` files.

## Real-browser stress harness

Playwright used the release GUI at a separate loopback port 8797. All AI responses and log input in the stress scenarios were explicitly synthetic: no real model was loaded and no real container log content was used. A test EventSource delivered events through the application's actual live-log handlers. A synthetic recent-log response contained approximately 8 MB of text.

| Measurement | Observed |
|---|---:|
| Live log events delivered | 6,000 |
| Log DOM writes | 34 |
| Retained displayed text (including notice) | 65,549 characters |
| Language-switch action and readback | 56 ms |
| Mocked AI-off action and readback | 56 ms |
| Observed main-thread tasks of at least 50 ms during the live burst | 0 |

The large recent response was truncated before rendering and retained its newest marker. Navigation to local images stopped the stream; a manually delivered late event was ignored. English/dark at 390px had no document-width overflow. Both screenshots were opened and visually inspected:

- [Desktop after the burst](../../output/playwright/log-pressure-desktop.png)
- [Narrow dark layout after navigation](../../output/playwright/log-pressure-mobile.png)

These measurements validate log processing/rendering and control responsiveness, not real-model inference latency, Core ML cold loading, every Mac model, or the user's exact original freeze. The model itself is unchanged.

## Local deployment readback

- The existing installer rebuilt/copied release v2.23.1 and restarted only GUI/watchdog LaunchAgents. Installed binary and `app.js` were byte-compared with build/source.
- Unmocked `127.0.0.1:8787/api/v1` returned Container GUI v2.23.1 (a final identity probe took about 2 ms).
- Real AI status remained off with no worker PID. The three existing `odoo19` history IDs and total were unchanged across the update; result bodies were not printed or exported.
- Official CLI readback (container 1.3.1): `odoo19` and `postgres-odoo-apple` remained running. No container lifecycle commands were issued.
- Browser mocks were removed, the browser returned to the real 8787 GUI, and the temporary 8797 listener was terminated.

Completed as a focused local commit with the version increment. No publication was performed.
