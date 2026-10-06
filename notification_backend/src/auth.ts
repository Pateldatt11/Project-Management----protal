import { adminAuth, adminDb } from "./firebase";
import { normalizedRole, stringValue } from "./values";

const NOTIFICATION_ADMIN_ROLES = new Set(["superadmin", "admin", "projectmanager", "teamlead", "itadmin"]);
const APPRAISAL_REVIEW_ROLES = new Set(["superadmin", "admin", "hrmanager"]);
const REPORT_GENERATOR_ROLES = new Set(["superadmin", "admin", "projectmanager", "hrmanager"]);

type AuthorizationResult = {
  uid: string;
  companyId: string;
  role: string;
};

async function authorizeRoles(
  authorization: string | undefined,
  companyIdInput: unknown,
  roles: Set<string>,
  errorCode: string,
): Promise<AuthorizationResult> {
  if (!authorization?.startsWith("Bearer ")) throw new Error("missing_bearer_token");
  const companyId = stringValue(companyIdInput);
  if (!companyId) throw new Error("missing_company_id");

  const decoded = await adminAuth.verifyIdToken(authorization.slice("Bearer ".length), true);
  const member = await adminDb.doc(`companies/${companyId}/members/${decoded.uid}`).get();
  const role = normalizedRole(member.data()?.role ?? decoded.role);
  if (!member.exists || !roles.has(role)) throw new Error(errorCode);
  return { uid: decoded.uid, companyId, role };
}

export async function authorizeAdmin(authorization: string | undefined, companyIdInput: unknown): Promise<AuthorizationResult> {
  return authorizeRoles(authorization, companyIdInput, NOTIFICATION_ADMIN_ROLES, "admin_permission_required");
}

export async function authorizeAppraisalReviewer(authorization: string | undefined, companyIdInput: unknown): Promise<AuthorizationResult> {
  return authorizeRoles(authorization, companyIdInput, APPRAISAL_REVIEW_ROLES, "appraisal_review_permission_required");
}

export async function authorizeReportGenerator(authorization: string | undefined, companyIdInput: unknown): Promise<AuthorizationResult> {
  return authorizeRoles(authorization, companyIdInput, REPORT_GENERATOR_ROLES, "report_generation_permission_required");
}

export async function authorizeMember(authorization: string | undefined, companyIdInput: unknown): Promise<AuthorizationResult> {
  if (!authorization?.startsWith("Bearer ")) throw new Error("missing_bearer_token");
  const companyId = stringValue(companyIdInput);
  if (!companyId) throw new Error("missing_company_id");
  const decoded = await adminAuth.verifyIdToken(authorization.slice("Bearer ".length), true);
  const member = await adminDb.doc(`companies/${companyId}/members/${decoded.uid}`).get();
  if (!member.exists) throw new Error("company_membership_required");
  return { uid: decoded.uid, companyId, role: normalizedRole(member.data()?.role) };
}
