# V289 direct use

1. Extract this ZIP over the current project.
2. Run:

```bash
flutter clean
flutter pub get
flutter analyze
flutter run -d chrome
```

3. Open Web Dashboard > Settings > Navigation personalization.
4. Choose placement, size, and animation in the live preview, then press Apply.

The feature is intentionally web-only. Building the Android APK uses the existing V287 mobile SDUI navigation without these desktop preferences.
