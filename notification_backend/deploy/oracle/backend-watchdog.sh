#!/usr/bin/env bash
set -uo pipefail

APP_USER="${APP_USER:-projectos}"
APP_NAME="${APP_NAME:-projectos-notification-backend}"
APP_ROOT="${APP_ROOT:-/opt/projectos-notification}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:8080/health}"
READY_URL="${READY_URL:-http://127.0.0.1:8080/ready}"
PM2_SERVICE="${PM2_SERVICE:-pm2-projectos.service}"
PM2_BIN="${PM2_BIN:-}"
CURL_TIMEOUT_SECONDS="${CURL_TIMEOUT_SECONDS:-10}"
RECOVERY_WAIT_SECONDS="${RECOVERY_WAIT_SECONDS:-12}"
ECOSYSTEM_FILE="${APP_ROOT}/current/notification_backend/ecosystem.config.cjs"

if [[ -z "${PM2_BIN}" ]]; then
  for candidate in /usr/bin/pm2 /usr/local/bin/pm2; do
    if [[ -x "${candidate}" ]]; then
      PM2_BIN="${candidate}"
      break
    fi
  done
fi

log() {
  logger -t projectos-notification-watchdog -- "$*"
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"
}

# The timer may be enabled before the first release is deployed.
if [[ ! -f "${ECOSYSTEM_FILE}" ]]; then
  exit 0
fi

if curl --fail --silent --show-error --max-time "${CURL_TIMEOUT_SECONDS}" \
  "${HEALTH_URL}" >/dev/null; then
  exit 0
fi

log "Health check failed for ${APP_NAME}; starting automatic recovery."

# First recover the PM2 daemon and all saved processes through systemd.
if systemctl cat "${PM2_SERVICE}" >/dev/null 2>&1; then
  systemctl restart "${PM2_SERVICE}" || true
elif [[ -n "${PM2_BIN}" && -x "${PM2_BIN}" ]]; then
  # Fallback for a server where PM2 startup has not yet created its unit.
  runuser -u "${APP_USER}" -- env \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    HOME="/home/${APP_USER}" \
    "${PM2_BIN}" startOrReload "${ECOSYSTEM_FILE}" --update-env || true
  runuser -u "${APP_USER}" -- env \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    HOME="/home/${APP_USER}" \
    "${PM2_BIN}" save || true
else
  log "PM2 executable and ${PM2_SERVICE} were not found."
fi

sleep "${RECOVERY_WAIT_SECONDS}"

if curl --fail --silent --show-error --max-time "${CURL_TIMEOUT_SECONDS}" \
  "${HEALTH_URL}" >/dev/null; then
  log "Recovery succeeded; ${APP_NAME} is healthy again."
  exit 0
fi

# A second direct reload handles the case where the PM2 unit was alive but the
# application definition was missing or stale.
if [[ -n "${PM2_BIN}" && -x "${PM2_BIN}" ]]; then
  runuser -u "${APP_USER}" -- env \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    HOME="/home/${APP_USER}" \
    "${PM2_BIN}" startOrReload "${ECOSYSTEM_FILE}" --update-env || true
fi

sleep "${RECOVERY_WAIT_SECONDS}"

if curl --fail --silent --show-error --max-time "${CURL_TIMEOUT_SECONDS}" \
  "${HEALTH_URL}" >/dev/null; then
  log "Direct PM2 reload succeeded; ${APP_NAME} is healthy again."
  exit 0
fi

log "Automatic recovery failed. Health=${HEALTH_URL}, readiness=${READY_URL}."
exit 1
