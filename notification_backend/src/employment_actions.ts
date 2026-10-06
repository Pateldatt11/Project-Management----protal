import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { adminDb } from "./firebase";
import { normalizedRole, stringValue } from "./values";

const TERMINAL_STATUSES = new Set(["approved", "rejected", "cancelled", "error"]);

function timestampValue(value: unknown): Timestamp | null {
  if (value instanceof Timestamp) return value;
  if (value instanceof Date) return Timestamp.fromDate(value);
  if (typeof value === "string") {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) return Timestamp.fromDate(parsed);
  }
  if (value && typeof value === "object") {
    const seconds = Number((value as Record<string, unknown>).seconds);
    if (Number.isFinite(seconds)) return new Timestamp(seconds, 0);
  }
  return null;
}

function cleanOptional(value: unknown): string | null {
  const clean = stringValue(value).trim();
  return clean.length === 0 ? null : clean;
}

function memberChanges(action: Record<string, unknown>, actionId: string): Record<string, unknown> {
  const updates: Record<string, unknown> = {
    lastCareerActionId: actionId,
    lastCareerActionAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  const proposedRole = cleanOptional(action.proposedRole);
  const proposedDepartment = cleanOptional(action.proposedDepartment);
  const proposedJobTitle = cleanOptional(action.proposedJobTitle);
  const proposedGrade = cleanOptional(action.proposedGrade);
  const proposedSalaryBand = cleanOptional(action.proposedSalaryBand);
  const proposedReportingManagerId = cleanOptional(action.proposedReportingManagerId);

  if (proposedRole && normalizedRole(proposedRole) !== "superadmin") updates.role = proposedRole;
  if (proposedDepartment) updates.department = proposedDepartment;
  if (proposedJobTitle) updates.jobTitle = proposedJobTitle;
  if (proposedGrade) updates.grade = proposedGrade;
  if (proposedSalaryBand) updates.salaryBand = proposedSalaryBand;
  if (proposedReportingManagerId) updates.reportingManagerId = proposedReportingManagerId;

  return updates;
}

export type EmploymentActionCommand = "review" | "approve" | "reject";

export async function processEmploymentAction(input: {
  companyId: string;
  actionId: string;
  actorUid: string;
  command: EmploymentActionCommand;
  comments?: string;
}): Promise<Record<string, unknown>> {
  const actionRef = adminDb.doc(`companies/${input.companyId}/employmentActions/${input.actionId}`);
  const auditRef = adminDb.collection(`companies/${input.companyId}/auditLogs`).doc();
  const activityRef = adminDb.collection(`companies/${input.companyId}/activityLogs`).doc();
  const now = Timestamp.now();

  return adminDb.runTransaction(async (transaction) => {
    const actionSnapshot = await transaction.get(actionRef);
    if (!actionSnapshot.exists) throw new Error("employment_action_not_found");
    const action = actionSnapshot.data() ?? {};
    const currentStatus = stringValue(action.status).trim().toLowerCase();
    if (TERMINAL_STATUSES.has(currentStatus)) throw new Error("employment_action_already_closed");

    const employeeId = stringValue(action.employeeId).trim();
    if (!employeeId) throw new Error("employment_action_employee_missing");
    const memberRef = adminDb.doc(`companies/${input.companyId}/members/${employeeId}`);
    const memberSnapshot = await transaction.get(memberRef);
    if (!memberSnapshot.exists) throw new Error("employment_action_member_not_found");

    const comments = (input.comments ?? "").trim();
    let nextStatus: string;
    const actionUpdate: Record<string, unknown> = {
      updatedAt: FieldValue.serverTimestamp(),
      lastProcessedBy: input.actorUid,
      lastProcessedAt: FieldValue.serverTimestamp(),
    };

    if (input.command === "review") {
      nextStatus = "underReview";
      actionUpdate.reviewedBy = input.actorUid;
      actionUpdate.reviewedAt = FieldValue.serverTimestamp();
      if (comments) actionUpdate.hrComments = comments;
    } else if (input.command === "reject") {
      if (comments.length < 4) throw new Error("rejection_reason_required");
      nextStatus = "rejected";
      actionUpdate.rejectedBy = input.actorUid;
      actionUpdate.rejectedAt = FieldValue.serverTimestamp();
      actionUpdate.hrComments = comments;
    } else {
      nextStatus = "approved";
      actionUpdate.approvedBy = input.actorUid;
      actionUpdate.approvedAt = FieldValue.serverTimestamp();
      if (comments) actionUpdate.hrComments = comments;

      const changes = memberChanges(action, input.actionId);
      transaction.set(memberRef, changes, { merge: true });
      const historyRef = memberRef.collection("employmentHistory").doc(input.actionId);
      transaction.set(historyRef, {
        ...action,
        actionId: input.actionId,
        companyId: input.companyId,
        employeeId,
        status: nextStatus,
        appliedChanges: changes,
        effectiveDate: timestampValue(action.effectiveDate) ?? now,
        processedBy: input.actorUid,
        processedAt: FieldValue.serverTimestamp(),
        createdAt: action.createdAt ?? FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    actionUpdate.status = nextStatus;
    transaction.set(actionRef, actionUpdate, { merge: true });

    transaction.set(auditRef, {
      auditLogId: auditRef.id,
      companyId: input.companyId,
      actorId: input.actorUid,
      action: `employmentAction.${input.command}`,
      entityType: "employmentAction",
      entityId: input.actionId,
      before: { status: currentStatus },
      after: { status: nextStatus, comments },
      createdAt: FieldValue.serverTimestamp(),
    });

    transaction.set(activityRef, {
      activityLogId: activityRef.id,
      companyId: input.companyId,
      title: `Employment action ${nextStatus}`,
      description: `${stringValue(action.employeeName) || employeeId} career action is ${nextStatus}.`,
      entityType: "employmentAction",
      entityId: input.actionId,
      actorId: input.actorUid,
      createdAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      actionId: input.actionId,
      employeeId,
      status: nextStatus,
    };
  });
}
