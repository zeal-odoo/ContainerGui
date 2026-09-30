# Implementation Plan: Edit an existing Odoo database endpoint

**Branch**: `codex/local-ai-logs` | **Date**: 2026-09-30 | **Spec**: [spec.md](spec.md)

**Input**: `specs/017-odoo-database-edit/spec.md`

## Summary

Add a detail-screen form and bounded read/save endpoints. Inspect the target through the official CLI; edit only `/etc/odoo/odoo.conf`. Host-mounted configuration uses secure native file access; a running internal configuration uses a fixed Python helper through structured `container exec` arguments. Unsupported stopped-internal configuration is explicit. Reuse the operation coordinator, safety middleware, and Chinese/English interface. No migration or automatic lifecycle actions.

## Technical Context

**Language/Version**: Swift 6, native browser JavaScript; fixed Python 3 helper only inside supported running Odoo containers.
**Primary Dependencies**: Existing Hummingbird, Foundation, Darwin, CryptoKit; no new package.
**Storage**: Existing configuration files and private sibling backups; no shadow database.
**Testing**: Swift Testing, HummingbirdTesting, Node tests with isolated files and fake command executors.
**Target Platform**: Apple silicon, macOS 26+, Container 1.3.1 / 1.4.1+ / 1.5.0.
**Project Type**: Existing single local Swift service and static web interface.
**Performance Goals**: Bounded 128 KiB configuration files and bounded command timeouts; no configuration reads in the recurring dashboard poll.
**Constraints**: No plaintext configuration/password responses or command arguments, arbitrary paths, shell interpolation, automatic starts/restarts, real-container writes in tests, or configuration migration.
**Scale/Scope**: One selected Odoo container and two editable settings per operation.

## Constitution Check

- CLI remains the authority for container identity, state, and mount mapping. Native file access is restricted to the actual host-mounted configuration, not CLI persistence or internal runtime APIs.
- Same-origin safety middleware and existing idempotency/target locks apply. No new authentication system or remote listener.
- Test invalid inputs, stale configuration, symlinks/hard links, permissions, bounds, failures, readback, and preservation before implementation.
- Incremental form + API is independent of AI, SSH, and container recreation.
- No migration, extra dependencies, generic file browser/editor, or unrelated refactor. Minor version becomes 2.25.0 in the same validated commit.
- No unresolved clarification: the user declined migration. No constitution exceptions.

## Project Structure

```text
Sources/ContainerGUI/Domain/OdooDatabaseModels.swift
Sources/ContainerGUI/Operations/OdooDatabaseService.swift
Sources/ContainerGUI/Operations/OdooConfigurationFile.swift
Sources/ContainerGUI/CLI/OdooDatabaseGuest.swift
Sources/ContainerGUI/Web/ContainerControlRoutes.swift
Sources/ContainerGUI/Resources/Public/odoo-database.js
Tests/ContainerGUITests/Unit/OdooDatabaseTests.swift
Tests/ContainerGUITests/Contract/OdooDatabaseAPITests.swift
Tests/Frontend/OdooDatabaseTests.mjs
specs/017-odoo-database-edit/{spec,plan,research,data-model,quickstart,tasks,validation}.md
specs/017-odoo-database-edit/contracts/api.md
```

**Structure Decision**: Extend the existing model/service/route/static-module layout and register the feature in AppFactory. Operation readback gains one optional bounded endpoint field; existing contracts remain backward compatible.

## Post-design Review

All gates pass. Preserve existing configuration bytes outside the active `[options]` endpoint assignments. Reject duplicate/ambiguous options and symlinks rather than inventing a generic editor. Backups are private; optimistic revision checks avoid overwriting intervening edits. No unresolved research questions remain after the read-only CLI and deployed-mount inspection.

Implementation uses the existing route helpers instead of duplicating them. Single-file bind mounts are explicitly rejected because atomic replacement could leave the guest reading its old inode; whole-directory mounts retain safe replacement semantics. The CLI parser adds only an optional boolean indicating the default Odoo configuration location, never its raw environment value.
