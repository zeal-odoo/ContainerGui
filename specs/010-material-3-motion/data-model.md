# Data Model: Material 3 渐进响应动效

No persistent or API data model changes are required.

## Transient UI states

### Dialog motion state

- `closed`: native dialog is not open.
- `opening/open`: native dialog is open and may be playing its enter animation.
- `closing`: dialog remains open with `.is-closing` until the exit duration ends.

### Detail motion state

- `placeholder`: no detail is selected.
- `revealing`: detail content is visible with an enter animation.
- `closing`: detail content exits before the placeholder returns.

### Image disclosure state

- `expanded`: `aria-expanded=true`, body visible.
- `collapsing`: grid row/opacity animate toward zero.
- `collapsed`: `aria-expanded=false`, body hidden after transition.

These states are browser-only and are never sent to the server.
