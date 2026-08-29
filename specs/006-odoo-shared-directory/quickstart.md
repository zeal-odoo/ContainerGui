# Quickstart Validation: Odoo 与通用共享目录

## Prerequisites

- Apple Container CLI 1.3.1 is installed and readable.
- Swift toolchain is available.
- Node.js is available for the small browser-logic test.
- `docker.io/library/odoo:19.0-20260817` may be inspected read-only; validation MUST NOT create a real container.

## 1. Automated tests

```bash
swift test
node --test Tests/Frontend/*.mjs
```

Expected:

- Domain tests reject invalid, missing, dangerous and nonexistent host paths before executor invocation.
- Exact official Odoo references are classified as Odoo; similar third-party names remain generic.
- CLI fixture tests show exactly one `--mount type=bind,source=...,target=...` argument and Odoo-only `HOST`/`PORT` arguments.
- HTTP tests prove redaction and rejection occur before the stub manager mutates.
- Browser tests prove field visibility, fixed `/mnt/extra-addons`, generic `/workspace`, and request shape.

## 2. Read-only CLI compatibility check

```bash
container --version
container create --help
container image inspect docker.io/library/odoo:19.0-20260817
```

Expected:

- CLI reports supported version 1.3.1.
- Help includes `--mount` with `type`, `source`, `target`, and optional `readonly` keys.
- Odoo image metadata includes `ODOO_VERSION=19.0`, `/entrypoint.sh`, `odoo`, and `/mnt/extra-addons`.

## 3. Browser acceptance without real submission

Start the updated local service, open `http://127.0.0.1:8787/#main`, and inspect the create dialog only.

1. Select `docker.io/library/ubuntu:26.04`.
   - The section says “本机共享目录”.
   - The container target defaults to `/workspace` and is editable.
   - No Odoo database fields are visible.
2. Select `docker.io/library/odoo:19.0-20260817`.
   - The section says “Odoo 自定义模块目录”.
   - The target is `/mnt/extra-addons` and cannot be edited.
   - Database address and port appear as `db` and `5432` and can be changed.
3. Switch back to Ubuntu.
   - Generic labels and editable `/workspace` return.
   - Odoo database values are not submitted.
4. Confirm the header displays `GUI v2.8.0`.

Do not press “创建容器” during this visual check; automated tests cover submission with stubs.

## 4. Git and release gate

```bash
git diff --check
git status --short
git log -1 --oneline
```

Expected:

- Specifications, source, tests and `AppVersion.current = "2.8.0"` are in one commit.
- The commit is pushed to `main` on the public `ContainerGui` repository.
