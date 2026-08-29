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
