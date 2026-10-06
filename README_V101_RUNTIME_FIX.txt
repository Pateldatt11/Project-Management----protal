V101 SDUI RUNTIME ENGINE FIX

Use this build when the UI renders but buttons/search/filters behave like a mockup.

Main fixed files:
- lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart
- lib/employee_app/employee_mobile_shell.dart
- lib/data/repositories/firebase_workspace_repository.dart

Build command:
flutter build apk --release --build-name=1.5.01 --build-number=101 --dart-define=SDUI_CONFIG_DOC=mobileEmployeeNext

Note: Old APKs cannot support these new JSON actions. Install v101 test APK.
