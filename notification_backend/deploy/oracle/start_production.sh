#!/usr/bin/env bash
set -euo pipefail
ENV_FILE="/opt/projectos-notification/shared/backend.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a
cd /opt/projectos-notification/current/notification_backend
exec node dist/server.js
