# V236 - No Admin SDK Private Key Required

## Fix

Removed the remaining local-tool dependency/documentation that told the developer to generate a Firebase Admin SDK private key.

## Why

The Firebase project may block service account key creation through Google Cloud organization policy. For this app, the safer architecture is to use Cloud Functions default credentials in production and Application Default Credentials for local scripts.

## Updated

- `tools/publish_sdui_v89_firestore_config.js`
- `tools/publish_sdui_v90_clean_wireframe_config.js`
- `ADMIN_SDK_NO_PRIVATE_KEY_SETUP.md`

## Existing production functions

`functions/src/index.ts` already uses:

```ts
admin.initializeApp();
```

So the FCM/backend push implementation does not require `serviceAccountKey.json` when deployed to Firebase Cloud Functions.
