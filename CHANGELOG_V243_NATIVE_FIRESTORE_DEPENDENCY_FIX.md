# V243 Native Firestore Dependency Fix

Fixes Android release build failure from `LoopingAlertService.kt` after terminated-state push acknowledgement was added in v242.

## Fixed

- Added native Android Firebase Firestore dependency to `android/app/build.gradle.kts`.
- Keeps v242 terminated-state push fallback logic.
- Keeps old v131 admin/web task assign screen restored in v241.
- No UI files changed.
- No Firestore rules changed.

## Why

`LoopingAlertService.kt` writes native render acknowledgement to Firestore using `FirebaseFirestore`, `FieldValue`, and `SetOptions`. Flutter plugin dependencies are not always visible to app module Kotlin source compilation, so the app module must declare the native Firestore Android SDK dependency directly.
