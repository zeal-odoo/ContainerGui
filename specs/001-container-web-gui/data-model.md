# Data Model: Apple Container Web GUI

The application has no persistent domain database. Every resource snapshot is derived from the current CLI
response; only bounded operation and log-session state lives in memory.

## 1. CLIInstallation

Represents the executable discovered at service startup and rechecked when a health request detects failure.

| Field | Type | Rules |
|-------|------|-------|
| `executablePath` | absolute path | Resolved executable, never supplied per HTTP request |
| `versionText` | string | Bounded to 1 KiB; retained for diagnosis |
| `semanticVersion` | string? | Parsed `major.minor.patch`; nil when unrecognized |
| `compatibility` | enum | `supported`, `unsupported`, `unrecognized`, `missing`, `notExecutable` |
| `checkedAt` | timestamp | UTC instant of the probe |

Identity: one installation per running GUI process. A path/version change replaces the prior in-memory value.

## 2. SystemHealth

An immutable snapshot of the CLI and its background service.

| Field | Type | Rules |
|-------|------|-------|
| `tool` | `CLIInstallation` | Required |
| `serviceState` | enum | `healthy`, `stopped`, `unregistered`, `degraded`, `unavailable`, `unknown` |
| `apiServerVersion` | string? | Redacted bounded text from structured status |
| `apiServerBuild` | string? | Optional |
| `apiServerCommit` | string? | Optional |
| `diagnosticCode` | string? | Stable GUI error code, never raw secret text |
| `diagnosticMessage` | string? | User-safe Chinese summary |
| `observedAt` | timestamp | Required |

The CLI may return non-zero for a known stopped/unregistered state. The client maps recognized structured status
to `serviceState`; exit code alone does not determine health.

## 3. ContainerSummary

Normalized fields used by list cards and action availability.

| Field | Type | Rules |
|-------|------|-------|
| `id` | string | Canonical full CLI identifier; non-empty; primary identity |
| `displayName` | string | User-facing name; falls back to `id` |
| `imageReference` | string? | Display only; may be absent in a newer/older schema |
| `state` | enum | `running`, `stopped`, `created`, `stopping`, `error`, `unknown(raw)` |
| `ipv4Address` | string? | Display only |
| `ipv6Address` | string? | Display only |
| `createdAt` | timestamp? | Optional because CLI schema may omit it |
| `observedAt` | timestamp | Time of the authoritative list read |

Unknown CLI fields are ignored. Missing `id` fails the whole affected item with `CLI_OUTPUT_INVALID`; an unknown
state remains visible as `unknown(raw)` and disables unsafe actions.

## 4. ContainerDetail

| Field | Type | Rules |
|-------|------|-------|
| `summary` | `ContainerSummary` | Required |
| `configuration` | generic JSON object | Recursively redacted before leaving the CLI layer |
| `status` | generic JSON object | Recursively redacted before leaving the CLI layer |
| `raw` | generic JSON value | Pretty-printed source-equivalent content after redaction |
| `observedAt` | timestamp | Required |

Redaction is case-insensitive for keys containing `password`, `passwd`, `secret`, `token`, `credential`,
`authorization`, `cookie`, `privateKey`, or environment values classified as secret.

## 5. RunConfiguration

One request to run a container. It is never stored after the operation no longer needs it.

| Field | Type | Rules |
|-------|------|-------|
| `image` | string | Required, 1-512 characters, no leading `-`, no control/NUL characters |
| `name` | string? | 1-128 characters; letters/digits plus `._-`; no leading `-` |
| `ports` | array of `PortMapping` | Maximum 32; no duplicate host IP/port/protocol tuple |
| `environment` | array of `EnvironmentEntry` | Maximum 128; unique names |
| `mounts` | array of `Mount` | Maximum 32; unique container target |
| `cpus` | decimal? | Positive and no greater than detected host logical CPU count |
| `memory` | byte count? | 1 MiB minimum; no greater than configured safe host limit |

### PortMapping

| Field | Type | Rules |
|-------|------|-------|
| `hostIP` | string? | Defaults to `127.0.0.1`; explicit non-loopback value triggers a visible warning |
| `hostPort` | integer | 1-65535 |
| `containerPort` | integer | 1-65535 |
| `protocol` | enum | `tcp` or `udp`; defaults to `tcp` |

### EnvironmentEntry

| Field | Type | Rules |
|-------|------|-------|
| `name` | string | POSIX-style name: `[A-Za-z_][A-Za-z0-9_]*` |
| `value` | string | Maximum 16 KiB; never included in preview/operation/error output |

### Mount

| Field | Type | Rules |
|-------|------|-------|
| `source` | absolute host path | Must exist at execution time; NUL/control characters rejected |
| `target` | absolute container path | Must be normalized, non-root and contain no `..` segment |
| `readOnly` | boolean | Defaults to `true`; write access must be explicitly selected |

The server converts a validated configuration to a fixed argument order. No free-form command or container
process arguments are part of this model.

## 6. RunPreview

A secret-free representation returned before execution.

| Field | Type | Rules |
|-------|------|-------|
| `image` | string | Normalized image reference |
| `name` | string? | Normalized name |
| `ports` | array | Normalized mappings |
| `environmentNames` | array of string | Names only; values omitted |
| `mounts` | array | Normalized source/target/read-only settings |
| `cpus` | decimal? | Normalized |
| `memoryBytes` | integer? | Normalized |
| `warnings` | array of code/message | Includes non-loopback publish or writable mount warnings |

## 7. Operation

In-memory record that protects and explains a command invocation.

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | Public lookup identity |
| `idempotencyFingerprint` | digest | Derived from key plus route/target; raw key is not logged |
| `kind` | enum | `startContainer`, `stopContainer`, `runContainer`, `deleteContainer`, `startSystem` |
| `target` | `OperationTarget` | Required; system or exact full container ID |
| `state` | enum | `queued`, `running`, `verifying`, `succeeded`, `failed`, `cancelled` |
| `requestedAt` | timestamp | Required |
| `startedAt` | timestamp? | Set once |
| `finishedAt` | timestamp? | Set for terminal state |
| `safeRequestSummary` | object | Secret-free, no environment values |
| `exitCode` | integer? | Present after process exit; not sufficient for success |
| `error` | `ProblemDetail`? | Present for failure/cancellation |
| `readback` | `OperationReadback`? | Required before `succeeded` |

Retention: completed records expire after 15 minutes; store is capped at 1,000 records, evicting oldest terminal
records first. Running records are never evicted. Reusing the same idempotency key with a different request returns
`IDEMPOTENCY_CONFLICT`.

### Operation state transitions

```text
queued -> running -> verifying -> succeeded
                   |            -> failed
                   -> failed
queued/running -> cancelled -> verifying -> succeeded|failed
```

Cancellation means the server requested child-process termination; the final resource state still comes from
readback. A request cannot transition directly from `running` to `succeeded`.

### Per-target concurrency

- At most one mutation may be `queued`, `running` or `verifying` for the same container ID.
- An independent container may run concurrently, subject to a global maximum of four mutation processes.
- System start uses the reserved target `system` and blocks new container mutations until its readback completes.

## 8. LogSession

| Field | Type | Rules |
|-------|------|-------|
| `id` | UUID | Internal diagnostic identity |
| `containerId` | string | Must reference a container observed immediately before launch |
| `tailLines` | integer | 0-10,000; default 200 |
| `state` | enum | `connecting`, `streaming`, `ended`, `cancelled`, `failed` |
| `startedAt` | timestamp | Required |
| `lastEventAt` | timestamp? | Updated as data is delivered |
| `droppedChunkCount` | integer | Incremented when bounded buffer discards data |
| `endReason` | string? | Secret-free reason/code |

No log content is persisted. Browser disconnect triggers cancellation and child-process termination. A keepalive
comment is emitted every 15 seconds; dropped output produces an explicit `warning` SSE event.

## 9. ProblemDetail

All API failures use one stable envelope.

| Field | Type | Rules |
|-------|------|-------|
| `code` | string enum | Stable machine-readable code |
| `message` | string | Chinese user-safe description |
| `retryable` | boolean | Whether retry may succeed without changing input |
| `operationId` | UUID? | Links mutation failure to operation record |
| `fieldErrors` | map? | Run-form field to validation message; never contains submitted values |
| `diagnosticId` | UUID | Correlates server log without exposing stderr |

Core codes: `CLI_NOT_FOUND`, `CLI_NOT_EXECUTABLE`, `CLI_VERSION_UNSUPPORTED`, `SERVICE_UNAVAILABLE`,
`CLI_TIMEOUT`, `CLI_EXIT_NONZERO`, `CLI_OUTPUT_INVALID`, `TARGET_NOT_FOUND`, `STATE_CONFLICT`,
`OPERATION_IN_PROGRESS`, `IDEMPOTENCY_CONFLICT`, `CONFIRMATION_MISMATCH`, `VALIDATION_FAILED`,
`ORIGIN_REJECTED`, `OUTPUT_LIMIT_EXCEEDED`, and `INTERNAL_ERROR`.

## Relationships and source-of-truth rules

- `SystemHealth`, `ContainerSummary`, and `ContainerDetail` are immutable snapshots, never durable records.
- An `Operation` targets one system or container identity and contains exactly one final readback outcome.
- A `LogSession` references one current container but does not extend the container's lifetime.
- `RunConfiguration` may create one container; the returned full container ID becomes the operation target before
  verification.
- If external CLI actions invalidate any relationship, the next authoritative read replaces it; the GUI never
  resolves conflict by overwriting external state.
