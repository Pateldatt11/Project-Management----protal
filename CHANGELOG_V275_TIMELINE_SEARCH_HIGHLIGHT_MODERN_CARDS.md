# V275 — Timeline Search Highlight + Modern Task Cards

## Added

- Added a dedicated search action button in the Timeline toolbar.
- Search now highlights matching task rows and matching Gantt bars instead of making the timeline lose context.
- Pressing Enter inside the search field also runs the highlight search.
- First matching task is auto-selected and opens the existing bottom task details panel.
- Added clear/search reset behavior through the existing filter clear action.

## Improved

- Modernized Gantt task bars:
  - rounded pill-style task cards
  - soft shadow
  - highlighted search border
  - SEARCH badge on matching bars
  - better visual distinction from baseline and dependency lines
- Matching left table rows now show a warm highlight and MATCH badge.
- Existing bottom details panel remains connected to task clicks.
- Existing permissions remain unchanged:
  - Super Admin / Admin / Project Manager / Team Lead can edit.
  - Employee / Developer / QA / Designer / DevOps are view-only.

## Main file updated

```text
lib/features/timeline/presentation/realtime_timeline_screen.dart
```
