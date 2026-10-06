# v267 — iMessage Stack Visual, No Boundaries/Sections

## What changed
- Reworked the Task Board carousel into an iMessage-style stacked-card visual.
- Removed the artificial carousel boundary/section chrome from production UI.
- Disabled hard carousel top/bottom fence behavior for this visual mode.
- Kept PageView.builder + PageController.page motion.
- Kept strict no-vertical-motion rules: no translateY, no scaleY, no height transform.
- Kept v266 directional gesture lock so the parent vertical ListView does not steal the first horizontal swipe.

## QA checklist
- Swipe horizontally on Task Board carousel.
- Confirm title/nav do not move.
- Confirm page does not vertically scroll during horizontal carousel swipe.
- Confirm no boundary line, section separator, or debug overlay is visible.
- Confirm project/phase lower content still appears after active-card interaction.
