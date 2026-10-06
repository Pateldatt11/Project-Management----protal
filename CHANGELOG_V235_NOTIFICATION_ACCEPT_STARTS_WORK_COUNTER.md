# v235 - Notification Accept Starts Work Counter

## What changed
- Native Android notification Accept now stores accepted task metadata when the FCM payload includes `taskId` and `type=taskAssigned`.
- Flutter sync now converts accepted notification IDs into `acceptNotificationAndStartWorkCounter(...)` instead of only marking them read.
- If the notification belongs to an assigned task, the assigned user's work counter starts automatically.
- If another task counter is already running for the same user, it is stopped/logged before the newly accepted task starts.
- Reject/Mark all read does not start work counters.
- The behavior works when the APK is foregrounded and also when the native Accept happens while Flutter is backgrounded; the timer starts when Flutter syncs the accepted native state.

## Changed files
- `lib/app/workspace_state.dart`
- `lib/core/platform/android_alert_notification_service.dart`
- `lib/features/notifications/presentation/notifications_screen.dart`
- `lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart`
- `android/app/src/main/kotlin/com/example/test/AppFirebaseMessagingService.kt`
- `android/app/src/main/kotlin/com/example/test/AlertActionReceiver.kt`
- `android/app/src/main/kotlin/com/example/test/LoopingAlertService.kt`
