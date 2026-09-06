# Design QA — Mercury-style workbench, v2.19.0

## Findings

- No remaining actionable P0, P1, or P2 findings in the requested redesign.
- [P3, accepted] The reference uses slightly larger small UI text and a custom cube drawing. The implementation uses local system UI fonts and licensed Heroicons, retaining the reference's hierarchy and sharp vector assets without a remote font dependency.
- [Accepted product constraint] Keep automatic refresh, complete redacted diagnostics, SSH controls, operation feedback, and native modal confirmation. Do not add the mock's refresh glyph or its “界面概念 · 示例数据” footer to the real application.

## Visual truth and comparison method

- User reference: `design-qa-assets/mercury-reference.png`, copied unchanged from `codex-clipboard-3ec71239-fedd-4a21-b6ec-6da396883563.png`.
- Source dimensions: 1487 × 1058 pixels. The application area is the upper 1487 × 1000 pixels; the remaining 58 pixels are the concept-board caption, not application UI.
- Final light capture: `design-qa-assets/mercury-workbench-light.png`, 1487 × 1000 pixels at a 1487 × 1000 CSS viewport. No image scaling was used for comparison.
- State: Chinese, two running containers, `odoo19` selected, the same metrics and timestamp as the reference, logs not loaded, raw details closed.
- The original reference and final browser capture were opened together in the same comparison tool response. Sidebar boundary, topbar, page title, search, rows, selected state, and detail rail were compared at readable 1:1 scale. Separate region crops were unnecessary because these elements and their labels were readable in the full-size comparison.
- Additional captures: `mercury-workbench-dark.png` (1487 × 1000); `mercury-mobile-en.png` (390 × 844, English with a long container name); `mercury-confirmation-en.png` (English restart confirmation).
- Browser: Codex in-app browser, using its documented browser automation and viewport capability. The isolated fixture can force the existing light/dark CSS media branch for visual QA; production still follows `prefers-color-scheme`. No application data or theme override was added to production for screenshots.

## Required fidelity surfaces

- **Typography:** Local system sans-serif with Chinese fallbacks; charcoal headings, restrained weights, tabular numeric metrics. Name and image are separate lines. Long names wrap on desktop and clamp to two lines on narrow screens; complete information remains available in details and accessible labels.
- **Spacing and layout:** 246 px sidebar, 58 px utility bar, 88 px page header, 416 px desktop detail rail. Flat five-column table, selected lavender row, outlined actions, and generous white space match the source composition. Small-screen breakpoints stack the detail rail and keep navigation/actions reachable.
- **Colors and tokens:** White content, warm neutral sidebar, blue-violet primary/selection, semantic green running state, restrained red destructive outline. No glass blur, ornamental gradient, oversized rounded cards, or heavy shadows. Dark mode keeps the same hierarchy and spacing.
- **Assets:** Bundled MIT-licensed Heroicons for cube, window, stacks, search, close, and disclosure. Crisp vectors, no embedded screenshot, generated mock text, external CDN, or new raster decoration in the application.
- **Copy and content:** Chinese and English labels work in all three workspaces. The table explains that 100% represents all assigned cores. Real identifiers, image references, diagnostics, and resource values remain backed by the existing API. Version is 2.19.0, not the reference's illustrative 2.18.0.

## Comparison history and resolved issues

1. Initial desktop pass found that forcing the OS-dark browser against a light reference was not a valid color comparison. The isolated preview was given an explicit test-only media-branch setting; the light screenshot was then compared with the reference in the same response.
2. [P2, fixed] Navigation symbols were less close to the reference. Replaced them with bundled window/stack library icons. Final desktop captures show the corrected assets.
3. [P2, fixed] At 390 px in English, status and core-count columns crowded each other, and long names made rows unnecessarily tall. Adjusted narrow-screen column widths and added a two-line name clamp. `mercury-mobile-en.png` shows clear actions and no horizontal page overflow.
4. [P2, fixed] Sidebar health diagnostics could stay hidden after a failed health request following a healthy result. Clear the old healthy state and indicator in the failure branch. A regression test failed before the fix and passes after it.
5. [P2, fixed] Switching detail rows could retain old logs/actions or accept a late log response. Clear the old detail state, disable controls while loading, and ignore a response for a different selection. Browser row switching and the late-response regression test verify the change.
6. Final matched light comparison and separate dark/mobile inspections found no remaining P0/P1/P2 layout or interaction issue.

## Interaction evidence

Browser QA uses `Tests/Frontend/fixtures/WorkbenchPreview.mjs`, bound only to `127.0.0.1:8796`. It serves the real frontend with in-memory responses; it never calls the container CLI or production service.

- Sidebar navigation, safe `#main` fallback, selected state, and language switching.
- Detail open, repeat-click close, close button, focus return, selected row, and narrow-screen detail access.
- Container search, no matches, no containers, no images, and readable API failure feedback.
- Local images: 23 fixture images paginated as 10 / 10 / 3; disclosure arrow still toggles the image body.
- Repositories and tags: 10 items per page, numbered navigation through page 20, tag selection opens the prefilled pull dialog, cancel returns to the workspace.
- Pull submit and progress/completion region; system-start busy/verified state; creation operation feedback; restart confirmation and submission. All mutating actions in this list used fixtures only.
- Creation form: Odoo-only database fields, Ubuntu mode, keep-running preset, SSH enable/disable relationship, cancel, and successful fixture creation.
- Recent logs display safely. A deliberately closed fixture stream exposes the reconnect/interruption status without breaking the detail panel.
- 768 px layout and empty/error states; 390 px English long-name layout; light and dark desktop states.
- Browser console: no JavaScript errors or warnings in the final inspected states.

## Automated checks

- `node --test Tests/Frontend/*.mjs`: 28 passed.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`: 222 executed, 2 opt-in live tests skipped, 0 failures.
- JavaScript syntax checks and `git diff --check`: passed.
- Release build and managed local installation: passed. `GET /api/v1` returns 2.19.0; health is `healthy`, Apple container version is 1.3.1, and the new cube asset returns HTTP 200.
- Installed browser readback: real container details, detail toggle, sidebar navigation, local images, and an error-free JavaScript console verified. Both `odoo19` and `postgres-odoo-apple` remained running before and after the GUI-only service update.

## Implementation checklist

- [x] Match sidebar, utility header, table/detail hierarchy, and restrained palette.
- [x] Preserve image/registry pagination, form behavior, lifecycle controls, and bilingual UI.
- [x] Preserve local-only security boundaries; do not change CLI or API mutation behavior.
- [x] Verify focused regression tests and isolated browser interactions.
- [x] Compare source and final rendered implementation together.
- [x] Verify the installed local service without restarting or stopping user containers.

## Earlier design history

Version 2.2.1 replaced the rejected image-collapse text button with a chevron beside the title. The original expanded/collapsed captures remain in `design-qa-assets/local-images-chevron-expanded.jpg` and `design-qa-assets/local-images-chevron-collapsed.jpg`; that behavior is preserved in the new workbench.

final result: passed
