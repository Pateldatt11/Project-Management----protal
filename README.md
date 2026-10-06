# ProjectOS Dashboard - Industrial Flutter + Firebase Starter

A professional company-grade project management dashboard built with Flutter, Riverpod, Firebase-ready services, and multi-tenant Firestore architecture.

## Included screens

- Login
- Dashboard with live task-completion charts
- Projects
- Project details
- Tasks
- Drag/drop Kanban
- Teams
- Employees
- Reports
- Private notifications
- Settings
- Profile

## Industrial features now working in demo mode

- Create project
- Change project status
- Archive project
- Create task
- Assign task to a specific member
- Send private notification only to assigned member
- Change task status
- Drag/drop Kanban status changes
- Dashboard charts update from task status/completion
- Project progress recalculates from completed tasks
- Add task comments
- Add attachment metadata with Firebase Storage path
- Delete task
- Create team
- Invite employee/member
- Generate report metadata
- Activity log writes
- Audit log writes
- Role permission matrix
- Private notification unread count and mark-read flow

## Firebase-ready backend assets

- `firebase/firestore.rules`
- `firebase/storage.rules`
- `firebase/firestore.indexes.json`
- `functions/src/index.ts`
- `lib/data/firebase/*`
- `lib/data/repositories/workspace_repository.dart`
- `lib/data/repositories/firebase_workspace_repository.dart`
- `lib/core/config/app_config.dart`

## Demo run

```bash
flutter clean
flutter pub get
flutter run -d chrome
```

## Connect Firebase later

```bash
flutterfire configure
flutter pub get
flutter run -d chrome --dart-define=USE_FIREBASE=true

## Project AI assistant

The project assistant uses Groq's OpenAI-compatible endpoint. Supply the key at
build time; never commit it to Dart source or configuration files:

```powershell
flutter run -d chrome --dart-define=GROQ_API_KEY=your_valid_key
flutter build apk --release --dart-define=GROQ_API_KEY=your_valid_key
flutter build ios --release --dart-define=GROQ_API_KEY=your_valid_key
flutter build windows --release --dart-define=GROQ_API_KEY=your_valid_key
```

For local development, copy `dart_defines.example.json` to
`dart_defines.json`, fill in the values locally, and use Flutter's defines
file. The local file is ignored by Git:

```powershell
Copy-Item dart_defines.example.json dart_defines.json
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

The OneSignal REST key and Groq key are read by the service classes through
`String.fromEnvironment` at build time. Do not put real values in the example
file. For production web or client builds, prefer a backend proxy because
build-time values can be extracted from the application binary.

`PROJECT_AI_API_KEY` is also supported and is preferred for new builds:

```powershell
flutter run -d chrome --dart-define=PROJECT_AI_API_KEY=your_valid_key
```

For production, use a backend proxy so the secret is not shipped inside web,
APK, iOS, or desktop binaries. If the key is absent or invalid, the assistant
shows a project-aware fallback instead of provider error JSON.
```

The current UI uses demo state for fast testing. The repository layer is included so you can move the controller from demo data to Firestore streams without rewriting the screens.

## Firebase deploy

```bash
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
firebase deploy --only storage
cd functions
npm install
npm run build
firebase deploy --only functions
```

## Private notification guarantee

Every notification has a `recipientId`. The UI filters by current user, and Firestore rules enforce:

```text
allow read: if resource.data.recipientId == request.auth.uid;
```

The Cloud Function sends FCM only to `/users/{recipientId}/fcmTokens`, not to all users.

## Role-based demo logins added

The login screen now lets you open the dashboard as different real company roles:

- Super Admin
- Company Admin
- IT Admin
- Project Manager
- Team Lead
- Developer
- QA / Tester
- Designer
- DevOps Engineer
- HR / People Manager
- Client / Viewer

Each role has a different menu scope, task visibility, notification inbox, project/report access, and settings/audit permission. This follows the same production pattern you will later enforce with Firebase Auth custom claims plus `/companies/{companyId}/members/{uid}` documents.

## Industrial RBAC rule

Do not trust only the Flutter UI. Flutter hides disabled screens and actions, but Firebase rules also enforce the same roles:

```text
Company membership document -> role -> Firestore/Storage rule -> allow/deny
```

When Firebase is connected, update each member document with one of these role values:

```text
superAdmin, admin, itAdmin, projectManager, teamLead, developer, qaTester, designer, devOps, hrManager, employee, clientViewer
```

Cloud Functions includes `syncRoleClaimsOnMemberWrite`, which can sync the member role into Firebase Auth custom claims for faster top-level access checks.

## Latest update: employee online/offline presence

The project now includes employee presence controls:

- Dashboard private status card
- Profile online/offline and available/busy switches
- Employee directory online/offline badges and counts
- Firestore member fields: `isOnline`, `lastSeenAt`, `available`
- Security rules allow users to update only safe self profile/presence fields

See `EMPLOYEE_PRESENCE_ONLINE_OFFLINE_UPDATE.md` for the exact architecture.

## Demo Data / Firestore Only Toggle

Admin settings now include **Admin Data Source Control**. Use this to disable demo data so the app shows only Firestore-streamed projects, tasks, teams, employees, notifications, reports, activity logs, and audit logs.

Firestore path:

```text
companies/{companyId}/settings/demoData
```

Set:

```json
{ "demoDataEnabled": false }
```

You can also control it from the app UI using Super Admin, Company Admin, or IT Admin.

## Automatic first admin bootstrap

The first Firebase account can now be created directly from the app login/register screen. The app automatically creates the first company, Company Admin member document, user document, membership shortcut, bootstrap lock document, portal post settings, and disables demo data by default. After the first admin is created, later users must be invited by Admin/HR from the Employees screen.

See `AUTOMATIC_FIRST_ADMIN_BOOTSTRAP.md`.


## Super Admin first setup

Create only one manual Firestore doc for the Platform Super Admin at `users/{AUTH_UID}` with `role: superAdmin`. Then sign in and open **Settings → Super Admin Company Setup**. The app will create company/member/settings docs automatically from the form data. See `SUPER_ADMIN_COMPANY_SETUP_FLOW.md`.

## Server-driven mobile UI SQLite cache

The employee mobile UI now uses a cache-first strategy. The app reads `companies/company_001/uiConfigs/mobileEmployee` from local SQLite first, renders immediately, then listens to Firestore for changes. If Firestore config is unchanged, the employee UI is not rebuilt.

Added files:

```text
lib/data/cache/mobile_ui_config_cache.dart
lib/data/cache/mobile_ui_config_cache_sqflite.dart
lib/data/cache/mobile_ui_config_cache_stub.dart
SERVER_DRIVEN_UI_SQLITE_CACHE_UPDATE.md
```

Added dependencies:

```yaml
sqflite: ^2.4.2
path: ^1.9.1
```

## Server-driven Mobile UI Designer + Preview

Admin now gets a no-code mobile UI designer:

```text
Settings -> Mobile UI Control -> Open Mobile UI Designer
```

It generates JSON automatically, renders a live phone preview, supports Save Draft and Publish, and updates the employee app through Firestore + SQLite cache without an APK rebuild for supported layout/style changes.

Documents used:

```text
companies/{companyId}/uiConfigs/mobileEmployeeDesignDraft
companies/{companyId}/uiConfigs/mobileEmployeeDesign
companies/{companyId}/uiConfigs/mobileEmployee
```

## Server-driven UI import + emulator preview

The admin Mobile UI Designer now supports importing JSON UI designs and previewing them in a real-use phone emulator before publishing.

Open:

```text
Settings → Mobile UI Control → Open Mobile UI Designer
```

New actions:

```text
Import JSON      Paste mobileEmployeeDesign JSON or mobileEmployee config JSON.
Device preview   Test Pixel 8, Compact Android, and iPhone preview sizes.
Tab preview      Preview Home, Tasks, Projects, Board, Inbox, and Profile.
Save Draft       Store preview-only JSON.
Publish Design   Increment version and sync employee mobile app via Firestore + SQLite cache.
```

## Server-driven UI emulator overflow fix

The Mobile UI Designer preview now uses a scroll-safe phone body and supports more real-use device presets: Compact Android, Moto G / Budget, Galaxy S24, Pixel 8, Pixel 8 Pro, S24 Ultra, iPhone SE, iPhone 15, iPhone 15 Pro Max, Pixel Fold, iPad Mini, and Android Tablet.

Updated file: `lib/features/settings/presentation/mobile_ui_designer_screen.dart`.

## Server-driven UI import modes

The Mobile UI Designer now supports import modes:

- **Use imported JSON for screen UI only**: applies imported screen/card/theme data but keeps current navbar/bottom navigation.
- **Apply imported JSON to all mobile UI**: applies full imported design including navigation.
- **Apply cosmetic changes only**: applies color/spacing/radius/card variant changes only while preserving structure and fields.

Open: `Settings -> Mobile UI Control -> Open Mobile UI Designer -> Start from template / import -> Use imported JSON file`.


## Server-driven UI screen import/raw render fix

Mobile UI Designer now supports Import JSON UI → choose mode → choose screen → Import to UI. Screen-only import keeps navbar/bottom tabs unchanged and renders the selected preview screen directly from the pasted JSON instead of forcing it through default no-code cards.


## Split admin web and employee mobile surfaces

Use the dedicated entrypoints for clean production builds:

```powershell
# Admin web dashboard
flutter run -d chrome -t lib/main_admin.dart
flutter build web -t lib/main_admin.dart

# Employee mobile app
flutter run -d android -t lib/main_employee.dart
flutter build apk --release -t lib/main_employee.dart
```

Server-driven JSON UI is runtime-enabled only in the employee mobile surface. Admin web can design, import, preview, and publish mobile JSON, but admin dashboard screens are fixed Flutter UI.

## APK UI Support Check + Mobile Renderer Update

The Mobile UI Designer now includes an **Employee APK support checker**. It verifies whether the no-code/imported JSON is supported by the employee APK renderer before publishing.

Published `mobileEmployeeDesign` is now consumed by the employee mobile app runtime, while admin web remains a fixed Flutter dashboard.

See `APK_UI_SUPPORT_CHECK_AND_MOBILE_RENDERER_UPDATE.md`.


## Deep sync + mobile renderer fix

Latest update: `DEEP_SYNC_AND_MOBILE_RENDERER_FIX.md` explains the fixed sync flow. Admin preview and employee APK now use the same server-driven renderer. `mobileEmployeeDesign` is cached in SQLite and mirrored to the lightweight runtime config so the APK matches the admin emulator after publish.

## Mobile UI Designer production parity update

See `MOBILE_UI_DESIGNER_PRODUCTION_PARITY_UPDATE.md` for the server-driven mobile UI editor changes. The admin emulator uses the same renderer as the employee APK in preview mode, and the APK persists supported task/profile actions.

## V94 — Import JSON Release/Test Publish Toggle

Mobile UI Designer now separates Release/Test JSON import and publish targets:

- Release → `companies/{companyId}/uiConfigs/mobileEmployee`
- Test → `companies/{companyId}/uiConfigs/mobileEmployeeNext`

Imported JSON dialog includes a target selector. The Draft/Publish panel also uses the selected target, so test JSON and release JSON stay separated.

See `ADMIN_IMPORT_JSON_RELEASE_TEST_PUBLISH_TOGGLE_V94.md`.

## V95 Admin Preview Real Parity

Mobile UI Designer preview now supports Release/Test real runtime preview:

- Release preview merges `mobileEmployee` + `mobileEmployeeDesign` + optional `mobileEmployeeScreens`.
- Test preview merges `mobileEmployeeNext` + `mobileEmployeeNextDesign` + optional `mobileEmployeeNextScreens`.
- The preview shell draws top/bottom nav from the merged Firestore JSON instead of using the old no-code preview shell.
- `workSummary` is now mapped as a supported summary/hero block.

Use `firebase/sdui_v62/mobileEmployeeNextDesign_v90_UI_LAYER_PUSH_THIS.json` for the Test UI layer document.
