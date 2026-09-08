# Local AI validation — 2026-09-08

## Scope

Qwen3-1.7B ANEMLL Core ML LUT6, pinned revision
`0977a61d00e39118aab5ed1e510f1d228df5eefd`. No cloud inference,
new listening service, container changes, Git push or release.

Hardware measured: Apple M4 Max, 128 GiB physical memory, macOS 26.6.2
(25G83). Measurements do not establish performance on 8/16 GiB Macs.
Every model configuration uses `.cpuAndNeuralEngine`, excluding GPU execution;
the actual device assignment of every operator was not instrumented.

## Verified model and native runtime

- Downloaded 22 fixed files, 1,954,040,277 bytes. Full SHA-256 and size readback
  passed against the pinned manifest; no model weights are committed.
- Cached full verification: 2.90 seconds, peak RSS 12,288,000 bytes (11.7 MiB).
  A measured 2.61 GB autoreleased-buffer accumulation was corrected with a
  per-chunk autorelease pool before this final measurement.
- Original Qwen licence and ANEMLL conversion attribution:
  [notices](../../docs/AI_LOG_MODEL_NOTICES.md).

| Synthetic real-model check | Measured result |
| --- | --- |
| First model preparation | 70.810 s |
| Cached model load | 0.589 s |
| English database connection refused | 170 input / 48 output tokens; 3.282 s; relevant advisory |
| Chinese permission denied | 207 input / 35 output tokens; 1.928 s; relevant advisory |
| Repeat first English request after Chinese | 3.241 s; exact same response, confirming per-request KV reset |
| Full input budget | 1792 input / 82 output tokens; 6.415 s; bounded relevant response |
| Worker maximum RSS | 1,323,794,432 bytes (1262.45 MiB) |
| EOF exit | 0.076 s; exit code 0 |
| Parent loss before ready | Worker exited in 0.519 s |
| Parent loss during active generation | Worker exited in 0.942 s |

The system ANE compilation service separately reached about 562 MiB RSS during
first preparation. It is not included in worker RSS and is owned by macOS;
ending the worker does not promise immediate removal of all system caches.
The real-model smoke used synthetic logs only, emitted no stderr, and left no
worker process behind. There was no network request during inference.

## Regression findings addressed

- Short stdin messages previously waited for a full Foundation read buffer.
  An open-writer regression reproduced the delay; bounded POSIX reads now
  process requests without waiting for EOF.
- A cancelled queued start could create a child after cancellation. A first
  failing test observed a live PID; entry/pre-launch cancellation checks and
  a final shutdown readback now prevent a false off state.
- An unbounded redaction expression took 66.88 s for a 20,000-character line.
  Long lines are now omitted before bounded redaction; a 1,000,000-character
  regression completed in approximately 0.1 s. Private-key boundaries are
  scanned before old lines are discarded.
- First-use download can initially return `phase=downloading` before the store's
  downloading flag changes. Actual browser testing reproduced a stuck UI and
  lease expiry. Polling now follows phase as well as store flags, with a
  first-failing regression. Visible owned downloads also renew the lease.
- Frontend errors now use the actual `ProblemDetail.message` field and localized
  known safe codes, rather than a nonexistent `detail` field.

## Acceptance gates

- Unit/API fixtures cover fixed download/redirect/path rules, corrupt and
  oversized files, cancelled/retried downloads, tokenizer role-like text,
  context and output bounds, plain-text output, redaction, available-memory
  rejection, deduplication, empty logs, expired lease, repeated toggles,
  cancellation while loading/generating, and SIGKILL escalation of an owned
  unresponsive child. Host/Origin restrictions apply to every AI endpoint.
- The backend never accepts caller-supplied prompts, log text, model URLs,
  executable paths or PIDs. It obtains bounded logs from the official CLI.
- Ordinary container management and recent/following logs retain their existing
  routes; AI suggestions are text only and never execute.
- Full Swift suite: 264 tests, zero failures, three opt-in integration tests
  skipped by default. The separate authorized model download and actual CoreML
  smoke above cover the real-model gate. Frontend Node suite: 53 tests passed.
- Release build passed with Xcode Swift 6. The first full test run caught stale
  version fixtures/asset query strings; these now match AppVersion 2.21.0.
- Real browser on isolated `127.0.0.1:8797`: explicit first-download confirmation,
  actual sustained download progress and automatic transition to loading passed.
  Closing during actual model loading returned off and the observed child PID
  no longer existed. Re-enabling produced a visible actual analysis (1792 input,
  69 output tokens, 6.08 s). The next close cleared the result and PID.
- A further English browser run waited for **Analysing recent logs**, clicked
  **Turn off AI** during generation, and returned **Off · Model is not running**;
  API readback confirmed disabled/off with no PID and no retained result.
- Chinese desktop and English 390-pixel dark/reduced-motion layouts were
  visually inspected. No JavaScript console errors were reported. Screenshots
  deliberately show no container logs:
  [download](../../output/playwright/ai-download-zh.png),
  [off, Chinese](../../output/playwright/ai-off-zh.png),
  [off, English mobile](../../output/playwright/ai-off-en-mobile.png).
- Existing containers `odoo19` and `postgres-odoo-apple` remained running during
  the read-only tests. Their configuration and lifecycle were not modified.

- Local LaunchAgent installation passed. `127.0.0.1:8787/api/v1` returned 2.21.0;
  AI status returned off/disabled, installed model, no worker and no active
  download. Installed executable and AI browser asset exactly matched the
  verified release build (`cmp`). Both existing containers remained running.
- The isolated development server on 8797 was stopped after validation. The
  optional model remains cached for the user; AI is left off. No GitHub push,
  tag, release or PKG publication was performed.

The focused local Git commit is a source handoff, not a public release.
