module.exports = {
  apps: [
    {
      name: "projectos-notification-backend",
      script: "/opt/projectos-notification/current/notification_backend/deploy/oracle/start_production.sh",
      interpreter: "/bin/bash",
      cwd: "/opt/projectos-notification/current/notification_backend",

      instances: 1,
      exec_mode: "fork",
      autorestart: true,
      watch: false,

      // Crash-loop and resource protection.
      restart_delay: 3000,
      exp_backoff_restart_delay: 100,
      min_uptime: "10s",
      max_restarts: 30,
      max_memory_restart: "450M",

      // Allow active HTTP requests and Firestore work to finish.
      kill_timeout: 20000,
      listen_timeout: 10000,
      wait_ready: false,

      time: true,
      error_file: "/var/log/projectos-notification/error.log",
      out_file: "/var/log/projectos-notification/output.log",
      merge_logs: true,

      env: {
        NODE_ENV: "production"
      }
    }
  ]
};
