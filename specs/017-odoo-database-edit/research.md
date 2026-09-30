# Research decisions

## Existing interfaces

- **Decision**: No configuration migration; host-mounted `/etc/odoo/odoo.conf` can be edited while stopped, internal configuration requires a running Odoo with Python 3.
- **Rationale**: The user rejected migration. Container 1.5.0 has no configuration-update command; its [official copy test](https://github.com/apple/container/blob/1.5.0/Tests/IntegrationTests/Containers/TestCLICopyCommand.swift#L86) rejects non-running containers. The deployed Odoo20 mount is read-only in the guest but its host file is user-owned and writable.
- **Alternative rejected**: Starting, rebuilding, modifying Container persistence, or migrating stopped Odoo19 without authorization.

## File integrity and privacy

- **Decision**: Restrict paths to the fixed Odoo location derived from live CLI mount inspection. Bounded regular files only; reject symbolic/hard links. Preserve unrelated lines, original ownership/mode, create private backups, require SHA-256 revision, and verify by independent read.
- **Rationale**: Avoid exposing a generic host filesystem editor or passwords. Do not pass complete configuration contents in guest command arguments.
- **Alternative rejected**: Rewriting all settings through an INI serializer, returning raw configuration, and interpolating submitted text into a shell.

## Operation and UI conventions

- **Decision**: Reuse the current coordinator and `.container(id:)` lock. Add atomic create/replay disposition only for this service so concurrent retries dispatch one save. Reuse operation polling and add optional endpoint readback.
- **Rationale**: Planning research found the existing pre-read/create/task pattern can dispatch duplicate tasks on concurrent initial retries; this feature must not reproduce it. Existing lifecycle services remain out of scope.
- **Decision**: A separately owned modal editing session reads configuration only on open/reload; recurring detail refresh must not refill it. Capture target and request generation, cancel reads on close/switch, and reject late responses. Autofill uses observed PostgreSQL IP only, with no TCP probing or automatic save.
- **Rationale**: Dashboard refresh happens every five seconds; a persistent draft avoids lost user input and wrong-target saves.

All design questions have been resolved by read-only source/CLI inspection and the user's no-migration instruction.
