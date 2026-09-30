# Controlled connection API

## GET /api/v1/containers/:containerId/connections

Return `ContainerConnectionView`. Recognized endpoints exclude secrets. Unknown, unsafe, stopped internal, template/include and running single-file forms return non-editable views with stable restrictions. CLI/target errors remain safe problems.

## POST /api/v1/containers/:containerId/connections

JSON: `endpointId`, `host`, `port`, `confirmationTarget`, `expectedRevision`. UUID `Idempotency-Key` required. No custom files/passwords accepted. Response 202 with operation Location, or safe validation/state/conflict problem.

Odoo delegates to existing endpoint service/readback. Other forms use `updateContainerConnection` with `observedConnections`. Exact replay returns same operation without redispatch; changed body with same key conflicts.

Shared Host/Origin/JSON/body-size checks remain. No create/start/stop/restart/reload commands or network probes. No raw files/CLI diagnostics in responses.

## UI

Every container has Connection configuration. Dialog distinguishes database/backend, selects one endpoint and disables save if unsupported/busy. PostgreSQL fills database draft once without saving. Refresh cannot reload drafts. Cancel/detail close/target switch invalidates outstanding responses. Success requires matching target/endpoint readback and instructs manual application.
