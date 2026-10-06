# V265 PageView No Vertical Motion

## Purpose

The Task Board carousel now follows the PageView.builder + PageController.page + AnimatedBuilder pattern from the referenced Flutter approach, but removes every vertical animation source so the carousel cannot create even a slight Y-axis movement.

## What changed

- Kept the carousel inside the invisible hard boundary added in v264.
- Locked the top nav and Task Board title outside the carousel paint area.
- Added strict no-vertical-motion controls:
  - `phaseStackStrictNoVerticalMotion: true`
  - `pageViewNoVerticalMotion: true`
  - `carouselNoVerticalMotion: true`
  - `taskBoardCarouselNoVerticalMotion: true`
  - `phaseStackPageHeightEffect: false`
  - `cardCarouselHeightEffect: false`
  - `pageViewHeightTransformEffect: false`
  - `phaseStackScaleYLocked: true`
  - `carouselTranslateYLocked: true`
- Renderer now keeps card movement on X-axis only:
  - `translateY = 0`
  - `rotateZ = 0`
  - `scaleY = 1.0`
  - height effect disabled in strict mode
- Side cards can still move horizontally, scale in width, rotate slightly on Y, and show depth/shadow.

## Result

During swipe and after snap:

- No title jump.
- No carousel top shift.
- No side-card vertical bobbing.
- No project-list overlap.
- No visible boundary line in production UI.
