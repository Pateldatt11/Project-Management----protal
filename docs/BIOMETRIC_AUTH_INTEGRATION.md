# Fingerprint / Biometric App Lock v270

This patch adds a user-controlled fingerprint app lock from Profile → Settings.

## Behavior

- User must sign in with Firebase first.
- User opens Profile → Settings → Fingerprint app lock.
- When enabling, the app asks for OS biometric confirmation.
- After enabled, returning to the app after a short background period requires fingerprint/biometric unlock.
- This is local app-lock only. It does not replace Firebase Auth and it does not store fingerprint data.

## Dependency

Add the official Flutter plugin:

```yaml
dependencies:
  local_auth: ^3.0.1
```

Keep existing dependencies:

```yaml
dependencies:
  shared_preferences: any
```

Run:

```bash
flutter pub get
```

## Android setup

`local_auth` uses Android's system biometric prompt through the Android implementation package. Confirm your `MainActivity` uses `FlutterFragmentActivity` if your Android embedding requires it for local auth.

Typical file:

```kotlin
class MainActivity: FlutterFragmentActivity()
```

## iOS setup

Add Face ID usage text if iOS is supported:

```xml
<key>NSFaceIDUsageDescription</key>
<string>Use Face ID to unlock your project workspace.</string>
```

## Files to copy

```text
lib/core/security/biometric_auth_service.dart
lib/core/security/biometric_unlock_gate.dart
lib/core/security/biometric_settings_tile.dart
config/mobile_employee_v270_bootstrap_biometric_auth.json
```

## App shell integration

After `MobileBootstrapGate` decides the user is signed in and the app shell can render, wrap the app shell with `BiometricUnlockGate`:

```dart
return BiometricUnlockGate(
  uid: user.uid,
  companyId: companyId,
  lockAfterSeconds: 15,
  child: AppShell(
    initialUiConfig: initialUiConfig,
  ),
);
```

Do not show this gate on Login or Firebase initialization screens. Only wrap the signed-in app shell.

## Profile settings integration

Inside the existing Settings accordion/profile settings list, add:

```dart
BiometricSettingsTile(
  uid: user.uid,
  companyId: companyId,
)
```

## Security notes

- Do not store biometric templates.
- Do not use fingerprint as the first sign-in method.
- Do not delete the biometric setting on normal app close.
- Clear or disable it only when the user toggles it off, or when the account/company is removed from this device.
