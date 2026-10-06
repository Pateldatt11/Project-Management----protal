# V281 Deployment

## 1. Flutter dependencies and web build

```bash
flutter clean
flutter pub get
flutter analyze
flutter build web --release
```

## 2. Cloud Functions validation

```bash
cd functions
npm install
npm run build
cd ..
```

## 3. Deploy backend changes

```bash
firebase login
firebase use project-management-dashb-aa77a
firebase deploy --only functions,firestore:rules,storage
```

To deploy only the new V281 functions:

```bash
firebase deploy --only \
functions:processEmploymentAction,\
functions:applyScheduledEmploymentActions,\
functions:rebuildMonthlyAnalytics,\
functions:refreshCurrentMonthlyAnalytics,\
functions:finalizePreviousMonthlyAnalytics
```

Then deploy rules:

```bash
firebase deploy --only firestore:rules,storage
```

## 4. Deploy web

```bash
firebase deploy --only hosting
```

## 5. Production checks

1. Open Timeline as Admin and as Employee; verify edit/view-only behavior.
2. Search a task inside a collapsed group; verify auto-expand, date focus, highlight and detail panel.
3. Create a dependency and confirm a circular dependency is rejected.
4. Save a Civil Engineering appraisal as Team Lead or Project Manager.
5. Create a future-dated promotion recommendation, review it as HR and approve it as Admin.
6. Confirm the action remains `scheduled` until the effective date and then becomes `approved`.
7. Rebuild the current monthly snapshot and verify the reporting cutoff and metrics.
8. Generate All Projects and single-project PDFs and verify eight-page minimum plus dynamic overflow.
