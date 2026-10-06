# v234 - Work Counter + Employee Role Upgrade/Downgrade

## Employee APK / Mobile
- Activated task work time counter on assigned tasks.
- Added start/stop work counter on the Task Timeline selected-task detail card.
- Counter is visible only when the selected task is assigned to the signed-in user.
- Starting a counter moves Backlog/Todo tasks into In Progress automatically.
- Starting a new task counter automatically closes any other running counter for the same user.
- Stopping the counter adds elapsed time into `loggedHours`.
- Persisted task timer fields:
  - `activeWorkTimerUserId`
  - `activeWorkTimerStartedAt`
  - `loggedHours`
- Task effort UI now uses live logged hours while the counter is running.

## Admin Web
- Added employee role upgrade/downgrade action on the Employees screen.
- Admin/HR/Super Admin can change employee roles from the web panel.
- Super Admin role assignment is protected: only Super Admin can assign or change Super Admin.
- The current signed-in admin cannot downgrade their own role from the Employees screen.
- Role updates persist to:
  - `companies/{companyId}/members/{uid}`
  - `users/{uid}`
  - `companies/{companyId}/invites/{inviteId}` when available
- Added audit log and activity log entries for every role change.

## Firestore Rules
- Added admin user-doc role update permission through `canManagePeopleForUserDoc(uid)`.
