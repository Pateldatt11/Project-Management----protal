# V218 Responsive Gantt Timeline

## Fixed / Improved

- Reworked the Task Timeline Gantt map for compact smartphones.
- Gantt map now keeps a fixed 5-row visible area on mobile.
- When the 6th task row is present, the row area becomes vertically scrollable inside the Gantt map card.
- Selected Gantt row now becomes a thick green capsule so the selected task is obvious.
- Tapping a Gantt row reveals the task detail card directly below the map.
- The revealed detail card updates automatically when another Gantt row is selected.
- Added a `View full timeline` action that opens a full timeline sheet.
- Full timeline sheet uses a larger scrollable Gantt map for long task lists.
- Added compact layout handling for narrow phones: reduced left lane width, row height, date labels, and text sizes.
- Kept the same light green visual language and existing real-data-only rule.

## Notes

- No fake task rows were added.
- Task rows, counts, dates, statuses, and progress still come from WorkspaceState task data.
- Flutter SDK is not installed in this sandbox, so analyze/build was not executed here.
