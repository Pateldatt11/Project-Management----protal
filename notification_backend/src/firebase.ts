import { existsSync } from "node:fs";
import { applicationDefault, getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { config } from "./config";

const explicitCredentialPath = (process.env.GOOGLE_APPLICATION_CREDENTIALS ?? "").trim();

// In normal production mode, ADC may come from the explicit service-account
// file or from the hosting environment. Setup mode intentionally avoids an ADC
// lookup when no credential file is configured, so /health can still run.
export const firebaseCredentialsConfigured =
  !config.allowStartWithoutFirebase ||
  (explicitCredentialPath.length > 0 && existsSync(explicitCredentialPath));

const app = getApps()[0] ?? initializeApp({
  credential: applicationDefault(),
  projectId: config.firebaseProjectId,
});

export const adminAuth = getAuth(app);
export const adminDb = getFirestore(app);
export const adminMessaging = getMessaging(app);
