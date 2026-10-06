#!/usr/bin/env bash
set -euo pipefail

APP_USER="projectos"
APP_ROOT="/opt/projectos-notification"
LOG_ROOT="/var/log/projectos-notification"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash bootstrap_ubuntu.sh" >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl gnupg git nginx ufw rsync

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi
npm install -g pm2

if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  useradd --system --create-home --shell /bin/bash "${APP_USER}"
fi

mkdir -p "${APP_ROOT}/releases" "${APP_ROOT}/shared" "${APP_ROOT}/secrets" "${APP_ROOT}/scripts" "${LOG_ROOT}"
touch "${LOG_ROOT}/output.log" "${LOG_ROOT}/error.log"
chown -R "${APP_USER}:${APP_USER}" "${APP_ROOT}" "${LOG_ROOT}"
chmod 750 "${APP_ROOT}/secrets"

ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

systemctl enable nginx
systemctl restart nginx

env PATH="$PATH" pm2 startup systemd -u "${APP_USER}" --hp "/home/${APP_USER}"

# Install the independent systemd watchdog. It safely exits until the first
# release exists, then checks /health every minute and recovers PM2 if needed.
install -m 0750 -o root -g root \
  "${SCRIPT_DIR}/backend-watchdog.sh" \
  "${APP_ROOT}/scripts/backend-watchdog.sh"
install -m 0644 -o root -g root \
  "${SCRIPT_DIR}/projectos-notification-watchdog.service" \
  "/etc/systemd/system/projectos-notification-watchdog.service"
install -m 0644 -o root -g root \
  "${SCRIPT_DIR}/projectos-notification-watchdog.timer" \
  "/etc/systemd/system/projectos-notification-watchdog.timer"
systemctl daemon-reload
systemctl enable --now projectos-notification-watchdog.timer

echo
printf '%s\n' \
  "Bootstrap completed." \
  "1. Upload firebase-admin.json to ${APP_ROOT}/secrets/firebase-admin.json" \
  "2. Create ${APP_ROOT}/shared/backend.env from .env.example" \
  "3. Deploy the repository into ${APP_ROOT}/current" \
  "4. Run PM2 as ${APP_USER}." \
  "5. Watchdog timer is installed and checks the backend every minute."
