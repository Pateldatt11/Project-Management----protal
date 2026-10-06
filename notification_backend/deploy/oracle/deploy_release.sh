#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/opt/projectos-notification"
RELEASE_ID="${1:-$(date -u +%Y%m%d%H%M%S)}"
SOURCE_DIR="${2:-$PWD}"
RELEASE_DIR="${APP_ROOT}/releases/${RELEASE_ID}"

mkdir -p "${RELEASE_DIR}"
rsync -a --delete \
  --exclude '.git' \
  --exclude 'build' \
  --exclude '.dart_tool' \
  --exclude 'node_modules' \
  "${SOURCE_DIR}/" "${RELEASE_DIR}/"

cd "${RELEASE_DIR}/notification_backend"
npm ci
npm run build
npm prune --omit=dev

ln -sfn "${RELEASE_DIR}" "${APP_ROOT}/current"
pm2 startOrReload "${APP_ROOT}/current/notification_backend/ecosystem.config.cjs" --update-env
pm2 save

for attempt in {1..12}; do
  if curl --fail --silent --show-error http://127.0.0.1:8080/health >/dev/null; then break; fi
  if [[ "$attempt" -eq 12 ]]; then echo "Health check failed" >&2; exit 1; fi
  sleep 2
done

# Keep five releases for rollback.
ls -1dt "${APP_ROOT}"/releases/* 2>/dev/null | tail -n +6 | xargs -r rm -rf

echo "Release ${RELEASE_ID} deployed successfully."
