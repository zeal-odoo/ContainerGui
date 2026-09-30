# Container 1.5.0 compatibility — GUI 2.24.2

Validated on 2026-09-30 on Apple silicon / macOS 27.0 (26A428), with Xcode's Swift 6.4 toolchain.

## Scope

- Accept Container 1.5.x while retaining 1.3.x and 1.4.x from 1.4.1 onward. Reject unverified 1.6.x, other major versions, and the unreleased 1.4.0.
- Keep existing structured CLI commands and health parsing. Container 1.5.0 retains the nested `client` / `server` health schema; a client upgrade must not be mistaken for a daemon upgrade.
- Add a sanitized 1.5.0 health fixture and extend version, mixed-version metadata, and live read-only smoke tests.
- Synchronize the application version, HTML resource cache keys, version assertion, and bilingual README to 2.24.2.

## Official installer

Source: [Apple Container 1.5.0 release](https://github.com/apple/container/releases/tag/1.5.0), published 2026-09-29.

- Asset: `container-1.5.0-installer-signed.pkg`, 118,045,087 bytes.
- SHA-256: `a24808cb202318fa1c3bbee0c6c6887fe1225fe899d7b687a0ddd939bd6573f8`, matching the official release asset digest.
- `pkgutil --check-signature`: trusted Apple Inc. - Containerization installer signature and Apple notarization.
- `spctl --assess --type install`: accepted, Notarized Developer ID.
- Expanded metadata: `com.apple.container-installer` 1.5.0, `/usr/local`, administrator authorization, no installer scripts.
- Installed CLI and daemon both report 1.5.0, commit `d265d669ecae041bf338cb3b39c4118316d138f0`; the package receipt reports 1.5.0.

## Verification

| Check | Result |
| --- | --- |
| New version-gate test before implementation | Reproduced unsupported 1.5.0 / 1.5.1; two failed assertions |
| Full Swift suite | 312 tests, four opt-in skips, zero failures; 308 passed |
| Tracked frontend tests | 81 passed, zero failures; unrelated untracked test was preserved and excluded |
| Extracted 1.5.0 CLI with installed 1.4.1 daemon | Live read-only smoke passed: health, containers, images, image inspection, detail/redaction, repeated and cancelled metrics |
| Installed 1.5.0 CLI with 1.5.0 daemon | Same live read-only smoke passed |
| Release build and local LaunchAgent deployment | GUI 2.24.2 served on loopback 8787 with the existing interactive scheduling policy |
| Installed GUI APIs | Health identifies supported CLI 1.5.0 and daemon 1.5.0; eight containers and their metrics load; images and recent logs return valid payloads |
| Isolated GUI mutation smoke | Create with 1 CPU / 256 MiB, loopback port and bind mount; restart, stop, start, stop, delete; every operation succeeded with matched readback |
| Port and bind-mount readback | HTTP returned the host-created test file before and after restart/start |
| Bind-mount writeback | A separate auto-removed test container copied its non-secret `/etc/os-release` into the temporary host mount; the host file was independently read back |
| Passive AI status | AI remained disabled / off; no model download or inference was triggered |

The mutation test used an existing cached Python image and only a private temporary directory. Its test container was deleted and absence was independently checked. No business container was used for the mutation smoke.

## Upgrade and restoration

The prior engine binaries/plugins and private container metadata were backed up before installation. Applications were stopped before PostgreSQL, then the engine was stopped. The signed installer was installed through macOS administrator authentication; the new engine was started, PostgreSQL readiness verified, and applications restored.

- All eight previously running containers are running again, without deletion or reconstruction.
- Before/after comparison matched their image descriptors, CPU/memory resources, mounts, published ports, and init-process configuration.
- All 15 pre-existing named image references remain present. Creating a new test container added the engine's official `vminit:0.45.0` system image; it was retained rather than deleting shared engine resources.
- Virtual-network address allocation changed after the engine restart. Private backups were kept; only database host addresses in two deployed Odoo configurations and IP upstreams in existing local proxy configurations were updated to the observed running containers. Passwords, modules, data directories, credentials, and resource limits were not changed.
- Odoo 19's database selector and the local Odoo 20 login returned HTTP 200. The local MiroFish frontend and proxied health endpoint returned HTTP 200; both proxy configurations passed `nginx -t` before reload.

These runtime backups/configurations contain local deployment data and are not included in Git. The committed fixture and this record are sanitized. GUI source changes are a local update; no GitHub push, GUI release, or GUI PKG publication is implied by this validation.
