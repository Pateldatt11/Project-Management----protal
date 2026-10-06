# Admin SDK private key not required

This project does not need `serviceAccountKey.json` for production push notifications.

## Production Cloud Functions

The Cloud Functions Admin SDK must use default Google credentials:

```ts
import * as admin from 'firebase-admin';
admin.initializeApp();
```

This is already how `functions/src/index.ts` is configured. Do not add `credential.cert(serviceAccount)` inside deployed functions.

Deploy backend push functions and rules:

```bash
firebase login
firebase use project-management-dashb-aa77a
firebase deploy --only functions,firestore:rules
```

## Local admin scripts without private key

For local scripts that publish SDUI JSON, use Application Default Credentials instead of a downloaded key:

```bash
gcloud auth application-default login
node tools/publish_sdui_v90_clean_wireframe_config.js --project project-management-dashb-aa77a --company YOUR_COMPANY_ID
```

## Why private key generation can be blocked

Newer Google Cloud organizations can block service account key creation with the `iam.disableServiceAccountKeyCreation` organization policy. That is a security protection. The correct fix for this project is to avoid long-lived private keys and use Cloud Functions default credentials / Application Default Credentials.

## Do not commit these files

Never put these in the app, web admin, APK, or project zip:

- `serviceAccountKey.json`
- any file containing `private_key`
- any `.json` downloaded from Google Cloud IAM service account key creation
