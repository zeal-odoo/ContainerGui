# Container 1.4.1 compatibility — GUI 2.23.2

Date: 2026-09-13 (JST). Scope: local GUI adaptation and engine-upgrade preparation;
no GitHub push, tag or GUI package release.

## Status and limits

- GUI 2.23.2 is installed locally on `127.0.0.1:8787` using the existing launch-agent installer.
- The installed engine **remains 1.3.1**. The two previously running containers were not stopped or restarted.
- The extracted official 1.4.1 **client** was tested against the existing 1.3.1 **server**. This establishes read compatibility, not a completed engine upgrade or 1.4.1 daemon lifecycle acceptance.
- Full engine replacement and subsequent lifecycle/readiness checks remain pending explicit downtime confirmation and macOS administrator authorization.

## Changes

- Retain the existing 1.3.x version gate; accept 1.4.x from 1.4.1 onward. Reject the discarded 1.4.0 tag, unverified 1.5.x and other major versions.
- Normalize 1.4.1 `server.version`, `server.build` and `server.commit` with legacy flat-field fallbacks. Never infer daemon version from `client.version`.
- Preserve the public health API, unknown-field tolerance, minimal stopped/unregistered outputs, nonzero-exit handling, fixed command arrays and loopback-only listener.
- No engine auto-upgrade endpoint, arbitrary command, `clean`, force deletion, authentication change or dependency upgrade was added.

Schema references: [official release](https://github.com/apple/container/releases/tag/1.4.1),
[official SystemStatus source](https://github.com/apple/container/blob/1.4.1/Sources/ContainerCommands/System/SystemStatus.swift).
The committed 1.4.1 fixture is sanitized from that schema and the extracted CLI's observed output.

## Verification

All successful Swift checks used Xcode's Swift 6.3.3 via
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` on arm64/macOS 26.6.2.
Initial command-line-tools Swift attempts were stopped before deployment; no source change was made for toolchain selection.

| Check | Result |
|---|---|
| Tests first: version, health parser and system-start fixture tests | 23 tests; 9 failures before the implementation, reproducing the unsupported gate and missing daemon metadata |
| Same focused tests after the fix | 23 tests, zero failures |
| `swift test` | 305 tests, 4 opt-in tests skipped, zero failures |
| `node --test Tests/Frontend/*Tests.mjs` | 77 tests passed |
| Opt-in read-only CLI smoke test with installed 1.3.1 | Passed: version, health, lists, image inspect, container detail, repeated/cancelled metrics reads |
| Same smoke test with extracted 1.4.1 client / 1.3.1 daemon | Passed; no lifecycle writes |
| `swift build -c release --product ContainerGUI` | Passed |
| Playwright, release binary on temporary loopback port 8797 | Healthy system, correct 1.4.1 client badge, two running containers, metrics/storage, detail open/close and local images |
| Recent logs in the temporary GUI | HTTP 200 and string payload verified without recording log contents in this report |
| Browser console | Zero errors or warnings |
| Installed GUI readback on 8787 | API and page show GUI 2.23.2; health correctly reports installed client/server 1.3.1; AI remains off |
| `git diff --check` | Passed |

Browser screenshots were visually inspected locally. Initial log-response automation used the wrong selected
container and an unavailable `URL` helper; the corrected predicate passed without changing application code.
The temporary GUI on 8797 was stopped after validation. No model was enabled, downloaded or deleted.
No container image, mount, environment or database configuration was changed.

## Official engine package preflight

- Asset: `container-1.4.1-installer-signed.pkg` from Apple's 1.4.1 release.
- SHA-256: `c0d2716afefbb194c93fae662e9cae7cc186bcbcf746816608ec673dd648a6a4` (matches GitHub release asset digest).
- `pkgutil --check-signature`: Apple Inc. - Containerization (`UPBK2H6LZM`), trusted signature/timestamp and notarization.
- `spctl -a -vv -t install`: accepted, Notarized Developer ID.
- Expanded package: `com.apple.container-installer` version 1.4.1, install location `/usr/local`, administrator authorization required; no package install scripts.
- Extracted CLI: `container CLI version 1.4.1 (build: release, commit: 9a8917c)`.
- Mixed-version health: client 1.4.1 / server 1.3.1 (`a9a62e2`), proving the GUI does not substitute one for the other.

Before and after the GUI-only deployment, `odoo19` and `postgres-odoo-apple` remained running;
their `startedDate` values stayed `2026-09-08T16:56:21Z` and `2026-09-05T07:09:19Z` respectively.
PostgreSQL's `pg_isready` still reports accepting connections.
For the pending engine upgrade: obtain downtime confirmation, gracefully stop Odoo then PostgreSQL,
stop the engine, install the verified package through administrator authorization, restart the engine,
start PostgreSQL and wait for readiness, then restore Odoo and verify independent service readbacks.
