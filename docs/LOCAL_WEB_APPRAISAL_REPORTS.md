# Local Web Appraisal and Report Functions

This build removes the paid Cloud Function dependency from appraisal processing and report generation.

## What now works locally

- Save appraisal score, template, competency values, self review, manager review, peer review and review period.
- Create promotion, demotion, role, department, grade and salary-band recommendations in Firestore.
- Review, approve and reject career actions through the local/Oracle Admin SDK backend.
- Rebuild monthly analytics directly in Flutter Web from the currently loaded workspace data.
- Generate an eight-page-or-more PDF locally and download it from the PDF preview.
- Download the appraisal table as CSV in the browser.
- Optionally persist a canonical monthly analytics snapshot through the Oracle backend API.

## Local development startup

### 1. Start the backend

Do not copy the service-account JSON into the repository. Keep it in a private folder, for example:

`C:\secure\project-management-adminsdk.json`

From PowerShell:

```powershell
cd notification_backend
deploy\local\run_local_backend.ps1 `
  -CredentialPath "C:\secure\project-management-adminsdk.json"
```

The API starts at `http://127.0.0.1:8080`.

### 2. Start Flutter Web

From another terminal at project root:

```powershell
flutter clean
flutter pub get
flutter run -d chrome -t lib/main_admin.dart
```

Debug builds automatically use `http://127.0.0.1:8080` for appraisal review/approval/rejection when no production backend URL is supplied.

## Production web build

```powershell
flutter build web -t lib/main_admin.dart `
  --dart-define=NOTIFICATION_BACKEND_BASE_URL=https://api.your-domain.com
```

Optional Firebase Storage PDF upload:

```powershell
flutter build web -t lib/main_admin.dart `
  --dart-define=NOTIFICATION_BACKEND_BASE_URL=https://api.your-domain.com `
  --dart-define=UPLOAD_REPORTS_TO_FIREBASE_STORAGE=true
```

Storage upload is disabled by default. Local PDF generation and download do not require it.

## Backend endpoints

- `POST /api/v1/appraisals/{actionId}/process`
- `POST /api/v1/reports/monthly/rebuild`
- `GET /health`
- `GET /ready`

Every protected endpoint verifies the Firebase ID token and the employee role before using Firebase Admin SDK.
