# V293 — Timeline Standard Navigation Performance

## Scope
Web/admin dashboard only. Android and iOS APK navigation and mobile SDUI configuration are unchanged.

## Changes
- Timeline now uses the same in-flow left/right/top/bottom navigation layout as every other web screen.
- Timeline now uses the same page fade/slide transition duration as every other screen.
- Removed the Timeline-only overlay navigation path at runtime.
- Removed the Timeline-only zero-duration page transition.
- The heavy Gantt board now holds its last settled width while the navigation rail animates.
- Intermediate sidebar width ticks are clipped instead of rebuilding every Timeline row, date cell, dependency line, and progress cell.
- After navigation motion settles, one final responsive Timeline layout is performed.
- Expensive Work Item and Assignee auto-fit text measurements are cached.
- The Timeline board is isolated with a RepaintBoundary.
- Existing search, filters, resizable columns, critical path, baseline, grouping, scrolling, and task actions are preserved.

## Files changed
- `lib/app/app_shell.dart`
- `lib/features/timeline/presentation/realtime_timeline_screen.dart`

## Verification
Run:

```bash
flutter clean
flutter pub get
flutter analyze
flutter run -d chrome
```

Test left and right side navigation in Expanded, Compact, and Icons-only modes. Also test Timeline auto-collapse and manual expand/collapse.
