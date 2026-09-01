# Quickstart: Version Update Reminder Validation

## Prerequisites

- macOS on Apple Silicon
- Swift toolchain supported by `Package.swift`
- Node.js for standalone frontend logic tests if added
- Existing Apple `container` CLI for the normal dashboard read-only smoke
- GitHub CLI authenticated only for the final explicitly authorized Release replacement

## 1. Automated tests

```bash
swift test --filter GitHubReleaseCheckerTests
swift test --filter UpdateCheckAPITests
swift test --filter UpdateReminderAssetTests
swift test
```

Expected: all tests pass. Fixtures prove newer/equal/older versions, invalid versions, untrusted URLs, draft/prerelease results, response limits, upstream failures, the API contract, bilingual labels, 24-hour throttling, single in-flight behavior, and no automatic navigation.

## 2. Local service smoke

```bash
swift run ContainerGUI
curl -fsS http://127.0.0.1:8787/api/v1
curl -fsS http://127.0.0.1:8787/api/v1/update-check
```

Expected: application version is `2.17.0`; the update response contains the same current version, a validated latest stable version, a boolean availability result, and an official GitHub release URL. If GitHub is unavailable, only the update route returns a safe retryable problem while `/api/v1/containers` remains usable.

## 3. Browser flow

1. Open `http://127.0.0.1:8787/#main`.
2. Verify the header contains `检查更新` / `Check for updates`.
3. Select the action and verify the button cannot submit a duplicate request while checking.
4. For a newer fixture/stub release, verify the dialog shows installed/latest versions and no download begins automatically.
5. Select the GitHub action and verify only the official ContainerGui Release page opens in a separate context.
6. Dismiss the dialog, switch Chinese/English, check again, and verify the same version and Release action appear in the selected language.
7. Enable reduced motion and verify the flow remains understandable.
8. Reload twice within 24 hours and verify the automatic check is not repeated.

## 4. Replacement PKG and Release

```bash
./scripts/build-pkg.sh
pkgutil --check-signature dist/ContainerGUI-2.17.0-arm64.pkg
shasum -a 256 -c dist/ContainerGUI-2.17.0-arm64.pkg.sha256
```

Expected: the package metadata, bundled binary `/api/v1` smoke, displayed version, filename, and checksum all identify `2.17.0`. The signature check may report unsigned unless a Developer ID Installer identity is available; that limitation must be stated in release notes.

Only after these checks pass: push the new commit, delete the old public `v2.17.0` Release and tag, tag the new commit, recreate the Release with both assets, download them into a temporary directory, and verify the published checksum again.
