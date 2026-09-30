# Validation guide

1. Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OdooDatabase` and `node --test Tests/Frontend/OdooDatabaseTests.mjs`.
2. Run the complete Swift and tracked frontend suites, plus `git diff --check`.
3. Launch the built GUI on a separate loopback port for read-only browser validation: open Odoo20 configuration while stopped, inspect its address and port, cancel; inspect the stopped-internal Odoo19 restriction; verify both languages and no secret fields.
4. Tests save only isolated host files or use fake CLI execution. Verify the internal guest helper against an isolated temporary file, including preservation, backup, stale revisions, unsafe files, and failure paths.
5. Do not click Save against the user's deployed configuration or start/restart any business container. Such a real write is outside this validation authorization.
6. Confirm unchanged real container states; deploy only the GUI update, then verify its version/health and read-only form. Commit version 2.25.0 together with the feature. Do not push or release a PKG.
