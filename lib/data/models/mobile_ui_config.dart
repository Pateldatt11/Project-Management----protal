import 'dart:convert';

import '../../core/utils/json_value.dart';

class MobileUiConfig {
  const MobileUiConfig({
    required this.enabled,
    required this.version,
    required this.bottomTabs,
    required this.topNav,
    required this.homeCards,
    required this.taskCardFields,
    required this.projectCardFields,
    required this.taskCardVariant,
    required this.projectCardVariant,
    required this.taskListConfig,
    required this.profileActions,
    required this.compactMode,
    this.inboxConfig = defaultInboxConfig,
    this.profileFields = defaultProfileFields,
    this.supportedWidgets = defaultSupportedWidgets,
    this.notificationAlertConfig = defaultNotificationAlertConfig,
    this.notificationSoundOptions = defaultNotificationSoundOptions,
    this.designSystem = defaultDesignSystem,
    this.animationConfig = defaultAnimationConfig,
    this.layoutConfig = defaultLayoutConfig,
    this.navigationConfig = defaultNavigationConfig,
    this.bottomNav = defaultBottomNav,
    this.floatingTopNav = defaultFloatingTopNav,
    this.floatingBottomNav = defaultFloatingBottomNav,
    this.quickActionDock = defaultQuickActionDock,
    this.sideMenuConfig = defaultSideMenuConfig,
    this.homeLayout = defaultHomeLayout,
    this.homeCardConfig = defaultHomeCardConfig,
    this.screenConfigs = defaultScreenConfigs,
    this.screenOverrides = const <String, dynamic>{},
    this.screenRegistry = const <String, dynamic>{},
    this.navigationGraph = const <String, dynamic>{},
    this.profileCardConfig = defaultProfileCardConfig,
    this.projectListConfig = defaultProjectListConfig,
    this.dataBindings = defaultDataBindings,
    this.rendererCompatibility = defaultRendererCompatibility,
    this.authUiPolicy = defaultAuthUiPolicy,
    this.texts = const <String, dynamic>{},
    this.updatedAt,
    this.updatedBy,
  });

  final bool enabled;
  final int version;
  final List<String> bottomTabs;
  final Map<String, dynamic> topNav;
  final List<String> homeCards;
  final List<String> taskCardFields;
  final List<String> projectCardFields;
  final String taskCardVariant;
  final String projectCardVariant;
  final Map<String, dynamic> taskListConfig;
  final Map<String, dynamic> profileActions;
  final Map<String, dynamic> inboxConfig;
  final List<String> profileFields;
  final List<String> supportedWidgets;
  final Map<String, dynamic> notificationAlertConfig;
  final Map<String, dynamic> notificationSoundOptions;
  final Map<String, dynamic> designSystem;
  final Map<String, dynamic> animationConfig;
  final Map<String, dynamic> layoutConfig;
  final Map<String, dynamic> navigationConfig;
  final Map<String, dynamic> bottomNav;
  final Map<String, dynamic> floatingTopNav;
  final Map<String, dynamic> floatingBottomNav;
  final Map<String, dynamic> quickActionDock;
  final Map<String, dynamic> sideMenuConfig;
  final Map<String, dynamic> homeLayout;
  final Map<String, dynamic> homeCardConfig;
  final Map<String, dynamic> screenConfigs;
  final Map<String, dynamic> screenOverrides;
  final Map<String, dynamic> screenRegistry;
  final Map<String, dynamic> navigationGraph;
  final Map<String, dynamic> profileCardConfig;
  final Map<String, dynamic> projectListConfig;
  final Map<String, dynamic> dataBindings;
  final Map<String, dynamic> rendererCompatibility;
  final Map<String, dynamic> authUiPolicy;
  final Map<String, dynamic> texts;
  final bool compactMode;
  final DateTime? updatedAt;
  final String? updatedBy;

  static const List<String> allowedBottomTabs = <String>[
    'home',
    'tasks',
    'projects',
    'board',
    'meetings',
    'notifications',
    'profile',
  ];

  static const List<String> allowedCardVariants = <String>[
    'modernCard',
    'minimalCard',
    'compactCard',
    'timelineCard',
    'progressCard',
    'advancedProgressCard',
    'nativeListRow',
    'editorialProgressCard',
    'editorialStatusCard',
    'editorialProjectRow',
    'darkEditorialHero',
    'smallMetricTile',
    'softProgressCard',
    'wireframeProjectFeedCard',
    'wireframeProfileSettings',
    'taskDetailHeader',
    'compactHeader',
    'safeCard',
    'safeFallbackCard',
    'plainCard',
    'outlineCard',
    'filledCard',
  ];

  static const List<String> allowedHomeCards = <String>[
    'workSummary',
    'deadlineTimer',
    'myOpenTasks',
    'todayTasks',
    'projectProgress',
    'activeProjectsGrid',
    'projectMetrics',
    'onlineStatus',
  ];

  static const List<String> allowedTaskCardFields = <String>[
    'projectName',
    'taskTitle',
    'status',
    'statusTag',
    'priority',
    'deadlineTimer',
    'progress',
    'description',
    'assignedBy',
    'commentsCount',
    'filesCount',
    'attachmentsCount',
    'assigneeCount',
  ];

  static const List<String> allowedProjectCardFields = <String>[
    'projectName',
    'taskCount',
    'completedTaskCount',
    'progress',
    'deadline',
    'status',
    'statusTag',
    'team',
    'teamCount',
    'description',
    'priority',
  ];

  static const List<String> defaultProfileFields = <String>[
    'name',
    'email',
    'phone',
    'companyName',
    'role',
    'department',
    'onlineStatus',
    'joinedAt',
  ];

  static const List<String> defaultSupportedWidgets = <String>[
    'topNav',
    'homeCards',
    'deadlineHero',
    'metricTile',
    'activeProjectsGrid',
    'taskCard',
    'projectCard',
    'taskPage',
    'taskList',
    'projectPage',
    'projectList',
    'profileCard',
    'inbox',
    'notificationAlert',
    'notificationSoundSelector',
    'notificationDisplayWindow',
    'floatingBottomNav',
    'floatingTopNav',
    'quickActionDock',
    'hamburgerMenu',
    'sideMenu',
    'sideNavigationMenu',
    'floatingSideSheet',
    'filterChips',
    'searchHeader',
    'progressTimeline',
    'statusPill',
    'emptyState',
    'skeletonLoader',
    'nativeSheet',
    'meetingList',
    'superAdminMeetingCreator',
    'meetingCreateForm',
    'sduiTemplate',
    'meetingPage',
    'meetingInviteCard',
    'adminMeetingAccess',
    'meetingLinkInput',
    'meetingActionButtons',
    'templateScreen',
    'templateSection',
    'jsonFirstSafeControls',
    'rendererSafety',
    'jsonRenderPolicy',
    'safeRenderer',
    'safeFallbackCard',
    'unknownWidgetSafeCard',
    'unsupportedWidgetMode',
    'hideUnsupportedBanner',
    'nodeRecovery',
    'safeNodeBoundary',
    'summaryStats',
    'metricCards',
    'summaryCards',
    'jsonControlledStats',
    'responsiveGrid',
    'cardGrid',
    'metricGrid',
    'statsGrid',
    'wrap',
    'hStack',
    'vStack',
    'section',
    'safeArea',
    'padding',
    'margin',
    'visibility',
    'listTile',
    'infoRow',
    'switchTile',
    'avatar',
    'lottie',
    'lottieIcon',
    'menuLottie',
    'oneShotMenuAnimation',
  ];

  static const Map<String, dynamic> defaultAuthUiPolicy = <String, dynamic>{
    'enabled': true,
    'newLoginSignupEnabled': true,
    'jsonControlsAuthUi': true,
    'applyTo': <String>['android', 'ios'],
    'disableOnWeb': true,
    'webUsesLegacyAuth': true,
    'adminPreviewCanRenderMobileAuth': true,
    'allowEmailPassword': true,
    'allowSignUp': true,
    'allowPasswordReset': true,
    'methods': <String>[
      'emailPassword',
      'signUp',
      'passwordReset',
      'google',
      'apple',
      'facebook',
    ],
    'labels': <String, dynamic>{
      'loginTitle': 'Welcome back',
      'signupTitle': 'Create your workspace account',
      'loginSubtitle': 'Sign in to continue to your project dashboard.',
      'signupSubtitle': 'Use company email to request access or create the first admin account.',
      'loginButton': 'Login',
      'signupButton': 'Create account',
      'forgotPassword': 'Forgot password?',
      'otherWays': 'Other ways to sign in',
      'securityNote': 'Protected with rate limiting and Firebase security checks.',
    },
    'bruteForceProtection': <String, dynamic>{
      'enabled': true,
      'useCloudFunctions': true,
      'localFallback': true,
      'maxLoginFailures': 5,
      'maxSignupFailures': 3,
      'maxResetRequests': 3,
      'windowMinutes': 15,
      'lockoutMinutes': 15,
      'maxLockoutMinutes': 60,
      'genericAuthErrors': true,
      'lockedMessage': 'Too many attempts. Please wait and try again.',
    },
  };

  static const Map<String, dynamic> defaultSideMenuConfig = <String, dynamic>{
    'enabled': false,
    'trigger': 'topNavHamburger',
    'presentation': 'floatingSideSheet',
    'source': 'screenRegistry',
    'title': 'All Screens',
    'subtitle': 'Open any workspace screen',
    'showMainTabs': true,
    'showNestedScreens': true,
    'groupBy': 'section',
    'respectRolePermissions': true,
    'mainGroupLabel': 'Main',
    'moreGroupLabel': 'More',
  };

  static const Map<String, dynamic> defaultInboxConfig = <String, dynamic>{
    'enabled': true,
    'source': 'notifications',
    'showUnreadCount': true,
    'allowMarkRead': true,
    'allowMarkAllRead': true,
    'openFromTopNav': true,
  };

  static const Map<String, dynamic> defaultNotificationAlertConfig = <String, dynamic>{
    'enabled': true,
    'showInProfile': true,
    'showTestButton': true,
    'allowUserSelection': true,
    'defaultSoundName': 'emergency_alarm',
    'loopUntilAccept': true,
    'assistantVoice': true,
    'assistantText': 'You are assigned a new task. Please accept the notification.',
    'lockScreenEnabled': true,
    'notificationCenterEnabled': true,
    'acceptButtonEnabled': true,
    'meetingActionsEnabled': true,
    'meetingLinkSupport': true,
    'googleMeetEnabled': true,
    'whatsappMeetingEnabled': true,
    'adminMeetingAccess': true,
    'includeAdminsOnMeetingInvite': true,
    'acceptJoinLabel': 'Accept & Join',
    'rejectLabel': 'Reject',
    // Notification history/display window. Default keeps inbox, badge count,
    // page search, meetings, and Android bridge scoped to the current month.
    // Admin/user config can publish displayWindowMode: currentMonth, customDays,
    // customHours, or all. Existing docs can also set expiresAt/visibleUntil.
    'displayWindowMode': 'currentMonth',
    'displayWindowDays': 31,
    'displayWindowHours': 24,
    'hideExpiredNotifications': true,
    'allowUserDisplayWindowSelection': true,
  };

  static const Map<String, dynamic> defaultNotificationSoundOptions = <String, dynamic>{
    'emergency_alarm': 'Emergency alarm',
    'task_alert_airport_ding': 'Airport ding',
    'task_alert_church_bell': 'Church bell',
    'old_phone_ringtone': 'Old phone ringtone',
    'ringing_old_phone': 'Ringing old phone',
    'old_ring_tone': 'Old ring tone',
  };

  static const Map<String, dynamic> defaultDesignSystem = <String, dynamic>{
    'id': 'projectManagementCalmNative2026',
    'name': 'Project Management Dashboard',
    'mode': 'projectManagementNeutralNative',
    'templateName': 'editorialNativeUi',
    'statusBarPolicy': 'nativeOnly',
    'shellPolicy': 'preserveNativeShell',
    'surface': '#F3F4F1',
    'card': '#FFFFFF',
    'textPrimary': '#0A0D0A',
    'textSecondary': '#687269',
    'border': '#D9DFDA',
    'accent': '#344D50',
    'success': '#405446',
    'warning': '#8F9168',
    'danger': '#D87465',
    'radiusLarge': 28,
    'radiusMedium': 22,
    'shadowStyle': 'softProjectFloating',
  };

  static const Map<String, dynamic> defaultAnimationConfig = <String, dynamic>{
    'enabled': true,
    'level': 'nativeSubtle',
    'respectReduceMotion': true,
    'defaultCurve': 'easeOutCubic',
    'screenTransition': 'slideFade',
    'cardEntrance': 'fadeUp',
    'listItemStaggerMs': 45,
    'tapScale': 0.97,
    'floatingNavAnimation': 'slideFade',
    'progressAnimation': true,
    'skeletonLoading': true,
  };

  static const Map<String, dynamic> defaultLayoutConfig = <String, dynamic>{
    'screenBodyOnly': true,
    'nativeStatusBar': true,
    'safeAreaTop': true,
    'safeAreaBottom': true,
    'contentPaddingTop': 86,
    'contentPaddingBottom': 106,
    'horizontalPadding': 18,
    'maxContentWidth': 560,
    'responsiveMode': 'phoneFirst',
    'background': '#F3F4F1',
    'avoidKeyboard': true,
  };

  static const Map<String, dynamic> defaultNavigationConfig = <String, dynamic>{
    'mode': 'nativeFloatingShell',
    'statusBarPolicy': 'nativeOnly',
    'shellPolicy': 'preserveNativeShell',
    'contentRenderMode': 'screenBodyOnly',
    'safeArea': true,
    'autoContentPadding': true,
    'routeSync': true,
    'tabStatePersistence': 'perTabScrollAndFilter',
    'tapDebounceMs': 220,
    'haptics': 'selectionClick',
    'keyboardBehavior': 'hideBottomBarWhenKeyboardVisible',
    'activeTabRetapBehavior': 'scrollToTopOrPopToRoot',
    'centerActionRoute': 'createTask',
  };

  static const Map<String, dynamic> defaultBottomNav = <String, dynamic>{
    'enabled': true,
    'mode': 'floatingNative',
    'variant': 'projectFloatingDock',
    'position': 'bottom',
    'safeArea': true,
    'overlayContent': true,
    'contentInset': 'auto',
    'height': 70,
    'marginHorizontal': 22,
    'marginBottom': 12,
    'cornerRadius': 26,
    'background': '#0A0D0A',
    'border': '#26322C',
    'activeColor': '#FFFFFF',
    'inactiveColor': '#A7AEA8',
    'indicatorColor': '#CCD2CD',
    'centerActionColor': '#FFFFFF',
    'centerActionIconColor': '#0A0D0A',
    'shadow': true,
    'elevation': 10,
    'activeIndicator': true,
    'activeIndicatorPosition': 'bottom',
    'selectedTabSource': 'currentRoute',
    'syncWithBottomTabs': true,
    'labelMode': 'selectedOnly',
    'centerAction': true,
    'centerActionIcon': 'plus',
    'centerActionRoute': 'createTask',
  };

  static const Map<String, dynamic> defaultFloatingTopNav = <String, dynamic>{
    'enabled': true,
    'style': 'nativeMinimalFloating',
    'height': 58,
    'contentInsetTop': 78,
    'routeTitleMap': <String, dynamic>{
      'home': 'Dashboard',
      'tasks': 'Tasks',
      'projects': 'Projects',
      'notifications': 'Inbox',
      'profile': 'Profile',
    },
    'showBackOnNested': true,
    'showSearchOnListPages': true,
    'showInbox': true,
    'showAvatar': true,
  };

  static const Map<String, dynamic> defaultFloatingBottomNav = <String, dynamic>{
    'enabled': true,
    'style': 'projectFloatingDock',
    'contentInsetBottom': 94,
    'hideWhenKeyboard': true,
    'showOnScrollUp': true,
    'hideOnScrollDown': false,
    'preserveTabState': true,
  };

  static const Map<String, dynamic> defaultQuickActionDock = <String, dynamic>{
    'enabled': true,
    'trigger': 'bottomNavCenterAction',
    'presentation': 'nativeBottomSheet',
    'sheetStyle': 'editorialActionSheet',
    'actions': <String>['createTask', 'createProject', 'uploadFile', 'openInbox'],
  };

  static const Map<String, dynamic> defaultHomeLayout = <String, dynamic>{
    'variant': 'projectManagementDashboard',
    'sections': <String>['workSummary', 'deadlineHero', 'todayTasks', 'myOpenTasks', 'projectProgress'],
    'headerStyle': 'calmHero',
    'showSectionTitles': true,
    'cardSpacing': 14,
  };

  static const Map<String, dynamic> defaultHomeCardConfig = <String, dynamic>{
    'deadlineTimer': <String, dynamic>{'variant': 'darkEditorialHero', 'showCountdown': true, 'showProjectName': true, 'showPriority': true},
    'todayTasks': <String, dynamic>{'variant': 'smallMetricTile', 'iconStyle': 'line', 'showTrend': false},
    'myOpenTasks': <String, dynamic>{'variant': 'smallMetricTile', 'iconStyle': 'line', 'showTrend': false},
    'projectProgress': <String, dynamic>{'variant': 'softProgressCard', 'showProgressBar': true, 'showCompletedCount': true},
  };

  static const Map<String, dynamic> defaultScreenConfigs = <String, dynamic>{
    'home': <String, dynamic>{'title': 'Dashboard', 'layout': 'projectManagementDashboard', 'topNav': true, 'bottomNav': true, 'search': true, 'pageSearchScope': 'currentPageContentOnly'},
    'tasks': <String, dynamic>{'title': 'Tasks', 'layout': 'statusTimelineList', 'topNav': true, 'bottomNav': true, 'search': true, 'filters': true, 'pageSearchScope': 'currentPageContentOnly'},
    'projects': <String, dynamic>{'title': 'Projects', 'layout': 'searchableProjectList', 'topNav': true, 'bottomNav': true, 'search': true, 'filters': true, 'pageSearchScope': 'currentPageContentOnly'},
    'board': <String, dynamic>{'title': 'Board', 'layout': 'kanbanBoard', 'topNav': true, 'bottomNav': true, 'search': true, 'filters': true, 'pageSearchScope': 'currentPageContentOnly'},
    'notifications': <String, dynamic>{'title': 'Inbox', 'layout': 'notificationList', 'topNav': true, 'bottomNav': true, 'search': true, 'pageSearchScope': 'currentPageContentOnly'},
    'meetings': <String, dynamic>{'title': 'Meetings', 'layout': 'meetingPage', 'topNav': true, 'bottomNav': true, 'search': true, 'pageSearchScope': 'currentPageContentOnly'},
    'profile': <String, dynamic>{'title': 'Profile', 'layout': 'projectProfile', 'topNav': true, 'bottomNav': true},
  };

  static const Map<String, dynamic> defaultProfileCardConfig = <String, dynamic>{
    'variant': 'editorialProfileCard',
    'showAvatar': true,
    'showOnlineStatus': true,
    'showCompanyName': true,
    'showRole': true,
    'showDepartment': true,
    'fieldStyle': 'cleanRows',
    'logoutPlacement': 'bottom',
    'logoutStyle': 'editorialFooterAction',
  };

  static const Map<String, dynamic> defaultProjectListConfig = <String, dynamic>{
    'layout': 'searchableEditorialList',
    'searchPlacement': 'topInline',
    'filterStyle': 'softChips',
    'showPopularFilters': true,
    'defaultFilters': <String>['All', 'In Progress', 'Completed'],
    'sort': 'deadlineAsc',
    'cardVariant': 'editorialProjectRow',
  };

  static const Map<String, dynamic> defaultDataBindings = <String, dynamic>{
    'profile': 'users/{uid}',
    'companyResolver': 'users/{uid}.defaultCompanyId -> users/{uid}/memberships -> fallbackCompanyId',
    'tasks': 'companies/{companyId}/tasks + legacy tasks where companyId == {companyId}',
    'projects': 'companies/{companyId}/projects + legacy projects where companyId == {companyId}',
    'members': 'companies/{companyId}/members + legacy members where companyId == {companyId}',
    'teams': 'companies/{companyId}/teams + legacy teams where companyId == {companyId}',
    'notifications': 'companies/{companyId}/notifications + members/{uid}/notifications + admin group notifications',
    'company': 'companies/{companyId}',
    'presence': 'presence/{uid}',
  };

  static const Map<String, dynamic> defaultRendererCompatibility = <String, dynamic>{
    'minRendererVersion': 3,
    'fallbackRendererVersion': 1,
    'fallbackMode': 'legacyConfigKeys',
    'preserveOldKeys': true,
    'requiresFloatingNavSupport': true,
    'requiresAnimationSupport': true,
    'requiresScreenBodyOnly': true,
    'hardcodedBodyRenderer': false,
    'apkPreviewParityMode': 'sharedSduiJson',
    'dataRecoveryMode': 'companyIdResolvedAndLegacyRootFallback',
    'preserveExistingFirestoreData': true,
    'jsonFirstSafeControls': true,
    'rendererDoesNotBlockOnUnknownJson': true,
    'unsupportedWidgetMode': 'safeCard',
    'summaryStatsJsonControlled': true,
    'responsiveGridJsonControlled': true,
    'nodeLevelRecovery': true,
  };

  factory MobileUiConfig.defaults() {
    return const MobileUiConfig(
      enabled: true,
      version: 1,
      bottomTabs: <String>['home', 'tasks', 'projects', 'profile'],
      topNav: <String, dynamic>{
        'enabled': true,
        'style': 'nativeMinimalFloating',
        'mode': 'floatingCompactTopBar',
        'density': 'comfortable',
        'floating': true,
        'position': 'top',
        'safeArea': true,
        'avoidStatusBar': true,
        'height': 58,
        'marginHorizontal': 18,
        'marginTop': 8,
        'cornerRadius': 24,
        'background': '#FFFFFF',
        'border': '#D9DFDA',
        'showInbox': true,
        'showCompanyName': false,
        'showUserRole': false,
        'showOnlineStatus': true,
        'showLogout': false,
        'inboxBadge': true,
        'showAvatar': true,
        'showPresenceGlow': true,
        'routeAwareTitle': true,
        'searchEnabled': true,
      },
      homeCards: <String>['workSummary', 'deadlineTimer', 'todayTasks', 'myOpenTasks', 'projectProgress'],
      taskCardFields: <String>['taskTitle', 'projectName', 'priority', 'status', 'deadlineTimer', 'progress'],
      projectCardFields: <String>['projectName', 'description', 'statusTag', 'priority', 'progress', 'teamCount', 'deadline', 'taskCount', 'completedTaskCount'],
      taskCardVariant: 'editorialStatusCard',
      projectCardVariant: 'softProgressCard',
      taskListConfig: <String, dynamic>{
        'showFloatingTabs': true,
        'defaultTab': 'newArrival',
        'newArrivalFirst': true,
        'showCompletedTab': true,
        'completedSort': 'completedAtDesc',
      },
      profileActions: <String, dynamic>{
        'showLogout': true,
        'logoutStyle': 'filledIcon',
        'logoutPosition': 'bottom',
        'setOfflineBeforeLogout': true,
      },
      inboxConfig: defaultInboxConfig,
      profileFields: defaultProfileFields,
      supportedWidgets: defaultSupportedWidgets,
      notificationAlertConfig: defaultNotificationAlertConfig,
      notificationSoundOptions: defaultNotificationSoundOptions,
      designSystem: defaultDesignSystem,
      animationConfig: defaultAnimationConfig,
      layoutConfig: defaultLayoutConfig,
      navigationConfig: defaultNavigationConfig,
      bottomNav: defaultBottomNav,
      floatingTopNav: defaultFloatingTopNav,
      floatingBottomNav: defaultFloatingBottomNav,
      quickActionDock: defaultQuickActionDock,
      homeLayout: defaultHomeLayout,
      homeCardConfig: defaultHomeCardConfig,
      screenConfigs: defaultScreenConfigs,
      profileCardConfig: defaultProfileCardConfig,
      projectListConfig: defaultProjectListConfig,
      dataBindings: defaultDataBindings,
      rendererCompatibility: defaultRendererCompatibility,
      authUiPolicy: defaultAuthUiPolicy,
      compactMode: false,
    );
  }

  static List<String> _cleanList(dynamic value, List<String> allowed) {
    final rawItems = JsonValue.stringList(value);
    if (rawItems.isEmpty) return const <String>[];
    final seen = <String>{};
    final result = <String>[];
    for (final item in rawItems) {
      if (allowed.contains(item) && seen.add(item)) result.add(item);
    }
    return result;
  }

  static List<String> _readSafeList(dynamic value, List<String> fallback, List<String> allowed) {
    final result = _cleanList(value, allowed);
    return result.isEmpty ? fallback : result;
  }

  /// Reads the root field and the nested card map field, then keeps the richer
  /// set. This prevents an old admin/design save from reverting a manually
  /// fixed Firestore config back to short legacy card fields.
  static List<String> _readBestSafeList(dynamic rootValue, dynamic nestedValue, List<String> fallback, List<String> allowed) {
    final root = _cleanList(rootValue, allowed);
    final nested = _cleanList(nestedValue, allowed);
    if (root.isEmpty && nested.isEmpty) return fallback;
    if (root.isEmpty) return nested;
    if (nested.isEmpty) return root;
    return nested.length > root.length ? nested : root;
  }

  static bool _hasSameItems(List<String> value, List<String> legacy) {
    if (value.length != legacy.length) return false;
    final valueSet = value.toSet();
    return legacy.every(valueSet.contains);
  }

  static List<String> _upgradeLegacyTaskFields(List<String> value, List<String> fallback) {
    const legacyA = <String>['projectName', 'taskTitle', 'status', 'priority', 'deadlineTimer'];
    const legacyB = <String>['taskTitle', 'projectName', 'status', 'deadlineTimer', 'priority'];
    if (_hasSameItems(value, legacyA) || _hasSameItems(value, legacyB)) return fallback;
    return value;
  }

  static List<String> _upgradeLegacyProjectFields(List<String> value, List<String> fallback) {
    const legacy = <String>['projectName', 'taskCount', 'progress', 'deadline'];
    if (_hasSameItems(value, legacy)) return fallback;
    return value;
  }

  static List<String> _readStringList(dynamic value, List<String> fallback) {
    final rawItems = JsonValue.stringList(value);
    if (rawItems.isEmpty) return fallback;
    final seen = <String>{};
    final result = <String>[];
    for (final item in rawItems) {
      if (item.trim().isNotEmpty && seen.add(item)) result.add(item);
    }
    return result.isEmpty ? fallback : result;
  }

  static Map<String, dynamic> _readSafeMap(dynamic value, Map<String, dynamic> fallback) {
    if (value is Map) {
      return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    }
    return Map<String, dynamic>.from(fallback);
  }

  static String _readCardVariant(dynamic value, String fallback) {
    final raw = value?.toString().trim();
    if (raw != null && allowedCardVariants.contains(raw)) return raw;
    return fallback;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    try {
      if (value is DateTime) return value;
      if (value.runtimeType.toString() == 'Timestamp') {
        return (value as dynamic).toDate() as DateTime;
      }
      return DateTime.tryParse(value.toString());
    } catch (_) {
      return null;
    }
  }

  factory MobileUiConfig.fromMap(Map<String, dynamic>? data) {
    final defaults = MobileUiConfig.defaults();
    if (data == null) return defaults;
    final taskCardMap = _readSafeMap(data['taskCard'], const <String, dynamic>{});
    final projectCardMap = _readSafeMap(data['projectCard'], const <String, dynamic>{});
    final taskFields = _upgradeLegacyTaskFields(
      _readBestSafeList(data['taskCardFields'], taskCardMap['showFields'], defaults.taskCardFields, allowedTaskCardFields),
      defaults.taskCardFields,
    );
    final projectFields = _upgradeLegacyProjectFields(
      _readBestSafeList(data['projectCardFields'], projectCardMap['showFields'], defaults.projectCardFields, allowedProjectCardFields),
      defaults.projectCardFields,
    );
    return MobileUiConfig(
      enabled: JsonValue.boolean(data['enabled'], fallback: defaults.enabled),
      version: JsonValue.integer(data['version'], fallback: defaults.version),
      bottomTabs: _readSafeList(data['bottomTabs'], defaults.bottomTabs, allowedBottomTabs),
      topNav: _readSafeMap(data['topNav'] ?? data['topNva'], defaults.topNav),
      homeCards: _readSafeList(data['homeCards'], defaults.homeCards, allowedHomeCards),
      taskCardFields: taskFields,
      projectCardFields: projectFields,
      taskCardVariant: _readCardVariant(data['taskCardVariant'] ?? taskCardMap['variant'], defaults.taskCardVariant),
      projectCardVariant: _readCardVariant(data['projectCardVariant'] ?? projectCardMap['variant'], defaults.projectCardVariant),
      taskListConfig: _readSafeMap(data['taskListConfig'], defaults.taskListConfig),
      profileActions: _readSafeMap(data['profileActions'], defaults.profileActions),
      inboxConfig: _readSafeMap(data['inboxConfig'], defaults.inboxConfig),
      profileFields: _readStringList(data['profileFields'], defaults.profileFields),
      supportedWidgets: _readStringList(data['supportedWidgets'], defaults.supportedWidgets),
      notificationAlertConfig: _readSafeMap(data['notificationAlertConfig'], defaults.notificationAlertConfig),
      notificationSoundOptions: _readSafeMap(data['notificationSoundOptions'], defaults.notificationSoundOptions),
      designSystem: _readSafeMap(data['designSystem'], defaults.designSystem),
      animationConfig: _readSafeMap(data['animationConfig'], defaults.animationConfig),
      layoutConfig: _readSafeMap(data['layoutConfig'], defaults.layoutConfig),
      navigationConfig: _readSafeMap(data['navigationConfig'], defaults.navigationConfig),
      bottomNav: _readSafeMap(data['bottomNav'], defaults.bottomNav),
      floatingTopNav: _readSafeMap(data['floatingTopNav'], defaults.floatingTopNav),
      floatingBottomNav: _readSafeMap(data['floatingBottomNav'], defaults.floatingBottomNav),
      quickActionDock: _readSafeMap(data['quickActionDock'], defaults.quickActionDock),
      sideMenuConfig: _readSafeMap(data['sideMenuConfig'], defaults.sideMenuConfig),
      homeLayout: _readSafeMap(data['homeLayout'], defaults.homeLayout),
      homeCardConfig: _readSafeMap(data['homeCardConfig'], defaults.homeCardConfig),
      screenConfigs: _readSafeMap(data['screenConfigs'], defaults.screenConfigs),
      screenOverrides: _readSafeMap(data['screenOverrides'], defaults.screenOverrides),
      screenRegistry: _readSafeMap(data['screenRegistry'], defaults.screenRegistry),
      navigationGraph: _readSafeMap(data['navigationGraph'], defaults.navigationGraph),
      profileCardConfig: _readSafeMap(data['profileCardConfig'], defaults.profileCardConfig),
      projectListConfig: _readSafeMap(data['projectListConfig'], defaults.projectListConfig),
      dataBindings: _readSafeMap(data['dataBindings'], defaults.dataBindings),
      rendererCompatibility: _readSafeMap(data['rendererCompatibility'], defaults.rendererCompatibility),
      authUiPolicy: _readSafeMap(data['authUiPolicy'], defaults.authUiPolicy),
      texts: _readSafeMap(data['texts'] ?? data['text'] ?? data['strings'] ?? data['copy'] ?? data['textOverrides'], const <String, dynamic>{}),
      compactMode: JsonValue.boolean(data['compactMode'], fallback: defaults.compactMode),
      updatedAt: _parseDate(data['updatedAt']),
      updatedBy: JsonValue.optionalString(data['updatedBy']),
    );
  }

  static Map<String, dynamic> _mergeMap(Map<String, dynamic> existing, Map<String, dynamic> incoming) {
    final result = Map<String, dynamic>.from(existing);
    for (final entry in incoming.entries) {
      final existingValue = result[entry.key];
      final incomingValue = entry.value;
      if (existingValue is Map && incomingValue is Map) {
        result[entry.key] = _mergeMap(
          existingValue.map((key, value) => MapEntry(key.toString(), value)),
          incomingValue.map((key, value) => MapEntry(key.toString(), value)),
        );
      } else {
        result[entry.key] = incomingValue;
      }
    }
    return result;
  }

  static List<String> _union(List<String> first, List<String> second) {
    final seen = <String>{};
    return <String>[...first, ...second].where((item) => item.trim().isNotEmpty && seen.add(item)).toList();
  }

  static List<String> _preferRicherExisting(List<String> existing, List<String> incoming) {
    // If an old/default admin screen tries to publish a short legacy field list
    // while Firestore already has a richer production list, keep the richer list.
    if (existing.length > incoming.length && incoming.length <= 5) return existing;
    return incoming;
  }

  /// Used before any admin/design save. It keeps newly edited values, but stops
  /// stale admin state, cached design documents, or bootstrap defaults from
  /// destroying fields that already exist in Firestore.
  MobileUiConfig preserveRuntimeSafeFieldsFrom(MobileUiConfig existing) {
    return copyWith(
      taskCardFields: _preferRicherExisting(existing.taskCardFields, taskCardFields),
      projectCardFields: _preferRicherExisting(existing.projectCardFields, projectCardFields),
      inboxConfig: _mergeMap(existing.inboxConfig, inboxConfig),
      profileFields: _union(profileFields, existing.profileFields),
      supportedWidgets: _union(supportedWidgets, existing.supportedWidgets),
      notificationAlertConfig: _mergeMap(existing.notificationAlertConfig, notificationAlertConfig),
      notificationSoundOptions: _mergeMap(existing.notificationSoundOptions, notificationSoundOptions),
      designSystem: _mergeMap(existing.designSystem, designSystem),
      animationConfig: _mergeMap(existing.animationConfig, animationConfig),
      layoutConfig: _mergeMap(existing.layoutConfig, layoutConfig),
      navigationConfig: _mergeMap(existing.navigationConfig, navigationConfig),
      bottomNav: _mergeMap(existing.bottomNav, bottomNav),
      floatingTopNav: _mergeMap(existing.floatingTopNav, floatingTopNav),
      floatingBottomNav: _mergeMap(existing.floatingBottomNav, floatingBottomNav),
      quickActionDock: _mergeMap(existing.quickActionDock, quickActionDock),
      sideMenuConfig: _mergeMap(existing.sideMenuConfig, sideMenuConfig),
      homeLayout: _mergeMap(existing.homeLayout, homeLayout),
      homeCardConfig: _mergeMap(existing.homeCardConfig, homeCardConfig),
      screenConfigs: _mergeMap(existing.screenConfigs, screenConfigs),
      screenOverrides: _mergeMap(existing.screenOverrides, screenOverrides),
      screenRegistry: _mergeMap(existing.screenRegistry, screenRegistry),
      navigationGraph: _mergeMap(existing.navigationGraph, navigationGraph),
      profileCardConfig: _mergeMap(existing.profileCardConfig, profileCardConfig),
      projectListConfig: _mergeMap(existing.projectListConfig, projectListConfig),
      dataBindings: _mergeMap(existing.dataBindings, dataBindings),
      rendererCompatibility: _mergeMap(existing.rendererCompatibility, rendererCompatibility),
      authUiPolicy: _mergeMap(existing.authUiPolicy, authUiPolicy),
      texts: _mergeMap(existing.texts, texts),
    );
  }

  String get cacheSignature => jsonEncode(<String, Object?>{
        'enabled': enabled,
        'version': version,
        'bottomTabs': bottomTabs,
        'topNav': topNav,
        'homeCards': homeCards,
        'taskCardFields': taskCardFields,
        'projectCardFields': projectCardFields,
        'taskCardVariant': taskCardVariant,
        'projectCardVariant': projectCardVariant,
        'taskCard': <String, dynamic>{'variant': taskCardVariant, 'showFields': taskCardFields},
        'projectCard': <String, dynamic>{'variant': projectCardVariant, 'showFields': projectCardFields},
        'taskListConfig': taskListConfig,
        'profileActions': profileActions,
        'inboxConfig': inboxConfig,
        'profileFields': profileFields,
        'supportedWidgets': supportedWidgets,
        'notificationAlertConfig': notificationAlertConfig,
        'notificationSoundOptions': notificationSoundOptions,
        'designSystem': designSystem,
        'animationConfig': animationConfig,
        'layoutConfig': layoutConfig,
        'navigationConfig': navigationConfig,
        'bottomNav': bottomNav,
        'floatingTopNav': floatingTopNav,
        'floatingBottomNav': floatingBottomNav,
        'quickActionDock': quickActionDock,
        'sideMenuConfig': sideMenuConfig,
        'homeLayout': homeLayout,
        'homeCardConfig': homeCardConfig,
        'screenConfigs': screenConfigs,
        'screenOverrides': screenOverrides,
        'screenRegistry': screenRegistry,
        'navigationGraph': navigationGraph,
        'profileCardConfig': profileCardConfig,
        'projectListConfig': projectListConfig,
        'dataBindings': dataBindings,
        'rendererCompatibility': rendererCompatibility,
        'authUiPolicy': authUiPolicy,
        'texts': texts,
        'compactMode': compactMode,
      });

  Map<String, dynamic> toMap({String? updatedBy}) {
    return <String, dynamic>{
      'enabled': enabled,
      'version': version,
      'bottomTabs': bottomTabs,
      'topNav': topNav,
      'homeCards': homeCards,
      'inboxConfig': inboxConfig,
      'profileFields': profileFields,
      'supportedWidgets': supportedWidgets,
      'notificationAlertConfig': notificationAlertConfig,
      'notificationSoundOptions': notificationSoundOptions,
      'designSystem': designSystem,
      'animationConfig': animationConfig,
      'layoutConfig': layoutConfig,
      'navigationConfig': navigationConfig,
      'bottomNav': bottomNav,
      'floatingTopNav': floatingTopNav,
      'floatingBottomNav': floatingBottomNav,
      'quickActionDock': quickActionDock,
      'sideMenuConfig': sideMenuConfig,
      'homeLayout': homeLayout,
      'homeCardConfig': homeCardConfig,
      'screenConfigs': screenConfigs,
      'screenOverrides': screenOverrides,
      'screenRegistry': screenRegistry,
      'navigationGraph': navigationGraph,
      'profileCardConfig': profileCardConfig,
      'projectListConfig': projectListConfig,
      'dataBindings': dataBindings,
      'rendererCompatibility': rendererCompatibility,
      'authUiPolicy': authUiPolicy,
      'texts': texts,
      'taskCardFields': taskCardFields,
      'projectCardFields': projectCardFields,
      'taskCardVariant': taskCardVariant,
      'projectCardVariant': projectCardVariant,
      'taskCard': <String, dynamic>{
        'variant': taskCardVariant,
        'showFields': taskCardFields,
        'actions': <String>['openDetails', 'comment', 'uploadFile'],
      },
      'projectCard': <String, dynamic>{
        'variant': projectCardVariant,
        'showFields': projectCardFields,
        'actions': <String>['openDetails'],
      },
      'taskListConfig': taskListConfig,
      'profileActions': profileActions,
      'compactMode': compactMode,
      'updatedBy': updatedBy ?? this.updatedBy,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  MobileUiConfig copyWith({
    bool? enabled,
    int? version,
    List<String>? bottomTabs,
    Map<String, dynamic>? topNav,
    List<String>? homeCards,
    List<String>? taskCardFields,
    List<String>? projectCardFields,
    String? taskCardVariant,
    String? projectCardVariant,
    Map<String, dynamic>? taskListConfig,
    Map<String, dynamic>? profileActions,
    Map<String, dynamic>? inboxConfig,
    List<String>? profileFields,
    List<String>? supportedWidgets,
    Map<String, dynamic>? notificationAlertConfig,
    Map<String, dynamic>? notificationSoundOptions,
    Map<String, dynamic>? designSystem,
    Map<String, dynamic>? animationConfig,
    Map<String, dynamic>? layoutConfig,
    Map<String, dynamic>? navigationConfig,
    Map<String, dynamic>? bottomNav,
    Map<String, dynamic>? floatingTopNav,
    Map<String, dynamic>? floatingBottomNav,
    Map<String, dynamic>? quickActionDock,
    Map<String, dynamic>? sideMenuConfig,
    Map<String, dynamic>? homeLayout,
    Map<String, dynamic>? homeCardConfig,
    Map<String, dynamic>? screenConfigs,
    Map<String, dynamic>? screenOverrides,
    Map<String, dynamic>? screenRegistry,
    Map<String, dynamic>? navigationGraph,
    Map<String, dynamic>? profileCardConfig,
    Map<String, dynamic>? projectListConfig,
    Map<String, dynamic>? dataBindings,
    Map<String, dynamic>? rendererCompatibility,
    Map<String, dynamic>? authUiPolicy,
    Map<String, dynamic>? texts,
    bool? compactMode,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return MobileUiConfig(
      enabled: enabled ?? this.enabled,
      version: version ?? this.version,
      bottomTabs: bottomTabs ?? this.bottomTabs,
      topNav: topNav ?? this.topNav,
      homeCards: homeCards ?? this.homeCards,
      taskCardFields: taskCardFields ?? this.taskCardFields,
      projectCardFields: projectCardFields ?? this.projectCardFields,
      taskCardVariant: taskCardVariant ?? this.taskCardVariant,
      projectCardVariant: projectCardVariant ?? this.projectCardVariant,
      taskListConfig: taskListConfig ?? this.taskListConfig,
      profileActions: profileActions ?? this.profileActions,
      inboxConfig: inboxConfig ?? this.inboxConfig,
      profileFields: profileFields ?? this.profileFields,
      supportedWidgets: supportedWidgets ?? this.supportedWidgets,
      notificationAlertConfig: notificationAlertConfig ?? this.notificationAlertConfig,
      notificationSoundOptions: notificationSoundOptions ?? this.notificationSoundOptions,
      designSystem: designSystem ?? this.designSystem,
      animationConfig: animationConfig ?? this.animationConfig,
      layoutConfig: layoutConfig ?? this.layoutConfig,
      navigationConfig: navigationConfig ?? this.navigationConfig,
      bottomNav: bottomNav ?? this.bottomNav,
      floatingTopNav: floatingTopNav ?? this.floatingTopNav,
      floatingBottomNav: floatingBottomNav ?? this.floatingBottomNav,
      quickActionDock: quickActionDock ?? this.quickActionDock,
      sideMenuConfig: sideMenuConfig ?? this.sideMenuConfig,
      homeLayout: homeLayout ?? this.homeLayout,
      homeCardConfig: homeCardConfig ?? this.homeCardConfig,
      screenConfigs: screenConfigs ?? this.screenConfigs,
      screenOverrides: screenOverrides ?? this.screenOverrides,
      screenRegistry: screenRegistry ?? this.screenRegistry,
      navigationGraph: navigationGraph ?? this.navigationGraph,
      profileCardConfig: profileCardConfig ?? this.profileCardConfig,
      projectListConfig: projectListConfig ?? this.projectListConfig,
      dataBindings: dataBindings ?? this.dataBindings,
      rendererCompatibility: rendererCompatibility ?? this.rendererCompatibility,
      authUiPolicy: authUiPolicy ?? this.authUiPolicy,
      texts: texts ?? this.texts,
      compactMode: compactMode ?? this.compactMode,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
