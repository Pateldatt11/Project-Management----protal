# Oracle 24×7 Backend Watchdog

This package keeps the ProjectOS notification backend recoverable while the Oracle VM is running.

## Protection layers

1. **PM2 autorestart** restarts Node.js after crashes or excessive memory usage.
2. **PM2 systemd startup** restores the process after an Oracle VM reboot.
3. **systemd watchdog timer** calls `http://127.0.0.1:8080/health` every minute.
4. If the health request fails, the watchdog restarts the PM2 service and then performs a direct PM2 reload as a fallback.
5. Notification retry state remains in Firestore, so a restart does not lose pending attempts.

This improves service resilience but cannot prevent Oracle from stopping or reclaiming the VM itself.

## Files

```text
notification_backend/ecosystem.config.cjs
notification_backend/deploy/oracle/backend-watchdog.sh
notification_backend/deploy/oracle/projectos-notification-watchdog.service
notification_backend/deploy/oracle/projectos-notification-watchdog.timer
notification_backend/deploy/oracle/install_watchdog.sh
notification_backend/deploy/oracle/uninstall_watchdog.sh
```

## Automatic installation during bootstrap

Run from the uploaded backend source:

```bash
sudo bash notification_backend/deploy/oracle/bootstrap_ubuntu.sh
```

The bootstrap script installs and enables the timer. Before the first application deployment, the watchdog exits without error.

## Manual installation

```bash
cd /opt/projectos-notification/current/notification_backend
sudo bash deploy/oracle/install_watchdog.sh
```

## Verify

```bash
systemctl status projectos-notification-watchdog.timer --no-pager
systemctl list-timers projectos-notification-watchdog.timer --no-pager
curl -fsS http://127.0.0.1:8080/health
curl -fsS http://127.0.0.1:8080/ready
```

Run one immediate watchdog check:

```bash
sudo systemctl start projectos-notification-watchdog.service
sudo journalctl -u projectos-notification-watchdog.service -n 100 --no-pager
```

## Recovery test

```bash
sudo -u projectos pm2 stop projectos-notification-backend
sudo systemctl start projectos-notification-watchdog.service
sleep 15
curl -fsS http://127.0.0.1:8080/health
```

The backend should be running again.

## External availability monitor

Configure any external uptime monitor to request the public HTTPS endpoint every five minutes:

```text
https://YOUR-BACKEND-DOMAIN/health
```

Use `/health` for liveness. Use `/ready` only for diagnostics because it also verifies Firestore connectivity.
