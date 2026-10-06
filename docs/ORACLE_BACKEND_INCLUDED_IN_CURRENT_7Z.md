# Oracle Notification Backend Included

This project includes the Oracle-hosted Firebase Admin SDK notification backend and 24x7 recovery package.

## Backend location

`notification_backend/`

## Firebase Admin credential location on Oracle

`/opt/projectos-notification/secrets/firebase-admin.json`

Do not place the credential JSON in this repository, Flutter app, web build, or archive.

## Oracle environment file

`/opt/projectos-notification/shared/backend.env`

## Main deployment commands

```bash
sudo bash notification_backend/deploy/oracle/bootstrap_ubuntu.sh
```

For an existing installation:

```bash
cd /opt/projectos-notification/current/notification_backend
sudo bash deploy/oracle/install_watchdog.sh
```

## Verification

```bash
curl -fsS http://127.0.0.1:8080/health
curl -fsS http://127.0.0.1:8080/ready
systemctl status projectos-notification-watchdog.timer --no-pager
```
