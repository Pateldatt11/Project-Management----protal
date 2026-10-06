# V272 - Taskford-style realtime Gantt timeline

## Scope

This update replaces the first simple Timeline/Gantt screen with a denser Taskford-style work-item planner while keeping it as a **new web-only screen**. No existing Tasks, Kanban, Projects, or SDUI mobile screen was converted.

## Added / improved

- Work-item toolbar matching the reference style:
  - Search and filter work item
  - Project dropdown
  - View: Default / Modified badge
  - Group by Project / Assignee / Status
  - Filter sheet for status and priority
  - Critical path toggle
  - Baseline toggle
  - Previous / Next / Today controls
  - CSV export to clipboard
- Frozen left work-item table:
  - # column
  - Hierarchical project/work-item tree
  - Assignee avatars
  - Progress bars
  - Warning indicators for overdue / critical items
- Right Gantt grid:
  - Month/week/date header
  - Weekend shading
  - Today vertical red marker
  - Important date markers
  - Parent project bars
  - Task bars with progress fill
  - Baseline striped bars
  - Critical-path dependency connector lines
  - Milestone diamond for completed tasks
- Real data integration remains through `workspaceProvider`.
- Existing edit restrictions remain enforced:
  - Super Admin / Admin / Project Manager / Team Lead can drag/update dates.
  - Employee / Developer / QA / Designer / DevOps can view only.

## Changed file

```text
lib/features/timeline/presentation/realtime_timeline_screen.dart
```

## Build note

After extracting the zip, run:

```bash
flutter pub get
flutter analyze
flutter build web
```
