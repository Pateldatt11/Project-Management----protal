import { FieldValue, Timestamp, type DocumentReference, type DocumentData } from "firebase-admin/firestore";
import { config } from "./config";
import { adminDb, adminMessaging } from "./firebase";
import { log } from "./log";
import { deleteInvalidTokens, loadFcmTokens } from "./tokens";
import { boolValue, intValue, safeData, stringValue, timestampValue } from "./values";

const COMPLETED_RESPONSES = new Set(["accepted", "declined", "muted", "read", "cancelled"]);

type ClaimedJob = {
  ref: DocumentReference;
  data: DocumentData;
  companyId: string;
  notificationId: string;
  recipientId: string;
  attemptNumber: number;
  maxAttempts: number;
  retryMinutes: number;
};

function memberNotificationRef(job: ClaimedJob): DocumentReference {
  return adminDb.doc(`companies/${job.companyId}/members/${job.recipientId}/notifications/${job.notificationId}`);
}

async function updateRootAndMirror(job: ClaimedJob, rootUpdate: DocumentData, mirrorUpdate?: DocumentData): Promise<void> {
  const batch = adminDb.batch();
  batch.set(job.ref, rootUpdate, { merge: true });
  batch.set(memberNotificationRef(job), mirrorUpdate ?? rootUpdate, { merge: true });
  await batch.commit();
}

async function claim(ref: DocumentReference): Promise<ClaimedJob | null> {
  return adminDb.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return null;
    const data = snapshot.data() ?? {};
    const now = Timestamp.now();
    const dueAt = timestampValue(data.nextAttemptAt);
    if (!dueAt || dueAt.toMillis() > now.toMillis()) return null;

    const responseStatus = stringValue(data.responseStatus, "pending").toLowerCase();
    if (COMPLETED_RESPONSES.has(responseStatus) || data.accepted === true || data.cancelled === true) {
      transaction.set(ref, {
        nextAttemptAt: FieldValue.delete(),
        activeQueue: false,
        pushStatus: `stopped_${responseStatus || "completed"}`,
        leaseOwner: FieldValue.delete(),
        leaseUntil: FieldValue.delete(),
      }, { merge: true });
      return null;
    }

    const leaseUntil = timestampValue(data.leaseUntil);
    if (leaseUntil && leaseUntil.toMillis() > now.toMillis()) return null;

    const companyId = stringValue(data.companyId) || ref.parent.parent?.id || "";
    const recipientId = stringValue(data.recipientId ?? data.targetUid);
    const notificationId = stringValue(data.notificationId, ref.id);
    if (!companyId || !recipientId || !notificationId) {
      transaction.set(ref, {
        pushStatus: "failed_invalid_queue_document",
        deliveryStatus: "failed",
        activeQueue: false,
        nextAttemptAt: FieldValue.delete(),
        lastError: "companyId, recipientId and notificationId are required",
      }, { merge: true });
      return null;
    }

    const attemptNumber = intValue(data.attemptCount, 0) + 1;
    const maxAttempts = intValue(data.maxAttempts, config.defaultMaxAttempts);
    const retryMinutes = intValue(data.retryIntervalMinutes, config.defaultRetryMinutes);
    if (attemptNumber > maxAttempts) {
      const escalation = {
        pushStatus: "escalated_no_response",
        deliveryStatus: "escalated",
        responseStatus: "no_response",
        adminAttentionRequired: true,
        activeQueue: false,
        nextAttemptAt: FieldValue.delete(),
        leaseOwner: FieldValue.delete(),
        leaseUntil: FieldValue.delete(),
        escalatedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };
      transaction.set(ref, escalation, { merge: true });
      transaction.set(
        adminDb.doc(`companies/${companyId}/members/${recipientId}/notifications/${notificationId}`),
        escalation,
        { merge: true },
      );
      transaction.set(
        adminDb.doc(`companies/${companyId}/notificationLogs/${notificationId}`),
        {
          notificationId,
          companyId,
          recipientId,
          title: stringValue(data.title, "Notification needs attention"),
          body: stringValue(data.body ?? data.message),
          type: stringValue(data.type, "notification"),
          taskId: stringValue(data.taskId),
          projectId: stringValue(data.projectId),
          deliveryStatus: "escalated",
          responseStatus: "no_response",
          attemptCount: intValue(data.attemptCount, maxAttempts),
          maxAttempts,
          reason: "employee_no_response_after_final_wait",
          adminAttentionRequired: true,
          escalatedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return null;
    }

    transaction.set(ref, {
      pushStatus: "sending_oracle_admin_sdk",
      deliveryStatus: "sending",
      attemptCount: attemptNumber,
      leaseOwner: config.instanceId,
      leaseUntil: Timestamp.fromMillis(now.toMillis() + config.leaseSeconds * 1000),
      lastAttemptStartedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ref, data, companyId, notificationId, recipientId, attemptNumber, maxAttempts, retryMinutes };
  });
}

function resolveAndroidSound(data: DocumentData): string {
  const raw = stringValue(data.androidSoundName ?? data.systemSoundName ?? data.soundName, "task_alert_airport_ding")
    .toLowerCase().replace(/-/g, "_");
  const allowed = new Set([
    "task_alert_airport_ding",
    "task_alert_church_bell",
    "old_phone_ringtone",
    "ringing_old_phone",
    "old_ring_tone",
    "emergency_alarm",
  ]);
  return allowed.has(raw) ? raw : "task_alert_airport_ding";
}

function completed(data: DocumentData): boolean {
  const status = stringValue(data.responseStatus, "pending").toLowerCase();
  return COMPLETED_RESPONSES.has(status) || data.accepted === true || data.cancelled === true;
}

export async function processNotificationDocument(ref: DocumentReference): Promise<void> {
  const job = await claim(ref);
  if (!job) return;
  const data = job.data;

  try {
    const latestSnapshot = await job.ref.get();
    const latest = latestSnapshot.data() ?? data;
    if (completed(latest)) {
      await updateRootAndMirror(job, {
        pushStatus: "stopped_employee_responded",
        activeQueue: false,
        nextAttemptAt: FieldValue.delete(),
        leaseOwner: FieldValue.delete(),
        leaseUntil: FieldValue.delete(),
      });
      return;
    }

    const expiresAt = timestampValue(latest.expiresAt ?? latest.visibleUntil);
    if (expiresAt && expiresAt.toMillis() <= Date.now()) {
      await updateRootAndMirror(job, {
        pushStatus: "skipped_expired",
        deliveryStatus: "expired",
        activeQueue: false,
        nextAttemptAt: FieldValue.delete(),
        leaseOwner: FieldValue.delete(),
        leaseUntil: FieldValue.delete(),
        pushCheckedAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    const tokenRecords = await loadFcmTokens(job.companyId, job.recipientId);
    const tokens = tokenRecords.map((record) => record.token);
    if (tokens.length === 0) {
      await finishFailedAttempt(job, "no_fcm_tokens", 0, 0, []);
      return;
    }

    const title = safeData(latest.title, "New work notification");
    const body = safeData(latest.body ?? latest.message, "You have a new notification.");
    const type = safeData(latest.type, "teamMention");
    const requiresAccept = boolValue(latest.requiresAccept, type === "taskAssigned" || type === "meetingInvite");
    const actionUrl = safeData(latest.actionUrl ?? latest.meetingUrl ?? latest.joinUrl);
    const soundName = safeData(latest.soundName, "user_preference");
    const androidSoundName = resolveAndroidSound(latest);
    const channelId = requiresAccept ? "urgent_work_alerts_v242_lock_screen" : "general_work_alerts";
    const nowMillis = Date.now();
    const errors: string[] = [];
    const invalidTokens = new Set<string>();
    let successCount = 0;
    let failureCount = 0;

    for (let start = 0; start < tokens.length; start += 500) {
      const chunk = tokens.slice(start, start + 500);
      const response = await adminMessaging.sendEachForMulticast({
        tokens: chunk,
        data: {
          title,
          body,
          message: body,
          companyId: job.companyId,
          recipientId: job.recipientId,
          targetUid: job.recipientId,
          notificationId: job.notificationId,
          taskId: safeData(latest.taskId),
          projectId: safeData(latest.projectId),
          teamId: safeData(latest.teamId),
          type,
          notificationType: type,
          alertLoop: requiresAccept ? "true" : "false",
          loopUntilAccept: boolValue(latest.loopUntilAccept, requiresAccept) ? "true" : "false",
          acceptButtonEnabled: boolValue(latest.acceptButtonEnabled, requiresAccept) ? "true" : "false",
          requiresAccept: requiresAccept ? "true" : "false",
          soundName,
          androidSoundName,
          forceSoundName: boolValue(latest.forceSoundName, false) ? "true" : "false",
          assistantVoice: boolValue(latest.assistantVoice, requiresAccept) ? "true" : "false",
          assistantText: safeData(latest.assistantText, requiresAccept ? "You have a new work notification. Please respond." : ""),
          actionUrl,
          meetingUrl: actionUrl,
          joinUrl: actionUrl,
          actionLabel: safeData(latest.actionLabel, actionUrl ? "Accept & Join" : "Accept"),
          rejectLabel: safeData(latest.rejectLabel, "Reject"),
          actionType: safeData(latest.actionType, actionUrl ? "meetingInvite" : ""),
          styleVariant: safeData(latest.styleVariant, "glass_remoteviews_v84"),
          channelId,
          createdAt: new Date(nowMillis).toISOString(),
          createdAtMillis: String(nowMillis),
          deliveryAttempt: String(job.attemptNumber),
          maxDeliveryAttempts: String(job.maxAttempts),
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          ttl: config.fcmTtlSeconds * 1000,
          restrictedPackageName: config.androidPackageName,
          collapseKey: job.notificationId.slice(0, 64),
        },
      });

      successCount += response.successCount;
      failureCount += response.failureCount;
      response.responses.forEach((item, index) => {
        if (item.success) return;
        const code = item.error?.code ?? "unknown";
        errors.push(`${code}:${item.error?.message ?? ""}`.slice(0, 300));
        if (code.includes("registration-token-not-registered") || code.includes("invalid-registration-token")) {
          invalidTokens.add(chunk[index]);
        }
      });
    }

    const invalidTokenCount = await deleteInvalidTokens(tokenRecords, invalidTokens);
    if (successCount === 0) {
      await finishFailedAttempt(job, errors[0] ?? "fcm_send_failed", failureCount, invalidTokenCount, errors);
      return;
    }

    // After the third successful delivery, wait one final retry interval.
    // The next worker pass escalates only if the employee still has not responded.
    const nextAttemptAt = requiresAccept
      ? Timestamp.fromMillis(Date.now() + job.retryMinutes * 60_000)
      : null;
    const rootUpdate: DocumentData = {
      pushStatus: requiresAccept ? "sent_waiting_response" : "sent",
      deliveryStatus: "sent",
      responseStatus: requiresAccept ? "pending" : "not_required",
      pushSentAt: FieldValue.serverTimestamp(),
      lastSentAt: FieldValue.serverTimestamp(),
      pushTokenCount: tokens.length,
      pushSuccessCount: successCount,
      pushFailureCount: failureCount,
      invalidTokenCount,
      pushErrors: errors.slice(0, 5),
      pushPayloadMode: "oracle_admin_sdk_data_only_high_priority",
      deliveryProvider: "oracle_admin_sdk",
      leaseOwner: FieldValue.delete(),
      leaseUntil: FieldValue.delete(),
      nextAttemptAt: nextAttemptAt ?? FieldValue.delete(),
      activeQueue: requiresAccept,
      adminAttentionRequired: false,
      updatedAt: FieldValue.serverTimestamp(),
    };
    await updateRootAndMirror(job, rootUpdate);

    log.info("Notification delivery attempt completed.", {
      notificationId: job.notificationId,
      companyId: job.companyId,
      recipientId: job.recipientId,
      attempt: job.attemptNumber,
      successCount,
      failureCount,
    });
  } catch (error) {
    await finishFailedAttempt(job, String(error), 0, 0, [String(error)]);
    log.error("Notification delivery attempt crashed.", {
      notificationId: job.notificationId,
      error: String(error),
    });
  }
}

async function finishFailedAttempt(
  job: ClaimedJob,
  reason: string,
  failureCount: number,
  invalidTokenCount: number,
  errors: string[],
): Promise<void> {
  const retry = job.attemptNumber < job.maxAttempts;
  const update: DocumentData = {
    pushStatus: retry ? "retry_scheduled" : "escalated_delivery_failed",
    deliveryStatus: retry ? "retry_pending" : "escalated",
    responseStatus: retry ? "pending" : "delivery_failed",
    lastError: reason.slice(0, 500),
    pushFailureCount: failureCount,
    invalidTokenCount,
    pushErrors: errors.slice(0, 5),
    leaseOwner: FieldValue.delete(),
    leaseUntil: FieldValue.delete(),
    nextAttemptAt: retry
      ? Timestamp.fromMillis(Date.now() + job.retryMinutes * 60_000)
      : FieldValue.delete(),
    activeQueue: retry,
    adminAttentionRequired: !retry,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (!retry) update.escalatedAt = FieldValue.serverTimestamp();
  await updateRootAndMirror(job, update);
  if (!retry) {
    await adminDb.doc(`companies/${job.companyId}/notificationLogs/${job.notificationId}`).set({
      notificationId: job.notificationId,
      companyId: job.companyId,
      recipientId: job.recipientId,
      title: stringValue(job.data.title, "Notification delivery failed"),
      body: stringValue(job.data.body ?? job.data.message),
      type: stringValue(job.data.type, "notification"),
      taskId: stringValue(job.data.taskId),
      projectId: stringValue(job.data.projectId),
      deliveryStatus: "escalated",
      responseStatus: "delivery_failed",
      attemptCount: job.attemptNumber,
      maxAttempts: job.maxAttempts,
      reason: reason.slice(0, 500),
      adminAttentionRequired: true,
      escalatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
}
