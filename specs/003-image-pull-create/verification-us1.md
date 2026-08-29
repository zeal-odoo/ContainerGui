# US1 Verification: 拉取镜像

**Date**: 2026-08-29

## Result

PASS. 镜像列表、拉取参数、幂等提交、操作轮询、镜像回读和页面资产均使用固定夹具或模拟执行器验证；未执行真实镜像拉取。

## Evidence

- `node --check Sources/ContainerGUI/Resources/Public/app.js`: PASS
- Focused unit, contract, browser and existing API regression suite: 18 tests, 0 failures
- Pull command shape: `image pull --progress none [--platform PLATFORM] REFERENCE`
- Success gate: exit code 0 plus `image inspect REFERENCE` readback and optional platform match
- Existing container read, metrics, control and logs contract tests remain green

## Final Gate

- Full Swift suite: 84 tests, 0 failures; 1 opt-in live test skipped by default
- Explicit read-only live CLI suite: 1 test, 0 failures
- Real browser against a temporary local service displayed 3 authoritative local images
- Invalid image input produced an inline field error and no mutation request
- The original feature gate executed no real pull; the later registry-shortcut incident is documented below

## Registry Shortcut Increment

- Browser asset suite: 3 tests, 0 failures
- Docker Hub selection resolves `postgres:latest` to `docker.io/library/postgres:latest`
- GHCR selection resolves `owner/image:tag` to `ghcr.io/owner/image:tag`
- A GHCR-qualified address combined with Docker Hub resolves to `null` and is rejected before normal submission
- The existing platform selector is now labelled “目标架构” and still submits `linux/arm64` or `linux/amd64`

## Remote Registry Search Increment

- TDD baseline: new registry client, API contract and browser tests failed before the implementation types and UI existed.
- Backend focus: 14 tests, 0 failures, covering fixed Docker Hub/GitHub hosts, scoped GHCR paths, API version,
  Bearer header, multi-page fixture parsing, response bounds, validation, rate limits and token-safe errors.
- Browser assets: 6 tests, 0 failures; JavaScript syntax check passed.
- Final full Swift suite: 98 tests, 0 failures; 2 opt-in read-only tests skipped by default.
- Explicit live read-only CLI suite: 1 test, 0 failures.
- Explicit Docker Hub GET-only suite: 1 test, 0 failures.
- Runtime service: current build listens on `127.0.0.1:8787`; `/api/v1/images` returned all 3 local images.
- Runtime Docker Hub: repository page 1 returned 20 of 52757 and tag page 1 returned 20 of 1421; both exposed a next page.
- Browser pagination appended repositories from 20 to 40 with 40 unique references, and tags from 20 to 40 with
  40 unique references.
- Selecting exact tag `docker.io/library/postgres:15.19-trixie` opened the pull dialog and filled the full reference;
  the selection handler contains no pull submission and “开始拉取” was not clicked.
- GHCR without `CONTAINER_GUI_GITHUB_TOKEN` displayed the safe configuration error, hid the stale loading state and
  left all 3 local image rows visible. The Token is read only from the service environment and never enters the page.
- GitHub's optional `visibility` filter is intentionally omitted so the owner listing preserves every package the
  configured Token can read, including public, private and internal packages.
- This increment performed only local/remote GET reads. It did not pull an image or create, start, stop or delete a container.

## Live Validation Boundary Incident

During the 2026-08-29 registry-shortcut browser check, the attempted Playwright request interception failed before
the submit click. One real request consequently reached the local service:

`container image pull --progress none --platform linux/arm64 docker.io/library/postgres:latest`

It completed before the process could be terminated. The authoritative readback changed the local
`docker.io/library/postgres:latest` tag from the previously observed multi-platform index
`sha256:4aabea78cf39b90e834caf3af7d602a18565f6fe2508705c8d01aa63245c2e20` to the ARM64 variant
`sha256:4ef4dbc939d61acea57712655ddb4b4ab27419c913f94cca0cd57cb3ea3c2280` (`linux/arm64/v8`,
161067506 bytes). The existing `postgres-odoo-apple` container remained running; no container create, start, stop
or delete command was issued. No compensating pull was performed because restoring the multi-platform reference is
another real mutation and requires explicit user authorization.
