#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /absolute/path/firebase-admin.json [project-id]" >&2
  exit 2
fi

CREDENTIAL_PATH="$1"
PROJECT_ID="${2:-project-management-dashb-aa77a}"

if [[ ! -f "$CREDENTIAL_PATH" ]]; then
  echo "Firebase Admin SDK credential not found: $CREDENTIAL_PATH" >&2
  exit 2
fi

export NODE_ENV=development
export HOST=127.0.0.1
export PORT=8080
export FIREBASE_PROJECT_ID="$PROJECT_ID"
export GOOGLE_APPLICATION_CREDENTIALS="$CREDENTIAL_PATH"
export ANDROID_PACKAGE_NAME=com.example.test
export ADMIN_WEB_ORIGINS=""
export ALLOW_START_WITHOUT_FIREBASE=false

cd "$(dirname "$0")/../.."
npm install
npm run build
npm start
