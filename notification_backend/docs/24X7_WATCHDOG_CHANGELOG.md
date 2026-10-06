# v88 Oracle 24×7 Watchdog Changes

## Updated

- `src/http_api.ts`: richer liveness diagnostics and readiness state.
- `src/server.ts`: safe health-only setup mode before Firebase credentials are installed.
- `src/firebase.ts`: explicit credential availability detection for setup mode.
- `ecosystem.config.cjs`: crash-loop backoff, restart delay, uptime and memory limits.
- `deploy/oracle/bootstrap_ubuntu.sh`: installs and enables the systemd watchdog timer.
- `README.md`: Oracle watchdog setup and verification.

## Added

- `deploy/oracle/backend-watchdog.sh`
- `deploy/oracle/projectos-notification-watchdog.service`
- `deploy/oracle/projectos-notification-watchdog.timer`
- `deploy/oracle/install_watchdog.sh`
- `deploy/oracle/uninstall_watchdog.sh`
- `docs/ORACLE_24X7_WATCHDOG.md`

## Runtime behavior

- `/health` is checked every minute.
- PM2 is restarted when the local API is not responding.
- A direct `pm2 startOrReload` is attempted if systemd recovery is insufficient.
- PM2 restores the process after VM reboot.
- Firestore-backed retry records survive process and VM restarts.
