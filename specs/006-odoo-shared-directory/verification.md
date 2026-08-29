# Verification: Odoo 与通用共享目录

## Baseline and read-only environment

- Date: 2026-08-30 (Asia/Tokyo)
- Existing frontend baseline: 2/2 Node tests passed before feature implementation.
- Swift baseline build was started with the active Command Line Tools developer path; that path lacks the macOS XCTest module, so all authoritative Swift runs below use the already-installed full Xcode through a command-local `DEVELOPER_DIR` without changing global `xcode-select` state.
- `container --version`: `container CLI version 1.3.1 (build: release, commit: a9a62e2)`.
- `container create --help`: exposes `--mount <mount>` with `type`, `source`, `target`, and optional `readonly` fields.
- Read-only inspect of `docker.io/library/odoo:19.0-20260817` reports `ODOO_VERSION=19.0`, user `odoo`, entrypoint `/entrypoint.sh`, command `odoo`, and volume `/mnt/extra-addons`.

No container, image, volume, network, directory, or database was created or changed by these checks.

## Test-first evidence

- New Node test initially failed because `Sources/ContainerGUI/Resources/Public/odoo-create-form.js` did not exist.
- New Swift tests were added before the request models and CLI behavior; the first Swift attempt also identified the developer-path XCTest issue described above.

## Final automated verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`: 155 tests executed, 2 opt-in read-only smoke tests skipped, 0 failures.
- `node --test Tests/Frontend/*.mjs`: 4 tests passed, 0 failures.
- `node --check` passed for `app.js` and `odoo-create-form.js`.
- `git diff --check` passed.
- All authoritative Swift commands used command-local `DEVELOPER_DIR`; global developer-tool selection was not changed.

## Browser acceptance

- Restarted only the verified listener for this project on `127.0.0.1:8787`; `GET /api/v1` returned GUI version `2.8.0`.
- Generic state with `docker.io/library/ubuntu:26.04`: label `本机共享目录`, editable target `/workspace`, database fieldset hidden and disabled.
- Odoo state with local image `docker.io/library/odoo:19.0-20260817`: label `Odoo 自定义模块目录`, read-only target `/mnt/extra-addons`, database fields visible and enabled with defaults `db` and `5432`.
- Switching back to Ubuntu restored the generic label, editable `/workspace` target and hidden database fields.
- The dialog was inspected only; the create form was never submitted, so no container or directory was created.

## Git evidence

- Full changed-file, scope, secret-pattern, destructive-command and whitespace review passed.
- The semantic-versioned commit and `origin/main` push are verified after creation; the exact hash is reported in the final handoff.
