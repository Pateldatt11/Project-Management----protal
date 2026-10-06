# Oracle VM Admin SDK Notification Backend

## 1. Final architecture

```text
Admin assigns task or creates meeting invite
        ↓
Flutter writes company root + member mirror notification documents
        ↓
Root document has activeQueue=true and nextAttemptAt=now
        ↓
Always-running Oracle backend receives the Firestore real-time change
        ↓
Backend verifies queue lease and loads employee FCM token(s)
        ↓
Firebase Admin SDK sends high-priority data-only FCM
        ↓
Android native FirebaseMessagingService renders the notification
        ↓
Employee accepts / declines / mutes / reads
        ↓
Firestore response state stops future retries
        ↓
If still pending, retry after 5 minutes, maximum 3 sends
        ↓
After the final response window, create notificationLogs escalation
        ↓
Admin Notifications screen displays the escalation and Resend action
```

## 2. Files added

```text
notification_backend/package.json
notification_backend/package-lock.json
notification_backend/tsconfig.json
notification_backend/src/config.ts
notification_backend/src/firebase.ts
notification_backend/src/auth.ts
notification_backend/src/tokens.ts
notification_backend/src/notification_sender.ts
notification_backend/src/worker.ts
notification_backend/src/http_api.ts
notification_backend/src/server.ts
notification_backend/ecosystem.config.cjs
notification_backend/deploy/oracle/*
.github/workflows/deploy-notification-backend-oracle.yml
lib/core/config/notification_backend_config.dart
lib/admin_app/services/oracle_notification_backend_service.dart
```

## 3. Existing app files connected

```text
lib/admin_app/services/admin_fcm_sender_service.dart
lib/data/repositories/firebase_workspace_repository.dart
lib/data/firebase/notification_service.dart
lib/features/notifications/presentation/notifications_screen.dart
functions/src/index.ts
pubspec.yaml
```

The Cloud Function source now skips documents whose `deliveryProvider` is `oracle_admin_sdk`, preventing duplicate pushes if Cloud Functions are deployed later.

## 4. Firestore queue fields

The root company notification document contains:

```text
queueScope: company_root
activeQueue: true
deliveryProvider: oracle_admin_sdk
pushStatus: queued_oracle_backend
deliveryStatus: queued
responseStatus: pending
attemptCount: 0
maxAttempts: 3
retryIntervalMinutes: 5
nextAttemptAt: Firestore timestamp
adminAttentionRequired: false
```

The member mirror keeps the notification visible in the APK but uses:

```text
queueScope: member_mirror
activeQueue: false
```

Only the root record is processed by the Oracle worker.

## 5. Admin SDK key added later

Download the private service-account JSON from the correct Firebase project only when the Oracle VM is ready.

Do not rename or edit its contents. Upload it to:

```text
/opt/projectos-notification/secrets/firebase-admin.json
```

Set secure ownership:

```bash
sudo chown projectos:projectos /opt/projectos-notification/secrets/firebase-admin.json
sudo chmod 600 /opt/projectos-notification/secrets/firebase-admin.json
```

The environment file must contain:

```text
FIREBASE_PROJECT_ID=project-management-dashb-aa77a
GOOGLE_APPLICATION_CREDENTIALS=/opt/projectos-notification/secrets/firebase-admin.json
ANDROID_PACKAGE_NAME=com.example.test
```

If the Android application ID changes, update `ANDROID_PACKAGE_NAME` to exactly match it.

## 6. Oracle VM bootstrap

Create an Ubuntu VM, reserve a public IP, and allow TCP ports 22, 80, and 443 in both the Oracle VCN security rules and the VM firewall.

Copy the repository to the VM, then run:

```bash
cd notification_backend/deploy/oracle
sudo bash bootstrap_ubuntu.sh
```

Create the production environment file:

```bash
sudo cp backend.env.template /opt/projectos-notification/shared/backend.env
sudo chown projectos:projectos /opt/projectos-notification/shared/backend.env
sudo chmod 600 /opt/projectos-notification/shared/backend.env
sudo nano /opt/projectos-notification/shared/backend.env
```

Deploy the first release:

```bash
sudo -u projectos ./deploy_release.sh first-release /path/to/project-root
```

Verify:

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/ready
sudo -u projectos pm2 status
sudo -u projectos pm2 logs projectos-notification-backend
```

## 7. HTTPS

1. Point the backend DNS name to the Oracle public IP.
2. Copy `nginx-projectos-notification-http.conf` to `/etc/nginx/sites-available/projectos-notification`.
3. Replace the example domain.
4. Enable it and reload Nginx.
5. Install Certbot and obtain the certificate.
6. Replace the HTTP config with `nginx-projectos-notification-tls.conf` and reload Nginx.

Example enable commands:

```bash
sudo ln -sfn /etc/nginx/sites-available/projectos-notification /etc/nginx/sites-enabled/projectos-notification
sudo nginx -t
sudo systemctl reload nginx
```

## 8. GitHub automatic deployment

Configure these GitHub Actions repository secrets:

```text
ORACLE_HOST
ORACLE_USER
ORACLE_SSH_KEY
BACKEND_HEALTH_URL
```

The workflow builds and type-checks the backend, uploads a release, switches the `current` symlink, reloads PM2, and checks the public health URL.

Never add the Firebase service-account JSON to GitHub secrets as a file inside the repository. Keep it only on the Oracle VM.

## 9. Admin web URL

Build the admin web panel after the public HTTPS endpoint is available:

```bash
flutter build web -t lib/main_admin.dart \
  --dart-define=NOTIFICATION_BACKEND_BASE_URL=https://YOUR-BACKEND-DOMAIN
```

Without this define, automatic Firestore-to-FCM delivery still works, but the Admin Panel Resend button remains disabled.

## 10. Test sequence

1. Install a newly built APK and log in as an employee.
2. Confirm the employee FCM token exists in Firestore.
3. Start the Oracle backend and confirm `/ready` returns HTTP 200.
4. Assign a task from the admin panel.
5. Confirm the root notification changes from `queued_oracle_backend` to `sent_waiting_response`.
6. Confirm the APK receives the notification in foreground, background, normally terminated, and locked states.
7. Leave it unanswered and verify attempts at approximately 0, 5, and 10 minutes.
8. Wait the final response window and verify an escalation appears in `notificationLogs` and the Admin Notifications screen.
9. Tap Resend and verify a fresh three-attempt cycle starts.
10. Accept from the APK and confirm no later retry occurs.

## 11. Validation completed in the generated package

```text
TypeScript type-check: passed
TypeScript production build: passed
Health endpoint smoke test: passed
Missing-credential setup mode: passed with worker safely disabled
Service-account private key included: no
```
