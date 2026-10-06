import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/constants/app_enums.dart';
import '../core/permissions/permission_service.dart';
import '../core/platform/android_file_picker_service.dart' show AndroidFilePickerService;
import '../core/services/notification_service.dart';
import '../core/services/onesignal_api_service.dart';
import '../core/utils/id_generator.dart';
import '../core/utils/json_value.dart';
import '../data/cloudinary/cloudinary_upload_service.dart' show CloudinaryUploadService;
import '../data/demo/demo_data.dart';
import '../data/firebase/firebase_paths.dart';
import '../data/models/activity_log.dart';
import '../data/models/app_notification.dart';
import '../data/models/app_user.dart';
import '../data/models/audit_log.dart';
import '../data/models/company.dart';
import '../data/models/file_attachment.dart';
import '../data/models/member.dart';
import '../data/models/mobile_ui_config.dart';
import '../data/models/mobile_ui_design.dart';
import '../data/models/portal_post_settings.dart';
import '../data/models/project.dart';
import '../data/models/report.dart';
import '../data/models/task.dart';
import '../data/models/task_comment.dart';
import '../data/models/team.dart';
import '../data/repositories/firebase_workspace_repository.dart';

class WorkspaceState {
  const WorkspaceState({
    required this.user,
    required this.company,
    required this.members,
    required this.teams,
    required this.projects,
    required this.tasks,
    required this.notifications,
    required this.activity,
    required this.reports,
    required this.comments,
    required this.attachments,
    required this.auditLogs,
    required this.portalPostSettings,
    required this.mobileUiConfig,
    required this.mobileUiDesign,
    required this.demoDataEnabled,
    this.isRegistrationComplete = true,
    this.lastError,
    this.isSaving = false,
    this.uploadingTaskId,
  });

  final AppUser user;
  final Company company;
  final List<Member> members;
  final List<Team> teams;
  final List<Project> projects;
  final List<ProjectTask> tasks;
  final List<AppNotification> notifications;
  final List<ActivityLog> activity;
  final List<ReportModel> reports;
  final List<TaskComment> comments;
  final List<FileAttachment> attachments;
  final List<AuditLog> auditLogs;
  final PortalPostSettings portalPostSettings;
  final MobileUiConfig mobileUiConfig;
  final MobileUiDesign mobileUiDesign;
  final bool demoDataEnabled;
  final bool isRegistrationComplete;
  final String? lastError;
  final bool isSaving;
  final String? uploadingTaskId;

  Member get currentMember => members.firstWhere(
        (member) => member.uid == user.uid,
        orElse: () => Member(
          uid: user.uid,
          displayName: user.displayName,
          email: user.email,
          role: user.role,
          status: user.status,
          isOnline: true,
          lastSeenAt: DateTime.now(),
        ),
      );

  List<Project> get activeProjects => projects.where((project) => !project.isArchived).toList();

  bool isPortalPostActive(UserRole role) => portalPostSettings.isRoleEnabled(role);

  List<UserRole> get activePortalRoles => UserRole.values.where(isPortalPostActive).toList();

  List<Member> get activePortalMembers => members.where((member) => member.status == 'active' && isPortalPostActive(member.role)).toList();

  List<Member> get onlineMembers => activePortalMembers.where((member) => member.isOnline).toList();

  List<Member> get offlineMembers => activePortalMembers.where((member) => !member.isOnline).toList();

  int get inactivePortalPostCount => UserRole.values.where((role) => !isPortalPostActive(role)).length;

  bool get firestoreOnlyMode => AppConfig.useFirebase && !demoDataEnabled;

  String get dataSourceLabel => firestoreOnlyMode ? 'Firestore only' : demoDataEnabled ? 'Firestore + demo overlay' : 'Local demo off';

  List<Project> get visibleProjects {
    final member = currentMember;
    if (!isPortalPostActive(member.role)) return const <Project>[];
    if ([UserRole.superAdmin, UserRole.admin, UserRole.itAdmin, UserRole.hrManager].contains(member.role)) {
      return activeProjects;
    }
    return activeProjects.where((project) {
      if (member.projectIds.contains(project.projectId)) return true;
      if (project.managerIds.contains(member.uid)) return true;
      if (project.teamIds.any(member.teamIds.contains)) return true;
      return tasks.any((task) => task.projectId == project.projectId && task.assignedToIds.contains(member.uid));
    }).toList();
  }

  List<ProjectTask> get visibleTasks {
    final member = currentMember;
    if (!isPortalPostActive(member.role)) return const <ProjectTask>[];
    if (PermissionService.canViewFullProjectProgress(member)) {
      return tasks;
    }
    if (member.role == UserRole.clientViewer || member.role == UserRole.hrManager) {
      return const <ProjectTask>[];
    }
    return tasks.where((task) => task.assignedToIds.contains(member.uid)).toList();
  }

  List<AppNotification> get myNotifications {
    final filtered = notifications.where(isNotificationVisibleToCurrentUser).toList();
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  Map<String, dynamic> get effectiveNotificationAlertConfig => <String, dynamic>{
        ...MobileUiConfig.defaultNotificationAlertConfig,
        ...mobileUiConfig.notificationAlertConfig,
        if (mobileUiDesign.enabled) ...mobileUiDesign.notificationAlertConfig,
      };

  Map<String, dynamic> get effectiveNotificationDisplayConfig {
    final base = effectiveNotificationAlertConfig;
    final allowUserWindow = _notificationConfigBool(base, const <String>[
      'allowUserDisplayWindowSelection',
      'allowUserNotificationWindow',
      'allowUserDisplayWindow',
    ], fallback: true);
    final userPrefs = user.notificationPreferences;
    if (!allowUserWindow || userPrefs.isEmpty) return base;
    return <String, dynamic>{
      ...base,
      ...userPrefs,
    };
  }

  bool isNotificationVisibleToCurrentUser(AppNotification notification) {
    final member = currentMember;
    final roleValue = member.role.value;
    final recipientMatches = notification.recipientId == user.uid ||
        notification.recipientIds.contains(user.uid) ||
        (notification.recipientRole ?? '').trim() == roleValue ||
        ((notification.recipientRoleGroup ?? '').trim() == 'admins' && member.role.isAdminLike);
    if (!recipientMatches) return false;
    return isNotificationInsideDisplayWindow(notification);
  }

  bool isNotificationInsideDisplayWindow(AppNotification notification, {DateTime? now}) {
    final alertConfig = effectiveNotificationDisplayConfig;
    final current = (now ?? DateTime.now()).toLocal();
    final hideExpired = _notificationConfigBool(alertConfig, const <String>[
      'hideExpiredNotifications',
      'hideAfterDisplayWindow',
      'enforceNotificationExpiry',
    ], fallback: true);
    if (hideExpired && notification.isExpiredAt(current)) return false;

    final mode = _notificationConfigString(alertConfig, const <String>[
      'displayWindowMode',
      'notificationDisplayWindowMode',
      'notificationHistoryMode',
      'visibleWindowMode',
    ], fallback: 'currentMonth').toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');

    if (mode == 'all' || mode == 'forever' || mode == 'unlimited' || mode == 'none') return true;

    final createdAt = notification.createdAt.toLocal();
    if (mode == 'currentmonth' || mode == 'thismonth' || mode == 'month') {
      final monthStart = DateTime(current.year, current.month);
      return !createdAt.isBefore(monthStart);
    }

    if (mode == 'customhours' || mode == 'lasthours' || mode == 'hours' || mode == 'usersethours') {
      final hours = _notificationConfigInt(alertConfig, const <String>[
        'displayWindowHours',
        'notificationDisplayHours',
        'visibleHours',
        'userSetHours',
      ], fallback: 24).clamp(1, 24 * 3660).toInt();
      return !createdAt.isBefore(current.subtract(Duration(hours: hours)));
    }

    final days = _notificationConfigInt(alertConfig, const <String>[
      'displayWindowDays',
      'notificationDisplayDays',
      'visibleDays',
      'userSetDays',
      'retentionDays',
    ], fallback: 31).clamp(1, 3660).toInt();
    return !createdAt.isBefore(current.subtract(Duration(days: days)));
  }

  DateTime? notificationExpiryFor(DateTime createdAt) {
    final alertConfig = effectiveNotificationAlertConfig;
    final mode = _notificationConfigString(alertConfig, const <String>[
      'displayWindowMode',
      'notificationDisplayWindowMode',
      'notificationHistoryMode',
      'visibleWindowMode',
    ], fallback: 'currentMonth').toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    final created = createdAt.toLocal();
    if (mode == 'all' || mode == 'forever' || mode == 'unlimited' || mode == 'none') return null;
    if (mode == 'currentmonth' || mode == 'thismonth' || mode == 'month') {
      return DateTime(created.year, created.month + 1);
    }
    if (mode == 'customhours' || mode == 'lasthours' || mode == 'hours' || mode == 'usersethours') {
      final hours = _notificationConfigInt(alertConfig, const <String>[
        'displayWindowHours',
        'notificationDisplayHours',
        'visibleHours',
        'userSetHours',
      ], fallback: 24).clamp(1, 24 * 3660).toInt();
      return created.add(Duration(hours: hours));
    }
    final days = _notificationConfigInt(alertConfig, const <String>[
      'displayWindowDays',
      'notificationDisplayDays',
      'visibleDays',
      'userSetDays',
      'retentionDays',
    ], fallback: 31).clamp(1, 3660).toInt();
    return created.add(Duration(days: days));
  }

  static bool _notificationConfigBool(Map<String, dynamic> config, List<String> keys, {required bool fallback}) {
    for (final key in keys) {
      final value = config[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == 'yes' || normalized == '1' || normalized == 'on') return true;
        if (normalized == 'false' || normalized == 'no' || normalized == '0' || normalized == 'off') return false;
      }
    }
    return fallback;
  }

  static String _notificationConfigString(Map<String, dynamic> config, List<String> keys, {required String fallback}) {
    for (final key in keys) {
      final value = config[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  static int _notificationConfigInt(Map<String, dynamic> config, List<String> keys, {required int fallback}) {
    for (final key in keys) {
      final value = config[key];
      if (value is int) return value;
      if (value is num) return value.round();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return fallback;
  }

  int get myUnreadNotificationCount => myNotifications.where((notification) => !notification.isRead).length;

  DashboardStatsLike get stats {
    final visibleProjects = this.visibleProjects;
    final tasks = visibleTasks;
    final activeProjectsCount = visibleProjects.where((p) => p.isActiveWork).length;
    final completedProjects = visibleProjects.where((p) => p.status == ProjectStatus.completed).length;
    final delayedProjects = visibleProjects.where((p) => p.isDelayed).length;
    final completedTasks = tasks.where((t) => t.status == TaskStatus.completed).length;
    final overdueTasks = tasks.where((t) => t.isOverdue).length;
    final productivity = tasks.isEmpty ? 0 : ((completedTasks / tasks.length) * 100).round();
    return DashboardStatsLike(
      totalProjects: visibleProjects.length,
      activeProjects: activeProjectsCount,
      completedProjects: completedProjects,
      delayedProjects: delayedProjects,
      totalTasks: tasks.length,
      completedTasks: completedTasks,
      overdueTasks: overdueTasks,
      teamProductivity: productivity,
    );
  }

  WorkspaceState copyWith({
    AppUser? user,
    Company? company,
    List<Member>? members,
    List<Team>? teams,
    List<Project>? projects,
    List<ProjectTask>? tasks,
    List<AppNotification>? notifications,
    List<ActivityLog>? activity,
    List<ReportModel>? reports,
    List<TaskComment>? comments,
    List<FileAttachment>? attachments,
    List<AuditLog>? auditLogs,
    PortalPostSettings? portalPostSettings,
    MobileUiConfig? mobileUiConfig,
    MobileUiDesign? mobileUiDesign,
    bool? demoDataEnabled,
    bool? isRegistrationComplete,
    String? lastError,
    bool? clearError,
    bool? isSaving,
    String? uploadingTaskId,
    bool clearUploadingTaskId = false,
  }) =>
      WorkspaceState(
        user: user ?? this.user,
        company: company ?? this.company,
        members: members ?? this.members,
        teams: teams ?? this.teams,
        projects: projects ?? this.projects,
        tasks: tasks ?? this.tasks,
        notifications: notifications ?? this.notifications,
        activity: activity ?? this.activity,
        reports: reports ?? this.reports,
        comments: comments ?? this.comments,
        attachments: attachments ?? this.attachments,
        auditLogs: auditLogs ?? this.auditLogs,
        portalPostSettings: portalPostSettings ?? this.portalPostSettings,
        mobileUiConfig: mobileUiConfig ?? this.mobileUiConfig,
        mobileUiDesign: mobileUiDesign ?? this.mobileUiDesign,
        demoDataEnabled: demoDataEnabled ?? this.demoDataEnabled,
        isRegistrationComplete: isRegistrationComplete ?? this.isRegistrationComplete,
        lastError: clearError == true ? null : lastError ?? this.lastError,
        isSaving: isSaving ?? this.isSaving,
        uploadingTaskId: clearUploadingTaskId ? null : uploadingTaskId ?? this.uploadingTaskId,
      );

  static WorkspaceState demo() => WorkspaceState(
        user: DemoData.user,
        company: DemoData.company,
        members: DemoData.members,
        teams: DemoData.teams,
        projects: DemoData.projects,
        tasks: DemoData.tasks,
        notifications: DemoData.notifications,
        activity: DemoData.activity,
        reports: DemoData.reports,
        comments: DemoData.comments,
        attachments: DemoData.attachments,
        auditLogs: DemoData.auditLogs,
        portalPostSettings: DemoData.portalPostSettings,
        mobileUiConfig: MobileUiConfig.defaults(),
        mobileUiDesign: MobileUiDesign.defaults(),
        demoDataEnabled: true,
        isRegistrationComplete: true,
      );

  static WorkspaceState empty({bool demoDataEnabled = false}) => WorkspaceState(
        user: const AppUser(
          uid: '',
          displayName: 'Not signed in',
          email: '',
          role: UserRole.employee,
          defaultCompanyId: AppConfig.fallbackCompanyId,
          status: 'signedOut',
        ),
        company: const Company(
          companyId: AppConfig.fallbackCompanyId,
          name: 'Company Workspace',
          industry: 'Project Management',
          status: 'active',
          timezone: 'Asia/Kolkata',
        ),
        members: const <Member>[],
        teams: const <Team>[],
        projects: const <Project>[],
        tasks: const <ProjectTask>[],
        notifications: const <AppNotification>[],
        activity: const <ActivityLog>[],
        reports: const <ReportModel>[],
        comments: const <TaskComment>[],
        attachments: const <FileAttachment>[],
        auditLogs: const <AuditLog>[],
        portalPostSettings: PortalPostSettings(enabledRoleValues: <String>[
          'superAdmin',
          'admin',
          'itAdmin',
          'projectManager',
          'teamLead',
          'developer',
          'qaTester',
          'designer',
          'devOps',
          'hrManager',
          'employee',
          'clientViewer',
        ]),
        mobileUiConfig: MobileUiConfig.defaults(),
        mobileUiDesign: MobileUiDesign.defaults(),
        demoDataEnabled: demoDataEnabled,
        isRegistrationComplete: false,
      );

  static WorkspaceState initial() => AppConfig.useFirebase ? WorkspaceState.empty() : WorkspaceState.demo();
}

class DashboardStatsLike {
  const DashboardStatsLike({
    required this.totalProjects,
    required this.activeProjects,
    required this.completedProjects,
    required this.delayedProjects,
    required this.totalTasks,
    required this.completedTasks,
    required this.overdueTasks,
    required this.teamProductivity,
  });

  final int totalProjects;
  final int activeProjects;
  final int completedProjects;
  final int delayedProjects;
  final int totalTasks;
  final int completedTasks;
  final int overdueTasks;
  final int teamProductivity;
}

class WorkspaceController extends StateNotifier<WorkspaceState> {
  WorkspaceController({FirebaseWorkspaceRepository? repository})
      : _repository = repository,
        super(WorkspaceState.initial()) {
    _recalculateProjectProgress();
  }

  final FirebaseWorkspaceRepository? _repository;
  final List<StreamSubscription<dynamic>> _firebaseSubscriptions = <StreamSubscription<dynamic>>[];
  StreamSubscription<dynamic>? _taskSubscription;
  bool? _taskStreamCanSeeAll;
  String? _firebaseCompanyId;
  String? _firebaseUid;

  List<Member> _firestoreMembers = const <Member>[];
  List<Team> _firestoreTeams = const <Team>[];
  List<Project> _firestoreProjects = const <Project>[];
  List<ProjectTask> _firestoreTasks = const <ProjectTask>[];
  List<AppNotification> _firestoreNotifications = const <AppNotification>[];
  List<ActivityLog> _firestoreActivity = const <ActivityLog>[];
  List<ReportModel> _firestoreReports = const <ReportModel>[];
  List<TaskComment> _firestoreComments = const <TaskComment>[];
  List<FileAttachment> _firestoreAttachments = const <FileAttachment>[];
  List<AuditLog> _firestoreAuditLogs = const <AuditLog>[];

  bool get _firebaseActive => AppConfig.useFirebase && _repository != null && _firebaseCompanyId != null;

  @override
  void dispose() {
    _cancelFirebaseSubscriptions();
    super.dispose();
  }

  void _cancelFirebaseSubscriptions() {
    for (final subscription in _firebaseSubscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_taskSubscription?.cancel());
    _taskSubscription = null;
    _taskStreamCanSeeAll = null;
    _firebaseSubscriptions.clear();
  }

  List<T> _mergeById<T>(List<T> firestoreItems, List<T> demoItems, String Function(T item) idOf, {bool? includeDemo}) {
    if (!(includeDemo ?? state.demoDataEnabled)) return firestoreItems;
    final ids = firestoreItems.map(idOf).toSet();
    return <T>[
      ...firestoreItems,
      ...demoItems.where((item) => !ids.contains(idOf(item))),
    ];
  }

  List<Member> _displayMembers(List<Member> items, {bool? includeDemo}) => _mergeById<Member>(items, DemoData.members, (item) => item.uid, includeDemo: includeDemo);
  List<Team> _displayTeams(List<Team> items, {bool? includeDemo}) => _mergeById<Team>(items, DemoData.teams, (item) => item.teamId, includeDemo: includeDemo);
  List<Project> _displayProjects(List<Project> items, {bool? includeDemo}) => _mergeById<Project>(items, DemoData.projects, (item) => item.projectId, includeDemo: includeDemo);
  List<ProjectTask> _displayTasks(List<ProjectTask> items, {bool? includeDemo}) => _mergeById<ProjectTask>(items, DemoData.tasks, (item) => item.taskId, includeDemo: includeDemo);
  List<AppNotification> _displayNotifications(List<AppNotification> items, {bool? includeDemo}) => _mergeById<AppNotification>(items, DemoData.notifications, (item) => item.notificationId, includeDemo: includeDemo);
  List<ActivityLog> _displayActivity(List<ActivityLog> items, {bool? includeDemo}) => _mergeById<ActivityLog>(items, DemoData.activity, (item) => item.activityLogId, includeDemo: includeDemo);
  List<ReportModel> _displayReports(List<ReportModel> items, {bool? includeDemo}) => _mergeById<ReportModel>(items, DemoData.reports, (item) => item.reportId, includeDemo: includeDemo);
  List<TaskComment> _displayComments(List<TaskComment> items, {bool? includeDemo}) => _mergeById<TaskComment>(items, DemoData.comments, (item) => item.commentId, includeDemo: includeDemo);
  List<FileAttachment> _displayAttachments(List<FileAttachment> items, {bool? includeDemo}) => _mergeById<FileAttachment>(items, DemoData.attachments, (item) => item.attachmentId, includeDemo: includeDemo);
  List<AuditLog> _displayAuditLogs(List<AuditLog> items, {bool? includeDemo}) => _mergeById<AuditLog>(items, DemoData.auditLogs, (item) => item.auditLogId, includeDemo: includeDemo);

  Future<bool> _readDemoDataEnabled(FirebaseFirestore db, String companyId) async {
    final ref = db.doc(FirebasePaths.demoDataSettings(companyId));
    final snapshot = await ref.get();
    final data = snapshot.data();
    final value = data == null ? null : data['demoDataEnabled'];
    final enabled = value is bool ? value : false;
    if (!snapshot.exists) {
      try {
        await ref.set({
          'demoDataEnabled': false,
          'updatedBy': state.user.uid,
          'updatedAt': DateTime.now().toIso8601String(),
          'note': 'When false, the app renders only documents streamed from Firestore collections.',
        }, SetOptions(merge: true));
      } catch (_) {}
    }
    return enabled;
  }

  static bool _isSuperAdminRoleValue(dynamic value) {
    final raw = (value ?? '').toString().trim();
    final normalized = raw.replaceAll(RegExp(r'[^A-Za-z]'), '').toLowerCase();
    return normalized == 'superadmin' || normalized == 'platformsuperadmin';
  }

  static bool _isActiveAccountStatus(dynamic value) {
    final raw = (value ?? 'active').toString().trim().toLowerCase();
    return raw.isEmpty || raw == 'active' || raw == 'enabled';
  }

  static bool _matchesAuthEmail(dynamic storedEmail, String authEmail) {
    final stored = (storedEmail ?? '').toString().trim().toLowerCase();
    final auth = authEmail.trim().toLowerCase();
    return stored.isEmpty || auth.isEmpty || stored == auth;
  }

  static String _inviteIdForEmail(String email) {
    final normalized = email.trim().toLowerCase();
    return normalized.replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
  }

  void _applyDataSourcePreference(bool enabled) {
    final memberFallback = _firestoreMembers.isEmpty && state.user.uid.isNotEmpty ? <Member>[state.currentMember] : _firestoreMembers;
    state = state.copyWith(
      demoDataEnabled: enabled,
      members: enabled ? _displayMembers(memberFallback, includeDemo: true) : memberFallback,
      teams: enabled ? _displayTeams(_firestoreTeams, includeDemo: true) : _firestoreTeams,
      projects: enabled ? _displayProjects(_firestoreProjects, includeDemo: true) : _firestoreProjects,
      tasks: enabled ? _displayTasks(_firestoreTasks, includeDemo: true) : _firestoreTasks,
      notifications: enabled ? _displayNotifications(_firestoreNotifications, includeDemo: true) : _firestoreNotifications,
      activity: enabled ? _displayActivity(_firestoreActivity, includeDemo: true) : _firestoreActivity,
      reports: enabled ? _displayReports(_firestoreReports, includeDemo: true) : _firestoreReports,
      comments: enabled ? _displayComments(_firestoreComments, includeDemo: true) : _firestoreComments,
      attachments: enabled ? _displayAttachments(_firestoreAttachments, includeDemo: true) : _firestoreAttachments,
      auditLogs: enabled ? _displayAuditLogs(_firestoreAuditLogs, includeDemo: true) : _firestoreAuditLogs,
      clearError: true,
    );
  }

  Future<String> _resolveCompanyIdForLogin({
    required FirebaseFirestore db,
    required String uid,
    Map<String, dynamic>? userData,
  }) async {
    final explicit = JsonValue.string(
      userData?['defaultCompanyId'] ?? userData?['companyId'] ?? userData?['activeCompanyId'],
      fallback: '',
    ).trim();
    if (explicit.isNotEmpty) return explicit;

    try {
      final memberships = await db.collection(FirebasePaths.userMemberships(uid)).limit(10).get();
      if (memberships.docs.isNotEmpty) {
        final active = memberships.docs.where((doc) {
          final status = JsonValue.string(doc.data()['status'], fallback: 'active').trim().toLowerCase();
          return status.isEmpty || status == 'active' || status == 'enabled';
        }).toList();
        final selected = active.isNotEmpty ? active.first : memberships.docs.first;
        final fromData = JsonValue.string(selected.data()['companyId'], fallback: '').trim();
        if (fromData.isNotEmpty) return fromData;
        if (selected.id.trim().isNotEmpty) return selected.id.trim();
      }
    } catch (_) {}

    return AppConfig.fallbackCompanyId;
  }

  Future<void> updateConditionalUserDoc({
    required String uid,
    required Map<String, dynamic> dataToUpdate,
  }) async {
    if (!AppConfig.useFirebase) return;

    final db = FirebaseFirestore.instance;
    final singularRef = db.doc('user/$uid');

    try {
      final singularSnap = await singularRef.get();
      if (singularSnap.exists) {
        await singularRef.set(dataToUpdate, SetOptions(merge: true));
      }
    } catch (error) {
      state = state.copyWith(lastError: 'User doc update failed: $error');
    }
  }

  void simulateRenewalWarning() {
    if (!PermissionService.canManageSettings(state.currentMember)) {
      state = state.copyWith(lastError: 'Only admins can simulate billing triggers.');
      return;
    }

    final currentCompany = state.company;
    final currentWarnings = currentCompany.renewalWarningCount;
    final newWarningCount = (currentWarnings + 1).clamp(0, 5);
    final isRestricted = newWarningCount >= 5;

    final updatedCompany = currentCompany.copyWith(
      renewalWarningCount: newWarningCount,
      subscriptionStatus: isRestricted ? 'restricted' : 'grace_period',
      plan: '',
    );

    state = state.copyWith(
      company: updatedCompany,
      clearError: true,
    );

    if (_firebaseActive) {
      _fireAndForget(
        FirebaseFirestore.instance.doc(FirebasePaths.company(state.company.companyId)).set({
          'renewalWarningCount': newWarningCount,
          'subscriptionStatus': isRestricted ? 'restricted' : 'grace_period',
          'updatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true)),
        'Simulated warning sync',
      );
    }
  }

  void simulateSuccessfulRenewal() {
    final updatedCompany = state.company.copyWith(
      renewalWarningCount: 0,
      subscriptionStatus: 'active',
      currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
      plan: '',
    );

    state = state.copyWith(
      company: updatedCompany,
      clearError: true,
    );

    if (_firebaseActive) {
      _fireAndForget(
        FirebaseFirestore.instance.doc(FirebasePaths.company(state.company.companyId)).set({
          'renewalWarningCount': 0,
          'subscriptionStatus': 'active',
          'currentPeriodEnd': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true)),
        'Simulated renewal sync',
      );
    }
  }

  void updateCompanyPlan(String planKey) {
    final updatedCompany = state.company.copyWith(
      plan: planKey,
      subscriptionStatus: 'active',
      renewalWarningCount: 0,
    );

    state = state.copyWith(
      company: updatedCompany,
      clearError: true,
    );

    if (_firebaseActive) {
      _fireAndForget(
        FirebaseFirestore.instance.doc(FirebasePaths.company(state.company.companyId)).set({
          'plan': planKey,
          'subscriptionStatus': 'active',
          'renewalWarningCount': 0,
          'updatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true)),
        'Company plan update sync',
      );
    }
  }

  Future<void> connectFirebaseUser({
    required String uid,
    required String email,
    String? displayName,
    String? companyIdOverride,
  }) async {
    if (!AppConfig.useFirebase || _repository == null) return;
    final requestedCompanyId = (companyIdOverride ?? '').trim();
    if (_firebaseUid == uid &&
        _firebaseCompanyId != null &&
        (requestedCompanyId.isEmpty || _firebaseCompanyId == requestedCompanyId)) {
      return;
    }

    var companyId = AppConfig.fallbackCompanyId;
    final safeName = (displayName?.trim().isNotEmpty ?? false) ? displayName!.trim() : email.split('@').first;
    final db = FirebaseFirestore.instance;

    try {
      state = state.copyWith(isSaving: true, clearError: true);
      final now = DateTime.now();
      Member firebaseMember;
      Company firebaseCompany;
      final userRef = db.doc(FirebasePaths.user(uid));
      var userSnapshot = await userRef.get();
      Map<String, dynamic>? userData = userSnapshot.data();

      // Platform Super Admin records may exist in either users/{uid} or the
      // legacy singular user/{uid} collection. Accept both consistently.
      if (!userSnapshot.exists || userData == null) {
        final singularUserSnapshot = await db.doc('user/$uid').get();
        if (singularUserSnapshot.exists && singularUserSnapshot.data() != null) {
          userSnapshot = singularUserSnapshot;
          userData = singularUserSnapshot.data();
        }
      }

      final isManualPlatformSuperAdmin = userSnapshot.exists &&
          userData != null &&
          _isSuperAdminRoleValue(userData['role']) &&
          _isActiveAccountStatus(userData['status']) &&
          _matchesAuthEmail(userData['email'], email);
      final manualPlatformSuperAdminData = userData ?? const <String, dynamic>{};
      companyId = requestedCompanyId.isNotEmpty && isManualPlatformSuperAdmin
          ? requestedCompanyId
          : await _resolveCompanyIdForLogin(db: db, uid: uid, userData: userData);
      _repository!.activeCompanyId = companyId;

      final memberRef = db.doc('${FirebasePaths.members(companyId)}/$uid');
      final companyRef = db.doc(FirebasePaths.company(companyId));
      final bootstrapRef = db.doc(FirebasePaths.bootstrapSettings(companyId));

      Future<DocumentSnapshot<Map<String, dynamic>>?> safeGetCompanySnapshot() async {
        try {
          return await companyRef.get();
        } catch (error) {
          if (isManualPlatformSuperAdmin) return null;
          rethrow;
        }
      }

      Future<DocumentSnapshot<Map<String, dynamic>>?> safeGetBootstrapSnapshot() async {
        try {
          return await bootstrapRef.get();
        } catch (error) {
          if (isManualPlatformSuperAdmin) return null;
          rethrow;
        }
      }

      WorkspaceState platformSetupState(Member member) {
        return WorkspaceState.empty(demoDataEnabled: false).copyWith(
          user: AppUser(
            uid: uid,
            displayName: member.displayName,
            email: email,
            role: UserRole.superAdmin,
            defaultCompanyId: companyId,
            status: 'active',
          ),
          company: Company.platform,
          members: <Member>[member],
          isRegistrationComplete: false,
          isSaving: false,
          clearError: true,
        );
      }

      final existingMember = await memberRef.get();
      bool isRegistrationComplete = true;

      if (existingMember.exists && existingMember.data() != null) {
        firebaseMember = Member.fromJson(existingMember.data()!);
        final companySnapshot = await safeGetCompanySnapshot();
        if (companySnapshot != null && companySnapshot.exists && companySnapshot.data() != null) {
          firebaseCompany = Company.fromJson(companySnapshot.data()!);

          final address = companySnapshot.data()?['address']?.toString() ?? '';
          isRegistrationComplete = address.trim().isNotEmpty;

          await memberRef.set(firebaseMember.copyWith(isOnline: true, lastSeenAt: now).toJson(), SetOptions(merge: true));
        } else if (firebaseMember.role == UserRole.superAdmin) {
          _firebaseUid = uid;
          _firebaseCompanyId = null;
          _firestoreMembers = <Member>[firebaseMember];
          _firestoreTeams = const <Team>[];
          _firestoreProjects = const <Project>[];
          _firestoreTasks = const <ProjectTask>[];
          _firestoreNotifications = const <AppNotification>[];
          _firestoreActivity = const <ActivityLog>[];
          _firestoreReports = const <ReportModel>[];
          _firestoreComments = const <TaskComment>[];
          _firestoreAttachments = const <FileAttachment>[];
          _firestoreAuditLogs = const <AuditLog>[];
          state = platformSetupState(firebaseMember.copyWith(isOnline: true, lastSeenAt: now));
          return;
        } else {
          throw StateError('Company workspace was not found or cannot be read. Ask the Super Admin to complete company setup first.');
        }
      } else if (isManualPlatformSuperAdmin) {
        firebaseMember = Member(
          uid: uid,
          displayName: JsonValue.string(manualPlatformSuperAdminData['displayName'], fallback: safeName),
          email: email,
          role: UserRole.superAdmin,
          status: 'active',
          capacityHoursPerWeek: JsonValue.number(manualPlatformSuperAdminData['capacityHoursPerWeek'], fallback: 40),
          department: 'Platform Administration',
          jobTitle: 'Platform Super Admin',
          location: JsonValue.string(manualPlatformSuperAdminData['location'], fallback: 'India'),
          available: true,
          isOnline: true,
          lastSeenAt: now,
        );

        final companySnapshot = await safeGetCompanySnapshot();
        final bootstrapSnapshot = await safeGetBootstrapSnapshot();
        final setupCompleted = companySnapshot != null &&
            companySnapshot.exists &&
            companySnapshot.data() != null &&
            bootstrapSnapshot != null &&
            bootstrapSnapshot.exists;

        if (setupCompleted) {
          firebaseCompany = Company.fromJson(companySnapshot.data()!);
          final address = companySnapshot.data()?['address']?.toString() ?? '';
          isRegistrationComplete = address.trim().isNotEmpty;

          final batch = db.batch();
          batch.set(memberRef, firebaseMember.toJson(), SetOptions(merge: true));
          batch.set(userRef, AppUser(
            uid: uid,
            displayName: firebaseMember.displayName,
            email: email,
            role: UserRole.superAdmin,
            defaultCompanyId: companyId,
            status: 'active',
          ).toJson(), SetOptions(merge: true));
          batch.set(db.doc('${FirebasePaths.userMemberships(uid)}/$companyId'), {
            'companyId': companyId,
            'companyName': firebaseCompany.name,
            'role': UserRole.superAdmin.value,
            'status': 'active',
            'joinedAt': now.toIso8601String(),
          }, SetOptions(merge: true));
          await batch.commit();
        } else {
          _firebaseUid = uid;
          _firebaseCompanyId = null;
          _firestoreMembers = <Member>[firebaseMember];
          _firestoreTeams = const <Team>[];
          _firestoreProjects = const <Project>[];
          _firestoreTasks = const <ProjectTask>[];
          _firestoreNotifications = const <AppNotification>[];
          _firestoreActivity = const <ActivityLog>[];
          _firestoreReports = const <ReportModel>[];
          _firestoreComments = const <TaskComment>[];
          _firestoreAttachments = const <FileAttachment>[];
          _firestoreAuditLogs = const <AuditLog>[];
          state = platformSetupState(firebaseMember);
          return;
        }
      } else {
        final inviteId = _inviteIdForEmail(email);
        DocumentSnapshot<Map<String, dynamic>>? inviteSnapshot;
        Map<String, dynamic>? inviteData;
        try {
          inviteSnapshot = await db.doc(FirebasePaths.invite(companyId, inviteId)).get();
          inviteData = inviteSnapshot.data();
        } catch (_) {
          inviteSnapshot = null;
          inviteData = null;
        }

        if ((inviteSnapshot?.exists ?? false) && inviteData != null && JsonValue.string(inviteData['email']).trim().toLowerCase() == email.trim().toLowerCase()) {
          firebaseMember = Member(
            uid: uid,
            displayName: JsonValue.string(inviteData['displayName'], fallback: safeName),
            email: email,
            role: UserRoleX.fromValue(JsonValue.string(inviteData['role'], fallback: UserRole.employee.value)),
            status: JsonValue.string(inviteData['status'], fallback: 'active'),
            teamIds: JsonValue.stringList(inviteData['teamIds'] ?? inviteData['teams']),
            projectIds: JsonValue.stringList(inviteData['projectIds'] ?? inviteData['projects']),
            capacityHoursPerWeek: JsonValue.number(inviteData['capacityHoursPerWeek'], fallback: 40),
            available: true,
            isOnline: true,
            lastSeenAt: now,
            department: JsonValue.optionalString(inviteData['department']),
            jobTitle: JsonValue.optionalString(inviteData['jobTitle'] ?? inviteData['postName']),
            location: JsonValue.string(inviteData['location'], fallback: 'Remote'),
          );
          final memberData = firebaseMember.toJson()..['inviteId'] = inviteId;
          final claimBatch = db.batch();
          claimBatch.set(memberRef, memberData, SetOptions(merge: true));
          claimBatch.set(userRef, AppUser(
            uid: uid,
            displayName: firebaseMember.displayName,
            email: email,
            role: firebaseMember.role,
            defaultCompanyId: companyId,
            status: firebaseMember.status,
          ).toJson(), SetOptions(merge: true));
          claimBatch.set(db.doc('${FirebasePaths.userMemberships(uid)}/$companyId'), {
            'companyId': companyId,
            'companyName': JsonValue.string(inviteData['companyName'], fallback: 'Company Workspace'),
            'role': firebaseMember.role.value,
            'status': firebaseMember.status,
            'joinedAt': now.toIso8601String(),
          }, SetOptions(merge: true));
          claimBatch.set(db.doc(FirebasePaths.invite(companyId, inviteId)), {
            'claimedBy': uid,
            'claimedAt': now.toIso8601String(),
            'status': 'claimed',
          }, SetOptions(merge: true));
          await claimBatch.commit();

          final companySnapshot = await companyRef.get();
          firebaseCompany = companySnapshot.exists && companySnapshot.data() != null ? Company.fromJson(companySnapshot.data()!) : DemoData.company;
          final address = companySnapshot.data()?['address']?.toString() ?? '';
          isRegistrationComplete = address.trim().isNotEmpty;
        } else {
          final existingRole = userData == null ? null : userData['role'];
          final roleHelp = userSnapshot.exists
              ? 'A users/$uid document exists, but its role is "${existingRole ?? 'missing'}". Set role to exactly "superAdmin" or "Super Admin" and status to "active".'
              : 'Create users/$uid once with role "superAdmin", status "active", and email "$email".';
          throw StateError('No active company member, invite, or valid manual Super Admin doc found for $email. $roleHelp Then sign in again and complete the Company Setup form.');
        }
      }

      final appUser = AppUser(
        uid: uid,
        displayName: firebaseMember.displayName,
        email: email,
        role: firebaseMember.role,
        defaultCompanyId: companyId,
        status: firebaseMember.status,
      );
      await db.doc(FirebasePaths.user(uid)).set(appUser.toJson(), SetOptions(merge: true));
      await db.doc('${FirebasePaths.userMemberships(uid)}/$companyId').set({
        'companyId': companyId,
        'companyName': firebaseCompany.name,
        'role': firebaseMember.role.value,
        'status': firebaseMember.status,
        'joinedAt': now.toIso8601String(),
      }, SetOptions(merge: true));

      final demoDataEnabled = await _readDemoDataEnabled(db, companyId);

      _firebaseUid = uid;
      _firebaseCompanyId = companyId;
      _firestoreMembers = <Member>[firebaseMember];
      _firestoreTeams = const <Team>[];
      _firestoreProjects = const <Project>[];
      _firestoreTasks = const <ProjectTask>[];
      _firestoreNotifications = const <AppNotification>[];
      _firestoreActivity = const <ActivityLog>[];
      _firestoreReports = const <ReportModel>[];
      _firestoreComments = const <TaskComment>[];
      _firestoreAttachments = const <FileAttachment>[];
      _firestoreAuditLogs = const <AuditLog>[];

      state = WorkspaceState.empty(demoDataEnabled: demoDataEnabled).copyWith(
        user: appUser,
        company: firebaseCompany,
        members: demoDataEnabled ? _displayMembers(_firestoreMembers, includeDemo: true) : _firestoreMembers,
        teams: demoDataEnabled ? _displayTeams(_firestoreTeams, includeDemo: true) : const <Team>[],
        projects: demoDataEnabled ? _displayProjects(_firestoreProjects, includeDemo: true) : const <Project>[],
        tasks: demoDataEnabled ? _displayTasks(_firestoreTasks, includeDemo: true) : const <ProjectTask>[],
        notifications: demoDataEnabled ? _displayNotifications(_firestoreNotifications, includeDemo: true) : const <AppNotification>[],
        activity: demoDataEnabled ? _displayActivity(_firestoreActivity, includeDemo: true) : const <ActivityLog>[],
        reports: demoDataEnabled ? _displayReports(_firestoreReports, includeDemo: true) : const <ReportModel>[],
        comments: demoDataEnabled ? _displayComments(_firestoreComments, includeDemo: true) : const <TaskComment>[],
        attachments: demoDataEnabled ? _displayAttachments(_firestoreAttachments, includeDemo: true) : const <FileAttachment>[],
        auditLogs: demoDataEnabled ? _displayAuditLogs(_firestoreAuditLogs, includeDemo: true) : const <AuditLog>[],
        isRegistrationComplete: isRegistrationComplete,
        isSaving: false,
        clearError: true,
      );
      _attachFirebaseStreams(companyId);
      setMyOnlineStatus(true);

      NotificationService.setExternalUserId(uid);
      NotificationService.addTags({
        'companyId': companyId,
        'role': firebaseMember.role.value,
        'email': email,
      });
    } catch (error) {
      state = state.copyWith(isSaving: false, lastError: 'Firebase startup failed: $error');
      throw StateError('Firebase startup failed: $error');
    }
  }

  Future<void> completeCompanySetupFromSuperAdmin({
    required String companyName,
    required String legalName,
    required String industry,
    required String timezone,
    required String email,
    required String phone,
    required String website,
    required String address,
    required String city,
    required String stateName,
    required String country,
    required String ownerName,
  }) async {
    if (!AppConfig.useFirebase) {
      state = state.copyWith(lastError: 'Company setup is only available in Firebase mode.');
      return;
    }
    if (state.user.uid.isEmpty || state.currentMember.role != UserRole.superAdmin) {
      state = state.copyWith(lastError: 'Only the manually-created Platform Super Admin can complete company setup.');
      return;
    }
    final cleanName = companyName.trim();
    if (cleanName.isEmpty) {
      state = state.copyWith(lastError: 'Company name is required.');
      return;
    }

    final cleanOwnerName = ownerName.trim().isEmpty ? state.user.displayName : ownerName.trim();

    final db = FirebaseFirestore.instance;
    final companyId = state.user.defaultCompanyId.trim().isNotEmpty ? state.user.defaultCompanyId : AppConfig.fallbackCompanyId;
    if (_repository != null) _repository!.activeCompanyId = companyId;
    final now = DateTime.now();
    final company = Company(
      companyId: companyId,
      name: cleanName,
      legalName: legalName.trim().isEmpty ? cleanName : legalName.trim(),
      industry: industry.trim().isEmpty ? 'Technology' : industry.trim(),
      status: 'active',
      timezone: timezone.trim().isEmpty ? 'Asia/Kolkata' : timezone.trim(),
      email: email.trim(),
      phone: phone.trim(),
      website: website.trim(),
      address: address.trim(),
      city: city.trim(),
      state: stateName.trim(),
      country: country.trim().isEmpty ? 'India' : country.trim(),
    );
    final member = state.currentMember.copyWith(
      displayName: cleanOwnerName,
      role: UserRole.superAdmin,
      department: 'Platform Administration',
      jobTitle: 'Platform Super Admin',
      isOnline: true,
      lastSeenAt: now,
    );
    final appUser = AppUser(
      uid: state.user.uid,
      displayName: cleanOwnerName,
      email: state.user.email,
      role: UserRole.superAdmin,
      defaultCompanyId: companyId,
      status: 'active',
    );

    try {
      state = state.copyWith(isSaving: true, clearError: true);
      final batch = db.batch();
      batch.set(db.doc(FirebasePaths.company(companyId)), {
        ...company.toJson(),
        'createdBy': state.user.uid,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'setupCompletedBy': state.user.uid,
        'setupCompletedAt': now.toIso8601String(),
      }, SetOptions(merge: true));
      batch.set(db.doc('${FirebasePaths.members(companyId)}/${state.user.uid}'), member.toJson(), SetOptions(merge: true));
      batch.set(db.doc(FirebasePaths.user(state.user.uid)), appUser.toJson(), SetOptions(merge: true));
      batch.set(db.doc('${FirebasePaths.userMemberships(state.user.uid)}/$companyId'), {
        'companyId': companyId,
        'companyName': company.name,
        'role': UserRole.superAdmin.value,
        'status': 'active',
        'joinedAt': now.toIso8601String(),
      }, SetOptions(merge: true));
      batch.set(db.doc(FirebasePaths.bootstrapSettings(companyId)), {
        'companyId': companyId,
        'firstAdminUid': state.user.uid,
        'firstAdminEmail': state.user.email,
        'firstAdminRole': UserRole.superAdmin.value,
        'status': 'completed',
        'createdAt': now.toIso8601String(),
        'createdBy': state.user.uid,
        'locked': true,
        'source': 'manualSuperAdminCompanySetup',
        'note': 'Company docs were created from the Super Admin company setup form.',
      }, SetOptions(merge: false));
      batch.set(db.doc(FirebasePaths.portalPostSettings(companyId)), DemoData.portalPostSettings.toJson(), SetOptions(merge: true));
      batch.set(db.doc(FirebasePaths.demoDataSettings(companyId)), {
        'demoDataEnabled': false,
        'updatedBy': state.user.uid,
        'updatedAt': now.toIso8601String(),
        'note': 'Disabled by default after Super Admin company setup so production shows only Firestore data.',
      }, SetOptions(merge: true));
      // Mobile UI configuration is platform-global and is intentionally not
      // seeded per company. Platform Super Admin publishes it once from the
      // APK Emulator / Mobile UI Designer for every customer application.
      await batch.commit();

      _firebaseUid = state.user.uid;
      _firebaseCompanyId = companyId;
      _firestoreMembers = <Member>[member];
      _firestoreTeams = const <Team>[];
      _firestoreProjects = const <Project>[];
      _firestoreTasks = const <ProjectTask>[];
      _firestoreNotifications = const <AppNotification>[];
      _firestoreActivity = const <ActivityLog>[];
      _firestoreReports = const <ReportModel>[];
      _firestoreComments = const <TaskComment>[];
      _firestoreAttachments = const <FileAttachment>[];
      _firestoreAuditLogs = const <AuditLog>[];
      state = WorkspaceState.empty(demoDataEnabled: false).copyWith(
        user: appUser,
        company: company,
        members: <Member>[member],
        isRegistrationComplete: true,
        isSaving: false,
        clearError: true,
      );
      _attachFirebaseStreams(companyId);

      NotificationService.setExternalUserId(state.user.uid);
      NotificationService.addTags({
        'companyId': companyId,
        'role': UserRole.superAdmin.value,
        'email': state.user.email,
      });

      final activity = _activity('Company setup completed', '${company.name} was configured by Super Admin $cleanOwnerName.', 'company', companyId);
      final audit = _audit('company.setup.completed', 'company', companyId, after: company.toJson());
      state = state.copyWith(activity: [activity, ...state.activity], auditLogs: [audit, ...state.auditLogs]);
      _persistActivity(activity);
      _persistAudit(audit);
    } catch (error) {
      state = state.copyWith(isSaving: false, lastError: 'Company setup failed: $error');
    }
  }

  void _attachFirebaseStreams(String companyId) {
    _cancelFirebaseSubscriptions();
    final canSeeAllTasks = PermissionService.canViewFullProjectProgress(state.currentMember);
    final canLoadHeavyWorkspaceStreams = state.currentMember.role.isDeliveryManager || state.currentMember.role == UserRole.hrManager;

    final scopedMember = state.currentMember;
    final scopedProjectIds = scopedMember.projectIds;
    final scopedTeamIds = scopedMember.teamIds;

    _firebaseSubscriptions.add(_repository!.watchMembers(
      companyId,
      currentUid: state.user.uid,
      canViewFullProgress: canSeeAllTasks,
      projectIds: scopedProjectIds,
      teamIds: scopedTeamIds,
    ).listen((items) {
      _firestoreMembers = items;
      final displayItems = _displayMembers(items);
      final current = displayItems.where((member) => member.uid == state.user.uid).toList();
      final currentRole = current.isEmpty ? state.user.role : current.first.role;
      state = state.copyWith(
        members: displayItems,
        user: state.user.copyWith(role: currentRole, displayName: current.isEmpty ? state.user.displayName : current.first.displayName),
        clearError: true,
      );
      final nextCanSeeAllTasks = PermissionService.canViewFullProjectProgress(state.currentMember);
      if (nextCanSeeAllTasks != _taskStreamCanSeeAll) {
        _attachTaskStream(companyId, nextCanSeeAllTasks);
      }
    }, onError: (error) => state = state.copyWith(lastError: 'Members stream failed: $error')));

    _firebaseSubscriptions.add(_repository!.watchProjects(
      companyId,
      currentUid: state.user.uid,
      canViewFullProgress: canSeeAllTasks,
      projectIds: scopedProjectIds,
      teamIds: scopedTeamIds,
    ).listen((items) {
      _firestoreProjects = items;
      state = state.copyWith(projects: _displayProjects(items), clearError: true);
    }, onError: (error) => state = state.copyWith(lastError: 'Projects stream failed: $error')));

    _attachTaskStream(companyId, canSeeAllTasks);

    _firebaseSubscriptions.add(_repository!.watchTeams(
      companyId,
      currentUid: state.user.uid,
      canViewFullProgress: canSeeAllTasks,
      projectIds: scopedProjectIds,
      teamIds: scopedTeamIds,
    ).listen((items) {
      _firestoreTeams = items;
      state = state.copyWith(teams: _displayTeams(items), clearError: true);
    }, onError: (error) => state = state.copyWith(lastError: 'Teams stream failed: $error')));

    _firebaseSubscriptions.add(_repository!.watchMyNotifications(companyId, state.user.uid).listen((items) {
      _firestoreNotifications = items;
      state = state.copyWith(notifications: _displayNotifications(items), clearError: true);
    }, onError: (error) => state = state.copyWith(lastError: 'Notifications stream failed: $error')));

    if (canLoadHeavyWorkspaceStreams) {
      _firebaseSubscriptions.add(_repository!.watchActivity(companyId).listen((items) {
        _firestoreActivity = items;
        state = state.copyWith(activity: _displayActivity(items), clearError: true);
      }, onError: (error) => state = state.copyWith(lastError: 'Activity stream failed: $error')));

      _firebaseSubscriptions.add(_repository!.watchAuditLogs(companyId).listen((items) {
        _firestoreAuditLogs = items;
        state = state.copyWith(auditLogs: _displayAuditLogs(items), clearError: true);
      }, onError: (_) {}));

      _firebaseSubscriptions.add(_repository!.watchReports(companyId).listen((items) {
        _firestoreReports = items;
        state = state.copyWith(reports: _displayReports(items), clearError: true);
      }, onError: (error) => state = state.copyWith(lastError: 'Reports stream failed: $error')));

      _firebaseSubscriptions.add(_repository!.watchComments(companyId).listen((items) {
        _firestoreComments = items;
        state = state.copyWith(comments: _displayComments(items), clearError: true);
      }, onError: (error) => state = state.copyWith(lastError: 'Comments stream failed: $error')));

    }

    // Attachments are lightweight Cloudinary metadata, not media bytes. Every
    // role that can see tasks needs this stream so Files works after reload on
    // both APK and web. The actual file remains stored in Cloudinary.
    _firebaseSubscriptions.add(_repository!.watchAttachments(companyId).listen((items) {
      _firestoreAttachments = items;
      state = state.copyWith(attachments: _displayAttachments(items), clearError: true);
    }, onError: (error) => state = state.copyWith(lastError: 'Attachments stream failed: $error')));

    _firebaseSubscriptions.add(FirebaseFirestore.instance.doc(FirebasePaths.portalPostSettings(companyId)).snapshots().listen((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return;
      state = state.copyWith(portalPostSettings: PortalPostSettings.fromJson(snapshot.data()!), clearError: true);
    }, onError: (error) => state = state.copyWith(lastError: 'Portal post settings stream failed: $error')));

    _firebaseSubscriptions.add(FirebaseFirestore.instance.doc(FirebasePaths.demoDataSettings(companyId)).snapshots().listen((snapshot) {
      final data = snapshot.data();
      final enabled = data == null ? false : data['demoDataEnabled'] == true;
      if (enabled != state.demoDataEnabled) {
        _applyDataSourcePreference(enabled);
      }
    }, onError: (error) => state = state.copyWith(lastError: 'Demo data setting stream failed: $error')));

    _firebaseSubscriptions.add(_repository!.watchMobileUiConfig(companyId).listen((config) {
      state = state.copyWith(mobileUiConfig: config, clearError: true);
    }, onError: (error) => state = state.copyWith(lastError: 'Mobile UI config stream failed: $error')));

    _firebaseSubscriptions.add(_repository!.watchMobileUiDesign(companyId).listen((design) {
      final currentConfig = state.mobileUiConfig;
      final designConfig = design
          .toMobileConfig(versionOverride: design.version)
          .preserveRuntimeSafeFieldsFrom(currentConfig);
      final nextConfig = design.version > currentConfig.version ? designConfig : currentConfig;
      state = state.copyWith(
        mobileUiDesign: design,
        mobileUiConfig: nextConfig,
        clearError: true,
      );
    }, onError: (error) => state = state.copyWith(lastError: 'Mobile UI design stream failed: $error')));
  }

  void _attachTaskStream(String companyId, bool canSeeAllTasks) {
    if (_repository == null) return;
    if (_taskStreamCanSeeAll == canSeeAllTasks && _taskSubscription != null) return;
    unawaited(_taskSubscription?.cancel());
    _taskStreamCanSeeAll = canSeeAllTasks;
    final scopedMember = state.currentMember;
    _taskSubscription = _repository!.watchTasks(
      companyId,
      currentUid: state.user.uid,
      canViewFullProgress: canSeeAllTasks,
      projectIds: scopedMember.projectIds,
      teamIds: scopedMember.teamIds,
    ).listen((items) {
      _firestoreTasks = items;
      state = state.copyWith(tasks: _displayTasks(items), clearError: true);
      _recalculateProjectProgress(persist: false);
    }, onError: (error) => state = state.copyWith(lastError: 'Tasks stream failed: $error'));
  }

  void _fireAndForget(Future<void> future, String label) {
    unawaited(future.catchError((Object error) {
      state = state.copyWith(lastError: '$label Firebase write failed: $error');
    }));
  }

  void _persistProject(Project project) {
    if (_firebaseActive) _fireAndForget(_repository!.saveProject(project), 'Project');
  }

  void _persistTask(ProjectTask task) {
    if (_firebaseActive) _fireAndForget(_repository!.saveTask(task), 'Task');
  }

  void _persistTeam(Team team) {
    if (_firebaseActive) _fireAndForget(_repository!.saveTeam(team), 'Task force');
  }

  void _persistMember(Member member) {
    if (_firebaseActive) _fireAndForget(_repository!.saveMember(member), 'Member');
  }

  void _persistNotification(AppNotification notification) {
    if (_firebaseActive) _fireAndForget(_repository!.saveNotification(notification), 'Notification');
  }

  void _persistActivity(ActivityLog log) {
    if (_firebaseActive) _fireAndForget(_repository!.saveActivity(log), 'Activity');
  }

  void _persistAudit(AuditLog log) {
    if (_firebaseActive) _fireAndForget(_repository!.saveAuditLog(log), 'Audit');
  }

  void _persistReport(ReportModel report) {
    if (_firebaseActive) _fireAndForget(_repository!.saveReport(report), 'Report');
  }

  void _persistComment(TaskComment comment) {
    if (_firebaseActive) _fireAndForget(_repository!.saveComment(state.company.companyId, comment), 'Comment');
  }

  void _persistAttachment(FileAttachment attachment) {
    if (_firebaseActive) _fireAndForget(_repository!.saveAttachment(state.company.companyId, attachment), 'Attachment');
  }

  Future<void> updateMobileUiConfig(MobileUiConfig config) async {
    if (!PermissionService.canManageMobileUi(state.currentMember)) {
      state = state.copyWith(lastError: 'Only the Platform Super Admin can change employee mobile UI settings.');
      return;
    }
    final nextVersion = config.version <= state.mobileUiConfig.version ? state.mobileUiConfig.version + 1 : config.version;
    final nextConfig = config.copyWith(version: nextVersion, updatedAt: DateTime.now(), updatedBy: state.user.uid);
    state = state.copyWith(mobileUiConfig: nextConfig, clearError: true);
    final activity = _activity(
      'Mobile UI updated',
      'Global employee mobile UI was updated for all customer applications.',
      'uiConfig',
      'mobileEmployee',
    );
    final audit = _audit(
      'settings.mobileUi.updated',
      'uiConfig',
      'mobileEmployee',
      after: nextConfig.toMap(updatedBy: state.user.uid),
    );
    state = state.copyWith(activity: [activity, ...state.activity], auditLogs: [audit, ...state.auditLogs]);
    if (_firebaseActive) {
      _fireAndForget(_repository!.saveMobileUiConfig(state.company.companyId, nextConfig, updatedBy: state.user.uid), 'Mobile UI config');
    }
    _persistActivity(activity);
    _persistAudit(audit);
  }

  Future<MobileUiDesign?> updateMobileUiDesign(MobileUiDesign design) async {
    if (!PermissionService.canManageMobileUi(state.currentMember)) {
      state = state.copyWith(lastError: 'Only the Platform Super Admin can publish employee mobile UI design.');
      return null;
    }

    try {
      final publishedDesign = _firebaseActive
          ? await _repository!.publishMobileUiDesign(state.company.companyId, design, updatedBy: state.user.uid)
          : design.copyWith(
              version: design.version <= state.mobileUiDesign.version ? state.mobileUiDesign.version + 1 : design.version,
              updatedAt: DateTime.now(),
              updatedBy: state.user.uid,
            );
      final publishedConfig = publishedDesign
          .toMobileConfig(versionOverride: publishedDesign.version)
          .preserveRuntimeSafeFieldsFrom(state.mobileUiConfig);
      state = state.copyWith(mobileUiDesign: publishedDesign, mobileUiConfig: publishedConfig, clearError: true);
      return publishedDesign;
    } catch (error) {
      state = state.copyWith(lastError: 'Mobile UI publish failed: $error');
      return null;
    }
  }

  void setDemoDataEnabled(bool enabled) {
    if (!PermissionService.canManageSettings(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role cannot change demo data settings.');
      return;
    }

    _applyDataSourcePreference(enabled);

    final activity = _activity(
      enabled ? 'Demo data enabled' : 'Demo data disabled',
      enabled
          ? 'Admin enabled demo overlay. Firestore records still remain the source of persisted data.'
          : 'Admin disabled demo overlay. The portal now renders only documents streamed from Firestore.',
      'settings',
      'demoData',
    );
    final audit = _audit(
      enabled ? 'settings.demoData.enabled' : 'settings.demoData.disabled',
      'settings',
      'demoData',
      after: <String, dynamic>{'demoDataEnabled': enabled},
    );

    state = state.copyWith(
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );

    if (_firebaseActive) {
      _fireAndForget(
        FirebaseFirestore.instance.doc(FirebasePaths.demoDataSettings(state.company.companyId)).set({
          'demoDataEnabled': enabled,
          'updatedBy': state.user.uid,
          'updatedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true)),
        'Demo data setting',
      );
    }
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void setPortalPostActive(UserRole role, bool isActive) {
    if (!PermissionService.canManageSettings(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role cannot change portal post settings.');
      return;
    }
    if (!role.canBePortalDeactivated && !isActive) {
      state = state.copyWith(lastError: '${role.label} is a protected post and cannot be deactivated.');
      return;
    }

    final enabled = state.portalPostSettings.enabledRoleValues.toSet();
    if (isActive) {
      enabled.add(role.value);
    } else {
      enabled.remove(role.value);
    }
    for (final coreRole in UserRole.values.where((item) => item.isCorePortalPost)) {
      enabled.add(coreRole.value);
    }

    final nextSettings = state.portalPostSettings.copyWith(
      enabledRoleValues: enabled.toList()..sort(),
      updatedBy: state.user.uid,
      updatedAt: DateTime.now(),
    );

    final affectedMembers = state.members.where((member) => member.role == role).length;
    final activity = _activity(
      isActive ? 'Portal post activated' : 'Portal post deactivated',
      '${role.label} was ${isActive ? 'activated' : 'deactivated'} for the company portal. Affected members: $affectedMembers.',
      'settings',
      'portalPosts',
    );
    final audit = _audit(
      isActive ? 'portal.post.activated' : 'portal.post.deactivated',
      'settings',
      'portalPosts',
      after: nextSettings.toJson(),
    );
    state = state.copyWith(
      portalPostSettings: nextSettings,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    if (_firebaseActive) {
      _fireAndForget(FirebaseFirestore.instance.doc(FirebasePaths.portalPostSettings(state.company.companyId)).set(nextSettings.toJson(), SetOptions(merge: true)), 'Portal post settings');
    }
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void selectDemoUser(String uid) {
    final nextUser = DemoData.userFor(uid);
    if (!state.isPortalPostActive(nextUser.role)) {
      state = state.copyWith(lastError: '${nextUser.role.label} is deactivated by IT Admin.');
      return;
    }
    final now = DateTime.now();
    final updatedMembers = state.members.map((member) {
      if (member.uid != nextUser.uid) return member;
      return member.copyWith(isOnline: true, lastSeenAt: now);
    }).toList();
    state = state.copyWith(
      user: nextUser,
      members: updatedMembers,
      activity: [
        _activity('Demo role switched', 'Signed in as ${nextUser.role.label}.', 'member', nextUser.uid),
        ...state.activity,
      ],
      clearError: true,
    );

    NotificationService.setExternalUserId(nextUser.uid);
    NotificationService.addTags({
      'companyId': state.company.companyId,
      'role': nextUser.role.value,
      'email': nextUser.email,
    });
  }

  void createProject({
    required String name,
    required String description,
    required DateTime dueDate,
    required TaskPriority priority,
    required num budget,
    List<String> teamIds = const [],
    List<String> managerIds = const [],
  }) {
    if (!PermissionService.canManageProjects(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role cannot create projects.');
      return;
    }
    final now = DateTime.now();
    final project = Project(
      projectId: IdGenerator.make('project'),
      companyId: state.company.companyId,
      name: name.trim(),
      description: description.trim(),
      status: ProjectStatus.planning,
      priority: priority,
      startDate: now,
      dueDate: dueDate,
      progress: ProjectStatus.planning.stageProgressFloor,
      totalTasks: 0,
      completedTasks: 0,
      managerIds: managerIds.isEmpty ? [state.user.uid] : managerIds,
      teamIds: teamIds,
      budget: budget,
      createdAt: now,
      updatedAt: now,
    );
    final activity = _activity('Project created', '${project.name} was created.', 'project', project.projectId);
    final audit = _audit('project.created', 'project', project.projectId, after: project.toJson());
    state = state.copyWith(
      projects: [project, ...state.projects],
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    _persistProject(project);
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void updateProjectStatus(String projectId, ProjectStatus status) {
    Project? before;
    Project? after;
    final updated = state.projects.map((project) {
      if (project.projectId != projectId) return project;
      before = project;
      after = project.copyWith(status: status, updatedAt: DateTime.now());
      return after!;
    }).toList();
    final activity = _activity('Project updated', '${before?.name ?? 'Project'} moved to ${status.label}.', 'project', projectId);
    final audit = _audit('project.status.changed', 'project', projectId, before: {'status': before?.status.value}, after: {'status': status.value});
    state = state.copyWith(
      projects: updated,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    _recalculateProjectProgress();
    if (after != null) _persistProject(after!);
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void archiveProject(String projectId) {
    Project? archived;
    final updated = state.projects.map((project) {
      if (project.projectId != projectId) return project;
      archived = project.copyWith(isArchived: true, updatedAt: DateTime.now());
      return archived!;
    }).toList();
    final activity = _activity('Project archived', '${archived?.name ?? 'A project'} was archived.', 'project', projectId);
    final audit = _audit('project.archived', 'project', projectId);
    state = state.copyWith(
      projects: updated,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    if (archived != null) _persistProject(archived!);
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void createTask({
    required String title,
    required String description,
    required String projectId,
    required String teamId,
    required TaskPriority priority,
    required DateTime dueDate,
    required List<String> assignedToIds,
    num estimatedHours = 0,
    String? meetingLink,
    bool includeAdminsInMeetingInvite = true,
    String? customPushTitle,
    String? customPushMessage,
  }) {
    if (!PermissionService.canCreateTasks(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role cannot create tasks.');
      return;
    }
    final invalidAssignee = assignedToIds.where((uid) {
      final matches = state.members.where((item) => item.uid == uid).toList();
      if (matches.isEmpty) return true;
      return !state.isPortalPostActive(matches.first.role);
    }).toList();
    if (invalidAssignee.isNotEmpty) {
      state = state.copyWith(lastError: 'Task assignee belongs to a deactivated portal post. Activate the post first.');
      return;
    }
    final now = DateTime.now();
    final task = ProjectTask(
      taskId: IdGenerator.make('task'),
      companyId: state.company.companyId,
      projectId: projectId,
      teamId: teamId,
      title: title.trim(),
      description: description.trim(),
      status: TaskStatus.todo,
      priority: priority,
      assignedToIds: assignedToIds,
      createdBy: state.user.uid,
      reporterId: state.user.uid,
      dueDate: dueDate,
      kanbanRank: now.microsecondsSinceEpoch.toString(),
      createdAt: now,
      updatedAt: now,
      estimatedHours: estimatedHours,
      attachments: const <FileAttachment>[],
      attachmentNames: const <String>[],
    );
    final createdNotifications = _taskCreatedNotifications(
      task,
      meetingLink: meetingLink,
      includeAdminsInMeetingInvite: includeAdminsInMeetingInvite,
    );
    final activity = _activity('Task created', '${task.title} was created.', 'task', task.taskId);
    final audit = _audit('task.created', 'task', task.taskId, after: task.toJson());
    state = state.copyWith(
      tasks: [task, ...state.tasks],
      notifications: [...createdNotifications, ...state.notifications],
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    _persistTask(task);
    for (final notification in createdNotifications) {
      _persistNotification(notification);
    }
    _persistActivity(activity);
    _persistAudit(audit);
    _recalculateProjectProgress();

    final targetRecipients = assignedToIds
        .where((uid) => uid.trim().isNotEmpty && uid != state.user.uid)
        .toList();

    if (targetRecipients.isNotEmpty) {
      final pushTitle = (customPushTitle != null && customPushTitle.trim().isNotEmpty)
          ? customPushTitle.trim()
          : 'New Task Assigned: ${task.title}';
      final pushMessage = (customPushMessage != null && customPushMessage.trim().isNotEmpty)
          ? customPushMessage.trim()
          : '${state.user.displayName} assigned you a new task.';

      unawaited(OneSignalApiService.sendPushToUsers(
        recipientUids: targetRecipients,
        title: pushTitle,
        message: pushMessage,
        additionalData: {
          'taskId': task.taskId,
          'projectId': task.projectId,
          'type': 'taskAssigned',
          'route': '/notifications',
        },
      ));
    }
  }

  void updateTaskTimelineDates(String taskId, {required DateTime startDate, required DateTime dueDate}) {
    if (!PermissionService.canEditTimeline(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role can view the timeline but cannot change schedule dates.');
      return;
    }
    ProjectTask? before;
    ProjectTask? after;
    final safeStart = DateTime(startDate.year, startDate.month, startDate.day);
    final safeDue = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final normalizedDue = safeDue.isBefore(safeStart) ? safeStart : safeDue;
    final updatedTasks = state.tasks.map((task) {
      if (task.taskId != taskId) return task;
      before = task;
      after = task.copyWith(startDate: safeStart, dueDate: normalizedDue, updatedAt: DateTime.now());
      return after!;
    }).toList();
    if (after == null) {
      state = state.copyWith(lastError: 'Task not found for timeline update.');
      return;
    }
    final activity = _activity('Timeline updated', '${after!.title} schedule moved to ${safeStart.toIso8601String().split('T').first} - ${normalizedDue.toIso8601String().split('T').first}.', 'task', taskId);
    final audit = _audit('task.timeline.dates.changed', 'task', taskId, before: {
      'startDate': before?.startDate?.toIso8601String(),
      'dueDate': before?.dueDate.toIso8601String(),
    }, after: {
      'startDate': safeStart.toIso8601String(),
      'dueDate': normalizedDue.toIso8601String(),
    });
    state = state.copyWith(
      tasks: updatedTasks,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    _persistTask(after!);
    _persistActivity(activity);
    _persistAudit(audit);
    _recalculateProjectProgress();
  }

  void updateTaskTimelineConfiguration({
    required String taskId,
    List<String>? dependencyTaskIds,
    DateTime? baselineStartDate,
    DateTime? baselineDueDate,
    bool? isMilestone,
    int? progressPercent,
    String? riskLevel,
    bool clearBaseline = false,
  }) {
    if (!PermissionService.canEditTimeline(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role can view the timeline but cannot change schedule intelligence.');
      return;
    }
    ProjectTask? before;
    ProjectTask? after;
    final validTaskIds = state.tasks.map((task) => task.taskId).toSet();
    List<String>? normalizedDependencies;
    if (dependencyTaskIds != null) {
      normalizedDependencies = dependencyTaskIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty && id != taskId && validTaskIds.contains(id))
          .toSet()
          .toList();
      normalizedDependencies.sort();
    }
    final safeProgress = progressPercent?.clamp(0, 100).toInt();
    final normalizedRiskLevel = riskLevel == null
        ? null
        : (riskLevel.trim().isEmpty ? 'normal' : riskLevel.trim().toLowerCase());
    final updatedTasks = state.tasks.map((task) {
      if (task.taskId != taskId) return task;
      before = task;
      final safeBaselineStart = baselineStartDate == null
          ? null
          : DateTime(baselineStartDate.year, baselineStartDate.month, baselineStartDate.day);
      final rawBaselineDue = baselineDueDate == null
          ? null
          : DateTime(baselineDueDate.year, baselineDueDate.month, baselineDueDate.day);
      final safeBaselineDue = safeBaselineStart != null && rawBaselineDue != null && rawBaselineDue.isBefore(safeBaselineStart)
          ? safeBaselineStart
          : rawBaselineDue;
      after = task.copyWith(
        dependencyTaskIds: normalizedDependencies,
        baselineStartDate: safeBaselineStart,
        baselineDueDate: safeBaselineDue,
        clearBaseline: clearBaseline,
        isMilestone: isMilestone,
        progressPercent: safeProgress,
        riskLevel: normalizedRiskLevel,
        updatedAt: DateTime.now(),
      );
      return after!;
    }).toList();
    if (after == null) {
      state = state.copyWith(lastError: 'Task not found for timeline update.');
      return;
    }
    final activity = _activity('Timeline intelligence updated', '${after!.title} dependencies, baseline, milestone, or progress settings were updated.', 'task', taskId);
    final audit = _audit('task.timeline.configuration.changed', 'task', taskId, before: {
      'dependencyTaskIds': before?.dependencyTaskIds,
      'baselineStartDate': before?.baselineStartDate?.toIso8601String(),
      'baselineDueDate': before?.baselineDueDate?.toIso8601String(),
      'isMilestone': before?.isMilestone,
      'progressPercent': before?.progressPercent,
      'riskLevel': before?.riskLevel,
    }, after: {
      'dependencyTaskIds': after!.dependencyTaskIds,
      'baselineStartDate': after!.baselineStartDate?.toIso8601String(),
      'baselineDueDate': after!.baselineDueDate?.toIso8601String(),
      'isMilestone': after!.isMilestone,
      'progressPercent': after!.progressPercent,
      'riskLevel': after!.riskLevel,
    });
    state = state.copyWith(
      tasks: updatedTasks,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    _persistTask(after!);
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void setTaskBaselineFromCurrent(String taskId) {
    ProjectTask? selectedTask;
    for (final task in state.tasks) {
      if (task.taskId == taskId) {
        selectedTask = task;
        break;
      }
    }
    if (selectedTask == null) {
      state = state.copyWith(lastError: 'Task not found for baseline update.');
      return;
    }
    final start = selectedTask.startDate ??
        selectedTask.createdAt ??
        selectedTask.dueDate.subtract(const Duration(days: 2));
    updateTaskTimelineConfiguration(
      taskId: taskId,
      baselineStartDate: start,
      baselineDueDate: selectedTask.dueDate,
    );
  }

  void updateTaskStatus(String taskId, TaskStatus status) {
    if (!PermissionService.canMoveKanban(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role cannot move Kanban tasks.');
      return;
    }
    ProjectTask? before;
    ProjectTask? after;
    final updatedTasks = state.tasks.map((task) {
      if (task.taskId != taskId) return task;
      before = task;
      after = task.copyWith(
        status: status,
        kanbanRank: DateTime.now().microsecondsSinceEpoch.toString(),
        updatedAt: DateTime.now(),
        completedAt: status == TaskStatus.completed ? DateTime.now() : null,
      );
      return after!;
    }).toList();

    final additionalNotifications = after == null ? <AppNotification>[] : _taskStatusNotifications(after!, status);
    final activity = _activity('Task status updated', '${after?.title ?? 'Task'} moved to ${status.label}.', 'task', taskId);
    final audit = _audit('task.status.changed', 'task', taskId, before: {'status': before?.status.value}, after: {'status': status.value});
    state = state.copyWith(
      tasks: updatedTasks,
      notifications: [...additionalNotifications, ...state.notifications],
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    if (after != null) _persistTask(after!);
    for (final notification in additionalNotifications) {
      _persistNotification(notification);
    }
    _persistActivity(activity);
    _persistAudit(audit);
    _recalculateProjectProgress();
  }

  ProjectTask _stopWorkTimerOnTask(ProjectTask task, DateTime now) {
    final startedAt = task.activeWorkTimerStartedAt;
    final elapsedSeconds = startedAt == null ? 0 : now.difference(startedAt).inSeconds;
    final addedHours = elapsedSeconds <= 0 ? 0.0 : elapsedSeconds / 3600.0;
    final nextLogged = double.parse((task.loggedHours.toDouble() + addedHours).toStringAsFixed(2));
    return task.copyWith(
      loggedHours: nextLogged,
      updatedAt: now,
      clearActiveWorkTimer: true,
    );
  }

  void startTaskWorkTimer(String taskId) {
    _startTaskWorkTimerInternal(taskId, source: 'manual', notifyErrors: true);
  }

  void startTaskWorkTimerFromNotification(String taskId) {
    _startTaskWorkTimerInternal(taskId, source: 'notification.accepted', notifyErrors: false);
  }

  void _startTaskWorkTimerInternal(String taskId, {required String source, required bool notifyErrors}) {
    final cleanTaskId = taskId.trim();
    if (cleanTaskId.isEmpty) return;
    final task = _findTask(cleanTaskId);
    if (task == null) {
      if (notifyErrors) state = state.copyWith(lastError: 'Task not found for work timer.');
      return;
    }
    final currentUid = state.user.uid;
    if (!task.assignedToIds.contains(currentUid)) {
      if (notifyErrors) state = state.copyWith(lastError: 'Only assigned users can start the work counter for this task.');
      return;
    }
    if (task.status == TaskStatus.completed) {
      if (notifyErrors) state = state.copyWith(lastError: 'Completed tasks cannot start a new work counter.');
      return;
    }
    if (task.isWorkTimerRunning && task.activeWorkTimerUserId != currentUid) {
      if (notifyErrors) state = state.copyWith(lastError: 'This task is already being tracked by another user.');
      return;
    }
    if (task.isWorkTimerRunning && task.activeWorkTimerUserId == currentUid) {
      if (notifyErrors) state = state.copyWith(clearError: true);
      return;
    }

    final now = DateTime.now();
    final changed = <ProjectTask>[];
    final updatedTasks = state.tasks.map((item) {
      ProjectTask next = item;
      if (item.isWorkTimerRunning && item.activeWorkTimerUserId == currentUid) {
        next = _stopWorkTimerOnTask(item, now);
      }
      if (item.taskId == cleanTaskId) {
        next = next.copyWith(
          status: next.status == TaskStatus.backlog || next.status == TaskStatus.todo ? TaskStatus.inProgress : next.status,
          activeWorkTimerUserId: currentUid,
          activeWorkTimerStartedAt: now,
          updatedAt: now,
        );
      }
      if (next != item) changed.add(next);
      return next;
    }).toList();

    final activityTitle = source == 'notification.accepted' ? 'Work counter auto-started' : 'Work counter started';
    final activity = _activity(activityTitle, '${task.title} work counter started by ${state.user.displayName}.', 'task', cleanTaskId);
    final audit = _audit('task.workTimer.started', 'task', cleanTaskId, after: {
      'activeWorkTimerUserId': currentUid,
      'activeWorkTimerStartedAt': now.toIso8601String(),
      'source': source,
    });
    state = state.copyWith(
      tasks: updatedTasks,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    for (final changedTask in changed) {
      _persistTask(changedTask);
    }
    _persistActivity(activity);
    _persistAudit(audit);
    _recalculateProjectProgress();
  }

  void stopTaskWorkTimer(String taskId) {
    final task = _findTask(taskId);
    if (task == null) {
      state = state.copyWith(lastError: 'Task not found for work timer.');
      return;
    }
    final currentUid = state.user.uid;
    if (!task.isWorkTimerRunning) {
      state = state.copyWith(clearError: true);
      return;
    }
    if (task.activeWorkTimerUserId != currentUid && !PermissionService.canAssignTasks(state.currentMember)) {
      state = state.copyWith(lastError: 'Only the active assignee or a manager can stop this work counter.');
      return;
    }

    final now = DateTime.now();
    ProjectTask? stoppedTask;
    final updatedTasks = state.tasks.map((item) {
      if (item.taskId != taskId) return item;
      stoppedTask = _stopWorkTimerOnTask(item, now);
      return stoppedTask!;
    }).toList();
    final addedSeconds = task.activeWorkTimerStartedAt == null ? 0 : now.difference(task.activeWorkTimerStartedAt!).inSeconds;
    final addedMinutes = (addedSeconds / 60).round().clamp(0, 999999).toInt();
    final activity = _activity('Work counter stopped', '${task.title} work counter stopped. Added ${addedMinutes}m.', 'task', taskId);
    final audit = _audit('task.workTimer.stopped', 'task', taskId, after: {
      'loggedHours': stoppedTask?.loggedHours,
      'addedMinutes': addedMinutes,
    });
    state = state.copyWith(
      tasks: updatedTasks,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    if (stoppedTask != null) _persistTask(stoppedTask!);
    _persistActivity(activity);
    _persistAudit(audit);
    _recalculateProjectProgress();
  }

  void assignTaskToMember(
    String taskId,
    String memberId, {
    String? customPushTitle,
    String? customPushMessage,
  }) {
    if (!PermissionService.canAssignTasks(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role cannot assign tasks.');
      return;
    }
    final targetMember = state.members.where((member) => member.uid == memberId).toList();
    if (targetMember.isEmpty || !state.isPortalPostActive(targetMember.first.role)) {
      state = state.copyWith(lastError: 'Selected member post is deactivated. Activate that post before assigning work.');
      return;
    }
    final task = state.tasks.firstWhere((item) => item.taskId == taskId);
    final wasAlreadyAssigned = task.assignedToIds.contains(memberId) && task.assignedToIds.length == 1;
    final updatedTask = task.copyWith(assignedToIds: [memberId], updatedAt: DateTime.now());

    final updatedTasks = state.tasks.map((item) => item.taskId == taskId ? updatedTask : item).toList();
    final newNotification = wasAlreadyAssigned ? null : _buildTaskAssignedNotification(updatedTask, memberId);
    final nextNotifications = newNotification == null ? state.notifications : [newNotification, ...state.notifications];
    final assignedMember = _memberName(memberId);
    final activity = _activity('Task assigned', '${updatedTask.title} was assigned to $assignedMember.', 'task', updatedTask.taskId);
    final audit = _audit('task.assignee.changed', 'task', taskId, before: {'assignedToIds': task.assignedToIds}, after: {'assignedToIds': [memberId]});

    state = state.copyWith(
      tasks: updatedTasks,
      notifications: nextNotifications,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    _persistTask(updatedTask);
    if (newNotification != null) _persistNotification(newNotification);
    _persistActivity(activity);
    _persistAudit(audit);
    _recalculateProjectProgress();

    if (memberId.trim().isNotEmpty && memberId != state.user.uid) {
      final pushTitle = (customPushTitle != null && customPushTitle.trim().isNotEmpty)
          ? customPushTitle.trim()
          : 'Task Assigned to You';
      final pushMessage = (customPushMessage != null && customPushMessage.trim().isNotEmpty)
          ? customPushMessage.trim()
          : '${updatedTask.title} has been assigned to you by ${state.user.displayName}.';

      unawaited(OneSignalApiService.sendPushToUsers(
        recipientUids: [memberId.trim()],
        title: pushTitle,
        message: pushMessage,
        additionalData: {
          'taskId': updatedTask.taskId,
          'projectId': updatedTask.projectId,
          'type': 'taskAssigned',
          'route': '/notifications',
        },
      ));
    }
  }

  void deleteTask(String taskId) {
    final task = state.tasks.firstWhere((item) => item.taskId == taskId);
    final activity = _activity('Task deleted', '${task.title} was removed.', 'task', taskId);
    final audit = _audit('task.deleted', 'task', taskId, before: task.toJson());
    state = state.copyWith(
      tasks: state.tasks.where((item) => item.taskId != taskId).toList(),
      comments: state.comments.where((item) => item.taskId != taskId).toList(),
      attachments: state.attachments.where((item) => item.taskId != taskId).toList(),
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    if (_firebaseActive) unawaited(_repository!.deleteTask(state.company.companyId, taskId));
    _persistActivity(activity);
    _persistAudit(audit);
    _recalculateProjectProgress();
  }

  void addTaskComment(String taskId, String message) {
    final comment = TaskComment(
      commentId: IdGenerator.make('comment'),
      taskId: taskId,
      authorId: state.user.uid,
      message: message.trim(),
      createdAt: DateTime.now(),
    );
    final task = state.tasks.firstWhere((item) => item.taskId == taskId);
    ProjectTask? updatedTask;
    final updatedTasks = state.tasks.map((item) {
      if (item.taskId != taskId) return item;
      updatedTask = item.copyWith(commentsCount: item.commentsCount + 1, updatedAt: DateTime.now());
      return updatedTask!;
    }).toList();
    final activity = _activity('Comment added', 'A comment was added on ${task.title}.', 'task', taskId);
    final audit = _audit('task.comment.created', 'task', taskId, after: comment.toJson());
    state = state.copyWith(
      comments: [comment, ...state.comments],
      tasks: updatedTasks,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    _persistComment(comment);
    if (updatedTask != null) _persistTask(updatedTask!);
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void addAttachmentMetadata(String taskId, String fileName, String fileType, int sizeBytes) {
    final task = _findTask(taskId);
    if (task == null) {
      state = state.copyWith(lastError: 'Task not found for file attachment.');
      return;
    }
    final attachmentId = IdGenerator.make('attachment');
    final safeName = _safeStorageFileName(fileName);
    _commitAttachment(
      task: task,
      attachment: FileAttachment(
        attachmentId: attachmentId,
        taskId: taskId,
        projectId: task.projectId,
        uploadedBy: state.user.uid,
        fileName: fileName.trim().isEmpty ? safeName : fileName.trim(),
        fileType: _normalizeBusinessMimeType(safeName, fileType),
        fileSize: sizeBytes,
        publicId: 'cloudinary_manual_$attachmentId',
        createdAt: DateTime.now(),
        secureUrl: '',
      ),
    );
  }

  Future<bool> addAttachmentFromDevicePicker(
    String taskId, {
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final task = _findTask(taskId);
    if (task == null) {
      state = state.copyWith(lastError: 'Task not found for file upload.');
      return false;
    }

    state = state.copyWith(clearError: true);

    try {
      final picked = await AndroidFilePickerService.pickBusinessFile();
      if (picked == null) return false;
      return addAttachmentBytes(
        taskId: taskId,
        fileName: picked.name,
        fileType: picked.mimeType,
        bytes: picked.bytes,
        onProgress: onProgress,
      );
    } on PlatformException catch (error) {
      state = state.copyWith(lastError: _filePickerErrorMessage(error));
      return false;
    } catch (error) {
      state = state.copyWith(lastError: 'File picker failed: $error');
      return false;
    }
  }

  Future<bool> addAttachmentBytes({
    required String taskId,
    required String fileName,
    required String fileType,
    required Uint8List bytes,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final task = _findTask(taskId);
    if (task == null) {
      state = state.copyWith(lastError: 'Task not found for file upload.');
      return false;
    }
    if (bytes.isEmpty) {
      state = state.copyWith(lastError: 'Selected file is empty.');
      return false;
    }
    if (bytes.lengthInBytes > AndroidFilePickerService.maxBusinessFileBytes) {
      state = state.copyWith(lastError: 'Selected file is larger than 25 MB.');
      return false;
    }

    final attachmentId = IdGenerator.make('attachment');
    final safeName = _safeStorageFileName(fileName);
    final contentType = _normalizeBusinessMimeType(safeName, fileType);
    if (!AndroidFilePickerService.allowedMimeTypes.contains(contentType)) {
      state = state.copyWith(
        lastError: 'Unsupported file type. Use PDF, image, Word, Excel, or text files.',
      );
      return false;
    }

    final storagePath = _taskAttachmentStoragePath(
      companyId: state.company.companyId,
      taskId: taskId,
      attachmentId: attachmentId,
      safeName: safeName,
    );

    state = state.copyWith(
      isSaving: true,
      uploadingTaskId: taskId,
      clearError: true,
    );
    onProgress?.call(0, bytes.lengthInBytes);

    try {
      final uploadResult = await _uploadTaskAttachmentAndGetUrl(
        storagePath: storagePath,
        bytes: bytes,
        contentType: contentType,
        originalName: fileName.trim().isEmpty ? safeName : fileName.trim(),
        onProgress: onProgress,
      );

      final attachment = FileAttachment(
        attachmentId: attachmentId,
        taskId: taskId,
        projectId: task.projectId,
        uploadedBy: state.user.uid,
        fileName: fileName.trim().isEmpty ? safeName : fileName.trim(),
        fileType: contentType,
        fileSize: bytes.lengthInBytes,
        publicId: uploadResult.storagePath,
        secureUrl: uploadResult.downloadUrl,
        createdAt: DateTime.now(),
      );

      // Do not show success until the Cloudinary URL metadata is durable.
      await _commitAttachment(task: task, attachment: attachment);

      state = state.copyWith(
        isSaving: false,
        clearUploadingTaskId: true,
        clearError: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        isSaving: false,
        clearUploadingTaskId: true,
        lastError: 'File upload failed: $error',
      );
      return false;
    }
  }

  ProjectTask? _findTask(String taskId) {
    for (final task in state.tasks) {
      if (task.taskId == taskId) return task;
    }
    return null;
  }

  Future<void> _commitAttachment({
    required ProjectTask task,
    required FileAttachment attachment,
  }) async {
    ProjectTask? updatedTask;
    final updatedTasks = state.tasks.map((item) {
      if (item.taskId != task.taskId) return item;

      final deduped = <String, FileAttachment>{
        for (final existing in item.attachments) existing.attachmentId: existing,
        attachment.attachmentId: attachment,
      };
      final nextAttachments = deduped.values.toList();
      final nextAttachmentNames = nextAttachments.map((item) => item.fileName).toList();

      updatedTask = item.copyWith(
        attachments: nextAttachments,
        attachmentNames: nextAttachmentNames,
        attachmentsCount: nextAttachments.length,
        updatedAt: DateTime.now(),
      );
      return updatedTask!;
    }).toList();

    // Cloudinary stores the media. Firestore stores only the URL/file metadata
    // required to make the attachment visible on every device after reload.
    if (_firebaseActive) {
      Object? lastMetadataError;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await _repository!.saveAttachment(state.company.companyId, attachment);
          lastMetadataError = null;
          break;
        } catch (error) {
          lastMetadataError = error;
          if (attempt < 2) {
            await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
          }
        }
      }
      if (lastMetadataError != null) {
        throw StateError('Cloudinary uploaded the file, but attachment metadata could not be saved: $lastMetadataError');
      }

      // Keep the task-level mirror/count in sync when rules permit it. The
      // attachment subcollection above is the durable source of truth.
      if (updatedTask != null) {
        try {
          await _repository!.saveTask(updatedTask!);
        } catch (_) {
          // Older rules may allow attachmentsCount but not the nested metadata.
          // The always-on attachment stream still keeps Files consistent.
        }
      }
    }

    final activity = _activity(
      'File attached',
      '${attachment.fileName} was attached to ${task.title}.',
      'task',
      task.taskId,
    );
    final audit = _audit(
      'task.attachment.created',
      'task',
      task.taskId,
      after: attachment.toJson(),
    );

    final attachmentMap = <String, FileAttachment>{
      for (final existing in state.attachments) existing.attachmentId: existing,
      attachment.attachmentId: attachment,
    };

    state = state.copyWith(
      attachments: attachmentMap.values.toList(),
      tasks: updatedTasks,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );

    _persistActivity(activity);
    _persistAudit(audit);
  }

  static String _safeStorageFileName(String fileName) {
    final trimmed = fileName.trim().isEmpty ? 'attachment' : fileName.trim();
    final safe = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'_+'), '_');
    final clipped = safe.length > 96 ? safe.substring(safe.length - 96) : safe;
    return clipped.trim().isEmpty ? 'attachment' : clipped;
  }

  static String _taskAttachmentStoragePath({
    required String companyId,
    required String taskId,
    required String attachmentId,
    required String safeName,
  }) {
    return 'companies/$companyId/tasks/$taskId/attachments/$attachmentId/$safeName';
  }

  Future<_AttachmentUploadResult> _uploadTaskAttachmentAndGetUrl({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    required String originalName,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    try {
      final cloudinaryResult = await CloudinaryUploadService().uploadFile(
        bytes: bytes,
        fileName: originalName.trim().isEmpty ? 'attachment' : originalName.trim(),
        contentType: contentType,
        onProgress: onProgress,
      );

      return _AttachmentUploadResult(
        downloadUrl: cloudinaryResult.secureUrl,
        storagePath: cloudinaryResult.publicId,
      );
    } catch (error) {
      throw StateError('Cloudinary file upload failed: $error');
    }
  }

  static String _normalizeBusinessMimeType(String fileName, String rawMimeType) {
    final cleaned = rawMimeType.trim().toLowerCase();
    if (AndroidFilePickerService.allowedMimeTypes.contains(cleaned)) return cleaned;
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  static String _filePickerErrorMessage(PlatformException error) {
    return switch (error.code) {
      'FILE_TOO_LARGE' => 'Selected file is larger than 25 MB.',
      'PICKER_BUSY' => 'File picker is already open.',
      'PICKER_OPEN_FAILED' => 'Could not open Android file picker.',
      'FILE_READ_FAILED' => 'Could not read selected file.',
      'MissingPluginException' => 'File picker is available only in the Android APK build.',
      _ => error.message ?? 'File picker failed.',
    };
  }

  void createTeam({required String name, required String leadId, List<String> memberIds = const []}) {
    if (!PermissionService.canManageTaskForces(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role cannot create task forces.');
      return;
    }
    final selectedMemberIds = {...memberIds, leadId}.toList()..sort();
    final team = Team(
      teamId: IdGenerator.make('team'),
      name: name.trim(),
      leadId: leadId,
      memberIds: selectedMemberIds,
      activeProjectIds: const [],
      description: 'Company task force',
    );
    final updatedMembers = state.members.map((member) {
      if (!selectedMemberIds.contains(member.uid)) return member;
      final teamIds = {...member.teamIds, team.teamId}.toList()..sort();
      return member.copyWith(teamIds: teamIds);
    }).toList();
    final activity = _activity('Task force created', '${team.name} was created with ${selectedMemberIds.length} members.', 'team', team.teamId);
    final audit = _audit('team.created', 'team', team.teamId, after: team.toJson());
    state = state.copyWith(
      teams: [team, ...state.teams],
      members: updatedMembers,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    _persistTeam(team);
    for (final member in updatedMembers.where((member) => selectedMemberIds.contains(member.uid))) {
      _persistMember(member);
    }
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void updateMemberAppraisal({
    required String memberId,
    required int score,
    required String notes,
    required String status,
  }) {
    if (!PermissionService.canEditAppraisal(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role can view appraisals but cannot change them.');
      return;
    }
    final safeScore = score.clamp(0, 100).toInt();
    final now = DateTime.now();
    Member? before;
    Member? after;
    final updatedMembers = state.members.map((member) {
      if (member.uid != memberId) return member;
      before = member;
      after = member.copyWith(
        appraisalScore: safeScore,
        appraisalNotes: notes.trim(),
        appraisalStatus: status.trim().isEmpty ? 'reviewed' : status.trim(),
        appraisalUpdatedAt: now,
        appraisalUpdatedBy: state.user.uid,
      );
      return after!;
    }).toList();
    if (after == null) {
      state = state.copyWith(lastError: 'Employee not found for appraisal update.');
      return;
    }
    final activity = _activity('Appraisal updated', '${after!.displayName} appraisal score updated to $safeScore%.', 'member', memberId);
    final audit = _audit('member.appraisal.updated', 'member', memberId, before: {
      'appraisalScore': before?.appraisalScore,
      'appraisalStatus': before?.appraisalStatus,
    }, after: {
      'appraisalScore': safeScore,
      'appraisalStatus': after!.appraisalStatus,
      'appraisalUpdatedAt': now.toIso8601String(),
      'appraisalUpdatedBy': state.user.uid,
    });
    state = state.copyWith(
      members: updatedMembers,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    _persistMember(after!);
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void updateMemberAppraisalDetails({
    required String memberId,
    required int score,
    required String notes,
    required String status,
    required String templateId,
    required Map<String, int> competencyScores,
    required String selfReview,
    required String managerReview,
    required String peerReview,
    required String appraisalPeriod,
  }) {
    if (!PermissionService.canEditAppraisal(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role can view appraisals but cannot change them.');
      return;
    }
    final safeScore = score.clamp(0, 100).toInt();
    final normalizedCompetencies = <String, int>{};
    for (final entry in competencyScores.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      normalizedCompetencies[key] = entry.value.clamp(0, 100).toInt();
    }
    final now = DateTime.now();
    Member? before;
    Member? after;
    final updatedMembers = state.members.map((member) {
      if (member.uid != memberId) return member;
      before = member;
      after = member.copyWith(
        previousAppraisalScore: member.appraisalScore,
        appraisalScore: safeScore,
        appraisalNotes: notes.trim(),
        appraisalStatus: status.trim().isEmpty ? 'reviewed' : status.trim(),
        appraisalTemplateId: templateId.trim(),
        appraisalCompetencyScores: normalizedCompetencies,
        appraisalSelfReview: selfReview.trim(),
        appraisalManagerReview: managerReview.trim(),
        appraisalPeerReview: peerReview.trim(),
        appraisalPeriod: appraisalPeriod.trim(),
        appraisalUpdatedAt: now,
        appraisalUpdatedBy: state.user.uid,
      );
      return after!;
    }).toList();
    if (after == null) {
      state = state.copyWith(lastError: 'Employee not found for appraisal update.');
      return;
    }
    final activity = _activity('Detailed appraisal updated', '${after!.displayName} appraisal was updated for ${after!.appraisalPeriod.isEmpty ? 'the current period' : after!.appraisalPeriod}.', 'member', memberId);
    final audit = _audit('member.appraisal.details.updated', 'member', memberId, before: {
      'appraisalScore': before?.appraisalScore,
      'appraisalStatus': before?.appraisalStatus,
      'appraisalTemplateId': before?.appraisalTemplateId,
      'appraisalPeriod': before?.appraisalPeriod,
    }, after: {
      'appraisalScore': safeScore,
      'appraisalStatus': after!.appraisalStatus,
      'appraisalTemplateId': after!.appraisalTemplateId,
      'appraisalCompetencyScores': after!.appraisalCompetencyScores,
      'appraisalPeriod': after!.appraisalPeriod,
      'appraisalUpdatedAt': now.toIso8601String(),
      'appraisalUpdatedBy': state.user.uid,
    });
    state = state.copyWith(
      members: updatedMembers,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    _persistMember(after!);
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void setMyOnlineStatus(bool isOnline) {
    final now = DateTime.now();
    Member? updatedMember;
    final updatedMembers = state.members.map((member) {
      if (member.uid != state.user.uid) return member;
      updatedMember = member.copyWith(
        isOnline: isOnline,
        lastSeenAt: now,
      );
      return updatedMember!;
    }).toList();
    final activity = _activity(isOnline ? 'Employee came online' : 'Employee went offline', '${state.user.displayName} is now ${isOnline ? 'online' : 'offline'}.', 'member', state.user.uid);
    final audit = _audit('member.presence.updated', 'member', state.user.uid, after: {'isOnline': isOnline, 'lastSeenAt': now.toIso8601String()});
    state = state.copyWith(
      members: updatedMembers,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    if (updatedMember != null) _persistMember(updatedMember!);
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void setMyAvailability(bool available) {
    Member? updatedMember;
    final updatedMembers = state.members.map((member) {
      if (member.uid != state.user.uid) return member;
      updatedMember = member.copyWith(available: available, lastSeenAt: DateTime.now());
      return updatedMember!;
    }).toList();
    final activity = _activity('Availability updated', '${state.user.displayName} is now ${available ? 'available' : 'busy'}.', 'member', state.user.uid);
    final audit = _audit('member.availability.updated', 'member', state.user.uid, after: {'available': available});
    state = state.copyWith(
      members: updatedMembers,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    if (updatedMember != null) _persistMember(updatedMember!);
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void setMyNotificationDisplayWindow({
    required String mode,
    int? days,
    int? hours,
  }) {
    final normalized = mode.trim().isEmpty ? 'currentMonth' : mode.trim();
    final nextPrefs = <String, dynamic>{
      ...state.user.notificationPreferences,
      'displayWindowMode': normalized,
      'notificationDisplayWindowMode': normalized,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (days != null) {
      final cleanDays = days.clamp(1, 3660).toInt();
      nextPrefs['displayWindowDays'] = cleanDays;
      nextPrefs['notificationDisplayDays'] = cleanDays;
    }
    if (hours != null) {
      final cleanHours = hours.clamp(1, 24 * 3660).toInt();
      nextPrefs['displayWindowHours'] = cleanHours;
      nextPrefs['notificationDisplayHours'] = cleanHours;
    }

    final nextUser = state.user.copyWith(notificationPreferences: nextPrefs);
    final audit = _audit('user.notification_window.updated', 'user', state.user.uid, after: <String, dynamic>{
      'notificationPreferences': nextPrefs,
    });
    state = state.copyWith(
      user: nextUser,
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    if (_firebaseActive) {
      _fireAndForget(
        updateConditionalUserDoc(
          uid: state.user.uid,
          dataToUpdate: <String, dynamic>{
            'notificationPreferences': nextPrefs,
            'updatedAt': DateTime.now().toIso8601String(),
          },
        ),
        'User notification display window preference',
      );
    }
    _persistAudit(audit);
  }

  void updateMyProfile({
    required String displayName,
    required String email,
    String? phone,
    String? department,
    String? jobTitle,
    String? location,
  }) {
    final cleanName = displayName.trim().isEmpty ? state.user.displayName : displayName.trim();
    final cleanEmail = email.trim().isEmpty ? state.user.email : email.trim();
    final nextUser = state.user.copyWith(displayName: cleanName, email: cleanEmail, phone: phone?.trim());
    Member? updatedMember;
    final updatedMembers = state.members.map((member) {
      if (member.uid != state.user.uid) return member;
      updatedMember = member.copyWith(
        displayName: cleanName,
        email: cleanEmail,
        department: department?.trim().isEmpty == true ? null : department?.trim(),
        jobTitle: jobTitle?.trim().isEmpty == true ? null : jobTitle?.trim(),
        location: location?.trim().isEmpty == true ? member.location : location?.trim(),
      );
      return updatedMember!;
    }).toList();
    final activity = _activity('Profile updated', '$cleanName updated personal profile details.', 'member', state.user.uid);
    final audit = _audit('member.profile.updated', 'member', state.user.uid, after: nextUser.toJson());
    state = state.copyWith(
      user: nextUser,
      members: updatedMembers,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    if (updatedMember != null) _persistMember(updatedMember!);

    if (_firebaseActive && state.user.uid.isNotEmpty) {
      _fireAndForget(
        updateConditionalUserDoc(
          uid: state.user.uid,
          dataToUpdate: nextUser.toJson(),
        ),
        'User profile',
      );
    }
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void updateMemberRole({required String uid, required UserRole role}) {
    if (!PermissionService.canManagePeople(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role cannot upgrade or downgrade employee roles.');
      return;
    }
    if (!state.isPortalPostActive(role)) {
      state = state.copyWith(lastError: '${role.label} is deactivated in Portal Post Control. Activate it before assigning this role.');
      return;
    }
    if (uid == state.user.uid) {
      state = state.copyWith(lastError: 'You cannot change your own role from this screen. Ask another admin to do it.');
      return;
    }

    final target = state.members.where((member) => member.uid == uid).toList();
    if (target.isEmpty) {
      state = state.copyWith(lastError: 'Employee not found.');
      return;
    }
    final beforeMember = target.first;
    if ((beforeMember.role == UserRole.superAdmin || role == UserRole.superAdmin) && state.currentMember.role != UserRole.superAdmin) {
      state = state.copyWith(lastError: 'Only Super Admin can assign or change Super Admin roles.');
      return;
    }
    if (beforeMember.role == role) {
      state = state.copyWith(clearError: true);
      return;
    }

    Member? updatedMember;
    final updatedMembers = state.members.map((member) {
      if (member.uid != uid) return member;
      updatedMember = member.copyWith(
        role: role,
        department: role.department,
        jobTitle: role.label,
        lastSeenAt: DateTime.now(),
      );
      return updatedMember!;
    }).toList();
    final activity = _activity('Employee role changed', '${beforeMember.displayName} moved from ${beforeMember.role.label} to ${role.label}.', 'member', uid);
    final audit = _audit('member.role.changed', 'member', uid, before: {'role': beforeMember.role.value}, after: {'role': role.value});
    state = state.copyWith(
      members: updatedMembers,
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    if (updatedMember != null) _persistMember(updatedMember!);
    if (_firebaseActive) {
      _fireAndForget(
        updateConditionalUserDoc(
          uid: uid,
          dataToUpdate: {
            'role': role.value,
            'department': role.department,
            'jobTitle': role.label,
            'updatedAt': DateTime.now().toIso8601String(),
            'updatedBy': state.user.uid,
          },
        ),
        'User role',
      );
      final inviteId = _inviteIdForEmail(beforeMember.email);
      _fireAndForget(
        FirebaseFirestore.instance.doc(FirebasePaths.invite(state.company.companyId, inviteId)).set({
          'role': role.value,
          'department': role.department,
          'jobTitle': role.label,
          'updatedAt': DateTime.now().toIso8601String(),
          'updatedBy': state.user.uid,
        }, SetOptions(merge: true)),
        'Employee invite role',
      );
    }
    _persistActivity(activity);
    _persistAudit(audit);
  }

  void addMember({required String name, required String email, required UserRole role}) {
    addEmployeeWithTaskForce(name: name, email: email, role: role);
  }

  void addEmployeeWithTaskForce({
    required String name,
    required String email,
    required UserRole role,
    String? department,
    String? jobTitle,
    String? location,
    num capacityHoursPerWeek = 40,
    String? taskForceName,
    List<String> taskForceMemberIds = const [],
  }) {
    if (!PermissionService.canInviteMembers(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role cannot invite members.');
      return;
    }
    if (!state.isPortalPostActive(role)) {
      state = state.copyWith(lastError: '${role.label} is deactivated in Portal Post Control. Activate it before inviting users.');
      return;
    }
    final member = Member(
      uid: IdGenerator.make('user'),
      displayName: name.trim(),
      email: email.trim(),
      role: role,
      status: 'active',
      capacityHoursPerWeek: capacityHoursPerWeek,
      department: department?.trim().isEmpty == true ? null : department?.trim(),
      jobTitle: jobTitle?.trim().isEmpty == true ? null : jobTitle?.trim(),
      location: location?.trim().isEmpty == true ? 'Remote' : location?.trim() ?? 'Remote',
      available: true,
      isOnline: false,
    );

    Team? taskForce;
    var nextMembers = [member, ...state.members];
    if ((taskForceName ?? '').trim().isNotEmpty) {
      final memberIds = {...taskForceMemberIds, member.uid}.toList()..sort();
      taskForce = Team(
        teamId: IdGenerator.make('team'),
        name: taskForceName!.trim(),
        leadId: member.uid,
        memberIds: memberIds,
        activeProjectIds: const [],
        description: 'Company task force created by HR onboarding',
      );
      nextMembers = nextMembers.map((item) {
        if (!memberIds.contains(item.uid)) return item;
        return item.copyWith(teamIds: {...item.teamIds, taskForce!.teamId}.toList()..sort());
      }).toList();
    }

    final activity = _activity(
      taskForce == null ? 'Member invited' : 'Employee and task force created',
      taskForce == null ? '${member.displayName} was added as ${role.label}.' : '${member.displayName} was added as ${role.label} and ${taskForce.name} was created.',
      'member',
      member.uid,
    );
    final audit = _audit('member.created', 'member', member.uid, after: member.toJson());
    final teamAudit = taskForce == null ? null : _audit('team.created', 'team', taskForce.teamId, after: taskForce.toJson());

    state = state.copyWith(
      members: nextMembers,
      teams: taskForce == null ? state.teams : [taskForce, ...state.teams],
      activity: [activity, ...state.activity],
      auditLogs: [audit, if (teamAudit != null) teamAudit, ...state.auditLogs],
      clearError: true,
    );
    for (final item in nextMembers.where((item) => item.uid == member.uid || (taskForce?.memberIds.contains(item.uid) ?? false))) {
      _persistMember(item);
    }
    if (_firebaseActive) {
      final inviteId = _inviteIdForEmail(member.email);
      _fireAndForget(
        FirebaseFirestore.instance.doc(FirebasePaths.invite(state.company.companyId, inviteId)).set({
          'inviteId': inviteId,
          'email': member.email,
          'displayName': member.displayName,
          'role': member.role.value,
          'status': 'active',
          'department': member.effectiveDepartment,
          'jobTitle': member.effectiveJobTitle,
          'location': member.location,
          'capacityHoursPerWeek': member.capacityHoursPerWeek,
          'teamIds': member.teamIds,
          'projectIds': member.projectIds,
          'createdBy': state.user.uid,
          'createdAt': DateTime.now().toIso8601String(),
          'note': 'When this email registers/signs in, the app automatically claims this invite and creates the real Auth UID member document.',
        }, SetOptions(merge: true)),
        'Employee invite',
      );
    }
    if (taskForce != null) _persistTeam(taskForce);
    _persistActivity(activity);
    _persistAudit(audit);
    if (teamAudit != null) _persistAudit(teamAudit);
  }

  ReportModel? generateReport(
    String reportType, {
    String? monthId,
    String? projectId,
    Map<String, dynamic> metrics = const <String, dynamic>{},
    DateTime? snapshotGeneratedAt,
    bool isSnapshotFinalized = false,
  }) {
    if (!PermissionService.canGenerateReports(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role cannot generate reports.');
      return null;
    }
    final now = DateTime.now();
    final normalizedMonthId = (monthId ?? '').trim().isEmpty
        ? '${now.year}-${now.month.toString().padLeft(2, '0')}'
        : monthId!.trim();
    final normalizedProjectId = (projectId ?? '').trim().isEmpty ? null : projectId!.trim();
    final safeType = reportType.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final scopeSuffix = normalizedProjectId == null ? 'all_projects' : normalizedProjectId;

    final activeCompanyName = state.company.name.isNotEmpty && state.company.name != 'Company Workspace'
        ? state.company.name
        : 'Company Workspace';
    final finalMetrics = <String, dynamic>{
      ...metrics,
      'companyName': activeCompanyName,
    };

    final report = ReportModel(
      reportId: IdGenerator.make('report'),
      reportType: reportType,
      period: normalizedMonthId,
      status: 'generated',
      createdAt: now,
      generatedBy: state.user.uid,
      pdfPath: 'companies/${state.company.companyId}/reports/$normalizedMonthId/${safeType}_$scopeSuffix.pdf',
      xlsxPath: 'companies/${state.company.companyId}/reports/$normalizedMonthId/${safeType}_$scopeSuffix.xlsx',
      monthId: normalizedMonthId,
      projectId: normalizedProjectId,
      projectScope: normalizedProjectId == null ? 'all' : 'project',
      snapshotGeneratedAt: snapshotGeneratedAt,
      isSnapshotFinalized: isSnapshotFinalized,
      metrics: finalMetrics,
    );
    final activity = _activity(
      'Report generated',
      '$reportType report was generated for $normalizedMonthId (${normalizedProjectId == null ? 'all projects' : 'one project'}).',
      'report',
      report.reportId,
    );
    final audit = _audit('report.generated', 'report', report.reportId, after: report.toJson());
    state = state.copyWith(
      reports: [report, ...state.reports],
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );
    _persistReport(report);
    _persistActivity(activity);
    _persistAudit(audit);
    return report;
  }

  void markNotificationRead(String notificationId) {
    AppNotification? updated;
    state = state.copyWith(
      notifications: state.notifications.map((notification) {
        if (notification.notificationId != notificationId) return notification;
        if (!state.isNotificationVisibleToCurrentUser(notification)) return notification;
        updated = notification.copyWith(isRead: true);
        return updated!;
      }).toList(),
    );
    if (updated != null) _persistNotification(updated!);
  }

  void acceptNotificationAndStartWorkCounter(String notificationId) {
    AppNotification? accepted;
    AppNotification? updated;
    state = state.copyWith(
      notifications: state.notifications.map((notification) {
        if (notification.notificationId != notificationId) return notification;
        if (!state.isNotificationVisibleToCurrentUser(notification)) return notification;
        accepted = notification;
        updated = notification.copyWith(isRead: true);
        return updated!;
      }).toList(),
    );
    if (updated != null) _persistNotification(updated!);
    final notification = accepted;
    final taskId = notification?.taskId?.trim() ?? '';
    if (notification != null && taskId.isNotEmpty && _shouldStartWorkCounterOnNotificationAccept(notification)) {
      startTaskWorkTimerFromNotification(taskId);
    }
  }

  bool _shouldStartWorkCounterOnNotificationAccept(AppNotification notification) {
    final normalizedType = notification.type.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    return normalizedType == 'taskassigned' || normalizedType == 'newtaskassigned';
  }

  void markAllMyNotificationsRead() {
    final updated = <AppNotification>[];
    state = state.copyWith(
      notifications: state.notifications.map((notification) {
        if (!state.isNotificationVisibleToCurrentUser(notification)) return notification;
        final next = notification.copyWith(isRead: true);
        updated.add(next);
        return next;
      }).toList(),
    );
    for (final notification in updated) {
      _persistNotification(notification);
    }
  }

  void createMeetingInvite({
    required String title,
    required String agenda,
    required String meetingLink,
    required List<String> recipientIds,
    bool includeAdmins = true,
  }) {
    if (!PermissionService.canCreateMeetings(state.currentMember)) {
      state = state.copyWith(lastError: 'Your role cannot create meeting invites.');
      return;
    }

    final safeMeetingLink = _safeMeetingUrl(meetingLink);
    if (safeMeetingLink == null) {
      state = state.copyWith(lastError: 'Add a valid Google Meet, WhatsApp, or HTTPS meeting link.');
      return;
    }

    final recipients = <String>{
      ...recipientIds.where((uid) => uid.trim().isNotEmpty),
    };
    if (includeAdmins) {
      recipients.addAll(
        state.members
            .where((member) => member.status == 'active' && member.role.isAdminLike)
            .map((member) => member.uid),
      );
    }

    recipients.removeWhere((uid) {
      if (uid.trim().isEmpty) return true;
      final matches = state.members.where((member) => member.uid == uid).toList();
      if (matches.isEmpty) return true;
      return !state.isPortalPostActive(matches.first.role);
    });

    if (recipients.isEmpty) {
      state = state.copyWith(lastError: 'Select at least one active recipient or keep admin access enabled.');
      return;
    }

    final now = DateTime.now();
    final cleanTitle = title.trim().isEmpty ? 'Meeting invite' : title.trim();
    final cleanAgenda = agenda.trim().isEmpty ? 'Please join the meeting.' : agenda.trim();
    final actionType = safeMeetingLink.toLowerCase().contains('whatsapp') ? 'whatsappMeeting' : 'googleMeet';

    final createdNotifications = recipients.map((uid) {
      return AppNotification(
        notificationId: IdGenerator.make('meeting'),
        title: cleanTitle,
        message: '${state.currentMember.displayName} invited you to a meeting. $cleanAgenda',
        type: 'meetingInvite',
        recipientId: uid,
        companyId: state.company.companyId,
        actorId: state.user.uid,
        actionUrl: safeMeetingLink,
        actionLabel: 'Accept & Join',
        rejectLabel: 'Reject',
        actionType: actionType,
        createdAt: now,
        expiresAt: state.notificationExpiryFor(now),
      );
    }).toList();

    final activity = _activity('Meeting invite created', '$cleanTitle was sent to ${createdNotifications.length} recipient(s).', 'meeting', createdNotifications.first.notificationId);
    final audit = _audit('meeting.invite.created', 'meeting', createdNotifications.first.notificationId, after: {
      'title': cleanTitle,
      'agenda': cleanAgenda,
      'meetingUrl': safeMeetingLink,
      'recipientIds': recipients.toList(),
      'includeAdmins': includeAdmins,
      'actionType': actionType,
    });

    state = state.copyWith(
      notifications: [...createdNotifications, ...state.notifications],
      activity: [activity, ...state.activity],
      auditLogs: [audit, ...state.auditLogs],
      clearError: true,
    );

    for (final notification in createdNotifications) {
      _persistNotification(notification);
    }
    _persistActivity(activity);
    _persistAudit(audit);

    final targetUids = recipients
        .where((uid) => uid.trim().isNotEmpty && uid != state.user.uid)
        .toList();

    if (targetUids.isNotEmpty) {
      unawaited(OneSignalApiService.sendPushToUsers(
        recipientUids: targetUids,
        title: 'Meeting Invite: $cleanTitle',
        message: '${state.currentMember.displayName} invited you to a meeting.',
        additionalData: {
          'meetingUrl': safeMeetingLink,
          'type': 'meetingInvite',
          'route': '/notifications',
        },
      ));
    }
  }

  List<AppNotification> _taskCreatedNotifications(
    ProjectTask task, {
    String? meetingLink,
    bool includeAdminsInMeetingInvite = true,
  }) {
    final notifications = task.assignedToIds.map((uid) => _buildTaskAssignedNotification(task, uid)).toList();
    final safeMeetingLink = _safeMeetingUrl(meetingLink);
    if (safeMeetingLink != null) {
      final recipients = <String>{...task.assignedToIds};
      if (includeAdminsInMeetingInvite) {
        recipients.addAll(_adminMeetingRecipientIds(task.projectId));
      }
      recipients.removeWhere((uid) => uid.trim().isEmpty || uid == state.user.uid);
      for (final uid in recipients) {
        notifications.add(_buildMeetingInviteNotification(task, uid, safeMeetingLink));
      }
    }
    return notifications;
  }

  List<String> _adminMeetingRecipientIds(String projectId) {
    return state.members
        .where((member) => member.status == 'active' && (member.role.isAdminLike || member.projectIds.contains(projectId)))
        .map((member) => member.uid)
        .where((uid) => uid.trim().isNotEmpty)
        .toSet()
        .toList();
  }

  String? _safeMeetingUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (lower.startsWith('https://') || lower.startsWith('http://') || lower.startsWith('whatsapp://')) return value;
    if (lower.startsWith('meet.google.com/') ||
        lower.startsWith('wa.me/') ||
        lower.startsWith('api.whatsapp.com/') ||
        lower.startsWith('chat.whatsapp.com/')) {
      return 'https://$value';
    }
    return null;
  }

  List<AppNotification> _taskStatusNotifications(ProjectTask task, TaskStatus status) {
    if (task.assignedToIds.isEmpty) return const [];
    final now = DateTime.now();
    final expiresAt = state.notificationExpiryFor(now);
    final title = status == TaskStatus.completed ? 'Task completed' : 'Task updated';
    final message = status == TaskStatus.completed ? '${task.title} is now completed.' : '${task.title} moved to ${status.label}.';
    return task.assignedToIds
        .where((uid) => uid != state.user.uid)
        .map((uid) => AppNotification(
              notificationId: IdGenerator.make('notification'),
              title: title,
              message: message,
              type: status == TaskStatus.completed ? 'taskCompleted' : 'taskUpdated',
              recipientId: uid,
              companyId: state.company.companyId,
              projectId: task.projectId,
              taskId: task.taskId,
              actorId: state.user.uid,
              createdAt: now,
              expiresAt: expiresAt,
            ))
        .toList();
  }

  AppNotification _buildTaskAssignedNotification(ProjectTask task, String recipientId) {
    final project = state.projects.firstWhere((project) => project.projectId == task.projectId);
    final now = DateTime.now();
    return AppNotification(
      notificationId: IdGenerator.make('notification'),
      title: 'Task assigned to you',
      message: '${task.title} in ${project.name} has been assigned to you.',
      type: 'taskAssigned',
      recipientId: recipientId,
      companyId: state.company.companyId,
      projectId: task.projectId,
      taskId: task.taskId,
      actorId: state.user.uid,
      createdAt: now,
      expiresAt: state.notificationExpiryFor(now),
    );
  }

  AppNotification _buildMeetingInviteNotification(ProjectTask task, String recipientId, String meetingUrl) {
    final project = state.projects.firstWhere((project) => project.projectId == task.projectId);
    final now = DateTime.now();
    return AppNotification(
      notificationId: IdGenerator.make('meeting'),
      title: 'Meeting invite',
      message: '${state.currentMember.displayName} invited you to join ${task.title} in ${project.name}.',
      type: 'meetingInvite',
      recipientId: recipientId,
      companyId: state.company.companyId,
      projectId: task.projectId,
      taskId: task.taskId,
      actorId: state.user.uid,
      actionUrl: meetingUrl,
      actionLabel: 'Accept & Join',
      rejectLabel: 'Reject',
      actionType: meetingUrl.toLowerCase().contains('whatsapp') ? 'whatsappMeeting' : 'googleMeet',
      createdAt: now,
      expiresAt: state.notificationExpiryFor(now),
    );
  }

  ActivityLog _activity(String title, String description, String targetType, String targetId) => ActivityLog(
        activityLogId: IdGenerator.make('activity'),
        title: title,
        description: description,
        actorId: state.user.uid,
        targetType: targetType,
        targetId: targetId,
        createdAt: DateTime.now(),
      );

  AuditLog _audit(String action, String targetType, String targetId, {Map<String, dynamic>? before, Map<String, dynamic>? after}) => AuditLog(
        auditLogId: IdGenerator.make('audit'),
        action: action,
        actorId: state.user.uid,
        targetType: targetType,
        targetId: targetId,
        before: before,
        after: after,
        createdAt: DateTime.now(),
      );

  String _memberName(String memberId) {
    final matches = state.members.where((member) => member.uid == memberId);
    return matches.isEmpty ? 'Unknown member' : matches.first.displayName;
  }

  int _stageBasedProjectProgress(Project project, List<ProjectTask> projectTasks) {
    if (project.status == ProjectStatus.completed) return 100;
    if (project.status == ProjectStatus.cancelled) return 0;
    final total = projectTasks.length;
    final taskPercent = total == 0 ? 0 : ((projectTasks.where((task) => task.status == TaskStatus.completed).length / total) * 100).round();
    final stageFloor = project.status.stageProgressFloor;
    if (project.status == ProjectStatus.planning) return taskPercent.clamp(stageFloor, 30).toInt();
    if (project.status == ProjectStatus.onHold) return taskPercent.clamp(stageFloor, 75).toInt();
    if (project.status == ProjectStatus.review) return taskPercent.clamp(stageFloor, 98).toInt();
    return taskPercent.clamp(stageFloor, 99).toInt();
  }

  void _recalculateProjectProgress({bool persist = true}) {
    final updatedProjects = state.projects.map((project) {
      final projectTasks = state.tasks.where((task) => task.projectId == project.projectId).toList();
      final completed = projectTasks.where((task) => task.status == TaskStatus.completed).length;
      final total = projectTasks.length;
      final progress = _stageBasedProjectProgress(project, projectTasks);
      final nextStatus = total > 0 && completed == total
          ? ProjectStatus.completed
          : project.status == ProjectStatus.completed
              ? ProjectStatus.review
              : project.status;
      return project.copyWith(totalTasks: total, completedTasks: completed, progress: progress, status: nextStatus, updatedAt: DateTime.now());
    }).toList();
    state = state.copyWith(projects: updatedProjects);
    if (persist) {
      for (final project in updatedProjects) {
        _persistProject(project);
      }
    }
  }
}

class _AttachmentUploadResult {
  const _AttachmentUploadResult({required this.downloadUrl, required this.storagePath});

  final String downloadUrl;
  final String storagePath;
}

final workspaceProvider = StateNotifierProvider<WorkspaceController, WorkspaceState>((ref) {
  return WorkspaceController(repository: AppConfig.useFirebase ? FirebaseWorkspaceRepository() : null);
});
final currentSectionProvider = StateProvider<MainSection>((ref) => MainSection.dashboard);
final selectedProjectIdProvider = StateProvider<String?>((ref) => null);