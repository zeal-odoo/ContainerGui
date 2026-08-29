# Design QA

## Reference and scope

- Reference: `/var/folders/31/k29n4k9x23g778c2mhb44qcw0000gn/T/codex-clipboard-1a7435ac-a9f7-4487-af60-3da0cb08d127.png`
  (3854 × 1110 px).
- Authoritative correction: remove the right-side “收起镜像” text button and place a chevron beside “本机镜像”; the chevron points down when expanded and right when collapsed.
- Scope preserved: existing typography, dark theme, table, “创建容器” and “拉取镜像” controls remain unchanged.

## Implementation evidence

- Expanded: `design-qa-assets/local-images-chevron-expanded.jpg` (1265 × 712 capture from a 1280 × 720 CSS viewport).
- Collapsed: `design-qa-assets/local-images-chevron-collapsed.jpg` (1265 × 712 capture from a 1280 × 720 CSS viewport).
- Runtime: Container GUI `2.2.1` at `127.0.0.1:8787`.

## Comparison

- Expanded state: the chevron is immediately beside the title, points down, and the four-row image table remains visible.
- Collapsed state: the same control points right and the image table/status body is hidden while the header actions remain visible.
- The rejected text button is absent; the right action group contains only “创建容器” and “拉取镜像”.
- The icon uses the bundled Heroicons chevron asset and retains the existing muted/accent styling.
- Keyboard and assistive state match the visual state through `aria-controls`, `aria-expanded`, and the “收起/展开本机镜像” accessible name.

## Findings and history

- P0: none.
- P1: none.
- P2: none.
- P3: none in the requested scope.
- History: GUI `2.2.0` used the rejected right-side text button. GUI `2.2.1` moved the disclosure control beside the title and verified both arrow directions in the live browser without triggering container or image mutations.

final result: passed
