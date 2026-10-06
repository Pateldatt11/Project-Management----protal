# PMD Mobile SDUI Compact Changelog v149-v184

## v184 - Admin Preview Task Timeline + Drawer Back
- Code-only update; no Firestore UI JSON files changed.
- Admin Mobile UI Designer now provides a real Task Timeline preview route even when the currently published JSON does not define `taskTimeline`.
- APK and Admin preview side menus now include Task Timeline after Tasks when it is not explicitly listed by JSON.
- Hamburger/menu leading control behaves as a close/back control while the new side menu is open.
- Drawer open cut-panel preview now shows the same back/close leading icon behavior as APK.
- Keeps old published JSON compatible; Task Timeline renderer falls back to the reference-style timeline if live task data is empty.

## Notes
- Build locally with `flutter analyze` and `flutter build apk --release`.
- Flutter tooling was not available in the generation container, so static Flutter analysis was not run here.
