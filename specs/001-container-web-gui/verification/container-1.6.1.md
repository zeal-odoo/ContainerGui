# Container 1.6.1 compatibility — GUI 2.26.2

Validation environment: Apple silicon / macOS 27.0.1 (26A434), Xcode Swift 6.4.2, 2026-11-03.

## Scope

- Accept Container 1.6.x while retaining 1.3.x, 1.4.x from 1.4.1 onward, and 1.5.x. Continue rejecting unverified 1.7.x, other major versions, and the unreleased 1.4.0.
- Keep existing structured CLI commands and output parsing. Review the official [1.5.0...1.6.1 changes](https://github.com/apple/container/compare/1.5.0...1.6.1): the new build/cluster plugins do not affect GUI commands; image-list nonzero exits still mean incomplete results and are not presented as complete listings.
- Preserve independent client/server health versions. A new CLI does not prove that the API server has been upgraded.
- Add a sanitized 1.6.1 health fixture and cover new-client/old-server, missing-server, and current-server health parsing.
- Accept distinct image references sharing one content ID, retaining duplicate-reference rejection. Prefer an exact deletion target, reject ambiguous IDs before mutation, and verify absence of only the deleted reference.
- Synchronize the application version, HTML cache keys, version assertion, and bilingual release documentation to 2.26.2.

## Verification

| Check | Result |
| --- | --- |
| Version-gate test before implementation | Reproduced unsupported 1.6.0, 1.6.1, and 1.6.2; three failed assertions |
| Full Swift suite with live read-only checks enabled | 342 tests, three opt-in skips, zero failures; 339 passed |
| Image-alias regression tests before implementation | Reproduced rejected shared IDs, wrong digest-alias deletion target/readback, and ambiguous-ID mutation attempt |
| Extracted official 1.6.1 CLI with installed 1.5.0 daemon | Live read-only smoke passed: health, containers, images, image inspection, detail/redaction, repeated and cancelled metrics |
| Browser using 1.6.1 CLI / 1.5.0 daemon | GUI 2.26.2 shows healthy status, 12 containers and shared-ID image aliases in Chinese and English |
| Tracked frontend tests | 95 passed, zero failures; the pre-existing untracked address test was excluded |
| Final arm64 PKG | Version/identifier, checksum, strict ad-hoc executable signature, source-resource parity, and standalone launch passed |
| Packaged GUI / 1.6.1 CLI / 1.5.0 daemon | Isolated create, restart, stop, start, stop, delete, logs, metrics, loopback port and bind-mount readback passed; test container removed |
| Installed GUI / 1.5.0 CLI / 1.5.0 daemon | GUI 2.26.2 identity and health readback passed; the same isolated lifecycle/network/mount checks passed |
| Request safety | Foreign Host and Origin requests rejected with HTTP 403 by the packaged runtime |
| Existing deployment | All 12 pre-existing container configuration files retained their original SHA-256 values; business containers were not restarted |

The first mixed-version create exceeded the GUI's 30-second mutation timeout before the 1.6.1 default `ghcr.io/apple/containerization/vminit:0.53.0` image was cached. The official image was explicitly pulled and unpacked without restarting services; the isolated checks then passed. Complete the official CLI's system-image preparation before first creation. Existing images were retained.

The GUI PKG SHA-256 is `bf5222f9f282c45e27842dc93bff43a7fa6283a26ac8b0c8e5ce94245d510b87`. The installer is unsigned and not notarized; its executable is ad-hoc signed. The installed GUI continues to use `/usr/local/bin/container`, and its prior runtime and LaunchAgent configuration were backed up.

## Official installer

Source: [Apple Container 1.6.1 release](https://github.com/apple/container/releases/tag/1.6.1), published 2026-10-23.

- Asset: `container-1.6.1-installer-signed.pkg`, 155,965,213 bytes.
- SHA-256: `cd47846819f06478d067060efe21e516b562ac0a9af8eecad6d5fea0b556b200`, matching GitHub release metadata.
- `pkgutil --check-signature`: trusted Apple Inc. - Containerization signature and Apple notarization.
- `spctl --assess --type install`: accepted, Notarized Developer ID.
- Expanded metadata: `com.apple.container-installer` 1.6.1, `/usr/local`, administrator authorization, no installer scripts.
- Extracted CLI reports 1.6.1, commit `aa8d76b44a834eee3ebf6a0bc577e376f65f6361`.

## Local engine upgrade boundary

The installed CLI and daemon remain at 1.5.0 while database work is in progress. The user explicitly requested waiting for database operations to finish before restarting the engine. GUI compatibility work and publication proceed independently of that restart.

Before any engine mutation, private snapshots of container/image state and backups of engine binaries, plugins, and JSON configuration were prepared outside Git. No database values or private deployment configuration are included in this record.

Live 1.6.1-client/1.6.1-daemon acceptance remains deferred until the engine upgrade is safe. The 1.6.1 server health schema is covered by fixtures; the live checks above use the existing 1.5.0 daemon.
