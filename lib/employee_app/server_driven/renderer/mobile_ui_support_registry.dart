import '../../../data/models/mobile_ui_config.dart';
import '../../../data/models/mobile_ui_design.dart';

/// Single source of truth for what the currently installed employee APK can render.
///
/// The admin designer uses this to show support/unsupported status before publish.
/// The employee renderer uses the same registry to avoid crashing on unknown JSON.
class MobileUiSupportRegistry {
  const MobileUiSupportRegistry._();

  static const String apkRendererVersion = 'employee_sdui_v212_reference_locked_phase_stack';

  static const Set<String> supportedScreens = <String>{
    // Primary employee tabs.
    'home',
    'tasks',
    'projects',
    'board',
    'meetings',
    'notifications',
    'profile',

    // Auth/onboarding screens.
    'onboarding',
    'login',
    'signup',
    'auth',

    // Nested/detail screens that can be published through screenOverrides.
    // These are rendered by the same safe SDUI body renderer and are not
    // required to appear as bottom tabs.
    'taskMap',
    'calendar',
    'taskDetail',
    'teamMembers',
    'timeline',
    'taskTimeline',
    'productiveTimeline',
    'taskProgressTimeline',
    'deliveryUIKitTimeline',
    'deliveryAppUIKitTimeline',
    'taskTimelineScreen',
    'milestoneTaskTimelineButton',
    'jsonControlledTimelineVisuals',
    'expandableProjectTimeline',
    'projectTaskTimeline',
    'selectProjectTimeline',
    'files',
    'projectDetail',
    'meetingDetail',
  };

  static const Set<String> supportedWidgetTypes = <String>{
    // Layout containers
    'screen',
    'page',
    'card',
    'container',
    'sectionList',
    'column',
    'row',
    'stack',
    'list',
    'grid',
    'spacer',
    'divider',

    // Text and media primitives
    'text',
    'title',
    'subtitle',
    'label',
    'icon',
    'image',
    'button',
    'actionButton',
    'primaryAction',
    'secondaryAction',
    'chip',
    'badge',
    'progressBar',
    'progressRing',

    // Employee app blocks
    'heroCard',
    'summaryCard',
    'workSummary',
    'metricCard',
    'deadlineCard',
    'taskList',
    'todayTaskList',
    'taskPage',
    'taskMenu',
    'taskAllFilterSubTabs',
    'taskOpenAllTabs',
    'pillSegmentedTaskTabs',
    'taskCard',
    'taskDetails',
    'projectCard',
    'projectDetails',
    'projectList',
    'projectPage',
    'projectProgressCard',
    'projectStatsGrid',
    'projectSummaryStrip',
    'taskStatsGrid',
    'taskSummaryStrip',
    'homeMetricStrip',
    'onlineStatusCard',
    'notificationList',
    'notificationMotionHeader',
    'stackedNotificationDeck',
    'notificationStackDeck',
    'stackNotificationHeader',
    'stackNotificationModeSelector',
    'previewRuntimeLogs',
    'taskTimelineFeatureScreen',
    'taskTimelineJsonCosmeticTheme',
    'taskTimelineColors',
    'jsonCosmeticTheme',
    'notificationAlert',
    'notificationSoundSelector',
    'notificationDisplayWindow',
    'profileSummary',
    'profileHeroCard',
    'profileStatsGrid',
    'profileInfoSection',
    'profileToggleRow',
    'profileQuickActions',
    'onboardingChecklist',
    'onboardingMetricPill',
    'profileAction',
    'profileActionList',
    'ratioBasedNavLayout',
    'aspectRatioAwareProtection',
    'ratioBasedTopProtection',
    'settingsTile',
    'settingsList',
    'settingsAccordion',
    'profileSettingsAccordion',
    'profileSettingTile',
    'kanbanBoard',
    'cinematicHorizontalTaskStack',
    'cinematicHorizontal3DStack',
    'saudiHtmlPhysicsStack',
    'taskBoardHtmlPhysicsParity',
    'taskBoardCinematicCards',
    'staticDesignerTaskBoardCards',
    'phaseProjectStackCarousel',
    'phaseProjectQueueCards',
    'exactAllCardPhaseStack',
    'referencePhaseCardArtwork',
    'projectThenPhaseTaskSheet',
    'emptyPhaseDialog',
    'phaseCardHeroTransition',
    'exactEightDesignerCarouselCards',
    'taskBoardDesignerTemplateCards',
    'taskBoardPreviewDialog',
    'designerThumbnailCarouselOnly',
    'carouselOnlyTaskBoard',
    'exactDesignerTaskCarousel',
    'designerTaskThumbnailStack',
    'taskBoardDesignerThumbnails',
    'todoBacklogDesignerCards',
    'dribbbleMotionThumbnailCards',
    'taskBoardDataThumbnailCards',
    'deadlineHero',
    'metricTile',
    'activeHomeMetrics',
    'todayWorkSummary',
    'liveMetricTile',
    'renderMatchedMeetings',
    'renderMatchedTimeline',
    'renderMatchedCalendar',
    'renderMatchedTaskMap',
    'renderMatchedTeamMembers',
    'renderMatchedFiles',
    'activeProjectsGrid',
    'filterChips',
    'searchHeader',
    'progressTimeline',
    'taskProgressPanel',
    'taskProgressChart',
    'taskProgressCard',
    'taskTimelineBars',
    'taskTimelineDateStrip',
    'taskTimelineAgenda',
    'taskTimelineSchedule',
    'referenceTaskTimeline',
    'deliveryUIKitTimeline',
    'deliveryAppUIKitTimeline',
    'properLiveTaskTimelineIntegration',
    'adminPreviewTaskTimelineParity',
    'taskTimelineRouteNoDashboardFallback',
    'timelineBars',
    'productiveTimeline',
    'taskProgressTimeline',
    'taskTimelineScreen',
    'milestoneTaskTimelineButton',
    'statusPill',
    'emptyState',
    'skeletonLoader',
    'nativeSheet',
    'meetingPage',
    'meetingCreateForm',
    'superAdminMeetingCreator',
    'meetingList',
    'meetingInviteCard',
    'adminMeetingAccess',
    'meetingLinkInput',
    'meetingActionButtons',
    'quickActionDock',
    'floatingBottomNav',
    'floatingTopNav',
    'bottomNav',
    'topNav',
    'hamburgerMenu',
    'sideMenu',
    'calendarStyleSideMenu',
    'animatedSideMenuReveal',
    'sideMenuPeekPanel',
    'sideMenuCutPanel',
    'slideRevealCutPanel',
    'workspaceDrawerMenu',
    'greenRevealDrawer',
    'sideMenuVisualConfig',
    'sideNavigationMenu',
    'floatingSideSheet',
    'mergedHamburgerSearch',
    'interactiveTopSearch',
    'runtimeSearchQuery',
    'pillSearchBar',
    'pageScopedTopSearch',
    'universalSearchSubmit',
    'globalUniversalSearch',
    'universalSearchController',
    'universalSearchResults',
    'floatingResultsSheet',
    'pageSearchActivePageOnly',
    'jsonControlledSummaryBeforeFilters',
    'projectTaskSearchSummaryFilterContentOrder',
    'summaryBeforeFilters',
    'statsBeforeFilters',
    'allTabIcons',
    'sideMenuIconMap',
    'routeIconMap',
    'sduiTemplate',
    'templateScreen',
    'templateSection',
    'filesDocuments',
    'calendarView',
    'taskMap',
    'teamMembers',
    'workspaceStateLiveData',
    'ratioBasedLayout',
    'onboardingScreen',
    'dashboardFeed',
    'projectFeed',
    'timelineMilestones',
    'calendarDeadlines',
    'calendarMonthPicker',
    'calendarTodayHighlight',
    'calendarDateFilter',
    'calendarThinSquircleLabels',
    'calendarCleanDateCells',
    'calendarLabelLegend',
    'calendarFilterSections',
    'taskMapSiteView',
    'teamProjectMembers',
    'membersList',
    'floatingReferenceBottomNav',
    'contentPassUnderNav',
    'quickCreateButton',
    'mapPins',
    'timeline',
    'expandableProjectTimeline',
    'projectTaskTimeline',
    'selectProjectTimeline',

    // Android figure-one edge-to-edge / system-bar support markers.
    'edgeToEdgeSystemBars',
    'androidFigureOneRightEdgeToEdge',
    'scrollAwareTopPadding',
    'systemBarContrastScrim',
    'gestureAwareBottomProtection',

    // Wireframe/auth primitives for server-driven login and signup previews.
    'wireframeAuthScreen',
    'authForm',
    'authLogo',
    'input',
    'textField',
    'passwordField',
    'socialAuthButton',
    'authSwitch',
    'jsonFirstLayoutEngine',
    'jsonSectionOrder',
    'authActionApi',
    'firebaseAuthApiActions',
    'emailPasswordAuth',
    'passwordResetApi',
    'providerAuthButton',
    'authBruteForceProtection',
    'authRateLimit',
    'authAttemptLockout',
    'authSecurityNote',
    'cloudFunctionAuthGuard',
    'genericAuthErrors',
    'emailEnumerationSafeErrors',

    // v173 JSON-first safe controls / generic primitives.
    // v174 keeps old visual primitives as default; JSON-first controls are opt-in for visual changes.
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
  };

  static const Set<String> supportedCardVariants = <String>{
    'modernCard',
    'minimalCard',
    'compactCard',
    'timelineCard',
    'progressCard',
    'taskProgressPanel',
    'productiveTimelineCard',
    'timelineBarsCard',
    'legacyExpandableMilestones',
    'referenceProductiveSoftCard',
    'advancedProgressCard',
    'nativeListRow',
    'editorialProgressCard',
    'editorialStatusCard',
    'editorialProjectRow',
    'darkEditorialHero',
    'smallMetricTile',
    'softProgressCard',
    'wireframeReferenceFloatingDock',
    'wireframeReferenceFloatingTopDock',
    'wireframeProjectFeedCard',
    'dashboardProjectFeedWireframe',
    'wireframeFilledDataCardList',
    'workspaceChecklist',
    'wireframeProfileSettings',
    'teamSetupHero',
    'sitePins',
    'compactMapList',
    'taskDetailHeader',
    'compactHeader',
    'deadlineCalendar',
    'deadlineFirstThinSquircleLabeledCalendar',
    'deadlineFirstCleanCalendar',
    'premiumWorkspaceProfile',
    'profileSettingsAccordion',
    'accentSoftFilled',
    'accentSoftOutlined',
    'wireframeQuickActionSheet',
    'safeCard',
    'safeFallbackCard',
    'plainCard',
    'outlineCard',
    'filledCard',
    'deliveryAppUIKitTimeline',
    'actualLiveTaskTimeline',
  };

  static const Set<String> supportedBottomNavStyles = <String>{
    'standard',
    'floating',
    'compact',
    'floatingNative',
    'minimalRaisedDock',
    'projectFloatingDock',
  };

  static const Set<String> supportedTopNavStyles = <String>{
    'standard',
    'floating',
    'compact',
    'glass',
    'glassAdvanced',
    'premium',
    'nativeMinimalFloating',
    'floatingCompactTopBar',
    'projectFloatingDock',
  };

  static const Set<String> supportedActions = <String>{
    'changeStatus',
    'comment',
    'uploadFile',
    'attachFile',
    'file',
    'openDetails',
    'updateProfile',
    'setAvailability',
    'setPresence',
    'createTask',
    'createProject',
    'openInbox',
    'continueSetup',
    'skipToDashboard',
    'markComplete',
    'acceptAndJoin',
    'reject',
    'createMeeting',
    'acceptAndJoinMeeting',
    'rejectMeeting',
    'smartSearch',
    'inbox',
    'hamburgerMenu',
    'openSideMenu',
    'sideMenu',
    'menu',
    'closeMenu',
    'editProfile',
    'copyLog',
    'copyDiagnostics',
    'crashlyticsTest',
    'logout',
    'testAlert',
    'openTasks',
    'openProjects',
    'openTimeline',
    'openTaskTimeline',
    'openFiles',
    'openCalendar',
    'openTeamMembers',
    'openProfile',
    'openBoard',
    'openMeetings',
  };

  static const Set<String> supportedProfileFields = <String>{
    'displayName',
    'name',
    'email',
    'phone',
    'role',
    'department',
    'jobTitle',
    'location',
    'available',
    'isOnline',
    'onlineStatus',
    'assignedScope',
    'projects',
    'tasks',
    'teams',
    'access',
    'company',
    'companyName',
    'joinedAt',
    'accountStatus',
  };

  static const Set<String> supportedSectionStyles = <String>{
    'soft',
    'modern',
    'compact',
    'minimal',
    'plain',
    'progressRing',
    'gradientSoft',
    'gradient',
    'progressHero',
    'ring',
    'pill',
    'progressList',
  };

  static Set<String> get supportedTabs => MobileUiConfig.allowedBottomTabs.toSet();
  static Set<String> get supportedHomeCards => MobileUiConfig.allowedHomeCards.toSet();
  static Set<String> get supportedTaskFields => MobileUiConfig.allowedTaskCardFields.toSet();
  static Set<String> get supportedProjectFields => MobileUiConfig.allowedProjectCardFields.toSet();

  static SupportReport analyzeDesign(MobileUiDesign design) {
    final unsupported = <SupportIssue>[];

    for (final tab in design.bottomTabs) {
      if (!supportedTabs.contains(tab)) {
        unsupported.add(SupportIssue(path: 'bottomNav.tabs', value: _issueValue(tab), message: 'This bottom tab is not supported by the employee APK.'));
      }
    }

    final navStyle = design.bottomNav['style']?.toString();
    if (navStyle != null && !supportedBottomNavStyles.contains(navStyle)) {
      unsupported.add(SupportIssue(path: 'bottomNav.style', value: _issueValue(navStyle), message: 'This bottom navigation style is not supported by the employee APK.'));
    }

    final topNavStyle = design.topNav['style']?.toString();
    if (topNavStyle != null && topNavStyle.isNotEmpty && !supportedTopNavStyles.contains(topNavStyle)) {
      unsupported.add(SupportIssue(path: 'topNav.style', value: _issueValue(topNavStyle), message: 'This top navigation style is not supported by the employee APK.'));
    }

    for (var i = 0; i < design.sections.length; i++) {
      final section = design.sections[i];
      final type = section['type']?.toString();
      final id = section['id']?.toString();
      final style = section['style']?.toString();
      if (id != null && id.isNotEmpty && !supportedHomeCards.contains(id) && id != 'workSummary') {
        unsupported.add(SupportIssue(path: 'sections[$i].id', value: _issueValue(id), message: 'This home section id is not mapped in the employee APK.'));
      }
      if (type != null && type.isNotEmpty && !isSupportedWidgetType(type)) {
        unsupported.add(SupportIssue(path: 'sections[$i].type', value: _issueValue(type), message: 'This section widget type is not in the APK renderer registry.'));
      }
      if (style != null && style.isNotEmpty && !supportedSectionStyles.contains(style)) {
        unsupported.add(SupportIssue(path: 'sections[$i].style', value: _issueValue(style), message: 'This section style is not supported by the employee APK.'));
      }
    }

    _checkCard('taskCard', design.taskCard, supportedTaskFields, unsupported);
    _checkCard('projectCard', design.projectCard, supportedProjectFields, unsupported);

    for (final entry in design.screenOverrides.entries) {
      if (!isSupportedScreen(entry.key)) {
        unsupported.add(SupportIssue(path: 'screenOverrides.${entry.key}', value: _issueValue(entry.key), message: 'This target screen is not available in the employee APK.'));
      }
      unsupported.addAll(analyzeRawJson(entry.value, rootPath: 'screenOverrides.${entry.key}').issues);
    }

    return SupportReport(issues: unsupported);
  }


  static String canonicalScreen(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    final compact = value.replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
    return switch (compact) {
      'employeehome' || 'homescreen' || 'dashboard' || 'home' => 'home',
      'task' || 'tasks' || 'tasklist' || 'mytasks' => 'tasks',
      'project' || 'projects' || 'projectlist' => 'projects',
      'board' || 'kanban' || 'kanbanboard' => 'board',
      'notification' || 'notifications' || 'inbox' || 'notificationlist' => 'notifications',
      'profile' || 'profilesummary' || 'account' => 'profile',
      'taskmap' || 'taskmapsiteview' || 'siteview' => 'taskMap',
      'calendar' || 'calendarview' || 'calendardeadlines' => 'calendar',
      'taskdetail' || 'taskdetails' => 'taskDetail',
      'teammembers' || 'teamprojectmembers' || 'members' => 'teamMembers',
      'tasktimeline' || 'taskprogresstimeline' || 'productivetasktimeline' => 'taskTimeline',
      'timeline' || 'timelinemilestones' || 'milestones' => 'timeline',
      'expandableprojecttimeline' || 'projecttasktimeline' || 'selectprojecttimeline' => 'timeline',
      'files' || 'filesdocuments' || 'documents' => 'files',
      'projectdetail' || 'projectdetails' => 'projectDetail',
      'meetingdetail' || 'meetingdetails' => 'meetingDetail',
      'onboarding' || 'onboardingteamsetup' => 'onboarding',
      'login' || 'signin' => 'login',
      'signup' || 'register' => 'signup',
      'auth' || 'authchoice' => 'auth',
      _ => value.isEmpty ? 'screen' : value,
    };
  }

  static String canonicalWidgetType(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    final compact = value.replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
    return switch (compact) {
      'screen' || 'page' => 'screen',
      'sectionlist' => 'sectionList',
      'column' || 'container' || 'view' || 'section' || 'safearea' || 'padding' || 'margin' || 'visibility' || 'visible' => 'container',
      'row' || 'hstack' || 'horizontal' || 'inforow' => 'row',
      'grid' || 'wrap' || 'responsivegrid' || 'cardgrid' || 'metricgrid' || 'statsgrid' => 'grid',
      'list' => 'list',
      'stack' => 'stack',
      'spacer' || 'space' => 'spacer',
      'divider' || 'line' => 'divider',
      'text' => 'text',
      'title' => 'title',
      'subtitle' => 'subtitle',
      'label' => 'label',
      'icon' || 'avatar' => 'icon',
      'image' || 'picture' => 'image',
      'button' || 'listtile' || 'tile' || 'switchtile' => 'button',
      'actionbutton' => 'actionButton',
      'primaryaction' => 'primaryAction',
      'secondaryaction' => 'secondaryAction',
      'textfield' || 'input' || 'emailfield' => 'textField',
      'passwordfield' || 'passwordinput' => 'passwordField',
      'authlogo' => 'authLogo',
      'authform' || 'loginform' || 'signupform' => 'authForm',
      'wireframeauthscreen' || 'authscreen' || 'login' || 'signup' => 'wireframeAuthScreen',
      'socialauthbutton' || 'socialloginbutton' => 'socialAuthButton',
      'authswitch' || 'switchauth' => 'authSwitch',
      'jsonfirstlayoutengine' || 'jsonsectionorder' || 'jsonfirstsafecontrols' || 'renderersafety' || 'jsonrenderpolicy' || 'saferenderer' || 'safenodeboundary' => 'jsonFirstSafeControls',
      'authactionapi' || 'firebaseauthapiactions' => 'authActionApi',
      'emailpasswordauth' => 'emailPasswordAuth',
      'passwordresetapi' => 'passwordResetApi',
      'providerauthbutton' => 'providerAuthButton',
      'chip' => 'chip',
      'badge' => 'badge',
      'progressbar' || 'linearprogress' => 'progressBar',
      'progressring' || 'ringprogress' => 'progressRing',
      'card' || 'panel' || 'surface' => 'card',
      'herocard' || 'herosummary' => 'heroCard',
      'summarycard' || 'worksummary' => 'summaryCard',
      'metriccard' || 'kpicard' || 'statcard' => 'metricCard',
      'deadlinecard' || 'deadline' => 'deadlineCard',
      'tasklist' || 'myopentasks' => 'taskList',
      'todaytasklist' || 'todaytasks' => 'todayTaskList',
      'taskpage' || 'taskmenu' || 'taskscreen' => 'taskPage',
      'taskcard' => 'taskCard',
      'taskdetail' || 'taskdetails' || 'taskdetailscard' => 'taskDetails',
      'projectcard' => 'projectCard',
      'projectdetail' || 'projectdetails' || 'projectdetailscard' => 'projectDetails',
      'projectlist' => 'projectList',
      'projectpage' || 'projectscreen' => 'projectPage',
      'projectprogresscard' || 'projectprogress' => 'projectProgressCard',
      'projectstatsgrid' || 'projectsummarystrip' || 'projectsummarygrid' => 'projectStatsGrid',
      'taskstatsgrid' || 'tasksummarystrip' || 'tasksummarygrid' => 'taskStatsGrid',
      'homemetricstrip' || 'homemetricsstrip' => 'homeMetricStrip',
      'onlinestatuscard' || 'onlinestatus' => 'onlineStatusCard',
      'notificationlist' || 'inbox' => 'notificationList',
      'notificationalert' || 'alertnotification' || 'urgentalert' => 'notificationAlert',
      'notificationsoundselector' || 'soundselector' || 'alertsoundselector' => 'notificationSoundSelector',
      'notificationdisplaywindow' || 'notificationwindow' || 'displaywindow' || 'historywindow' => 'notificationDisplayWindow',
      'notificationalertsettings' || 'notificationalertsettingssection' || 'alertsettingssection' => 'notificationAlert',
      'profilesummary' || 'profilecard' => 'profileSummary',
      'profileaction' || 'profileactionbutton' || 'logoutbutton' => 'profileAction',
      'profileactionlist' || 'profileactions' => 'profileActionList',
      'ratiobasednavlayout' || 'ratiobasedlayout' => 'ratioBasedNavLayout',
      'aspectratioawareprotection' || 'aspectratioprotection' => 'aspectRatioAwareProtection',
      'ratiobasedtopprotection' || 'ratiotopprotection' => 'ratioBasedTopProtection',
      'settingstile' || 'settingsitem' => 'settingsTile',
      'settingslist' || 'settingssection' || 'settingsaccordion' || 'profilesettingsaccordion' => 'settingsList',
      'profilesettingtile' || 'profiletile' => 'profileSettingTile',
      'kanbanboard' || 'board' => 'kanbanBoard',
      'cinematichorizontaltaskstack' => 'cinematicHorizontalTaskStack',
      'cinematichorizontal3dstack' => 'cinematicHorizontal3DStack',
      'saudihtmlphysicsstack' => 'saudiHtmlPhysicsStack',
      'taskboardhtmlphysicsparity' => 'taskBoardHtmlPhysicsParity',
      'taskboardcinematiccards' => 'taskBoardCinematicCards',
      'staticdesignertaskboardcards' => 'staticDesignerTaskBoardCards',
      'exacteightdesignercarouselcards' => 'exactEightDesignerCarouselCards',
      'taskboarddesignertemplatecards' => 'taskBoardDesignerTemplateCards',
      'designertaskthumbnailstack' => 'designerTaskThumbnailStack',
      'taskboarddesignerthumbnails' => 'taskBoardDesignerThumbnails',
      'todobacklogdesignercards' => 'todoBacklogDesignerCards',
      'dribbblemotionthumbnailcards' => 'dribbbleMotionThumbnailCards',
      'taskboarddatathumbnailcards' => 'taskBoardDataThumbnailCards',
      'deadlinehero' => 'deadlineHero',
      'metrictile' || 'metric' => 'metricTile',
      'activehomemetrics' => 'activeHomeMetrics',
      'todayworksummary' => 'todayWorkSummary',
      'livemetrictile' => 'liveMetricTile',
      'activeprojectsgrid' => 'activeProjectsGrid',
      'filterchips' || 'chips' => 'filterChips',
      'searchheader' || 'searchbar' => 'searchHeader',
      'taskprogresstimeline' || 'tasktimelinescreen' || 'productivetasktimeline' || 'realtasktimeline' || 'activetasktimeline' || 'deliveryuikittimeline' || 'deliveryappuikittimeline' => 'taskProgressTimeline',
      'progresstimeline' || 'timeline' || 'timelinemilestones' => 'progressTimeline',
      'expandableprojecttimeline' || 'projecttasktimeline' || 'selectprojecttimeline' => 'expandableProjectTimeline',
      'statuspill' => 'statusPill',
      'emptystate' => 'emptyState',
      'skeletonloader' || 'shimmer' => 'skeletonLoader',
      'nativesheet' || 'bottomsheet' => 'nativeSheet',
      'filesdocuments' || 'fileslist' => 'filesDocuments',
      'calendarview' || 'calendar' || 'calendardeadlines' || 'calendarlabelfiltersections' || 'calendarlabelsections' || 'calendarfiltersections' || 'calendarthinsquirclelabels' || 'deadlinefirstthinsquirclelabeledcalendar' => 'calendarView',
      'calendarmonthpicker' || 'monthpicker' => 'calendarMonthPicker',
      'calendartodayhighlight' || 'todayhighlight' => 'calendarTodayHighlight',
      'calendardatefilter' || 'datefiltercalendar' => 'calendarDateFilter',
      'calendarlabellegend' || 'thinlabellegend' => 'calendarLabelLegend',
      'calendarthinsquirclelabels' || 'thinsquirclelabels' || 'squirclecalendarlabels' => 'calendarThinSquircleLabels',
      'calendarcleandatecells' || 'cleancalendarcells' || 'cleancalendardatecells' => 'calendarCleanDateCells',
      'calendarfiltersections' || 'calendarlabelfiltersections' => 'calendarFilterSections',
      'taskmap' || 'sitemap' || 'taskmapsiteview' => 'taskMap',
      'teammembers' || 'memberslist' => 'teamMembers',
      'onboardingscreen' || 'teamsetuphero' => 'onboardingScreen',
      'dashboardfeed' || 'dashboardprojectfeed' => 'dashboardFeed',
      'projectfeed' => 'projectFeed',
      'floatingreferencebottomnav' => 'floatingReferenceBottomNav',
      'contentpassundernav' => 'contentPassUnderNav',
      'edgetoedgesystembars' || 'systembars' || 'transparentsystembars' => 'edgeToEdgeSystemBars',
      'androidfigureonerightedgetoedge' || 'androidfigureoneedge' || 'figureonerightedgetoedge' => 'androidFigureOneRightEdgeToEdge',
      'scrollawaretoppadding' || 'scrollawareinsets' => 'scrollAwareTopPadding',
      'systembarcontrastscrim' || 'threebuttonnavigationcontrastscrim' => 'systemBarContrastScrim',
      'gestureawarebottomprotection' || 'gestureawareoverlay' => 'gestureAwareBottomProtection',
      'quickcreatebutton' => 'quickCreateButton',
      'mappins' => 'mapPins',
      'quickactiondock' => 'quickActionDock',
      'floatingbottomnav' => 'floatingBottomNav',
      'floatingtopnav' => 'floatingTopNav',
      'bottomnav' || 'bottomnavigation' || 'navigation' => 'bottomNav',
      'topnav' || 'appbar' || 'uppernav' || 'uppernavigation' => 'topNav',
      'hamburgermenu' || 'menuaction' || 'menubutton' => 'hamburgerMenu',
      'sidemenu' || 'sidenavigationmenu' || 'alcreensmenu' || 'allscreensmenu' => 'sideMenu',
      'calendarstylesidemenu' || 'calendarworkspacedrawer' || 'workspaceleftdrawer' || 'greenrevealdrawer' => 'calendarStyleSideMenu',
      'animatedsidemenu' || 'animatedsidemenureveal' || 'sliderevealpeekpanel' => 'animatedSideMenuReveal',
      'sidemenupeekpanel' || 'drawerpeekpanel' || 'peekpanel' => 'sideMenuPeekPanel',
      'sidemenucutpanel' || 'drawercutpanel' || 'cutpanel' || 'sliderevealcutpanel' => 'sideMenuCutPanel',
      'floatingsidesheet' || 'sidesheet' || 'drawersheet' => 'floatingSideSheet',
      'mergedhamburgersearch' || 'mergedsearchhamburger' || 'hamburgersearchpill' => 'mergedHamburgerSearch',
      'interactivetopsearch' || 'workingtopsearch' || 'topsearchfield' => 'interactiveTopSearch',
      'pillsearchbar' || 'floatingpillsearch' || 'topsearchpill' => 'pillSearchBar',
      'pagescopedtopsearch' || 'topsearchfilterscurrentpage' => 'pageScopedTopSearch',
      'universalsearchsubmit' || 'searchsubmitopensuniversal' => 'universalSearchSubmit',
      'globaluniversalsearch' || 'topnavglobalsearch' || 'searchallmodules' => 'globalUniversalSearch',
      'universalsearchcontroller' || 'globalsearchcontroller' => 'universalSearchController',
      'universalsearchresults' || 'globalresults' || 'searchresultlist' => 'universalSearchResults',
      'floatingresultssheet' || 'searchresultssheet' || 'floatingsearchresults' => 'floatingResultsSheet',
      'pagesearchactivepageonly' || 'activepageonlysearch' || 'pagesearchcontroller' => 'pageSearchActivePageOnly',
      'taskallfiltersubtabs' || 'taskopenalltabs' || 'pillsegmentedtasktabs' || 'openalltasktabs' => 'taskOpenAllTabs',
      'alltabicons' || 'sidemenuicons' => 'allTabIcons',
      'sidemenuiconmap' || 'routeiconmap' => 'sideMenuIconMap',
      'runtimesearchquery' || 'searchquerybinding' => 'runtimeSearchQuery',
      _ => value.isEmpty ? 'card' : value,
    };
  }

  static bool isSupportedWidgetType(dynamic raw) => supportedWidgetTypes.contains(canonicalWidgetType(raw));
  static bool isSupportedScreen(dynamic raw) => supportedScreens.contains(canonicalScreen(raw));

  /// Firestore/admin JSON may store fields such as type, screen, actions, or
  /// showFields as structured objects instead of primitive strings. Support
  /// analysis must never pass those raw objects into String-typed issue fields,
  /// otherwise the employee APK profile page can crash before rendering.
  static String _issueValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    if (value is Map) {
      for (final key in const <String>['value', 'label', 'name', 'title', 'text', 'type', 'screen', 'id']) {
        if (value.containsKey(key)) {
          final nested = _issueValue(value[key]).trim();
          if (nested.isNotEmpty) return nested;
        }
      }
      return 'object';
    }
    if (value is Iterable) {
      final joined = value.map(_issueValue).where((item) => item.trim().isNotEmpty).join(', ');
      return joined.isEmpty ? 'list' : joined;
    }
    return value.toString();
  }

  static SupportReport analyzeRawJson(Map<String, dynamic> json, {String rootPath = 'json'}) {
    final unsupported = <SupportIssue>[];

    void walk(dynamic node, String path) {
      if (node is Map) {
        final type = node['type'] ?? node['widget'] ?? node['component'] ?? node['componentType'];
        if (type != null && type.toString().isNotEmpty && !isSupportedWidgetType(type)) {
          unsupported.add(SupportIssue(path: '$path.type', value: _issueValue(type), message: 'This JSON widget type is not supported by the employee APK.'));
        }

        final screen = node['screen'];
        if (screen != null && screen.toString().isNotEmpty && !isSupportedScreen(screen)) {
          unsupported.add(SupportIssue(path: '$path.screen', value: _issueValue(screen), message: 'This screen is not supported by the employee APK.'));
        }

        final variant = node['variant']?.toString();
        final canonicalType = canonicalWidgetType(type);
        final variantRequiresCardSupport = _variantRequiresCardSupport(canonicalType, node);
        if (variantRequiresCardSupport && variant != null && variant.isNotEmpty && !supportedCardVariants.contains(variant)) {
          unsupported.add(SupportIssue(path: '$path.variant', value: _issueValue(variant), message: 'This visual variant is not supported by the employee APK.'));
        }

        final actions = node['actions'];
        if (actions is List) {
          for (final action in actions.map((item) => item.toString())) {
            if (!supportedActions.contains(action)) {
              unsupported.add(SupportIssue(path: '$path.actions', value: _issueValue(action), message: 'This action is not supported by the employee APK.'));
            }
          }
        }

        final singleAction = node['action'] ?? node['actionRoute'] ?? node['handler'];
        if (singleAction != null && singleAction.toString().isNotEmpty) {
          final actionValue = _issueValue(singleAction);
          if (actionValue.isNotEmpty && !supportedActions.contains(actionValue)) {
            unsupported.add(SupportIssue(path: '$path.action', value: _issueValue(singleAction), message: 'This action is not supported by the employee APK.'));
          }
        }

        final fields = node['showFields'] ?? node['fields'];
        if (fields is List) {
          final typeName = canonicalWidgetType(node['type'] ?? node['widget'] ?? node['component'] ?? node['componentType']);
          final supported = (typeName == 'projectCard' || typeName == 'projectDetails')
              ? supportedProjectFields
              : typeName == 'profileSummary'
                  ? supportedProfileFields
                  : supportedTaskFields.union(supportedProjectFields).union(supportedProfileFields);
          for (final field in fields.map((item) => item.toString())) {
            if (!supported.contains(field)) {
              unsupported.add(SupportIssue(path: '$path.showFields', value: _issueValue(field), message: 'This field is not supported by the employee APK renderer.'));
            }
          }
        }

        for (final childKey in <String>['children', 'sections', 'items', 'blocks', 'widgets', 'body', 'content', 'nodes']) {
          final list = node[childKey];
          if (list is List) {
            for (var i = 0; i < list.length; i++) {
              walk(list[i], '$path.$childKey[$i]');
            }
          }
        }
      } else if (node is List) {
        for (var i = 0; i < node.length; i++) {
          walk(node[i], '$path[$i]');
        }
      }
    }

    walk(json, rootPath);
    return SupportReport(issues: unsupported);
  }

  static bool _variantRequiresCardSupport(String canonicalType, Map<dynamic, dynamic> node) {
    if (canonicalType == 'topNav' ||
        canonicalType == 'bottomNav' ||
        canonicalType == 'floatingTopNav' ||
        canonicalType == 'floatingBottomNav' ||
        canonicalType == 'quickActionDock' ||
        canonicalType == 'hamburgerMenu' ||
        canonicalType == 'sideMenu' ||
        canonicalType == 'floatingSideSheet' ||
        canonicalType == 'mergedHamburgerSearch' ||
        canonicalType == 'interactiveTopSearch' ||
        canonicalType == 'runtimeSearchQuery' ||
        canonicalType == 'globalUniversalSearch' ||
        canonicalType == 'universalSearchController' ||
        canonicalType == 'universalSearchResults' ||
        canonicalType == 'floatingResultsSheet' ||
        canonicalType == 'pageSearchActivePageOnly' ||
        canonicalType == 'onboardingScreen' ||
        canonicalType == 'profileSummary' ||
        canonicalType == 'profileActionList' ||
        canonicalType == 'settingsList' ||
        canonicalType == 'notificationAlert' ||
        canonicalType == 'notificationSoundSelector' ||
        canonicalType == 'notificationDisplayWindow' ||
        canonicalType == 'taskMap' ||
        canonicalType == 'calendarView' ||
        canonicalType == 'progressTimeline' ||
        canonicalType == 'taskProgressTimeline') {
      return false;
    }
    return true;
  }

  static void _checkCard(String path, Map<String, dynamic> card, Set<String> supportedFields, List<SupportIssue> unsupported) {
    final variant = card['variant']?.toString();
    if (variant != null && !supportedCardVariants.contains(variant)) {
      unsupported.add(SupportIssue(path: '$path.variant', value: _issueValue(variant), message: 'This card variant is not available in the employee APK.'));
    }
    final fields = card['showFields'];
    if (fields is List) {
      for (final field in fields.map((item) => item.toString())) {
        if (!supportedFields.contains(field)) {
          unsupported.add(SupportIssue(path: '$path.showFields', value: _issueValue(field), message: 'This field is not rendered by the employee APK.'));
        }
      }
    }
    final actions = card['actions'];
    if (actions is List) {
      for (final action in actions.map((item) => item.toString())) {
        if (!supportedActions.contains(action)) {
          unsupported.add(SupportIssue(path: '$path.actions', value: _issueValue(action), message: 'This action is not rendered by the employee APK.'));
        }
      }
    }
  }
}

class SupportReport {
  const SupportReport({required this.issues});

  final List<SupportIssue> issues;
  bool get isFullySupported => issues.isEmpty;
}

class SupportIssue {
  const SupportIssue({required this.path, required this.value, required this.message});

  final String path;
  final String value;
  final String message;
}
