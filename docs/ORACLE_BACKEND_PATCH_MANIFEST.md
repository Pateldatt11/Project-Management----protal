# Oracle Notification Backend Patch Manifest

## Added

- `notification_backend/` — Node.js/TypeScript Firebase Admin SDK backend
- `.github/workflows/deploy-notification-backend-oracle.yml`
- `lib/core/config/notification_backend_config.dart`
- `lib/admin_app/services/oracle_notification_backend_service.dart`
- `docs/ORACLE_ADMIN_SDK_NOTIFICATION_BACKEND.md`

## Updated

- `lib/admin_app/services/admin_fcm_sender_service.dart`
  - Queues direct, project, and team notifications for the Oracle backend.
  - No notification path depends on callable Cloud Functions.
- `lib/data/repositories/firebase_workspace_repository.dart`
  - Task assignment and meeting notification records now include durable Oracle queue fields.
- `lib/data/firebase/notification_service.dart`
  - Root and member mirror writes are separated so only the root is processed.
- `lib/features/notifications/presentation/notifications_screen.dart`
  - Delivery managers see escalated notifications and can request a secure resend.
- `functions/src/index.ts`
  - Skips `oracle_admin_sdk` jobs to prevent duplicate pushes if Functions are deployed later.
- `pubspec.yaml` and `pubspec.lock`
  - Adds the HTTP client used by the authenticated admin resend API.

## Validation

- Notification backend TypeScript type-check: passed
- Notification backend production build: passed
- `/health` endpoint smoke test: passed
- Startup without credentials in setup mode: passed; worker remains disabled
- Service-account credential included in project: no
- Firebase project ID: `project-management-dashb-aa77a`
