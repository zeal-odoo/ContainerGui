# Implementation Plan

1. Add a dependency-free localization runtime loaded before the main application script.
2. Keep Simplified Chinese as canonical interface copy and provide an English catalog plus dynamic-pattern translations.
3. Translate existing and newly rendered DOM text/attributes while preserving user and runtime values.
4. Add a Material 3 segmented language switch and persist the selected language locally.
5. Re-render locale-sensitive values when the language changes.
6. Bump to `2.16.0`, run automated tests, validate the live browser, then commit and push.
