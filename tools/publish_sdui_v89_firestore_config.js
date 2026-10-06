#!/usr/bin/env node
/**
 * Publish Project Management Dashboard mobile SDUI v89 JSON to Firestore.
 *
 * Usage:
 *   node tools/publish_sdui_v89_firestore_config.js --company COMPANY_ID --file firebase/sdui_v62/companies_uiConfigs_mobileEmployee_v89_firestore_active.json
 *   node tools/publish_sdui_v89_firestore_config.js --company COMPANY_ID --file firebase/sdui_v62/companies_uiConfigs_mobileEmployee_v89_firestore_active.json --watch
 *
 * Requires:
 *   npm install firebase-admin
 *
 * No serviceAccountKey.json is required. For local publishing, login with:
 *   gcloud auth application-default login
 *
 * Then run:
 *   node tools/publish_sdui_v89_firestore_config.js --project project-management-dashb-aa77a --company COMPANY_ID --file firebase/sdui_v62/companies_uiConfigs_mobileEmployee_v89_firestore_active.json
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

function arg(name, fallback = null) {
  const idx = process.argv.indexOf(`--${name}`);
  if (idx === -1 || idx + 1 >= process.argv.length) return fallback;
  return process.argv[idx + 1];
}

const companyId = arg('company');
const filePath = arg('file');
const projectId = arg('project') || process.env.FIREBASE_PROJECT_ID || process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'project-management-dashb-aa77a';
const watch = process.argv.includes('--watch');

if (!companyId || !filePath) {
  console.error('Missing required args: --company COMPANY_ID --file FILE_PATH');
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

const db = admin.firestore();

function validateConfig(config) {
  const missing = [];
  for (const key of [
    'version',
    'bottomNav',
    'topNav',
    'floatingBottomNav',
    'layoutConfig',
    'designSystem',
    'screenOverrides',
    'screenRegistry',
    'navigationGraph',
    'rendererCompatibility',
  ]) {
    if (config[key] === undefined || config[key] === null) missing.push(key);
  }

  if (missing.length) {
    throw new Error(`Invalid SDUI config. Missing keys: ${missing.join(', ')}`);
  }

  if (!Array.isArray(config.bottomNav.tabs) || config.bottomNav.tabs.length === 0) {
    throw new Error('Invalid SDUI config. bottomNav.tabs must be a non-empty array.');
  }

  if (config.rendererCompatibility.futureUiChangeMode !== 'jsonOnlyFirestoreConfig') {
    console.warn('Warning: rendererCompatibility.futureUiChangeMode is not jsonOnlyFirestoreConfig.');
  }
}

async function publishOnce() {
  const absolute = path.resolve(process.cwd(), filePath);
  const raw = fs.readFileSync(absolute, 'utf8');
  const config = JSON.parse(raw);

  validateConfig(config);

  const activeRef = db.doc(`companies/${companyId}/uiConfigs/mobileEmployee`);
  const draftRef = db.doc(`companies/${companyId}/uiConfigs/mobileEmployeeDesignDraft`);
  const metaRef = db.doc(`companies/${companyId}/uiConfigMeta/mobileEmployee`);
  const versionId = `mobileEmployee_v${config.version || Date.now()}`;
  const versionRef = db.doc(`companies/${companyId}/uiConfigVersions/${versionId}`);

  const payload = {
    ...config,
    updatedAt: new Date().toISOString(),
    publishedAt: admin.firestore.FieldValue.serverTimestamp(),
    publishedByTool: 'publish_sdui_v89_firestore_config',
  };

  await db.runTransaction(async (tx) => {
    tx.set(activeRef, payload);
    tx.set(draftRef, payload);
    tx.set(versionRef, {
      config: payload,
      version: config.version || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdByTool: 'publish_sdui_v89_firestore_config',
    });
    tx.set(metaRef, {
      activeVersion: config.version || null,
      activeVersionDoc: versionId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      sourceFile: filePath,
      publishMode: watch ? 'watch' : 'manual',
    }, { merge: true });
  });

  console.log(`[SDUI] Published v${config.version} to companies/${companyId}/uiConfigs/mobileEmployee`);
}

let timer = null;
function schedulePublish() {
  clearTimeout(timer);
  timer = setTimeout(() => {
    publishOnce().catch((error) => {
      console.error('[SDUI] Publish failed:', error.message || error);
    });
  }, 350);
}

publishOnce().catch((error) => {
  console.error('[SDUI] Initial publish failed:', error.message || error);
  console.error('[SDUI] No private key is required. For local publishing run: gcloud auth application-default login');
  process.exitCode = 1;
});

if (watch) {
  console.log(`[SDUI] Watching ${filePath}`);
  fs.watch(path.resolve(process.cwd(), filePath), { persistent: true }, schedulePublish);
}
