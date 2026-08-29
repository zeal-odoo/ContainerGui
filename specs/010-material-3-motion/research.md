# Research: Material 3 渐进响应动效

## Official references

- Material 3 Motion overview: https://m3.material.io/styles/motion/overview
- Easing and duration tokens: https://m3.material.io/styles/motion/easing-and-duration/tokens-specs
- Dialog guidelines: https://m3.material.io/components/dialogs/guidelines
- Material `MotionScheme`: https://developer.android.com/reference/kotlin/androidx/compose/material3/MotionScheme
- Interaction states: https://m3.material.io/foundations/interaction/states/overview

## Decisions

### Spatial and effects motion are separate

Dialog/pane movement changes bounds or position and therefore uses a spatial curve. Backdrop, opacity and color use shorter effects motion. This keeps the interface responsive while making surfaces feel connected.

### Expressive motion is limited to prominent surfaces

Dialogs and detail panes use emphasized deceleration on enter and emphasized acceleration on exit. Repeated dashboard refreshes do not animate every table row, preventing distraction.

### Both directions are implemented explicitly

Native `dialog.close()` removes the surface immediately. A small JavaScript coordinator keeps the dialog open during the exit animation, then calls the native close method with the preserved return value.

### Reduced motion is functional, not cosmetic

When `prefers-reduced-motion: reduce` matches, JavaScript skips delayed closes and CSS reduces durations. State and focus behavior remain identical.

### No spring library

CSS easing and keyframes are sufficient for this compact web GUI. A physics library would add dependency and complexity without improving the core task.
