# Research: Apple Container Web GUI

**Date**: 2026-08-29
**Verified local baseline**: macOS 26, Apple Silicon, Swift 6.3.3, `container` CLI 1.3.1

## Decision 1: Use Hummingbird 2 for the local Swift web server

**Decision**: Use Hummingbird 2.26.x with its router, middleware, static-file support and testing
utilities. Package resolution may accept compatible 2.x releases, while `Package.resolved` records the
exact tested revision.

**Rationale**: Hummingbird describes itself as a lightweight SwiftNIO-based server with a minimal
dependency goal. It supports Codable JSON routes, middleware, lifecycle management and an official
testing module. Its official examples include static file serving and Server-Sent Events, which cover
this product without adding a template engine or WebSocket package. The installed Swift 6.3.3 exceeds
the framework's Swift 6.1 minimum introduced in Hummingbird 2.22.

**Alternatives considered**:

- Vapor 4: mature and capable, but Leaf, Fluent and the broader application stack add no value for a
  database-free local tool.
- `Network.framework` or raw SwiftNIO: fewer high-level dependencies but would require implementing
  routing, body limits, error conversion, static files and test harnesses ourselves.
- SwiftUI-only native application: good native experience but does not satisfy the requested B/S
  architecture; it remains a possible later thin launcher/menu-bar client.

**Primary sources**:

- [Hummingbird overview](https://docs.hummingbird.codes/2.0/documentation/hummingbird/)
- [Hummingbird 2.26.0 release](https://github.com/hummingbird-project/hummingbird/releases/tag/2.26.0)
- [Official Server-Sent Events example](https://github.com/hummingbird-project/hummingbird-examples/tree/main/server-sent-events)

## Decision 2: Wrap the official CLI instead of linking internal container APIs

**Decision**: Resolve and invoke the installed `container` executable through `Foundation.Process`.
Use JSON output for supported read commands and typed parsers at the adapter boundary. Do not link the
Containerization package or call the container apiserver/XPC interface directly in v1.

**Rationale**: The CLI is the product's user-visible, versioned interface and exposes JSON for container
lists, system status and stats; inspect commands already emit JSON. The lower-level Containerization
package explicitly limits source stability within minor versions, and direct apiserver integration would
couple the GUI to internal authorization and compatibility details. A CLI wrapper also sees changes made
from Terminal without maintaining a second state store.

**Alternatives considered**:

- Apple Containerization Swift package: attractive because it is native Swift, but its API is lower level
  than the installed CLI service and has a tighter source-compatibility window.
- Direct XPC/apiserver calls: lower process-launch overhead, but relies on internal contracts and entitlement
  behavior that are not needed for the expected single-user scale.
- Parsing table output: fragile under localization/column changes; JSON is available for the required reads.

**Primary sources**:

- [`container` 1.3.1 command reference](https://github.com/apple/container/blob/1.3.1/docs/command-reference.md)
- [Apple Containerization stability statement](https://github.com/apple/containerization)

## Decision 3: Define an explicit CLI command matrix

**Decision**: `ContainerCLIClient` exposes only typed methods from the following allowlist. Arguments are
passed as an array; no method accepts a raw subcommand string.

| Capability | CLI invocation shape | Output | Timeout | Required readback |
|------------|----------------------|--------|---------|-------------------|
| Tool version | `container --version` | bounded text | 2 s | none |
| System health | `container system status --format json` | JSON object | 5 s | n/a |
| Container list | `container list --all --format json` | JSON array | 5 s | n/a |
| Container detail | `container inspect ID` | JSON | 5 s | n/a |
| Start | `container start ID` | bounded text | 120 s | inspect/list ID |
| Stop | `container stop --time 10 ID` | bounded text | 30 s | inspect/list ID |
| Recent logs | `container logs -n N ID` | bounded bytes | 10 s | none |
| Follow logs | `container logs --follow -n N ID` | byte stream | session lifetime | none |
| Run | `container run --detach [allowed flags] IMAGE` | progress/text | 15 min | list/inspect returned ID |
| Delete | `container delete ID` | bounded text | 30 s | list confirms absence |
| System start | `container system start --disable-kernel-install --timeout 30` | progress/text | 120 s | system status |
| Confirmed kernel start | `container system start --enable-kernel-install --timeout 120` | progress/text | 10 min | system status |

Container identifiers must match a conservative non-empty resource-id grammar and must come from a recent
list/detail read. The GUI never exposes `kill`, `--all`, `--force`, `exec`, registry login, arbitrary process
arguments, custom kernels or custom runtime paths in this feature.

## Decision 4: Normalize only stable fields and retain redacted raw JSON

**Decision**: Decode the CLI's outer resource shape (`id`, `configuration`, `status`) into tolerant DTOs.
Map only fields needed by the UI into stable domain models and retain a generic `JSONValue` copy for the raw
detail panel after recursive redaction. Ignore unknown fields; fail with `CLI_OUTPUT_INVALID` when a required
identity/state field is absent or the top-level shape is wrong.

**Rationale**: Local readback confirmed that CLI 1.3.1 container list items use outer keys `id`,
`configuration`, and `status`, while system status exposes version/build/root/status fields. Keeping raw JSON
available helps diagnosis, but binding the whole frontend to Apple's nested schema would make every CLI change
a UI change.

**Alternatives considered**:

- Mirror all CLI structs: high coupling and unnecessary for the MVP.
- Treat every response as untyped JSON: easy initially but pushes schema mistakes into route/UI code.
- Persist normalized objects: violates the CLI-as-source-of-truth rule and creates stale-state handling.

## Decision 5: Use polling for state and SSE only for continuous output

**Decision**: The browser performs a five-second conditional refresh while the dashboard is visible and also
offers manual refresh. Logs use one Server-Sent Events connection per visible log viewer. Mutation progress is
read via operation polling in v1; it can adopt SSE later without changing the operation model.

**Rationale**: Container state is small and only one local user is expected. Polling is simpler and self-heals
after browser sleep or connection loss. Logs are naturally one-way, long-lived data, making SSE a better fit
than polling or WebSocket.

**Alternatives considered**:

- WebSocket for everything: adds bidirectional connection lifecycle without a current bidirectional need.
- Server-side state watcher: adds hidden cached state and coordination complexity.
- Log polling: loses streaming behavior and repeatedly launches short-lived CLI processes.

## Decision 6: Keep safety and idempotency in the server, not only the modal

**Decision**: All mutation routes require same-origin JSON requests and an `Idempotency-Key`. The in-memory
`OperationCoordinator` deduplicates a key for 15 minutes, serializes operations per target and records the final
readback. Dangerous routes additionally require `confirmationTarget` to exactly match the current full target
identifier. The browser modal is presentation; server validation is authoritative.

**Rationale**: Browser refreshes, retries and double-clicks can repeat requests. A UI-only confirmation does not
protect the process boundary, and a global lock would unnecessarily block unrelated containers.

**Alternatives considered**:

- Disable buttons only: insufficient across tabs and network retries.
- Persistent job database: unnecessary for a single-process local tool and would imply recovery semantics not
  required in v1.
- Global serial queue: simpler but makes slow image pulls block every container action.

## Decision 7: Apply a local-web security profile

**Decision**: The listen host is a compile-time/default invariant of `127.0.0.1`; configuration can change the
port but not the host in v1. Disable CORS, reject mutation requests whose `Origin` is absent or not the service's
own origin, require JSON content type, cap request bodies at 64 KiB and set CSP plus standard anti-sniffing/frame
headers. Static assets are packaged, not fetched from a CDN. Logs omit headers and all environment/credential
values. Secrets in run requests are used once and redacted before operation recording.

**Rationale**: Loopback services can still be targeted by malicious web pages through the user's browser. Same-
origin enforcement, no CORS and strict request shapes reduce cross-site request risks without adding accounts
or TLS to a local-only product.

**Alternatives considered**:

- No web security because the host is loopback: rejected because browsers can send cross-origin requests to
  loopback addresses.
- Authentication for MVP: adds credential lifecycle without protecting against more than the explicit
  local-only threat model; it becomes mandatory if remote binding is ever introduced.

## Decision 8: Bound processes, output and memory

**Decision**: The executor drains stdout and stderr concurrently, supports cooperative cancellation followed by
termination, enforces per-command timeouts, and caps non-streaming output at 16 MiB. Log SSE uses a bounded
buffer and emits a truncation/drop notice rather than growing memory. At most eight follow sessions and four
unrelated mutation processes may run concurrently.

**Rationale**: Waiting for a full pipe can deadlock a child process; unbounded inspect/log output can exhaust a
small local service. Explicit limits also make error behavior testable.

**Alternatives considered**:

- `Process.waitUntilExit()` with post-read pipes: can deadlock when pipe buffers fill.
- Unbounded async streams: simplest code, unsafe for noisy containers or a paused browser.
- Redirect temporary files: complicates cleanup and risks persisting secrets/logs.
