import os from "node:os";

function readInt(name: string, fallback: number, min: number, max: number): number {
  const parsed = Number.parseInt(process.env[name] ?? "", 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(max, Math.max(min, parsed));
}

function readBool(name: string, fallback: boolean): boolean {
  const raw = (process.env[name] ?? "").trim().toLowerCase();
  if (!raw) return fallback;
  return raw === "1" || raw === "true" || raw === "yes" || raw === "on";
}

function readOrigins(): Set<string> {
  const raw = process.env.ADMIN_WEB_ORIGINS ?? "";
  return new Set(raw.split(",").map((value) => value.trim()).filter(Boolean));
}

export const config = Object.freeze({
  nodeEnv: process.env.NODE_ENV ?? "production",
  host: process.env.HOST ?? "0.0.0.0",
  port: readInt("PORT", 8080, 1, 65535),
  firebaseProjectId: process.env.FIREBASE_PROJECT_ID ?? "project-management-dashb-aa77a",
  androidPackageName: process.env.ANDROID_PACKAGE_NAME ?? "com.example.test",
  adminWebOrigins: readOrigins(),
  pollIntervalMs: readInt("POLL_INTERVAL_MS", 1500, 500, 60_000),
  workerBatchSize: readInt("WORKER_BATCH_SIZE", 40, 1, 100),
  leaseSeconds: readInt("LEASE_SECONDS", 60, 15, 600),
  defaultRetryMinutes: readInt("DEFAULT_RETRY_MINUTES", 5, 1, 1_440),
  defaultMaxAttempts: readInt("DEFAULT_MAX_ATTEMPTS", 3, 1, 20),
  fcmTtlSeconds: readInt("FCM_TTL_SECONDS", 3_600, 60, 2_419_200),
  apiRateLimitPerMinute: readInt("API_RATE_LIMIT_PER_MINUTE", 120, 10, 10_000),
  allowStartWithoutFirebase: readBool("ALLOW_START_WITHOUT_FIREBASE", false),
  instanceId: process.env.INSTANCE_ID ?? `${os.hostname()}-${process.pid}`,
});
