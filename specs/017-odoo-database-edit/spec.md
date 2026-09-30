# Feature Specification: Edit an existing Odoo database endpoint

**Feature Branch**: `codex/local-ai-logs`

**Created**: 2026-09-30

**Status**: Approved scope

**Input**: After diagnosing changed PostgreSQL addresses, the user requested self-service endpoint editing and explicitly declined configuration migration: “不用迁移，直接开始吧”.

## User Scenarios & Testing

### User Story 1 - Edit the database address without rebuilding (Priority: P1)

A local user opens an Odoo container's details, reads its database address and port, edits them, and saves without retyping passwords or replacing the container.

**Why this priority**: An obsolete database address prevents Odoo from starting.

**Independent Test**: Save an endpoint in an isolated configuration fixture; independently reread it and verify that all other configuration bytes and the container state are unchanged.

**Acceptance Scenarios**:

1. **Given** an Odoo configuration already mounted from the host, **When** the user edits and saves its endpoint, **Then** the endpoint changes even if the container is stopped, its other settings are preserved, and a private backup remains available.
2. **Given** an Odoo configuration stored inside a running container, **When** the user saves, **Then** only its database endpoint changes and the container is not restarted.
3. **Given** a stopped Odoo with configuration stored inside it, **When** the user opens database configuration, **Then** an explicit limitation is displayed and saving is disabled; the application does not start, migrate, or rebuild it.
4. **Given** the configuration changed after it was read, **When** the user saves, **Then** saving fails with a reload instruction instead of overwriting the newer file.

### User Story 2 - Choose the current PostgreSQL address (Priority: P2)

The user can select a running PostgreSQL container to fill its observed address and the standard database port, or enter a different endpoint manually.

**Why this priority**: It reduces address-copying errors after network changes.

**Independent Test**: Select a database from fixture data and verify the form fields without making a connection or submitting a save.

**Acceptance Scenarios**:

1. **Given** a running PostgreSQL container with an observed address, **When** selected, **Then** the address without its subnet suffix and port 5432 fill the form; nothing is saved automatically.
2. **Given** an edited form, **When** the dashboard refreshes or the language changes, **Then** unsaved input is retained; selecting another container discards the old form rather than saving to the new target.

### Edge Cases

- Invalid host syntax, credentials embedded in a host, control characters, invalid port, wrong confirmation target, and duplicate saves.
- Missing or malformed configuration, duplicate options, symlinks, hard links, excessive file size, read-only host permissions, unsupported configuration locations, or another editor changing the file.
- Missing tool/service, command timeout, nonzero exit, unrecognized command output, stopped/deleted target, and conflicting lifecycle operation.
- A non-Odoo container must not gain a generic file-editing capability.

## Requirements

### Functional Requirements

- **FR-001**: Display endpoint configuration in Odoo details only, with Chinese and English labels and status messages.
- **FR-002**: Validate an address or hostname and port 1–65535 before any file change; require confirmation of the exact container.
- **FR-003**: Read only the endpoint and an opaque revision into the browser; never return passwords or the complete configuration.
- **FR-004**: Change only the two endpoint settings, retain other bytes and file permissions, create a private backup, and independently verify the result.
- **FR-005**: Reject a stale revision and serialize edits with the target's existing lifecycle operations.
- **FR-006**: Never automatically start, stop, restart, rebuild, or migrate containers; make the need for an explicit subsequent start/restart clear.
- **FR-007**: Support host-mounted configuration while stopped and internal configuration while running; explain unsupported cases without claiming success.
- **FR-008**: Allow autofilling from observed running PostgreSQL containers without connecting to arbitrary endpoints or saving automatically.
- **FR-009**: Automated tests must use isolated files and simulated commands, not alter the user's containers or databases.

### Key Entities

- **Database configuration view**: target, editable status, endpoint, storage kind, revision, reason for a restriction.
- **Save request**: exact target confirmation, new endpoint, and expected revision.
- **Save result**: independently observed endpoint and explicit manual-start/restart requirement.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can change a supported endpoint from the details screen without using a terminal, recreating a container, or reentering a password.
- **SC-002**: All invalid/stale-target safety scenarios reject the edit without changing the configuration.
- **SC-003**: Every successful save preserves unrelated configuration, keeps a private backup, and shows independently verified values.
- **SC-004**: Every unsupported stopped-internal case is explicit, with zero automatic lifecycle or migration operations.

## Assumptions

- The supported configuration location is `/etc/odoo/odoo.conf`; custom locations are rejected rather than guessed.
- The user's rejection of migration remains binding. Stopped internal configurations cannot be edited with the supported official interfaces.
- Address selection is a one-time fill, not a promise of automatic tracking after future network changes.
- This is a local update; GitHub publication and PKG release require a separate request.
