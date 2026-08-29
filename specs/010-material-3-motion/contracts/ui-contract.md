# UI Contract: Material 3 Motion

## Dialogs

- `openDialog(dialog, focusTarget)` is the only application path that calls `showModal()`.
- `closeDialog(dialog, returnValue)` preserves `returnValue`, supports cancellation, and calls native `close()` only after exit motion unless reduced motion is requested.
- Create, pull and confirm dialogs share the same CSS enter/exit/backdrop motion.

## Revealed surfaces

- `#detailContent` uses `.is-revealing` and `.is-closing`.
- `#imageSectionBody` uses `.is-collapsed`; its direct inner wrapper clips grid-row collapse.
- `.toast` uses `.is-showing` and `.is-hiding`.

## Accessibility

- Existing labels, focus targets, `aria-expanded`, `aria-controls`, `aria-live` and native dialog focus trapping remain unchanged.
- Escape is intercepted only to play the exit motion, then resolves as `cancel`.
- Reduced-motion preference removes meaningful delay from all state changes.
