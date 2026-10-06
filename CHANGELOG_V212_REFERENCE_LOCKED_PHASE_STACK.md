# v212 Reference-Locked Phase Stack Carousel

## What was corrected after rechecking the supplied render

- Rebuilt the carousel card proportions as tall portrait cards, not wide dashboard cards.
- All eight phase cards remain visible inside one circular stack deck.
- Side cards only focus the queue; the active center card opens the phase project list.
- Project tap opens only tasks from that selected project and selected phase.
- Empty phase still opens the sheet/dialog and shows: `No task was in this phase.`
- Removed doubled dot matrices from v211. Each phase card now has only one visible top-right dot grid, matching the reference.
- Corrected the In Progress card art routing. It now uses the reference circle/vertical-line overlay instead of Todo artwork.
- Retuned typography to reference style: serif title/subtitle, smaller title scale, tighter icon row, thin divider, and no footer/status/progress rail.
- Added JSON controls for exact card width/height: `phaseStackCardWidth`, `phaseStackCardHeight`, `referenceCardWidth`, and `referenceCardHeight`.

## Files added

- `mobileEmployee_cleanWireframe_v212_reference_locked_phase_stack_FULL.json`
- `reference_locked_phase_stack_patch_v212.json`
- `firebase/sdui_v212/mobileEmployee_PUSH_THIS_v212.json`
- `firebase/sdui_v212/mobileEmployee_cleanWireframe_v212_reference_locked_phase_stack_FULL.json`
- `firebase/sdui_v212/reference_locked_phase_stack_patch_v212.json`
- `pmd_v212_reference_locked_phase_stack_render.png`
