# V294 — Timeline Settings + Original Project Plan Fix

## Scope

Web/admin realtime Timeline only. Android/iOS employee SDUI navigation was not modified.

## Fixed

- Enabled the Timeline settings gear button; it now opens a complete settings dialog instead of showing a placeholder snackbar.
- Added a Settings > Timeline settings card with a live preview.
- Added per-user web Timeline preferences persisted in browser storage.
- Added an Enable realtime Timeline switch that controls the web navigation item.
- Added default scale and grouping settings.
- Added switches for original project plan, automatic range fitting, task baselines, critical path, and today line.
- Fixed missing project original timeline by rendering `Project.startDate` through `Project.dueDate` as a striped plan bar.
- Preserved the solid realtime task roll-up bar, allowing planned-vs-live schedule drift comparison.
- Projects with no tasks now still appear in Project grouping when original plan display is enabled.
- Timeline range now auto-fits project/task dates so project plans outside the old fixed six-week window are visible.
- Added safe range limits to prevent malformed Firestore dates from creating an excessively large Gantt canvas.
- Expanded Project date parsing aliases for legacy Firestore documents.
- Corrected Navigation personalization action label from `Apply to web and APK` to `Apply to web`.

## Changed files

- `lib/app/app_shell.dart`
- `lib/core/timeline/timeline_preferences.dart` (new)
- `lib/data/models/project.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/features/timeline/presentation/realtime_timeline_screen.dart`

## Original vs realtime rendering

- Striped outlined bar: original project `startDate` → `dueDate`
- Solid project-colored bar: realtime roll-up from the earliest live task start to the latest live task due date
- Task baseline strip: task `baselineStartDate` → `baselineDueDate`

## Storage

Timeline preferences are stored per company/user in web browser storage under:

`web_timeline_preferences_v294::<companyId>::<userId>`
