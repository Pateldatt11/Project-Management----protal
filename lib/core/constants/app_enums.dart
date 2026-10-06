import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

enum UserRole {
  superAdmin,
  admin,
  itAdmin,
  projectManager,
  teamLead,
  developer,
  qaTester,
  designer,
  devOps,
  hrManager,
  employee,
  clientViewer,
}

enum ProjectStatus { planning, active, onHold, review, completed, cancelled }
enum TaskStatus { backlog, todo, inProgress, review, testing, completed }
enum TaskPriority { low, medium, high, critical }
enum MainSection { dashboard, projects, tasks, kanban, timeline, appraisals, meetings, teams, employees, reports, notifications, settings, profile }

extension UserRoleX on UserRole {
  String get value => name;

  String get label => switch (this) {
        UserRole.superAdmin => 'Super Admin',
        UserRole.admin => 'Company Admin',
        UserRole.itAdmin => 'IT Admin',
        UserRole.projectManager => 'Project Manager',
        UserRole.teamLead => 'Team Lead',
        UserRole.developer => 'Developer',
        UserRole.qaTester => 'QA / Tester',
        UserRole.designer => 'Designer',
        UserRole.devOps => 'DevOps Engineer',
        UserRole.hrManager => 'HR / People Manager',
        UserRole.employee => 'Employee',
        UserRole.clientViewer => 'Client / Viewer',
      };

  String get shortLabel => switch (this) {
        UserRole.superAdmin => 'Super',
        UserRole.admin => 'Admin',
        UserRole.itAdmin => 'IT',
        UserRole.projectManager => 'PM',
        UserRole.teamLead => 'TL',
        UserRole.developer => 'Dev',
        UserRole.qaTester => 'QA',
        UserRole.designer => 'Design',
        UserRole.devOps => 'DevOps',
        UserRole.hrManager => 'HR',
        UserRole.employee => 'Employee',
        UserRole.clientViewer => 'Viewer',
      };

  String get department => switch (this) {
        UserRole.superAdmin => 'Administration',
        UserRole.admin => 'Administration',
        UserRole.itAdmin => 'IT & Infrastructure',
        UserRole.devOps => 'IT & Infrastructure',
        UserRole.projectManager => 'Delivery Management',
        UserRole.teamLead => 'Delivery Management',
        UserRole.developer => 'Engineering',
        UserRole.qaTester => 'Quality Assurance',
        UserRole.designer => 'Product Design',
        UserRole.hrManager => 'People Operations',
        UserRole.employee => 'Operations',
        UserRole.clientViewer => 'External Stakeholder',
      };

  String get description => switch (this) {
        UserRole.superAdmin => 'Platform owner with full company, billing, security, and system access.',
        UserRole.admin => 'Company workspace admin with users, roles, projects, reports, and settings access.',
        UserRole.itAdmin => 'Manages security, integrations, storage, audit visibility, devices, and Firebase rollout settings.',
        UserRole.projectManager => 'Owns project planning, milestones, assignment, progress, reports, and delivery risk.',
        UserRole.teamLead => 'Controls team execution, task status, reviews, QA handoff, and workload balance.',
        UserRole.developer => 'Works on assigned development tasks, comments, uploads files, and updates progress.',
        UserRole.qaTester => 'Tests assigned work, moves tasks through Review/Testing, and reports defects.',
        UserRole.designer => 'Handles design tasks, assets, product flows, and design review work.',
        UserRole.devOps => 'Handles deployment, CI/CD, release tasks, infrastructure tasks, and production checks.',
        UserRole.hrManager => 'Views employee directory, availability, people workload, and HR reports.',
        UserRole.employee => 'General contributor with assigned task and notification access.',
        UserRole.clientViewer => 'Read-only external stakeholder with limited project/report visibility.',
      };

  Color get color => switch (this) {
        UserRole.superAdmin => AppTheme.danger,
        UserRole.admin => AppTheme.violet,
        UserRole.itAdmin => Colors.teal,
        UserRole.projectManager => AppTheme.blue,
        UserRole.teamLead => Colors.indigo,
        UserRole.developer => AppTheme.success,
        UserRole.qaTester => Colors.deepOrange,
        UserRole.designer => Colors.pink,
        UserRole.devOps => Colors.cyan,
        UserRole.hrManager => Colors.brown,
        UserRole.employee => AppTheme.muted,
        UserRole.clientViewer => Colors.blueGrey,
      };

  bool get isAdminLike => this == UserRole.superAdmin || this == UserRole.admin || this == UserRole.itAdmin;
  bool get isDeliveryManager => isAdminLike || this == UserRole.projectManager || this == UserRole.teamLead;
  bool get isContributor => [UserRole.developer, UserRole.qaTester, UserRole.designer, UserRole.devOps, UserRole.employee].contains(this);
  bool get isReadOnly => this == UserRole.clientViewer;

  /// Core portal posts are safety roles. They stay active so the company is never locked out.
  bool get isCorePortalPost => this == UserRole.superAdmin || this == UserRole.admin || this == UserRole.itAdmin;

  /// Optional posts can be enabled/disabled by IT Admin, Admin, or Super Admin.
  bool get canBePortalDeactivated => !isCorePortalPost;

  static UserRole fromValue(String? value) {
    return UserRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UserRole.employee,
    );
  }
}

extension ProjectStatusX on ProjectStatus {
  String get value => name;
  String get label => switch (this) {
        ProjectStatus.planning => 'Planning',
        ProjectStatus.active => 'Active',
        ProjectStatus.onHold => 'On Hold',
        ProjectStatus.review => 'Review',
        ProjectStatus.completed => 'Completed',
        ProjectStatus.cancelled => 'Cancelled',
      };

  Color get color => switch (this) {
        ProjectStatus.planning => AppTheme.muted,
        ProjectStatus.active => AppTheme.blue,
        ProjectStatus.onHold => AppTheme.warning,
        ProjectStatus.review => Colors.purple,
        ProjectStatus.completed => AppTheme.success,
        ProjectStatus.cancelled => AppTheme.danger,
      };


  int get stageProgressFloor => switch (this) {
        ProjectStatus.planning => 10,
        ProjectStatus.active => 35,
        ProjectStatus.onHold => 45,
        ProjectStatus.review => 85,
        ProjectStatus.completed => 100,
        ProjectStatus.cancelled => 0,
      };

  String get progressMeaning => switch (this) {
        ProjectStatus.planning => 'Planning started',
        ProjectStatus.active => 'Execution active',
        ProjectStatus.onHold => 'Paused / blocked',
        ProjectStatus.review => 'Final review stage',
        ProjectStatus.completed => 'Delivery completed',
        ProjectStatus.cancelled => 'Cancelled',
      };


  static ProjectStatus fromValue(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return ProjectStatus.planning;
    final normalized = raw.replaceAll(RegExp(r'[\s_\-]+'), '').toLowerCase();
    for (final status in ProjectStatus.values) {
      if (status.name.toLowerCase() == raw.toLowerCase() ||
          status.name.replaceAll(RegExp(r'[\s_\-]+'), '').toLowerCase() == normalized ||
          status.label.replaceAll(RegExp(r'[\s_\-]+'), '').toLowerCase() == normalized) {
        return status;
      }
    }
    return switch (normalized) {
      'live' || 'open' || 'ongoing' || 'inprogress' || 'execution' || 'executionactive' => ProjectStatus.active,
      'todo' || 'backlog' || 'planned' => ProjectStatus.planning,
      'hold' || 'paused' || 'blocked' => ProjectStatus.onHold,
      'inreview' || 'qa' || 'testing' => ProjectStatus.review,
      'done' || 'closed' || 'complete' || 'finished' => ProjectStatus.completed,
      'canceled' || 'cancel' || 'void' => ProjectStatus.cancelled,
      _ => ProjectStatus.planning,
    };
  }
}

extension TaskStatusX on TaskStatus {
  String get value => name;
  String get label => switch (this) {
        TaskStatus.backlog => 'Backlog',
        TaskStatus.todo => 'Todo',
        TaskStatus.inProgress => 'In Progress',
        TaskStatus.review => 'Review',
        TaskStatus.testing => 'Testing',
        TaskStatus.completed => 'Completed',
      };

  Color get color => switch (this) {
        TaskStatus.backlog => AppTheme.muted,
        TaskStatus.todo => Colors.indigo,
        TaskStatus.inProgress => AppTheme.blue,
        TaskStatus.review => Colors.purple,
        TaskStatus.testing => AppTheme.warning,
        TaskStatus.completed => AppTheme.success,
      };

  static TaskStatus fromValue(String? value) {
    return TaskStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TaskStatus.backlog,
    );
  }
}

extension TaskPriorityX on TaskPriority {
  String get value => name;
  String get label => switch (this) {
        TaskPriority.low => 'Low',
        TaskPriority.medium => 'Medium',
        TaskPriority.high => 'High',
        TaskPriority.critical => 'Critical',
      };

  Color get color => switch (this) {
        TaskPriority.low => AppTheme.success,
        TaskPriority.medium => AppTheme.blue,
        TaskPriority.high => AppTheme.warning,
        TaskPriority.critical => AppTheme.danger,
      };

  static TaskPriority fromValue(String? value) {
    return TaskPriority.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TaskPriority.medium,
    );
  }
}

extension MainSectionX on MainSection {
  String get label => switch (this) {
        MainSection.dashboard => 'Dashboard',
        MainSection.projects => 'Projects',
        MainSection.tasks => 'Tasks',
        MainSection.kanban => 'Kanban',
        MainSection.timeline => 'Timeline',
        MainSection.appraisals => 'Appraisals',
        MainSection.meetings => 'Meetings',
        MainSection.teams => 'Teams',
        MainSection.employees => 'Employees',
        MainSection.reports => 'Reports',
        MainSection.notifications => 'Notifications',
        MainSection.settings => 'Settings',
        MainSection.profile => 'Profile',
      };

  IconData get icon => switch (this) {
        MainSection.dashboard => Icons.dashboard_rounded,
        MainSection.projects => Icons.folder_copy_rounded,
        MainSection.tasks => Icons.task_alt_rounded,
        MainSection.kanban => Icons.view_kanban_rounded,
        MainSection.timeline => Icons.timeline_rounded,
        MainSection.appraisals => Icons.workspace_premium_rounded,
        MainSection.meetings => Icons.video_call_rounded,
        MainSection.teams => Icons.groups_rounded,
        MainSection.employees => Icons.badge_rounded,
        MainSection.reports => Icons.insert_chart_rounded,
        MainSection.notifications => Icons.notifications_rounded,
        MainSection.settings => Icons.settings_rounded,
        MainSection.profile => Icons.person_rounded,
      };
}
