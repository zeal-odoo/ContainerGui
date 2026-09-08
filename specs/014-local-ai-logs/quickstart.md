# Validation guide

1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`; `node --test Tests/Frontend/*.mjs`.
2. Install pinned model on isolated dev instance through explicit GUI action; verify progress and hashes.
3. Private worker synthetic connection-refused/empty/hostile logs: record load/generation, quality, RSS/footprint and exit. Configured units do not prove ANE use.
4. Browser readonly container logs: enable/result/disable during load and generation, repeated toggles, lease expiry, two languages, narrow layout. No user container mutations.
5. Full regressions, `git diff --check`, version2.21.0 and focused local commit. Do not publish.
