#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
let admin;
try {
  admin = require('firebase-admin');
} catch (_) {
  admin = require('../functions/node_modules/firebase-admin');
}

const companyId = process.argv[2];
if (!companyId) {
  console.error('Usage: node tools/publish_sdui_v88_wireframe.js <companyId>');
  process.exit(1);
}

const configPath = path.resolve(__dirname, '..', 'firebase', 'sdui_v62', 'companies_uiConfigs_mobileEmployee_v88_wireframe.json');
const raw = fs.readFileSync(configPath, 'utf8');
const config = JSON.parse(raw);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
}

async function main() {
  const db = admin.firestore();
  const activeRef = db.doc(`companies/${companyId}/uiConfigs/mobileEmployee`);
  const draftRef = db.doc(`companies/${companyId}/uiConfigs/mobileEmployeeDesignDraft`);
  const versionRef = activeRef.collection('versions').doc('v88');

  const payload = {
    ...config,
    enabled: true,
    version: 88,
    updatedBy: 'tools/publish_sdui_v88_wireframe.js',
    updatedAt: new Date().toISOString(),
  };

  await db.runTransaction(async (tx) => {
    const current = await tx.get(activeRef);
    if (current.exists) {
      const data = current.data() || {};
      const previousVersion = data.version || 'unknown';
      tx.set(activeRef.collection('versions').doc(`before_v88_${Date.now()}`), {
        ...data,
        backupReason: 'before_v88_wireframe_publish',
        backupCreatedAt: new Date().toISOString(),
        previousVersion,
      }, { merge: true });
    }

    tx.set(activeRef, payload, { merge: true });
    tx.set(draftRef, payload, { merge: true });
    tx.set(versionRef, {
      ...payload,
      savedAsRollbackVersion: true,
    }, { merge: true });
  });

  console.log(`Published v88 wireframe SDUI to company ${companyId}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
