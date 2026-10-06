# v231 - Phase Project Direct Task Fix

- Fixed the phase carousel project preview tap flow.
- When a project row is tapped under the active phase card, the phase dialog now opens directly on that project's task list.
- This fixes the Completed phase issue where tapping a project row opened the same project list again instead of showing tasks.
- View all / phase-card tap still opens the normal project list first.
- Task filtering remains phase-aware: only tasks from the tapped project and selected phase are shown.

Changed file:
- lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart
