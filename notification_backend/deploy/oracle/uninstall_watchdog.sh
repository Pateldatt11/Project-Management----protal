#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo: sudo bash uninstall_watchdog.sh" >&2
  exit 1
fi

systemctl disable --now projectos-notification-watchdog.timer 2>/dev/null || true
rm -f /etc/systemd/system/projectos-notification-watchdog.timer
rm -f /etc/systemd/system/projectos-notification-watchdog.service
rm -f /opt/projectos-notification/scripts/backend-watchdog.sh
systemctl daemon-reload
systemctl reset-failed projectos-notification-watchdog.service 2>/dev/null || true

echo "ProjectOS watchdog removed."
