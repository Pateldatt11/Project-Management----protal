# V219 Timeline Week/Month Responsive Fix

## Fixed
- Main Task Timeline Gantt map now uses a proper calendar window mode.
- Added Week / Month toggle for timeline map.
- Week mode uses a real calendar week window from Monday to Sunday.
- Month mode uses the selected calendar month from first date to last date.
- Previous / Today / Next controls shift the visible calendar window.
- Tasks that span two weeks are clipped to the visible week, so the first part shows in week one and the remaining part shows when moving to week two.
- Gantt map still shows 5 visible rows and activates inner scroll when the visible calendar window has 6+ rows.
- Selected Gantt row capsule is thicker and no longer clips text at the top edge.
- Full Timeline sheet also has Week / Month controls and selectable rows.
- Phase stack carousel height is reduced by 20% through code defaults and v219 Firebase patch keys.

## Files touched
- lib/features/tasks/presentation/task_timeline_screen.dart
- lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart
- firebase/sdui_v219/mobileEmployee_PUSH_THIS_v219.json
- firebase/sdui_v219/responsive_gantt_calendar_week_month_patch_v219.json
