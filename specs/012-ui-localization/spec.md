# Feature Specification: Chinese and English UI

## Goal

Container GUI shall provide a complete Simplified Chinese and English interface without changing container-owned data.

## Requirements

- The header provides clearly visible `中文` and `English` choices.
- A saved user choice takes precedence; otherwise the first visit follows the browser language.
- The choice persists in the current browser and updates `html[lang]`.
- Static copy, dynamically rendered statuses, forms, dialogs, validation messages, pagination, SSH/Odoo guidance, placeholders, titles, and ARIA labels switch together.
- Container names, image references, identifiers, commands, logs, paths, environment values, and other user/runtime data remain unchanged.
- Newly rendered content after refresh uses the active language without reloading the page.
- The switch follows the existing Material 3 visual, focus, responsive, and reduced-motion conventions.

## Acceptance

- Automated tests cover browser-language selection, saved preference, bidirectional static copy, dynamic patterns, asset order, and switch styling.
- Browser verification demonstrates Chinese -> English -> Chinese switching on the live dashboard.
- GUI version is `2.16.0`; the completed update is committed and pushed with Git.
