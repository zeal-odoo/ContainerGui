# Quickstart and Validation Guide

This guide describes the expected runnable flow after implementation. Commands in the automated sections are
read-only with respect to existing Apple containers unless explicitly marked otherwise.

## 1. Prerequisites

Use an Apple Silicon Mac with macOS 26 and verify the locally installed tools:

```bash
swift --version
container --version
container system status --format json
```

Expected baseline for this plan:

- Swift 6.3.3 or a compatible Swift 6 release supported by the selected Hummingbird version.
- Apple `container` CLI 1.3.1.
- `container system status` may report a recognized stopped/unregistered state; that is a valid test state, not
  permission to start or install anything automatically.

## 2. Resolve, build and test

```bash
swift package resolve
swift build
swift test
```

Expected outcome: all fixture, unit and HTTP contract tests pass. The default test command must not start, stop,
create, delete or otherwise modify real containers.

Run the optional live read-only compatibility tests only when the local CLI may be queried:

```bash
CONTAINER_GUI_LIVE_READONLY=1 swift test --filter ReadOnlyCLISmokeTests
```

Expected outcome: the test records the CLI version and validates the current shapes for system status, container
list and, when available, one container detail. It performs no mutation.

## 3. Start the local service

```bash
swift run ContainerGUI
```

Expected startup log:

- resolved `container` executable path;
- detected CLI version and compatibility state;
- `http://127.0.0.1:8787` as the listen address;
- no environment variables, registry credentials or container secrets.

Open the page:

```bash
open http://127.0.0.1:8787
```

The application must reject non-loopback bind configuration in v1.

## 4. Validate User Story 1 (read-only MVP)

1. Open the dashboard and compare its system health with `container system status --format json`.
2. Compare the displayed container count and states with `container list --all --format json`.
3. Open one container detail and compare its identity/state with `container inspect CONTAINER_ID`.
4. Change nothing, then use the page's manual refresh and confirm the observed timestamp changes.
5. Validate the empty-list fixture through the HTTP contract test; do not delete real containers to create an
   empty environment.

Expected outcome: browser and CLI agree at the same observation point, and raw details are present with sensitive
keys redacted.

## 5. Validate User Story 2 (explicit disposable environment only)

This section performs real writes. Run it only after explicitly choosing a disposable test image/container and
confirming that the name does not collide with an existing resource. It is not part of automated tests.

1. Create or identify a disposable stopped container outside this guide.
2. From the detail page, start it once and verify the operation passes through running and verifying states.
3. Open recent logs, begin follow mode, generate known output in the disposable workload, then stop following.
4. Request a normal stop, confirm the full target shown in the modal and verify the final stopped readback.
5. Compare the page with `container inspect CONTAINER_ID` after each mutation.

Expected outcome: no duplicate process is launched on a double-click, each success contains fresh readback, and
log streaming ends when the browser disconnects.

## 6. API contract smoke checks

Read-only endpoints:

```bash
curl --fail --silent http://127.0.0.1:8787/api/v1/system/health
curl --fail --silent http://127.0.0.1:8787/api/v1/containers
```

Validate the responses against [contracts/openapi.yaml](contracts/openapi.yaml). Mutation tests use the in-process
HTTP harness with a fake command executor; do not copy mutation requests to a live service unless intentionally
testing a disposable target.

## 7. Failure-path acceptance

Run fixture tests for each required class:

- executable missing and non-executable;
- unsupported/unrecognized version;
- stopped/unregistered service with non-zero exit;
- timeout and cancellation;
- non-zero exit with stderr only;
- malformed, oversized and missing-required-field JSON;
- target removed or externally changed during mutation;
- duplicate idempotency key and simultaneous target mutation;
- log disconnect, invalid UTF-8, oversized line and bounded-buffer drop.

Expected outcome: every failure maps to the documented `ProblemDetail` code, no secret value appears in test
logs/responses, and no operation reports success without readback.

## 8. MVP completion gate

User Stories 1 and 2 are complete only when all of the following are true:

- `swift test` passes from a clean checkout;
- the OpenAPI contract tests pass;
- the optional read-only CLI smoke test passes against the recorded CLI version;
- the browser journey for list, detail, logs, start and stop passes on a disposable container;
- each mutation's final page state matches an independent CLI readback;
- no real destructive action occurred during automated tests.
