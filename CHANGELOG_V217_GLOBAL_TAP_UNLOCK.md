# v217 — Global Tap Unlock Phase Stack Fix

Fixed the phase stack reveal bug found in v216.

## Problem
In v216, detail reveal was stored per phase ID, so after swiping to another phase the user had to tap again to see the lower project/task details.

## Fix
- Added a carousel-level `_phaseStackDetailsUnlocked` boolean.
- First tap on any phase card unlocks lower details globally.
- Swiping after unlock automatically refreshes the lower content for the active phase.
- Completed phase still renders details by default.
- Empty phases keep showing `No task was in this phase.`

## Files changed
- `lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart`
- `mobileEmployee_PUSH_THIS_v217.json`
- `mobileEmployee_cleanWireframe_v217_global_tap_unlock_phase_stack_FULL.json`
- `firebase/sdui_v217/*`
