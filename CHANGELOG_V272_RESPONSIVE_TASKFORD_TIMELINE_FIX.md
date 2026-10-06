# V272 Responsive Taskford Timeline Fix

This patch fixes the web-only realtime Timeline/Gantt screen so it behaves reliably across desktop, laptop and smaller web widths.

## Fixed

- Rebuilt the Timeline toolbar from a single overflowing Row into a responsive Wrap.
- Made the search, project selector, view selector, group selector, filters, critical path, baseline, date navigation, export and settings controls wrap safely.
- Rebuilt the summary metrics into a responsive Row/Wrap layout.
- Removed Expanded from metric cards so they can be safely used in both Row and Wrap layouts.
- Made the Gantt table responsive:
  - adaptive left frozen table width
  - adaptive work item / assignee / progress column widths
  - adaptive day width
  - adaptive row height
  - no small-screen Row overflow
- Added working collapse/expand behavior for group rows.
- Kept the right timeline horizontally scrollable with synced header/body scrolling.
- Kept all existing realtime workspaceProvider data connections.
- Kept role protection:
  - Super Admin / Admin / Project Manager / Team Lead can drag/update schedule dates.
  - Employee / Developer / QA / Designer / DevOps remain view-only.

## Main file changed

```text
lib/features/timeline/presentation/realtime_timeline_screen.dart
```

## Build note

Run after extraction:

```bash
flutter pub get
flutter analyze
flutter build web
```
