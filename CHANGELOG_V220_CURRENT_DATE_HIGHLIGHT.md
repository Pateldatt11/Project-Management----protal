# v220 — Current Date Highlight Timeline

## Task Timeline
- Removed the visible `Today` text stamp from the Gantt date header.
- Added an automatic circular current-date highlight in the date header.
- The highlighted date is calculated from `DateTime.now()` so it follows the device/current date whenever the screen rebuilds.
- Kept the vertical current-date guide line, but the header now uses the cleaner date-chip style.
- Updated regular Gantt bars to avoid harsh black appearance: bars now use the app green/red timeline palette and slightly thicker rounded capsules.
- Selected row behavior remains unchanged: the selected task still becomes the large thick capsule and reveals details below.

## Files changed
- `lib/features/tasks/presentation/task_timeline_screen.dart`
