# Data model

## ContainerConnectionView

`containerId`, `kind` (`database`, `backend`, `unsupported`), `editable`, `endpoints[]`, optional `revision`, `storage` and `restriction`, `observedAt`.

No paths, passwords, API/TLS keys or full content. Odoo adapts its existing view. Unsupported views have no fabricated endpoint.

## ContainerConnectionEndpoint

`id` (selection within revision), `label` (fixed role or route), `host`, `port`.

Database ID: `database`. Nginx IDs: directive-order `proxy-1` etc, valid only with matching revision. At most 32 endpoints. Identical host/port on different routes remain independent.

## ContainerConnectionSaveRequest

`endpointId`, `host`, `port`, `confirmationTarget`, `expectedRevision`.

Exact target, endpoint membership, DNS/IP only, integer port 1...65535, SHA256 revision. Reject URL credentials, arbitrary paths/commands/control characters and stale files. Only the selected host/port can change.

## Operation/readback

New `updateContainerConnection` uses the shared container lock and safe target-only summary. Existing Odoo operation stays compatible. Optional `observedConnections` readback; unified frontend also adapts `observedOdooDatabase`.

`queued → running → verifying → succeeded|failed`. Lifecycle unchanged. Success requires fresh configuration readback matching the captured endpoint, not connectivity or application-health verification.
