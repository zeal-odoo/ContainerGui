# Data model

- `OdooDatabaseView`: `containerId`, `isOdoo`, `editable`, optional `storage` (`hostMount` or `container`), `host`, `port`, opaque `revision`, `restriction`, and `observedAt`. Never contains full file contents, passwords, or environment values.
- `OdooDatabaseSaveRequest`: normalized valid `host`, integer `port` in 1...65535, exact `confirmationTarget`, and 64-character lowercase hex `expectedRevision`.
- `OperationKind.updateOdooDatabaseConfig`: target is the existing container lock. Safe request summary says only that endpoint settings are being changed. The fingerprint includes target/endpoint/revision; it contains no password.
- `OperationReadback.observedOdooDatabase`: optional endpoint-only view; success requires endpoint match after a fresh read. Existing operations omit this optional field.
- Backups are private sibling files with generated names; neither backup contents nor raw configuration cross the browser/API boundary.

State: queued -> running -> verifying -> succeeded/failed. No container lifecycle state transition is requested by this feature.
