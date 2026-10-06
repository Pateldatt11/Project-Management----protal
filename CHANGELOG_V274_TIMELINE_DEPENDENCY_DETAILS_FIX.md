# V274 Timeline Dependency, Details Panel, Color, and Week/Month Fix

## Timeline dependency line meaning

The green connected lines between Gantt bars are dependency connectors. They show that one task depends on another task before it can safely start. A delay in the predecessor task can affect the successor task and the downstream schedule.

The blue diamond at the end of a task bar is a milestone/completion marker.

## Changes made

- Fixed Week/Month filter behavior so the date window changes visibly.
- Week mode now shows a fixed six-week window around the selected focus date.
- Month mode now shows a wider multi-month window with compact day columns.
- Removed the old behavior where the timeline range expanded to all tasks, which made the week/month toggle look broken.
- Added bottom task detail panel when a row or Gantt bar is clicked.
- Details panel shows task title, project, assignees, start/end dates, status, priority, progress, and description.
- Admin / Project Manager / Team Lead can edit task status from the detail panel.
- Employees and other contributor roles remain view-only.
- Task bars now use varied Taskford-style colors instead of all completed tasks becoming the same green.
- Selected task row/bar now receives a blue focus border.

## Main file changed

lib/features/timeline/presentation/realtime_timeline_screen.dart
