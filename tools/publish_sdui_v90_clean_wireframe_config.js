#!/usr/bin/env node
/*
  Publish Project Management Dashboard SDUI v90 clean wireframe config to Firestore.

  Usage:
    gcloud auth application-default login
    node tools/publish_sdui_v90_clean_wireframe_config.js --project project-management-dashb-aa77a --company YOUR_COMPANY_ID

  No serviceAccountKey.json/private key is required.

  Optional:
    --file firebase/sdui_v62/companies_uiConfigs_mobileEmployee_v90_clean_wireframe.json
    --draft-only
    --active-only
*/
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

function arg(name, fallback = undefined) {
  const prefix = `--${name}=`;
  const inline = process.argv.find((v) => v.startsWith(prefix));
  if (inline) return inline.slice(prefix.length);
  const i = process.argv.indexOf(`--${name}`);
  if (i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith('--')) {
    return process.argv[i + 1];
  }
  return fallback;
}

function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

function readJson(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  return JSON.parse(raw);
}

function validateConfig(config) {
  const requiredTopLevel = [
    'enabled',
    'version',
    'designSystem',
    'topNav',
    'bottomNav',
    'navigationConfig',
    'layoutConfig',
    'screenOverrides',
    'screenRegistry',
    'navigationGraph',
    'rendererCompatibility',
  ];

  for (const key of requiredTopLevel) {
    if (!(key in config)) {
      throw new Error(`Missing required SDUI key: ${key}`);
    }
  }

  if (!Array.isArray(config.bottomTabs) || config.bottomTabs.length === 0) {
    throw new Error('bottomTabs must be a non-empty array.');
  }

  if (!config.bottomNav || !Array.isArray(config.bottomNav.tabs)) {
    throw new Error('bottomNav.tabs must be a non-empty array.');
  }

  const overrides = config.screenOverrides || {};
  for (const route of config.bottomNav.tabs) {
    if (!overrides[route]) {
      throw new Error(`screenOverrides.${route} is required for bottom nav route.`);
    }
  }

  if (config.designSystem.brandLock === 'estate') {
    throw new Error('Invalid brand lock: estate. Config must stay project-management-only.');
  }

  return true;
}

async function main() {
  const companyId = arg('company') || arg('companyId');
  const projectId = arg('project') || process.env.FIREBASE_PROJECT_ID || process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'project-management-dashb-aa77a';
  if (!companyId) {
    throw new Error('Missing company id. Use --company YOUR_COMPANY_ID');
  }

  const defaultFile = path.resolve(
    process.cwd(),
    'firebase/sdui_v62/companies_uiConfigs_mobileEmployee_v90_clean_wireframe.json'
  );
  const filePath = path.resolve(arg('file', defaultFile));
  const activeOnly = hasFlag('active-only');
  const draftOnly = hasFlag('draft-only');

  if (activeOnly && draftOnly) {
    throw new Error('Use either --active-only or --draft-only, not both.');
  }

  const config = readJson(filePath);
  validateConfig(config);

  if (!admin.apps.length) {
    admin.initializeApp({ projectId });
  }

  const db = admin.firestore();
  const companyRef = db.collection('companies').doc(companyId);
  const now = admin.firestore.FieldValue.serverTimestamp();

  const version = Number(config.version || 0);
  const batch = db.batch();

  const activeRef = companyRef.collection('uiConfigs').doc('mobileEmployee');
  const draftRef = companyRef.collection('uiConfigs').doc('mobileEmployeeDesignDraft');
  const versionRef = companyRef.collection('uiConfigVersions').doc(`mobileEmployee_v${version}`);
  const metaRef = companyRef.collection('uiConfigMeta').doc('mobileEmployee');

  const payload = {
    ...config,
    companyId,
    publishedAt: now,
    publishSource: 'tools/publish_sdui_v90_clean_wireframe_config.js',
  };

  if (!draftOnly) {
    batch.set(activeRef, payload);
  }

  if (!activeOnly) {
    batch.set(draftRef, payload);
  }

  batch.set(versionRef, {
    version,
    configId: config.configId || `mobileEmployee_v${version}`,
    templateName: config.templateName || 'projectManagementCleanWireframeUi',
    createdAt: now,
    createdBy: 'local_publish_script',
    sourceFile: filePath,
    config: payload,
  });

  batch.set(metaRef, {
    activeVersion: draftOnly ? admin.firestore.FieldValue.delete() : version,
    latestDraftVersion: activeOnly ? admin.firestore.FieldValue.delete() : version,
    templateName: config.templateName || 'projectManagementCleanWireframeUi',
    updatedAt: now,
    updatedBy: 'local_publish_script',
    sourceFile: filePath,
    jsonOnlyFutureUiChanges: true,
  }, { merge: true });

  await batch.commit();

  console.log('✅ SDUI v90 clean wireframe config published.');
  console.log(`Project: ${projectId}`);
  console.log(`Company: ${companyId}`);
  console.log(`File: ${filePath}`);
  console.log(`Active: ${!draftOnly}`);
  console.log(`Draft: ${!activeOnly}`);
  console.log(`Version backup: uiConfigVersions/mobileEmployee_v${version}`);
}

main().catch((error) => {
  console.error('❌ Publish failed:', error.message || error);
  console.error('No private key is required. For local publishing run: gcloud auth application-default login');
  process.exit(1);
});
