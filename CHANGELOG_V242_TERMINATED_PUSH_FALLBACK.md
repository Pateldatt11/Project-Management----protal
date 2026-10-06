# V242 - Terminated-state push notification fallback

Scope: fix Android task assignment notifications that do not appear when the APK is closed/terminated.

Changes:
- Kept the v241 restored old admin/web task assign screen unchanged.
- Kept v236 no-private-key Cloud Functions/Admin SDK flow.
- Kept v235 Accept notification action starts task work counter.
- Added native Android render acknowledgement fields on notification docs:
  - nativeReceivedAt
  - nativeRenderStatus
  - nativeRenderUpdatedAt
  - nativeRenderSource
- Added delayed backend system-tray fallback from Cloud Functions:
  - sends data-only native push first for custom Accept/Reject notification.
  - waits 10 seconds.
  - if Android has not confirmed native rendering, sends normal FCM notification payload for lock-screen visibility.
- Added a fresh Android notification channel:
  - urgent_work_alerts_v242_lock_screen
- Added delayed Android notification permission prompt after employee login/token registration.
- Preserved old-data-visible Firestore rules from v238.

Test flow:
1. Deploy functions and rules.
2. Install APK fresh or clear notification channel settings.
3. Login as employee once and allow notification permission.
4. Kill/close app normally, do not force-stop from Settings.
5. Assign task from admin.
6. Expected: custom native notification appears within 3-10 seconds. If native render is blocked, fallback system notification appears after about 10-20 seconds.

Important:
- Force-stopped apps can still block background FCM delivery until opened again.
- Android notification permission and lock-screen notification setting must be enabled.
