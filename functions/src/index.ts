import { createHash } from "crypto";
import * as admin from "firebase-admin";
import {
  onDocumentCreated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";

admin.initializeApp();

function stringField(data: Record<string, unknown>, keys: string[]): string {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === "string" && value.trim().length > 0) return value.trim();
  }
  return "";
}

function notificationExpiryMillis(data: Record<string, unknown>): number | undefined {
  const value = data.expiresAtMillis ??
    data.expiresAt ??
    data.visibleUntil ??
    data.hideAfter ??
    data.notificationExpiresAt ??
    data.ttlUntil ??
    data.validUntil;
  if (value == null) return undefined;
  if (typeof value === "number" && Number.isFinite(value)) return value < 10000000000 ? value * 1000 : value;
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!trimmed) return undefined;
    const numeric = Number(trimmed);
    if (Number.isFinite(numeric)) return numeric < 10000000000 ? numeric * 1000 : numeric;
    const parsed = Date.parse(trimmed);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  const timestampValue = value as { toMillis?: () => number; seconds?: number; _seconds?: number };
  if (typeof timestampValue.toMillis === "function") return timestampValue.toMillis();
  if (typeof timestampValue.seconds === "number") return timestampValue.seconds * 1000;
  if (typeof timestampValue._seconds === "number") return timestampValue._seconds * 1000;
  return undefined;
}

function defaultNotificationExpiryDate(now = new Date()): Date {
  return new Date(now.getFullYear(), now.getMonth() + 1, 1);
}

function notificationExpiryIso(data: Record<string, unknown>): string {
  const millis = notificationExpiryMillis(data);
  return millis == null ? "" : new Date(millis).toISOString();
}

function normalizeActionUrl(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return "";
  const lower = trimmed.toLowerCase();
  if (lower.startsWith("https://") || lower.startsWith("http://") || lower.startsWith("whatsapp://")) return trimmed;
  if (lower.startsWith("meet.google.com/") || lower.startsWith("wa.me/") || lower.startsWith("api.whatsapp.com/") || lower.startsWith("chat.whatsapp.com/") || lower.startsWith("call.whatsapp.com/")) return `https://${trimmed}`;
  return "";
}

function safeNotificationData(value: string | undefined): string {
  return (value ?? "").trim();
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function nativeRenderCompleted(value: unknown): boolean {
  const status = typeof value === "string" ? value.trim().toLowerCase() : "";
  return status === "rendered" ||
    status === "rendered_duplicate" ||
    status === "fallback_rendered" ||
    status === "system_fallback_rendered";
}

function normalizeNotificationType(value: string): string {
  const cleaned = value.trim().toLowerCase().replace(/[_-]/g, "");
  if (cleaned === "taskassigned") return "taskAssigned";
  if (cleaned === "deadlinereminder") return "deadlineReminder";
  if (cleaned === "meetinginvite" || cleaned === "googlemeet" || cleaned === "whatsappmeeting") return "meetingInvite";
  if (cleaned === "callinvite") return "callInvite";
  return value.trim() || "general";
}

function isMeetingLikeNotification(type: string, actionType: string, actionUrl: string): boolean {
  const cleanedType = type.trim().toLowerCase().replace(/[_-]/g, "");
  const cleanedAction = actionType.trim().toLowerCase().replace(/[_-]/g, "");
  return cleanedType === "meetinginvite" ||
    cleanedType === "callinvite" ||
    cleanedAction.includes("meet") ||
    cleanedAction.includes("call") ||
    cleanedAction.includes("whatsapp") ||
    actionUrl.includes("meet.google.com") ||
    actionUrl.includes("wa.me/") ||
    actionUrl.includes("whatsapp");
}

async function loadEnabledFcmTokenDocs(companyId: string, uid: string): Promise<Array<{ref: admin.firestore.DocumentReference; token: string}>> {
  const db = admin.firestore();
  const paths = [
    `users/${uid}/fcmTokens`,
    `companies/${companyId}/members/${uid}/fcmTokens`,
    `companies/${companyId}/users/${uid}/fcmTokens`,
    `companies/${companyId}/users/${uid}/devices`,
  ];
  const byToken = new Map<string, {ref: admin.firestore.DocumentReference; token: string}>();
  for (const path of paths) {
    try {
      const snap = await db.collection(path).get();
      snap.docs.forEach((doc) => {
        const data = doc.data();
        const enabled = data.enabled;
        const token = (data.token ?? data.fcmToken) as string | undefined;
        if (typeof token === "string" && token.trim().length > 20 && enabled !== false) {
          byToken.set(token.trim(), { ref: doc.ref, token: token.trim() });
        }
      });
    } catch (error) {
      console.warn(`Could not read FCM token collection ${path}.`, error);
    }
  }
  return [...byToken.values()];
}



type AuthAttemptRequestData = {
  email?: string;
  action?: string;
  success?: boolean;
  errorCode?: string;
  policy?: Record<string, unknown>;
};

type AuthRateLimitPolicy = {
  maxLoginFailures: number;
  maxSignupFailures: number;
  maxResetRequests: number;
  windowMinutes: number;
  lockoutMinutes: number;
  maxLockoutMinutes: number;
};

const defaultAuthRateLimitPolicy: AuthRateLimitPolicy = {
  maxLoginFailures: 5,
  maxSignupFailures: 3,
  maxResetRequests: 3,
  windowMinutes: 15,
  lockoutMinutes: 15,
  maxLockoutMinutes: 60,
};

function positiveInt(value: unknown, fallback: number): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : fallback;
}

function authPolicyFromRequest(value: unknown): AuthRateLimitPolicy {
  const raw = value && typeof value === "object" ? value as Record<string, unknown> : {};
  return {
    maxLoginFailures: positiveInt(raw.maxLoginFailures, defaultAuthRateLimitPolicy.maxLoginFailures),
    maxSignupFailures: positiveInt(raw.maxSignupFailures, defaultAuthRateLimitPolicy.maxSignupFailures),
    maxResetRequests: positiveInt(raw.maxResetRequests, defaultAuthRateLimitPolicy.maxResetRequests),
    windowMinutes: positiveInt(raw.windowMinutes, defaultAuthRateLimitPolicy.windowMinutes),
    lockoutMinutes: positiveInt(raw.lockoutMinutes, defaultAuthRateLimitPolicy.lockoutMinutes),
    maxLockoutMinutes: positiveInt(raw.maxLockoutMinutes, defaultAuthRateLimitPolicy.maxLockoutMinutes),
  };
}

function normalizeAuthIdentifier(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function normalizeAuthAction(value: unknown): "login" | "signup" | "passwordReset" {
  const cleaned = typeof value === "string" ? value.trim().toLowerCase().replace(/[\s_-]+/g, "") : "login";
  if (cleaned === "signup" || cleaned === "register" || cleaned === "createaccount") return "signup";
  if (cleaned === "passwordreset" || cleaned === "forgotpassword" || cleaned === "reset") return "passwordReset";
  return "login";
}

function authMaxFailures(action: string, policy: AuthRateLimitPolicy): number {
  if (action === "signup") return policy.maxSignupFailures;
  if (action === "passwordReset") return policy.maxResetRequests;
  return policy.maxLoginFailures;
}

function authRateLimitDocId(identifier: string, action: string): string {
  const hash = createHash("sha256").update(`${action}:${identifier}`).digest("hex");
  return `${action}_${hash}`;
}

function rateLimitDocRef(identifier: string, action: string): admin.firestore.DocumentReference {
  return admin.firestore().doc(`security/authRateLimits/${authRateLimitDocId(identifier, action)}`);
}

function timestampMillis(value: unknown): number | undefined {
  if (!value) return undefined;
  if (typeof value === "number") return value;
  const asTimestamp = value as { toMillis?: () => number; seconds?: number; _seconds?: number };
  if (typeof asTimestamp.toMillis === "function") return asTimestamp.toMillis();
  if (typeof asTimestamp.seconds === "number") return asTimestamp.seconds * 1000;
  if (typeof asTimestamp._seconds === "number") return asTimestamp._seconds * 1000;
  return undefined;
}

function retryAfterSeconds(lockedUntilMs: number, nowMs: number): number {
  return Math.max(1, Math.ceil((lockedUntilMs - nowMs) / 1000));
}

function rateLimitMessage(lockedUntilMs: number, nowMs: number): string {
  const minutes = Math.max(1, Math.ceil(retryAfterSeconds(lockedUntilMs, nowMs) / 60));
  return `Too many attempts. Please wait ${minutes}m and try again.`;
}

function throwIfLocked(data: Record<string, unknown>, nowMs: number): void {
  const lockedUntilMs = timestampMillis(data.lockedUntil);
  if (lockedUntilMs && lockedUntilMs > nowMs) {
    throw new HttpsError("resource-exhausted", rateLimitMessage(lockedUntilMs, nowMs), {
      retryAfterSeconds: retryAfterSeconds(lockedUntilMs, nowMs),
      lockedUntil: new Date(lockedUntilMs).toISOString(),
      message: rateLimitMessage(lockedUntilMs, nowMs),
    });
  }
}

export const checkAuthRateLimit = onCall<AuthAttemptRequestData>(async (request) => {
  const identifier = normalizeAuthIdentifier(request.data?.email);
  const action = normalizeAuthAction(request.data?.action);
  if (!identifier || !identifier.includes("@")) {
    throw new HttpsError("invalid-argument", "A valid email is required.");
  }

  const ref = rateLimitDocRef(identifier, action);
  const snap = await ref.get();
  if (snap.exists) throwIfLocked(snap.data() as Record<string, unknown>, Date.now());

  return { allowed: true, action };
});

export const recordAuthAttempt = onCall<AuthAttemptRequestData>(async (request) => {
  const identifier = normalizeAuthIdentifier(request.data?.email);
  const action = normalizeAuthAction(request.data?.action);
  const success = request.data?.success === true;
  const policy = authPolicyFromRequest(request.data?.policy);
  if (!identifier || !identifier.includes("@")) {
    throw new HttpsError("invalid-argument", "A valid email is required.");
  }

  const ref = rateLimitDocRef(identifier, action);
  const nowMs = Date.now();
  const now = admin.firestore.Timestamp.fromMillis(nowMs);
  const windowMs = policy.windowMinutes * 60 * 1000;
  const maxFailures = authMaxFailures(action, policy);

  return admin.firestore().runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    const existing = snap.exists ? snap.data() as Record<string, unknown> : {};
    throwIfLocked(existing, nowMs);

    if (success) {
      transaction.set(ref, {
        identifierHash: createHash("sha256").update(identifier).digest("hex"),
        action,
        failCount: 0,
        lockedUntil: admin.firestore.FieldValue.delete(),
        lastSuccessAt: now,
        lastAttemptAt: now,
        updatedAt: now,
      }, { merge: true });
      return { allowed: true, action, failCount: 0 };
    }

    const windowStartMs = timestampMillis(existing.windowStart) ?? nowMs;
    const windowExpired = nowMs - windowStartMs > windowMs;
    const previousFailures = windowExpired ? 0 : positiveInt(existing.failCount, 0);
    const failCount = previousFailures + 1;
    const lockMultiplier = Math.max(1, Math.floor((failCount - maxFailures) / maxFailures) + 1);
    const shouldLock = failCount >= maxFailures;
    const lockMinutes = Math.min(policy.maxLockoutMinutes, policy.lockoutMinutes * lockMultiplier);
    const lockedUntilDate = shouldLock ? admin.firestore.Timestamp.fromMillis(nowMs + lockMinutes * 60 * 1000) : null;

    transaction.set(ref, {
      identifierHash: createHash("sha256").update(identifier).digest("hex"),
      action,
      failCount,
      windowStart: windowExpired ? now : (existing.windowStart ?? now),
      lockedUntil: lockedUntilDate ?? admin.firestore.FieldValue.delete(),
      lastFailureAt: now,
      lastAttemptAt: now,
      lastErrorCode: request.data?.errorCode ?? "unknown",
      updatedAt: now,
    }, { merge: true });

    if (shouldLock && lockedUntilDate) {
      const lockedUntilMs = lockedUntilDate.toMillis();
      return {
        allowed: false,
        action,
        failCount,
        retryAfterSeconds: retryAfterSeconds(lockedUntilMs, nowMs),
        lockedUntil: new Date(lockedUntilMs).toISOString(),
        message: rateLimitMessage(lockedUntilMs, nowMs),
      };
    }

    return { allowed: true, action, failCount, remainingBeforeLock: Math.max(0, maxFailures - failCount) };
  }).then((result) => {
    if (result.allowed === false) {
      throw new HttpsError("resource-exhausted", result.message as string, result);
    }
    return result;
  });
});

type MemberLookupResult = {
  ref: admin.firestore.DocumentReference;
  data: Record<string, unknown>;
};

type SendFcmRequestData = {
  companyId?: string;
  targetUid?: string;
  targetUids?: string[];
  projectId?: string;
  teamId?: string;
  title?: string;
  body?: string;
  type?: string;
  taskId?: string;
  notificationId?: string;
  deepLink?: string;
  actionUrl?: string;
  actionLabel?: string;
  rejectLabel?: string;
  actionType?: string;
  soundName?: string;
  androidSoundName?: string;
  forceSoundName?: boolean;
  requiresAccept?: boolean;
  loopUntilAccept?: boolean;
  assistantVoice?: boolean;
  assistantText?: string;
  expiresAt?: string;
  visibleUntil?: string;
  expiresAtMillis?: number;
};

const directFcmSenderRoles = new Set([
  "superAdmin",
  "admin",
  "itAdmin",
  "projectManager",
  "teamLead",
  "hrManager",
]);

function requestString(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value.trim() : fallback;
}

function requestBoolean(value: unknown, fallback = false): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") return value.trim().toLowerCase() === "true";
  return fallback;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => (typeof item === "string" ? item.trim() : ""))
    .filter(Boolean);
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values.filter((item) => item.trim().length > 0))];
}

function extractProjectIds(member: Record<string, unknown>): string[] {
  return uniqueStrings([
    ...stringArray(member.projectIds),
    ...stringArray(member.assignedProjectIds),
    ...stringArray(member.managedProjectIds),
    ...stringArray(member.workingProjectIds),
  ]);
}

function extractTeamIds(member: Record<string, unknown>): string[] {
  return uniqueStrings([
    ...stringArray(member.teamIds),
    ...stringArray(member.assignedTeamIds),
    ...stringArray(member.managedTeamIds),
  ]);
}

function hasObjectPermission(member: Record<string, unknown>, key: string): boolean | undefined {
  const permissions = member.permissions;
  if (!permissions || typeof permissions !== "object") return undefined;
  const value = (permissions as Record<string, unknown>)[key];
  return typeof value === "boolean" ? value : undefined;
}

function hasIntersection(left: string[], right: string[]): boolean {
  const rightSet = new Set(right);
  return left.some((item) => rightSet.has(item));
}

async function loadCompanyMember(companyId: string, uid: string): Promise<MemberLookupResult | undefined> {
  const db = admin.firestore();
  const refs = [
    db.doc(`companies/${companyId}/members/${uid}`),
    db.doc(`companies/${companyId}/users/${uid}`),
    db.doc(`users/${uid}`),
  ];
  for (const ref of refs) {
    const snap = await ref.get();
    if (snap.exists) return { ref, data: snap.data() as Record<string, unknown> };
  }
  return undefined;
}

function validateSenderPermission(sender: Record<string, unknown>): string {
  const role = requestString(sender.role, "employee");
  const status = requestString(sender.status, "active");
  const active = sender.active !== false && status !== "inactive" && status !== "disabled";
  const explicitCanSend = hasObjectPermission(sender, "canSendFcm");

  if (!active) {
    throw new HttpsError("permission-denied", "Your account is inactive.");
  }
  if (explicitCanSend === false) {
    throw new HttpsError("permission-denied", "FCM sending is disabled for your role.");
  }
  if (!directFcmSenderRoles.has(role) && explicitCanSend !== true) {
    throw new HttpsError("permission-denied", "You are not allowed to send FCM messages.");
  }
  return role;
}

function validateScopedTarget(
  senderRole: string,
  sender: Record<string, unknown>,
  target: Record<string, unknown>,
  projectId: string,
  teamId: string,
): void {
  if (["superAdmin", "admin", "itAdmin", "hrManager"].includes(senderRole)) return;

  const senderProjects = extractProjectIds(sender);
  const targetProjects = extractProjectIds(target);
  const senderTeams = extractTeamIds(sender);
  const targetTeams = extractTeamIds(target);

  const projectAllowed = projectId
    ? senderProjects.includes(projectId) && (targetProjects.length === 0 || targetProjects.includes(projectId))
    : hasIntersection(senderProjects, targetProjects);
  const teamAllowed = teamId
    ? senderTeams.includes(teamId) && (targetTeams.length === 0 || targetTeams.includes(teamId))
    : hasIntersection(senderTeams, targetTeams);

  if (!projectAllowed && !teamAllowed) {
    throw new HttpsError(
      "permission-denied",
      "Managers and team leads can send only inside their assigned project/team scope.",
    );
  }
}

function buildDirectFcmData(
  input: Required<Pick<SendFcmRequestData, "companyId" | "title" | "body">> & SendFcmRequestData,
  senderUid: string,
  targetUid: string,
): Record<string, string> {
  const normalizedType = normalizeNotificationType(requestString(input.type, "directMessage"));
  const requiresAccept = requestBoolean(input.requiresAccept, normalizedType === "taskAssigned" || normalizedType === "deadlineReminder");
  const loopUntilAccept = requestBoolean(input.loopUntilAccept, requiresAccept);
  const soundName = requestString(input.soundName, requiresAccept ? "user_preference" : "default");
  const assistantVoice = requestBoolean(input.assistantVoice, requiresAccept);
  const assistantText = requestString(
    input.assistantText,
    requiresAccept
      ? "You have a new work notification. Please accept it."
      : "You have a new work notification.",
  );
  const directExpiryIso = notificationExpiryIso(input as Record<string, unknown>);
  const directCreatedAtMillis = Date.now();

  return {
    title: input.title,
    body: input.body,
    message: input.body,
    companyId: input.companyId,
    senderUid,
    targetUid,
    type: normalizedType,
    notificationType: normalizedType,
    taskId: requestString(input.taskId),
    projectId: requestString(input.projectId),
    notificationId: requestString(input.notificationId),
    deepLink: requestString(input.deepLink),
    actionUrl: requestString(input.actionUrl),
    meetingUrl: requestString(input.actionUrl),
    joinUrl: requestString(input.actionUrl),
    actionLabel: requestString(input.actionLabel, requiresAccept ? "Accept" : "Open"),
    rejectLabel: requestString(input.rejectLabel, "Reject"),
    actionType: requestString(input.actionType),
    requiresAccept: requiresAccept ? "true" : "false",
    alertLoop: loopUntilAccept ? "true" : "false",
    loopUntilAccept: loopUntilAccept ? "true" : "false",
    acceptButtonEnabled: requiresAccept ? "true" : "false",
    soundName,
    androidSoundName: requestString(input.androidSoundName, soundName),
    forceSoundName: requestBoolean(input.forceSoundName, false) ? "true" : "false",
    assistantVoice: assistantVoice ? "true" : "false",
    assistantText,
    expiresAt: directExpiryIso,
    visibleUntil: directExpiryIso,
    createdAt: new Date(directCreatedAtMillis).toISOString(),
    createdAtMillis: directCreatedAtMillis.toString(),
    styleVariant: "glass_remoteviews_v84",
    channelId: requiresAccept ? "urgent_work_alerts_v242_lock_screen" : "general_work_alerts",
    click_action: "FLUTTER_NOTIFICATION_CLICK",
  };
}

async function deleteInvalidFcmTokens(
  tokenDocs: Array<{ref: admin.firestore.DocumentReference; token: string}>,
  tokens: string[],
  responses: admin.messaging.SendResponse[],
): Promise<number> {
  const invalidTokens = new Set<string>();
  responses.forEach((result, index) => {
    if (result.success) return;
    const code = result.error?.code ?? "";
    if (
      code.includes("registration-token-not-registered") ||
      code.includes("invalid-registration-token")
    ) {
      invalidTokens.add(tokens[index]);
    }
  });
  if (invalidTokens.size === 0) return 0;
  const batch = admin.firestore().batch();
  tokenDocs.forEach((item) => {
    if (invalidTokens.has(item.token)) batch.delete(item.ref);
  });
  await batch.commit();
  return invalidTokens.size;
}

async function sendFcmToUids(params: {
  companyId: string;
  senderUid: string;
  targetUids: string[];
  input: Required<Pick<SendFcmRequestData, "companyId" | "title" | "body">> & SendFcmRequestData;
}): Promise<{sent: number; failed: number; tokenCount: number; invalidTokenCount: number; noTokenUids: string[]}> {
  let sent = 0;
  let failed = 0;
  let tokenCount = 0;
  let invalidTokenCount = 0;
  const noTokenUids: string[] = [];

  for (const targetUid of uniqueStrings(params.targetUids)) {
    const tokenDocs = await loadEnabledFcmTokenDocs(params.companyId, targetUid);
    const tokens = tokenDocs.map((item) => item.token);
    if (tokens.length === 0) {
      noTokenUids.push(targetUid);
      continue;
    }

    const data = buildDirectFcmData(params.input, params.senderUid, targetUid);
    for (let start = 0; start < tokens.length; start += 500) {
      const chunkTokens = tokens.slice(start, start + 500);
      const chunkDocs = tokenDocs.filter((item) => chunkTokens.includes(item.token));
      const response = await admin.messaging().sendEachForMulticast({
        tokens: chunkTokens,
        data,
        android: {
          priority: "high",
          ttl: requestBoolean(params.input.requiresAccept, false) ? 60 * 60 * 1000 : 24 * 60 * 60 * 1000,
          restrictedPackageName: "com.example.test",
        },
      });
      sent += response.successCount;
      failed += response.failureCount;
      tokenCount += chunkTokens.length;
      invalidTokenCount += await deleteInvalidFcmTokens(chunkDocs, chunkTokens, response.responses);
    }
  }

  return { sent, failed, tokenCount, invalidTokenCount, noTokenUids };
}


type QueueNotificationResult = {
  queued: number;
  targetCount: number;
  notificationIds: string[];
};

function queuedNotificationType(rawType: string, fallback: string): string {
  const normalized = normalizeNotificationType(rawType || fallback);
  const allowed = new Set([
    "taskAssigned",
    "taskUpdated",
    "taskCompleted",
    "deadlineReminder",
    "projectUpdated",
    "teamMention",
    "securityAlert",
    "meetingInvite",
    "callInvite",
    "directMessage",
  ]);
  if (allowed.has(normalized)) return normalized;
  const cleaned = normalized.trim().toLowerCase().replace(/[_-]/g, "");
  if (cleaned.includes("project")) return "projectUpdated";
  if (cleaned.includes("team")) return "teamMention";
  return fallback;
}

async function queueFirestoreNotifications(params: {
  companyId: string;
  senderUid: string;
  targetUids: string[];
  input: Required<Pick<SendFcmRequestData, "companyId" | "title" | "body">> & SendFcmRequestData;
  defaultType: string;
  source: string;
}): Promise<QueueNotificationResult> {
  const db = admin.firestore();
  const targetUids = uniqueStrings(params.targetUids);
  const notificationIds: string[] = [];
  if (targetUids.length === 0) return { queued: 0, targetCount: 0, notificationIds };

  const nowMs = Date.now();
  const expiresAtMillis = notificationExpiryMillis(params.input as Record<string, unknown>);
  const expiresAt = expiresAtMillis == null ? defaultNotificationExpiryDate(new Date(nowMs)) : new Date(expiresAtMillis);
  const normalizedType = queuedNotificationType(requestString(params.input.type, params.defaultType), params.defaultType);
  const actionUrl = normalizeActionUrl(stringField(params.input as Record<string, unknown>, [
    "actionUrl",
    "meetingUrl",
    "meetLink",
    "meetingLink",
    "googleMeetUrl",
    "whatsappUrl",
    "whatsappMeetingUrl",
    "joinUrl",
    "conferenceUrl",
    "url",
  ]));
  const isMeeting = isMeetingLikeNotification(normalizedType, requestString(params.input.actionType), actionUrl);
  const finalType = isMeeting ? (normalizedType === "callInvite" ? "callInvite" : "meetingInvite") : normalizedType;
  const requiresAccept = requestBoolean(params.input.requiresAccept, finalType === "taskAssigned" || finalType === "deadlineReminder" || finalType === "meetingInvite" || finalType === "callInvite");
  const loopUntilAccept = requestBoolean(params.input.loopUntilAccept, requiresAccept);
  const assistantVoice = requestBoolean(params.input.assistantVoice, requiresAccept);
  const assistantText = requestString(
    params.input.assistantText,
    finalType === "taskAssigned"
      ? "You are assigned a new task. Please accept the notification."
      : (finalType === "meetingInvite" || finalType === "callInvite")
        ? "You have a meeting invite. Please accept and join, or reject the notification."
        : "You have a new work notification. Please accept the notification.",
  );
  const actionLabel = requestString(params.input.actionLabel, actionUrl ? "Accept & Join" : (requiresAccept ? "Accept" : "Open"));
  const rejectLabel = requestString(params.input.rejectLabel, "Reject");
  const actionType = requestString(params.input.actionType, actionUrl ? (finalType === "callInvite" ? "callInvite" : "meetingInvite") : "");
  const soundName = requestString(params.input.soundName, requiresAccept ? "user_preference" : "default");

  let batch = db.batch();
  let batchOps = 0;
  let queued = 0;

  async function commitIfFull(force = false): Promise<void> {
    if (batchOps === 0) return;
    if (!force && batchOps < 420) return;
    await batch.commit();
    batch = db.batch();
    batchOps = 0;
  }

  for (const uid of targetUids) {
    const seed = `${params.source}:${params.companyId}:${uid}:${params.senderUid}:${params.input.title}:${params.input.body}:${nowMs}:${Math.random()}`;
    const notificationId = `notif_${createHash("sha1").update(seed).digest("hex").slice(0, 24)}`;
    notificationIds.push(notificationId);
    const docData = {
      notificationId,
      companyId: params.companyId,
      recipientId: uid,
      recipientIds: [uid],
      senderUid: params.senderUid,
      actorId: params.senderUid,
      title: params.input.title,
      body: params.input.body,
      message: params.input.body,
      type: finalType,
      taskId: requestString(params.input.taskId),
      projectId: requestString(params.input.projectId),
      teamId: requestString(params.input.teamId),
      deepLink: requestString(params.input.deepLink),
      actionUrl,
      meetingUrl: actionUrl,
      joinUrl: actionUrl,
      actionLabel,
      rejectLabel,
      actionType,
      soundName,
      forceSoundName: requestBoolean(params.input.forceSoundName, false),
      requiresAccept,
      loopUntilAccept,
      assistantVoice,
      assistantText,
      isRead: false,
      read: false,
      accepted: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAtMillis: nowMs.toString(),
      expiresAt,
      visibleUntil: expiresAt,
      pushStatus: "queued_firestore_trigger",
      source: params.source,
      deliveryPipeline: "firestore_root_plus_member_mirror_all_ui_states_v245",
      pushPrimaryTrigger: "company_root",
    };

    const rootRef = db.doc(`companies/${params.companyId}/notifications/${notificationId}`);
    const memberRef = db.doc(`companies/${params.companyId}/members/${uid}/notifications/${notificationId}`);
    batch.set(rootRef, docData, { merge: false });
    batch.set(memberRef, docData, { merge: false });
    batchOps += 2;
    queued += 1;
    await commitIfFull();
  }

  await commitIfFull(true);
  return { queued, targetCount: targetUids.length, notificationIds };
}

export const sendDirectFcm = onCall<SendFcmRequestData>(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const companyId = requestString(request.data.companyId);
  const targetUid = requestString(request.data.targetUid);
  const title = requestString(request.data.title);
  const body = requestString(request.data.body);
  const projectId = requestString(request.data.projectId);
  const teamId = requestString(request.data.teamId);

  if (!companyId || !targetUid || !title || !body) {
    throw new HttpsError("invalid-argument", "companyId, targetUid, title and body are required.");
  }

  const [senderLookup, targetLookup] = await Promise.all([
    loadCompanyMember(companyId, request.auth.uid),
    loadCompanyMember(companyId, targetUid),
  ]);

  if (!senderLookup) throw new HttpsError("permission-denied", "Sender member profile not found.");
  if (!targetLookup) throw new HttpsError("not-found", "Target member profile not found.");

  const senderRole = validateSenderPermission(senderLookup.data);
  validateScopedTarget(senderRole, senderLookup.data, targetLookup.data, projectId, teamId);

  const input = { ...request.data, companyId, title, body };
  const result = await queueFirestoreNotifications({
    companyId,
    senderUid: request.auth.uid,
    targetUids: [targetUid],
    input,
    defaultType: "directMessage",
    source: "callable_direct_firestore_queue",
  });

  await admin.firestore().collection(`companies/${companyId}/notificationLogs`).add({
    senderUid: request.auth.uid,
    senderRole,
    targetUid,
    title,
    body,
    type: requestString(request.data.type, "directMessage"),
    taskId: requestString(request.data.taskId),
    projectId,
    teamId,
    targetCount: result.targetCount,
    queued: result.queued,
    status: result.queued > 0 ? "queued_firestore_trigger" : "no_targets",
    notificationIds: result.notificationIds.slice(0, 20),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    success: result.queued > 0,
    sent: 0,
    failed: 0,
    tokenCount: 0,
    invalidTokenCount: 0,
    noTokenUids: [],
    ...result,
    message: result.queued > 0
      ? "Notification queued. Firestore trigger will deliver it in foreground, background and normally terminated Android states."
      : "No target users were queued.",
  };
});

export const sendProjectFcm = onCall<SendFcmRequestData>(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const companyId = requestString(request.data.companyId);
  const projectId = requestString(request.data.projectId);
  const title = requestString(request.data.title);
  const body = requestString(request.data.body);

  if (!companyId || !projectId || !title || !body) {
    throw new HttpsError("invalid-argument", "companyId, projectId, title and body are required.");
  }

  const senderLookup = await loadCompanyMember(companyId, request.auth.uid);
  if (!senderLookup) throw new HttpsError("permission-denied", "Sender member profile not found.");
  const senderRole = validateSenderPermission(senderLookup.data);
  if (["projectManager", "teamLead"].includes(senderRole) && !extractProjectIds(senderLookup.data).includes(projectId)) {
    throw new HttpsError("permission-denied", "You can broadcast only to your assigned project.");
  }

  const membersSnap = await admin.firestore()
    .collection(`companies/${companyId}/members`)
    .where("projectIds", "array-contains", projectId)
    .get();
  const targetUids = membersSnap.docs
    .filter((doc) => doc.id !== request.auth?.uid && requestString(doc.data().status, "active") !== "inactive")
    .map((doc) => doc.id);

  const input = { ...request.data, companyId, projectId, title, body, type: requestString(request.data.type, "projectUpdated") };
  const result = await queueFirestoreNotifications({
    companyId,
    senderUid: request.auth.uid,
    targetUids,
    input,
    defaultType: "projectUpdated",
    source: "callable_project_firestore_queue",
  });

  await admin.firestore().collection(`companies/${companyId}/notificationLogs`).add({
    senderUid: request.auth.uid,
    senderRole,
    projectId,
    title,
    body,
    type: requestString(request.data.type, "projectUpdated"),
    targetCount: targetUids.length,
    queued: result.queued,
    status: result.queued > 0 ? "queued_firestore_trigger" : "no_targets",
    notificationIds: result.notificationIds.slice(0, 20),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    success: result.queued > 0,
    sent: 0,
    failed: 0,
    tokenCount: 0,
    invalidTokenCount: 0,
    noTokenUids: [],
    ...result,
  };
});

export const sendTeamFcm = onCall<SendFcmRequestData>(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const companyId = requestString(request.data.companyId);
  const teamId = requestString(request.data.teamId);
  const title = requestString(request.data.title);
  const body = requestString(request.data.body);

  if (!companyId || !teamId || !title || !body) {
    throw new HttpsError("invalid-argument", "companyId, teamId, title and body are required.");
  }

  const senderLookup = await loadCompanyMember(companyId, request.auth.uid);
  if (!senderLookup) throw new HttpsError("permission-denied", "Sender member profile not found.");
  const senderRole = validateSenderPermission(senderLookup.data);
  if (senderRole === "teamLead" && !extractTeamIds(senderLookup.data).includes(teamId)) {
    throw new HttpsError("permission-denied", "You can broadcast only to your assigned team.");
  }

  const membersSnap = await admin.firestore()
    .collection(`companies/${companyId}/members`)
    .where("teamIds", "array-contains", teamId)
    .get();
  const targetUids = membersSnap.docs
    .filter((doc) => doc.id !== request.auth?.uid && requestString(doc.data().status, "active") !== "inactive")
    .map((doc) => doc.id);

  const input = { ...request.data, companyId, teamId, title, body, type: requestString(request.data.type, "teamMention") };
  const result = await queueFirestoreNotifications({
    companyId,
    senderUid: request.auth.uid,
    targetUids,
    input,
    defaultType: "teamMention",
    source: "callable_team_firestore_queue",
  });

  await admin.firestore().collection(`companies/${companyId}/notificationLogs`).add({
    senderUid: request.auth.uid,
    senderRole,
    teamId,
    title,
    body,
    type: requestString(request.data.type, "teamMention"),
    targetCount: targetUids.length,
    queued: result.queued,
    status: result.queued > 0 ? "queued_firestore_trigger" : "no_targets",
    notificationIds: result.notificationIds.slice(0, 20),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    success: result.queued > 0,
    sent: 0,
    failed: 0,
    tokenCount: 0,
    invalidTokenCount: 0,
    noTokenUids: [],
    ...result,
  };
});

export const syncRoleClaimsOnMemberWrite = onDocumentWritten(
  "companies/{companyId}/members/{uid}",
  async (event) => {
    const after = event.data?.after;
    const uid = event.params.uid;
    const companyId = event.params.companyId;

    if (!after?.exists) {
      try {
        await admin
          .auth()
          .setCustomUserClaims(uid, { accountStatus: "removed" });
      } catch (error) {
        console.warn(`Could not mark removed account ${uid}.`, error);
      }
      return;
    }

    const member = after.data() as Record<string, unknown>;
    const role = (member.role as string | undefined) ?? "employee";
    const status = (member.status as string | undefined) ?? "active";
    const allowedRoles = [
      "superAdmin",
      "admin",
      "itAdmin",
      "projectManager",
      "teamLead",
      "developer",
      "qaTester",
      "designer",
      "devOps",
      "hrManager",
      "employee",
      "clientViewer",
    ];

    try {
      await admin.auth().setCustomUserClaims(uid, {
        activeCompanyId: companyId,
        role: allowedRoles.includes(role) ? role : "employee",
        isSuperAdmin: role === "superAdmin",
        accountStatus: status,
      });
    } catch (error) {
      console.warn(
        `Could not sync custom claims for ${uid}. This can happen for HR-created invite placeholders before the employee registers.`,
        error,
      );
    }
  },
);

export const sendPrivateNotificationPush = onDocumentWritten(
  "companies/{companyId}/notifications/{notificationId}",
  async (event) => {
    await dispatchPrivateNotificationPush(event.data?.after, {
      companyId: event.params.companyId,
      notificationId: event.params.notificationId,
      source: "company_root",
    });
  },
);

export const sendMemberNotificationPush = onDocumentWritten(
  "companies/{companyId}/members/{uid}/notifications/{notificationId}",
  async (event) => {
    await dispatchPrivateNotificationPush(event.data?.after, {
      companyId: event.params.companyId,
      notificationId: event.params.notificationId,
      uid: event.params.uid,
      source: "member_mirror",
    });
  },
);

async function dispatchPrivateNotificationPush(
  after: FirebaseFirestore.DocumentSnapshot | undefined,
  context: {
    companyId: string;
    notificationId: string;
    uid?: string;
    source: "company_root" | "member_mirror";
  },
): Promise<void> {
  if (!after?.exists) return;

  const data = after.data() as Record<string, unknown>;
  // The Oracle VM backend owns these jobs. Skip them here to prevent duplicate
  // pushes if Cloud Functions are deployed again in the future.
  if (data.deliveryProvider === "oracle_admin_sdk") return;
  const recipientId = ((data.recipientId as string | undefined) ?? context.uid ?? "").trim();

  if (context.source === "member_mirror") {
    const rootSnapshot = await admin.firestore().doc(`companies/${context.companyId}/notifications/${context.notificationId}`).get();
    if (rootSnapshot.exists) return;
  }

  if (!recipientId) {
    await after.ref.set(
      {
        pushStatus: "skipped_no_recipient",
        pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }

  const alreadyRead = data.isRead === true || data.read === true || data.accepted === true;
  if (alreadyRead) {
    await after.ref.set(
      {
        pushStatus: "skipped_read_or_accepted",
        pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }

  const forcePushAt = data.forcePushAt as { toMillis?: () => number } | undefined;
  const pushSentAt = data.pushSentAt as { toMillis?: () => number } | undefined;
  const hasFreshForcePush = forcePushAt && (!pushSentAt || (forcePushAt.toMillis?.() ?? 0) > (pushSentAt.toMillis?.() ?? 0));
  if (pushSentAt && !hasFreshForcePush) return;

  const title = (data.title as string | undefined) ?? (data.notificationTitle as string | undefined) ?? "Project update";
  const body = (data.body as string | undefined) ?? (data.message as string | undefined) ?? (data.notificationBody as string | undefined) ?? "You have a new notification.";
  const taskId = (data.taskId as string | undefined) ?? "";
  const projectId = (data.projectId as string | undefined) ?? "";
  const rawType = ((data.type as string | undefined) ?? "general").trim();
  let normalizedType = normalizeNotificationType(rawType);
  const assistantText =
    (data.assistantText as string | undefined) ??
    (normalizedType === "taskAssigned"
      ? "You are assigned a new task. Please accept the notification."
      : "You have a new work notification. Please accept the notification.");
  const assistantVoiceValue = data.assistantVoice;
  const assistantVoice =
    typeof assistantVoiceValue === "boolean"
      ? assistantVoiceValue
        ? "true"
        : "false"
      : ((assistantVoiceValue as string | undefined) ?? (normalizedType === "taskAssigned" ? "true" : "false"));
  const actionUrl = normalizeActionUrl(
    stringField(data, [
      "actionUrl",
      "meetingUrl",
      "meetLink",
      "meetingLink",
      "googleMeetUrl",
      "whatsappUrl",
      "whatsappMeetingUrl",
      "joinUrl",
      "conferenceUrl",
      "url",
    ]),
  );
  const actionLabel = safeNotificationData(stringField(data, ["actionLabel", "joinLabel", "primaryActionLabel"])) || (actionUrl ? "Accept & Join" : "Accept");
  const rejectLabel = safeNotificationData(stringField(data, ["rejectLabel", "secondaryActionLabel"])) || "Reject";
  const actionType = safeNotificationData(stringField(data, ["actionType", "meetingProvider", "actionMode"])) || (actionUrl ? (normalizedType === "callInvite" ? "callInvite" : "meetingInvite") : "");
  if (isMeetingLikeNotification(normalizedType, actionType, actionUrl)) {
    normalizedType = normalizedType === "callInvite" ? "callInvite" : "meetingInvite";
  }

  const expiresAtMillis = notificationExpiryMillis(data);
  const expiresAtIso = expiresAtMillis == null ? "" : new Date(expiresAtMillis).toISOString();
  if (expiresAtMillis != null && Date.now() >= expiresAtMillis) {
    await after.ref.set(
      {
        pushStatus: "skipped_expired",
        pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        pushExpiryAt: expiresAtIso,
      },
      { merge: true },
    );
    return;
  }

  const tokenDocs = await loadEnabledFcmTokenDocs(context.companyId, recipientId);
  const tokens = tokenDocs.map((item) => item.token);

  if (tokens.length === 0) {
    await after.ref.set(
      {
        pushStatus: "no_tokens",
        pushTokenCount: 0,
        pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }

  await after.ref.set(
    {
      pushStatus: "sending",
      pushTokenCount: tokens.length,
      pushAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const selectedSoundName = (data.soundName as string | undefined) ?? "user_preference";
  const androidSystemSoundName = (() => {
    const requested = ((data.androidSoundName as string | undefined) ??
      (data.systemSoundName as string | undefined) ??
      (selectedSoundName === "user_preference" || selectedSoundName === "default"
        ? "task_alert_airport_ding"
        : selectedSoundName))
      .trim()
      .toLowerCase()
      .replace(/-/g, "_");
    const allowed = new Set([
      "task_alert_airport_ding",
      "task_alert_church_bell",
      "old_phone_ringtone",
      "ringing_old_phone",
      "old_ring_tone",
      "emergency_alarm",
    ]);
    return allowed.has(requested) ? requested : "task_alert_airport_ding";
  })();
  const channelId = "urgent_work_alerts_v242_lock_screen";
  const pushCreatedAtMillis = Date.now();

  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    data: {
      title,
      body,
      message: body,
      companyId: context.companyId,
      recipientId,
      targetUid: recipientId,
      taskId,
      projectId,
      type: normalizedType,
      notificationType: normalizedType,
      notificationId: context.notificationId,
      alertLoop: "true",
      loopUntilAccept: "true",
      acceptButtonEnabled: "true",
      soundName: selectedSoundName,
      androidSoundName: androidSystemSoundName,
      forceSoundName: data.forceSoundName === true ? "true" : "false",
      assistantVoice,
      assistantText,
      expiresAt: expiresAtIso,
      visibleUntil: expiresAtIso,
      createdAt: new Date(pushCreatedAtMillis).toISOString(),
      createdAtMillis: pushCreatedAtMillis.toString(),
      actionUrl,
      meetingUrl: actionUrl,
      joinUrl: actionUrl,
      actionLabel,
      rejectLabel,
      actionType,
      styleVariant: "glass_remoteviews_v84",
      channelId,
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
    android: {
      priority: "high",
      ttl: 60 * 60 * 1000,
      restrictedPackageName: "com.example.test",
    },
  });

  const invalidTokens: string[] = [];
  const errors: string[] = [];
  response.responses.forEach((result, index) => {
    if (!result.success) {
      const code = result.error?.code ?? "unknown";
      errors.push(`${code}:${result.error?.message ?? ""}`.slice(0, 240));
      if (code.includes("registration-token-not-registered") || code.includes("invalid-registration-token")) {
        invalidTokens.push(tokens[index]);
      }
    }
  });

  if (invalidTokens.length > 0) {
    const batch = admin.firestore().batch();
    tokenDocs.forEach((item) => {
      if (item.token && invalidTokens.includes(item.token)) batch.delete(item.ref);
    });
    await batch.commit();
  }

  await after.ref.set(
    {
      pushStatus: response.successCount > 0 ? "sent" : "failed",
      pushSentAt: admin.firestore.FieldValue.serverTimestamp(),
      pushTokenCount: tokens.length,
      pushSuccessCount: response.successCount,
      pushFailureCount: response.failureCount,
      pushErrors: errors.slice(0, 5),
      pushPayloadMode: "data_only_high_priority_glass_remoteviews_v84_with_delayed_system_fallback_v242",
      pushVisibleWhenTerminated: true,
      pushRequiresNotForceStopped: true,
      pushAndroidChannelId: channelId,
      pushNotificationUiLayer: "android_remoteviews_glassmorphism_v84",
      pushAndroidSystemSoundName: androidSystemSoundName,
      pushExpiryAt: expiresAtIso,
      pushSystemFallbackDelayMs: 10000,
    },
    { merge: true },
  );

  if (response.successCount > 0 && data.disableSystemFallback !== true) {
    await sleep(10000);
    const latestSnap = await after.ref.get();
    const latest = (latestSnap.data() ?? {}) as Record<string, unknown>;
    const alreadyDone = latest.accepted === true || latest.isRead === true || latest.read === true;
    const alreadyFallback = latest.pushSystemFallbackSentAt != null;
    const rendered = nativeRenderCompleted(latest.nativeRenderStatus);
    if (!alreadyDone && !alreadyFallback && !rendered) {
      const fallbackResponse = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title,
          body,
        },
        data: {
          title,
          body,
          message: body,
          companyId: context.companyId,
          recipientId,
          targetUid: recipientId,
          taskId,
          projectId,
          type: normalizedType,
          notificationType: normalizedType,
          notificationId: context.notificationId,
          fallbackMode: "system_tray_visible",
          requiresOpenAppForAccept: "true",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          priority: "high",
          ttl: 60 * 60 * 1000,
          restrictedPackageName: "com.example.test",
          collapseKey: context.notificationId.substring(0, 64),
          notification: {
            channelId,
            tag: context.notificationId.substring(0, 64),
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
            priority: "high",
            visibility: "public",
          },
        },
      });
      await after.ref.set(
        {
          pushSystemFallbackStatus: fallbackResponse.successCount > 0 ? "sent" : "failed",
          pushSystemFallbackSentAt: admin.firestore.FieldValue.serverTimestamp(),
          pushSystemFallbackSuccessCount: fallbackResponse.successCount,
          pushSystemFallbackFailureCount: fallbackResponse.failureCount,
          nativeRenderStatusBeforeFallback: latest.nativeRenderStatus ?? "missing",
        },
        { merge: true },
      );
    }
  }
}

export const updateProjectStatsOnTaskWrite = onDocumentWritten(
  "companies/{companyId}/tasks/{taskId}",
  async (event) => {
    const after = event.data?.after.data();
    const before = event.data?.before.data();
    const companyId = event.params.companyId;
    const projectId =
      (after?.projectId as string | undefined) ??
      (before?.projectId as string | undefined);
    if (!projectId) return;

    const tasksSnap = await admin
      .firestore()
      .collection(`companies/${companyId}/tasks`)
      .where("projectId", "==", projectId)
      .get();

    const totalTasks = tasksSnap.size;
    const completedTasks = tasksSnap.docs.filter(
      (doc) => doc.data().status === "completed",
    ).length;
    const progress =
      totalTasks === 0 ? 0 : Math.round((completedTasks / totalTasks) * 100);

    const update: Record<string, unknown> = {
      totalTasks,
      completedTasks,
      progress,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (progress === 100) update.status = "completed";

    await admin
      .firestore()
      .doc(`companies/${companyId}/projects/${projectId}`)
      .set(update, { merge: true });
  },
);

export const createTaskAssignmentNotifications = onDocumentWritten(
  "companies/{companyId}/tasks/{taskId}",
  async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists) return;

    const after = afterSnap.data() as Record<string, unknown>;
    const before = event.data?.before.exists
      ? (event.data.before.data() as Record<string, unknown>)
      : undefined;
    const companyId = event.params.companyId;
    const taskId = event.params.taskId;
    const assignedAfter = new Set(
      (
        (after.assignedToIds ??
          after.assignees ??
          after.assignedTo ??
          []) as string[]
      ).filter(Boolean),
    );
    const assignedBefore = new Set(
      (
        (before?.assignedToIds ??
          before?.assignees ??
          before?.assignedTo ??
          []) as string[]
      ).filter(Boolean),
    );
    const newlyAssigned = [...assignedAfter].filter(
      (uid) => !assignedBefore.has(uid),
    );
    if (newlyAssigned.length === 0) return;

    const status = ((after.status as string | undefined) ?? "").toLowerCase();
    if (
      status === "completed" ||
      status === "cancelled" ||
      status === "archived"
    )
      return;

    const projectId = (after.projectId as string | undefined) ?? "";
    let projectName = (after.projectName as string | undefined) ?? "";
    if (!projectName && projectId) {
      try {
        const projectDoc = await admin
          .firestore()
          .doc(`companies/${companyId}/projects/${projectId}`)
          .get();
        projectName =
          (projectDoc.data()?.projectName as string | undefined) ??
          (projectDoc.data()?.name as string | undefined) ??
          "";
      } catch (_) {
        projectName = "";
      }
    }

    const meetingUrl = normalizeActionUrl(
      stringField(after, [
        "actionUrl",
        "meetingUrl",
        "meetLink",
        "meetingLink",
        "googleMeetUrl",
        "whatsappUrl",
        "whatsappMeetingUrl",
        "joinUrl",
        "conferenceUrl",
        "url",
      ]),
    );
    const taskTitle =
      (after.title as string | undefined) ??
      (after.taskTitle as string | undefined) ??
      "New task";
    const actorId =
      (after.createdBy as string | undefined) ??
      (after.updatedBy as string | undefined) ??
      "system";

    await Promise.all(
      newlyAssigned.map(async (uid) => {
        const notificationId = `task_assigned_${taskId}_${uid}`;
        const ref = admin
          .firestore()
          .collection(`companies/${companyId}/notifications`)
          .doc(notificationId);
        const memberRef = admin
          .firestore()
          .collection(`companies/${companyId}/members/${uid}/notifications`)
          .doc(notificationId);
        const existing = await ref.get();
        if (existing.exists) return;
        const notificationData = {
            notificationId,
            title: "New task assigned",
            message: projectName
              ? `${taskTitle} in ${projectName} has been assigned to you.`
              : `${taskTitle} has been assigned to you.`,
            type: meetingUrl ? "meetingInvite" : "taskAssigned",
            recipientId: uid,
            recipientIds: [uid],
            companyId,
            projectId,
            taskId,
            actorId,
            isRead: false,
            read: false,
            accepted: false,
            requiresAccept: true,
            loopUntilAccept: true,
            soundName: "user_preference",
            forceSoundName: false,
            assistantVoice: true,
            assistantText:
              meetingUrl
                ? "You have a meeting invite. Please accept and join, or reject the notification."
                : "You are assigned a new task. Please accept the notification.",
            actionUrl: meetingUrl,
            meetingUrl,
            joinUrl: meetingUrl,
            actionLabel: meetingUrl ? "Accept & Join" : "Accept",
            rejectLabel: "Reject",
            actionType: meetingUrl ? (meetingUrl.toLowerCase().includes("whatsapp") ? "whatsappMeeting" : "googleMeet") : "taskAssigned",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: defaultNotificationExpiryDate(),
            visibleUntil: defaultNotificationExpiryDate(),
            deliveryPipeline: "firestore_root_plus_member_mirror_all_ui_states_v245",
            pushPrimaryTrigger: "company_root",
          };
        const batch = admin.firestore().batch();
        batch.set(ref, notificationData, { merge: false });
        batch.set(memberRef, notificationData, { merge: false });
        await batch.commit();
      }),
    );
  },
);

export const createDeadlineReminderNotifications = onSchedule(
  "every day 09:00",
  async () => {
    const now = new Date();
    const in24h = new Date(now.getTime() + 24 * 60 * 60 * 1000);
    const companiesSnap = await admin
      .firestore()
      .collection("companies")
      .where("status", "==", "active")
      .get();

    for (const companyDoc of companiesSnap.docs) {
      const companyId = companyDoc.id;
      const tasksSnap = await admin
        .firestore()
        .collection(`companies/${companyId}/tasks`)
        .where("status", "in", [
          "backlog",
          "todo",
          "inProgress",
          "review",
          "testing",
        ])
        .where("dueDate", "<=", in24h.toISOString())
        .get();

      const batch = admin.firestore().batch();
      tasksSnap.docs.forEach((taskDoc) => {
        const task = taskDoc.data();
        const assignees = (task.assignedToIds ?? []) as string[];
        assignees.forEach((uid) => {
          const notificationRef = admin
            .firestore()
            .collection(`companies/${companyId}/notifications`)
            .doc();
          const memberNotificationRef = admin
            .firestore()
            .collection(`companies/${companyId}/members/${uid}/notifications`)
            .doc(notificationRef.id);
          const notificationData = {
            notificationId: notificationRef.id,
            title: "Deadline reminder",
            message: `${task.title ?? "Task"} is due soon.`,
            type: "deadlineReminder",
            recipientId: uid,
            recipientIds: [uid],
            companyId,
            projectId: task.projectId ?? "",
            taskId: taskDoc.id,
            actorId: "system",
            isRead: false,
            read: false,
            accepted: false,
            soundName: "user_preference",
            forceSoundName: false,
            requiresAccept: true,
            loopUntilAccept: true,
            assistantVoice: true,
            assistantText: "This task deadline is near. Please accept the notification.",
            actionLabel: "Accept",
            rejectLabel: "Reject",
            actionType: "deadlineReminder",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt: defaultNotificationExpiryDate(),
            visibleUntil: defaultNotificationExpiryDate(),
            deliveryPipeline: "firestore_root_plus_member_mirror_all_ui_states_v245",
            pushPrimaryTrigger: "company_root",
          };
          batch.set(notificationRef, notificationData);
          batch.set(memberNotificationRef, notificationData);
        });
      });
      await batch.commit();
    }
  },
);
