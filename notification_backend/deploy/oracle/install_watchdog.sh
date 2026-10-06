#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="/opt/projectos-notification"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo: sudo bash install_watchdog.sh" >&2
  exit 1
fi

install -d -m 0750 -o root -g root "${APP_ROOT}/scripts"
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

echo "ProjectOS watchdog installed and enabled."
systemctl list-timers projectos-notification-watchdog.timer --no-pager || true
