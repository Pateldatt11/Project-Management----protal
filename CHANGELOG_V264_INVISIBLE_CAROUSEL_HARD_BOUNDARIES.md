# V264 - Invisible Carousel Hard Boundaries

- Added an invisible hard paint boundary for the Task Board phase carousel only.
- The top nav and Task Board title remain normal and locked; no visible zone lines are rendered.
- Carousel cards can keep side depth and bottom shadow inside their own expansion zone.
- Upward paint into the title/nav area is blocked.
- Downward paint over the phase project list is bounded.
- JSON flags added for `carouselOnlyTopBoundaryLocked`, `carouselOnlyBottomBoundaryLocked`, `carouselOnlyBoundaryVisible: false`, and `carouselPaintBoundaryMode: invisibleHardFence`.
