# v233 Clean Dialog Build

- Replaced plain AlertDialog usage in the SDUI mobile renderer with clean app dialogs.
- Removed the separate GreenHaus/theme showcase panel concept from the implementation.
- Dialogs now use the existing app theme tokens only: surface, accent, border, text colors.
- Updated comment dialog, edit profile dialog, Crashlytics confirmation dialogs.
- Kept all v232 project stack carousel behavior and v231 phase-project direct task fix.
- No new decorative theme assets or branded side panels were added.

Changed file:
- lib/employee_app/server_driven/renderer/mobile_json_ui_renderer.dart
