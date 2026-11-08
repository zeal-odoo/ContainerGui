# Container 1.7.1 compatibility — GUI 2.28.1

Validation environment: Apple silicon / macOS 27.2 (26B123), Xcode Swift 6.4.2, 2026-11-09.

## Scope

- Accept Container 1.7.x from 1.7.1 onward, retaining 1.3.x, 1.4.x from 1.4.1, 1.5.x and 1.6.x. Keep unverified 1.7.0, 1.8.x and other major versions outside the supported range.
- The [official 1.7.1 release](https://github.com/apple/container/releases/tag/1.7.1) adds `cpuUtilization` to structured statistics. It is a fraction of one CPU core, not the GUI's percentage of allocated cores. Continue using cumulative `cpuUsageUsec` samples and the existing display normalization; cover reports with and without the new optional field.
- Continue reading CLI and server versions independently. Health fixtures cover 1.7.1 servers and mixed-version upgrades; a 1.7.1 client does not establish that the running server was upgraded.
- Preserve existing container grouping, row controls, port mappings, image aliases, connection configuration, and confirmation/readback behavior.
- Update the GUI version and resource cache keys to 2.28.1. The README distinguishes this source version from the previously published v2.26.2 PKG.

## Verification

- Before the compatibility change, the new version-classification regression failed for 1.7.1 and 1.7.2, reproducing the unsupported-version gate.
- `CONTAINER_GUI_LIVE_READONLY=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`: 347 tests, zero failures, three opt-in tests skipped (AI model download, native ANE smoke, external registry reads). The live version/status/container/image read test passed.
- Tracked frontend suite: 104 tests passed. The pre-existing untracked `Tests/Frontend/ContainerAddressTests.mjs` was left untouched and excluded.
- A separate GUI 2.28.1 instance on loopback port 18787 recognized CLI 1.7.1 as supported and independently reported the existing server as 1.6.1. Chromium confirmed the two vertical container groups, row controls, list/detail port mappings, and resource values.
- Through the GUI HTTP API, a uniquely named temporary Python container with a loopback-only host port passed create → start → restart → stop → delete. Every operation returned a successful readback and was independently checked with the CLI. HTTP returned the expected unique marker; recent logs contained the marker; CPU and memory samples became ready. The temporary container was removed.
- During the temporary restart/stop checks, two concurrent metrics polls returned `CLI_TIMEOUT` (HTTP 504). Subsequent polling recovered without intervention, and both business containers returned ready CPU/memory samples. This transient is recorded rather than treated as a clean browser-console run.
- All seven pre-existing containers retained their exact configuration hashes and status, including the original start timestamps of the two running containers.
- The release build and `scripts/install-launch-agent.sh` succeeded. The managed service on `http://127.0.0.1:8787/` independently reports GUI 2.28.1, supported CLI 1.7.1, a healthy 1.6.1 API server, seven containers and 28 image entries. List/detail port mappings match the CLI for every container; served HTML, JavaScript, CSS and translations match the source files. CPU/memory samples are ready, and a fresh browser check found no console errors or warnings.
- Post-installation configuration hashes and statuses still match the original seven-container baseline. The separate test GUI was shut down; the managed GUI remains active. Local validation evidence is under ignored `dist/container-1.7.1/`.

## Running server boundary

At validation start the installed CLI reports 1.7.1 (`a15b46097aa4c2325da13c1fb5192b9274aab083`), while the running API server reports 1.6.1 (`aa8d76b44a834eee3ebf6a0bc577e376f65f6361`). Live checks use that existing server. The server's 1.7.1 health shape is covered by fixtures, not claimed as a live 1.7.1-server result.

This GUI update does not restart the Container engine. Engine replacement and business-container downtime are separate from GUI compatibility validation.
