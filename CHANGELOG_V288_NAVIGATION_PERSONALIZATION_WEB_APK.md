# V289 Web-only Windows-style navigation personalization

## Added
- Personal web navigation placement: Automatic, Left, Right, Top, Bottom.
- Display modes: Expanded, Compact, Icons only.
- Motion modes: System, Smooth, Fast, Off.
- Windows 11 Insider-style interactive miniature preview in Settings.
- Optional Timeline auto-collapse, hover expansion, and state restoration.
- Smooth width/position transitions with isolated repaint boundaries.

## Web-only enforcement
- Preferences are loaded and saved only when `kIsWeb` is true.
- Preferences are stored per company + signed-in user in browser SharedPreferences.
- The employee Android/iOS shell was restored to the V287 SDUI implementation.
- No navigation preference is written into mobile SDUI JSON or Firestore mobile UI config.
- APK top navigation, bottom navigation, rail behavior, and responsive SDUI shell remain unchanged.
