import { config } from "./config";
import { adminDb, firebaseCredentialsConfigured } from "./firebase";
import { buildHttpServer } from "./http_api";
import { log } from "./log";
import { startWorker, stopWorker } from "./worker";

async function main(): Promise<void> {
  let firebaseReady = false;
  if (!firebaseCredentialsConfigured && config.allowStartWithoutFirebase) {
    log.warn("Firebase credential is not configured; starting in health-only setup mode.");
  } else {
    try {
      await adminDb.collection("companies").limit(1).get();
      firebaseReady = true;
      log.info("Firebase Admin SDK connection verified.", { projectId: config.firebaseProjectId });
    } catch (error) {
      log.error("Firebase Admin SDK startup verification failed.", { error: String(error) });
      if (!config.allowStartWithoutFirebase) throw error;
    }
  }

  const server = buildHttpServer();
  server.listen(config.port, config.host, () => {
    log.info("Notification backend is online.", {
      host: config.host,
      port: config.port,
      projectId: config.firebaseProjectId,
      androidPackageName: config.androidPackageName,
    });
  });
  if (firebaseReady) {
    startWorker();
  } else {
    log.warn("Notification worker is disabled until Firebase credentials are available.");
  }

  let shuttingDown = false;
  const shutdown = async (signal: string): Promise<void> => {
    if (shuttingDown) return;
    shuttingDown = true;
    log.info("Graceful shutdown started.", { signal });
    await stopWorker();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    process.exit(0);
  };
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("uncaughtException", (error) => {
    log.error("Uncaught exception.", { error: String(error), stack: error.stack });
    void shutdown("uncaughtException");
  });
  process.on("unhandledRejection", (reason) => {
    log.error("Unhandled rejection.", { reason: String(reason) });
  });
}

void main().catch((error) => {
  log.error("Notification backend failed to start.", { error: String(error) });
  process.exit(1);
});
