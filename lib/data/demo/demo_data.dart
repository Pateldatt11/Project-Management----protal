import '../../core/constants/app_constants.dart';
import '../../core/constants/app_enums.dart';
import '../models/activity_log.dart';
import '../models/audit_log.dart';
import '../models/file_attachment.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/company.dart';
import '../models/member.dart';
import '../models/portal_post_settings.dart';
import '../models/project.dart';
import '../models/report.dart';
import '../models/task_comment.dart';
import '../models/task.dart';
import '../models/team.dart';

class DemoData {
  static final portalPostSettings = PortalPostSettings(
    enabledRoleValues: PortalPostSettings.defaultEnabledRoleValues(),
    updatedBy: 'system',
    updatedAt: DateTime.now(),
  );

  static final company = Company(
    companyId: AppConstants.demoCompanyId,
    name: AppConstants.demoCompanyName,
    industry: 'Software Services',
    status: 'active',
    timezone: 'Asia/Kolkata',
  );

  static final demoUsers = <AppUser>[
    AppUser(uid: 'user_super', displayName: 'Sanjay Owner', email: 'super@acme.demo', role: UserRole.superAdmin, defaultCompanyId: AppConstants.demoCompanyId),
    AppUser(uid: 'user_admin', displayName: 'Darshan Admin', email: 'admin@acme.demo', role: UserRole.admin, defaultCompanyId: AppConstants.demoCompanyId),
    AppUser(uid: 'user_it', displayName: 'Meera IT Admin', email: 'it.admin@acme.demo', role: UserRole.itAdmin, defaultCompanyId: AppConstants.demoCompanyId),
    AppUser(uid: 'user_pm', displayName: 'Aarav Mehta', email: 'pm@acme.demo', role: UserRole.projectManager, defaultCompanyId: AppConstants.demoCompanyId),
    AppUser(uid: 'user_lead', displayName: 'Nisha Patel', email: 'tl@acme.demo', role: UserRole.teamLead, defaultCompanyId: AppConstants.demoCompanyId),
    AppUser(uid: 'user_dev1', displayName: 'Rohan Shah', email: 'developer@acme.demo', role: UserRole.developer, defaultCompanyId: AppConstants.demoCompanyId),
    AppUser(uid: 'user_qa', displayName: 'Isha QA', email: 'qa@acme.demo', role: UserRole.qaTester, defaultCompanyId: AppConstants.demoCompanyId),
    AppUser(uid: 'user_designer', displayName: 'Maya Designer', email: 'designer@acme.demo', role: UserRole.designer, defaultCompanyId: AppConstants.demoCompanyId),
    AppUser(uid: 'user_devops', displayName: 'Kabir DevOps', email: 'devops@acme.demo', role: UserRole.devOps, defaultCompanyId: AppConstants.demoCompanyId),
    AppUser(uid: 'user_hr', displayName: 'Priya HR', email: 'hr@acme.demo', role: UserRole.hrManager, defaultCompanyId: AppConstants.demoCompanyId),
    AppUser(uid: 'user_client', displayName: 'Client Viewer', email: 'client@acme.demo', role: UserRole.clientViewer, defaultCompanyId: AppConstants.demoCompanyId),
  ];

  static AppUser userFor(String uid) => demoUsers.firstWhere(
        (user) => user.uid == uid,
        orElse: () => demoUsers.firstWhere((user) => user.uid == AppConstants.demoUserId),
      );

  static final user = userFor(AppConstants.demoUserId);

  static final members = <Member>[
    const Member(uid: 'user_super', displayName: 'Sanjay Owner', email: 'super@acme.demo', role: UserRole.superAdmin, status: 'active', teamIds: ['team_admin'], projectIds: ['project_app', 'project_web', 'project_ops'], department: 'Executive', jobTitle: 'Workspace Owner', location: 'Surat', isOnline: true),
    const Member(uid: 'user_admin', displayName: 'Darshan Admin', email: 'admin@acme.demo', role: UserRole.admin, status: 'active', teamIds: ['team_admin'], projectIds: ['project_app', 'project_web', 'project_ops'], department: 'Administration', jobTitle: 'Company Admin', location: 'Surat', isOnline: true),
    const Member(uid: 'user_it', displayName: 'Meera IT Admin', email: 'it.admin@acme.demo', role: UserRole.itAdmin, status: 'active', teamIds: ['team_it'], projectIds: ['project_web', 'project_ops'], department: 'IT & Infrastructure', jobTitle: 'IT Administrator', location: 'Ahmedabad', isOnline: true),
    const Member(uid: 'user_pm', displayName: 'Aarav Mehta', email: 'pm@acme.demo', role: UserRole.projectManager, status: 'active', teamIds: ['team_product'], projectIds: ['project_app', 'project_web'], department: 'Delivery Management', jobTitle: 'Project Manager', location: 'Mumbai', isOnline: false),
    const Member(uid: 'user_lead', displayName: 'Nisha Patel', email: 'tl@acme.demo', role: UserRole.teamLead, status: 'active', teamIds: ['team_frontend'], projectIds: ['project_app'], department: 'Delivery Management', jobTitle: 'Frontend Team Lead', location: 'Vadodara', isOnline: true),
    const Member(uid: 'user_dev1', displayName: 'Rohan Shah', email: 'developer@acme.demo', role: UserRole.developer, status: 'active', teamIds: ['team_frontend'], projectIds: ['project_app'], department: 'Engineering', jobTitle: 'Flutter Developer', location: 'Remote', isOnline: true),
    const Member(uid: 'user_dev2', displayName: 'Kavya Rao', email: 'backend@acme.demo', role: UserRole.developer, status: 'active', teamIds: ['team_backend'], projectIds: ['project_web'], department: 'Engineering', jobTitle: 'Backend Developer', location: 'Bengaluru', isOnline: false),
    const Member(uid: 'user_qa', displayName: 'Isha QA', email: 'qa@acme.demo', role: UserRole.qaTester, status: 'active', teamIds: ['team_quality'], projectIds: ['project_app', 'project_web'], department: 'Quality Assurance', jobTitle: 'QA Engineer', location: 'Pune', isOnline: true),
    const Member(uid: 'user_designer', displayName: 'Maya Designer', email: 'designer@acme.demo', role: UserRole.designer, status: 'active', teamIds: ['team_product'], projectIds: ['project_app'], department: 'Product Design', jobTitle: 'UI/UX Designer', location: 'Remote', isOnline: false),
    const Member(uid: 'user_devops', displayName: 'Kabir DevOps', email: 'devops@acme.demo', role: UserRole.devOps, status: 'active', teamIds: ['team_it'], projectIds: ['project_web', 'project_ops'], department: 'IT & Infrastructure', jobTitle: 'DevOps Engineer', location: 'Hyderabad', isOnline: true),
    const Member(uid: 'user_hr', displayName: 'Priya HR', email: 'hr@acme.demo', role: UserRole.hrManager, status: 'active', teamIds: ['team_people'], projectIds: ['project_ops'], department: 'People Operations', jobTitle: 'HR Manager', location: 'Surat', isOnline: false),
    const Member(uid: 'user_client', displayName: 'Client Viewer', email: 'client@acme.demo', role: UserRole.clientViewer, status: 'active', teamIds: [], projectIds: ['project_app'], department: 'External Stakeholder', jobTitle: 'Client Reviewer', location: 'External', isOnline: false),
  ];

  static final teams = <Team>[
    const Team(teamId: 'team_admin', name: 'Admin & Governance', leadId: 'user_admin', memberIds: ['user_super', 'user_admin'], activeProjectIds: ['project_ops']),
    const Team(teamId: 'team_it', name: 'IT & Infrastructure', leadId: 'user_it', memberIds: ['user_it', 'user_devops'], activeProjectIds: ['project_web', 'project_ops']),
    const Team(teamId: 'team_frontend', name: 'Frontend Team', leadId: 'user_lead', memberIds: ['user_lead', 'user_dev1', 'user_designer'], activeProjectIds: ['project_app']),
    const Team(teamId: 'team_backend', name: 'Backend Team', leadId: 'user_pm', memberIds: ['user_dev2', 'user_devops'], activeProjectIds: ['project_web']),
    const Team(teamId: 'team_quality', name: 'QA Team', leadId: 'user_qa', memberIds: ['user_qa'], activeProjectIds: ['project_app', 'project_web']),
    const Team(teamId: 'team_product', name: 'Product Team', leadId: 'user_pm', memberIds: ['user_pm', 'user_designer'], activeProjectIds: ['project_app', 'project_web']),
    const Team(teamId: 'team_people', name: 'People Operations', leadId: 'user_hr', memberIds: ['user_hr'], activeProjectIds: ['project_ops']),
  ];

  static final projects = <Project>[
    Project(
      projectId: 'project_app',
      companyId: AppConstants.demoCompanyId,
      name: 'Mobile App Redesign',
      description: 'Enterprise mobile app redesign with dashboard, Kanban, and reports.',
      status: ProjectStatus.active,
      priority: TaskPriority.high,
      startDate: DateTime.now().subtract(const Duration(days: 24)),
      dueDate: DateTime.now().add(const Duration(days: 42)),
      progress: 55,
      totalTasks: 20,
      completedTasks: 11,
      managerIds: ['user_pm'],
      teamIds: ['team_frontend', 'team_product'],
      budget: 500000,
    ),
    Project(
      projectId: 'project_web',
      companyId: AppConstants.demoCompanyId,
      name: 'Client Portal Launch',
      description: 'Flutter web portal with file upload, audit logs, and live notifications.',
      status: ProjectStatus.review,
      priority: TaskPriority.critical,
      startDate: DateTime.now().subtract(const Duration(days: 60)),
      dueDate: DateTime.now().add(const Duration(days: 12)),
      progress: 78,
      totalTasks: 18,
      completedTasks: 14,
      managerIds: ['user_pm'],
      teamIds: ['team_backend', 'team_product'],
      budget: 750000,
    ),
    Project(
      projectId: 'project_ops',
      companyId: AppConstants.demoCompanyId,
      name: 'Internal Ops Automation',
      description: 'Automate monthly reports and team productivity tracking.',
      status: ProjectStatus.planning,
      priority: TaskPriority.medium,
      startDate: DateTime.now().add(const Duration(days: 5)),
      dueDate: DateTime.now().add(const Duration(days: 85)),
      progress: 10,
      totalTasks: 8,
      completedTasks: 1,
      managerIds: ['user_admin'],
      teamIds: ['team_product'],
      budget: 250000,
    ),
  ];

  static final tasks = <ProjectTask>[
    ProjectTask(taskId: 'task_1', companyId: AppConstants.demoCompanyId, projectId: 'project_app', teamId: 'team_frontend', title: 'Create responsive dashboard shell', description: 'Sidebar, top bar, mobile drawer, and adaptive content area.', status: TaskStatus.completed, priority: TaskPriority.high, assignedToIds: ['user_dev1'], createdBy: 'user_pm', dueDate: DateTime.now().subtract(const Duration(days: 150)), kanbanRank: 'a001', commentsCount: 4),
    ProjectTask(taskId: 'task_2', companyId: AppConstants.demoCompanyId, projectId: 'project_app', teamId: 'team_product', title: 'Design executive KPI cards', description: 'Professional KPI cards with live task completion metrics.', status: TaskStatus.completed, priority: TaskPriority.medium, assignedToIds: ['user_designer'], createdBy: 'user_pm', dueDate: DateTime.now().subtract(const Duration(days: 128)), kanbanRank: 'a002', commentsCount: 3),
    ProjectTask(taskId: 'task_3', companyId: AppConstants.demoCompanyId, projectId: 'project_web', teamId: 'team_backend', title: 'Configure company Firestore collections', description: 'Multi-tenant company, project, task, and member collections.', status: TaskStatus.completed, priority: TaskPriority.critical, assignedToIds: ['user_dev2'], createdBy: 'user_admin', dueDate: DateTime.now().subtract(const Duration(days: 103)), kanbanRank: 'a003', attachmentsCount: 1),
    ProjectTask(taskId: 'task_4', companyId: AppConstants.demoCompanyId, projectId: 'project_web', teamId: 'team_backend', title: 'Create Firebase security rule draft', description: 'Company membership based access, tasks, projects, audit logs.', status: TaskStatus.completed, priority: TaskPriority.critical, assignedToIds: ['user_dev2'], createdBy: 'user_admin', dueDate: DateTime.now().subtract(const Duration(days: 87)), kanbanRank: 'a004', attachmentsCount: 1),
    ProjectTask(taskId: 'task_5', companyId: AppConstants.demoCompanyId, projectId: 'project_app', teamId: 'team_product', title: 'Finalize dashboard KPI copy', description: 'Prepare exact enterprise labels and helper text.', status: TaskStatus.completed, priority: TaskPriority.medium, assignedToIds: ['user_pm'], createdBy: 'user_admin', dueDate: DateTime.now().subtract(const Duration(days: 63)), kanbanRank: 'a005'),
    ProjectTask(taskId: 'task_6', companyId: AppConstants.demoCompanyId, projectId: 'project_ops', teamId: 'team_people', title: 'Monthly report shell', description: 'Create the first report structure and filters.', status: TaskStatus.completed, priority: TaskPriority.medium, assignedToIds: ['user_hr'], createdBy: 'user_admin', dueDate: DateTime.now().subtract(const Duration(days: 48)), kanbanRank: 'a006'),
    ProjectTask(taskId: 'task_7', companyId: AppConstants.demoCompanyId, projectId: 'project_app', teamId: 'team_frontend', title: 'Build project details page', description: 'Project overview, progress, timeline, teams, and files.', status: TaskStatus.inProgress, priority: TaskPriority.high, assignedToIds: ['user_dev1'], createdBy: 'user_pm', dueDate: DateTime.now().add(const Duration(days: 3)), kanbanRank: 'a007', commentsCount: 2),
    ProjectTask(taskId: 'task_8', companyId: AppConstants.demoCompanyId, projectId: 'project_web', teamId: 'team_backend', title: 'Implement FCM token storage', description: 'Store device token per user and platform.', status: TaskStatus.todo, priority: TaskPriority.high, assignedToIds: ['user_dev2'], createdBy: 'user_pm', dueDate: DateTime.now().add(const Duration(days: 8)), kanbanRank: 'a008'),
    ProjectTask(taskId: 'task_9', companyId: AppConstants.demoCompanyId, projectId: 'project_ops', teamId: 'team_product', title: 'PDF and Excel report design', description: 'Create export design for PDF and spreadsheet reports.', status: TaskStatus.backlog, priority: TaskPriority.medium, assignedToIds: ['user_designer'], createdBy: 'user_admin', dueDate: DateTime.now().add(const Duration(days: 18)), kanbanRank: 'a009'),
    ProjectTask(taskId: 'task_10', companyId: AppConstants.demoCompanyId, projectId: 'project_app', teamId: 'team_frontend', title: 'Kanban drag and drop refinement', description: 'Improve card density, drop state, and live task status update.', status: TaskStatus.review, priority: TaskPriority.high, assignedToIds: ['user_lead'], createdBy: 'user_pm', dueDate: DateTime.now().add(const Duration(days: 2)), kanbanRank: 'a010'),
    ProjectTask(taskId: 'task_11', companyId: AppConstants.demoCompanyId, projectId: 'project_web', teamId: 'team_it', title: 'Audit log event writer', description: 'Generate audit logs when projects and tasks change.', status: TaskStatus.testing, priority: TaskPriority.critical, assignedToIds: ['user_devops'], createdBy: 'user_admin', dueDate: DateTime.now().add(const Duration(days: 1)), kanbanRank: 'a011'),
    ProjectTask(taskId: 'task_12', companyId: AppConstants.demoCompanyId, projectId: 'project_app', teamId: 'team_frontend', title: 'Responsive mobile dashboard', description: 'Make dashboard cards and charts clean on mobile widths.', status: TaskStatus.inProgress, priority: TaskPriority.high, assignedToIds: ['user_dev1'], createdBy: 'user_pm', dueDate: DateTime.now().add(const Duration(days: 6)), kanbanRank: 'a012'),
    ProjectTask(taskId: 'task_13', companyId: AppConstants.demoCompanyId, projectId: 'project_web', teamId: 'team_it', title: 'File metadata model', description: 'Store attachment metadata beside Firebase Storage uploads.', status: TaskStatus.review, priority: TaskPriority.medium, assignedToIds: ['user_it'], createdBy: 'user_pm', dueDate: DateTime.now().add(const Duration(days: 11)), kanbanRank: 'a013'),
    ProjectTask(taskId: 'task_14', companyId: AppConstants.demoCompanyId, projectId: 'project_ops', teamId: 'team_product', title: 'Role permission matrix screen', description: 'Create access-control screen for admin roles.', status: TaskStatus.todo, priority: TaskPriority.high, assignedToIds: ['user_admin'], createdBy: 'user_admin', dueDate: DateTime.now().add(const Duration(days: 21)), kanbanRank: 'a014'),
    ProjectTask(taskId: 'task_15', companyId: AppConstants.demoCompanyId, projectId: 'project_app', teamId: 'team_quality', title: 'Task completion analytics QA', description: 'Verify charts update when tasks move into Completed.', status: TaskStatus.testing, priority: TaskPriority.high, assignedToIds: ['user_qa'], createdBy: 'user_admin', dueDate: DateTime.now().add(const Duration(days: 5)), kanbanRank: 'a015'),
    ProjectTask(taskId: 'task_16', companyId: AppConstants.demoCompanyId, projectId: 'project_ops', teamId: 'team_product', title: 'Workload balancing rules', description: 'Define rules for overloaded employee warnings.', status: TaskStatus.backlog, priority: TaskPriority.medium, assignedToIds: ['user_lead'], createdBy: 'user_pm', dueDate: DateTime.now().add(const Duration(days: 30)), kanbanRank: 'a016'),
    ProjectTask(taskId: 'task_17', companyId: AppConstants.demoCompanyId, projectId: 'project_app', teamId: 'team_frontend', title: 'Chart card micro-interactions', description: 'Add polished loading, empty, and hover states for charts.', status: TaskStatus.todo, priority: TaskPriority.low, assignedToIds: ['user_dev1'], createdBy: 'user_pm', dueDate: DateTime.now().add(const Duration(days: 14)), kanbanRank: 'a017'),
    ProjectTask(taskId: 'task_18', companyId: AppConstants.demoCompanyId, projectId: 'project_web', teamId: 'team_it', title: 'Deadline reminder function plan', description: 'Plan scheduled reminder Cloud Function for overdue tasks.', status: TaskStatus.backlog, priority: TaskPriority.medium, assignedToIds: ['user_devops'], createdBy: 'user_admin', dueDate: DateTime.now().add(const Duration(days: 26)), kanbanRank: 'a018'),
  ];

  static final notifications = <AppNotification>[
    AppNotification(
      notificationId: 'notification_1',
      title: 'Task assigned to you',
      message: 'Build project details page has been assigned to you.',
      type: 'taskAssigned',
      recipientId: 'user_dev1',
      companyId: AppConstants.demoCompanyId,
      projectId: 'project_app',
      taskId: 'task_7',
      actorId: 'user_pm',
      createdAt: DateTime.now().subtract(const Duration(minutes: 18)),
    ),
    AppNotification(
      notificationId: 'notification_2',
      title: 'Deadline reminder',
      message: 'Firestore security rules testing is due tomorrow.',
      type: 'deadlineReminder',
      recipientId: 'user_devops',
      companyId: AppConstants.demoCompanyId,
      projectId: 'project_web',
      taskId: 'task_11',
      actorId: 'system',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    AppNotification(
      notificationId: 'notification_3',
      title: 'Task assigned to you',
      message: 'Role permission matrix screen has been assigned to you.',
      type: 'taskAssigned',
      recipientId: 'user_admin',
      companyId: AppConstants.demoCompanyId,
      projectId: 'project_ops',
      taskId: 'task_14',
      actorId: 'user_admin',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
  ];

  static final activity = <ActivityLog>[
    ActivityLog(activityLogId: 'activity_1', title: 'Task completed', description: 'Create responsive dashboard shell was completed.', actorId: 'user_dev1', targetType: 'task', targetId: 'task_1', createdAt: DateTime.now().subtract(const Duration(hours: 1))),
    ActivityLog(activityLogId: 'activity_2', title: 'Project updated', description: 'Client Portal Launch moved to Review.', actorId: 'user_pm', targetType: 'project', targetId: 'project_web', createdAt: DateTime.now().subtract(const Duration(hours: 5))),
    ActivityLog(activityLogId: 'activity_3', title: 'Comment added', description: 'A new review comment was added on dashboard KPI copy.', actorId: 'user_pm', targetType: 'task', targetId: 'task_3', createdAt: DateTime.now().subtract(const Duration(hours: 9))),
  ];

  static final reports = <ReportModel>[
    ReportModel(reportId: 'report_1', reportType: 'Monthly Company Report', period: 'Jun 2026', status: 'generated', createdAt: DateTime.now().subtract(const Duration(days: 2))),
    ReportModel(reportId: 'report_2', reportType: 'Employee Performance', period: 'Jun 2026', status: 'generated', createdAt: DateTime.now().subtract(const Duration(days: 4))),
    ReportModel(reportId: 'report_3', reportType: 'Team Productivity', period: 'May 2026', status: 'archived', createdAt: DateTime.now().subtract(const Duration(days: 25))),
  ];

  static final comments = <TaskComment>[
    TaskComment(commentId: 'comment_1', taskId: 'task_7', authorId: 'user_pm', message: 'Please keep the project details layout compact for web and mobile.', createdAt: DateTime.now().subtract(const Duration(hours: 4))),
    TaskComment(commentId: 'comment_2', taskId: 'task_10', authorId: 'user_lead', message: 'Kanban drop behavior is ready for QA.', createdAt: DateTime.now().subtract(const Duration(hours: 2))),
  ];

  static final attachments = <FileAttachment>[
    FileAttachment(
      attachmentId: 'attachment_1', 
      taskId: 'task_13', 
      projectId: 'project_web', 
      uploadedBy: 'user_dev2', 
      fileName: 'storage-metadata-plan.pdf', 
      fileType: 'application/pdf', 
      fileSize: 840000, 
      publicId: 'companies/company_001/projects/project_web/tasks/task_13/storage-metadata-plan', // <-- Updated to publicId
      secureUrl: '', // <-- Added secureUrl
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  static final auditLogs = <AuditLog>[
    AuditLog(auditLogId: 'audit_1', action: 'task.status.changed', actorId: 'user_dev1', targetType: 'task', targetId: 'task_1', createdAt: DateTime.now().subtract(const Duration(hours: 1)), before: {'status': 'testing'}, after: {'status': 'completed'}),
    AuditLog(auditLogId: 'audit_2', action: 'project.status.changed', actorId: 'user_pm', targetType: 'project', targetId: 'project_web', createdAt: DateTime.now().subtract(const Duration(hours: 5)), before: {'status': 'active'}, after: {'status': 'review'}),
  ];

}