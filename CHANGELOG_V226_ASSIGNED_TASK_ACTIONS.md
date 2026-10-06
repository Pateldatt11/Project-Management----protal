# v226 — Assigned Task Actions

- Task Timeline selected-task action bar now appears only when the selected task is assigned to the current user.
- Comment action opens a comment dialog and saves through `WorkspaceNotifier.addTaskComment`.
- Attach action opens the device picker and saves through `WorkspaceNotifier.addAttachmentFromDevicePicker`.
- Update action opens a status selector and saves through `WorkspaceNotifier.updateTaskStatus`.
- More action continues opening the task insight sheet.
- Non-assigned tasks remain visible for timeline context, but the action bar is hidden.

Changed file:
- `lib/features/tasks/presentation/task_timeline_screen.dart`
