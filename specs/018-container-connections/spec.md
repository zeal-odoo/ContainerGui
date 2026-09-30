# Feature Specification: Unified container connection configuration

**Feature Branch**: `codex/local-ai-logs`
**Created**: 2026-10-01
**Status**: Approved scope
**Input**: “给所有容器都添加连接数据库的功能”; user selected option 2: database connections plus backend service addresses, including Nginx proxy targets.

## Clarifications

### Session 2026-10-01

- Q: Only databases or also gateway backend addresses? → A: Option 2, both.
- Existing constraints remain: no migration, no password changes, no automatic business-container lifecycle action.

## User Scenarios & Testing

### User Story 1 - One entry for every container (Priority: P1)

Users open any container's connection configuration and see recognized database/backend endpoints or an explicit limitation.

**Why this priority**: Users need an intuitive entry without guessing the application configuration.
**Independent Test**: Open database, gateway, and unrelated container fixtures; all expose the entry with correct editability and no file changes.

**Acceptance Scenarios**:

1. **Given** Odoo or a supported database-configured application, **When** opened, **Then** database endpoints appear without credentials.
2. **Given** a supported Nginx gateway, **When** opened, **Then** backend endpoints appear separately from database connections.
3. **Given** an unsupported container/configuration, **When** opened, **Then** a reason appears and saving is disabled.

### User Story 2 - Edit a database endpoint (Priority: P2)

Users edit an existing database address/port, optionally filling the observed PostgreSQL address, while preserving passwords and other settings.

**Why this priority**: Network changes can invalidate application database addresses.
**Independent Test**: Save isolated database configuration fixtures and verify unrelated bytes, private backups, and independent endpoint readback.

**Acceptance Scenarios**:

1. **Given** a supported writable configuration, **When** saved, **Then** only its endpoint changes; applying it is a separate manual action.
2. **Given** an observed running PostgreSQL, **When** selected, **Then** its address and standard port fill the form without saving or probing.
3. **Given** unsupported storage/state or an externally changed file, **When** saved, **Then** the edit is rejected and the draft remains.

### User Story 3 - Edit a gateway backend (Priority: P2)

Users select one backend endpoint and edit its address/port without changing route paths, authentication, TLS, or other endpoints.

**Why this priority**: The stopped BettaFish gateway has an obsolete backend address, not a database connection.
**Independent Test**: Edit one of several backend fixtures and verify only occurrences of that exact endpoint change.

**Acceptance Scenarios**:

1. **Given** routes with different backend ports, **When** one endpoint changes, **Then** other ports and routing suffixes remain intact.
2. **Given** a supported stopped gateway with a mounted configuration, **When** saved, **Then** backup and readback succeed without starting it or migrating its mount.
3. **Given** ambiguous/dynamic gateway configuration, **When** opened, **Then** its limitation is explained instead of guessed.

### Edge Cases

- Wrong target/endpoint, invalid address/port, credentials or control characters, stale revision, repeated requests, lifecycle conflicts, and replaced containers.
- Missing/duplicate/ambiguous settings, unsafe or linked files, excessive content, volume permissions, stopped internal configurations, and running single-file mounts.
- Late responses, container switches, dialog cancellation, language changes, and dashboard refresh must preserve drafts and correct target ownership.
- File save is not database connectivity or application readiness; no automatic network probe or lifecycle action.

## Requirements

### Functional Requirements

- **FR-001**: Every container detail exposes a bilingual connection entry; recognized connections have distinct database/backend labels.
- **FR-002**: Retain existing Odoo editing; add safely recognized database-environment configurations and direct Nginx backend endpoints.
- **FR-003**: Unknown, non-applicable, ambiguous, and unsafe forms remain explicitly non-editable; never invent settings for arbitrary images.
- **FR-004**: Return endpoints and opaque revisions only; never expose passwords, API/TLS keys, whole files, or secret-bearing paths.
- **FR-005**: Validate exact target, selected endpoint, address, port, and revision; only edit actual supported configuration discovered from the container.
- **FR-006**: Preserve unrelated bytes and ownership/permissions, make a private backup, and independently verify saves. Mounted-file edits must be visible to the container, not just the host.
- **FR-007**: Serialize saves with container actions; dispatch idempotent requests once, release locks on failure, retain drafts.
- **FR-008**: Never migrate, recreate, start, stop, restart, reload, or change passwords automatically; required application actions are manual.
- **FR-009**: Autofill uses current observations once, without future tracking or a connectivity promise.
- **FR-010**: Tests use isolated files/fake execution; actual configuration and business-container states remain unchanged.

### Key Entities

- **Connection view**: target, connection type, available endpoints, revision, storage, editability, and restriction.
- **Endpoint**: selection identifier, host, port, user-facing role.
- **Save request/result**: captured target/endpoint/revision and independently verified readback.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All containers expose the entry; unsupported forms show a reason and disabled save.
- **SC-002**: Supported endpoints can be edited without a terminal, credential reentry, or migration.
- **SC-003**: Every successful fixture save changes only the selected endpoint, keeps a private backup, and matches independent readback.
- **SC-004**: Invalid/ambiguous/stale/prohibited scenarios change no configuration and perform zero lifecycle actions.
- **SC-005**: Refresh and late responses cannot overwrite drafts or newly selected targets.

## Assumptions

- “All containers” means a universal entry with honest type-specific support, not forcing every image to consume invented parameters.
- Initial forms are existing Odoo configuration, recognizable database environment files, and direct Nginx backend URLs. Arbitrary custom formats, database login, and database creation are out of scope.
- This is local only; GitHub push and PKG publication require a separate request.
