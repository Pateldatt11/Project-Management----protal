"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.finalizePreviousMonthlyAnalytics = exports.refreshCurrentMonthlyAnalytics = exports.rebuildMonthlyAnalytics = exports.applyScheduledEmploymentActions = exports.processEmploymentAction = exports.createDeadlineReminderNotifications = exports.createTaskAssignmentNotifications = exports.updateProjectStatsOnTaskWrite = exports.sendPrivateNotificationPush = exports.syncRoleClaimsOnMemberWrite = exports.sendTeamFcm = exports.sendProjectFcm = exports.sendDirectFcm = exports.recordAuthAttempt = exports.checkAuthRateLimit = void 0;
const crypto_1 = require("crypto");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const https_1 = require("firebase-functions/v2/https");
admin.initializeApp();
function stringField(data, keys) {
    for (const key of keys) {
        const value = data[key];
        if (typeof value === "string" && value.trim().length > 0)
            return value.trim();
    }
    return "";
}
function notificationExpiryMillis(data) {
    const value = data.expiresAtMillis ??
        data.expiresAt ??
        data.visibleUntil ??
        data.hideAfter ??
        data.notificationExpiresAt ??
        data.ttlUntil ??
        data.validUntil;
    if (value == null)
        return undefined;
    if (typeof value === "number" && Number.isFinite(value))
        return value < 10000000000 ? value * 1000 : value;
    if (typeof value === "string") {
        const trimmed = value.trim();
        if (!trimmed)
            return undefined;
        const numeric = Number(trimmed);
        if (Number.isFinite(numeric))
            return numeric < 10000000000 ? numeric * 1000 : numeric;
        const parsed = Date.parse(trimmed);
        return Number.isFinite(parsed) ? parsed : undefined;
    }
    const timestampValue = value;
    if (typeof timestampValue.toMillis === "function")
        return timestampValue.toMillis();
    if (typeof timestampValue.seconds === "number")
        return timestampValue.seconds * 1000;
    if (typeof timestampValue._seconds === "number")
        return timestampValue._seconds * 1000;
    return undefined;
}
function defaultNotificationExpiryDate(now = new Date()) {
    return new Date(now.getFullYear(), now.getMonth() + 1, 1);
}
function notificationExpiryIso(data) {
    const millis = notificationExpiryMillis(data);
    return millis == null ? "" : new Date(millis).toISOString();
}
function normalizeActionUrl(value) {
    const trimmed = value.trim();
    if (!trimmed)
        return "";
    const lower = trimmed.toLowerCase();
    if (lower.startsWith("https://") || lower.startsWith("http://") || lower.startsWith("whatsapp://"))
        return trimmed;
    if (lower.startsWith("meet.google.com/") || lower.startsWith("wa.me/") || lower.startsWith("api.whatsapp.com/") || lower.startsWith("chat.whatsapp.com/") || lower.startsWith("call.whatsapp.com/"))
        return `https://${trimmed}`;
    return "";
}
function safeNotificationData(value) {
    return (value ?? "").trim();
}
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
function nativeRenderCompleted(value) {
    const status = typeof value === "string" ? value.trim().toLowerCase() : "";
    return status === "rendered" ||
        status === "rendered_duplicate" ||
        status === "fallback_rendered" ||
        status === "system_fallback_rendered";
}
function normalizeNotificationType(value) {
    const cleaned = value.trim().toLowerCase().replace(/[_-]/g, "");
    if (cleaned === "taskassigned")
        return "taskAssigned";
    if (cleaned === "deadlinereminder")
        return "deadlineReminder";
    if (cleaned === "meetinginvite" || cleaned === "googlemeet" || cleaned === "whatsappmeeting")
        return "meetingInvite";
    if (cleaned === "callinvite")
        return "callInvite";
    return value.trim() || "general";
}
function isMeetingLikeNotification(type, actionType, actionUrl) {
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
async function loadEnabledFcmTokenDocs(companyId, uid) {
    const db = admin.firestore();
    const paths = [
        `users/${uid}/fcmTokens`,
        `companies/${companyId}/members/${uid}/fcmTokens`,
        `companies/${companyId}/users/${uid}/fcmTokens`,
        `companies/${companyId}/users/${uid}/devices`,
    ];
    const byToken = new Map();
    for (const path of paths) {
        try {
            const snap = await db.collection(path).get();
            snap.docs.forEach((doc) => {
                const data = doc.data();
                const enabled = data.enabled;
                const token = (data.token ?? data.fcmToken);
                if (typeof token === "string" && token.trim().length > 20 && enabled !== false) {
                    byToken.set(token.trim(), { ref: doc.ref, token: token.trim() });
                }
            });
        }
        catch (error) {
            console.warn(`Could not read FCM token collection ${path}.`, error);
        }
    }
    return [...byToken.values()];
}
const defaultAuthRateLimitPolicy = {
    maxLoginFailures: 5,
    maxSignupFailures: 3,
    maxResetRequests: 3,
    windowMinutes: 15,
    lockoutMinutes: 15,
    maxLockoutMinutes: 60,
};
function positiveInt(value, fallback) {
    const parsed = typeof value === "number" ? value : Number(value);
    return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : fallback;
}
function authPolicyFromRequest(value) {
    const raw = value && typeof value === "object" ? value : {};
    return {
        maxLoginFailures: positiveInt(raw.maxLoginFailures, defaultAuthRateLimitPolicy.maxLoginFailures),
        maxSignupFailures: positiveInt(raw.maxSignupFailures, defaultAuthRateLimitPolicy.maxSignupFailures),
        maxResetRequests: positiveInt(raw.maxResetRequests, defaultAuthRateLimitPolicy.maxResetRequests),
        windowMinutes: positiveInt(raw.windowMinutes, defaultAuthRateLimitPolicy.windowMinutes),
        lockoutMinutes: positiveInt(raw.lockoutMinutes, defaultAuthRateLimitPolicy.lockoutMinutes),
        maxLockoutMinutes: positiveInt(raw.maxLockoutMinutes, defaultAuthRateLimitPolicy.maxLockoutMinutes),
    };
}
function normalizeAuthIdentifier(value) {
    return typeof value === "string" ? value.trim().toLowerCase() : "";
}
function normalizeAuthAction(value) {
    const cleaned = typeof value === "string" ? value.trim().toLowerCase().replace(/[\s_-]+/g, "") : "login";
    if (cleaned === "signup" || cleaned === "register" || cleaned === "createaccount")
        return "signup";
    if (cleaned === "passwordreset" || cleaned === "forgotpassword" || cleaned === "reset")
        return "passwordReset";
    return "login";
}
function authMaxFailures(action, policy) {
    if (action === "signup")
        return policy.maxSignupFailures;
    if (action === "passwordReset")
        return policy.maxResetRequests;
    return policy.maxLoginFailures;
}
function authRateLimitDocId(identifier, action) {
    const hash = (0, crypto_1.createHash)("sha256").update(`${action}:${identifier}`).digest("hex");
    return `${action}_${hash}`;
}
function rateLimitDocRef(identifier, action) {
    return admin.firestore().doc(`security/authRateLimits/${authRateLimitDocId(identifier, action)}`);
}
function timestampMillis(value) {
    if (!value)
        return undefined;
    if (typeof value === "number")
        return value;
    const asTimestamp = value;
    if (typeof asTimestamp.toMillis === "function")
        return asTimestamp.toMillis();
    if (typeof asTimestamp.seconds === "number")
        return asTimestamp.seconds * 1000;
    if (typeof asTimestamp._seconds === "number")
        return asTimestamp._seconds * 1000;
    return undefined;
}
function retryAfterSeconds(lockedUntilMs, nowMs) {
    return Math.max(1, Math.ceil((lockedUntilMs - nowMs) / 1000));
}
function rateLimitMessage(lockedUntilMs, nowMs) {
    const minutes = Math.max(1, Math.ceil(retryAfterSeconds(lockedUntilMs, nowMs) / 60));
    return `Too many attempts. Please wait ${minutes}m and try again.`;
}
function throwIfLocked(data, nowMs) {
    const lockedUntilMs = timestampMillis(data.lockedUntil);
    if (lockedUntilMs && lockedUntilMs > nowMs) {
        throw new https_1.HttpsError("resource-exhausted", rateLimitMessage(lockedUntilMs, nowMs), {
            retryAfterSeconds: retryAfterSeconds(lockedUntilMs, nowMs),
            lockedUntil: new Date(lockedUntilMs).toISOString(),
            message: rateLimitMessage(lockedUntilMs, nowMs),
        });
    }
}
exports.checkAuthRateLimit = (0, https_1.onCall)(async (request) => {
    const identifier = normalizeAuthIdentifier(request.data?.email);
    const action = normalizeAuthAction(request.data?.action);
    if (!identifier || !identifier.includes("@")) {
        throw new https_1.HttpsError("invalid-argument", "A valid email is required.");
    }
    const ref = rateLimitDocRef(identifier, action);
    const snap = await ref.get();
    if (snap.exists)
        throwIfLocked(snap.data(), Date.now());
    return { allowed: true, action };
});
exports.recordAuthAttempt = (0, https_1.onCall)(async (request) => {
    const identifier = normalizeAuthIdentifier(request.data?.email);
    const action = normalizeAuthAction(request.data?.action);
    const success = request.data?.success === true;
    const policy = authPolicyFromRequest(request.data?.policy);
    if (!identifier || !identifier.includes("@")) {
        throw new https_1.HttpsError("invalid-argument", "A valid email is required.");
    }
    const ref = rateLimitDocRef(identifier, action);
    const nowMs = Date.now();
    const now = admin.firestore.Timestamp.fromMillis(nowMs);
    const windowMs = policy.windowMinutes * 60 * 1000;
    const maxFailures = authMaxFailures(action, policy);
    return admin.firestore().runTransaction(async (transaction) => {
        const snap = await transaction.get(ref);
        const existing = snap.exists ? snap.data() : {};
        throwIfLocked(existing, nowMs);
        if (success) {
            transaction.set(ref, {
                identifierHash: (0, crypto_1.createHash)("sha256").update(identifier).digest("hex"),
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
            identifierHash: (0, crypto_1.createHash)("sha256").update(identifier).digest("hex"),
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
            throw new https_1.HttpsError("resource-exhausted", result.message, result);
        }
        return result;
    });
});
const directFcmSenderRoles = new Set([
    "superAdmin",
    "admin",
    "itAdmin",
    "projectManager",
    "teamLead",
    "hrManager",
]);
function requestString(value, fallback = "") {
    return typeof value === "string" ? value.trim() : fallback;
}
function requestBoolean(value, fallback = false) {
    if (typeof value === "boolean")
        return value;
    if (typeof value === "string")
        return value.trim().toLowerCase() === "true";
    return fallback;
}
function stringArray(value) {
    if (!Array.isArray(value))
        return [];
    return value
        .map((item) => (typeof item === "string" ? item.trim() : ""))
        .filter(Boolean);
}
function uniqueStrings(values) {
    return [...new Set(values.filter((item) => item.trim().length > 0))];
}
function extractProjectIds(member) {
    return uniqueStrings([
        ...stringArray(member.projectIds),
        ...stringArray(member.assignedProjectIds),
        ...stringArray(member.managedProjectIds),
        ...stringArray(member.workingProjectIds),
    ]);
}
function extractTeamIds(member) {
    return uniqueStrings([
        ...stringArray(member.teamIds),
        ...stringArray(member.assignedTeamIds),
        ...stringArray(member.managedTeamIds),
    ]);
}
function hasObjectPermission(member, key) {
    const permissions = member.permissions;
    if (!permissions || typeof permissions !== "object")
        return undefined;
    const value = permissions[key];
    return typeof value === "boolean" ? value : undefined;
}
function hasIntersection(left, right) {
    const rightSet = new Set(right);
    return left.some((item) => rightSet.has(item));
}
async function loadCompanyMember(companyId, uid) {
    const db = admin.firestore();
    const refs = [
        db.doc(`companies/${companyId}/members/${uid}`),
        db.doc(`companies/${companyId}/users/${uid}`),
        db.doc(`users/${uid}`),
    ];
    for (const ref of refs) {
        const snap = await ref.get();
        if (snap.exists)
            return { ref, data: snap.data() };
    }
    return undefined;
}
function validateSenderPermission(sender) {
    const role = requestString(sender.role, "employee");
    const status = requestString(sender.status, "active");
    const active = sender.active !== false && status !== "inactive" && status !== "disabled";
    const explicitCanSend = hasObjectPermission(sender, "canSendFcm");
    if (!active) {
        throw new https_1.HttpsError("permission-denied", "Your account is inactive.");
    }
    if (explicitCanSend === false) {
        throw new https_1.HttpsError("permission-denied", "FCM sending is disabled for your role.");
    }
    if (!directFcmSenderRoles.has(role) && explicitCanSend !== true) {
        throw new https_1.HttpsError("permission-denied", "You are not allowed to send FCM messages.");
    }
    return role;
}
function validateScopedTarget(senderRole, sender, target, projectId, teamId) {
    if (["superAdmin", "admin", "itAdmin", "hrManager"].includes(senderRole))
        return;
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
        throw new https_1.HttpsError("permission-denied", "Managers and team leads can send only inside their assigned project/team scope.");
    }
}
function buildDirectFcmData(input, senderUid, targetUid) {
    const normalizedType = normalizeNotificationType(requestString(input.type, "directMessage"));
    const requiresAccept = requestBoolean(input.requiresAccept, normalizedType === "taskAssigned" || normalizedType === "deadlineReminder");
    const loopUntilAccept = requestBoolean(input.loopUntilAccept, requiresAccept);
    const soundName = requestString(input.soundName, requiresAccept ? "user_preference" : "default");
    const assistantVoice = requestBoolean(input.assistantVoice, requiresAccept);
    const assistantText = requestString(input.assistantText, requiresAccept
        ? "You have a new work notification. Please accept it."
        : "You have a new work notification.");
    const directExpiryIso = notificationExpiryIso(input);
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
async function deleteInvalidFcmTokens(tokenDocs, tokens, responses) {
    const invalidTokens = new Set();
    responses.forEach((result, index) => {
        if (result.success)
            return;
        const code = result.error?.code ?? "";
        if (code.includes("registration-token-not-registered") ||
            code.includes("invalid-registration-token")) {
            invalidTokens.add(tokens[index]);
        }
    });
    if (invalidTokens.size === 0)
        return 0;
    const batch = admin.firestore().batch();
    tokenDocs.forEach((item) => {
        if (invalidTokens.has(item.token))
            batch.delete(item.ref);
    });
    await batch.commit();
    return invalidTokens.size;
}
async function sendFcmToUids(params) {
    let sent = 0;
    let failed = 0;
    let tokenCount = 0;
    let invalidTokenCount = 0;
    const noTokenUids = [];
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
exports.sendDirectFcm = (0, https_1.onCall)(async (request) => {
    if (!request.auth?.uid) {
        throw new https_1.HttpsError("unauthenticated", "Login required.");
    }
    const companyId = requestString(request.data.companyId);
    const targetUid = requestString(request.data.targetUid);
    const title = requestString(request.data.title);
    const body = requestString(request.data.body);
    const projectId = requestString(request.data.projectId);
    const teamId = requestString(request.data.teamId);
    if (!companyId || !targetUid || !title || !body) {
        throw new https_1.HttpsError("invalid-argument", "companyId, targetUid, title and body are required.");
    }
    const [senderLookup, targetLookup] = await Promise.all([
        loadCompanyMember(companyId, request.auth.uid),
        loadCompanyMember(companyId, targetUid),
    ]);
    if (!senderLookup)
        throw new https_1.HttpsError("permission-denied", "Sender member profile not found.");
    if (!targetLookup)
        throw new https_1.HttpsError("not-found", "Target member profile not found.");
    const senderRole = validateSenderPermission(senderLookup.data);
    validateScopedTarget(senderRole, senderLookup.data, targetLookup.data, projectId, teamId);
    const input = { ...request.data, companyId, title, body };
    const result = await sendFcmToUids({
        companyId,
        senderUid: request.auth.uid,
        targetUids: [targetUid],
        input,
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
        tokenCount: result.tokenCount,
        sent: result.sent,
        failed: result.failed,
        invalidTokenCount: result.invalidTokenCount,
        noTokenUids: result.noTokenUids,
        status: result.sent > 0 ? (result.failed > 0 ? "partial" : "sent") : "failed_or_no_token",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
        success: result.sent > 0,
        ...result,
        message: result.sent > 0 ? "FCM sent." : "No active FCM token found for this user.",
    };
});
exports.sendProjectFcm = (0, https_1.onCall)(async (request) => {
    if (!request.auth?.uid) {
        throw new https_1.HttpsError("unauthenticated", "Login required.");
    }
    const companyId = requestString(request.data.companyId);
    const projectId = requestString(request.data.projectId);
    const title = requestString(request.data.title);
    const body = requestString(request.data.body);
    if (!companyId || !projectId || !title || !body) {
        throw new https_1.HttpsError("invalid-argument", "companyId, projectId, title and body are required.");
    }
    const senderLookup = await loadCompanyMember(companyId, request.auth.uid);
    if (!senderLookup)
        throw new https_1.HttpsError("permission-denied", "Sender member profile not found.");
    const senderRole = validateSenderPermission(senderLookup.data);
    if (["projectManager", "teamLead"].includes(senderRole) && !extractProjectIds(senderLookup.data).includes(projectId)) {
        throw new https_1.HttpsError("permission-denied", "You can broadcast only to your assigned project.");
    }
    const membersSnap = await admin.firestore()
        .collection(`companies/${companyId}/members`)
        .where("projectIds", "array-contains", projectId)
        .get();
    const targetUids = membersSnap.docs
        .filter((doc) => doc.id !== request.auth?.uid && requestString(doc.data().status, "active") !== "inactive")
        .map((doc) => doc.id);
    const input = { ...request.data, companyId, projectId, title, body };
    const result = await sendFcmToUids({
        companyId,
        senderUid: request.auth.uid,
        targetUids,
        input,
    });
    await admin.firestore().collection(`companies/${companyId}/notificationLogs`).add({
        senderUid: request.auth.uid,
        senderRole,
        projectId,
        title,
        body,
        type: requestString(request.data.type, "projectBroadcast"),
        targetCount: targetUids.length,
        tokenCount: result.tokenCount,
        sent: result.sent,
        failed: result.failed,
        invalidTokenCount: result.invalidTokenCount,
        noTokenUids: result.noTokenUids,
        status: result.sent > 0 ? (result.failed > 0 ? "partial" : "sent") : "failed_or_no_token",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: result.sent > 0, targetCount: targetUids.length, ...result };
});
exports.sendTeamFcm = (0, https_1.onCall)(async (request) => {
    if (!request.auth?.uid) {
        throw new https_1.HttpsError("unauthenticated", "Login required.");
    }
    const companyId = requestString(request.data.companyId);
    const teamId = requestString(request.data.teamId);
    const title = requestString(request.data.title);
    const body = requestString(request.data.body);
    if (!companyId || !teamId || !title || !body) {
        throw new https_1.HttpsError("invalid-argument", "companyId, teamId, title and body are required.");
    }
    const senderLookup = await loadCompanyMember(companyId, request.auth.uid);
    if (!senderLookup)
        throw new https_1.HttpsError("permission-denied", "Sender member profile not found.");
    const senderRole = validateSenderPermission(senderLookup.data);
    if (senderRole === "teamLead" && !extractTeamIds(senderLookup.data).includes(teamId)) {
        throw new https_1.HttpsError("permission-denied", "You can broadcast only to your assigned team.");
    }
    const membersSnap = await admin.firestore()
        .collection(`companies/${companyId}/members`)
        .where("teamIds", "array-contains", teamId)
        .get();
    const targetUids = membersSnap.docs
        .filter((doc) => doc.id !== request.auth?.uid && requestString(doc.data().status, "active") !== "inactive")
        .map((doc) => doc.id);
    const input = { ...request.data, companyId, teamId, title, body };
    const result = await sendFcmToUids({
        companyId,
        senderUid: request.auth.uid,
        targetUids,
        input,
    });
    await admin.firestore().collection(`companies/${companyId}/notificationLogs`).add({
        senderUid: request.auth.uid,
        senderRole,
        teamId,
        title,
        body,
        type: requestString(request.data.type, "teamBroadcast"),
        targetCount: targetUids.length,
        tokenCount: result.tokenCount,
        sent: result.sent,
        failed: result.failed,
        invalidTokenCount: result.invalidTokenCount,
        noTokenUids: result.noTokenUids,
        status: result.sent > 0 ? (result.failed > 0 ? "partial" : "sent") : "failed_or_no_token",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: result.sent > 0, targetCount: targetUids.length, ...result };
});
exports.syncRoleClaimsOnMemberWrite = (0, firestore_1.onDocumentWritten)("companies/{companyId}/members/{uid}", async (event) => {
    const after = event.data?.after;
    const uid = event.params.uid;
    const companyId = event.params.companyId;
    if (!after?.exists) {
        try {
            await admin
                .auth()
                .setCustomUserClaims(uid, { accountStatus: "removed" });
        }
        catch (error) {
            console.warn(`Could not mark removed account ${uid}.`, error);
        }
        return;
    }
    const member = after.data();
    const role = member.role ?? "employee";
    const status = member.status ?? "active";
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
    }
    catch (error) {
        console.warn(`Could not sync custom claims for ${uid}. This can happen for HR-created invite placeholders before the employee registers.`, error);
    }
});
exports.sendPrivateNotificationPush = (0, firestore_1.onDocumentWritten)("companies/{companyId}/notifications/{notificationId}", async (event) => {
    const after = event.data?.after;
    if (!after?.exists)
        return;
    const data = after.data();
    const recipientId = data.recipientId?.trim();
    const notificationId = event.params.notificationId;
    const companyId = event.params.companyId;
    if (!recipientId) {
        await after.ref.set({
            pushStatus: "skipped_no_recipient",
            pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    const alreadyRead = data.isRead === true || data.read === true || data.accepted === true;
    if (alreadyRead) {
        await after.ref.set({
            pushStatus: "skipped_read_or_accepted",
            pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    // Avoid replay loops. Function updates below will trigger this onWrite again;
    // this guard exits when the notification was already dispatched.
    const forcePushAt = data.forcePushAt;
    const pushSentAt = data.pushSentAt;
    const hasFreshForcePush = forcePushAt &&
        (!pushSentAt ||
            (forcePushAt.toMillis?.() ?? 0) > (pushSentAt.toMillis?.() ?? 0));
    if (pushSentAt && !hasFreshForcePush)
        return;
    const title = data.title ??
        data.notificationTitle ??
        "Project update";
    const body = data.body ??
        data.message ??
        data.notificationBody ??
        "You have a new notification.";
    const taskId = data.taskId ?? "";
    const projectId = data.projectId ?? "";
    const rawType = (data.type ?? "general").trim();
    let normalizedType = normalizeNotificationType(rawType);
    const assistantText = data.assistantText ??
        (normalizedType === "taskAssigned"
            ? "You are assigned a new task. Please accept the notification."
            : "You have a new work notification. Please accept the notification.");
    const assistantVoiceValue = data.assistantVoice;
    const assistantVoice = typeof assistantVoiceValue === "boolean"
        ? assistantVoiceValue
            ? "true"
            : "false"
        : (assistantVoiceValue ??
            (normalizedType === "taskAssigned" ? "true" : "false"));
    const actionUrl = normalizeActionUrl(stringField(data, [
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
    const actionLabel = safeNotificationData(stringField(data, ["actionLabel", "joinLabel", "primaryActionLabel"])) || (actionUrl ? "Accept & Join" : "Accept");
    const rejectLabel = safeNotificationData(stringField(data, ["rejectLabel", "secondaryActionLabel"])) || "Reject";
    const actionType = safeNotificationData(stringField(data, ["actionType", "meetingProvider", "actionMode"])) || (actionUrl ? (normalizedType === "callInvite" ? "callInvite" : "meetingInvite") : "");
    if (isMeetingLikeNotification(normalizedType, actionType, actionUrl)) {
        normalizedType = normalizedType === "callInvite" ? "callInvite" : "meetingInvite";
    }
    const expiresAtMillis = notificationExpiryMillis(data);
    const expiresAtIso = expiresAtMillis == null ? "" : new Date(expiresAtMillis).toISOString();
    if (expiresAtMillis != null && Date.now() >= expiresAtMillis) {
        await after.ref.set({
            pushStatus: "skipped_expired",
            pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
            pushExpiryAt: expiresAtIso,
        }, { merge: true });
        return;
    }
    const tokenDocs = await loadEnabledFcmTokenDocs(companyId, recipientId);
    const tokens = tokenDocs.map((item) => item.token);
    if (tokens.length === 0) {
        await after.ref.set({
            pushStatus: "no_tokens",
            pushTokenCount: 0,
            pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        return;
    }
    await after.ref.set({
        pushStatus: "sending",
        pushTokenCount: tokens.length,
        pushAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    const selectedSoundName = data.soundName ?? "user_preference";
    const androidSystemSoundName = (() => {
        const requested = (data.androidSoundName ??
            data.systemSoundName ??
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
        // V84 glassmorphism/native UI solution:
        // data-only high-priority messages let AppFirebaseMessagingService build
        // the Android RemoteViews notification layer instead of the default
        // system tray template. Do not force-stop the app during terminated tests.
        data: {
            title,
            body,
            message: body,
            companyId,
            taskId,
            projectId,
            type: normalizedType,
            notificationType: normalizedType,
            notificationId,
            alertLoop: "true",
            loopUntilAccept: "true",
            acceptButtonEnabled: "true",
            // Keep the user-selected device sound as the default. If an admin ever
            // needs to force a specific server sound, set forceSoundName=true on the
            // notification document.
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
    const invalidTokens = [];
    const errors = [];
    response.responses.forEach((result, index) => {
        if (!result.success) {
            const code = result.error?.code ?? "unknown";
            errors.push(`${code}:${result.error?.message ?? ""}`.slice(0, 240));
            if (code.includes("registration-token-not-registered") ||
                code.includes("invalid-registration-token")) {
                invalidTokens.push(tokens[index]);
            }
        }
    });
    if (invalidTokens.length > 0) {
        const batch = admin.firestore().batch();
        tokenDocs.forEach((item) => {
            if (item.token && invalidTokens.includes(item.token))
                batch.delete(item.ref);
        });
        await batch.commit();
    }
    await after.ref.set({
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
    }, { merge: true });
    // v242 terminated-state hardening:
    // Keep the native data-only message as the primary path so Android can show
    // the custom Accept/Reject RemoteViews notification. If the APK does not
    // confirm that native rendering completed within 10 seconds, send one normal
    // system-tray FCM notification as a visibility fallback. This avoids silent
    // failures on OEM builds that delay/block data-only processing while the app
    // is fully terminated.
    if (response.successCount > 0 && data.disableSystemFallback !== true) {
        await sleep(10000);
        const latestSnap = await after.ref.get();
        const latest = (latestSnap.data() ?? {});
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
                    companyId,
                    taskId,
                    projectId,
                    type: normalizedType,
                    notificationType: normalizedType,
                    notificationId,
                    fallbackMode: "system_tray_visible",
                    requiresOpenAppForAccept: "true",
                    click_action: "FLUTTER_NOTIFICATION_CLICK",
                },
                android: {
                    priority: "high",
                    ttl: 60 * 60 * 1000,
                    restrictedPackageName: "com.example.test",
                    collapseKey: notificationId.substring(0, 64),
                    notification: {
                        channelId,
                        tag: notificationId.substring(0, 64),
                        clickAction: "FLUTTER_NOTIFICATION_CLICK",
                        priority: "high",
                        visibility: "public",
                    },
                },
            });
            await after.ref.set({
                pushSystemFallbackStatus: fallbackResponse.successCount > 0 ? "sent" : "failed",
                pushSystemFallbackSentAt: admin.firestore.FieldValue.serverTimestamp(),
                pushSystemFallbackSuccessCount: fallbackResponse.successCount,
                pushSystemFallbackFailureCount: fallbackResponse.failureCount,
                nativeRenderStatusBeforeFallback: latest.nativeRenderStatus ?? "missing",
            }, { merge: true });
        }
    }
});
exports.updateProjectStatsOnTaskWrite = (0, firestore_1.onDocumentWritten)("companies/{companyId}/tasks/{taskId}", async (event) => {
    const after = event.data?.after.data();
    const before = event.data?.before.data();
    const companyId = event.params.companyId;
    const projectId = after?.projectId ??
        before?.projectId;
    if (!projectId)
        return;
    const tasksSnap = await admin
        .firestore()
        .collection(`companies/${companyId}/tasks`)
        .where("projectId", "==", projectId)
        .get();
    const totalTasks = tasksSnap.size;
    const completedTasks = tasksSnap.docs.filter((doc) => doc.data().status === "completed").length;
    const progress = totalTasks === 0 ? 0 : Math.round((completedTasks / totalTasks) * 100);
    const update = {
        totalTasks,
        completedTasks,
        progress,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (progress === 100)
        update.status = "completed";
    await admin
        .firestore()
        .doc(`companies/${companyId}/projects/${projectId}`)
        .set(update, { merge: true });
});
exports.createTaskAssignmentNotifications = (0, firestore_1.onDocumentWritten)("companies/{companyId}/tasks/{taskId}", async (event) => {
    const afterSnap = event.data?.after;
    if (!afterSnap?.exists)
        return;
    const after = afterSnap.data();
    const before = event.data?.before.exists
        ? event.data.before.data()
        : undefined;
    const companyId = event.params.companyId;
    const taskId = event.params.taskId;
    const assignedAfter = new Set((after.assignedToIds ??
        after.assignees ??
        after.assignedTo ??
        []).filter(Boolean));
    const assignedBefore = new Set((before?.assignedToIds ??
        before?.assignees ??
        before?.assignedTo ??
        []).filter(Boolean));
    const newlyAssigned = [...assignedAfter].filter((uid) => !assignedBefore.has(uid));
    if (newlyAssigned.length === 0)
        return;
    const status = (after.status ?? "").toLowerCase();
    if (status === "completed" ||
        status === "cancelled" ||
        status === "archived")
        return;
    const projectId = after.projectId ?? "";
    let projectName = after.projectName ?? "";
    if (!projectName && projectId) {
        try {
            const projectDoc = await admin
                .firestore()
                .doc(`companies/${companyId}/projects/${projectId}`)
                .get();
            projectName =
                projectDoc.data()?.projectName ??
                    projectDoc.data()?.name ??
                    "";
        }
        catch (_) {
            projectName = "";
        }
    }
    const meetingUrl = normalizeActionUrl(stringField(after, [
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
    const taskTitle = after.title ??
        after.taskTitle ??
        "New task";
    const actorId = after.createdBy ??
        after.updatedBy ??
        "system";
    await Promise.all(newlyAssigned.map(async (uid) => {
        const notificationId = `task_assigned_${taskId}_${uid}`;
        const ref = admin
            .firestore()
            .collection(`companies/${companyId}/notifications`)
            .doc(notificationId);
        const existing = await ref.get();
        if (existing.exists)
            return;
        await ref.set({
            notificationId,
            title: "New task assigned",
            message: projectName
                ? `${taskTitle} in ${projectName} has been assigned to you.`
                : `${taskTitle} has been assigned to you.`,
            type: meetingUrl ? "meetingInvite" : "taskAssigned",
            recipientId: uid,
            companyId,
            projectId,
            taskId,
            actorId,
            isRead: false,
            read: false,
            accepted: false,
            soundName: "user_preference",
            forceSoundName: false,
            assistantVoice: true,
            assistantText: meetingUrl
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
        }, { merge: false });
    }));
});
exports.createDeadlineReminderNotifications = (0, scheduler_1.onSchedule)("every day 09:00", async () => {
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
            const assignees = (task.assignedToIds ?? []);
            assignees.forEach((uid) => {
                const notificationRef = admin
                    .firestore()
                    .collection(`companies/${companyId}/notifications`)
                    .doc();
                batch.set(notificationRef, {
                    notificationId: notificationRef.id,
                    title: "Deadline reminder",
                    message: `${task.title ?? "Task"} is due soon.`,
                    type: "deadlineReminder",
                    recipientId: uid,
                    companyId,
                    projectId: task.projectId ?? "",
                    taskId: taskDoc.id,
                    actorId: "system",
                    isRead: false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    expiresAt: defaultNotificationExpiryDate(),
                    visibleUntil: defaultNotificationExpiryDate(),
                });
            });
        });
        await batch.commit();
    }
});
const analyticsTimeZone = "Asia/Kolkata";
const analyticsRegion = "asia-south1";
function cleanString(value) {
    return typeof value === "string" ? value.trim() : "";
}
function normalizedRole(value) {
    return cleanString(value).replace(/[\s_-]+/g, "").toLowerCase();
}
function roleAllowsCareerReview(roleValue) {
    const role = normalizedRole(roleValue);
    return ["superadmin", "admin", "hrmanager"].includes(role);
}
function roleAllowsCareerApproval(roleValue) {
    const role = normalizedRole(roleValue);
    return ["superadmin", "admin", "hrmanager"].includes(role);
}
function roleAllowsAnalyticsRebuild(roleValue) {
    const role = normalizedRole(roleValue);
    return ["superadmin", "admin", "projectmanager", "teamlead", "hrmanager"].includes(role);
}
async function authenticatedCompanyMember(companyId, uid) {
    const snap = await admin.firestore().doc(`companies/${companyId}/members/${uid}`).get();
    if (!snap.exists)
        throw new https_1.HttpsError("permission-denied", "Active company membership is required.");
    const data = snap.data();
    if (cleanString(data.status).toLowerCase() !== "active") {
        throw new https_1.HttpsError("permission-denied", "This company membership is not active.");
    }
    return data;
}
function allowedProposedRole(value) {
    const role = cleanString(value);
    return [
        "admin", "itAdmin", "hrManager", "projectManager", "teamLead", "developer",
        "qaTester", "designer", "devOps", "employee", "clientViewer",
    ].includes(role);
}
async function applyEmploymentActionInTransaction(tx, db, companyId, actionRef, actionId, action, employeeId, actorId, now) {
    const memberRef = db.doc(`companies/${companyId}/members/${employeeId}`);
    const memberSnap = await tx.get(memberRef);
    if (!memberSnap.exists)
        throw new https_1.HttpsError("not-found", "Employee record no longer exists.");
    const before = memberSnap.data();
    const proposedRole = cleanString(action.proposedRole);
    if (proposedRole && !allowedProposedRole(proposedRole)) {
        throw new https_1.HttpsError("failed-precondition", "The proposed role is not allowed for this workflow.");
    }
    const memberUpdate = {
        lastCareerActionId: actionId,
        lastCareerActionAt: now,
        updatedAt: now,
        updatedBy: actorId,
    };
    const copyProposed = (source, target) => {
        const value = cleanString(action[source]);
        if (value)
            memberUpdate[target] = value;
    };
    if (proposedRole)
        memberUpdate.role = proposedRole;
    copyProposed("proposedDepartment", "department");
    copyProposed("proposedJobTitle", "jobTitle");
    copyProposed("proposedGrade", "grade");
    copyProposed("proposedSalaryBand", "salaryBand");
    copyProposed("proposedReportingManagerId", "reportingManagerId");
    tx.set(memberRef, memberUpdate, { merge: true });
    tx.set(actionRef, {
        status: "approved",
        approvedBy: cleanString(action.approvedBy) || actorId,
        approvedAt: action.approvedAt ?? now,
        appliedBy: actorId,
        appliedAt: now,
        updatedAt: now,
    }, { merge: true });
    const historyRef = memberRef.collection("employmentHistory").doc(actionId);
    tx.set(historyRef, {
        ...action,
        actionId,
        status: "approved",
        appliedBy: actorId,
        appliedAt: now,
        recordedAt: now,
        before: {
            role: before.role ?? "",
            department: before.department ?? "",
            jobTitle: before.jobTitle ?? "",
            grade: before.grade ?? "",
            salaryBand: before.salaryBand ?? "",
            reportingManagerId: before.reportingManagerId ?? "",
        },
        after: memberUpdate,
    });
    const auditRef = db.collection(`companies/${companyId}/auditLogs`).doc();
    tx.set(auditRef, {
        auditLogId: auditRef.id,
        action: "employmentAction.applied",
        entityType: "employmentAction",
        entityId: actionId,
        actorId,
        before: { status: action.status ?? "", employeeId },
        after: { status: "approved", employeeId, actionType: action.actionType ?? "" },
        createdAt: now,
    });
    const notificationRef = db.collection(`companies/${companyId}/notifications`).doc();
    tx.set(notificationRef, {
        notificationId: notificationRef.id,
        companyId,
        recipientId: employeeId,
        title: `${cleanString(action.actionType) || "Employment action"} effective`,
        message: "Your approved employment action is now effective. Open your profile for details.",
        type: "projectUpdated",
        actorId,
        isRead: false,
        read: false,
        accepted: false,
        createdAt: now,
        expiresAt: defaultNotificationExpiryDate(),
        visibleUntil: defaultNotificationExpiryDate(),
    });
}
exports.processEmploymentAction = (0, https_1.onCall)({ region: analyticsRegion, timeoutSeconds: 60, memory: "256MiB" }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in before processing an employment action.");
    const companyId = cleanString(request.data?.companyId);
    const actionId = cleanString(request.data?.actionId);
    const command = request.data?.command;
    const comments = cleanString(request.data?.comments);
    if (!companyId || !actionId || !command) {
        throw new https_1.HttpsError("invalid-argument", "companyId, actionId, and command are required.");
    }
    const actor = await authenticatedCompanyMember(companyId, uid);
    if (command === "review" && !roleAllowsCareerReview(actor.role)) {
        throw new https_1.HttpsError("permission-denied", "Only HR or company administrators can review employment actions.");
    }
    if ((command === "approve" || command === "reject") && !roleAllowsCareerApproval(actor.role)) {
        throw new https_1.HttpsError("permission-denied", "Only HR or company administrators can approve or reject employment actions.");
    }
    if ((command === "review" || command === "reject") && comments.length < 5) {
        throw new https_1.HttpsError("invalid-argument", "Add a clear review comment with at least five characters.");
    }
    const db = admin.firestore();
    const actionRef = db.doc(`companies/${companyId}/employmentActions/${actionId}`);
    await db.runTransaction(async (tx) => {
        const actionSnap = await tx.get(actionRef);
        if (!actionSnap.exists)
            throw new https_1.HttpsError("not-found", "Employment action not found.");
        const action = actionSnap.data();
        const status = cleanString(action.status);
        if (["scheduled", "approved", "rejected", "cancelled", "error"].includes(status)) {
            throw new https_1.HttpsError("failed-precondition", "This employment action is already closed.");
        }
        const employeeId = cleanString(action.employeeId);
        if (!employeeId)
            throw new https_1.HttpsError("failed-precondition", "Employment action has no employeeId.");
        const now = admin.firestore.FieldValue.serverTimestamp();
        if (command === "review") {
            tx.set(actionRef, {
                status: "underReview",
                hrComments: comments,
                reviewedBy: uid,
                reviewedAt: now,
                updatedAt: now,
            }, { merge: true });
            return;
        }
        if (command === "reject") {
            tx.set(actionRef, {
                status: "rejected",
                hrComments: comments,
                rejectedBy: uid,
                rejectedAt: now,
                updatedAt: now,
            }, { merge: true });
            const auditRef = db.collection(`companies/${companyId}/auditLogs`).doc();
            tx.set(auditRef, {
                auditLogId: auditRef.id,
                action: "employmentAction.rejected",
                entityType: "employmentAction",
                entityId: actionId,
                actorId: uid,
                before: { status },
                after: { status: "rejected", employeeId, comments },
                createdAt: now,
            });
            return;
        }
        const effectiveDate = firestoreDate(action.effectiveDate);
        const shouldSchedule = !!effectiveDate && effectiveDate.getTime() > Date.now() + 60000;
        if (shouldSchedule) {
            tx.set(actionRef, {
                status: "scheduled",
                approvedBy: uid,
                approvedAt: now,
                scheduledFor: admin.firestore.Timestamp.fromDate(effectiveDate),
                updatedAt: now,
            }, { merge: true });
            const auditRef = db.collection(`companies/${companyId}/auditLogs`).doc();
            tx.set(auditRef, {
                auditLogId: auditRef.id,
                action: "employmentAction.scheduled",
                entityType: "employmentAction",
                entityId: actionId,
                actorId: uid,
                before: { status, employeeId },
                after: {
                    status: "scheduled",
                    employeeId,
                    actionType: action.actionType ?? "",
                    effectiveDate: admin.firestore.Timestamp.fromDate(effectiveDate),
                },
                createdAt: now,
            });
            const notificationRef = db.collection(`companies/${companyId}/notifications`).doc();
            tx.set(notificationRef, {
                notificationId: notificationRef.id,
                companyId,
                recipientId: employeeId,
                title: `${cleanString(action.actionType) || "Employment action"} approved`,
                message: `Your employment action is approved and scheduled for ${effectiveDate.toISOString().slice(0, 10)}.`,
                type: "projectUpdated",
                actorId: uid,
                isRead: false,
                read: false,
                accepted: false,
                createdAt: now,
                expiresAt: defaultNotificationExpiryDate(),
                visibleUntil: defaultNotificationExpiryDate(),
            });
            return;
        }
        await applyEmploymentActionInTransaction(tx, db, companyId, actionRef, actionId, action, employeeId, uid, now);
    });
    return { success: true, command, actionId };
});
exports.applyScheduledEmploymentActions = (0, scheduler_1.onSchedule)({
    schedule: "every 30 minutes",
    timeZone: analyticsTimeZone,
    region: analyticsRegion,
    timeoutSeconds: 300,
    memory: "512MiB",
}, async () => {
    const db = admin.firestore();
    const nowDate = new Date();
    const companiesSnap = await db.collection("companies").get();
    for (const companyDoc of companiesSnap.docs) {
        const companyId = companyDoc.id;
        const scheduledSnap = await db
            .collection(`companies/${companyId}/employmentActions`)
            .where("status", "==", "scheduled")
            .limit(250)
            .get();
        for (const scheduledDoc of scheduledSnap.docs) {
            const effectiveDate = firestoreDate(scheduledDoc.data().effectiveDate) ??
                firestoreDate(scheduledDoc.data().scheduledFor);
            if (!effectiveDate || effectiveDate > nowDate)
                continue;
            try {
                await db.runTransaction(async (tx) => {
                    const actionSnap = await tx.get(scheduledDoc.ref);
                    if (!actionSnap.exists)
                        return;
                    const action = actionSnap.data();
                    if (cleanString(action.status) !== "scheduled")
                        return;
                    const employeeId = cleanString(action.employeeId);
                    if (!employeeId) {
                        tx.set(scheduledDoc.ref, {
                            status: "error",
                            processingError: "Missing employeeId",
                            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                        }, { merge: true });
                        return;
                    }
                    await applyEmploymentActionInTransaction(tx, db, companyId, scheduledDoc.ref, scheduledDoc.id, action, employeeId, cleanString(action.approvedBy) || "system", admin.firestore.FieldValue.serverTimestamp());
                });
            }
            catch (error) {
                console.error("Failed to apply scheduled employment action", {
                    companyId,
                    actionId: scheduledDoc.id,
                    error,
                });
            }
        }
    }
});
function analyticsMonthId(date, timeZone = analyticsTimeZone) {
    const parts = new Intl.DateTimeFormat("en-CA", {
        timeZone,
        year: "numeric",
        month: "2-digit",
    }).formatToParts(date);
    const year = parts.find((part) => part.type === "year")?.value ?? `${date.getUTCFullYear()}`;
    const month = parts.find((part) => part.type === "month")?.value ?? `${date.getUTCMonth() + 1}`.padStart(2, "0");
    return `${year}-${month}`;
}
function validateMonthId(value) {
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(value)) {
        throw new https_1.HttpsError("invalid-argument", "monthId must use YYYY-MM format.");
    }
    return value;
}
function monthBounds(monthId) {
    const [yearText, monthText] = monthId.split("-");
    const year = Number(yearText);
    const month = Number(monthText);
    const nextYear = month === 12 ? year + 1 : year;
    const nextMonth = month === 12 ? 1 : month + 1;
    return {
        start: new Date(`${yearText}-${monthText}-01T00:00:00+05:30`),
        end: new Date(`${nextYear}-${`${nextMonth}`.padStart(2, "0")}-01T00:00:00+05:30`),
    };
}
function previousMonthId(now = new Date()) {
    const current = analyticsMonthId(now);
    const [yearText, monthText] = current.split("-");
    const year = Number(yearText);
    const month = Number(monthText);
    return month === 1 ? `${year - 1}-12` : `${year}-${`${month - 1}`.padStart(2, "0")}`;
}
function firestoreDate(value) {
    if (!value)
        return undefined;
    if (value instanceof Date)
        return value;
    if (typeof value === "string") {
        const parsed = new Date(value);
        return Number.isNaN(parsed.getTime()) ? undefined : parsed;
    }
    if (typeof value === "number") {
        const parsed = new Date(value < 10000000000 ? value * 1000 : value);
        return Number.isNaN(parsed.getTime()) ? undefined : parsed;
    }
    const candidate = value;
    if (typeof candidate.toDate === "function")
        return candidate.toDate();
    if (typeof candidate.toMillis === "function")
        return new Date(candidate.toMillis());
    if (typeof candidate.seconds === "number")
        return new Date(candidate.seconds * 1000);
    if (typeof candidate._seconds === "number")
        return new Date(candidate._seconds * 1000);
    return undefined;
}
function inMonth(value, start, end) {
    const date = firestoreDate(value);
    return !!date && date >= start && date < end;
}
function numberValue(value) {
    const parsed = typeof value === "number" ? value : Number(value ?? 0);
    return Number.isFinite(parsed) ? parsed : 0;
}
function stringList(value) {
    return Array.isArray(value) ? value.map((item) => cleanString(item)).filter(Boolean) : [];
}
function normalizedTaskStatus(value) {
    return cleanString(value) || "backlog";
}
function taskWasCompletedBefore(task, date) {
    const completedAt = firestoreDate(task.completedAt);
    return !!completedAt && completedAt < date;
}
function taskStatusAt(task, cutoff) {
    const completedAt = firestoreDate(task.completedAt);
    if (completedAt && completedAt < cutoff)
        return "completed";
    const currentStatus = normalizedTaskStatus(task.status);
    // A task marked completed after the reporting cutoff was still active at the
    // cutoff. Firestore does not retain every historic status transition, so the
    // safest non-misleading fallback is inProgress.
    return currentStatus === "completed" ? "inProgress" : currentStatus;
}
function taskOverdueAt(task, cutoff) {
    const dueDate = firestoreDate(task.dueDate);
    const completedAt = firestoreDate(task.completedAt);
    return !!dueDate && dueDate < cutoff && (!completedAt || completedAt >= cutoff);
}
async function buildMonthlyAnalyticsSnapshot(companyId, monthId, finalize) {
    const { start, end } = monthBounds(monthId);
    const now = new Date();
    const reportingCutoff = end <= now || finalize ? end : now;
    const db = admin.firestore();
    const [projectsSnap, tasksSnap, membersSnap, actionsSnap] = await Promise.all([
        db.collection(`companies/${companyId}/projects`).get(),
        db.collection(`companies/${companyId}/tasks`).get(),
        db.collection(`companies/${companyId}/members`).get(),
        db.collection(`companies/${companyId}/employmentActions`).get(),
    ]);
    const projects = projectsSnap.docs.map((doc) => ({
        ...doc.data(),
        id: doc.id,
    }));
    const tasks = tasksSnap.docs.map((doc) => ({
        ...doc.data(),
        id: doc.id,
    }));
    const members = membersSnap.docs.map((doc) => ({
        ...doc.data(),
        id: doc.id,
    }));
    const actions = actionsSnap.docs.map((doc) => ({
        ...doc.data(),
        id: doc.id,
    }));
    const relevantTasks = tasks.filter((task) => {
        const created = firestoreDate(task.createdAt) ?? firestoreDate(task.startDate) ?? firestoreDate(task.dueDate);
        const completed = firestoreDate(task.completedAt);
        const due = firestoreDate(task.dueDate);
        const startDate = firestoreDate(task.startDate);
        return (!!created && created < end && (!completed || completed >= start)) ||
            (!!due && due >= start && due < end) ||
            (!!startDate && startDate >= start && startDate < end);
    });
    const projectById = new Map(projects.map((project) => [cleanString(project.id), project]));
    const memberById = new Map(members.map((member) => [
        cleanString(member.id) || cleanString(member.uid),
        member,
    ]));
    const memberMetrics = new Map();
    for (const member of members) {
        const id = cleanString(member.id) || cleanString(member.uid);
        memberMetrics.set(id, {
            memberId: id,
            name: cleanString(member.displayName) || cleanString(member.name) || cleanString(member.email),
            role: cleanString(member.role),
            department: cleanString(member.department),
            discipline: cleanString(member.industryDiscipline) || cleanString(member.department),
            assigned: 0,
            completed: 0,
            overdue: 0,
            estimatedHours: 0,
            loggedHours: 0,
            appraisalScore: numberValue(member.appraisalScore),
            appraisalStatus: cleanString(member.appraisalStatus),
        });
    }
    const statusDistribution = {};
    const priorityDistribution = {};
    const projectMetrics = new Map();
    for (const project of projects) {
        const projectId = cleanString(project.id) || cleanString(project.projectId);
        projectMetrics.set(projectId, {
            projectId,
            name: cleanString(project.name) || cleanString(project.title) || projectId,
            status: cleanString(project.status),
            tasks: 0,
            completed: 0,
            overdue: 0,
            estimatedHours: 0,
            loggedHours: 0,
        });
    }
    let tasksCreated = 0;
    let tasksCompleted = 0;
    let tasksOverdue = 0;
    let tasksCarriedForward = 0;
    let estimatedHours = 0;
    let loggedHours = 0;
    for (const task of relevantTasks) {
        const status = taskStatusAt(task, reportingCutoff);
        const priority = cleanString(task.priority) || "medium";
        statusDistribution[status] = (statusDistribution[status] ?? 0) + 1;
        priorityDistribution[priority] = (priorityDistribution[priority] ?? 0) + 1;
        if (inMonth(task.createdAt, start, end))
            tasksCreated++;
        if (inMonth(task.completedAt, start, end))
            tasksCompleted++;
        const completedAt = firestoreDate(task.completedAt);
        const overdue = taskOverdueAt(task, reportingCutoff);
        if (overdue)
            tasksOverdue++;
        const created = firestoreDate(task.createdAt) ?? firestoreDate(task.startDate);
        if (created && created < start && !taskWasCompletedBefore(task, start))
            tasksCarriedForward++;
        const estimated = numberValue(task.estimatedHours);
        const logged = numberValue(task.loggedHours);
        estimatedHours += estimated;
        loggedHours += logged;
        const projectId = cleanString(task.projectId);
        const projectMetric = projectMetrics.get(projectId) ?? {
            projectId,
            name: cleanString(projectById.get(projectId)?.name) || projectId || "Unassigned",
            status: cleanString(projectById.get(projectId)?.status),
            tasks: 0,
            completed: 0,
            overdue: 0,
            estimatedHours: 0,
            loggedHours: 0,
        };
        projectMetric.tasks++;
        if (status === "completed")
            projectMetric.completed++;
        if (overdue)
            projectMetric.overdue++;
        projectMetric.estimatedHours += estimated;
        projectMetric.loggedHours += logged;
        projectMetrics.set(projectId, projectMetric);
        for (const uid of stringList(task.assignedToIds)) {
            const metric = memberMetrics.get(uid);
            if (!metric)
                continue;
            metric.assigned++;
            if (status === "completed")
                metric.completed++;
            if (overdue)
                metric.overdue++;
            metric.estimatedHours += estimated;
            metric.loggedHours += logged;
        }
    }
    const appraisalMembers = members.filter((member) => {
        const period = cleanString(member.appraisalPeriod);
        return period === monthId || inMonth(member.appraisalUpdatedAt, start, end);
    });
    const appraisalAverage = appraisalMembers.length === 0
        ? 0
        : Math.round(appraisalMembers.reduce((sum, member) => sum + numberValue(member.appraisalScore), 0) / appraisalMembers.length);
    const actionsInMonth = actions.filter((action) => inMonth(action.approvedAt, start, end) || inMonth(action.updatedAt, start, end) || cleanString(action.appraisalPeriod) === monthId);
    const actionCounts = {};
    for (const action of actionsInMonth) {
        const type = cleanString(action.actionType) || "other";
        const status = cleanString(action.status) || "draft";
        actionCounts[`${type}.${status}`] = (actionCounts[`${type}.${status}`] ?? 0) + 1;
    }
    const projectsStarted = projects.filter((project) => inMonth(project.startDate ?? project.createdAt, start, end)).length;
    const projectsCompleted = projects.filter((project) => cleanString(project.status).toLowerCase() === "completed" && inMonth(project.completedAt ?? project.updatedAt ?? project.endDate, start, end)).length;
    const projectsDelayed = projects.filter((project) => {
        const due = firestoreDate(project.endDate ?? project.dueDate);
        return !!due && due < end && cleanString(project.status).toLowerCase() !== "completed";
    }).length;
    const activeProjectCount = [...projectMetrics.values()].filter((item) => item.tasks > 0).length;
    const completionRate = relevantTasks.length === 0
        ? 0
        : Math.round(relevantTasks.filter((task) => taskStatusAt(task, reportingCutoff) === "completed").length * 100 / relevantTasks.length);
    const taskBreakdown = relevantTasks.map((task) => {
        const taskId = cleanString(task.id) || cleanString(task.taskId);
        const projectId = cleanString(task.projectId);
        const assignedToIds = stringList(task.assignedToIds);
        const startDate = firestoreDate(task.startDate);
        const dueDate = firestoreDate(task.dueDate);
        const completedAt = firestoreDate(task.completedAt);
        const createdAt = firestoreDate(task.createdAt);
        const statusAtPeriodEnd = taskStatusAt(task, reportingCutoff);
        const overdueAtPeriodEnd = taskOverdueAt(task, reportingCutoff);
        const completedLate = !!dueDate && !!completedAt && completedAt > dueDate && completedAt >= start && completedAt < end;
        return {
            taskId,
            title: cleanString(task.title) || cleanString(task.name) || taskId,
            projectId,
            projectName: cleanString(projectById.get(projectId)?.name) || projectId || "Unassigned",
            status: statusAtPeriodEnd,
            currentStatus: normalizedTaskStatus(task.status),
            priority: cleanString(task.priority) || "medium",
            startDate: startDate ? admin.firestore.Timestamp.fromDate(startDate) : null,
            dueDate: dueDate ? admin.firestore.Timestamp.fromDate(dueDate) : null,
            completedAt: completedAt ? admin.firestore.Timestamp.fromDate(completedAt) : null,
            createdAt: createdAt ? admin.firestore.Timestamp.fromDate(createdAt) : null,
            assignedToIds,
            assigneeNames: assignedToIds.map((uid) => {
                const member = memberById.get(uid);
                return cleanString(member?.displayName) || cleanString(member?.name) || cleanString(member?.email) || uid;
            }),
            estimatedHours: Number(numberValue(task.estimatedHours).toFixed(2)),
            loggedHours: Number(numberValue(task.loggedHours).toFixed(2)),
            isMilestone: task.isMilestone === true,
            riskLevel: cleanString(task.riskLevel) || "normal",
            dependencyTaskIds: stringList(task.dependencyTaskIds),
            progressPercent: Math.max(0, Math.min(100, Math.round(numberValue(task.progressPercent)))),
            createdInMonth: inMonth(task.createdAt, start, end),
            completedInMonth: inMonth(task.completedAt, start, end),
            overdueAtPeriodEnd,
            completedLate,
        };
    }).sort((a, b) => {
        const projectCompare = a.projectName.localeCompare(b.projectName);
        return projectCompare !== 0 ? projectCompare : a.title.localeCompare(b.title);
    });
    const employmentActionBreakdown = actionsInMonth.map((action) => ({
        actionId: cleanString(action.id) || cleanString(action.actionId),
        employeeId: cleanString(action.employeeId),
        employeeName: cleanString(action.employeeName),
        actionType: cleanString(action.actionType),
        status: cleanString(action.status),
        appraisalPeriod: cleanString(action.appraisalPeriod),
        appraisalScore: numberValue(action.appraisalScore),
        effectiveDate: firestoreDate(action.effectiveDate)
            ? admin.firestore.Timestamp.fromDate(firestoreDate(action.effectiveDate))
            : null,
        recommendedAt: firestoreDate(action.recommendedAt)
            ? admin.firestore.Timestamp.fromDate(firestoreDate(action.recommendedAt))
            : null,
        approvedAt: firestoreDate(action.approvedAt)
            ? admin.firestore.Timestamp.fromDate(firestoreDate(action.approvedAt))
            : null,
        proposedRole: cleanString(action.proposedRole),
        proposedDepartment: cleanString(action.proposedDepartment),
        proposedJobTitle: cleanString(action.proposedJobTitle),
        proposedGrade: cleanString(action.proposedGrade),
    })).sort((a, b) => a.employeeName.localeCompare(b.employeeName));
    return {
        monthId,
        companyId,
        periodStart: admin.firestore.Timestamp.fromDate(start),
        periodEnd: admin.firestore.Timestamp.fromDate(end),
        reportingCutoff: admin.firestore.Timestamp.fromDate(reportingCutoff),
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        finalizedAt: finalize ? admin.firestore.FieldValue.serverTimestamp() : null,
        isFinalized: finalize,
        dirty: false,
        schemaVersion: 2,
        metrics: {
            projectCount: projects.length,
            activeProjectCount,
            projectsStarted,
            projectsCompleted,
            projectsDelayed,
            taskCount: relevantTasks.length,
            tasksCreated,
            tasksCompleted,
            tasksOverdue,
            tasksCarriedForward,
            completionRate,
            estimatedHours: Number(estimatedHours.toFixed(2)),
            loggedHours: Number(loggedHours.toFixed(2)),
            memberCount: members.length,
            appraisalCount: appraisalMembers.length,
            appraisalAverage,
            employmentActionCount: actionsInMonth.length,
            statusDistribution,
            priorityDistribution,
            employmentActionDistribution: actionCounts,
        },
        projectBreakdown: [...projectMetrics.values()]
            .filter((item) => item.tasks > 0)
            .map((item) => ({
            ...item,
            completionRate: item.tasks === 0 ? 0 : Math.round(item.completed * 100 / item.tasks),
            estimatedHours: Number(item.estimatedHours.toFixed(2)),
            loggedHours: Number(item.loggedHours.toFixed(2)),
        }))
            .sort((a, b) => a.name.localeCompare(b.name)),
        employeeBreakdown: [...memberMetrics.values()]
            .filter((item) => item.assigned > 0 || item.appraisalScore > 0)
            .map((item) => ({
            ...item,
            completionRate: item.assigned === 0 ? 0 : Math.round(item.completed * 100 / item.assigned),
            estimatedHours: Number(item.estimatedHours.toFixed(2)),
            loggedHours: Number(item.loggedHours.toFixed(2)),
        }))
            .sort((a, b) => a.name.localeCompare(b.name)),
        taskBreakdown,
        employmentActionBreakdown,
    };
}
function safeBreakdownDocumentId(item, idField, index) {
    const raw = cleanString(item[idField]);
    if (raw && !raw.includes("/"))
        return raw;
    return (0, crypto_1.createHash)("sha256")
        .update(`${idField}:${raw}:${index}:${JSON.stringify(item)}`)
        .digest("hex")
        .slice(0, 32);
}
async function replaceMonthlyBreakdown(rootRef, collectionName, items, idField, generationId) {
    const collection = rootRef.collection(collectionName);
    const existing = await collection.get();
    const writer = admin.firestore().bulkWriter();
    const nextIds = new Set();
    items.forEach((item, index) => {
        const id = safeBreakdownDocumentId(item, idField, index);
        nextIds.add(id);
        writer.set(collection.doc(id), {
            ...item,
            generationId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    });
    for (const doc of existing.docs) {
        if (!nextIds.has(doc.id))
            writer.delete(doc.ref);
    }
    await writer.close();
}
async function saveMonthlyAnalyticsSnapshot(companyId, monthId, finalize, force = false) {
    validateMonthId(monthId);
    const ref = admin.firestore().doc(`companies/${companyId}/monthlyAnalytics/${monthId}`);
    const existing = await ref.get();
    if (existing.exists && existing.data()?.isFinalized === true && !force)
        return;
    const fullSnapshot = await buildMonthlyAnalyticsSnapshot(companyId, monthId, finalize);
    const projectBreakdown = Array.isArray(fullSnapshot.projectBreakdown)
        ? fullSnapshot.projectBreakdown
        : [];
    const employeeBreakdown = Array.isArray(fullSnapshot.employeeBreakdown)
        ? fullSnapshot.employeeBreakdown
        : [];
    const taskBreakdown = Array.isArray(fullSnapshot.taskBreakdown)
        ? fullSnapshot.taskBreakdown
        : [];
    const employmentActionBreakdown = Array.isArray(fullSnapshot.employmentActionBreakdown)
        ? fullSnapshot.employmentActionBreakdown
        : [];
    const generationId = (0, crypto_1.createHash)("sha256")
        .update(`${companyId}:${monthId}:${Date.now()}:${Math.random()}`)
        .digest("hex")
        .slice(0, 24);
    // Write detail collections first. The root generationId is published last so
    // clients never observe a partially updated monthly snapshot.
    await Promise.all([
        replaceMonthlyBreakdown(ref, "projects", projectBreakdown, "projectId", generationId),
        replaceMonthlyBreakdown(ref, "employees", employeeBreakdown, "memberId", generationId),
        replaceMonthlyBreakdown(ref, "tasks", taskBreakdown, "taskId", generationId),
        replaceMonthlyBreakdown(ref, "employmentActions", employmentActionBreakdown, "actionId", generationId),
    ]);
    const rootSnapshot = {
        ...fullSnapshot,
        generationId,
        breakdownStorage: "subcollections",
        detailCounts: {
            projects: projectBreakdown.length,
            employees: employeeBreakdown.length,
            tasks: taskBreakdown.length,
            employmentActions: employmentActionBreakdown.length,
        },
        // Small previews preserve backward compatibility without risking the
        // Firestore 1 MiB document limit.
        projectBreakdown: projectBreakdown.slice(0, 25),
        employeeBreakdown: employeeBreakdown.slice(0, 25),
        taskBreakdown: taskBreakdown.slice(0, 40),
        employmentActionBreakdown: employmentActionBreakdown.slice(0, 25),
    };
    await ref.set(rootSnapshot);
}
exports.rebuildMonthlyAnalytics = (0, https_1.onCall)({ region: analyticsRegion, timeoutSeconds: 300, memory: "512MiB" }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in before rebuilding analytics.");
    const companyId = cleanString(request.data?.companyId);
    const monthId = validateMonthId(cleanString(request.data?.monthId) || analyticsMonthId(new Date()));
    if (!companyId)
        throw new https_1.HttpsError("invalid-argument", "companyId is required.");
    const actor = await authenticatedCompanyMember(companyId, uid);
    if (!roleAllowsAnalyticsRebuild(actor.role)) {
        throw new https_1.HttpsError("permission-denied", "Your role cannot rebuild monthly analytics.");
    }
    const force = request.data?.force === true && ["superadmin", "admin"].includes(normalizedRole(actor.role));
    await saveMonthlyAnalyticsSnapshot(companyId, monthId, false, force);
    return { success: true, companyId, monthId };
});
async function allCompanyIds() {
    const snap = await admin.firestore().collection("companies").get();
    return snap.docs
        .filter((doc) => cleanString(doc.data().status).toLowerCase() !== "inactive")
        .map((doc) => doc.id);
}
exports.refreshCurrentMonthlyAnalytics = (0, scheduler_1.onSchedule)({
    schedule: "every 1 hours",
    timeZone: analyticsTimeZone,
    region: analyticsRegion,
    timeoutSeconds: 540,
    memory: "512MiB",
}, async () => {
    const monthId = analyticsMonthId(new Date());
    const companyIds = await allCompanyIds();
    for (const companyId of companyIds) {
        try {
            await saveMonthlyAnalyticsSnapshot(companyId, monthId, false, false);
        }
        catch (error) {
            console.error(`Monthly analytics refresh failed for ${companyId}/${monthId}.`, error);
        }
    }
});
exports.finalizePreviousMonthlyAnalytics = (0, scheduler_1.onSchedule)({
    schedule: "5 0 1 * *",
    timeZone: analyticsTimeZone,
    region: analyticsRegion,
    timeoutSeconds: 540,
    memory: "512MiB",
}, async () => {
    const monthId = previousMonthId(new Date());
    const companyIds = await allCompanyIds();
    for (const companyId of companyIds) {
        try {
            await saveMonthlyAnalyticsSnapshot(companyId, monthId, true, true);
        }
        catch (error) {
            console.error(`Monthly analytics finalization failed for ${companyId}/${monthId}.`, error);
        }
    }
});
//# sourceMappingURL=index.js.map