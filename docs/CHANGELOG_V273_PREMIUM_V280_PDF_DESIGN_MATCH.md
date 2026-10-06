# V273 - Premium V280 PDF Design Match

## What changed

- Added `lib/features/reports/pdf/premium_v280_report_pdf_builder.dart`.
- The existing `DynamicReportPdfBuilder` now delegates report rendering to the premium eight-page builder.
- Kept the existing web browser print-preview flow unchanged.
- Added the supplied reference PDF under `docs/reports/` for future visual regression checks.

## Fixed eight-page structure

1. Monthly Company Report
2. Portfolio Delivery Health
3. Task Execution & Throughput
4. Timeline, Dependencies & Milestones
5. Team Capacity & Workload
6. Appraisal & Performance Intelligence
7. Risk, Quality & Notification Operations
8. Management Actions, Audit & Export

## Dynamic behavior

- Uses current project, task, member, timeline, appraisal and monthly snapshot data.
- Keeps at least eight pages.
- Appends continuation pages for additional projects, tasks and members.
- Uses the actual page count in headers and footers.
- Preserves Chrome/Edge/Firefox print preview and Save as PDF behavior.

## Main files

- `lib/features/reports/pdf/dynamic_report_pdf_builder.dart`
- `lib/features/reports/pdf/premium_v280_report_pdf_builder.dart`
- `docs/reports/management_dashboard_v280_premium_8_page_report_reference.pdf`
