# V271 Realtime Web Timeline Integration

Added a new web Timeline/Gantt screen without converting any existing screen.

## Added

- `lib/features/timeline/presentation/realtime_timeline_screen.dart`
- New `MainSection.timeline` sidebar item.
- Realtime timeline connected to existing `workspaceProvider` streams:
  - Projects
  - Tasks
  - Members
  - Current user role/permissions
- Admin/PM/TL editable timeline schedule:
  - drag task bars horizontally to update `startDate` + `dueDate`
  - status popup updates task status
- Employee/developer/QA view-only timeline.
- Employee web logout support in `EmployeeMobileShell`.

## Modified

- `lib/core/constants/app_enums.dart`
- `lib/core/permissions/permission_service.dart`
- `lib/app/app_shell.dart`
- `lib/app/workspace_state.dart`
- `lib/data/models/task.dart`
- `lib/employee_app/employee_mobile_shell.dart`

## Data fields

Tasks now support optional `startDate` while remaining compatible with existing data.
If `startDate` is missing, the screen falls back to `createdAt`, project `startDate`, or `dueDate - 2 days`.

## Permission behavior

Editable roles:

- Super Admin
- Company Admin
- Project Manager
- Team Lead

View-only roles:

- Developer
- QA Tester
- Designer
- DevOps
- Employee

`clientViewer` is hidden from the Timeline section.
