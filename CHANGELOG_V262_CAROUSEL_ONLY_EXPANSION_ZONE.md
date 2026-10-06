# v262 — Task Board Carousel-Only Expansion Zone

## What changed

- Removed the global Task Board top protection padding from the page layout.
- Kept the top nav and Task Board title/header in their normal fixed page zones.
- Added a dedicated expansion/safety area owned only by the phase carousel.
- The carousel can now expand downward inside its own section during swipe/stack rendering.
- The carousel top boundary is locked below the title, so cards cannot push the title or nav upward/downward.
- The PageView remains horizontal-only and one-card-per-swipe.
- Empty phase tap behavior remains: opens the phase sheet/dialog and shows “No task was in this phase.”

## Important SDUI keys

```json
{
  "taskBoardPageTopPadding": 0,
  "taskBoardNormalTopPadding": 0,
  "taskBoardTitleTopProtectionPadding": 0,
  "taskBoardTopProtectionPadding": 0,
  "carouselOnlyExpansionZoneEnabled": true,
  "taskBoardCarouselExpansionZoneEnabled": true,
  "phaseStackCarouselOnlyExpansionZone": true,
  "carouselOnlyBottomExpansion": 56,
  "compactCarouselOnlyBottomExpansion": 44,
  "carouselOnlyTopFenceInset": 0,
  "carouselExpansionScope": "carouselOnly",
  "carouselExpansionDirection": "down",
  "carouselExpansionAffectsPagePadding": false,
  "carouselExpansionAffectsTitlePadding": false,
  "lockTaskBoardTitleDuringCarouselSwipe": true,
  "lockTopNavDuringCarouselSwipe": true,
  "carouselTransformAxis": "xOnly"
}
```

## QA expectation

- Before swipe: normal nav, normal title, carousel starts below title.
- During swipe: only carousel cards animate; carousel has extra downward space for stack/shadow.
- After snap: no global padding reset, no title movement, no vertical jump.
