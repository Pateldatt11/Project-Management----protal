# V281 — Cutting-Edge Timeline, Appraisal, Career Actions and Monthly Analytics

## Timeline V2

- Added Day, Week, Month and Quarter timeline scales.
- Added grouping by Project, Assignee, Status and Department.
- Added modern visual task bars with status/priority/risk colors, progress fill, milestone diamonds and baseline overlays.
- Added dependency connectors with critical-chain highlighting.
- Added timeline intelligence cards for dependencies, milestones, baseline coverage, risk and schedule health.
- Search now preserves timeline context, highlights the result, expands its collapsed group, changes the focus date and scrolls to the matching row/bar.
- Added a responsive bottom task intelligence panel.
- Added task intelligence editing for dependencies, progress, risk, milestone state and baseline controls.
- Added circular-dependency prevention.
- Prevented off-range tasks, baselines and connectors from being incorrectly drawn at timeline edges.
- Kept role-based editing: Super Admin, Admin, Project Manager and Team Lead can edit; other employees remain view-only.

## Appraisal V2

- Rebuilt the appraisal workspace with employee search, role filter, performance summary, competency scoring, career actions and action history.
- Added evidence-based recommendations using monthly task delivery and weighted competency scores.
- Added manager review, self-review, peer/360 feedback, notes, status, period and previous-score comparison.
- Added industry competency templates for General Operations, Civil Engineering, Software, QA, Mechanical, Electrical, HR, Sales and Finance.
- Civil Engineering includes site supervision, drawing interpretation, BOQ/estimation, quality inspection, safety, contractor coordination, materials, schedule control and documentation.

## Promotion, Demotion and Career Workflow

- Added employment actions for promotion, demotion, role change, department transfer, grade change, salary-band change, probation extension, PIP, contract renewal and exit recommendation.
- Team Lead / Project Manager / HR / Admin can recommend according to role permissions.
- HR Manager / Admin / Super Admin can review, approve or reject.
- Approval is performed by a secured callable Cloud Function, not a direct client update.
- Future effective dates are stored as scheduled actions and applied automatically every 30 minutes.
- Effective actions update the employee, create immutable employment history, create an audit log and notify the employee.
- Protected roles cannot be assigned through the appraisal workflow.

## Monthly Analytics and PDF Accuracy

- Added hourly current-month analytics refresh in `asia-south1`.
- Added previous-month finalization at 00:05 on the first day of each month using `Asia/Kolkata`.
- Finalized snapshots are immutable unless an authorized admin performs a force rebuild.
- Large breakdowns are stored in versioned subcollections with a generation ID; the root snapshot is published last so clients do not read partial data.
- Historical task status, completion and overdue values are calculated against the reporting cutoff rather than blindly using the current task status.
- The reporting screen shows the selected month, snapshot cutoff, finalized/live state, project scope and snapshot generation.
- PDF output uses the selected monthly snapshot, supports All Projects or one project, generates at least eight pages and grows dynamically for large datasets.
- Generated PDFs are uploaded to Firebase Storage with report metadata.

## Security and Reliability

- Added safe Firestore appraisal-field updates for authorized appraisal editors without allowing role/department privilege escalation.
- Employment action review/approval updates are server-only.
- Monthly analytics documents and detail collections are server-only writes.
- Fixed Firestore transaction ordering for immediate employment-action approval.
- Scheduled actions preserve their original approval metadata when they become effective.
- Added malformed-record tolerance so one old record does not blank the appraisal screen.

## Main files

- `lib/features/timeline/presentation/realtime_timeline_screen.dart`
- `lib/features/appraisals/presentation/appraisal_screen.dart`
- `lib/features/appraisals/data/appraisal_template_catalog.dart`
- `lib/features/appraisals/data/career_progression_service.dart`
- `lib/data/models/employment_action.dart`
- `lib/data/models/monthly_analytics_snapshot.dart`
- `lib/features/reports/data/monthly_analytics_service.dart`
- `lib/features/reports/presentation/reports_screen.dart`
- `lib/features/reports/pdf/dynamic_report_pdf_builder.dart`
- `lib/app/workspace_state.dart`
- `functions/src/index.ts`
- `firebase/firestore.rules`
