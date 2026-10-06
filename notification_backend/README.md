# ProjectOS Oracle Notification Backend

This folder contains the always-running Node.js/TypeScript backend used by the management dashboard to turn Firestore notification jobs into Firebase Cloud Messaging pushes without Firebase Cloud Functions.

## What it does

- Uses the Firebase Admin SDK only on the trusted Oracle VM.
- Watches each company notification collection in real time.
- Sends high-priority data-only FCM payloads to Android devices.
- Reads tokens from both global and company-scoped token paths.
- Deletes invalid FCM tokens.
- Retries unanswered task/meeting alerts after 5 minutes.
- Sends a maximum of 3 push attempts.
- Waits one final 5-minute response window after attempt 3.
- Writes an escalation record to `companies/{companyId}/notificationLogs/{notificationId}`.
- Supports secure admin-initiated resend through the backend API.
- Uses Firestore leases so duplicate backend instances do not send the same job simultaneously.

## Firebase credentials

No private key is included in this repository.

Later, place the downloaded service-account JSON on the Oracle VM at:

```text
/opt/projectos-notification/secrets/firebase-admin.json
```

Then set:

```text
GOOGLE_APPLICATION_CREDENTIALS=/opt/projectos-notification/secrets/firebase-admin.json
```

Never add the service-account file to Flutter, Android, Web, GitHub, or this zip.

## Local build

```bash
cd notification_backend
npm install
npm run typecheck
npm run build
```

For a setup-only health test before credentials are available:

```bash
ALLOW_START_WITHOUT_FIREBASE=true npm start
```

The worker stays disabled until valid Firebase credentials are supplied.

## Production endpoints

```text
GET  /health
GET  /ready
POST /api/v1/notifications/{notificationId}/resend
POST /api/v1/notifications/{notificationId}/respond
```

The resend and response endpoints require a Firebase ID token in the Authorization header.

## Admin web build

After the Oracle backend has a public HTTPS URL, build the admin web app with:

```bash
flutter build web -t lib/main_admin.dart \
  --dart-define=NOTIFICATION_BACKEND_BASE_URL=https://api.notifications.example.com
```

The Admin Notifications screen then shows escalated alerts and enables the **Resend** button.

## 24×7 recovery and watchdog

The Oracle deployment includes three independent recovery layers:

```text
PM2 autorestart
+ PM2 systemd startup after reboot
+ one-minute systemd health watchdog
```

The watchdog files are in:

```text
deploy/oracle/backend-watchdog.sh
deploy/oracle/projectos-notification-watchdog.service
deploy/oracle/projectos-notification-watchdog.timer
deploy/oracle/install_watchdog.sh
```

The normal Oracle bootstrap installs the watchdog automatically. For an existing VM, install it manually:

```bash
cd /opt/projectos-notification/current/notification_backend
sudo bash deploy/oracle/install_watchdog.sh
```

Detailed validation and recovery-test commands are documented in:

```text
docs/ORACLE_24X7_WATCHDOG.md
```

## Appraisal and report APIs (V271)

The same always-on backend now also replaces the paid callable-function paths used by the local Flutter Web admin build.

- `POST /api/v1/appraisals/{actionId}/process`
  - body: `companyId`, `command` (`review`, `approve`, `reject`), `comments`
  - roles: Super Admin, Admin, HR Manager
  - applies approved member changes transactionally and writes employment history, activity, and audit documents

- `POST /api/v1/reports/monthly/rebuild`
  - body: `companyId`, `monthId`, optional `projectId`
  - roles: Super Admin, Admin, Project Manager, HR Manager
  - generates a canonical monthly analytics document with project, task, employee, and appraisal breakdowns

The Flutter Web report screen also has a client-side analytics fallback, so PDF and CSV generation continues even when the backend or canonical snapshot is unavailable.
