# v270 Biometric Auth + Minimal Carousel Haptics

## Added

- Fingerprint / biometric app lock for signed-in employee APK users.
- Profile -> Settings tile: **Fingerprint app lock**.
- Biometric unlock gate wraps the app shell after Firebase login.
- Android biometric permissions and FragmentActivity host support.
- iOS Face ID usage description.
- Minimal Task Board carousel haptics: one `selectionClick` only when the carousel snaps to a new phase.

## Behavior

- Firebase Auth remains the real login mechanism.
- Fingerprint app lock is optional and disabled by default.
- The app never stores fingerprint or face data.
- Returning from background after the lock interval asks for biometric unlock when enabled.
- Carousel drag does not vibrate continuously; haptic feedback happens only on page snap / selection.

## Files touched

- `pubspec.yaml`
- `android/app/src/main/kotlin/com/example/test/MainActivity.kt`
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`
- `lib/features/auth/presentation/auth_gate.dart`
- `lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart`
- `lib/core/security/biometric_auth_service.dart`
- `lib/core/security/biometric_unlock_gate.dart`
- `lib/core/security/biometric_settings_tile.dart`
- `mobileEmployee_cleanWireframe_v270_biometric_haptics_FULL.json`
- `biometric_carousel_haptics_patch_v270.json`
