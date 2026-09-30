# Odoo endpoint API

## GET /api/v1/containers/:containerId/odoo/database-config

Return `OdooDatabaseView` from live target inspection. Non-Odoo targets return `isOdoo=false`. Stopped internal configuration returns `editable=false`, `restriction=stoppedInternal`, without executing or starting the container. Unsupported/missing/unsafe configuration returns a bounded restriction. File contents and credentials are never returned.

## POST /api/v1/containers/:containerId/odoo/database-config

Existing exact Host/Origin, JSON body limits, and UUID `Idempotency-Key` requirements apply. JSON fields are `host`, `port`, `confirmationTarget`, `expectedRevision`; no client-supplied path, file contents, command, or password.

- 202 + operation and Location: accepted once; an exact replay returns the existing operation.
- 422: invalid fields or mismatched confirmation.
- 409: newer configuration, unsupported state, conflicting target mutation, or different request using the same key.
- Command failures/timeouts preserve existing sanitized problem contracts.

Saving does not apply or restart Odoo. Success means the file was independently read back and verified; the user performs a separate start/restart with the existing controls.
