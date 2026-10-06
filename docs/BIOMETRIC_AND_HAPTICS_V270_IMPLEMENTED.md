# Biometric + Haptics v270 Implementation

This repo version includes the biometric app-lock patch directly, not only as a reference patch.

## Biometric app lock

User path: **Profile -> Settings -> Fingerprint app lock**.

The toggle uses `local_auth` and stores only the enabled flag in `SharedPreferences` using a per-user/per-company key.
The OS handles fingerprint/face enrollment and prompt UI.

## Carousel haptics

Task Board phase carousel haptics are intentionally minimal. The renderer calls `HapticFeedback.selectionClick()` only when `PageView.onPageChanged` moves to a new phase.

JSON flags:

```json
{
  "taskBoardCarouselHapticsEnabled": true,
  "minimalCarouselHaptics": true,
  "carouselHapticMode": "selectionClickOnPageSnap",
  "carouselDragHaptics": "none"
}
```

## Build note

Run:

```bash
flutter pub get
flutter analyze
flutter build apk --release --build-name=1.4.270 --build-number=270
```

## v93 correction

The biometric app-lock row is now hardcoded in Flutter instead of being inserted as an SDUI widget. Admin Mobile UI Designer preview now shows the same Profile → Settings fingerprint row with preview-only toggle behavior.
