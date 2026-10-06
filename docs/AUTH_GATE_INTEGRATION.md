# Mobile Bootstrap Integration

This patch adds a production startup flow for the employee APK:

- Fresh signed-in user or missing/corrupted UI cache: show the Firebase initialization screen once.
- Returning signed-in user with usable UI cache: open app immediately from local SDUI cache.
- Firestore UI updates download silently in the background and replace cache only after validation.
- Logout should not delete `mobile_sdui_cache_*` keys.

## Files to copy

Copy these into your project:

```text
lib/app/mobile_bootstrap/firebase_initialization_screen.dart
lib/app/mobile_bootstrap/mobile_bootstrap_controller.dart
lib/app/mobile_bootstrap/mobile_bootstrap_gate.dart
lib/app/mobile_bootstrap/mobile_ui_cache_service.dart
lib/data/firebase/mobile_sdui_remote_config_repository.dart
config/mobile_employee_v269_bootstrap_background_cache.json
```

## pubspec dependencies

This patch uses dependencies that are usually already present in this project:

```yaml
dependencies:
  firebase_auth: any
  cloud_firestore: any
  shared_preferences: any
```

Run:

```bash
flutter pub get
```

## AuthGate usage pattern

Use `MobileBootstrapGate` after Firebase auth resolves the signed-in user. Keep your existing Login screen and AppShell.

```dart
import 'package:firebase_auth/firebase_auth.dart';
import '../../../app/mobile_bootstrap/mobile_bootstrap_gate.dart';
import '../../../data/firebase/mobile_sdui_remote_config_repository.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;

        return MobileBootstrapGate(
          user: user,
          loginBuilder: (_) => const LoginScreen(),
          companyIdResolver: (user) async {
            // Replace this with your existing company resolver.
            // Use users/{uid}.defaultCompanyId -> memberships fallback.
            final companyId = await resolveCompanyIdForUser(user.uid);
            return companyId;
          },
          remoteUiFetcher: (companyId) {
            return MobileSduiRemoteConfigRepository().fetchMobileEmployeeConfig(companyId);
          },
          workspacePreloader: (user, companyId) async {
            // Optional. Keep this lightweight.
            // Load profile/company membership/permissions only if your app requires them before first render.
          },
          appBuilder: (context, initialUiConfig) {
            return EmployeeMobileShell(
              initialUiConfig: initialUiConfig,
              backgroundRefreshEnabled: true,
            );
          },
        );
      },
    );
  }
}
```

## Important logout rule

Do not clear the SDUI cache on logout. Clear only session/runtime state.

Keep:

```text
mobile_sdui_cache_companyId
mobile_sdui_version_companyId
mobile_sdui_updated_at_companyId
```

Clear:

```text
auth/session state
runtime search/filter state
presence state
temporary bootstrap errors
```

## Firestore publish rule

When admin publishes new mobile UI JSON:

1. Increment `version`.
2. Write the new config to `companies/{companyId}/uiConfigs/mobileEmployee`.
3. Do not clear old local cache from the app.
4. The APK will render old cache first, fetch the new config in background, validate it, and then switch.

## Why this fixes startup

This prevents:

- blank screen after login
- app stuck before Home
- Firebase loading screen on every app open
- UI config fetch blocking returning users
- broken/half-written Firestore UI replacing a working cached UI

## v270 biometric wrapper

After the signed-in app shell is ready, wrap it with `BiometricUnlockGate`:

```dart
return BiometricUnlockGate(
  uid: user.uid,
  companyId: companyId,
  lockAfterSeconds: 15,
  child: AppShell(initialUiConfig: initialUiConfig),
);
```

This wrapper must run after Firebase login/bootstrap, not on the login screen and not on the one-time Firebase initialization screen.
