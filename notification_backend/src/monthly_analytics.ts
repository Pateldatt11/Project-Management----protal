import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { adminDb } from "./firebase";
import { stringValue } from "./values";


type DataMap = Record<string, unknown>;

function withId(data: DataMap, key: string, fallback: string): DataMap {
  return { ...data, [key]: stringValue(data[key]) || fallback };
}

function dateValue(value: unknown): Date | null {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "string") {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (value && typeof value === "object") {
    const seconds = Number((value as Record<string, unknown>).seconds);
    if (Number.isFinite(seconds)) return new Date(seconds * 1000);
  }
  return null;
}

function numberValue(value: unknown, fallback = 0): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function listValue(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => String(item).trim()).filter(Boolean);
}

function monthRange(monthId: string): { start: Date; end: Date } {
  const match = /^(\d{4})-(\d{2})$/.exec(monthId);
  if (!match) throw new Error("invalid_month_id");
  const year = Number(match[1]);
  const month = Number(match[2]);
  if (month < 1 || month > 12) throw new Error("invalid_month_id");
  return {
    start: new Date(Date.UTC(year, month - 1, 1)),
    end: new Date(Date.UTC(year, month, 1)),
  };
}

function lifecycleOverlaps(item: Record<string, unknown>, start: Date, end: Date): boolean {
  const created = dateValue(item.createdAt);
  const updated = dateValue(item.updatedAt);
  const completed = dateValue(item.completedAt);
  const startDate = dateValue(item.startDate) ?? created;
  const dueDate = dateValue(item.dueDate);
  const touchDates = [created, updated, completed].filter((value): value is Date => value !== null);
  if (touchDates.some((date) => date >= start && date < end)) return true;
  const lifecycleStart = startDate ?? start;
  const lifecycleEnd = completed ?? dueDate ?? end;
  return lifecycleStart < end && lifecycleEnd >= start;
}

function isCompleted(task: Record<string, unknown>): boolean {
  return stringValue(task.status).toLowerCase() === "completed";
}

function isOverdue(task: Record<string, unknown>, cutoff: Date): boolean {
  const due = dateValue(task.dueDate);
  return !isCompleted(task) && due !== null && due < cutoff;
}

export async function buildMonthlyAnalytics(input: {
  companyId: string;
  monthId: string;
  projectId?: string | null;
  generatedBy: string;
}): Promise<Record<string, unknown>> {
  const { start, end } = monthRange(input.monthId);
  const cutoff = new Date(Math.min(Date.now(), end.getTime() - 1));
  const companyPath = `companies/${input.companyId}`;

  const [projectSnapshot, taskSnapshot, memberSnapshot, actionSnapshot] = await Promise.all([
    adminDb.collection(`${companyPath}/projects`).get(),
    adminDb.collection(`${companyPath}/tasks`).get(),
    adminDb.collection(`${companyPath}/members`).get(),
    adminDb.collection(`${companyPath}/employmentActions`).limit(500).get(),
  ]);

  const requestedProjectId = (input.projectId ?? "").trim();
  const projects = projectSnapshot.docs
    .map((doc): DataMap => withId(doc.data() as DataMap, "projectId", doc.id))
    .filter((project) => !requestedProjectId || stringValue(project.projectId) === requestedProjectId);
  const projectIds = new Set(projects.map((project) => stringValue(project.projectId)));

  const tasks = taskSnapshot.docs
    .map((doc): DataMap => withId(doc.data() as DataMap, "taskId", doc.id))
    .filter((task) => (!requestedProjectId || projectIds.has(stringValue(task.projectId))) && lifecycleOverlaps(task, start, end));

  const relevantMemberIds = new Set<string>();
  for (const task of tasks) for (const uid of listValue(task.assignedToIds)) relevantMemberIds.add(uid);
  for (const project of projects) for (const uid of listValue(project.managerIds)) relevantMemberIds.add(uid);

  const members = memberSnapshot.docs
    .map((doc): DataMap => withId(doc.data() as DataMap, "uid", doc.id))
    .filter((member) => !requestedProjectId || relevantMemberIds.has(stringValue(member.uid)) || listValue(member.projectIds).includes(requestedProjectId));

  const actions = actionSnapshot.docs
    .map((doc): DataMap => withId(doc.data() as DataMap, "actionId", doc.id))
    .filter((action) => {
      const created = dateValue(action.createdAt) ?? dateValue(action.updatedAt);
      return created !== null && created >= start && created < end && (!requestedProjectId || relevantMemberIds.has(stringValue(action.employeeId)));
    });

  const completedTasks = tasks.filter(isCompleted).length;
  const overdueTasks = tasks.filter((task) => isOverdue(task, cutoff)).length;
  const estimatedHours = tasks.reduce((sum, task) => sum + numberValue(task.estimatedHours), 0);
  const loggedHours = tasks.reduce((sum, task) => sum + numberValue(task.loggedHours), 0);
  const appraisalScores = members.map((member) => numberValue(member.appraisalScore)).filter((score) => score > 0);
  const appraisalAverage = appraisalScores.length === 0 ? 0 : Math.round(appraisalScores.reduce((a, b) => a + b, 0) / appraisalScores.length);

  const statusDistribution: Record<string, number> = {};
  const priorityDistribution: Record<string, number> = {};
  for (const task of tasks) {
    const status = stringValue(task.status) || "backlog";
    const priority = stringValue(task.priority) || "medium";
    statusDistribution[status] = (statusDistribution[status] ?? 0) + 1;
    priorityDistribution[priority] = (priorityDistribution[priority] ?? 0) + 1;
  }

  const projectBreakdown = projects.map((project) => {
    const id = stringValue(project.projectId);
    const projectTasks = tasks.filter((task) => stringValue(task.projectId) === id);
    const completed = projectTasks.filter(isCompleted).length;
    return {
      projectId: id,
      name: stringValue(project.name) || "Untitled project",
      status: stringValue(project.status) || "planning",
      tasks: projectTasks.length,
      completed,
      overdue: projectTasks.filter((task) => isOverdue(task, cutoff)).length,
      completionRate: projectTasks.length === 0 ? numberValue(project.progress) : Math.round((completed * 100) / projectTasks.length),
      estimatedHours: projectTasks.reduce((sum, task) => sum + numberValue(task.estimatedHours), 0),
      loggedHours: projectTasks.reduce((sum, task) => sum + numberValue(task.loggedHours), 0),
    };
  });

  const employeeBreakdown = members.map((member) => {
    const uid = stringValue(member.uid);
    const assigned = tasks.filter((task) => listValue(task.assignedToIds).includes(uid));
    const completed = assigned.filter(isCompleted).length;
    return {
      uid,
      name: stringValue(member.displayName) || stringValue(member.email) || "Employee",
      role: stringValue(member.role) || "employee",
      department: stringValue(member.department),
      assigned: assigned.length,
      completed,
      overdue: assigned.filter((task) => isOverdue(task, cutoff)).length,
      completionRate: assigned.length === 0 ? 0 : Math.round((completed * 100) / assigned.length),
      loggedHours: assigned.reduce((sum, task) => sum + numberValue(task.loggedHours), 0),
      appraisalScore: numberValue(member.appraisalScore),
      appraisalStatus: stringValue(member.appraisalStatus) || "notReviewed",
      appraisalPeriod: stringValue(member.appraisalPeriod),
    };
  });

  const taskBreakdown = tasks.map((task) => ({
    taskId: stringValue(task.taskId),
    projectId: stringValue(task.projectId),
    title: stringValue(task.title) || "Untitled task",
    status: stringValue(task.status) || "backlog",
    priority: stringValue(task.priority) || "medium",
    assignedToIds: listValue(task.assignedToIds),
    dueDate: dateValue(task.dueDate)?.toISOString() ?? null,
    completedAt: dateValue(task.completedAt)?.toISOString() ?? null,
    estimatedHours: numberValue(task.estimatedHours),
    loggedHours: numberValue(task.loggedHours),
    overdue: isOverdue(task, cutoff),
  }));

  const generationId = `oracle_${Date.now()}`;
  const metrics = {
    projectCount: projects.length,
    activeProjectCount: projects.filter((project) => !["completed", "cancelled"].includes(stringValue(project.status).toLowerCase())).length,
    projectsDelayed: projectBreakdown.filter((project) => numberValue(project.overdue) > 0).length,
    taskCount: tasks.length,
    tasksCompleted: completedTasks,
    tasksOverdue: overdueTasks,
    completionRate: tasks.length === 0 ? 0 : Math.round((completedTasks * 100) / tasks.length),
    estimatedHours,
    loggedHours,
    memberCount: members.length,
    appraisalCount: appraisalScores.length,
    appraisalAverage,
    employmentActionCount: actions.length,
    statusDistribution,
    priorityDistribution,
    reportScope: requestedProjectId ? "project" : "all",
    scopeProjectId: requestedProjectId || null,
    generatedLocallyCompatible: true,
  };

  const snapshot: Record<string, unknown> = {
    monthId: input.monthId,
    companyId: input.companyId,
    periodStart: start.toISOString(),
    periodEnd: end.toISOString(),
    generatedAt: new Date().toISOString(),
    reportingCutoff: cutoff.toISOString(),
    isFinalized: end.getTime() <= Date.now(),
    finalizedAt: end.getTime() <= Date.now() ? new Date().toISOString() : null,
    schemaVersion: 2,
    generationId,
    breakdownStorage: "inline",
    detailCounts: {
      projects: projectBreakdown.length,
      employees: employeeBreakdown.length,
      tasks: taskBreakdown.length,
      employmentActions: actions.length,
    },
    metrics,
    projectBreakdown,
    employeeBreakdown,
    taskBreakdown,
    employmentActionBreakdown: actions,
    generatedBy: input.generatedBy,
    generationSource: "oracle_admin_sdk_backend",
    updatedAt: FieldValue.serverTimestamp(),
  };

  await adminDb.doc(`${companyPath}/monthlyAnalytics/${input.monthId}`).set(snapshot, { merge: true });

  return {
    ...snapshot,
    updatedAt: new Date().toISOString(),
  };
}
