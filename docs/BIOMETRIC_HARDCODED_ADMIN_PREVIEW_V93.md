# v93 Hardcoded biometric app lock + Admin preview parity

This update makes the fingerprint / biometric app-lock option a Flutter-native hardcoded feature, not an SDUI widget.

## Where it is implemented

- `lib/core/security/biometric_auth_service.dart`
  - Owns local `local_auth` calls, availability checks, enable/disable state, and last-unlocked timestamps.
- `lib/core/security/biometric_settings_tile.dart`
  - Hardcoded Profile → Settings switch.
  - In APK mode it calls the OS biometric prompt.
  - In Admin Mobile UI Designer preview mode it shows a preview-only switch and never calls the OS prompt.
- `lib/core/security/biometric_unlock_gate.dart`
  - Hardcoded gate after Firebase login/bootstrap.
  - Wraps the signed-in `WorkspaceShellRouter`.
- `lib/features/auth/presentation/auth_gate.dart`
  - Wraps the authenticated app shell with `BiometricUnlockGate`.
- `lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart`
  - Injects `BiometricSettingsTile` directly into `_ProfileSettingsSection` for both APK and admin preview.

## Why it is not SDUI now

The biometric switch is not controlled by Firestore JSON and does not require a `biometricSettingsTile` node in `screenOverrides.profile.sections`.
The renderer always inserts it into the native Profile → Settings accordion when Profile is rendered.

## Admin preview behavior

Admin preview now shows the same fingerprint app-lock row in Profile → Settings.
Toggling it only changes local preview state and shows a preview snackbar. It does not open Android/iOS biometric prompts from the admin designer.

## APK behavior

In the APK, the switch uses `local_auth` after Firebase sign-in. If the user enables it, returning after the configured timeout requires OS biometric unlock.

## SDUI cleanup

The v270 config files were cleaned so the profile JSON no longer needs a `biometricSettingsTile` section. A `hardcodedBiometricAppLock` metadata block remains only as documentation for admin publishing.
