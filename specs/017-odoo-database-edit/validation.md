# Validation results - Odoo database endpoint editor

Date: 2026-09-30. Local source/runtime version: 2.25.0. Apple Container: 1.5.0. macOS: 27.0.1.

## Automated checks

- Tests-first: new Swift tests initially failed because the endpoint models/editor/service were absent; the new frontend suite initially failed because its module was absent. Both passed after implementation.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`: 323 tests executed, 4 skipped, 0 failures. Includes 6 new unit tests and 5 new API/service tests.
- `node --test $(git ls-files 'Tests/Frontend/*Tests.mjs') Tests/Frontend/OdooDatabaseTests.mjs`: 88 tests passed, 0 failures, including 7 new session/autofill tests. The existing untracked `ContainerAddressTests.mjs` was not changed or included in the tracked suite.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --product ContainerGUI`: passed.
- `git diff --check`: passed before delivery.

Fixture checks cover input/target validation, malformed/oversize/linked/read-only files, CRLF and unrelated-content preservation, POSIX permissions, private backups, optimistic revisions, same-key retries/concurrent dispatch, shared container locks, origin rejection, guest failures/timeouts/invalid output, mismatched readback, stale frontend responses, draft preservation, and PostgreSQL autofill without submission. Guest-helper writes used only isolated temporary files; service tests used fixtures or fake CLI execution.

## Read-only browser checks

The debug service on port 8788 displayed the editor for the stopped, directory-mounted `hilite-odoo20`. It read the existing `192.168.66.2:5432` endpoint, offered the running PostgreSQL container at `192.168.66.4:5432`, and filled that address without saving. Chinese/English language changes and dashboard refresh preserved the unsaved draft. The stopped internal-config `odoo19` displayed its explicit restriction with editing and Save disabled. No deployed configuration was saved.

After installing only the GUI with `Scripts/install-launch-agent.sh`, both launch-agent plist checks passed. The managed service on port 8787 independently returned `{"name":"Container GUI","version":"2.25.0"}` and displayed the new editor.

An initial installed-service read waited inside macOS filesystem access to the external LaCie volume. A process sample showed the host editor waiting in `open()` and TCC logs showed its authorization request. No permission was bypassed or silently granted. Subsequent independent GET and browser checks returned the mounted configuration successfully; the installed editor and PostgreSQL autofill were enabled. OS consent requirements are documented in the bilingual README. This was a runtime permission wait, not a failed configuration save.

## Protected state

Only the GUI service was updated/restarted. No migration, recreation, actual Odoo configuration save, or business-container start/stop/restart was performed.

All eight real containers retained their previous states and started timestamps. In particular, `hilite-odoo20` and `odoo19` remained stopped, and `postgres-odoo-apple` remained running. The mounted Odoo20 configuration's SHA-256 stayed unchanged:

`96582432ebb8460b510fe6aedcfffee792c0239ae198179aab25c6c422d5377d`

The internal configuration of stopped Odoo19 was not opened or altered. Editing it while stopped is deliberately unsupported rather than triggering migration or startup. Real-configuration saving remains for the user; automated saving/readback behavior was validated with isolated fixtures.

## Delivery boundary

The feature and version increment are one focused local commit. The existing untracked test is excluded. No GitHub push or PKG publication is part of this task. Generated `.specify/feature.json` remains ignored according to the repository's existing policy.
