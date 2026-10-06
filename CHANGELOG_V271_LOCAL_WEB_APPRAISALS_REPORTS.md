# V271 — Local Web Appraisals and Report Generation

## Fixed

- Removed the missing `processEmploymentAction` Cloud Function dependency from appraisal review, approval, and rejection.
- Fixed the duplicate `actionId` named argument in `CareerProgressionService.approve`.
- Added authenticated Oracle Admin SDK endpoints for appraisal processing and canonical monthly analytics rebuilds.
- Added a browser-safe local monthly analytics builder, so report generation works without Cloud Functions.
- Added the missing `pdf` and `printing` dependencies required by the dynamic PDF builder and preview screen.
- Made Firebase Storage upload optional instead of blocking local PDF generation.
- Added local browser download for appraisal CSV and generated report CSV.
- Added local Windows and Linux backend startup scripts.

## Local flow

```text
Flutter Web admin
  → save appraisal directly to Firestore
  → review/approve/reject through localhost:8080 or Oracle backend
  → Firebase Admin SDK transaction updates action + member + history + audit

Flutter Web reports
  → build monthly analytics from loaded workspace state
  → generate 8+ page PDF in the browser
  → preview/download PDF
  → download CSV
```

No Firebase Cloud Function deployment is required for these two workflows.
