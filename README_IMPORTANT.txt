This package has been upgraded to an industrial-level starter.

Use demo mode first:
flutter clean
flutter pub get
flutter run -d chrome

Connect Firebase later:
flutterfire configure
flutter run -d chrome --dart-define=USE_FIREBASE=true

Important production files:
- lib/app/workspace_state.dart
- lib/data/repositories/workspace_repository.dart
- lib/data/repositories/firebase_workspace_repository.dart
- lib/core/config/app_config.dart
- firebase/firestore.rules
- firebase/storage.rules
- firebase/firestore.indexes.json
- functions/src/index.ts
- INDUSTRIAL_FIREBASE_CONNECTION_GUIDE.md


## Portal Post Control Update

IT Admin, Company Admin, and Super Admin can now open Settings > IT Admin Portal Post Control and activate only the posts needed in the company portal. Disabled posts are removed from demo login, employee invite role selection, task assignment, and permission checks. See `PORTAL_POST_CONTROL_GUIDE.md`.
