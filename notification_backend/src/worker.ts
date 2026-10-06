import type { DocumentData, DocumentReference, QueryDocumentSnapshot } from "firebase-admin/firestore";

type Unsubscribe = () => void;
import { adminDb } from "./firebase";
import { log } from "./log";
import { processNotificationDocument } from "./notification_sender";
import { timestampValue } from "./values";

const companyListeners = new Map<string, Unsubscribe>();
const dueTimers = new Map<string, NodeJS.Timeout>();
const inFlight = new Set<Promise<void>>();
let companiesUnsubscribe: Unsubscribe | null = null;
let stopping = false;

function cancelScheduled(path: string): void {
  const timer = dueTimers.get(path);
  if (timer) clearTimeout(timer);
  dueTimers.delete(path);
}

function runTracked(ref: DocumentReference): void {
  cancelScheduled(ref.path);
  const task = processNotificationDocument(ref)
    .catch((error) => log.error("Scheduled notification processing failed.", { path: ref.path, error: String(error) }))
    .finally(() => inFlight.delete(task));
  inFlight.add(task);
}

function schedule(ref: DocumentReference, data: DocumentData): void {
  cancelScheduled(ref.path);
  if (stopping || data.activeQueue !== true) return;
  const due = timestampValue(data.nextAttemptAt);
  if (!due) return;
  const delay = Math.max(0, due.toMillis() - Date.now());
  if (delay === 0) {
    runTracked(ref);
    return;
  }
  // Node timers have a signed 32-bit limit. Long delays are re-evaluated.
  const safeDelay = Math.min(delay, 2_000_000_000);
  const timer = setTimeout(() => runTracked(ref), safeDelay);
  timer.unref();
  dueTimers.set(ref.path, timer);
}

function attachCompany(companyId: string): void {
  if (companyListeners.has(companyId) || stopping) return;
  const query = adminDb
    .collection(`companies/${companyId}/notifications`)
    .where("activeQueue", "==", true);
  const unsubscribe = query.onSnapshot(
    (snapshot) => {
      for (const change of snapshot.docChanges()) {
        const document = change.doc as QueryDocumentSnapshot;
        if (change.type === "removed") cancelScheduled(document.ref.path);
        else schedule(document.ref, document.data());
      }
    },
    (error) => {
      log.error("Company notification listener failed.", { companyId, error: String(error) });
      const current = companyListeners.get(companyId);
      current?.();
      companyListeners.delete(companyId);
      if (!stopping) {
        const timer = setTimeout(() => attachCompany(companyId), 5_000);
        timer.unref();
      }
    },
  );
  companyListeners.set(companyId, unsubscribe);
  log.info("Attached company notification listener.", { companyId });
}

function detachCompany(companyId: string): void {
  companyListeners.get(companyId)?.();
  companyListeners.delete(companyId);
  for (const path of [...dueTimers.keys()]) {
    if (path.startsWith(`companies/${companyId}/notifications/`)) cancelScheduled(path);
  }
}

export function startWorker(): void {
  if (companiesUnsubscribe) return;
  stopping = false;
  companiesUnsubscribe = adminDb.collection("companies").onSnapshot(
    (snapshot) => {
      const activeIds = new Set(snapshot.docs.map((document) => document.id));
      for (const companyId of activeIds) attachCompany(companyId);
      for (const companyId of [...companyListeners.keys()]) {
        if (!activeIds.has(companyId)) detachCompany(companyId);
      }
    },
    (error) => log.error("Companies listener failed.", { error: String(error) }),
  );
  log.info("Real-time Oracle notification worker started.");
}

export async function stopWorker(): Promise<void> {
  stopping = true;
  companiesUnsubscribe?.();
  companiesUnsubscribe = null;
  for (const unsubscribe of companyListeners.values()) unsubscribe();
  companyListeners.clear();
  for (const timer of dueTimers.values()) clearTimeout(timer);
  dueTimers.clear();
  await Promise.allSettled([...inFlight]);
}
