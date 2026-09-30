# Implementation Plan: Unified container connections

**Branch**: `codex/local-ai-logs` | **Date**: 2026-10-01 | **Spec**: [spec.md](spec.md)

## Summary

One connection dialog for every container. Delegate Odoo to its existing safe editor; recognize a mounted, explicitly consumed app.env with literal DB_HOST/DB_PORT; expose direct Nginx proxy_pass URLs individually. Unsupported configuration remains read-only. Saves preserve credentials and unrelated bytes, keep private backups, require revision/target confirmation, and never perform lifecycle actions.

## Technical Context

- Language: Swift 6 and plain JavaScript.
- Dependencies: existing Hummingbird 2, CryptoKit, Foundation/Darwin; no new packages.
- Storage: existing application configuration discovered from CLI mounts; no shadow database.
- Testing: XCTest unit/HTTP fixtures and Node frontend tests; real environment read-only.
- Platform: Apple Silicon/macOS 26+; current host macOS 27, CLI 1.5.0.
- Limits: 128 KiB configuration files, at most 32 backend endpoints, bounded CLI requests, no network probes.
- Scope: one controlled GET/POST API and dialog, supporting Odoo, database dotenv and mounted Nginx.

## Constitution Check

PASS before and after design: CLI is target/mount/state authority; loopback HTTP; no arbitrary path or shell input; tests before code and fake execution; independent readback; no secrets in responses/audits; one Swift service/static UI; focused edits; version 2.26.0 and one local commit. No exception needed. No real business-container mutations, publication, or migration.

## Research decisions

See [research.md](research.md). A single-file bind mount cannot be safely replaced by rename while active. Edit it only while stopped/created, preserving inode and verifying bytes and metadata. Directory mounts use atomic replacement. Templates, includes other than mime types, dynamic URLs, upstream groups and guest-only Nginx are explicitly unsupported.

## Project Structure

```text
specs/018-container-connections/
  spec.md plan.md research.md data-model.md quickstart.md
  contracts/connections.md checklists/requirements.md tasks.md
Sources/ContainerGUI/
  Domain/ContainerConnectionModels.swift
  Operations/ContainerConnectionService.swift ConnectionDocument.swift
  Operations/OdooConfigurationFile.swift
  Web/ContainerControlRoutes.swift
  App/AppFactory.swift AppVersion.swift
  Resources/Public/odoo-database.js app.js index.html i18n.js
Tests/ContainerGUITests/Unit/ContainerConnectionTests.swift
Tests/ContainerGUITests/Contract/ContainerConnectionAPITests.swift
Tests/Frontend/ContainerConnectionTests.mjs
```

Reuse bounded host-file IO from the Odoo editor with a scoped data transform; retain its API and regressions. Reuse its frontend session with an explicit unified-mode option, preserving legacy semantics. No general plugin system or database drivers.

## Complexity Tracking

No constitution violations. In-place writes exist solely for stopped single-file mounts; all other host saves stay atomic. Manual application of saved settings is separate from configuration verification.
