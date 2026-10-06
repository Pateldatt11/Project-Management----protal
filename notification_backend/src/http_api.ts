import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { URL } from "node:url";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { config } from "./config";
import { authorizeAdmin, authorizeAppraisalReviewer, authorizeMember, authorizeReportGenerator } from "./auth";
import { adminDb, firebaseCredentialsConfigured } from "./firebase";
import { log } from "./log";
import { processNotificationDocument } from "./notification_sender";
import { processEmploymentAction, type EmploymentActionCommand } from "./employment_actions";
import { buildMonthlyAnalytics } from "./monthly_analytics";
import { boolValue, stringValue } from "./values";

const rateBuckets = new Map<string, { minute: number; count: number }>();

function clientIp(request: IncomingMessage): string {
  const forwarded = request.headers["x-forwarded-for"];
  if (typeof forwarded === "string") return forwarded.split(",")[0].trim();
  return request.socket.remoteAddress ?? "unknown";
}

function allowedByRateLimit(request: IncomingMessage): boolean {
  const key = clientIp(request);
  const minute = Math.floor(Date.now() / 60_000);
  const current = rateBuckets.get(key);
  if (!current || current.minute !== minute) {
    rateBuckets.set(key, { minute, count: 1 });
    return true;
  }
  current.count += 1;
  return current.count <= config.apiRateLimitPerMinute;
}

function setCors(request: IncomingMessage, response: ServerResponse): boolean {
  const origin = typeof request.headers.origin === "string" ? request.headers.origin : "";
  if (origin && (config.adminWebOrigins.size === 0 || config.adminWebOrigins.has(origin))) {
    response.setHeader("Access-Control-Allow-Origin", origin);
    response.setHeader("Vary", "Origin");
  }
  response.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type, Idempotency-Key");
  response.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  return !origin || config.adminWebOrigins.size === 0 || config.adminWebOrigins.has(origin);
}

function json(response: ServerResponse, status: number, body: unknown): void {
  response.statusCode = status;
  response.setHeader("Content-Type", "application/json; charset=utf-8");
  response.setHeader("Cache-Control", "no-store");
  response.end(JSON.stringify(body));
}

async function readJson(request: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > 256 * 1024) throw new Error("request_body_too_large");
    chunks.push(buffer);
  }
  if (chunks.length === 0) return {};
  const parsed: unknown = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("json_object_required");
  return parsed as Record<string, unknown>;
}

function routeId(pathname: string, suffix: string): string | null {
  const prefix = "/api/v1/notifications/";
  if (!pathname.startsWith(prefix) || !pathname.endsWith(suffix)) return null;
  const id = pathname.slice(prefix.length, pathname.length - suffix.length).replace(/^\/+|\/+$/g, "");
  return id || null;
}

async function findRootNotification(companyId: string, notificationId: string) {
  return adminDb.doc(`companies/${companyId}/notifications/${notificationId}`);
}

export function buildHttpServer() {
  return createServer(async (request, response) => {
    const requestId = crypto.randomUUID();
    response.setHeader("X-Request-Id", requestId);
    response.setHeader("X-Content-Type-Options", "nosniff");
    response.setHeader("X-Frame-Options", "DENY");
    response.setHeader("Referrer-Policy", "no-referrer");

    if (!setCors(request, response)) {
      json(response, 403, { error: "origin_not_allowed", requestId });
      return;
    }
    if (request.method === "OPTIONS") {
      response.statusCode = 204;
      response.end();
      return;
    }
    if (!allowedByRateLimit(request)) {
      json(response, 429, { error: "rate_limit_exceeded", requestId });
      return;
    }

    const url = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);
    try {
      if (request.method === "GET" && url.pathname === "/health") {
        const memory = process.memoryUsage();
        json(response, 200, {
          status: "ok",
          service: "projectos-notification-backend",
          projectId: config.firebaseProjectId,
          instanceId: config.instanceId,
          uptimeSeconds: Math.floor(process.uptime()),
          processId: process.pid,
          nodeVersion: process.version,
          memoryMb: {
            rss: Math.round(memory.rss / 1024 / 1024),
            heapUsed: Math.round(memory.heapUsed / 1024 / 1024),
            heapTotal: Math.round(memory.heapTotal / 1024 / 1024),
          },
          timestamp: new Date().toISOString(),
        });
        return;
      }

      if (request.method === "GET" && url.pathname === "/ready") {
        if (!firebaseCredentialsConfigured) {
          json(response, 503, {
            status: "not_ready",
            service: "projectos-notification-backend",
            firebase: "credential_not_configured",
            projectId: config.firebaseProjectId,
            instanceId: config.instanceId,
            timestamp: new Date().toISOString(),
          });
          return;
        }
        await adminDb.collection("companies").limit(1).get();
        json(response, 200, {
          status: "ready",
          service: "projectos-notification-backend",
          firebase: "connected",
          projectId: config.firebaseProjectId,
          instanceId: config.instanceId,
          timestamp: new Date().toISOString(),
        });
        return;
      }

      const appraisalMatch = /^\/api\/v1\/appraisals\/([^/]+)\/process$/.exec(url.pathname);
      if (request.method === "POST" && appraisalMatch) {
        const body = await readJson(request);
        const auth = await authorizeAppraisalReviewer(request.headers.authorization, body.companyId);
        const command = stringValue(body.command).toLowerCase() as EmploymentActionCommand;
        if (!new Set(["review", "approve", "reject"]).has(command)) {
          json(response, 400, { error: "invalid_employment_action_command", requestId });
          return;
        }
        const result = await processEmploymentAction({
          companyId: auth.companyId,
          actionId: decodeURIComponent(appraisalMatch[1]),
          actorUid: auth.uid,
          command,
          comments: stringValue(body.comments),
        });
        json(response, 200, { ...result, requestId });
        return;
      }

      if (request.method === "POST" && url.pathname === "/api/v1/reports/monthly/rebuild") {
        const body = await readJson(request);
        const auth = await authorizeReportGenerator(request.headers.authorization, body.companyId);
        const snapshot = await buildMonthlyAnalytics({
          companyId: auth.companyId,
          monthId: stringValue(body.monthId),
          projectId: stringValue(body.projectId) || null,
          generatedBy: auth.uid,
        });
        json(response, 200, { success: true, snapshot, requestId });
        return;
      }

      const resendId = routeId(url.pathname, "/resend");
      if (request.method === "POST" && resendId) {
        const body = await readJson(request);
        const auth = await authorizeAdmin(request.headers.authorization, body.companyId);
        const ref = await findRootNotification(auth.companyId, resendId);
        const snapshot = await ref.get();
        if (!snapshot.exists) {
          json(response, 404, { error: "notification_not_found", requestId });
          return;
        }
        const resetAttempts = boolValue(body.resetAttempts, false);
        await ref.set({
          deliveryProvider: "oracle_admin_sdk",
          queueScope: "company_root",
          activeQueue: true,
          pushStatus: "manual_resend_queued",
          deliveryStatus: "queued",
          responseStatus: "pending",
          nextAttemptAt: Timestamp.now(),
          adminAttentionRequired: false,
          ...(resetAttempts ? { attemptCount: 0 } : {}),
          updatedAt: FieldValue.serverTimestamp(),
          manualResendBy: auth.uid,
        }, { merge: true });
        await adminDb.doc(`companies/${auth.companyId}/notificationLogs/${resendId}`).set({
          adminAttentionRequired: false,
          status: "manual_resend_queued",
          manualResendBy: auth.uid,
          manualResendAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
        void processNotificationDocument(ref);
        json(response, 202, { success: true, notificationId: resendId, requestId });
        return;
      }

      const responseId = routeId(url.pathname, "/respond");
      if (request.method === "POST" && responseId) {
        const body = await readJson(request);
        const auth = await authorizeMember(request.headers.authorization, body.companyId);
        const status = stringValue(body.status).toLowerCase();
        if (!new Set(["accepted", "declined", "muted", "read"]).has(status)) {
          json(response, 400, { error: "invalid_response_status", requestId });
          return;
        }
        const rootRef = await findRootNotification(auth.companyId, responseId);
        const snapshot = await rootRef.get();
        const data = snapshot.data();
        if (!snapshot.exists || stringValue(data?.recipientId ?? data?.targetUid) !== auth.uid) {
          json(response, 404, { error: "notification_not_found", requestId });
          return;
        }
        const memberRef = adminDb.doc(`companies/${auth.companyId}/members/${auth.uid}/notifications/${responseId}`);
        const update = {
          responseStatus: status,
          accepted: status === "accepted",
          read: true,
          isRead: true,
          pushStatus: `employee_${status}`,
          nextAttemptAt: FieldValue.delete(),
          leaseOwner: FieldValue.delete(),
          leaseUntil: FieldValue.delete(),
          respondedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        };
        const batch = adminDb.batch();
        batch.set(rootRef, update, { merge: true });
        batch.set(memberRef, update, { merge: true });
        await batch.commit();
        json(response, 200, { success: true, notificationId: responseId, status, requestId });
        return;
      }

      json(response, 404, { error: "not_found", requestId });
    } catch (error) {
      const message = String(error instanceof Error ? error.message : error);
      const status = message.includes("permission") ? 403 : message.includes("token") || message.includes("membership") ? 401 : 400;
      log.warn("HTTP request failed.", { requestId, path: url.pathname, error: message });
      json(response, status, { error: message, requestId });
    }
  });
}
