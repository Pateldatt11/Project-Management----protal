# V287 Appraisal and Career Action Fix

## Fixed

- Removed repeated employee identity labels such as `QA Tester • QA Tester • QA Tester`.
- Uses the role department as a safe display fallback when a stored department duplicates the job title or role label.
- Replaced `-` placeholders for Grade, Level, and Salary band with `Not configured`.
- Added appraisal status and review-period context next to the employee score.
- Added a clear career-profile setup warning when Grade or Employment Level is missing.
- Promotion and demotion actions remain disabled until Grade and Employment Level are configured.
- Transfer and role-change actions remain available when only Grade/Level are missing.
- Disabled all new career actions while another Draft, Recommended, Under Review, or Scheduled action exists.
- Added backend duplicate-workflow protection before creating an employment action.
- Career actions are blocked for inactive employees.
- Workflow loading/error state is verified before action buttons become active.
- Improved empty workflow copy and responsive career metrics.
- Trimmed empty employee department/job-title values before applying role fallbacks.

## Files changed

- `lib/features/appraisals/presentation/appraisal_screen.dart`
- `lib/features/appraisals/data/career_progression_service.dart`
- `lib/data/models/member.dart`

## Preserved from previous fixes

- Deep Timeline 1-pixel RenderFlex overflow fix.
- Automatic Timeline sidebar collapse behavior.
