#!/usr/bin/env bash
set -euo pipefail
# The Firebase service-account key is intentionally excluded from backups.
BACKUP_DIR="/opt/projectos-notification/backups"
mkdir -p "${BACKUP_DIR}"
tar -czf "${BACKUP_DIR}/projectos-config-$(date -u +%Y%m%d%H%M%S).tar.gz" \
  /opt/projectos-notification/shared/backend.env \
  /etc/nginx/sites-available/projectos-notification 2>/dev/null || true
find "${BACKUP_DIR}" -type f -mtime +14 -delete
