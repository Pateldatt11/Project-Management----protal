import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/workspace_state.dart';
import '../../../core/config/app_config.dart';
import '../../../core/crash/crashlytics_sdk.dart';
import '../../../core/crash/apk_crash_forensics.dart';
import '../../../core/constants/app_enums.dart';
import '../.
./../core/utils/date_utils.dart';
import '../../../core/platform/android_alert_notification_service.dart';
import '../../../core/security/biometric_settings_tile.dart';
import '../../../core/utils/json_value.dart';
import '../../../core/widgets/deadline_countdown_chip.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../features/auth/presentation/auth_gate.dart';
import '../../../data/firebase/auth_service.dart';
import '../../../data/models/project.dart';
import '../../../data/models/task.dart';
import '../../../data/models/app_notification.dart';
import 'mobile_ui_support_registry.dart';

/// Employee-mobile-only JSON renderer boundary.
///
/// Admin may import this for phone preview, but admin dashboard screens never run
/// from server JSON. Installed employee APKs render only what this registry supports.
///
/// When [previewMode] is true, controls react visually inside the admin emulator but
/// do not write to Firestore. In the employee APK, [previewMode] remains false and
/// task/profile updates are persisted through [workspaceProvider].
class MobileJsonUiRenderer extends ConsumerWidget {
  const MobileJsonUiRenderer({
    super.key,
    required this.json,
    this.fallback,
    this.previewMode = false,
    this.onAction,
    this.runtimeSearchQuery = '',
    this.suppressPageSearchBars = false,
    this.showChatBot = true,
  });

  final Map<String, dynamic> json;
  final Widget? fallback;
  final bool previewMode;
  final ValueChanged<String>? onAction;

  /// Optional legacy shell query. Current APK keeps top-nav search universal,
  /// while page-level search fields keep their own local query state.
  final String runtimeSearchQuery;
  final bool suppressPageSearchBars;
  final bool showChatBot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (json.isEmpty) return fallback ?? const SizedBox.shrink();
    try {
      final state = ref.watch(workspaceProvider);
      final report = _safeAnalyzeRawJson(json);
      final theme = _UiTheme.fromJson(_asMap(json['theme']) ?? _asMap(json['style']));
      final screen = _canonicalScreen(json['screen'] ?? json['screenKey'] ?? json['screenId'] ?? json['targetScreen'] ?? json['route'] ?? json['tab'] ?? json['type'] ?? 'screen');

      final rendererSafety = _rendererSafetyOf(json);
      final showUnsupportedBanner = _flag(
        rendererSafety['showUnsupportedBanner'] ??
            rendererSafety['showUnsupportedWarnings'] ??
            json['showUnsupportedBanner'],
        fallback: false,
      );

      return Stack(
        children: [
          Container(
            color: theme.background,
            child: Column(
              children: [
                if (!report.isFullySupported && showUnsupportedBanner) _UnsupportedBanner(count: report.issues.length),
                Expanded(child: _renderScreen(context, state, screen, json, theme)),
              ],
            ),
          ),
        ],
      );
    } catch (error, stackTrace) {
      debugPrint('SDUI renderer recovered from build error: $error');
      debugPrint('$stackTrace');
      ApkCrashForensics.recordError(error, stackTrace, fatal: false, source: 'MobileJsonUiRenderer.build');
      return fallback ?? _SduiRecoveryScreen(error: error);
    }
  }

  Widget _renderScreen(BuildContext context, WorkspaceState state, String screen, Map<String, dynamic> data, _UiTheme theme) {
    final strict = data['_strictJsonOnly'] == true || data['strictJsonOnly'] == true;
    final items = _dedupeNotificationAlertSettingsNodes(_orderedItemsOf(data));
    if (_isGenericScreenShell(screen)) {
      final inferredScreen = _inferScreenFromJsonShell(data, items);
      if (inferredScreen != null && inferredScreen != screen) {
        return _renderScreen(context, state, inferredScreen, data, theme);
      }
    }

    if (items.isNotEmpty && screen == 'home') {
      return _HomeJsonScreen(
        state: state,
        data: data,
        theme: theme,
        previewMode: previewMode,
        renderNode: _renderNode,
        runtimeSearchQuery: runtimeSearchQuery,
        suppressPageSearchBars: suppressPageSearchBars,
      );
    }

    if (items.isNotEmpty && screen == 'calendar') {
      // Calendar is an interactive date-filter screen. Even if older Firestore
      // JSON still contains an extra calendar.upcoming taskList section, the APK
      // must not render unrelated tasks below the selected-date result. The
      // calendar module owns the full screen and shows only tasks whose deadline
      // or assigned/created date matches the tapped date.
      return _CalendarDataJsonScreen(state: state, data: data, theme: theme);
    }

    if (screen == 'profile' || screen == 'profileSummary') {
      // Profile has interactive local state (online, availability, settings
      // accordion and real account actions). Render it through the dedicated
      // production profile renderer even when Firestore JSON contains a
      // `sections` list, otherwise every profile sub-section is rendered as a
      // full profile card by the generic JSON walker.
      return _ProfileJsonScreen(state: state, data: data, theme: theme, previewMode: previewMode);
    }

    if (screen == 'timeline' || screen == 'progressTimeline') {
      // Project milestones are a dedicated page. Do not let a generic
      // `sectionList` wrapper deactivate the milestone renderer.
      return _TimelineDataJsonScreen(state: state, data: data, theme: theme, onExternalAction: onAction);
    }

    if (screen == 'taskTimeline' || screen == 'taskProgressTimeline' || screen == 'productiveTaskTimeline') {
      // Task Timeline must be an active first-class screen. Earlier JSON
      // published it as a sectionList, which made the generic walker own the
      // route and the dedicated progress/timeline renderer never became active.
      return _TaskTimelineDataJsonScreen(state: state, data: data, theme: theme);
    }

    // Primary tab screens must keep their dedicated renderer even when the
    // admin-published JSON contains a `sections`/`items` wrapper. Otherwise the
    // generic walker marks nested project/task blocks as `embedded`, which is
    // correct for Home sections but wrong for the real Projects/Tasks pages.
    if (screen == 'tasks' || screen == 'taskList' || screen == 'taskPage' || screen == 'taskMenu') {
      return _TasksJsonScreen(
        state: state,
        data: data,
        theme: theme,
        previewMode: previewMode,
        runtimeSearchQuery: runtimeSearchQuery,
        suppressPageSearchBars: suppressPageSearchBars,
      );
    }

    if (screen == 'projects' || screen == 'projectList') {
      return _ProjectsJsonScreen(
        state: state,
        data: data,
        theme: theme,
        runtimeSearchQuery: runtimeSearchQuery,
        suppressPageSearchBars: suppressPageSearchBars,
      );
    }

    if (screen == 'board' || screen == 'kanbanBoard') {
      return _BoardJsonScreen(
        state: state,
        data: data,
        theme: theme,
        runtimeSearchQuery: runtimeSearchQuery,
        suppressPageSearchBars: suppressPageSearchBars,
      );
    }

    if (screen == 'notifications' || screen == 'notificationList') {
      return _NotificationsJsonScreen(state: state, data: data, theme: theme, runtimeSearchQuery: runtimeSearchQuery, suppressPageSearchBars: suppressPageSearchBars);
    }

    if (screen == 'meetings' || screen == 'meetingPage') {
      return _MeetingsJsonScreen(state: state, data: data, theme: theme, runtimeSearchQuery: runtimeSearchQuery, suppressPageSearchBars: suppressPageSearchBars);
    }

    if (items.isNotEmpty) {
      return _GenericItemsJsonScreen(
        state: state,
        data: data,
        theme: theme,
        items: items,
        renderNode: _renderNode,
        runtimeSearchQuery: runtimeSearchQuery,
        suppressPageSearchBars: suppressPageSearchBars,
      );
    }

    if (strict) {
      final rootType = _canonicalWidgetType(data['type'] ?? data['widget'] ?? data['component'] ?? data['componentType'] ?? screen);
      if (screen == 'projects' && (rootType == 'projectPage' || rootType == 'projectList' || rootType == 'projects')) {
        return _ProjectsJsonScreen(
          state: state,
          data: data,
          theme: theme,
          runtimeSearchQuery: '',
          suppressPageSearchBars: false,
        );
      }
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: _paddingOf(data['padding'], fallback: EdgeInsets.all(theme.padding)),
        children: [_renderNode(context, state, data, theme)],
      );
    }

    return switch (screen) {
      'home' || 'employeeHome' => _HomeJsonScreen(
          state: state,
          data: data,
          theme: theme,
          previewMode: previewMode,
          renderNode: _renderNode,
          runtimeSearchQuery: runtimeSearchQuery,
          suppressPageSearchBars: suppressPageSearchBars,
        ),
      'tasks' || 'taskList' || 'taskPage' || 'taskMenu' => _TasksJsonScreen(
          state: state,
          data: data,
          theme: theme,
          previewMode: previewMode,
          runtimeSearchQuery: runtimeSearchQuery,
          suppressPageSearchBars: suppressPageSearchBars,
        ),
      'projects' || 'projectList' => _ProjectsJsonScreen(
          state: state,
          data: data,
          theme: theme,
          runtimeSearchQuery: runtimeSearchQuery,
          suppressPageSearchBars: suppressPageSearchBars,
        ),
      'board' || 'kanbanBoard' => _BoardJsonScreen(
          state: state,
          data: data,
          theme: theme,
          runtimeSearchQuery: runtimeSearchQuery,
          suppressPageSearchBars: suppressPageSearchBars,
        ),
      'notifications' || 'notificationList' => _NotificationsJsonScreen(state: state, data: data, theme: theme, runtimeSearchQuery: runtimeSearchQuery, suppressPageSearchBars: suppressPageSearchBars),
      'meetings' || 'meetingPage' => _MeetingsJsonScreen(state: state, data: data, theme: theme, runtimeSearchQuery: runtimeSearchQuery, suppressPageSearchBars: suppressPageSearchBars),
      'profile' || 'profileSummary' => _ProfileJsonScreen(state: state, data: data, theme: theme, previewMode: previewMode),
      'taskMap' => _TaskMapDataJsonScreen(state: state, data: data, theme: theme),
      'calendar' => _CalendarDataJsonScreen(state: state, data: data, theme: theme),
      'timeline' => _TimelineDataJsonScreen(state: state, data: data, theme: theme, onExternalAction: onAction),
      'taskTimeline' => _TaskTimelineDataJsonScreen(state: state, data: data, theme: theme),
      'files' => _FilesDataJsonScreen(state: state, data: data, theme: theme),
      'teamMembers' => _TeamMembersDataJsonScreen(state: state, data: data, theme: theme),
      'taskDetail' => _TaskDetailDataJsonScreen(state: state, data: data, theme: theme, previewMode: previewMode),
      'projectDetail' => _ProjectDetailDataJsonScreen(state: state, data: data, theme: theme),
      'meetingDetail' => _MeetingDetailDataJsonScreen(state: state, data: data, theme: theme),
      'onboarding' => _OnboardingJsonScreen(
          state: state,
          data: data,
          theme: theme,
          previewMode: previewMode,
          onAction: onAction,
        ),
      'login' || 'signup' || 'auth' => _serverDrivenAuthDisabledOnWeb(previewMode: previewMode)
          ? (fallback ?? const SizedBox.shrink())
          : ListView(
              physics: const BouncingScrollPhysics(),
              padding: _paddingOf(data['padding'], fallback: EdgeInsets.all(theme.padding)),
              children: _orderedItemsOf(data).isEmpty ? [_renderNode(context, state, data, theme)] : _orderedItemsOf(data).map((item) => _renderNode(context, state, item, theme)).toList(),
            ),
      _ => ListView(padding: EdgeInsets.all(theme.padding), children: [_renderNode(context, state, data, theme)]),
    };
  }

  Widget _renderNode(BuildContext context, WorkspaceState state, dynamic node, _UiTheme theme) {
    try {
      return _renderNodeUnsafe(context, state, node, theme);
    } catch (error, stackTrace) {
      debugPrint('SDUI node recovered from render error: $error');
      ApkCrashForensics.recordError(error, stackTrace, fatal: false, source: 'MobileJsonUiRenderer._renderNode');
      final safety = _rendererSafetyOf(json);
      final hideBrokenNode = _flag(safety['hideBrokenNodes'] ?? safety['hideRenderErrors'], fallback: false);
      if (hideBrokenNode) return const SizedBox.shrink();
      return _JsonRecoveryNode(error: error, theme: theme);
    }
  }

  Widget _renderNodeUnsafe(BuildContext context, WorkspaceState state, dynamic node, _UiTheme theme) {
    if (node is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: node.map((item) => _renderNode(context, state, item, theme)).toList(),
      );
    }
    if (node is! Map) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(node?.toString() ?? '', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w700)),
      );
    }
    final data = node.map((key, value) => MapEntry(key.toString(), value));
    final type = _canonicalWidgetType(data['type'] ?? data['widget'] ?? data['component'] ?? data['componentType'] ?? 'card');

    if (!MobileUiSupportRegistry.supportedWidgetTypes.contains(type)) {
      final safety = _rendererSafetyOf(json);
      final mode = (data['unsupportedWidgetMode'] ??
              safety['unsupportedWidgetMode'] ??
              safety['unknownWidgetMode'] ??
              'legacyWarning')
          .toString()
          .trim()
          .toLowerCase();
      if (mode == 'hide' || mode == 'ignore' || mode == 'silent') {
        return const SizedBox.shrink();
      }
      if (_orderedItemsOf(data).isNotEmpty && (mode == 'safecard' || mode == 'safe' || mode == 'children' || mode == 'column')) {
        return _JsonColumn(data: data, state: state, theme: theme, renderNode: _renderNode);
      }
      return _JsonCard(
        title: data['title']?.toString() ?? data['label']?.toString() ?? type,
        subtitle: mode == 'safecard' || mode == 'safe'
            ? _textOf(data, 'subtitle', _textOf(data, 'text', 'Rendered as a safe JSON card because this widget is not a native primitive yet.'))
            : 'Unsupported in current APK renderer: $type',
        theme: theme,
        warning: mode != 'safecard' && mode != 'safe',
      );
    }

    return switch (type) {
      'screen' || 'page' || 'sectionList' || 'column' || 'list' || 'container' || 'sduiTemplate' || 'templateScreen' || 'templateSection' => _JsonColumn(data: data, state: state, theme: theme, renderNode: _renderNode),
      'row' => _JsonRow(data: data, state: state, theme: theme, renderNode: _renderNode),
      'grid' => _JsonGrid(data: data, state: state, theme: theme, renderNode: _renderNode),
      'text' || 'title' || 'subtitle' || 'label' => _JsonText(data: data, theme: theme, type: type),
      'divider' => Padding(padding: const EdgeInsets.only(bottom: 12), child: Divider(color: theme.border)),
      'spacer' => SizedBox(height: _num(data['height'], 12).toDouble().clamp(0, 120)),
      'card' => _JsonCard(title: _textOf(data, 'title', 'Card'), subtitle: _textOf(data, 'subtitle', _textOf(data, 'text', '')), theme: theme),
      'heroCard' || 'summaryCard' || 'workSummary' => _HeroJsonCard(data: data, state: state, theme: theme),
      'metricCard' => _MetricJsonCard(data: data, state: state, theme: theme),
      'deadlineCard' || 'deadlineHero' => _DeadlineFromTasksCard(state: state, data: data, theme: theme, title: _textOf(data, 'title', 'Next deadline')),
      'metricTile' => _MetricJsonCard(data: data, state: state, theme: theme),
      'activeProjectsGrid' => _ProjectsJsonScreen(
          state: state,
          data: data,
          theme: theme,
          embedded: true,
          runtimeSearchQuery: runtimeSearchQuery,
          suppressPageSearchBars: suppressPageSearchBars,
        ),
      'taskList' || 'todayTaskList' => _TasksJsonScreen(
          state: state,
          data: data,
          theme: theme,
          embedded: true,
          previewMode: previewMode,
          runtimeSearchQuery: runtimeSearchQuery,
          suppressPageSearchBars: suppressPageSearchBars,
        ),
      'taskCard' || 'taskDetails' => _EditableTaskCard(
          task: _firstTask(state),
          fields: _mergeStringLists(_fieldsOf(data, fallback: state.mobileUiDesign.taskFields), const <String>['projectName', 'taskTitle', 'status', 'priority', 'deadlineTimer', 'progress']),
          actions: _mergeStringLists(_actionsOf(data, fallback: state.mobileUiDesign.taskCard['actions']), const <String>['openDetails', 'comment', 'uploadFile']),
          variant: _cardVariant(data['variant'] ?? state.mobileUiDesign.taskCard['variant'], 'modernCard'),
          theme: theme,
          previewMode: previewMode,
          projectName: _firstTask(state) == null ? null : _projectName(state, _firstTask(state)!.projectId),
        ),
      'projectList' || 'projectPage' || 'projectProgressCard' => _ProjectsJsonScreen(
          state: state,
          data: data,
          theme: theme,
          embedded: true,
          runtimeSearchQuery: runtimeSearchQuery,
          suppressPageSearchBars: suppressPageSearchBars,
        ),
      'projectStatsGrid' || 'projectSummaryStrip' => _ProjectSummaryStrip(
          projects: state.visibleProjects,
          theme: theme,
          horizontal: _flag(data['horizontal'] ?? data['scroll'] ?? data['horizontalScroll'], fallback: false),
          config: data,
        ),
      'taskStatsGrid' || 'taskSummaryStrip' => _TaskSummaryStrip(tasks: state.visibleTasks, theme: theme, config: data),
      'homeMetricStrip' => _ProjectSummaryStrip(projects: state.visibleProjects, theme: theme, horizontal: true, config: data),
      'projectCard' || 'projectDetails' => _ProjectCard(project: _firstProject(state), fields: _mergeStringLists(_fieldsOf(data, fallback: state.mobileUiDesign.projectFields), const <String>['projectName', 'status', 'taskCount', 'team', 'deadline', 'progress']), variant: _cardVariant(data['variant'] ?? state.mobileUiDesign.projectCard['variant'], 'progressCard'), theme: theme, tasks: _firstProject(state) == null ? const <ProjectTask>[] : state.visibleTasks.where((task) => task.projectId == _firstProject(state)!.projectId).toList()),
      'onlineStatusCard' => _OnlineStatusCard(state: state, theme: theme, data: data, previewMode: previewMode),
      'notificationList' => _NotificationsJsonScreen(state: state, data: data, theme: theme, embedded: true, runtimeSearchQuery: runtimeSearchQuery, suppressPageSearchBars: suppressPageSearchBars),
      'meetingPage' || 'meetingList' || 'meetingInviteCard' || 'meetingActionButtons' => _MeetingsJsonScreen(state: state, data: data, theme: theme, embedded: true, runtimeSearchQuery: runtimeSearchQuery, suppressPageSearchBars: suppressPageSearchBars),
      'meetingCreateForm' || 'superAdminMeetingCreator' || 'meetingLinkInput' || 'adminMeetingAccess' => _JsonCard(title: _textOf(data, 'title', 'Meeting creator'), subtitle: 'Create meeting links from the admin Meetings page. Employee APK receives Accept & Join / Reject notifications.', theme: theme),
      'notificationAlert' || 'notificationSoundSelector' || 'notificationDisplayWindow' => _NotificationAlertSettingsJsonCard(theme: theme, alertConfig: state.mobileUiConfig.notificationAlertConfig, soundOptions: state.mobileUiConfig.notificationSoundOptions, previewMode: previewMode, embedded: data['embedded'] == true || data['insideSettings'] == true || data['flattened'] == true),
      'profileSummary' => _ProfileJsonScreen(state: state, data: data, theme: theme, embedded: true, previewMode: previewMode),
      'profileHeroCard' || 'profileStatsGrid' || 'profileInfoSection' || 'profileToggleRow' || 'profileQuickActions' => _ProfileJsonScreen(state: state, data: data, theme: theme, embedded: true, previewMode: previewMode),
      'onboardingChecklist' || 'onboardingMetricPill' => _OnboardingJsonScreen(state: state, data: data, theme: theme, previewMode: previewMode, embedded: true, onAction: onAction),
      'kanbanBoard' => _BoardJsonScreen(
          state: state,
          data: data,
          theme: theme,
          embedded: true,
          runtimeSearchQuery: runtimeSearchQuery,
          suppressPageSearchBars: suppressPageSearchBars,
        ),
      'progressBar' => _ProgressBar(data: data, theme: theme),
      'progressRing' => _MetricJsonCard(data: <String, dynamic>{...data, 'title': _textOf(data, 'title', 'Progress'), 'value': _textOf(data, 'value', '82%')}, state: state, theme: theme),
      'button' || 'actionButton' || 'primaryAction' || 'secondaryAction' || 'profileAction' || 'settingsTile' || 'profileSettingTile' => _JsonActionButton(
          data: data,
          theme: theme,
          previewMode: previewMode,
          onExternalAction: onAction,
        ),
      'profileActionList' => _JsonColumn(data: data, state: state, theme: theme, renderNode: _renderNode),
      'settingsList' => _SettingsListJson(data: data, state: state, theme: theme, renderNode: _renderNode),
      'wireframeAuthScreen' => _JsonColumn(data: data, state: state, theme: theme, renderNode: _renderNode),
      'authForm' => _AuthFormJson(data: data, theme: theme, previewMode: previewMode),
      'authLogo' => _AuthLogoJson(data: data, theme: theme),
      'input' || 'textField' || 'passwordField' => _InputJson(data: data, theme: theme, obscure: type == 'passwordField'),
      'socialAuthButton' => _SocialAuthButtonJson(data: data, theme: theme, previewMode: previewMode),
      'authSwitch' => _AuthSwitchJson(data: data, theme: theme),
      'chip' || 'badge' => Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Chip(label: Text(_textOf(data, 'label', _textOf(data, 'title', 'Badge')))),
          ),
        ),
      'icon' => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Icon(_iconFor(data['icon']?.toString()), color: theme.accent),
        ),
      'image' => _JsonCard(title: _textOf(data, 'title', 'Image'), subtitle: _textOf(data, 'url', 'Image preview is disabled in safe renderer.'), theme: theme),
      'floatingBottomNav' || 'floatingTopNav' || 'bottomNav' || 'topNav' || 'quickActionDock' || 'edgeToEdgeSystemBars' || 'androidFigureOneRightEdgeToEdge' || 'scrollAwareTopPadding' || 'systemBarContrastScrim' || 'gestureAwareBottomProtection' => const SizedBox.shrink(),
      'filterChips' => _FilterChipsJson(data: data, theme: theme),
      'searchHeader' => _SearchHeaderJson(data: data, theme: theme, onExternalAction: onAction),
      'taskProgressPanel' => _TaskProgressPanelJson(state: state, data: data, theme: theme),
      'taskTimelineBars' => _TaskTimelineBarsJson(state: state, data: data, theme: theme),
      'progressTimeline' => _TimelineDataJsonScreen(state: state, data: data, theme: theme, embedded: true, onExternalAction: onAction),
      'taskProgressTimeline' => _TaskTimelineDataJsonScreen(state: state, data: data, theme: theme, embedded: true),
      'onboardingScreen' => _OnboardingJsonScreen(state: state, data: data, theme: theme, previewMode: previewMode, embedded: true, onAction: onAction),
      'dashboardFeed' || 'projectFeed' => _JsonColumn(data: data, state: state, theme: theme, renderNode: _renderNode),
      'filesDocuments' => _FilesDataJsonScreen(state: state, data: data, theme: theme, embedded: true),
      'calendarView' => _CalendarDataJsonScreen(state: state, data: data, theme: theme, embedded: true),
      'taskMap' => _TaskMapDataJsonScreen(state: state, data: data, theme: theme, embedded: true),
      'teamMembers' => _TeamMembersDataJsonScreen(state: state, data: data, theme: theme, embedded: true),
      'statusPill' => Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 10), child: Chip(label: Text(_textOf(data, 'label', _textOf(data, 'title', 'Status')))))),
      'emptyState' => _JsonCard(title: _textOf(data, 'title', 'No items'), subtitle: _textOf(data, 'subtitle', 'Nothing to show yet.'), theme: theme),
      'skeletonLoader' => _JsonCard(title: 'Loading', subtitle: 'Skeleton loading placeholder', theme: theme),
      'nativeSheet' => _JsonCard(title: _textOf(data, 'title', 'Action sheet'), subtitle: _textOf(data, 'subtitle', 'Native sheet placeholder'), theme: theme),
      _ => _JsonCard(title: _textOf(data, 'title', data['id']?.toString() ?? type), subtitle: type, theme: theme),
    };
  }
}


bool _isGenericScreenShell(String screen) {
  return screen == 'screen' || screen == 'page' || screen == 'sectionList' || screen == 'container' || screen == 'list';
}

String? _inferScreenFromJsonShell(Map<String, dynamic> data, List<dynamic> items) {
  for (final key in const <String>['screenKey', 'screenId', 'targetScreen', 'route', 'tab', 'id']) {
    final raw = data[key]?.toString().trim();
    if (raw == null || raw.isEmpty) continue;
    final screen = _canonicalScreen(raw);
    if (const <String>{
      'home',
      'tasks',
      'projects',
      'board',
      'notifications',
      'meetings',
      'profile',
      'calendar',
      'taskMap',
      'timeline',
      'files',
      'teamMembers',
      'taskDetail',
      'projectDetail',
      'meetingDetail',
      'onboarding',
      'login',
      'signup',
      'auth',
    }.contains(screen)) {
      return screen;
    }
  }

  final types = <String>{};
  final ids = <String>{};
  for (final item in items.whereType<Map>()) {
    types.add(_canonicalWidgetType(item['type'] ?? item['widget'] ?? item['component'] ?? item['componentType'] ?? item['id']));
    final id = item['id']?.toString().trim();
    if (id != null && id.isNotEmpty) ids.add(id.toLowerCase());
  }

  // Home publishes a sectionList containing mixed modules such as workSummary,
  // metrics, activeProjects and todayTasks. Do not mistake its embedded
  // project/task modules for the real Projects or Tasks tab.
  if (ids.any((id) => id == 'worksummary' || id == 'metrics' || id == 'activeprojects' || id == 'todaytasks') ||
      types.any((type) => type == 'deadlineHero' || type == 'todayTaskList' || type == 'activeHomeMetrics' || type == 'workSummary')) {
    return 'home';
  }
  if (types.any((type) => type == 'taskPage' || type == 'taskMenu')) return 'tasks';
  if (types.any((type) => type == 'projectPage' || type == 'projectProgressCard')) return 'projects';
  if (types.contains('kanbanBoard')) return 'board';
  if (types.contains('notificationList')) return 'notifications';
  if (types.any((type) => type == 'meetingPage' || type == 'meetingList' || type == 'meetingInviteCard')) return 'meetings';
  if (types.any((type) => type == 'profileSummary' || type == 'profileHeroCard' || type == 'profileInfoSection')) return 'profile';
  if (types.contains('calendarView')) return 'calendar';
  if (types.contains('taskMap')) return 'taskMap';
  if (types.contains('progressTimeline')) return 'timeline';
  if (types.contains('filesDocuments')) return 'files';
  if (types.contains('teamMembers')) return 'teamMembers';
  return null;
}


bool _serverDrivenAuthDisabledOnWeb({required bool previewMode}) {
  // Mobile auth SDUI is an APK/iOS runtime feature. Flutter Web keeps the
  // stable web auth screen so admin/web login cannot be broken by mobile-only
  // login or signup experiments. Admin emulator preview may still render it.
  return kIsWeb && !previewMode;
}

SupportReport _safeAnalyzeRawJson(Map<String, dynamic> json) {
  try {
    return MobileUiSupportRegistry.analyzeRawJson(json);
  } catch (error) {
    // The production APK must continue rendering even if the admin-published
    // JSON has unexpected nested objects in registry-only fields.
    return SupportReport(
      issues: <SupportIssue>[
        SupportIssue(path: 'json', value: error.toString(), message: 'Support analysis failed but rendering continued.'),
      ],
    );
  }
}

class _GenericItemsJsonScreen extends StatefulWidget {
  const _GenericItemsJsonScreen({
    required this.state,
    required this.data,
    required this.theme,
    required this.items,
    required this.renderNode,
    this.runtimeSearchQuery = '',
    this.suppressPageSearchBars = false,
  });

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final List<dynamic> items;
  final Widget Function(BuildContext, WorkspaceState, dynamic, _UiTheme) renderNode;
  final String runtimeSearchQuery;
  final bool suppressPageSearchBars;

  @override
  State<_GenericItemsJsonScreen> createState() => _GenericItemsJsonScreenState();
}

class _GenericItemsJsonScreenState extends State<_GenericItemsJsonScreen> {
  String _query = '';
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final shellQuery = _normalizeSearchQuery(widget.runtimeSearchQuery);
    final q = shellQuery.isNotEmpty ? shellQuery : _normalizeSearchQuery(_query);
    final searchNodes = <dynamic>[];
    final filterNodes = <dynamic>[];
    final contentNodes = <dynamic>[];

    for (final item in widget.items) {
      final type = item is Map
          ? _canonicalWidgetType(item['type'] ?? item['widget'] ?? item['component'] ?? item['componentType'])
          : '';
      if (type == 'searchHeader') {
        searchNodes.add(item);
      } else if (type == 'filterChips') {
        filterNodes.add(item);
      } else {
        contentNodes.add(item);
      }
    }

    final filteredContent = contentNodes.where((item) {
      final matchesSearch = q.isEmpty || _matchesGenericPageItemQuery(widget.state, item, q);
      final matchesFilter = _matchesGenericPageItemFilter(widget.state, item, _filter);
      return matchesSearch && matchesFilter;
    }).toList();
    final hasActiveFilter = !_isAllPageFilter(_filter);
    final children = <Widget>[
      if (!widget.suppressPageSearchBars && shellQuery.isEmpty)
        ...searchNodes.map((item) {
          final map = item is Map ? item.map((key, value) => MapEntry(key.toString(), value)) : <String, dynamic>{};
          return _ProjectPageNavSearchBox(
            theme: widget.theme,
            hint: _textOf(map, 'placeholder', _textOf(map, 'hint', _textOf(map, 'label', 'Search this page'))),
            initialQuery: _query,
            resultCount: filteredContent.length,
            resultName: 'item',
            clearTooltip: 'Clear page search',
            onChanged: (value) => setState(() => _query = value),
          );
        }),
      ...filterNodes.map((item) {
        final map = item is Map ? item.map((key, value) => MapEntry(key.toString(), value)) : <String, dynamic>{};
        return _FilterChipsJson(
          data: map,
          theme: widget.theme,
          selected: _filter,
          onChanged: (value) => setState(() => _filter = value),
        );
      }),
      if ((q.isNotEmpty || hasActiveFilter) && filteredContent.isEmpty)
        _JsonCard(
          title: 'No matching content',
          subtitle: 'This page has no card or section matching the current search/filter.',
          theme: widget.theme,
        ),
      ...filteredContent.map((item) => _renderScopedItem(context, item, q, _filter)),
    ];

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: _paddingOf(widget.data['padding'], fallback: EdgeInsets.all(widget.theme.padding)),
      children: children,
    );
  }

  Widget _renderScopedItem(BuildContext context, dynamic item, String query, String filter) {
    if (item is! Map) return widget.renderNode(context, widget.state, item, widget.theme);
    final map = item.map((key, value) => MapEntry(key.toString(), value));
    final type = _canonicalWidgetType(map['type'] ?? map['widget'] ?? map['component'] ?? map['componentType'] ?? map['id']);
    if (type == 'taskList' || type == 'todayTaskList' || type == 'taskPage') {
      return _TasksJsonScreen(
        state: widget.state,
        data: map,
        theme: widget.theme,
        embedded: true,
        runtimeSearchQuery: query,
        runtimeContentFilter: filter,
        suppressPageSearchBars: true,
      );
    }
    if (type == 'projectPage' || type == 'projectProgressCard' || type == 'projectList' || type == 'activeProjectsGrid') {
      return _ProjectsJsonScreen(
        state: widget.state,
        data: map,
        theme: widget.theme,
        embedded: true,
        runtimeSearchQuery: query,
        runtimeContentFilter: filter,
        suppressPageSearchBars: true,
      );
    }
    if (type == 'kanbanBoard') {
      return _BoardJsonScreen(
        state: widget.state,
        data: map,
        theme: widget.theme,
        embedded: true,
        runtimeSearchQuery: query,
        runtimeContentFilter: filter,
        suppressPageSearchBars: true,
      );
    }
    if (type == 'notificationList') {
      return _NotificationsJsonScreen(
        state: widget.state,
        data: map,
        theme: widget.theme,
        embedded: true,
        runtimeSearchQuery: query,
        runtimeContentFilter: filter,
        suppressPageSearchBars: true,
      );
    }
    if (type == 'meetingPage' || type == 'meetingList' || type == 'meetingInviteCard') {
      return _MeetingsJsonScreen(
        state: widget.state,
        data: map,
        theme: widget.theme,
        embedded: true,
        runtimeSearchQuery: query,
        runtimeContentFilter: filter,
        suppressPageSearchBars: true,
      );
    }
    if (type == 'taskMap') {
      return _TaskMapDataJsonScreen(state: widget.state, data: map, theme: widget.theme, embedded: true);
    }
    if (type == 'calendarView') {
      return _CalendarDataJsonScreen(state: widget.state, data: map, theme: widget.theme, embedded: true);
    }
    if (type == 'progressTimeline') {
      return _TimelineDataJsonScreen(state: widget.state, data: map, theme: widget.theme, embedded: true);
    }
    if (type == 'teamMembers') {
      return _TeamMembersDataJsonScreen(state: widget.state, data: map, theme: widget.theme, embedded: true);
    }
    if (type == 'filesDocuments') {
      return _FilesDataJsonScreen(state: widget.state, data: map, theme: widget.theme, embedded: true);
    }
    return _SectionResultBadge(
      theme: widget.theme,
      label: _sectionResultLabelForType(type),
      icon: _sectionResultIconForType(type),
      visible: _normalizeSearchQuery(query).isNotEmpty || !_isAllPageFilter(filter),
      child: widget.renderNode(context, widget.state, map, widget.theme),
    );
  }
}

class _HomeJsonScreen extends StatefulWidget {
  const _HomeJsonScreen({
    required this.state,
    required this.data,
    required this.theme,
    required this.previewMode,
    required this.renderNode,
    this.runtimeSearchQuery = '',
    this.suppressPageSearchBars = false,
  });

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool previewMode;
  final Widget Function(BuildContext, WorkspaceState, dynamic, _UiTheme) renderNode;
  final String runtimeSearchQuery;
  final bool suppressPageSearchBars;

  @override
  State<_HomeJsonScreen> createState() => _HomeJsonScreenState();
}

class _HomeJsonScreenState extends State<_HomeJsonScreen> {
  String _query = '';
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final sections = _itemsOf(widget.data).isEmpty ? widget.state.mobileUiDesign.sections : _itemsOf(widget.data);
    final sectionMaps = sections.whereType<Map>().where((section) => section['visible'] != false).toList();
    Map<String, dynamic>? searchHeader;
    final filterNodes = <Map<String, dynamic>>[];
    for (final section in sectionMaps) {
      final type = _canonicalWidgetType(section['type'] ?? section['widget'] ?? section['component'] ?? section['componentType']);
      if (type == 'searchHeader' && searchHeader == null) {
        searchHeader = section.map((key, value) => MapEntry(key.toString(), value));
      } else if (type == 'filterChips') {
        filterNodes.add(section.map((key, value) => MapEntry(key.toString(), value)));
      }
    }
    final visibleSections = sectionMaps.where((section) {
      final type = _canonicalWidgetType(section['type'] ?? section['widget'] ?? section['component'] ?? section['componentType']);
      return type != 'searchHeader' && type != 'filterChips';
    }).toList();
    final shellQuery = _normalizeSearchQuery(widget.runtimeSearchQuery);
    final q = shellQuery.isNotEmpty ? shellQuery : _normalizeSearchQuery(_query);
    final filteredSections = visibleSections.where((section) {
      final matchesSearch = q.isEmpty || _matchesHomeSectionQuery(widget.state, section, q);
      final matchesFilter = _matchesHomeSectionFilter(widget.state, section, _filter);
      return matchesSearch && matchesFilter;
    }).toList();
    final hasActiveFilter = !_isAllPageFilter(_filter);
    final showSearch = !widget.suppressPageSearchBars && shellQuery.isEmpty && _flag(widget.data['showSearch'] ?? widget.data['allowPageSearchBar'], fallback: true);
    final searchHint = searchHeader == null
        ? _textOf(_asMap(widget.data['search']) ?? const <String, dynamic>{}, 'hint', 'Search this home page')
        : _textOf(searchHeader, 'placeholder', _textOf(searchHeader, 'hint', _textOf(searchHeader, 'label', 'Search this home page')));

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: _paddingOf(widget.data['padding'], fallback: EdgeInsets.all(widget.theme.padding)),
      children: [
        if (widget.data['hideTitle'] != true)
          _ScreenTitle(
            title: _textOf(widget.data, 'title', 'My Work'),
            subtitle: _textOf(widget.data, 'subtitle', 'Server-driven employee mobile UI'),
          ),
        if (showSearch)
          _ProjectPageNavSearchBox(
            theme: widget.theme,
            hint: searchHint,
            initialQuery: _query,
            resultCount: filteredSections.length,
            resultName: 'section',
            clearTooltip: 'Clear home search',
            onChanged: (value) => setState(() => _query = value),
          ),
        ...filterNodes.map((filterNode) => _FilterChipsJson(
              data: filterNode,
              theme: widget.theme,
              selected: _filter,
              onChanged: (value) => setState(() => _filter = value),
            )),
        if ((q.isNotEmpty || hasActiveFilter) && filteredSections.isEmpty)
          _JsonCard(
            title: 'No matching home section',
            subtitle: 'No Home card or section matches the current search/filter.',
            theme: widget.theme,
          ),
        ...filteredSections.map((section) {
          final map = section.map((key, value) => MapEntry(key.toString(), value));
          final type = _canonicalWidgetType(map['type'] ?? map['widget'] ?? map['component'] ?? 'summaryCard');
          if (type == 'taskList' || type == 'todayTaskList' || type == 'taskPage' || type == 'taskMenu') {
            return _TasksJsonScreen(
              state: widget.state,
              data: map,
              theme: widget.theme,
              embedded: type != 'taskPage' && type != 'taskMenu',
              previewMode: widget.previewMode,
              runtimeSearchQuery: q,
              runtimeContentFilter: _filter,
              suppressPageSearchBars: widget.suppressPageSearchBars,
            );
          }
          if (type == 'projectProgressCard' || type == 'projectList' || type == 'projectPage' || type == 'activeProjectsGrid') {
            return _ProjectsJsonScreen(
              state: widget.state,
              data: map,
              theme: widget.theme,
              embedded: true,
              runtimeSearchQuery: q,
              runtimeContentFilter: _filter,
              suppressPageSearchBars: widget.suppressPageSearchBars,
            );
          }
          if (type == 'kanbanBoard') {
            return _BoardJsonScreen(
              state: widget.state,
              data: map,
              theme: widget.theme,
              embedded: true,
              runtimeSearchQuery: q,
              runtimeContentFilter: _filter,
              suppressPageSearchBars: widget.suppressPageSearchBars,
            );
          }
          if (type == 'notificationList') {
            return _NotificationsJsonScreen(
              state: widget.state,
              data: map,
              theme: widget.theme,
              embedded: true,
              runtimeSearchQuery: q,
              runtimeContentFilter: _filter,
              suppressPageSearchBars: widget.suppressPageSearchBars,
            );
          }
          if (type == 'meetingPage' || type == 'meetingList' || type == 'meetingInviteCard') {
            return _MeetingsJsonScreen(
              state: widget.state,
              data: map,
              theme: widget.theme,
              embedded: true,
              runtimeSearchQuery: q,
              runtimeContentFilter: _filter,
              suppressPageSearchBars: widget.suppressPageSearchBars,
            );
          }
          if (type == 'onlineStatusCard') {
            return _SectionResultBadge(
              theme: widget.theme,
              label: _sectionResultLabelForType(type),
              icon: _sectionResultIconForType(type),
              visible: q.isNotEmpty || !_isAllPageFilter(_filter),
              child: _OnlineStatusCard(state: widget.state, theme: widget.theme, data: map, previewMode: widget.previewMode),
            );
          }
          if (type == 'deadlineCard') {
            return _SectionResultBadge(
              theme: widget.theme,
              label: _sectionResultLabelForType(type),
              icon: _sectionResultIconForType(type),
              visible: q.isNotEmpty || !_isAllPageFilter(_filter),
              child: _DeadlineFromTasksCard(state: widget.state, data: map, theme: widget.theme, title: map['title']?.toString() ?? 'Next deadline'),
            );
          }
          if (type == 'heroCard') {
            return _SectionResultBadge(
              theme: widget.theme,
              label: _sectionResultLabelForType(type),
              icon: _sectionResultIconForType(type),
              visible: q.isNotEmpty || !_isAllPageFilter(_filter),
              child: _HeroJsonCard(data: map, state: widget.state, theme: widget.theme),
            );
          }
          return _SectionResultBadge(
            theme: widget.theme,
            label: _sectionResultLabelForType(type),
            icon: _sectionResultIconForType(type),
            visible: q.isNotEmpty || !_isAllPageFilter(_filter),
            child: widget.renderNode(context, widget.state, map, widget.theme),
          );
        }),
      ],
    );
  }
}

class _TasksJsonScreen extends StatefulWidget {
  const _TasksJsonScreen({
    required this.state,
    required this.data,
    required this.theme,
    this.embedded = false,
    this.previewMode = false,
    this.runtimeSearchQuery = '',
    this.runtimeContentFilter = 'All',
    this.suppressPageSearchBars = false,
  });

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;
  final bool previewMode;
  final String runtimeSearchQuery;
  final String runtimeContentFilter;
  final bool suppressPageSearchBars;

  @override
  State<_TasksJsonScreen> createState() => _TasksJsonScreenState();
}

enum _TasksJsonTab { newArrival, allTasks, completed }

class _TasksJsonScreenState extends State<_TasksJsonScreen> {
  _TasksJsonTab _tab = _TasksJsonTab.newArrival;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final requested = (widget.data['defaultTab'] ?? widget.data['taskFilter'] ?? '').toString().toLowerCase().trim();
    if (requested == 'completed' || requested == 'done') _tab = _TasksJsonTab.completed;
    if (requested == 'all' || requested == 'alltasks' || requested == 'all_tasks') {
      _tab = _TasksJsonTab.allTasks;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final data = widget.data;
    final theme = widget.theme;
    final embedded = widget.embedded;
    final taskCardMap = _asMap(data['taskCard']);
    final fields = _mergeStringLists(
      _stringList(data['showFields'] ?? data['fields'] ?? taskCardMap?['showFields'], fallback: state.mobileUiDesign.taskFields),
      const <String>['projectName', 'taskTitle', 'status', 'priority', 'deadlineTimer', 'progress'],
    );
    final actions = _mergeStringLists(
      _actionsOf(data, fallback: taskCardMap?['actions'] ?? state.mobileUiDesign.taskCard['actions']),
      const <String>['openDetails', 'comment', 'uploadFile'],
    );
    final variant = _cardVariant(data['variant'] ?? taskCardMap?['variant'] ?? state.mobileUiDesign.taskCard['variant'], 'modernCard');
    final limit = _num(data['limit'], embedded ? 3 : 30).round().clamp(1, 80).toInt();
    final source = data['type'] == 'todayTaskList'
        ? state.visibleTasks.where((t) => _isSameDate(t.dueDate, DateTime.now())).toList()
        : state.visibleTasks.toList();
    final q = _normalizeSearchQuery(embedded ? widget.runtimeSearchQuery : _query);
    final hasRuntimeFilter = !_isAllPageFilter(widget.runtimeContentFilter);
    final scopedSource = hasRuntimeFilter ? source.where((task) => _matchesTaskFilter(state, task, widget.runtimeContentFilter)).toList() : source;
    final rawSource = q.isEmpty ? scopedSource : scopedSource.where((task) => _matchesTaskQuery(state, task, q)).toList();
    final newTasks = rawSource.where((task) => task.status != TaskStatus.completed).toList()
      ..sort((a, b) => _taskActivityDateForSort(b).compareTo(_taskActivityDateForSort(a)));
    final completedTasks = rawSource.where((task) => task.status == TaskStatus.completed).toList()
      ..sort((a, b) => _taskCompletedDateForSort(b).compareTo(_taskCompletedDateForSort(a)));
    final showSummary = !embedded && _flag(data['showSummary'] ?? data['showTaskSummary'] ?? data['showStats'], fallback: true);
    final showSearch = !embedded &&
        !widget.suppressPageSearchBars &&
        _flag(data['showSearch'] ?? data['allowPageSearchBar'] ?? data['allowInlineSearch'], fallback: true);
    final showTabs = !embedded && _flag(data['showFloatingTabs'] ?? data['showFilters'], fallback: true);
    final showCompletedTab = _flag(data['showCompletedTab'], fallback: true);
    final showAllFilterSubTabs = _flag(
      data['showAllFilterSubTabs'] ??
          data['showOpenAllTabs'] ??
          data['showAllTasksModeTabs'] ??
          data['taskAllFilterSubTabs'],
      fallback: false,
    );
    final allPrimaryFilterActive = _isAllPageFilter(widget.runtimeContentFilter);
    final showOpenAllTabs = embedded && allPrimaryFilterActive && showAllFilterSubTabs;
    final activeTab = showOpenAllTabs
        ? (_tab == _TasksJsonTab.allTasks ? _TasksJsonTab.allTasks : _TasksJsonTab.newArrival)
        : (showCompletedTab ? (_tab == _TasksJsonTab.allTasks ? _TasksJsonTab.newArrival : _tab) : _TasksJsonTab.newArrival);
    final selected = showOpenAllTabs
        ? (activeTab == _TasksJsonTab.allTasks ? rawSource : newTasks).take(limit).toList()
        : (embedded && (q.isNotEmpty || hasRuntimeFilter)
            ? rawSource.take(limit).toList()
            : (activeTab == _TasksJsonTab.completed ? completedTasks : newTasks).take(limit).toList());
    final emptyTitle = showOpenAllTabs && activeTab == _TasksJsonTab.allTasks
        ? 'No tasks'
        : (activeTab == _TasksJsonTab.completed ? 'No completed tasks' : 'No new/open tasks');
    final emptySubtitle = q.isNotEmpty
        ? 'Try changing the search text or tab.'
        : (showOpenAllTabs && activeTab == _TasksJsonTab.allTasks
            ? 'All assigned tasks will appear here when Firestore task data is available.'
            : (activeTab == _TasksJsonTab.completed
                ? 'Completed tasks will appear here after status is marked completed.'
                : 'Newest assigned and open tasks appear first here.'));
    final searchBeforeStats = _pageSearchComesBeforeStats(data);
    final summaryBeforeFilters = _pageSummaryComesBeforeFilters(data);
    final taskSearchWidget = showSearch
        ? _ProjectPageNavSearchBox(
            theme: theme,
            hint: _textOf(_asMap(data['search']) ?? const <String, dynamic>{}, 'hint', 'Search assigned tasks'),
            initialQuery: _query,
            resultCount: selected.length,
            resultName: 'task',
            clearTooltip: 'Clear task search',
            onChanged: (value) => setState(() => _query = value),
          )
        : null;
    final taskSummaryWidget = showSummary ? _TaskSummaryStrip(tasks: rawSource, theme: theme, config: data) : null;
    final taskFilterWidgets = <Widget>[
      if (showOpenAllTabs) ...[
        _TasksOpenAllTabs(
          selected: activeTab,
          newOpenCount: newTasks.length,
          allCount: rawSource.length,
          theme: theme,
          onChanged: (value) => setState(() => _tab = value),
        ),
        const SizedBox(height: 12),
      ] else if (showTabs) ...[
        _TasksSduiFloatingTabs(
          selected: activeTab,
          newCount: newTasks.length,
          completedCount: completedTasks.length,
          showCompleted: showCompletedTab,
          theme: theme,
          onChanged: (value) => setState(() => _tab = value),
        ),
        const SizedBox(height: 12),
      ],
    ];
    final children = <Widget>[
      if (!embedded && data['hideTitle'] != true)
        _ScreenTitle(
          title: _textOf(data, 'title', 'My Tasks'),
          subtitle: _textOf(data, 'subtitle', '${rawSource.length} synced task(s) from Firestore'),
        ),
      if (searchBeforeStats && taskSearchWidget != null) taskSearchWidget,
      if (summaryBeforeFilters && taskSummaryWidget != null) taskSummaryWidget,
      ...taskFilterWidgets,
      if (!summaryBeforeFilters && taskSummaryWidget != null) taskSummaryWidget,
      if (!searchBeforeStats && taskSearchWidget != null) taskSearchWidget,
      if (selected.isEmpty)
        _JsonCard(
          title: emptyTitle,
          subtitle: emptySubtitle,
          theme: theme,
        ),
      ...selected.map((task) => _SectionResultBadge(
            theme: theme,
            label: 'Task section',
            icon: Icons.task_alt_rounded,
            visible: _showSourceBadges(embedded: embedded, query: q, filter: widget.runtimeContentFilter),
            child: _EditableTaskCard(
              task: task,
              fields: fields,
              actions: actions,
              variant: variant,
              theme: theme,
              previewMode: widget.previewMode,
              projectName: _projectName(state, task.projectId),
            ),
          )),
    ];
    return embedded ? Column(children: children) : ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(theme.padding), children: children);
  }
}

class _TaskSummaryStrip extends StatelessWidget {
  const _TaskSummaryStrip({required this.tasks, required this.theme, this.config});

  final List<ProjectTask> tasks;
  final _UiTheme theme;
  final Map<String, dynamic>? config;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final completed = tasks.where((task) => task.status == TaskStatus.completed).length;
    final active = tasks.where((task) => task.status != TaskStatus.completed).length;
    final delayed = tasks.where((task) => task.status != TaskStatus.completed && task.dueDate.isBefore(now)).length;
    final average = tasks.isEmpty ? 0 : ((completed / tasks.length) * 100).round();
    final stats = _jsonOrderedStats(
      config,
      theme,
      <String, _ProjectStatData>{
        'total': _ProjectStatData('Total', tasks.length.toString(), Icons.task_alt_rounded, theme.accent),
        'active': _ProjectStatData('Active', active.toString(), Icons.bolt_rounded, const Color(0xFF2563EB)),
        'delayed': _ProjectStatData('Delayed', delayed.toString(), Icons.warning_amber_rounded, const Color(0xFFDC2626)),
        'average': _ProjectStatData('Average', '$average%', Icons.auto_graph_rounded, const Color(0xFF16A34A)),
        'done': _ProjectStatData('Done', completed.toString(), Icons.verified_rounded, const Color(0xFF059669)),
        'completed': _ProjectStatData('Completed', completed.toString(), Icons.verified_rounded, const Color(0xFF059669)),
        'open': _ProjectStatData('Open', active.toString(), Icons.task_alt_rounded, const Color(0xFF2563EB)),
      },
      const <String>['total', 'active', 'delayed', 'average', 'done'],
    );

    return _ResponsiveStatsGrid(stats: stats, theme: theme);
  }
}


class _TaskSearchBox extends StatelessWidget {
  const _TaskSearchBox({required this.theme, required this.hint, required this.onChanged});

  final _UiTheme theme;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(Icons.search_rounded, color: theme.accent),
          filled: true,
          fillColor: theme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: theme.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: theme.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: theme.accent, width: 1.4)),
        ),
      ),
    );
  }
}

class _TasksOpenAllTabs extends StatelessWidget {
  const _TasksOpenAllTabs({
    required this.selected,
    required this.newOpenCount,
    required this.allCount,
    required this.theme,
    required this.onChanged,
  });

  final _TasksJsonTab selected;
  final int newOpenCount;
  final int allCount;
  final _UiTheme theme;
  final ValueChanged<_TasksJsonTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final availableWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : screenWidth;
        // Overflow protection: compact labels are used only on narrow phones.
        // Wider screens keep the normal readable labels.
        final compact = availableWidth < 390;
        final medium = availableWidth >= 390 && availableWidth < 470;
        final newOpenLabel = compact ? 'New tas...' : (medium ? 'New/Open' : 'New/Open tasks');
        final allTasksLabel = compact ? 'All tas...' : 'All tasks';
        final tabMaxWidth = compact
            ? ((availableWidth - 10) / 2).clamp(112.0, 158.0).toDouble()
            : (medium ? 178.0 : 228.0);

        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: availableWidth),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: theme.border),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 20, offset: const Offset(0, 10))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: _TasksSduiFloatingTab(
                      label: newOpenLabel,
                      count: newOpenCount,
                      icon: Icons.fiber_new_rounded,
                      selected: selected != _TasksJsonTab.allTasks,
                      theme: theme,
                      maxWidth: tabMaxWidth,
                      dense: compact,
                      onTap: () => onChanged(_TasksJsonTab.newArrival),
                    ),
                  ),
                  Flexible(
                    child: _TasksSduiFloatingTab(
                      label: allTasksLabel,
                      count: allCount,
                      icon: Icons.task_alt_rounded,
                      selected: selected == _TasksJsonTab.allTasks,
                      theme: theme,
                      maxWidth: tabMaxWidth,
                      dense: compact,
                      onTap: () => onChanged(_TasksJsonTab.allTasks),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TasksSduiFloatingTabs extends StatelessWidget {
  const _TasksSduiFloatingTabs({required this.selected, required this.newCount, required this.completedCount, required this.showCompleted, required this.theme, required this.onChanged});

  final _TasksJsonTab selected;
  final int newCount;
  final int completedCount;
  final bool showCompleted;
  final _UiTheme theme;
  final ValueChanged<_TasksJsonTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TasksSduiFloatingTab(
            label: 'New tas...',
            count: newCount,
            icon: Icons.fiber_new_rounded,
            selected: selected == _TasksJsonTab.newArrival,
            theme: theme,
            onTap: () => onChanged(_TasksJsonTab.newArrival),
          ),
          if (showCompleted)
            _TasksSduiFloatingTab(
              label: 'Completed',
              count: completedCount,
              icon: Icons.check_circle_rounded,
              selected: selected == _TasksJsonTab.completed,
              theme: theme,
              onTap: () => onChanged(_TasksJsonTab.completed),
            ),
        ],
      ),
    );
  }
}

class _TasksSduiFloatingTab extends StatelessWidget {
  const _TasksSduiFloatingTab({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.theme,
    required this.onTap,
    this.maxWidth = 168,
    this.dense = false,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final _UiTheme theme;
  final VoidCallback onTap;
  final double maxWidth;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : theme.textSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? theme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: dense ? 16 : 18, color: fg),
              SizedBox(width: dense ? 4 : 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(color: fg, fontSize: dense ? 13 : null, fontWeight: FontWeight.w900),
                ),
              ),
              SizedBox(width: dense ? 4 : 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 7, vertical: 2),
                decoration: BoxDecoration(color: selected ? Colors.white.withOpacity(.20) : theme.background, borderRadius: BorderRadius.circular(999)),
                child: Text('$count', style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

DateTime _taskActivityDateForSort(ProjectTask task) => task.createdAt ?? task.updatedAt ?? task.completedAt ?? task.dueDate;
DateTime _taskCompletedDateForSort(ProjectTask task) => task.completedAt ?? task.updatedAt ?? task.createdAt ?? task.dueDate;

class _ProjectsJsonScreen extends StatefulWidget {
  const _ProjectsJsonScreen({
    required this.state,
    required this.data,
    required this.theme,
    this.embedded = false,
    this.runtimeSearchQuery = '',
    this.runtimeContentFilter = 'All',
    this.suppressPageSearchBars = false,
  });

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;
  final String runtimeSearchQuery;
  final String runtimeContentFilter;
  final bool suppressPageSearchBars;

  @override
  State<_ProjectsJsonScreen> createState() => _ProjectsJsonScreenState();
}

class _ProjectsJsonScreenState extends State<_ProjectsJsonScreen> {
  String _query = '';
  String _statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final data = widget.data;
    final theme = widget.theme;
    final embedded = widget.embedded;
    final projectCardMap = _asMap(data['projectCard']);
    final fields = _mergeStringLists(
      _stringList(data['showFields'] ?? data['fields'] ?? projectCardMap?['showFields'], fallback: state.mobileUiDesign.projectFields),
      const <String>['projectName', 'status', 'statusTag', 'taskCount', 'teamCount', 'deadline', 'progress', 'completedTaskCount'],
    );
    final variant = _cardVariant(data['variant'] ?? projectCardMap?['variant'] ?? state.mobileUiDesign.projectCard['variant'], 'progressCard');
    final limit = _num(data['limit'], embedded ? 6 : 50).round().clamp(1, 80).toInt();
    final showHeader = data['hideTitle'] != true && (!embedded || _flag(data['showHeader'], fallback: true));
    final showSummary = _flag(data['showSummary'], fallback: true);
    final summaryLayout = (data['summaryLayout'] ?? data['projectSummaryLayout'] ?? data['statsLayout'] ?? '').toString().trim().toLowerCase();
    final summaryHorizontal = embedded || summaryLayout.contains('horizontal') || summaryLayout.contains('scroll');
    // Page-level project search is intentionally local to this Projects page.
    // The top-nav search remains universal and must not feed this query.
    final showSearch = !embedded &&
        !widget.suppressPageSearchBars &&
        _flag(data['showSearch'], fallback: true);
    final showStatusFilters = _flag(data['showStatusFilters'], fallback: true);
    final allProjects = state.visibleProjects;
    final q = _normalizeSearchQuery(embedded ? widget.runtimeSearchQuery : _query);
    final scopedProjects = _isAllPageFilter(widget.runtimeContentFilter)
        ? allProjects
        : allProjects.where((project) => _matchesProjectFilter(state, project, widget.runtimeContentFilter)).toList();
    final searchedProjects = q.isEmpty ? scopedProjects : scopedProjects.where((project) => _matchesProjectQuery(state, project, q)).toList();
    final filtered = searchedProjects.where((project) {
      final matchesStatus = switch (_statusFilter) {
        'all' => true,
        'active' => project.isActiveWork,
        'delayed' => project.isDelayed,
        _ => project.status.value == _statusFilter,
      };
      return matchesStatus;
    }).take(limit).toList();

    final searchBeforeStats = _pageSearchComesBeforeStats(data);
    final summaryBeforeFilters = _pageSummaryComesBeforeFilters(data);
    final projectSearchWidget = showSearch
        ? _ProjectPageNavSearchBox(
            theme: theme,
            hint: _textOf(_asMap(data['search']) ?? const <String, dynamic>{}, 'hint', 'Search active project name or details'),
            initialQuery: _query,
            resultCount: filtered.length,
            resultName: 'project',
            clearTooltip: 'Clear project search',
            onChanged: (value) => setState(() => _query = value),
          )
        : null;
    final projectSummaryWidget = showSummary
        ? _ProjectSummaryStrip(
            projects: searchedProjects,
            theme: theme,
            horizontal: summaryHorizontal,
            config: data,
          )
        : null;
    final projectFilterWidget = showStatusFilters
        ? _ProjectStatusFilters(
            theme: theme,
            selected: _statusFilter,
            onChanged: (value) => setState(() => _statusFilter = value),
          )
        : null;

    final children = <Widget>[
      if (showHeader)
        _ScreenTitle(
          title: _textOf(data, 'title', 'Projects'),
          subtitle: _textOf(data, 'subtitle', '${allProjects.length} synced project(s) from Firestore'),
        ),
      if (searchBeforeStats && projectSearchWidget != null) projectSearchWidget,
      if (summaryBeforeFilters && projectSummaryWidget != null) projectSummaryWidget,
      if (projectFilterWidget != null) projectFilterWidget,
      if (!summaryBeforeFilters && projectSummaryWidget != null) projectSummaryWidget,
      if (!searchBeforeStats && projectSearchWidget != null) projectSearchWidget,
      if (filtered.isEmpty)
        _JsonCard(
          title: q.isEmpty ? 'No projects' : 'No matching projects',
          subtitle: q.isEmpty ? 'No visible projects found.' : 'Try clearing search or changing the status filter.',
          theme: theme,
        ),
      ...filtered.map(
        (project) => _SectionResultBadge(
          theme: theme,
          label: 'Project section',
          icon: Icons.folder_rounded,
          visible: _showSourceBadges(embedded: embedded, query: q, filter: widget.runtimeContentFilter),
          child: _ProjectCard(
            project: project,
            fields: fields,
            variant: variant,
            theme: theme,
            tasks: state.visibleTasks.where((task) => task.projectId == project.projectId).toList(),
          ),
        ),
      ),
    ];
    return embedded ? Column(children: children) : ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(theme.padding), children: children);
  }
}

class _ProjectSummaryStrip extends StatelessWidget {
  const _ProjectSummaryStrip({
    required this.projects,
    required this.theme,
    this.horizontal = false,
    this.config,
  });

  final List<Project> projects;
  final _UiTheme theme;
  final Map<String, dynamic>? config;

  /// Embedded project summaries usually appear inside Home/feed sections.
  /// Keep those as the older horizontal metric strip so Home does not become
  /// a tall 2-column stats block. Full project/task-related pages keep the
  /// newer responsive wrap/grid summary.
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final active = projects.where((project) => project.isActiveWork).length;
    final completed = projects.where((project) => project.status == ProjectStatus.completed).length;
    final delayed = projects.where((project) => project.isDelayed).length;
    final average = projects.isEmpty ? 0 : (projects.fold<int>(0, (sum, project) => sum + project.progress) / projects.length).round();
    final stats = _jsonOrderedStats(
      config,
      theme,
      <String, _ProjectStatData>{
        'total': _ProjectStatData('Total', projects.length.toString(), Icons.folder_rounded, theme.accent),
        'active': _ProjectStatData('Active', active.toString(), Icons.bolt_rounded, const Color(0xFF2563EB)),
        'delayed': _ProjectStatData('Delayed', delayed.toString(), Icons.warning_amber_rounded, const Color(0xFFDC2626)),
        'average': _ProjectStatData('Average', '$average%', Icons.auto_graph_rounded, const Color(0xFF16A34A)),
        'done': _ProjectStatData('Done', completed.toString(), Icons.verified_rounded, const Color(0xFF059669)),
        'completed': _ProjectStatData('Completed', completed.toString(), Icons.verified_rounded, const Color(0xFF059669)),
        'open': _ProjectStatData('Open', active.toString(), Icons.folder_open_rounded, const Color(0xFF2563EB)),
      },
      const <String>['total', 'active', 'delayed', 'average', 'done'],
    );

    return _ResponsiveStatsGrid(stats: stats, theme: theme, horizontal: horizontal);
  }
}

class _ResponsiveStatsGrid extends StatelessWidget {
  const _ResponsiveStatsGrid({required this.stats, required this.theme, this.horizontal = false});

  final List<_ProjectStatData> stats;
  final _UiTheme theme;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaWidth = MediaQuery.sizeOf(context).width;
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : mediaWidth;
        final safeWidth = maxWidth.clamp(0.0, 1200.0).toDouble();

        if (horizontal) {
          final cardWidth = safeWidth < 330
              ? 124.0
              : safeWidth < 420
                  ? 132.0
                  : 148.0;
          final height = safeWidth < 330 ? 76.0 : 80.0;
          return SizedBox(
            height: height,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 12),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: stats.length,
              separatorBuilder: (_, __) => SizedBox(width: safeWidth < 330 ? 8 : 10),
              itemBuilder: (context, index) => SizedBox(
                width: cardWidth,
                child: _ProjectStatCard(data: stats[index], theme: theme),
              ),
            ),
          );
        }

        final columns = _adaptiveProjectColumns(safeWidth, stats.length);
        final spacing = safeWidth < 340 ? 8.0 : 10.0;
        final itemWidth = columns <= 1 ? safeWidth : (safeWidth - (spacing * (columns - 1))) / columns;
        final spanLastFullWidth = columns == 2 && stats.length.isOdd && safeWidth < 600;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: stats.asMap().entries.map((entry) {
              final isLast = entry.key == stats.length - 1;
              final width = spanLastFullWidth && isLast ? safeWidth : itemWidth;
              return SizedBox(
                width: width,
                child: _ProjectStatCard(data: entry.value, theme: theme),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

int _adaptiveProjectColumns(double width, int itemCount) {
  if (itemCount <= 1) return 1;
  if (width < 270) return 1;
  if (width < 600) return 2;
  if (width < 860) return 3;
  return 4;
}


List<_ProjectStatData> _jsonOrderedStats(
  Map<String, dynamic>? config,
  _UiTheme theme,
  Map<String, _ProjectStatData> base,
  List<String> fallbackOrder,
) {
  final rawItems = config?['summaryStats'] ?? config?['stats'] ?? config?['metricCards'] ?? config?['summaryCards'];
  final output = <_ProjectStatData>[];
  String normalizeKey(Object? value) => (value?.toString() ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s_\-/]+'), '');
  _ProjectStatData? byKey(Object? value) {
    final token = normalizeKey(value);
    if (token.isEmpty) return null;
    for (final entry in base.entries) {
      final key = normalizeKey(entry.key);
      final label = normalizeKey(entry.value.label);
      if (token == key || token == label || token.contains(key) || token.contains(label)) return entry.value;
    }
    return null;
  }

  if (rawItems is List) {
    for (final item in rawItems) {
      if (item is Map) {
        final map = item.map((key, value) => MapEntry(key.toString(), value));
        if (_flag(map['visible'] ?? map['enabled'], fallback: true) == false) continue;
        final baseItem = byKey(map['key'] ?? map['id'] ?? map['source'] ?? map['label'] ?? map['title']);
        final fallback = baseItem ?? _ProjectStatData(
          _textOf(map, 'label', _textOf(map, 'title', 'Metric')),
          _textOf(map, 'value', '0'),
          _iconFor(map['icon']?.toString()),
          _color(map['color']?.toString(), theme.accent),
        );
        output.add(_ProjectStatData(
          _textOf(map, 'label', _textOf(map, 'title', fallback.label)),
          _textOf(map, 'value', fallback.value),
          _iconFor(map['icon']?.toString()) == Icons.circle_rounded ? fallback.icon : _iconFor(map['icon']?.toString()),
          _color(map['color']?.toString(), fallback.color),
        ));
      } else {
        final stat = byKey(item);
        if (stat != null) output.add(stat);
      }
    }
  }

  if (output.isNotEmpty) return output;
  return fallbackOrder.map((key) => base[key]).whereType<_ProjectStatData>().toList();
}

class _ProjectStatData {
  const _ProjectStatData(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _ProjectStatCard extends StatelessWidget {
  const _ProjectStatCard({required this.data, required this.theme});
  final _ProjectStatData data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 140.0;
        final compact = maxWidth < 132;
        final tiny = maxWidth < 108;
        final iconSize = tiny ? 28.0 : compact ? 31.0 : 34.0;
        final iconRadius = tiny ? 11.0 : 14.0;
        final gap = tiny ? 7.0 : 9.0;
        return Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: compact ? 62 : 66),
          padding: EdgeInsets.symmetric(horizontal: tiny ? 9 : compact ? 10 : 12, vertical: compact ? 9 : 10),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: data.color.withOpacity(.16)),
            boxShadow: [BoxShadow(color: data.color.withOpacity(.07), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(color: data.color.withOpacity(.10), borderRadius: BorderRadius.circular(iconRadius)),
                child: Icon(data.icon, color: data.color, size: tiny ? 15 : 18),
              ),
              SizedBox(width: gap),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: (maxWidth - iconSize - gap - 24).clamp(48.0, 900.0).toDouble()),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(data.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: compact ? 16 : 17)),
                        Text(data.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: compact ? 10.5 : 11)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProjectSearchBox extends StatelessWidget {
  const _ProjectSearchBox({required this.theme, required this.hint, required this.onChanged});

  final _UiTheme theme;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(Icons.search_rounded, color: theme.accent),
          filled: true,
          fillColor: theme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: theme.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: theme.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: theme.accent, width: 1.4)),
        ),
      ),
    );
  }
}

class _ProjectPageNavSearchBox extends StatefulWidget {
  const _ProjectPageNavSearchBox({
    required this.theme,
    required this.hint,
    required this.onChanged,
    required this.resultCount,
    this.initialQuery = '',
    this.resultName = 'project',
    this.clearTooltip = 'Clear page search',
  });

  final _UiTheme theme;
  final String hint;
  final String initialQuery;
  final int resultCount;
  final String resultName;
  final String clearTooltip;
  final ValueChanged<String> onChanged;

  @override
  State<_ProjectPageNavSearchBox> createState() => _ProjectPageNavSearchBoxState();
}

class _ProjectPageNavSearchBoxState extends State<_ProjectPageNavSearchBox> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void didUpdateWidget(covariant _ProjectPageNavSearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery && widget.initialQuery != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initialQuery,
        selection: TextSelection.collapsed(offset: widget.initialQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    final resultLabel = widget.resultCount == 1 ? '1 ${widget.resultName}' : '${widget.resultCount} ${widget.resultName}s';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: widget.theme.surface,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              widget.theme.surface,
              Color.lerp(widget.theme.surface, widget.theme.accent, .035) ?? widget.theme.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: widget.theme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.06),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.theme.accent.withOpacity(.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: widget.theme.accent.withOpacity(.16)),
              ),
              child: Icon(Icons.search_rounded, color: widget.theme.accent, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  setState(() {});
                  widget.onChanged(value);
                },
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w700),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: hasText
                  ? IconButton(
                      key: const ValueKey<String>('clear'),
                      tooltip: widget.clearTooltip,
                      icon: Icon(Icons.close_rounded, color: widget.theme.textSecondary),
                      onPressed: () {
                        _controller.clear();
                        setState(() {});
                        widget.onChanged('');
                      },
                    )
                  : Container(
                      key: const ValueKey<String>('count'),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.theme.accent.withOpacity(.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: widget.theme.accent.withOpacity(.14)),
                      ),
                      child: Text(
                        resultLabel,
                        style: TextStyle(color: widget.theme.accent, fontSize: 11, fontWeight: FontWeight.w900),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}



bool _pageSearchComesBeforeStats(Map<String, dynamic> data) {
  // v168: page order is controlled by Firestore JSON. The renderer only
  // interprets placement keys; it must not force metrics above the search bar.
  final searchPlacement = (data['searchPlacement'] ?? data['pageSearchPlacement'] ?? '').toString().trim().toLowerCase();
  final summaryPlacement = (data['summaryPlacement'] ?? data['statsPlacement'] ?? data['projectSummaryPlacement'] ?? data['taskSummaryPlacement'] ?? '').toString().trim().toLowerCase();
  final explicitOrder = _stringList(
    data['contentOrder'] ?? data['layoutOrder'] ?? data['sectionOrder'] ?? data['pageOrder'],
    fallback: const <String>[],
  ).map((item) => item.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '')).toList();

  int indexOfAny(Iterable<String> keys) {
    for (var i = 0; i < explicitOrder.length; i++) {
      final value = explicitOrder[i];
      if (keys.any((key) => value == key || value.contains(key))) return i;
    }
    return -1;
  }

  final searchIndex = indexOfAny(const <String>['search', 'pagesearch', 'searchheader']);
  final statsIndex = indexOfAny(const <String>['stats', 'summary', 'metrics', 'projectsummary', 'tasksummary']);
  if (searchIndex >= 0 && statsIndex >= 0) return searchIndex < statsIndex;

  if (summaryPlacement.contains('beforesearch') || summaryPlacement.contains('top')) return false;
  if (searchPlacement.contains('after') && (searchPlacement.contains('summary') || searchPlacement.contains('stats') || searchPlacement.contains('metrics'))) {
    return false;
  }
  if (searchPlacement.contains('first') || searchPlacement.contains('top') || searchPlacement.contains('before')) return true;

  // Default to search first. This matches the published screenOverrides order:
  // search -> filters -> feed/stats/content.
  return true;
}

bool _pageSummaryComesBeforeFilters(Map<String, dynamic> data) {
  // v170: Projects/Tasks page sequence is JSON-controlled. The requested
  // default for non-Home pages is search -> summary -> filters -> content.
  // Home still renders its own sectionList exactly as published.
  final summaryPlacement = (data['summaryPlacement'] ??
          data['statsPlacement'] ??
          data['projectSummaryPlacement'] ??
          data['taskSummaryPlacement'] ??
          '')
      .toString()
      .trim()
      .toLowerCase();
  final filterPlacement = (data['filterPlacement'] ?? data['filtersPlacement'] ?? data['tabPlacement'] ?? '').toString().trim().toLowerCase();
  final explicitOrder = _stringList(
    data['contentOrder'] ?? data['layoutOrder'] ?? data['sectionOrder'] ?? data['pageOrder'],
    fallback: const <String>[],
  ).map((item) => item.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '')).toList();

  int indexOfAny(Iterable<String> keys) {
    for (var i = 0; i < explicitOrder.length; i++) {
      final value = explicitOrder[i];
      if (keys.any((key) => value == key || value.contains(key))) return i;
    }
    return -1;
  }

  final summaryIndex = indexOfAny(const <String>['summary', 'stats', 'metrics', 'projectsummary', 'tasksummary']);
  final filterIndex = indexOfAny(const <String>['filter', 'filters', 'tabs', 'chips', 'statusfilter', 'tasktabs']);
  if (summaryIndex >= 0 && filterIndex >= 0) return summaryIndex < filterIndex;

  if (filterPlacement.contains('beforesummary') || filterPlacement.contains('beforestats')) return false;
  if (summaryPlacement.contains('afterfilter') || summaryPlacement.contains('aftertab') || summaryPlacement.contains('afterchip')) return false;
  if (summaryPlacement.contains('beforefilter') ||
      summaryPlacement.contains('beforetab') ||
      summaryPlacement.contains('beforechip') ||
      summaryPlacement.contains('aftersearch')) {
    return true;
  }

  return _flag(data['summaryBeforeFilters'] ?? data['statsBeforeFilters'], fallback: true);
}

class _SectionResultBadge extends StatelessWidget {
  const _SectionResultBadge({required this.theme, required this.label, required this.icon, required this.child, required this.visible});

  final _UiTheme theme;
  final String label;
  final IconData icon;
  final Widget child;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.accent.withOpacity(.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: theme.accent.withOpacity(.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: theme.accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(color: theme.accent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .1),
                ),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

String _sectionResultLabelForType(String type) {
  return switch (type) {
    'taskList' || 'todayTaskList' || 'taskPage' || 'taskMenu' => 'Task section',
    'projectPage' || 'projectList' || 'projectProgressCard' || 'activeProjectsGrid' => 'Project section',
    'kanbanBoard' => 'Board section',
    'notificationList' => 'Inbox section',
    'meetingPage' || 'meetingList' || 'meetingInviteCard' => 'Meeting section',
    'deadlineCard' || 'deadlineHero' => 'Deadline section',
    'onlineStatusCard' => 'Profile section',
    'heroCard' || 'summaryCard' || 'metricCard' || 'metricTile' => 'Dashboard section',
    _ => 'Page section',
  };
}

IconData _sectionResultIconForType(String type) {
  return switch (type) {
    'taskList' || 'todayTaskList' || 'taskPage' || 'taskMenu' => Icons.task_alt_rounded,
    'projectPage' || 'projectList' || 'projectProgressCard' || 'activeProjectsGrid' => Icons.folder_rounded,
    'kanbanBoard' => Icons.view_kanban_rounded,
    'notificationList' => Icons.notifications_rounded,
    'meetingPage' || 'meetingList' || 'meetingInviteCard' => Icons.video_call_rounded,
    'deadlineCard' || 'deadlineHero' => Icons.timer_rounded,
    'onlineStatusCard' => Icons.person_rounded,
    'heroCard' || 'summaryCard' || 'metricCard' || 'metricTile' => Icons.dashboard_customize_rounded,
    _ => Icons.label_rounded,
  };
}

bool _showSourceBadges({required bool embedded, required String query, required String filter}) {
  return embedded && (_normalizeSearchQuery(query).isNotEmpty || !_isAllPageFilter(filter));
}

class _ProjectStatusFilters extends StatelessWidget {
  const _ProjectStatusFilters({required this.theme, required this.selected, required this.onChanged});
  final _UiTheme theme;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final filters = <Map<String, dynamic>>[
      {'value': 'all', 'label': 'All', 'shortLabel': 'All', 'icon': Icons.apps_rounded},
      {'value': ProjectStatus.active.value, 'label': 'In Progress', 'shortLabel': 'In prog...', 'icon': Icons.bolt_rounded},
      {'value': ProjectStatus.completed.value, 'label': 'Completed', 'shortLabel': 'Done', 'icon': Icons.verified_rounded},
      {'value': ProjectStatus.onHold.value, 'label': 'On Hold', 'shortLabel': 'On hold', 'icon': Icons.pause_circle_rounded},
      {'value': ProjectStatus.review.value, 'label': 'Review', 'shortLabel': 'Review', 'icon': Icons.rate_review_rounded},
      {'value': 'delayed', 'label': 'Delayed', 'shortLabel': 'Delayed', 'icon': Icons.warning_amber_rounded},
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
        final columns = _adaptiveProjectColumns(maxWidth, filters.length);
        const spacing = 8.0;
        final itemWidth = ((maxWidth - (spacing * (columns - 1))) / columns).clamp(98.0, 220.0).toDouble();
        final useShortLabels = itemWidth < 124;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: spacing,
            runSpacing: 8,
            children: filters.map((filter) {
              final value = filter['value']!.toString();
              final isSelected = selected == value;
              final label = useShortLabels ? (filter['shortLabel'] ?? filter['label']).toString() : filter['label']!.toString();
              return SizedBox(
                width: itemWidth,
                child: _AdaptiveProjectFilterPill(
                  selected: isSelected,
                  label: label,
                  icon: filter['icon'] as IconData,
                  theme: theme,
                  onTap: () => onChanged(value),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _AdaptiveProjectFilterPill extends StatelessWidget {
  const _AdaptiveProjectFilterPill({
    required this.selected,
    required this.label,
    required this.icon,
    required this.theme,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final _UiTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected ? theme.accent : theme.surface;
    final foreground = selected ? Colors.white : theme.textPrimary;
    final iconColor = selected ? Colors.white : theme.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? theme.accent : theme.border),
            boxShadow: selected ? [BoxShadow(color: theme.accent.withOpacity(.16), blurRadius: 14, offset: const Offset(0, 8))] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, color: foreground, fontSize: 13.5, height: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardJsonScreen extends StatefulWidget {
  const _BoardJsonScreen({
    required this.state,
    required this.data,
    required this.theme,
    this.embedded = false,
    this.runtimeSearchQuery = '',
    this.runtimeContentFilter = 'All',
    this.suppressPageSearchBars = false,
  });
  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;
  final String runtimeSearchQuery;
  final String runtimeContentFilter;
  final bool suppressPageSearchBars;

  @override
  State<_BoardJsonScreen> createState() => _BoardJsonScreenState();
}

class _BoardJsonScreenState extends State<_BoardJsonScreen> {
  String _query = '';
  String _projectId = 'all';
  String _filter = 'all';
  String? _selectedPhaseId;

  // Task Board carousel scroll fix:
  // Do not jump the parent ListView to minScrollExtent when a card swipe starts.
  // The jump was causing the visible spring-back to the screen start. Instead,
  // keep the parent controller stable and hold the current scroll activity while
  // the horizontal PageView owns the gesture.
  final ScrollController _boardScrollController = ScrollController();
  ScrollHoldController? _boardScrollHold;
  double? _boardHeldScrollOffset;

  @override
  void dispose() {
    _boardScrollHold?.cancel();
    _boardScrollController.dispose();
    super.dispose();
  }

  void _setBoardCarouselScrollHold(bool hold) {
    if (widget.embedded) return;

    if (hold) {
      if (!_boardScrollController.hasClients) return;
      final position = _boardScrollController.position;
      _boardHeldScrollOffset = position.pixels;
      _boardScrollHold?.cancel();
      _boardScrollHold = position.hold(() {});
      return;
    }

    final restoreOffset = _boardHeldScrollOffset;
    _boardHeldScrollOffset = null;
    _boardScrollHold?.cancel();
    _boardScrollHold = null;

    if (restoreOffset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_boardScrollController.hasClients) return;
      final position = _boardScrollController.position;
      final target = restoreOffset.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
      if ((position.pixels - target).abs() > 1.0) {
        _boardScrollController.jumpTo(target);
      }
    });
  }

  Future<void> _openBoardTaskDetailSheet(BuildContext context, ProjectTask task) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.28),
      builder: (sheetContext) => _PinterestTaskDetailSheet(
        theme: widget.theme,
        task: task,
        projectName: _projectName(widget.state, task.projectId),
        assignees: _assigneeNamesForTask(widget.state, task),
      ),
    );
  }

  Future<void> _handleBoardTaskTap(BuildContext context, ProjectTask task, {required bool openDetailOnTap}) async {
    HapticFeedback.selectionClick();
    if (!openDetailOnTap) return;

    final openFullPage = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(.42),
      builder: (dialogContext) => _TaskBoardPreviewDialog(
        theme: widget.theme,
        task: task,
        projectName: _projectName(widget.state, task.projectId),
        assignees: _assigneeNamesForTask(widget.state, task),
      ),
    );

    if (!mounted || openFullPage != true) return;
    await _openBoardTaskDetailSheet(context, task);
  }

  Future<void> _openPhaseProjectSheet(BuildContext context, _DesignerTaskBoardCardData card, {required bool openDetailOnTap}) async {
    HapticFeedback.selectionClick();
    setState(() => _selectedPhaseId = card.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.34),
      builder: (sheetContext) => _PhaseProjectTaskSheet(
        theme: widget.theme,
        state: widget.state,
        card: card,
        onTaskTap: (task) async {
          Navigator.of(sheetContext).pop();
          if (!mounted) return;
          await _handleBoardTaskTap(context, task, openDetailOnTap: openDetailOnTap);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final data = widget.data;
    final theme = widget.theme;
    final embedded = widget.embedded;
    final shellQuery = _normalizeSearchQuery(embedded ? widget.runtimeSearchQuery : _query);
    final contentFilter = widget.runtimeContentFilter;
    final allTasks = _boardTasksForState(state);
    final projectScoped = _projectId == 'all' ? allTasks : allTasks.where((task) => task.projectId == _projectId).toList();
    final filtered = projectScoped.where((task) {
      if (!_matchesTaskFilter(state, task, contentFilter)) return false;
      if (!_matchesTaskBoardFilter(task, _filter)) return false;
      if (shellQuery.isNotEmpty && !_matchesTaskQuery(state, task, shellQuery)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
        final priority = b.priority.index.compareTo(a.priority.index);
        if (priority != 0) return priority;
        return a.dueDate.compareTo(b.dueDate);
      });
    final designerCards = _designerTaskBoardCardsForTasks(filtered);
    final cardMotionEnabled = _flag(
      data['cardMotionEnabled'] ?? data['middlePhoneContentMotion'] ?? data['animatedMainCards'] ?? data['mainCardMotionEnabled'],
      fallback: true,
    );
    final openDetailOnTap = _flag(
      data['openTaskDetailOnTap'] ?? data['tapCardOpensDetail'] ?? data['taskCardDetailSheetEnabled'],
      fallback: true,
    );

    final children = <Widget>[
      // v210: phase cards stay visible even when a phase has no active task.
      // Tapping the active carousel card opens the phase project list first;
      // selecting a project then reveals only tasks that belong to that phase.
      if (designerCards.isEmpty)
        _JsonCard(
          title: 'No task board phases',
          subtitle: 'Phase cards will appear here after the SDUI task-board renderer is enabled.',
          theme: theme,
        )
      else
        _TaskBoardVerticalStackCarousel(
          theme: theme,
          state: state,
          data: data,
          cards: designerCards,
          selectedPhaseId: _selectedPhaseId,
          motionEnabled: cardMotionEnabled,
          onCarouselScrollHoldChanged: _setBoardCarouselScrollHold,
          onPhaseTap: (card) => _openPhaseProjectSheet(context, card, openDetailOnTap: openDetailOnTap),
        ),
    ];
    return embedded
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)
        : ListView(
            key: const PageStorageKey<String>('mobile-task-board-scroll-stable'),
            controller: _boardScrollController,
            primary: false,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: _taskBoardScreenPadding(data, theme, context),
            children: children,
          );
  }
}

List<ProjectTask> _boardTasksForState(WorkspaceState state) {
  final visible = state.visibleTasks.toList();
  if (visible.isNotEmpty) return visible;
  return _timelineTasksForState(state);
}

List<Project> _boardProjectsForState(WorkspaceState state, List<ProjectTask> tasks) {
  final ids = tasks.map((task) => task.projectId).where((id) => id.trim().isNotEmpty).toSet();
  final projects = state.projects.where((project) => ids.contains(project.projectId)).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  if (projects.isNotEmpty) return projects;
  return state.visibleProjects.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

EdgeInsets _taskBoardScreenPadding(Map<String, dynamic> data, _UiTheme theme, BuildContext context) {
  final mediaSize = MediaQuery.maybeOf(context)?.size ?? Size.zero;
  final compactPhone = mediaSize.width > 0 && mediaSize.width <= 390;
  final paddingData = _taskBoardPaddingData(data);

  // Task Board has a floating top-nav + stacked-card hero. Keep the APK-safe
  // hardcoded default padding, but also accept explicit Admin/Firestore padding
  // objects. This lets you tune the Task Board edge gap from JSON without
  // changing Dart again.
  final fallbackHorizontal = compactPhone ? 16.0 : math.max(18.0, theme.padding.toDouble());

  final horizontal = _num(
    _taskBoardPaddingValue(paddingData, const <String>['horizontal', 'x', 'side', 'sides']) ??
        data['taskBoardHorizontalPadding'] ??
        data['phaseStackScreenHorizontalPadding'] ??
        data['phaseStackHorizontalPadding'] ??
        data['screenHorizontalPadding'],
    fallbackHorizontal,
  ).toDouble().clamp(compactPhone ? 14.0 : 16.0, compactPhone ? 22.0 : 30.0).toDouble();

  final left = _num(
    _taskBoardPaddingValue(paddingData, const <String>['left', 'start']) ??
        data['taskBoardLeftPadding'] ??
        data['phaseStackScreenLeftPadding'],
    horizontal,
  ).toDouble().clamp(compactPhone ? 14.0 : 16.0, compactPhone ? 24.0 : 34.0).toDouble();

  final right = _num(
    _taskBoardPaddingValue(paddingData, const <String>['right', 'end']) ??
        data['taskBoardRightPadding'] ??
        data['phaseStackScreenRightPadding'],
    horizontal,
  ).toDouble().clamp(compactPhone ? 14.0 : 16.0, compactPhone ? 24.0 : 34.0).toDouble();

  // v114: hardcoded carousel/top-nav gap protection.
  // Do not read top padding from Firestore/JSON here. Older published JSON can
  // contain taskBoardTopPadding, phaseStackTopPadding, topNavContentGap, or a
  // generic padding.top value; those values caused the carousel to drop too far
  // below the floating top nav. Keep this gap fixed in Dart.
  final top = compactPhone ? 2.0 : 4.0;

  final bottom = _num(
    _taskBoardPaddingValue(paddingData, const <String>['bottom', 'b']) ??
        data['taskBoardBottomPadding'] ??
        data['phaseStackScreenBottomPadding'] ??
        data['phaseStackBottomPadding'],
    math.max(22, theme.padding + 8),
  ).toDouble().clamp(16.0, 80.0).toDouble();

  return EdgeInsets.fromLTRB(left, top, right, bottom);
}

Map<String, dynamic> _taskBoardPaddingData(Map<String, dynamic> data) {
  final output = <String, dynamic>{};

  void mergePaddingMap(Object? raw) {
    if (raw == null) return;
    if (raw is num || raw is String) {
      output['horizontal'] = raw;
      output['top'] = raw;
      output['bottom'] = raw;
      return;
    }
    final map = _asMap(raw);
    if (map == null || map.isEmpty) return;
    output.addAll(map);
  }

  // Preferred Task Board-specific paths.
  mergePaddingMap(data['taskBoardScreenPadding']);
  mergePaddingMap(data['taskBoardPadding']);
  mergePaddingMap(data['taskBoardInsets']);
  mergePaddingMap(data['phaseStackScreenPadding']);
  mergePaddingMap(data['phaseStackPadding']);

  // Admin may group layout values under layout/padding/layoutPadding.
  final layout = _asMap(data['layout']);
  mergePaddingMap(layout?['taskBoardScreenPadding']);
  mergePaddingMap(layout?['taskBoardPadding']);
  mergePaddingMap(layout?['phaseStackScreenPadding']);

  final layoutPadding = _asMap(data['layoutPadding']);
  mergePaddingMap(layoutPadding?['taskBoard']);
  mergePaddingMap(layoutPadding?['phaseStack']);

  // Generic `padding` is used only when it is a map/number on the board JSON.
  // This keeps the hardcoded default safe while still allowing normal SDUI
  // padding shapes in the admin preview.
  mergePaddingMap(data['padding']);

  return output;
}

Object? _taskBoardPaddingValue(Map<String, dynamic> paddingData, List<String> keys) {
  Object? all;
  for (final entry in paddingData.entries) {
    final key = entry.key.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    if (key == 'all' || key == 'value' || key == 'inset') all ??= entry.value;
    for (final candidate in keys) {
      final token = candidate.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
      if (key == token) return entry.value;
    }
  }
  return all;
}

bool _matchesTaskBoardFilter(ProjectTask task, String filter) {
  final token = _compactFilterToken(filter);
  if (token.isEmpty || token == 'all') return true;
  if (token == 'open') return task.status != TaskStatus.completed;
  if (token == 'overdue' || token == 'late') return task.isOverdue;
  if (token == 'today') return _isSameDate(task.dueDate, DateTime.now());
  if (token == 'critical') return task.priority == TaskPriority.critical;
  if (token == 'high') return task.priority == TaskPriority.high || task.priority == TaskPriority.critical;
  if (token == 'done' || token == 'completed') return task.status == TaskStatus.completed;
  return task.status.value.toLowerCase() == token || task.status.label.toLowerCase().replaceAll(' ', '') == token;
}

class _PinterestBoardLaneData {
  const _PinterestBoardLaneData({required this.status, required this.tasks});
  final TaskStatus status;
  final List<ProjectTask> tasks;
}

class _PinterestBoardHero extends StatelessWidget {
  const _PinterestBoardHero({required this.theme, required this.total, required this.active, required this.review, required this.overdue, required this.done, required this.selectedProjectName});

  final _UiTheme theme;
  final int total;
  final int active;
  final int review;
  final int overdue;
  final int done;
  final String selectedProjectName;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0 : ((done / total) * 100).round();
    return _Surface(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.accent.withOpacity(.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.accent.withOpacity(.16)),
                ),
                child: Icon(Icons.dashboard_customize_rounded, color: theme.accent, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Task board cockpit', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 5),
                    Text('$selectedProjectName • $total live cards • $progress% complete', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.2, height: 1.25)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _InfoTag(label: overdue > 0 ? '$overdue late' : 'On track', icon: overdue > 0 ? Icons.warning_amber_rounded : Icons.verified_rounded, color: overdue > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669), theme: theme),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final itemWidth = width < 360 ? (width - 8) / 2 : (width - 24) / 4;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PinterestMetricTile(theme: theme, label: 'Active', value: '$active', color: theme.accent, width: itemWidth),
                  _PinterestMetricTile(theme: theme, label: 'Review', value: '$review', color: const Color(0xFF7C3AED), width: itemWidth),
                  _PinterestMetricTile(theme: theme, label: 'Late', value: '$overdue', color: const Color(0xFFDC2626), width: itemWidth),
                  _PinterestMetricTile(theme: theme, label: 'Done', value: '$done', color: const Color(0xFF059669), width: itemWidth),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PinterestMetricTile extends StatelessWidget {
  const _PinterestMetricTile({required this.theme, required this.label, required this.value, required this.color, required this.width});
  final _UiTheme theme;
  final String label;
  final String value;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 3),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _PinterestProjectPicker extends StatelessWidget {
  const _PinterestProjectPicker({required this.theme, required this.projects, required this.selectedProjectId, required this.onChanged});

  final _UiTheme theme;
  final List<Project> projects;
  final String selectedProjectId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    var selectedLabel = 'All projects';
    if (selectedProjectId != 'all') {
      selectedLabel = 'Selected project';
      for (final project in projects) {
        if (project.projectId == selectedProjectId) {
          selectedLabel = project.name;
          break;
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PopupMenuButton<String>(
        onSelected: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        itemBuilder: (context) => [
          const PopupMenuItem<String>(value: 'all', child: Text('All projects')),
          ...projects.map((project) => PopupMenuItem<String>(value: project.projectId, child: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis))),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: theme.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 16, offset: const Offset(0, 8))]),
          child: Row(
            children: [
              Container(width: 34, height: 34, decoration: BoxDecoration(color: theme.accent.withOpacity(.10), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.folder_copy_rounded, color: theme.accent, size: 18)),
              const SizedBox(width: 10),
              Expanded(child: Text(selectedLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900))),
              Icon(Icons.keyboard_arrow_down_rounded, color: theme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinterestBoardFilterChips extends StatelessWidget {
  const _PinterestBoardFilterChips({required this.theme, required this.selected, required this.onChanged});

  final _UiTheme theme;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final chips = const <Map<String, String>>[
      {'value': 'all', 'label': 'All'},
      {'value': 'open', 'label': 'Open'},
      {'value': 'overdue', 'label': 'Late'},
      {'value': 'today', 'label': 'Today'},
      {'value': 'critical', 'label': 'Critical'},
      {'value': 'done', 'label': 'Done'},
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final item = chips[index];
            final active = item['value'] == selected;
            return ChoiceChip(
              selected: active,
              onSelected: (_) => onChanged(item['value']!),
              label: Text(item['label']!),
              selectedColor: theme.accent,
              backgroundColor: theme.surface,
              side: BorderSide(color: active ? theme.accent : theme.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              labelStyle: TextStyle(color: active ? Colors.white : theme.textPrimary, fontWeight: FontWeight.w900),
            );
          },
        ),
      ),
    );
  }
}

class _PinterestSelectedTaskCard extends StatelessWidget {
  const _PinterestSelectedTaskCard({super.key, required this.theme, required this.task, required this.projectName, required this.assignees, required this.onClear});

  final _UiTheme theme;
  final ProjectTask task;
  final String projectName;
  final String assignees;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final progress = (_taskProgressForStatus(task.status) * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.accent.withOpacity(.10),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: theme.accent.withOpacity(.22)),
        ),
        child: Row(
          children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: theme.accent, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.visibility_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Watching ${task.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 4),
                Text('$projectName • ${task.status.label} • $progress%${assignees.trim().isEmpty ? '' : ' • $assignees'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 11.5)),
              ]),
            ),
            IconButton(onPressed: onClear, icon: Icon(Icons.close_rounded, color: theme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _PinnedPriorityRail extends StatelessWidget {
  const _PinnedPriorityRail({required this.theme, required this.state, required this.tasks, required this.selectedTaskId, required this.motionEnabled, required this.onTaskTap});

  final _UiTheme theme;
  final WorkspaceState state;
  final List<ProjectTask> tasks;
  final String? selectedTaskId;
  final bool motionEnabled;
  final ValueChanged<ProjectTask> onTaskTap;

  @override
  Widget build(BuildContext context) {
    final pinned = tasks.where((task) => task.isOverdue || task.priority == TaskPriority.critical || task.priority == TaskPriority.high).take(6).toList();
    if (pinned.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 126,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: pinned.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final task = pinned[index];
            return SizedBox(
              width: 212,
              child: _PinterestMiniCard(
                theme: theme,
                task: task,
                projectName: _projectName(state, task.projectId),
                selected: selectedTaskId == task.taskId,
                animationIndex: index,
                motionEnabled: motionEnabled,
                onTap: () => onTaskTap(task),
              ),
            );
          },
        ),
      ),
    );
  }
}


class _DesignerTaskBoardCardData {
  const _DesignerTaskBoardCardData({
    required this.id,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.caption,
    required this.icon,
    required this.paletteMode,
    required this.tasks,
    required this.primaryTask,
  });

  final String id;
  final String eyebrow;
  final String title;
  final String subtitle;
  final String caption;
  final IconData icon;
  final int paletteMode;
  final List<ProjectTask> tasks;
  final ProjectTask? primaryTask;

  int get count => tasks.length;
  int get projectCount => tasks.map((task) => task.projectId).where((id) => id.trim().isNotEmpty).toSet().length;
  bool get hasLiveTasks => tasks.isNotEmpty;

  double get progress {
    if (tasks.isEmpty) return 0;
    final total = tasks.fold<double>(0, (sum, task) => sum + _taskProgressForStatus(task.status));
    return (total / tasks.length).clamp(0.0, 1.0).toDouble();
  }

  TaskPriority get maxPriority {
    if (tasks.any((task) => task.priority == TaskPriority.critical)) return TaskPriority.critical;
    if (tasks.any((task) => task.priority == TaskPriority.high)) return TaskPriority.high;
    if (tasks.any((task) => task.priority == TaskPriority.medium)) return TaskPriority.medium;
    return TaskPriority.low;
  }

  DateTime? get dueDate {
    if (tasks.isEmpty) return null;
    final sorted = tasks.toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return sorted.first.dueDate;
  }

  String get sampleTitle => tasks.isEmpty ? 'No task was in this phase' : tasks.first.title;

  _DesignerTaskThumbnailPalette palette(_UiTheme theme) {
    switch (paletteMode) {
      case 0:
        return _DesignerTaskThumbnailPalette._dark(
          card: const Color(0xFF082033),
          panel: const Color(0xFF061827),
          accent: const Color(0xFFBDA98B),
          theme: theme,
          artMode: 0,
        );
      case 1:
        return _DesignerTaskThumbnailPalette._light(
          card: const Color(0xFFEFE4CF),
          panel: const Color(0xFFE4D6BB),
          accent: const Color(0xFF9A7651),
          theme: theme,
          artMode: 1,
        );
      case 2:
        return _DesignerTaskThumbnailPalette._light(
          card: const Color(0xFFF8F7F3),
          panel: const Color(0xFFEDECE8),
          accent: const Color(0xFF8E6D56),
          theme: theme,
          artMode: 2,
        );
      case 3:
        return _DesignerTaskThumbnailPalette._light(
          card: const Color(0xFFF8F7F3),
          panel: const Color(0xFFEDECE8),
          accent: const Color(0xFFB18472),
          theme: theme,
          artMode: 3,
        );
      case 4:
        return _DesignerTaskThumbnailPalette._dark(
          card: const Color(0xFF8A0D50),
          panel: const Color(0xFF9F145E),
          accent: const Color(0xFFE6C8D5),
          theme: theme,
          artMode: 3,
        );
      case 5:
        return _DesignerTaskThumbnailPalette._light(
          card: const Color(0xFFF8F6F0),
          panel: const Color(0xFFEDE9E0),
          accent: const Color(0xFFB18472),
          theme: theme,
          artMode: 4,
        );
      case 6:
        return _DesignerTaskThumbnailPalette._dark(
          card: const Color(0xFF082033),
          panel: const Color(0xFF071B2C),
          accent: const Color(0xFFAFC6D8),
          theme: theme,
          artMode: 5,
        );
      default:
        return _DesignerTaskThumbnailPalette._light(
          card: const Color(0xFFA8B69F),
          panel: const Color(0xFF9EAD96),
          accent: const Color(0xFF4D6F49),
          theme: theme,
          artMode: 6,
        );
    }
  }
}

List<_DesignerTaskBoardCardData> _designerTaskBoardCardsForTasks(List<ProjectTask> tasks) {
  final sorted = tasks.toList()
    ..sort((a, b) {
      if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
      final priority = b.priority.index.compareTo(a.priority.index);
      if (priority != 0) return priority;
      return a.dueDate.compareTo(b.dueDate);
    });

  List<ProjectTask> whereTasks(bool Function(ProjectTask task) test) => sorted.where(test).toList();

  final backlog = whereTasks((task) => task.status == TaskStatus.backlog);
  final planning = whereTasks((task) => task.status == TaskStatus.backlog || task.status == TaskStatus.todo);
  final todo = whereTasks((task) => task.status == TaskStatus.todo);
  final progress = whereTasks((task) => task.status == TaskStatus.inProgress);
  final review = whereTasks((task) => task.status == TaskStatus.review);
  final creative = whereTasks((task) {
    final haystack = '${task.title} ${task.description} ${task.tags.join(' ')}'.toLowerCase();
    return haystack.contains('design') || haystack.contains('ui') || haystack.contains('creative') || haystack.contains('asset') || task.status == TaskStatus.review;
  });
  final testing = whereTasks((task) => task.status == TaskStatus.testing);
  final completed = whereTasks((task) => task.status == TaskStatus.completed);

  _DesignerTaskBoardCardData phaseCard({
    required String id,
    required String eyebrow,
    required String title,
    required String subtitle,
    required String caption,
    required IconData icon,
    required int paletteMode,
    required List<ProjectTask> phaseTasks,
  }) {
    return _DesignerTaskBoardCardData(
      id: id,
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      caption: caption,
      icon: icon,
      paletteMode: paletteMode,
      tasks: phaseTasks,
      primaryTask: phaseTasks.isEmpty ? null : phaseTasks.first,
    );
  }

  return <_DesignerTaskBoardCardData>[
    phaseCard(
      id: 'backlog',
      eyebrow: 'BACKLOG',
      title: 'Backlog',
      subtitle: 'Task Board',
      caption: 'Capture and organize everything.',
      icon: Icons.grid_view_rounded,
      paletteMode: 0,
      phaseTasks: backlog,
    ),
    phaseCard(
      id: 'planning',
      eyebrow: 'PLANNING',
      title: 'Planning',
      subtitle: 'Sprint Planning',
      caption: 'Plan work and align your team.',
      icon: Icons.calendar_month_rounded,
      paletteMode: 1,
      phaseTasks: planning,
    ),
    phaseCard(
      id: 'todo',
      eyebrow: 'TODO',
      title: 'Todo',
      subtitle: 'Task Queue',
      caption: 'Prioritize and tackle what is next.',
      icon: Icons.check_circle_outline_rounded,
      paletteMode: 2,
      phaseTasks: todo,
    ),
    phaseCard(
      id: 'inProgress',
      eyebrow: 'IN PROGRESS',
      title: 'In Progress',
      subtitle: 'API Integration',
      caption: 'Backend sync, alerts and progress tracking.',
      icon: Icons.code_rounded,
      paletteMode: 3,
      phaseTasks: progress,
    ),
    phaseCard(
      id: 'review',
      eyebrow: 'REVIEW',
      title: 'Review',
      subtitle: 'Mobile UI Audit',
      caption: 'Evaluate experience and improve quality.',
      icon: Icons.phone_iphone_rounded,
      paletteMode: 4,
      phaseTasks: review,
    ),
    phaseCard(
      id: 'creative',
      eyebrow: 'CREATIVE',
      title: 'Creative',
      subtitle: 'Launch Assets',
      caption: 'Design assets that inspire and convert.',
      icon: Icons.draw_rounded,
      paletteMode: 5,
      phaseTasks: creative,
    ),
    phaseCard(
      id: 'testing',
      eyebrow: 'TESTING',
      title: 'Testing',
      subtitle: 'User Testing',
      caption: 'Validate with real users and iterate.',
      icon: Icons.group_outlined,
      paletteMode: 6,
      phaseTasks: testing,
    ),
    phaseCard(
      id: 'completed',
      eyebrow: 'COMPLETED',
      title: 'Completed',
      subtitle: 'Release Done',
      caption: 'Ship confidently. Celebrate progress.',
      icon: Icons.verified_rounded,
      paletteMode: 7,
      phaseTasks: completed,
    ),
  ];
}

class _TaskBoardVerticalStackCarousel extends StatefulWidget {
  const _TaskBoardVerticalStackCarousel({
    required this.theme,
    required this.state,
    required this.data,
    required this.cards,
    required this.selectedPhaseId,
    required this.motionEnabled,
    this.onCarouselScrollHoldChanged,
    required this.onPhaseTap,
  });

  final _UiTheme theme;
  final WorkspaceState state;
  final Map<String, dynamic> data;
  final List<_DesignerTaskBoardCardData> cards;
  final String? selectedPhaseId;
  final bool motionEnabled;
  final ValueChanged<bool>? onCarouselScrollHoldChanged;
  final ValueChanged<_DesignerTaskBoardCardData> onPhaseTap;

  @override
  State<_TaskBoardVerticalStackCarousel> createState() => _TaskBoardVerticalStackCarouselState();
}


class _PhaseStackPageViewScrollBehavior extends MaterialScrollBehavior {
  const _PhaseStackPageViewScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}

class _TaskBoardVerticalStackCarouselState extends State<_TaskBoardVerticalStackCarousel> {
  int _currentIndex = 0;
  double _currentDragX = 0;
  bool _isDragging = false;
  final Set<String> _revealedLowerDetailPhaseIds = <String>{};
  bool _phaseStackDetailsUnlocked = false;
  PageController? _phasePageController;
  double _phasePageViewportFraction = -1;
  int _phaseVirtualPage = 0;
  Offset? _carouselGestureStart;
  int? _carouselPointerId;
  bool _parentScrollHeldForCarousel = false;

  static const Curve _cinematicSpringCurve = Cubic(.34, 1.56, .64, 1);

  double get _dragDamping => _num(widget.data['cinematicDragDamping'] ?? widget.data['stackedDragDamping'] ?? widget.data['dragDamping'], .85).toDouble().clamp(.45, 1.15).toDouble();
  double get _dragThreshold => _num(widget.data['cinematicDragThreshold'] ?? widget.data['stackedDragThreshold'] ?? widget.data['dragThreshold'], 80).toDouble().clamp(42, 140).toDouble();
  double get _velocityThreshold => _num(widget.data['cinematicVelocityThreshold'] ?? widget.data['stackedVelocityThreshold'] ?? widget.data['swipeVelocityThreshold'], 700).toDouble().clamp(260, 1600).toDouble();
  int get _visibleSideDepth => _num(widget.data['cinematicVisibleSideDepth'] ?? widget.data['stackedVisibleSideDepth'] ?? widget.data['visibleSideDepth'], 4).round().clamp(1, 4).toInt();

  // Keep the whole phase deck mounted while swiping. The earlier render-window
  // filter created/destroyed side cards exactly as they entered the stack, so
  // users saw a small hitch when the remaining cards loaded from either side.
  bool get _phaseStackPrewarmEnabled => _flag(
        widget.data['taskBoardCarouselPrewarmStack'] ??
            widget.data['phaseStackPrewarmCards'] ??
            widget.data['phaseStackStableRenderWindow'] ??
            widget.data['carouselKeepHiddenCardsMounted'],
        fallback: true,
      );

  double get _phaseStackPrewarmBuffer => _num(
        widget.data['taskBoardCarouselPrewarmBuffer'] ??
            widget.data['phaseStackPrewarmBuffer'] ??
            widget.data['carouselRenderBuffer'],
        1.35,
      ).toDouble().clamp(.45, 2.5).toDouble();

  @override
  void initState() {
    super.initState();
    _currentIndex = _initialCarouselIndex(widget.cards, widget.selectedPhaseId);
  }

  @override
  void dispose() {
    if (_parentScrollHeldForCarousel) {
      widget.onCarouselScrollHoldChanged?.call(false);
    }
    _phasePageController?.dispose();
    super.dispose();
  }

  int _initialCarouselIndex(List<_DesignerTaskBoardCardData> cards, String? selectedPhaseId) {
    if (cards.isEmpty) return 0;
    if (selectedPhaseId != null) {
      final selectedIndex = cards.indexWhere((card) => card.id == selectedPhaseId);
      if (selectedIndex >= 0) return selectedIndex;
    }
    return 0;
  }

  int _positiveModulo(int value, int count) {
    if (count <= 0) return 0;
    final mod = value % count;
    return mod < 0 ? mod + count : mod;
  }

  double _positiveModuloDouble(double value, int count) {
    if (count <= 0) return 0;
    final mod = value % count;
    return mod < 0 ? mod + count : mod;
  }

  int _nearestVirtualPageFor(int phaseIndex, int count) {
    if (count <= 0) return 0;
    final current = (_phasePageController?.hasClients == true ? _phasePageController?.page?.round() : null) ?? _phaseVirtualPage;
    final base = current - _positiveModulo(current, count);
    final candidates = <int>[base + phaseIndex, base + phaseIndex + count, base + phaseIndex - count];
    candidates.sort((a, b) => (a - current).abs().compareTo((b - current).abs()));
    return candidates.first;
  }

  void _ensurePhasePageController(int count, double viewportFraction) {
    if (count <= 0) return;
    final normalizedFraction = viewportFraction.clamp(.46, .86).toDouble();
    final shouldRecreate = _phasePageController == null || (_phasePageViewportFraction - normalizedFraction).abs() > .001;
    if (!shouldRecreate) return;
    _phasePageController?.dispose();
    _phasePageViewportFraction = normalizedFraction;
    final base = count * 1200;
    _phaseVirtualPage = base + _currentIndex.clamp(0, count - 1).toInt();
    _phasePageController = PageController(initialPage: _phaseVirtualPage, viewportFraction: normalizedFraction);
  }

  void _jumpToIndex(int index, int count) {
    if (count <= 0) return;
    final next = _positiveModulo(index, count);
    final targetVirtualPage = _nearestVirtualPageFor(next, count);
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = next;
      _phaseVirtualPage = targetVirtualPage;
      _currentDragX = 0;
      _isDragging = false;
    });
    final controller = _phasePageController;
    if (controller?.hasClients == true) {
      controller!.animateToPage(
        targetVirtualPage,
        duration: Duration(milliseconds: _num(widget.data['cinematicSnapDurationMs'] ?? widget.data['stackedSnapDurationMs'], 520).round().clamp(240, 780).toInt()),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _revealPhaseDetails(_DesignerTaskBoardCardData card) {
    final globalRevealOnFirstTap = _flag(widget.data['phaseStackGlobalTapUnlockDetails'] ?? widget.data['phaseStackOneTapGlobalUnlock'], fallback: true);
    if (globalRevealOnFirstTap) {
      _phaseStackDetailsUnlocked = true;
    } else {
      _revealedLowerDetailPhaseIds.add(card.id);
    }
  }

  bool get _carouselDirectionalScrollHoldEnabled => _flag(
        widget.data['taskBoardCarouselDirectionalGestureLock'] ??
            widget.data['carouselDirectionalGestureLock'] ??
            widget.data['phaseStackDirectionalGestureLock'],
        fallback: true,
      );

  double get _carouselGestureSlopPx => _num(
        widget.data['taskBoardCarouselGestureLockSlopPx'] ??
            widget.data['carouselGestureLockSlopPx'] ??
            widget.data['phaseStackGestureLockSlopPx'],
        6,
      ).toDouble().clamp(3, 18).toDouble();

  bool get _carouselHapticsEnabled => _flag(
        widget.data['taskBoardCarouselHapticsEnabled'] ??
            widget.data['minimalCarouselHaptics'] ??
            widget.data['carouselHapticsEnabled'],
        fallback: true,
      );

  bool _carouselHapticFrameScheduled = false;

  void _playCarouselSelectionHaptic() {
    if (!_carouselHapticsEnabled || _carouselHapticFrameScheduled) return;

    // Keep haptics minimal and off the current layout/paint frame. On some
    // Android devices the haptic call can steal a few milliseconds exactly when
    // the next stack card becomes visible, which looks like a swipe stutter.
    _carouselHapticFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _carouselHapticFrameScheduled = false;
      if (!mounted) return;
      HapticFeedback.selectionClick();
    });
  }

  void _setParentScrollHoldForCarousel(bool hold) {
    if (_parentScrollHeldForCarousel == hold) return;
    _parentScrollHeldForCarousel = hold;
    widget.onCarouselScrollHoldChanged?.call(hold);
  }

  void _handleCarouselPointerDown(PointerDownEvent event) {
    _carouselGestureStart = event.position;
    _carouselPointerId = event.pointer;
  }

  void _handleCarouselPointerMove(PointerMoveEvent event) {
    if (_carouselPointerId != event.pointer || _parentScrollHeldForCarousel) return;
    final start = _carouselGestureStart;
    if (start == null) return;

    final dx = (event.position.dx - start.dx).abs();
    final dy = (event.position.dy - start.dy).abs();
    if (!_carouselDirectionalScrollHoldEnabled || (dx > _carouselGestureSlopPx && dx > dy)) {
      _setParentScrollHoldForCarousel(true);
    }
  }

  void _releaseCarouselPointer(PointerEvent event) {
    _carouselGestureStart = null;
    _carouselPointerId = null;

    if (!_parentScrollHeldForCarousel) return;
    _setParentScrollHoldForCarousel(false);
  }

  @override
  void didUpdateWidget(covariant _TaskBoardVerticalStackCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cards.isEmpty) {
      _currentIndex = 0;
      _currentDragX = 0;
      _isDragging = false;
      return;
    }
    if (_currentIndex >= widget.cards.length) _currentIndex = widget.cards.length - 1;
    if (oldWidget.selectedPhaseId != widget.selectedPhaseId && widget.selectedPhaseId != null) {
      final index = widget.cards.indexWhere((card) => card.id == widget.selectedPhaseId);
      if (index >= 0 && index != _currentIndex) {
        _currentIndex = index;
        _currentDragX = 0;
        _isDragging = false;
        final controller = _phasePageController;
        if (controller?.hasClients == true) {
          final targetVirtualPage = _nearestVirtualPageFor(index, widget.cards.length);
          _phaseVirtualPage = targetVirtualPage;
          controller!.jumpToPage(targetVirtualPage);
        }
      }
    }
  }

  double _stackOffsetForPage(int index, double page, int count) {
    if (count <= 0) return 0;
    final current = _positiveModuloDouble(page, count);
    var diff = index - current;
    if (diff > count / 2) diff -= count;
    if (diff < -count / 2) diff += count;
    return diff;
  }

  List<_TaskBoardCinematicStackEntry> _phaseStackRenderEntries({
    required List<_DesignerTaskBoardCardData> cards,
    required double page,
  }) {
    final renderDepth = _phaseStackPrewarmEnabled
        ? math.max(cards.length.toDouble(), _visibleSideDepth + _phaseStackPrewarmBuffer)
        : _visibleSideDepth + .78;

    final entries = cards.asMap().entries.map((entry) {
      final offset = _stackOffsetForPage(entry.key, page, cards.length);
      return _TaskBoardCinematicStackEntry(
        index: entry.key,
        card: entry.value,
        offset: offset,
      );
    }).where((entry) => entry.offset.abs() <= renderDepth).toList();

    entries.sort((a, b) {
      final za = 1000 - (a.offset.abs() * 100).round();
      final zb = 1000 - (b.offset.abs() * 100).round();
      final zCompare = za.compareTo(zb);
      if (zCompare != 0) return zCompare;
      return a.index.compareTo(b.index);
    });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final limit = _num(widget.data['stackedCarouselLimit'] ?? widget.data['cinematicStackLimit'] ?? widget.data['verticalStackedCardLimit'], 8).round().clamp(1, 8).toInt();
    final cards = widget.cards.take(limit).toList();
    if (cards.isEmpty) return const SizedBox.shrink();
    if (_currentIndex >= cards.length) _currentIndex = cards.length - 1;
    if (_currentIndex < 0) _currentIndex = 0;

    final mediaSize = MediaQuery.maybeOf(context)?.size ?? Size.zero;
    final responsive = _flag(widget.data['responsivePhaseStackCards'] ?? widget.data['compactPhoneFriendlyCards'] ?? widget.data['compactResponsivePhaseDeck'], fallback: true);
    final compactPhone = responsive && (mediaSize.width <= 390 || mediaSize.height <= 760);
    final requestedHeightRaw = _num(
      compactPhone
          ? (widget.data['compactPhaseStackCarouselHeight'] ?? widget.data['phaseStackCarouselHeight'] ?? widget.data['stackedCarouselHeight'] ?? widget.data['cinematicStackHeight'] ?? widget.data['verticalStackedCarouselHeight'])
          : (widget.data['phaseStackCarouselHeight'] ?? widget.data['stackedCarouselHeight'] ?? widget.data['cinematicStackHeight'] ?? widget.data['verticalStackedCarouselHeight']),
      compactPhone ? 372 : 470,
    ).toDouble();
    // v107: compact Task Board visual density. The second reference keeps the
    // carousel closer to the top nav and uses a shorter deck so the project
    // section begins earlier on small phones.
    final heightScale = _num(widget.data['phaseStackHeightScale'] ?? widget.data['carouselHeightScale'], .74).toDouble().clamp(.58, 1.0).toDouble();
    final requestedHeight = requestedHeightRaw * heightScale;
    final viewportCap = mediaSize.height > 0 ? mediaSize.height * (compactPhone ? .37 : .43) : (compactPhone ? 304.0 : 424.0);
    final minHeight = compactPhone ? 238.0 : 286.0;
    final maxHeight = compactPhone ? math.max(238.0, math.min(304.0, viewportCap)) : math.max(314.0, math.min(424.0, viewportCap));
    final height = requestedHeight.clamp(minHeight, maxHeight).toDouble();

    final stackViewportFraction = _num(
      compactPhone
          ? (widget.data['compactPhaseStackPageViewportFraction'] ?? widget.data['phaseStackPageViewportFraction'] ?? widget.data['stackedPageViewportFraction'])
          : (widget.data['phaseStackPageViewportFraction'] ?? widget.data['stackedPageViewportFraction']),
      compactPhone ? .56 : .54,
    ).toDouble().clamp(.44, .78).toDouble();
    _ensurePhasePageController(cards.length, stackViewportFraction);
    final controller = _phasePageController;
    final activeCard = cards[_currentIndex];

    final showLowerContent = _flag(widget.data['phaseStackLowerContentEnabled'] ?? widget.data['showPhaseStackLowerContent'] ?? widget.data['responsiveLowerPhaseContent'], fallback: true);
    final completedDetailsDefault = _flag(widget.data['phaseStackCompletedDetailsDefault'] ?? widget.data['completedPhaseDetailsDefault'], fallback: true);
    final revealOnTap = _flag(widget.data['phaseStackTapToRevealDetails'] ?? widget.data['tapCardShowsPhaseDetails'], fallback: true);
    final globalRevealOnFirstTap = _flag(widget.data['phaseStackGlobalTapUnlockDetails'] ?? widget.data['phaseStackOneTapGlobalUnlock'], fallback: true);
    final completedSelected = activeCard.id.toLowerCase() == 'completed' || activeCard.title.toLowerCase() == 'completed';
    final lowerDetailsVisible = (completedDetailsDefault && completedSelected) ||
        (globalRevealOnFirstTap && _phaseStackDetailsUnlocked) ||
        _revealedLowerDetailPhaseIds.contains(activeCard.id);

    final outerHorizontalPadding = _num(
      widget.data['phaseStackOuterHorizontalPadding'] ??
          widget.data['taskBoardCarouselHorizontalPadding'] ??
          widget.data['taskBoardCarouselSidePadding'],
      0,
    ).toDouble().clamp(0.0, compactPhone ? 16.0 : 24.0).toDouble();

    // v114: protect the carousel from JSON top-offset overrides.
    // The top gap is controlled only by _taskBoardScreenPadding above.
    final outerTopPadding = 0.0;

    final outerBottomPadding = _num(
      widget.data['phaseStackOuterBottomPadding'] ?? widget.data['taskBoardCarouselBottomPadding'],
      14,
    ).toDouble().clamp(8.0, 34.0).toDouble();

    final lowerContentGap = _num(
      widget.data['phaseStackLowerContentTopGap'] ??
          widget.data['taskBoardLowerContentTopGap'] ??
          widget.data['phaseStackLowerContentGap'],
      18,
    ).toDouble().clamp(8.0, 34.0).toDouble();

    final lowerContentHorizontalPadding = _num(
      widget.data['phaseStackLowerContentHorizontalPadding'] ??
          widget.data['taskBoardLowerContentHorizontalPadding'] ??
          widget.data['phaseStackDetailsHorizontalPadding'],
      0,
    ).toDouble().clamp(0.0, compactPhone ? 14.0 : 24.0).toDouble();

    final lowerContentBottomPadding = _num(
      widget.data['phaseStackLowerContentBottomPadding'] ??
          widget.data['taskBoardLowerContentBottomPadding'] ??
          widget.data['phaseStackDetailsBottomPadding'],
      0,
    ).toDouble().clamp(0.0, 34.0).toDouble();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        outerHorizontalPadding,
        outerTopPadding,
        outerHorizontalPadding,
        outerBottomPadding,
      ),
      child: RepaintBoundary(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: controller == null
                  ? const SizedBox.shrink()
                  : Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: controller,
                            builder: (context, _) {
                              final page = controller.hasClients && controller.position.haveDimensions ? (controller.page ?? _phaseVirtualPage.toDouble()) : _phaseVirtualPage.toDouble();
                              final renderEntries = _phaseStackRenderEntries(
                                cards: cards,
                                page: page,
                              );
                              return Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: renderEntries.map((entry) {
                                  return Positioned.fill(
                                    key: ValueKey<String>('phase-stack-position-${entry.card.id}'),
                                    child: _TaskBoardStackedCarouselCard(
                                      key: ValueKey<String>('phase-stack-card-${entry.card.id}'),
                                      theme: widget.theme,
                                      data: widget.data,
                                      card: entry.card,
                                      stackOffset: entry.offset,
                                      currentDragX: 0,
                                      isDragging: false,
                                      selected: _currentIndex == entry.index,
                                      motionEnabled: widget.motionEnabled,
                                      onTap: () {},
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),
                        Positioned.fill(
                          child: ScrollConfiguration(
                            // v230: desktop/admin preview fix. Flutter web/desktop does not
                            // allow mouse dragging for PageView by default, so the carousel
                            // looked frozen in the laptop-size preview. This keeps APK touch
                            // swipe unchanged and adds mouse/stylus drag support for preview.
                            behavior: const _PhaseStackPageViewScrollBehavior(),
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: _handleCarouselPointerDown,
                              onPointerMove: _handleCarouselPointerMove,
                              onPointerUp: _releaseCarouselPointer,
                              onPointerCancel: _releaseCarouselPointer,
                              child: PageView.builder(
                                controller: controller,
                                clipBehavior: Clip.none,
                                allowImplicitScrolling: true,
                                physics: widget.motionEnabled ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()) : const NeverScrollableScrollPhysics(),
                                onPageChanged: (page) {
                                  final nextIndex = _positiveModulo(page, cards.length);
                                  if (nextIndex != _currentIndex) {
                                    _playCarouselSelectionHaptic();
                                  }
                                  setState(() {
                                    _phaseVirtualPage = page;
                                    _currentIndex = nextIndex;
                                    _currentDragX = 0;
                                    _isDragging = false;
                                  });
                                },
                              itemBuilder: (context, virtualIndex) {
                                final phaseIndex = _positiveModulo(virtualIndex, cards.length);
                                final card = cards[phaseIndex];
                                return GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () {
                                    final isCenter = phaseIndex == _currentIndex;
                                    // v229: drag-only carousel behavior.
                                    // Side-card taps must not auto-scroll/snap the PageView.
                                    // Users change cards only by swiping/dragging the carousel.
                                    final sideTapFocusEnabled = _flag(
                                      widget.data['phaseStackSideTapFocusEnabled'] ??
                                          widget.data['phaseStackTapSideCardToFocus'] ??
                                          widget.data['tapSideCardToFocus'],
                                      fallback: false,
                                    );
                                    if (!isCenter) {
                                      if (sideTapFocusEnabled) {
                                        _jumpToIndex(phaseIndex, cards.length);
                                      }
                                      return;
                                    }
                                    if (revealOnTap) {
                                      HapticFeedback.selectionClick();
                                      setState(() => _revealPhaseDetails(card));
                                    }
                                    final openSheetOnCardTap = _flag(widget.data['phaseStackCardTapOpensSheet'] ?? widget.data['tapPhaseCardOpensSheet'], fallback: true);
                                    if (openSheetOnCardTap) widget.onPhaseTap(card);
                                  },
                                    child: const SizedBox.expand(),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            _PhaseCarouselDots(theme: widget.theme, count: cards.length, currentIndex: _currentIndex),
            if (showLowerContent) ...[
              SizedBox(height: lowerContentGap),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  lowerContentHorizontalPadding,
                  0,
                  lowerContentHorizontalPadding,
                  lowerContentBottomPadding,
                ),
                child: _PhaseCarouselLowerContent(
                  theme: widget.theme,
                  state: widget.state,
                  data: widget.data,
                  card: activeCard,
                  detailsVisible: lowerDetailsVisible,
                  onOpenPhase: () {
                    setState(() {
                      if (globalRevealOnFirstTap) {
                        _phaseStackDetailsUnlocked = true;
                      } else {
                        _revealedLowerDetailPhaseIds.add(activeCard.id);
                      }
                    });
                    widget.onPhaseTap(activeCard);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskBoardCinematicStackEntry {
  const _TaskBoardCinematicStackEntry({required this.index, required this.card, required this.offset});
  final int index;
  final _DesignerTaskBoardCardData card;
  final double offset;
}

class _PhaseCarouselDots extends StatelessWidget {
  const _PhaseCarouselDots({required this.theme, required this.count, required this.currentIndex});

  final _UiTheme theme;
  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: i == currentIndex ? 18 : 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: i == currentIndex ? theme.textPrimary.withOpacity(.86) : theme.textSecondary.withOpacity(.22),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _PhaseCarouselLowerContent extends StatelessWidget {
  const _PhaseCarouselLowerContent({required this.theme, required this.state, required this.data, required this.card, required this.detailsVisible, required this.onOpenPhase});

  final _UiTheme theme;
  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _DesignerTaskBoardCardData card;
  final bool detailsVisible;
  final VoidCallback onOpenPhase;

  @override
  Widget build(BuildContext context) {
    final palette = card.palette(theme);
    final buckets = _phaseProjectBuckets(state, card.tasks).take(3).toList();
    final compact = MediaQuery.maybeOf(context)?.size.width != null && (MediaQuery.maybeOf(context)?.size.width ?? 400) <= 390;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Column(
        key: ValueKey(card.id),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Projects in this phase', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontFamily: 'serif', fontWeight: FontWeight.w600, fontSize: compact ? 22 : 24, letterSpacing: -.35)),
                    const SizedBox(height: 3),
                    Text(detailsVisible ? '${card.title} • ${card.count} task${card.count == 1 ? '' : 's'}' : (data['phaseStackPlaceholderText']?.toString() ?? 'Please tap on any card to get the details.'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onOpenPhase,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('View all', style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 12.5)),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, color: theme.textSecondary, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!detailsVisible) ...[
            _PhaseCarouselHelperPrompt(theme: theme, palette: palette, message: data['phaseStackPlaceholderText']?.toString() ?? 'Please tap on any card to get the details.'),
            const SizedBox(height: 10),
            _PhaseCarouselInlineEmpty(theme: theme, palette: palette, phaseTitle: card.title, onTap: onOpenPhase),
          ] else if (buckets.isEmpty)
            _PhaseCarouselInlineEmpty(theme: theme, palette: palette, phaseTitle: card.title, onTap: onOpenPhase)
          else
            ...buckets.map((bucket) => _PhaseProjectPreviewRow(theme: theme, palette: palette, bucket: bucket, onTap: onOpenPhase)),
          const SizedBox(height: 12),
          Text('Quick access', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary.withOpacity(.84), fontFamily: 'serif', fontWeight: FontWeight.w600, fontSize: 18, letterSpacing: -.2)),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoPerRow = constraints.maxWidth < 430;
              final buttonWidth = twoPerRow ? (constraints.maxWidth - 8) / 2 : (constraints.maxWidth - 24) / 4;
              final buttons = <Widget>[
                _PhaseQuickActionButton(theme: theme, label: 'New Project', icon: Icons.add_rounded, accent: palette.accent, width: buttonWidth, onTap: onOpenPhase),
                _PhaseQuickActionButton(theme: theme, label: 'All Projects', icon: Icons.folder_rounded, accent: palette.accent, width: buttonWidth, onTap: onOpenPhase),
                _PhaseQuickActionButton(theme: theme, label: 'Team', icon: Icons.groups_rounded, accent: palette.accent, width: buttonWidth, onTap: onOpenPhase),
                _PhaseQuickActionButton(theme: theme, label: 'Reports', icon: Icons.bar_chart_rounded, accent: palette.accent, width: buttonWidth, onTap: onOpenPhase),
              ];
              if (!twoPerRow) {
                return Row(children: [buttons[0], const SizedBox(width: 8), buttons[1], const SizedBox(width: 8), buttons[2], const SizedBox(width: 8), buttons[3]]);
              }
              return Wrap(spacing: 8, runSpacing: 8, children: buttons);
            },
          ),
        ],
      ),
    );
  }
}

class _PhaseCarouselHelperPrompt extends StatelessWidget {
  const _PhaseCarouselHelperPrompt({required this.theme, required this.palette, required this.message});

  final _UiTheme theme;
  final _DesignerTaskThumbnailPalette palette;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: palette.accent.withOpacity(.10),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: palette.accent.withOpacity(.16)),
          ),
          child: Icon(Icons.auto_awesome_rounded, color: palette.accent.withOpacity(.84), size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 13.2, height: 1.25),
          ),
        ),
      ],
    );
  }
}

class _PhaseCarouselInlineEmpty extends StatelessWidget {
  const _PhaseCarouselInlineEmpty({required this.theme, required this.palette, required this.phaseTitle, required this.onTap});

  final _UiTheme theme;
  final _DesignerTaskThumbnailPalette palette;
  final String phaseTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          decoration: BoxDecoration(
            color: theme.surface.withOpacity(.76),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.border.withOpacity(.76)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: palette.accent.withOpacity(.12), borderRadius: BorderRadius.circular(17)),
                child: Icon(Icons.inbox_rounded, color: palette.accent, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No task was in this phase.', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14.5)),
                    const SizedBox(height: 4),
                    Text('Open $phaseTitle to view project buckets when tasks arrive.', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 11.8, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: theme.textSecondary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhaseProjectPreviewRow extends StatelessWidget {
  const _PhaseProjectPreviewRow({required this.theme, required this.palette, required this.bucket, required this.onTap});

  final _UiTheme theme;
  final _DesignerTaskThumbnailPalette palette;
  final _PhaseProjectBucket bucket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = bucket.tasks.length;
    final progress = total <= 0 ? 0.0 : (bucket.completed / total).clamp(0.0, 1.0).toDouble();
    final statusLabel = bucket.tasks.isEmpty ? 'No tasks' : _phasePreviewStatus(bucket.tasks.first.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.surface.withOpacity(.78),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.border.withOpacity(.72)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 18, offset: const Offset(0, 10))],
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(color: palette.accent.withOpacity(.13), borderRadius: BorderRadius.circular(18)),
                  child: Icon(Icons.layers_rounded, color: palette.accent, size: 25),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bucket.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontFamily: 'serif', fontWeight: FontWeight.w600, fontSize: 18, height: 1.04, letterSpacing: -.25)),
                      const SizedBox(height: 5),
                      Text('$total task${total == 1 ? '' : 's'}  •  $statusLabel', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.accent, fontWeight: FontWeight.w800, fontSize: 12.2)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _PhaseMiniProgressRing(value: progress, color: palette.accent, label: '${(progress * 100).round()}%'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhaseMiniProgressRing extends StatelessWidget {
  const _PhaseMiniProgressRing({required this.value, required this.color, required this.label});

  final double value;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(value: value.clamp(0.0, 1.0).toDouble(), strokeWidth: 2.2, backgroundColor: color.withOpacity(.12), valueColor: AlwaysStoppedAnimation<Color>(color.withOpacity(.78))),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(.86), fontWeight: FontWeight.w900, fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _PhaseQuickActionButton extends StatelessWidget {
  const _PhaseQuickActionButton({required this.theme, required this.label, required this.icon, required this.accent, required this.width, required this.onTap});

  final _UiTheme theme;
  final String label;
  final IconData icon;
  final Color accent;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: theme.surface.withOpacity(.70),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.border.withOpacity(.68)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: accent, size: 18),
                const SizedBox(width: 8),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary.withOpacity(.86), fontWeight: FontWeight.w900, fontSize: 12.2))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _phasePreviewStatus(TaskStatus status) {
  switch (status) {
    case TaskStatus.backlog:
      return 'Backlog';
    case TaskStatus.todo:
      return 'To Do';
    case TaskStatus.inProgress:
      return 'In Progress';
    case TaskStatus.review:
      return 'Review';
    case TaskStatus.testing:
      return 'Testing';
    case TaskStatus.completed:
      return 'Completed';
  }
}

class _TaskBoardStackedCarouselCard extends StatelessWidget {
  const _TaskBoardStackedCarouselCard({
    super.key,
    required this.theme,
    required this.data,
    required this.card,
    required this.stackOffset,
    required this.currentDragX,
    required this.isDragging,
    required this.selected,
    required this.motionEnabled,
    required this.onTap,
  });

  final _UiTheme theme;
  final Map<String, dynamic> data;
  final _DesignerTaskBoardCardData card;
  final double stackOffset;
  final double currentDragX;
  final bool isDragging;
  final bool selected;
  final bool motionEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final absOffset = stackOffset.abs().toDouble();
    final mediaSize = MediaQuery.maybeOf(context)?.size ?? Size.zero;

    final responsive = _flag(
      data['responsivePhaseStackCards'] ??
          data['compactPhoneFriendlyCards'] ??
          data['compactResponsivePhaseDeck'],
      fallback: true,
    );

    final compactViewport =
        responsive && (mediaSize.width <= 390 || mediaSize.height <= 760);

    // v94 carousel fix:
    // PageController.page is the only animation source. This widget renders the
    // current calculated frame directly, so side-stack cards do not get a second
    // tween while the user swipes.
    final strictNoVerticalMotion = _flag(
      data['phaseStackStrictNoVerticalMotion'] ??
          data['pageViewNoVerticalMotion'] ??
          data['carouselNoVerticalMotion'] ??
          data['taskBoardCarouselNoVerticalMotion'] ??
          data['carouselTranslateYLocked'],
      fallback: false,
    );

    final spacing = _num(
      compactViewport
          ? (data['compactStackedCardSpacingX'] ??
              data['compactCinematicCardSpacingX'] ??
              data['cinematicCardSpacingX'] ??
              data['stackedCardSpacingX'] ??
              data['cardXOffset'])
          : (data['cinematicCardSpacingX'] ??
              data['stackedCardSpacingX'] ??
              data['cardXOffset']),
      46,
    ).toDouble().clamp(18.0, 96.0).toDouble();

    final scaleStep = _num(
      data['cinematicCardScaleStep'] ??
          data['stackedCardScaleStep'] ??
          data['cardScaleStep'],
      .048,
    ).toDouble().clamp(.018, .09).toDouble();

    final minScale = _num(
      data['cinematicCardMinScale'] ??
          data['stackedCardMinScale'] ??
          data['cardMinScale'],
      .85,
    ).toDouble().clamp(.76, .94).toDouble();

    final perspective = _num(
      data['cinematicPerspective'] ?? data['stackedPerspective'],
      .0012,
    ).toDouble().clamp(.0003, .0030).toDouble();

    final ySpacing = strictNoVerticalMotion
        ? 0.0
        : _num(
            data['stackedCardSpacingY'] ??
                data['deckCardSpacingY'] ??
                data['cardYOffset'],
            10,
          ).toDouble().clamp(0, 36).toDouble();

    final rotateZStep = strictNoVerticalMotion
        ? 0.0
        : _num(
            data['stackedCardRotateZ'] ?? data['deckCardRotateZ'],
            .025,
          ).toDouble().clamp(-.12, .12).toDouble();

    final maxOverlay = _num(
      data['cinematicMaxDepthOverlay'] ??
          data['stackedCardMaxOverlay'] ??
          data['cardMaxOverlay'],
      .36,
    ).toDouble().clamp(.08, .72).toDouble();

    final hideAfter = _num(
      data['cinematicHideAfterOffset'] ?? data['stackedHideAfterOffset'],
      2,
    ).round().clamp(1, 4).toInt();

    final fadeDistance = _num(
      data['phaseStackCardFadeDistance'] ??
          data['taskBoardCarouselCardFadeDistance'] ??
          data['carouselCardFadeDistance'],
      1.15,
    ).toDouble().clamp(.35, 2.25).toDouble();

    final keepHiddenCardsMounted = _flag(
      data['taskBoardCarouselPrewarmStack'] ??
          data['phaseStackPrewarmCards'] ??
          data['phaseStackStableRenderWindow'] ??
          data['carouselKeepHiddenCardsMounted'],
      fallback: true,
    );

    final rotateDivisor = _num(
      data['cinematicRotateYDivisor'] ??
          data['stackedRotateYDivisor'] ??
          data['rotateYDivisor'],
      10,
    ).toDouble().clamp(6, 28).toDouble();

    var scale = (1 - (absOffset * scaleStep)).clamp(minScale, 1.0).toDouble();
    var xOffset = stackOffset * spacing;
    var yOffset = absOffset * ySpacing;
    var rotateZ = stackOffset * rotateZStep;
    var rotateY = 0.0;
    var depthOverlay = (absOffset * .20).clamp(0.0, maxOverlay).toDouble();
    // Smooth deterministic fade for side cards. This replaces the old hard
    // opacity cutoff that made a newly visible remaining card appear in one
    // frame when swiping left/right.
    var opacity = absOffset <= hideAfter
        ? 1.0
        : (1.0 - ((absOffset - hideAfter) / fadeDistance)).clamp(0.0, 1.0).toDouble();
    var shadowOpacity = (.50 - (absOffset * .10)).clamp(.14, .50).toDouble();
    var shadowBlur = (40 - (absOffset * 5)).clamp(18, 40).toDouble();

    final isCenterCard = absOffset < .001;

    if (isCenterCard) {
      xOffset += currentDragX;
      yOffset = 0;
      rotateY = currentDragX == 0
          ? 0
          : (currentDragX / rotateDivisor) * math.pi / 180;
      rotateZ = currentDragX == 0
          ? 0
          : (currentDragX / 4200).clamp(-.08, .08).toDouble();
      depthOverlay = 0;
      opacity = 1;
      shadowOpacity = .50;
      shadowBlur = 40;
    }

    if (selected || isCenterCard) {
      scale *= 1.018;
    }

    if (!motionEnabled) {
      rotateY = 0;
      rotateZ = 0;
      shadowOpacity = (.34 - (absOffset * .045)).clamp(.12, .34).toDouble();
      shadowBlur = (30 - (absOffset * 2)).clamp(18, 30).toDouble();
    }

    final transform = Matrix4.identity()
      ..setEntry(3, 2, perspective)
      ..translate(xOffset, yOffset, 0.0)
      ..scale(scale, scale)
      ..rotateZ(rotateZ)
      ..rotateY(rotateY);

    return LayoutBuilder(
      builder: (context, constraints) {
        final desiredWidth = _num(
          compactViewport
              ? (data['compactPhaseStackCardWidth'] ??
                  data['phaseStackCardWidth'] ??
                  data['referenceCardWidth'] ??
                  data['stackedCardWidth'])
              : (data['phaseStackCardWidth'] ??
                  data['referenceCardWidth'] ??
                  data['stackedCardWidth']),
          compactViewport ? 218 : 238,
        ).toDouble();

        final minWidth = compactViewport ? 166.0 : 196.0;
        final maxWidth = compactViewport ? 236.0 : 270.0;

        final widthFraction = _num(
          compactViewport
              ? data['compactPhaseStackWidthFraction']
              : data['phaseStackWidthFraction'],
          compactViewport ? .68 : .70,
        ).toDouble().clamp(.54, .82).toDouble();

        final maxAllowedWidth = constraints.maxWidth.isFinite
            ? math.max(
                minWidth,
                math.min(maxWidth, constraints.maxWidth * widthFraction),
              )
            : maxWidth;

        final cardWidth = desiredWidth
            .clamp(minWidth, maxAllowedWidth)
            .toDouble();

        final desiredHeightRaw = _num(
          compactViewport
              ? (data['compactPhaseStackCardHeight'] ??
                  data['phaseStackCardHeight'] ??
                  data['referenceCardHeight'] ??
                  data['stackedCardHeight'])
              : (data['phaseStackCardHeight'] ??
                  data['referenceCardHeight'] ??
                  data['stackedCardHeight']),
          cardWidth * 1.24,
        ).toDouble();

        final targetAspect = _num(
          data['phaseStackCardHeightRatio'],
          1.24,
        ).toDouble().clamp(1.04, 1.60).toDouble();

        final desiredHeight = math.min(desiredHeightRaw, cardWidth * targetAspect);

        final minHeight = compactViewport ? 204.0 : 250.0;
        final maxHeight = compactViewport ? 292.0 : 344.0;

        final maxAllowedHeight = constraints.maxHeight.isFinite
            ? math.max(
                minHeight,
                math.min(maxHeight, constraints.maxHeight - 8),
              )
            : maxHeight;

        final cardHeight = desiredHeight
            .clamp(minHeight, maxAllowedHeight)
            .toDouble();

        if (opacity <= 0.0 && !keepHiddenCardsMounted) {
          return const SizedBox.shrink();
        }

        Widget cardWidget = RepaintBoundary(
          child: Transform(
            transform: transform,
            alignment: Alignment.center,
            transformHitTests: true,
            child: Container(
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Container(
                width: cardWidth,
                height: cardHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(shadowOpacity),
                      blurRadius: shadowBlur,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: _TaskBoardStackedCardBody(
                  theme: theme,
                  card: card,
                  selected: selected || isCenterCard,
                  depthOverlay: depthOverlay,
                  onTap: onTap,
                ),
              ),
            ),
          ),
        );

        if (opacity < 1.0) {
          cardWidget = Opacity(
            opacity: opacity,
            alwaysIncludeSemantics: false,
            child: cardWidget,
          );
        }

        return IgnorePointer(
          ignoring: opacity <= 0.01,
          child: cardWidget,
        );
      },
    );
  }
}

class _TaskBoardStackedCardBody extends StatelessWidget {
  const _TaskBoardStackedCardBody({
    required this.theme,
    required this.card,
    required this.selected,
    required this.depthOverlay,
    required this.onTap,
  });

  final _UiTheme theme;
  final _DesignerTaskBoardCardData card;
  final bool selected;
  final double depthOverlay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = card.palette(theme);
    final cardRadius = selected ? 36.0 : 34.0;
    final accent = palette.accent;
    final muted = palette.onCard.withOpacity(palette.dark ? .82 : .68);

    return Hero(
      tag: 'task-phase-card-${card.id}',
      transitionOnUserGestures: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(cardRadius),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(cardRadius),
              border: Border.all(
                color: selected ? accent.withOpacity(.62) : palette.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  right: -20,
                  bottom: -20,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent.withOpacity(0.15), width: 30),
                    ),
                  ),
                ),
                Positioned.fill(child: Container(color: Colors.black.withOpacity(depthOverlay))),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compactHeight = constraints.maxHeight < 340;
                    final compactWidth = constraints.maxWidth < 236;
                    final compact = compactHeight || compactWidth;
                    final padding = compact ? 18.0 : 22.0;
                    final iconSize = compact ? 44.0 : 48.0;
                    final topGap = compact ? 24.0 : 32.0;
                    final titleSize = compact ? 27.0 : 31.5;
                    final subtitleSize = compact ? 15.5 : 18.0;
                    final eyebrowSize = compact ? 8.4 : 9.0;
                    final captionVisible = constraints.maxHeight >= 294;

                    return Padding(
                      padding: EdgeInsets.all(padding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: iconSize,
                                height: iconSize,
                                decoration: BoxDecoration(
                                  color: palette.dark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.045),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: palette.dark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05)),
                                ),
                                child: Icon(card.icon, color: accent, size: compact ? 20 : 22),
                              ),
                              const Spacer(),
                              Icon(Icons.more_horiz_rounded, color: accent.withOpacity(0.5)),
                            ],
                          ),
                          SizedBox(height: topGap),
                          Text(
                            card.eyebrow,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w900,
                              fontSize: eyebrowSize,
                              letterSpacing: compact ? 3.3 : 3.8,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            card.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.onCard,
                              fontFamily: 'serif',
                              fontWeight: FontWeight.bold,
                              fontSize: titleSize,
                              height: 1.04,
                              letterSpacing: -.55,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            card.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.onCard.withOpacity(.90),
                              fontFamily: 'serif',
                              fontWeight: FontWeight.w500,
                              fontSize: subtitleSize,
                              height: 1.0,
                            ),
                          ),
                          SizedBox(height: compact ? 18 : 26),
                          Container(width: 48, height: 1.35, color: accent.withOpacity(.62)),
                          if (captionVisible) ...[
                            SizedBox(height: compact ? 12 : 14),
                            Text(
                              card.caption,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: muted,
                                fontWeight: FontWeight.w700,
                                fontSize: compact ? 12.2 : 13.0,
                                height: 1.32,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhaseCardDotGrid extends StatelessWidget {
  const _PhaseCardDotGrid({required this.color, required this.compact});

  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dot = compact ? 2.2 : 2.6;
    final gap = compact ? 9.0 : 11.0;
    return SizedBox(
      width: gap * 4,
      height: gap * 4,
      child: Wrap(
        spacing: gap - dot,
        runSpacing: gap - dot,
        children: [
          for (var i = 0; i < 16; i++) Container(width: dot, height: dot, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ],
      ),
    );
  }
}

class _PhaseProjectBucket {
  const _PhaseProjectBucket({required this.projectId, required this.project, required this.tasks});

  final String projectId;
  final Project? project;
  final List<ProjectTask> tasks;

  String get name {
    final projectName = project?.name.trim() ?? '';
    if (projectName.isNotEmpty) return projectName;
    return projectId.trim().isEmpty ? 'Workspace project' : 'Project ${projectId.trim()}';
  }

  int get completed => tasks.where((task) => task.status == TaskStatus.completed).length;
  DateTime? get nextDue {
    if (tasks.isEmpty) return null;
    final sorted = tasks.toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return sorted.first.dueDate;
  }
}

List<_PhaseProjectBucket> _phaseProjectBuckets(WorkspaceState state, List<ProjectTask> tasks) {
  final grouped = <String, List<ProjectTask>>{};
  for (final task in tasks) {
    final id = task.projectId.trim().isEmpty ? 'unassigned_project' : task.projectId.trim();
    grouped.putIfAbsent(id, () => <ProjectTask>[]).add(task);
  }
  final buckets = grouped.entries.map((entry) {
    Project? project;
    for (final item in state.projects) {
      if (item.projectId == entry.key) {
        project = item;
        break;
      }
    }
    final sortedTasks = entry.value.toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return _PhaseProjectBucket(projectId: entry.key, project: project, tasks: sortedTasks);
  }).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return buckets;
}

class _PhaseProjectTaskSheet extends StatefulWidget {
  const _PhaseProjectTaskSheet({required this.theme, required this.state, required this.card, required this.onTaskTap});

  final _UiTheme theme;
  final WorkspaceState state;
  final _DesignerTaskBoardCardData card;
  final Future<void> Function(ProjectTask task) onTaskTap;

  @override
  State<_PhaseProjectTaskSheet> createState() => _PhaseProjectTaskSheetState();
}

class _PhaseProjectTaskSheetState extends State<_PhaseProjectTaskSheet> {
  String? _selectedProjectId;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final card = widget.card;
    final palette = card.palette(theme);
    final buckets = _phaseProjectBuckets(widget.state, card.tasks);
    _PhaseProjectBucket? selectedBucket;
    for (final bucket in buckets) {
      if (bucket.projectId == _selectedProjectId) {
        selectedBucket = bucket;
        break;
      }
    }
    final empty = card.tasks.isEmpty;
    final initialSize = empty ? .42 : .72;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: initialSize,
      minChildSize: .34,
      maxChildSize: .94,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            border: Border.all(color: theme.border.withOpacity(.82)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.24), blurRadius: 30, offset: const Offset(0, -10))],
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
            children: [
              Center(
                child: Container(width: 44, height: 5, decoration: BoxDecoration(color: theme.border, borderRadius: BorderRadius.circular(999))),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Hero(
                    tag: 'task-phase-card-${card.id}',
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: palette.card,
                          borderRadius: BorderRadius.circular(21),
                          border: Border.all(color: palette.focusBorder.withOpacity(.72)),
                        ),
                        child: Icon(card.icon, color: palette.icon, size: 25),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -.35)),
                        const SizedBox(height: 4),
                        Text(
                          empty ? 'No task was in this phase.' : '${buckets.length} project${buckets.length == 1 ? '' : 's'} • ${card.count} task${card.count == 1 ? '' : 's'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (empty)
                _PhaseEmptyState(theme: theme, palette: palette, phaseTitle: card.title)
              else if (selectedBucket == null) ...[
                Text('Projects in this phase', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15.5)),
                const SizedBox(height: 10),
                ...buckets.map((bucket) => _PhaseProjectRow(
                      theme: theme,
                      palette: palette,
                      bucket: bucket,
                      onTap: () => setState(() => _selectedProjectId = bucket.projectId),
                    )),
              ] else ...[
                Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setState(() => _selectedProjectId = null),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                        decoration: BoxDecoration(color: theme.background, borderRadius: BorderRadius.circular(999), border: Border.all(color: theme.border)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_rounded, size: 16, color: theme.textPrimary),
                            const SizedBox(width: 6),
                            Text('Projects', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(selectedBucket.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16))),
                  ],
                ),
                const SizedBox(height: 12),
                ...selectedBucket.tasks.map((task) => _PhaseTaskRow(
                      theme: theme,
                      palette: palette,
                      task: task,
                      onTap: () => widget.onTaskTap(task),
                    )),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PhaseEmptyState extends StatelessWidget {
  const _PhaseEmptyState({required this.theme, required this.palette, required this.phaseTitle});

  final _UiTheme theme;
  final _DesignerTaskThumbnailPalette palette;
  final String phaseTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(color: palette.accent.withOpacity(.10), borderRadius: BorderRadius.circular(24)),
            child: Icon(Icons.inbox_rounded, color: palette.accent, size: 28),
          ),
          const SizedBox(height: 14),
          Text('No task was in this phase.', textAlign: TextAlign.center, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 6),
          Text('When a project gets a $phaseTitle task, it will appear here before the task list opens.', textAlign: TextAlign.center, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.35)),
        ],
      ),
    );
  }
}

class _PhaseProjectRow extends StatelessWidget {
  const _PhaseProjectRow({required this.theme, required this.palette, required this.bucket, required this.onTap});

  final _UiTheme theme;
  final _DesignerTaskThumbnailPalette palette;
  final _PhaseProjectBucket bucket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final due = bucket.nextDue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.background,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: palette.accent.withOpacity(.11), borderRadius: BorderRadius.circular(17)),
                  child: Icon(Icons.folder_rounded, color: palette.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bucket.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14.5)),
                      const SizedBox(height: 5),
                      Text(
                        '${bucket.tasks.length} task${bucket.tasks.length == 1 ? '' : 's'}${due == null ? '' : ' • Next ${DateText.compact(due)}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.chevron_right_rounded, color: theme.textSecondary, size: 25),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhaseTaskRow extends StatelessWidget {
  const _PhaseTaskRow({required this.theme, required this.palette, required this.task, required this.onTap});

  final _UiTheme theme;
  final _DesignerTaskThumbnailPalette palette;
  final ProjectTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue;
    final accent = overdue ? palette.danger : palette.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.background,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: overdue ? palette.danger.withOpacity(.26) : theme.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: accent.withOpacity(.10), borderRadius: BorderRadius.circular(16)),
                  child: Icon(_boardIconForTask(task), color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14.5)),
                      const SizedBox(height: 5),
                      Text('${task.priority.label} • Due ${DateText.compact(task.dueDate)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.open_in_new_rounded, color: theme.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


String _spacedTaskStatus(String value) {
  final text = value.trim().toUpperCase();
  if (text.length <= 1) return text;
  return text.split('').join(' ');
}

class _DesignerTaskThumbnailPalette {
  const _DesignerTaskThumbnailPalette({
    required this.card,
    required this.thumbnailPanel,
    required this.onCard,
    required this.panelText,
    required this.accent,
    required this.danger,
    required this.border,
    required this.focusBorder,
    required this.panelDivider,
    required this.iconFill,
    required this.iconBorder,
    required this.icon,
    required this.pill,
    required this.pillBorder,
    required this.pillText,
    required this.selectedPill,
    required this.selectedPillText,
    required this.progressTrack,
    required this.chipText,
    required this.dark,
    required this.artMode,
  });

  final Color card;
  final Color thumbnailPanel;
  final Color onCard;
  final Color panelText;
  final Color accent;
  final Color danger;
  final Color border;
  final Color focusBorder;
  final Color panelDivider;
  final Color iconFill;
  final Color iconBorder;
  final Color icon;
  final Color pill;
  final Color pillBorder;
  final Color pillText;
  final Color selectedPill;
  final Color selectedPillText;
  final Color progressTrack;
  final Color chipText;
  final bool dark;
  final int artMode;

  factory _DesignerTaskThumbnailPalette.forTask({required _UiTheme theme, required ProjectTask task}) {
    final danger = const Color(0xFFC85F55);
    final status = task.status;
    if (task.isOverdue) {
      return _DesignerTaskThumbnailPalette._light(
        card: const Color(0xFFF7EFEC),
        panel: const Color(0xFFE9D9D3),
        accent: danger,
        theme: theme,
        artMode: 4,
      );
    }
    switch (status) {
      case TaskStatus.backlog:
        return _DesignerTaskThumbnailPalette._dark(
          card: const Color(0xFF082033),
          panel: const Color(0xFF061827),
          accent: const Color(0xFFBDA98B),
          theme: theme,
          artMode: 0,
        );
      case TaskStatus.todo:
        return _DesignerTaskThumbnailPalette._light(
          card: const Color(0xFFEFE4CF),
          panel: const Color(0xFFE4D6BB),
          accent: const Color(0xFF9A7651),
          theme: theme,
          artMode: 1,
        );
      case TaskStatus.inProgress:
        return _DesignerTaskThumbnailPalette._light(
          card: const Color(0xFFF8F7F3),
          panel: const Color(0xFFEDECE8),
          accent: const Color(0xFFB18472),
          theme: theme,
          artMode: 3,
        );
      case TaskStatus.review:
        return _DesignerTaskThumbnailPalette._dark(
          card: const Color(0xFF8A0D50),
          panel: const Color(0xFF9F145E),
          accent: const Color(0xFFE6C8D5),
          theme: theme,
          artMode: 3,
        );
      case TaskStatus.testing:
        return _DesignerTaskThumbnailPalette._dark(
          card: const Color(0xFF082033),
          panel: const Color(0xFF071B2C),
          accent: const Color(0xFFAFC6D8),
          theme: theme,
          artMode: 5,
        );
      case TaskStatus.completed:
        return _DesignerTaskThumbnailPalette._light(
          card: const Color(0xFFF8F8F5),
          panel: const Color(0xFFEDEDE9),
          accent: const Color(0xFF5F7F55),
          theme: theme,
          artMode: 6,
        );
    }
  }

  factory _DesignerTaskThumbnailPalette._light({required Color card, required Color panel, required Color accent, required _UiTheme theme, required int artMode}) {
    const text = Color(0xFF201E1C);
    return _DesignerTaskThumbnailPalette(
      card: card,
      thumbnailPanel: panel,
      onCard: text,
      panelText: text,
      accent: accent,
      danger: const Color(0xFFC85F55),
      border: Colors.black.withOpacity(.045),
      focusBorder: accent.withOpacity(.62),
      panelDivider: Colors.black.withOpacity(.035),
      iconFill: Colors.black.withOpacity(.045),
      iconBorder: Colors.black.withOpacity(.045),
      icon: accent,
      pill: Colors.white.withOpacity(.58),
      pillBorder: Colors.black.withOpacity(.055),
      pillText: text.withOpacity(.74),
      selectedPill: accent,
      selectedPillText: Colors.white,
      progressTrack: Colors.black.withOpacity(.08),
      chipText: text.withOpacity(.72),
      dark: false,
      artMode: artMode,
    );
  }

  factory _DesignerTaskThumbnailPalette._dark({required Color card, required Color panel, required Color accent, required _UiTheme theme, required int artMode}) {
    return _DesignerTaskThumbnailPalette(
      card: card,
      thumbnailPanel: panel,
      onCard: Colors.white,
      panelText: Colors.white,
      accent: accent,
      danger: const Color(0xFFFF8A78),
      border: Colors.white.withOpacity(.10),
      focusBorder: Colors.white.withOpacity(.54),
      panelDivider: Colors.white.withOpacity(.055),
      iconFill: Colors.white.withOpacity(.10),
      iconBorder: Colors.white.withOpacity(.12),
      icon: Colors.white,
      pill: Colors.black.withOpacity(.16),
      pillBorder: Colors.white.withOpacity(.10),
      pillText: Colors.white.withOpacity(.86),
      selectedPill: Colors.white.withOpacity(.92),
      selectedPillText: card,
      progressTrack: Colors.white.withOpacity(.16),
      chipText: Colors.white.withOpacity(.78),
      dark: true,
      artMode: artMode,
    );
  }
}

class _DesignerTaskThumbChip extends StatelessWidget {
  const _DesignerTaskThumbChip({required this.label, required this.color, required this.dark});

  final String label;
  final Color color;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(dark ? .16 : .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(dark ? .20 : .16)),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10.5)),
    );
  }
}

class _DesignerAssigneeDots extends StatelessWidget {
  const _DesignerAssigneeDots({required this.color, required this.count, required this.label});

  final Color color;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final visibleCount = count <= 0 ? 1 : count.clamp(1, 3).toInt();
    return SizedBox(
      width: 18.0 + visibleCount * 14.0 + (count > 3 ? 18 : 0),
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visibleCount; i++)
            Positioned(
              left: i * 14.0,
              top: 4,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Color.lerp(color, Colors.transparent, .62 + i * .08) ?? color.withOpacity(.30),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(.18), width: 1.2),
                ),
              ),
            ),
          if (count > 3)
            Positioned(
              left: visibleCount * 14.0 + 2,
              top: 5,
              child: Text('+${count - 3}', style: TextStyle(color: color.withOpacity(.72), fontWeight: FontWeight.w900, fontSize: 10.5)),
            ),
        ],
      ),
    );
  }
}

class _TaskBoardDesignerBasePainter extends CustomPainter {
  const _TaskBoardDesignerBasePainter({required this.palette});

  final _DesignerTaskThumbnailPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final vignette = Paint()..shader = RadialGradient(
      center: const Alignment(.66, -.72),
      radius: 1.2,
      colors: [Colors.white.withOpacity(palette.dark ? .050 : .34), Colors.transparent],
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);

    // The visible dot matrix is drawn by _PhaseCardDotGrid so it aligns with the icon row.
    // Keeping the painter free of extra dots prevents the doubled-dot issue from v211.
  }

  @override
  bool shouldRepaint(covariant _TaskBoardDesignerBasePainter oldDelegate) => oldDelegate.palette != palette;
}

class _TaskBoardDesignerArtPainter extends CustomPainter {
  const _TaskBoardDesignerArtPainter({required this.palette, required this.task, required this.projectName});

  final _DesignerTaskThumbnailPalette palette;
  final ProjectTask? task;
  final String projectName;

  @override
  void paint(Canvas canvas, Size size) {
    switch (palette.artMode) {
      case 0:
        _paintBacklog(canvas, size);
        break;
      case 1:
        _paintPlanning(canvas, size);
        break;
      case 2:
        _paintTodo(canvas, size);
        break;
      case 3:
        _paintInProgress(canvas, size);
        break;
      case 4:
        _paintCreative(canvas, size);
        break;
      case 5:
        _paintTesting(canvas, size);
        break;
      default:
        _paintCompleted(canvas, size);
        break;
    }
  }

  void _paintBottomRightRings(Canvas canvas, Size size, {double opacity = .24, Offset? center}) {
    final stroke = Paint()
      ..color = palette.accent.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05;
    final c = center ?? Offset(size.width * .92, size.height * .96);
    for (var i = 0; i < 9; i++) {
      canvas.drawCircle(c, 36 + i * 17, stroke);
    }
  }

  void _paintBacklog(Canvas canvas, Size size) {
    _paintBottomRightRings(canvas, size, opacity: .18, center: Offset(size.width * .98, size.height * .98));
    canvas.drawCircle(Offset(size.width * .78, size.height * .78), size.width * .18, Paint()..color = const Color(0xFF0E3560).withOpacity(.58));
  }

  void _paintPlanning(Canvas canvas, Size size) {
    _paintBottomRightRings(canvas, size, opacity: .20, center: Offset(size.width * .91, size.height * .92));
    canvas.drawCircle(Offset(size.width * .76, size.height * .86), size.width * .18, Paint()..color = palette.accent.withOpacity(.16));
  }

  void _paintTodo(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = palette.accent.withOpacity(.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawArc(Rect.fromCircle(center: Offset(size.width * .50, size.height * 1.02), radius: size.width * .44), -math.pi * .92, math.pi * .84, false, stroke);
    canvas.drawCircle(Offset(size.width * .50, size.height * .97), size.width * .20, Paint()..color = palette.accent.withOpacity(.10));
    canvas.drawCircle(Offset(size.width * .50, size.height * .60), 11, Paint()..color = palette.accent.withOpacity(.42));
  }

  void _paintInProgress(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(size.width * .56, 0, size.width * .44, size.height), Paint()..color = Colors.black.withOpacity(.035));
    final thin = Paint()
      ..color = palette.accent.withOpacity(.48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;
    final c = Offset(size.width * .80, size.height * .48);
    canvas.drawCircle(c, size.width * .22, thin);
    canvas.drawLine(Offset(c.dx, c.dy + size.width * .19), Offset(c.dx, size.height * .86), Paint()..color = palette.accent.withOpacity(.44)..strokeWidth = 1.2);
    canvas.drawCircle(Offset(c.dx, size.height * .86), 3.2, Paint()..color = palette.accent.withOpacity(.68));
    canvas.drawCircle(Offset(size.width * .80, size.height * .62), size.width * .19, Paint()..color = const Color(0xFFC87083).withOpacity(.54));
  }

  void _paintCreative(Canvas canvas, Size size) {
    _paintBottomRightRings(canvas, size, opacity: .18, center: Offset(size.width * .98, size.height * .42));
    final navy = Paint()..color = const Color(0xFF082033);
    canvas.drawCircle(Offset(size.width * .72, size.height * 1.05), size.width * .35, navy);
    canvas.drawCircle(Offset(size.width * .58, size.height * .74), size.width * .16, Paint()..color = palette.accent.withOpacity(.17));
    final dot = Paint()..color = palette.accent.withOpacity(.34);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        canvas.drawCircle(Offset(size.width * .14 + c * 13, size.height * .86 + r * 13), 1.35, dot);
      }
    }
  }

  void _paintTesting(Canvas canvas, Size size) {
    _paintBottomRightRings(canvas, size, opacity: .22, center: Offset(size.width * .93, size.height * .98));
    canvas.drawCircle(Offset(size.width * .78, size.height * .80), size.width * .16, Paint()..color = const Color(0xFF0F5A92).withOpacity(.72));
  }

  void _paintCompleted(Canvas canvas, Size size) {
    _paintBottomRightRings(canvas, size, opacity: .18, center: Offset(size.width * .98, size.height * 1.02));

    // Completed card uses only soft abstract circles here.
    // Keep this decoration icon-free: no large tick/check mark in the artwork.
    final center = Offset(size.width * .82, size.height * .86);
    final ring = Paint()
      ..color = Colors.white.withOpacity(.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15;

    canvas.drawCircle(center, size.width * .21, ring);
    canvas.drawCircle(Offset(size.width * .74, size.height * .80), size.width * .15, Paint()..color = const Color(0xFFE9F0E2).withOpacity(.10));
    canvas.drawCircle(center, size.width * .18, Paint()..color = const Color(0xFF3F6446).withOpacity(.26));
    canvas.drawCircle(Offset(size.width * .90, size.height * .88), size.width * .14, Paint()..color = const Color(0xFF2F5337).withOpacity(.30));
    canvas.drawCircle(Offset(size.width * .70, size.height * .92), size.width * .04, Paint()..color = Colors.white.withOpacity(.08));
  }

  @override
  bool shouldRepaint(covariant _TaskBoardDesignerArtPainter oldDelegate) {
    return oldDelegate.palette != palette || oldDelegate.task?.taskId != task?.taskId || oldDelegate.projectName != projectName;
  }
}

class _TaskBoardDarkChip extends StatelessWidget {
  const _TaskBoardDarkChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withOpacity(.14))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withOpacity(.88)),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(.90), fontWeight: FontWeight.w900, fontSize: 10.5)),
          ),
        ],
      ),
    );
  }
}

class _TaskBoardStackedCardTexturePainter extends CustomPainter {
  const _TaskBoardStackedCardTexturePainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = Colors.white.withOpacity(.07);
    canvas.drawCircle(Offset(size.width * .86, size.height * .22), size.width * .30, soft);
    canvas.drawCircle(Offset(size.width * .12, size.height * .88), size.width * .24, Paint()..color = accent.withOpacity(.18));
    final line = Paint()
      ..color = Colors.white.withOpacity(.08)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var i = -size.height; i < size.width; i += 22) {
      canvas.drawLine(Offset(i.toDouble(), size.height), Offset(i + size.height * .62, 0), line);
    }
  }

  @override
  bool shouldRepaint(covariant _TaskBoardStackedCardTexturePainter oldDelegate) => oldDelegate.accent != accent;
}

class _PinterestLaneBoard extends StatelessWidget {
  const _PinterestLaneBoard({required this.theme, required this.state, required this.lanes, required this.selectedTaskId, required this.motionEnabled, required this.onTaskTap});

  final _UiTheme theme;
  final WorkspaceState state;
  final List<_PinterestBoardLaneData> lanes;
  final String? selectedTaskId;
  final bool motionEnabled;
  final ValueChanged<ProjectTask> onTaskTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 448,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: lanes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final lane = lanes[index];
          return SizedBox(
            width: 270,
            child: _PinterestBoardLane(
              theme: theme,
              state: state,
              lane: lane,
              selectedTaskId: selectedTaskId,
              motionEnabled: motionEnabled,
              onTaskTap: onTaskTap,
            ),
          );
        },
      ),
    );
  }
}

class _PinterestBoardLane extends StatelessWidget {
  const _PinterestBoardLane({required this.theme, required this.state, required this.lane, required this.selectedTaskId, required this.motionEnabled, required this.onTaskTap});

  final _UiTheme theme;
  final WorkspaceState state;
  final _PinterestBoardLaneData lane;
  final String? selectedTaskId;
  final bool motionEnabled;
  final ValueChanged<ProjectTask> onTaskTap;

  @override
  Widget build(BuildContext context) {
    final accent = _boardStatusColor(lane.status, theme);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.lerp(theme.surface, accent, .035),
        borderRadius: BorderRadius.circular(theme.radius + 10),
        border: Border.all(color: accent.withOpacity(.16)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(lane.status.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15))),
              _InfoTag(label: '${lane.tasks.length}', color: accent, theme: theme),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: lane.tasks.isEmpty
                ? _PinterestEmptyLane(theme: theme, accent: accent)
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: lane.tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final task = lane.tasks[index];
                      return _PinterestMiniCard(
                        theme: theme,
                        task: task,
                        projectName: _projectName(state, task.projectId),
                        selected: selectedTaskId == task.taskId,
                        animationIndex: index + (lane.status.index * 2),
                        motionEnabled: motionEnabled,
                        onTap: () => onTaskTap(task),
                        tall: index.isOdd,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PinterestMiniCard extends StatelessWidget {
  const _PinterestMiniCard({
    required this.theme,
    required this.task,
    required this.projectName,
    required this.selected,
    required this.onTap,
    this.tall = false,
    this.animationIndex = 0,
    this.motionEnabled = true,
  });

  final _UiTheme theme;
  final ProjectTask task;
  final String projectName;
  final bool selected;
  final VoidCallback onTap;
  final bool tall;
  final int animationIndex;
  final bool motionEnabled;

  @override
  Widget build(BuildContext context) {
    final accent = task.isOverdue ? const Color(0xFFDC2626) : task.priority.color;
    final progress = _taskProgressForStatus(task.status);
    final delay = (animationIndex * 42).clamp(0, 240).toInt();
    final card = AnimatedScale(
      duration: const Duration(milliseconds: 210),
      curve: Curves.easeOutCubic,
      scale: selected ? 1.018 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            constraints: BoxConstraints(minHeight: tall ? 148 : 118),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: selected ? Color.lerp(theme.surface, accent, .10) : theme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: selected ? accent.withOpacity(.44) : theme.border),
              boxShadow: [
                BoxShadow(
                  color: selected ? accent.withOpacity(.16) : Colors.black.withOpacity(.035),
                  blurRadius: selected ? 26 : 14,
                  offset: Offset(0, selected ? 12 : 8),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          width: selected ? 38 : 34,
                          height: selected ? 38 : 34,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(selected ? .16 : .10),
                            borderRadius: BorderRadius.circular(selected ? 16 : 14),
                          ),
                          child: Icon(_boardIconForTask(task), color: accent, size: selected ? 19 : 18),
                        ),
                        const SizedBox(width: 9),
                        Expanded(child: Text(task.priority.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 11))),
                        if (task.isOverdue) Icon(Icons.warning_amber_rounded, size: 18, color: accent),
                        const SizedBox(width: 6),
                        AnimatedOpacity(
                          opacity: selected ? 1 : .54,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(Icons.open_in_full_rounded, color: selected ? accent : theme.textSecondary, size: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(task.title, maxLines: tall ? 3 : 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14, height: 1.15)),
                    const SizedBox(height: 8),
                    Text(projectName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 11.5)),
                    const SizedBox(height: 11),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(value: progress, minHeight: 6, color: accent, backgroundColor: accent.withOpacity(.10)),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _BoardTinyChip(theme: theme, label: DateText.compact(task.dueDate), icon: Icons.calendar_month_rounded, color: task.isOverdue ? const Color(0xFFDC2626) : theme.textSecondary),
                        if (task.commentsCount > 0) _BoardTinyChip(theme: theme, label: '${task.commentsCount}', icon: Icons.chat_bubble_rounded, color: theme.textSecondary),
                        if (task.attachmentsCount > 0) _BoardTinyChip(theme: theme, label: '${task.attachmentsCount}', icon: Icons.attach_file_rounded, color: theme.textSecondary),
                      ],
                    ),
                  ],
                ),
                if (selected)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle, border: Border.all(color: theme.surface, width: 2)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!motionEnabled) return card;
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('board-card-motion-${task.taskId}'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + delay),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        final safe = value.clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: safe,
          child: Transform.translate(
            offset: Offset(0, (1 - safe) * 26),
            child: Transform.scale(
              scale: .94 + (safe * .06),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
      child: card,
    );
  }
}


class _TaskBoardPreviewDialog extends StatelessWidget {
  const _TaskBoardPreviewDialog({required this.theme, required this.task, required this.projectName, required this.assignees});

  final _UiTheme theme;
  final ProjectTask task;
  final String projectName;
  final String assignees;

  @override
  Widget build(BuildContext context) {
    final palette = _DesignerTaskThumbnailPalette.forTask(theme: theme, task: task);
    final accent = task.isOverdue ? palette.danger : palette.accent;
    final progress = _taskProgressForStatus(task.status).clamp(0.0, 1.0).toDouble();
    final assigned = assignees.trim().isEmpty ? 'Unassigned' : assignees.trim();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
      backgroundColor: Colors.transparent,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: .92, end: 1),
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0.0, 1.0).toDouble(), child: child),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: palette.focusBorder.withOpacity(.72), width: 1.2),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.30), blurRadius: 34, offset: const Offset(0, 22))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 206,
                child: Row(
                  children: [
                    Expanded(
                      flex: 10,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(color: palette.iconFill, borderRadius: BorderRadius.circular(16), border: Border.all(color: palette.iconBorder)),
                                  child: Icon(_boardIconForTask(task), color: palette.icon, size: 22),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(color: palette.selectedPill, borderRadius: BorderRadius.circular(999)),
                                  child: Text('WATCH', style: TextStyle(color: palette.selectedPillText, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: .5)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(_spacedTaskStatus(task.status.label), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 9.5, letterSpacing: 3.2)),
                            const SizedBox(height: 8),
                            Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.onCard, fontWeight: FontWeight.w900, fontSize: 24, height: 1.02, letterSpacing: -.45)),
                            const SizedBox(height: 8),
                            Container(width: 58, height: 1.3, color: accent.withOpacity(.62)),
                            const Spacer(),
                            Text('$projectName • $assigned', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.onCard.withOpacity(.62), fontWeight: FontWeight.w800, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 8,
                      child: Container(
                        decoration: BoxDecoration(color: palette.thumbnailPanel, border: Border(left: BorderSide(color: palette.panelDivider))),
                        child: CustomPaint(painter: _TaskBoardDesignerArtPainter(palette: palette, task: task, projectName: projectName)),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _BoardTinyChip(theme: theme, label: task.priority.label, icon: Icons.flag_rounded, color: accent),
                        const SizedBox(width: 8),
                        _BoardTinyChip(theme: theme, label: DateText.compact(task.dueDate), icon: Icons.calendar_month_rounded, color: palette.chipText),
                        const Spacer(),
                        Text('${(progress * 100).round()}%', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(value: progress, minHeight: 7, color: accent, backgroundColor: palette.progressTrack),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: palette.onCard,
                              side: BorderSide(color: palette.border),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Open full task', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinterestTaskDetailSheet extends StatelessWidget {
  const _PinterestTaskDetailSheet({required this.theme, required this.task, required this.projectName, required this.assignees});

  final _UiTheme theme;
  final ProjectTask task;
  final String projectName;
  final String assignees;

  @override
  Widget build(BuildContext context) {
    final accent = task.isOverdue ? const Color(0xFFDC2626) : task.priority.color;
    final progress = _taskProgressForStatus(task.status);
    final effort = task.effortUsage.clamp(0.0, 1.0).toDouble();
    final createdAt = task.createdAt;
    final updatedAt = task.updatedAt;
    final completedAt = task.completedAt;
    final assigneeLabel = assignees.trim().isEmpty ? 'Unassigned' : assignees;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, (1 - value) * 36),
        child: Opacity(opacity: value, child: child),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: .88,
        minChildSize: .55,
        maxChildSize: .96,
        expand: false,
        builder: (context, controller) => Container(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.18), blurRadius: 32, offset: const Offset(0, -12))],
          ),
          child: ListView(
            controller: controller,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            children: [
              Center(
                child: Container(width: 46, height: 5, decoration: BoxDecoration(color: theme.border, borderRadius: BorderRadius.circular(999))),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Color.lerp(theme.surface, accent, .10),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: accent.withOpacity(.18)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 48, height: 48, decoration: BoxDecoration(color: accent.withOpacity(.12), borderRadius: BorderRadius.circular(18)), child: Icon(_boardIconForTask(task), color: accent, size: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Task details', style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(task.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 19, height: 1.12)),
                            ],
                          ),
                        ),
                        IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.close_rounded, color: theme.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _BoardTinyChip(theme: theme, label: task.status.label, icon: _boardIconForTask(task), color: task.status.color),
                        _BoardTinyChip(theme: theme, label: task.priority.label, icon: Icons.flag_rounded, color: accent),
                        if (task.isOverdue) _BoardTinyChip(theme: theme, label: 'Overdue', icon: Icons.warning_amber_rounded, color: const Color(0xFFDC2626)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (task.description.trim().isNotEmpty)
                _BoardDetailSection(
                  theme: theme,
                  title: 'Description',
                  child: Text(task.description, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w700, height: 1.35)),
                ),
              _BoardDetailSection(
                theme: theme,
                title: 'Execution',
                child: Column(
                  children: [
                    _BoardDetailProgress(theme: theme, label: 'Status progress', value: progress, color: accent, valueText: '${(progress * 100).round()}%'),
                    const SizedBox(height: 12),
                    _BoardDetailProgress(theme: theme, label: 'Effort usage', value: effort, color: theme.accent, valueText: task.estimatedHours == 0 ? 'No estimate' : '${task.loggedHours}/${task.estimatedHours}h'),
                  ],
                ),
              ),
              _BoardDetailSection(
                theme: theme,
                title: 'Task information',
                child: Column(
                  children: [
                    _BoardDetailRow(theme: theme, icon: Icons.folder_rounded, label: 'Project', value: projectName.trim().isEmpty ? 'Unknown project' : projectName),
                    _BoardDetailRow(theme: theme, icon: Icons.people_rounded, label: 'Assignees', value: assigneeLabel),
                    _BoardDetailRow(theme: theme, icon: Icons.calendar_month_rounded, label: 'Due date', value: DateText.compact(task.dueDate)),
                    if (createdAt != null) _BoardDetailRow(theme: theme, icon: Icons.add_circle_outline_rounded, label: 'Created', value: DateText.compact(createdAt)),
                    if (updatedAt != null) _BoardDetailRow(theme: theme, icon: Icons.update_rounded, label: 'Updated', value: DateText.compact(updatedAt)),
                    if (completedAt != null) _BoardDetailRow(theme: theme, icon: Icons.verified_rounded, label: 'Completed', value: DateText.compact(completedAt)),
                  ],
                ),
              ),
              _BoardDetailSection(
                theme: theme,
                title: 'Activity',
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _BoardDetailMetric(theme: theme, icon: Icons.chat_bubble_rounded, label: 'Comments', value: '${task.commentsCount}'),
                    _BoardDetailMetric(theme: theme, icon: Icons.attach_file_rounded, label: 'Files', value: '${task.attachmentsCount}'),
                    _BoardDetailMetric(theme: theme, icon: Icons.timer_rounded, label: 'Logged', value: '${task.loggedHours}h'),
                    _BoardDetailMetric(theme: theme, icon: Icons.schedule_rounded, label: 'Estimate', value: '${task.estimatedHours}h'),
                  ],
                ),
              ),
              if (task.tags.isNotEmpty)
                _BoardDetailSection(
                  theme: theme,
                  title: 'Tags',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: task.tags.map((tag) => _BoardTinyChip(theme: theme, label: tag, icon: Icons.local_offer_rounded, color: theme.textSecondary)).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardDetailSection extends StatelessWidget {
  const _BoardDetailSection({required this.theme, required this.title, required this.child});

  final _UiTheme theme;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.background.withOpacity(.58),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14.5)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _BoardDetailProgress extends StatelessWidget {
  const _BoardDetailProgress({required this.theme, required this.label, required this.value, required this.color, required this.valueText});

  final _UiTheme theme;
  final String label;
  final double value;
  final Color color;
  final String valueText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 12))),
            Text(valueText, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: value.clamp(0.0, 1.0).toDouble(), minHeight: 8, color: color, backgroundColor: color.withOpacity(.10)),
        ),
      ],
    );
  }
}

class _BoardDetailRow extends StatelessWidget {
  const _BoardDetailRow({required this.theme, required this.icon, required this.label, required this.value});

  final _UiTheme theme;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: theme.accent.withOpacity(.08), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: theme.accent, size: 17)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardDetailMetric extends StatelessWidget {
  const _BoardDetailMetric({required this.theme, required this.icon, required this.label, required this.value});

  final _UiTheme theme;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: theme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.accent, size: 18),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 11)),
        ],
      ),
    );
  }
}

class _BoardTinyChip extends StatelessWidget {
  const _BoardTinyChip({required this.theme, required this.label, required this.icon, required this.color});
  final _UiTheme theme;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(.07), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(.14))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: color), const SizedBox(width: 4), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10))]),
    );
  }
}

class _PinterestEmptyLane extends StatelessWidget {
  const _PinterestEmptyLane({required this.theme, required this.accent});
  final _UiTheme theme;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(color: theme.surface.withOpacity(.58), borderRadius: BorderRadius.circular(22), border: Border.all(color: theme.border)),
      child: Text('No cards', style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

Color _boardStatusColor(TaskStatus status, _UiTheme theme) {
  return switch (status) {
    TaskStatus.backlog => const Color(0xFF64748B),
    TaskStatus.todo => const Color(0xFF2563EB),
    TaskStatus.inProgress => theme.accent,
    TaskStatus.review => const Color(0xFF7C3AED),
    TaskStatus.testing => const Color(0xFFF59E0B),
    TaskStatus.completed => const Color(0xFF059669),
  };
}

IconData _boardIconForTask(ProjectTask task) {
  if (task.isOverdue) return Icons.warning_amber_rounded;
  return switch (task.status) {
    TaskStatus.backlog => Icons.inbox_rounded,
    TaskStatus.todo => Icons.radio_button_unchecked_rounded,
    TaskStatus.inProgress => Icons.bolt_rounded,
    TaskStatus.review => Icons.rate_review_rounded,
    TaskStatus.testing => Icons.science_rounded,
    TaskStatus.completed => Icons.verified_rounded,
  };
}


Widget _referenceModuleIcon(_UiTheme theme, IconData icon, {Color? color}) {
  final accent = color ?? theme.accent;
  return Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: accent.withOpacity(.10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Icon(icon, color: accent, size: 22),
  );
}

Widget _referenceModuleCard({
  required _UiTheme theme,
  required String title,
  required String subtitle,
  required IconData icon,
  Color? color,
  Widget? trailing,
  Widget? footer,
}) {
  final accent = color ?? theme.accent;
  return _Surface(
    theme: theme,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _referenceModuleIcon(theme, icon, color: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 5),
                  Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.28)),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing,
            ],
          ],
        ),
        if (footer != null) ...[
          const SizedBox(height: 14),
          footer,
        ],
      ],
    ),
  );
}

Widget _referenceModuleSummary({required _UiTheme theme, required String title, required String subtitle, required IconData icon}) {
  return _Surface(
    theme: theme,
    child: Row(
      children: [
        _referenceModuleIcon(theme, icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReferenceFilterPills extends StatelessWidget {
  const _ReferenceFilterPills({required this.theme, required this.items, required this.selected, required this.onChanged});

  final _UiTheme theme;
  final List<String> items;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((item) {
          final active = _samePageFilter(item, selected);
          return ChoiceChip(
            selected: active,
            onSelected: (_) => onChanged(item),
            avatar: active ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
            label: Text(item),
            selectedColor: theme.accent,
            backgroundColor: theme.surface,
            side: BorderSide(color: active ? theme.accent : theme.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            labelStyle: TextStyle(color: active ? Colors.white : theme.textPrimary, fontWeight: FontWeight.w900),
          );
        }).toList(),
      ),
    );
  }
}

class _TaskMapDataJsonScreen extends StatelessWidget {
  const _TaskMapDataJsonScreen({required this.state, required this.data, required this.theme, this.embedded = false});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final tasks = state.visibleTasks.toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final visible = tasks.take(_num(data['limit'], 8).round().clamp(1, 40).toInt()).toList();
    final children = <Widget>[
      if (!embedded)
        _ScreenTitle(
          title: _textOf(data, 'title', 'Task map'),
          subtitle: _textOf(data, 'subtitle', 'Site/location preview'),
        ),
      _Surface(
        theme: theme,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _referenceModuleIcon(theme, Icons.location_on_rounded),
                const SizedBox(width: 12),
                Expanded(child: Text('Live task/site data', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16))),
                _InfoTag(label: '${tasks.length} tasks', icon: Icons.task_alt_rounded, theme: theme),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 210,
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.accent.withOpacity(.075),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: theme.border),
              ),
              child: CustomPaint(
                painter: _TaskMapPreviewPainter(theme.accent),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      tasks.isEmpty ? 'No assigned task locations yet' : '${state.visibleProjects.length} projects • ${tasks.length} task rows',
                      style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      if (visible.isEmpty)
        _referenceModuleCard(
          theme: theme,
          title: 'No task map data',
          subtitle: 'Add tasks with assigned users/projects. Location pins can be connected when task/site coordinates are stored.',
          icon: Icons.near_me_rounded,
        )
      else
        ...visible.map((task) => _referenceModuleCard(
              theme: theme,
              title: task.title,
              subtitle: '${_projectName(state, task.projectId)} • ${task.status.label} • Due ${DateText.compact(task.dueDate)}',
              icon: Icons.near_me_rounded,
              color: task.status.color,
              trailing: Icon(Icons.circle, color: task.status.color, size: 16),
            )),
    ];
    return embedded
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)
        : ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(theme.padding), children: children);
  }
}

class _TaskMapPreviewPainter extends CustomPainter {
  const _TaskMapPreviewPainter(this.accent);
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = accent.withOpacity(.08)..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += size.width / 5) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.width * .15, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += size.height / 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + size.height * .08), grid);
    }
    final path = Path()
      ..moveTo(size.width * .12, size.height * .70)
      ..quadraticBezierTo(size.width * .35, size.height * .28, size.width * .55, size.height * .52)
      ..quadraticBezierTo(size.width * .74, size.height * .74, size.width * .88, size.height * .30);
    canvas.drawPath(path, Paint()..color = accent.withOpacity(.55)..strokeWidth = 4..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    final pins = <Offset>[
      Offset(size.width * .12, size.height * .70),
      Offset(size.width * .36, size.height * .35),
      Offset(size.width * .58, size.height * .53),
      Offset(size.width * .88, size.height * .30),
    ];
    for (final pin in pins) {
      canvas.drawCircle(pin, 11, Paint()..color = accent);
      canvas.drawCircle(pin, 5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _TaskMapPreviewPainter oldDelegate) => oldDelegate.accent != accent;
}

class _CalendarDataJsonScreen extends StatefulWidget {
  const _CalendarDataJsonScreen({required this.state, required this.data, required this.theme, this.embedded = false});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;

  @override
  State<_CalendarDataJsonScreen> createState() => _CalendarDataJsonScreenState();
}

class _CalendarDataJsonScreenState extends State<_CalendarDataJsonScreen> {
  DateTime? _selectedDate;
  DateTime? _visibleMonth;
  String _calendarFilter = 'all';

  DateTime _monthOnly(DateTime date) => DateTime(date.year, date.month);

  DateTime _shiftMonth(DateTime date, int offset) => DateTime(date.year, date.month + offset);

  DateTime _defaultSelectedDateForMonth(DateTime month, List<ProjectTask> tasks, List<AppNotification> meetings) {
    final candidates = <DateTime>[
      for (final task in tasks)
        if (task.dueDate.year == month.year && task.dueDate.month == month.month) task.dueDate,
      for (final task in tasks)
        if (task.createdAt != null && task.createdAt!.year == month.year && task.createdAt!.month == month.month) task.createdAt!,
      for (final item in meetings)
        if (item.createdAt.year == month.year && item.createdAt.month == month.month) item.createdAt,
    ]..sort();
    if (candidates.isNotEmpty) return DateTime(candidates.first.year, candidates.first.month, candidates.first.day);
    final now = DateTime.now();
    if (now.year == month.year && now.month == month.month) return DateTime(now.year, now.month, now.day);
    return DateTime(month.year, month.month);
  }

  void _goToMonth(DateTime month, List<ProjectTask> tasks, List<AppNotification> meetings) {
    final normalized = _monthOnly(month);
    setState(() {
      _visibleMonth = normalized;
      _calendarFilter = 'all';
      final selected = _selectedDate;
      if (selected == null || selected.year != normalized.year || selected.month != normalized.month) {
        _selectedDate = _defaultSelectedDateForMonth(normalized, tasks, meetings);
      }
    });
  }

  Future<void> _showMonthPicker(BuildContext context, DateTime currentMonth, List<ProjectTask> tasks, List<AppNotification> meetings) async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CalendarMonthPickerSheet(
        theme: widget.theme,
        initialMonth: currentMonth,
        tasks: tasks,
        meetings: meetings,
      ),
    );
    if (picked != null && mounted) {
      _goToMonth(picked, tasks, meetings);
    }
  }

  String _monthLabel(DateTime date) {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final index = (date.month - 1).clamp(0, months.length - 1).toInt();
    return '${months[index]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final data = widget.data;
    final theme = widget.theme;
    final now = DateTime.now();
    final tasks = state.visibleTasks.toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final meetings = state.myNotifications.where((item) => item.isMeetingInvite).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final monthStart = _visibleMonth ?? DateTime(now.year, now.month);
    final daysInMonth = DateTime(monthStart.year, monthStart.month + 1, 0).day;
    final selectedDate = _selectedDate != null && _selectedDate!.year == monthStart.year && _selectedDate!.month == monthStart.month
        ? _selectedDate!
        : _defaultSelectedDateForMonth(monthStart, tasks, meetings);
    final selectedDeadlineTasks = tasks.where((task) => _isSameDate(task.dueDate, selectedDate)).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final selectedAssignedTasks = tasks.where((task) {
      final createdAt = task.createdAt;
      return createdAt != null && _isSameDate(createdAt, selectedDate);
    }).toList()
      ..sort((a, b) => _taskActivityDateForSort(b).compareTo(_taskActivityDateForSort(a)));
    final selectedMeetings = meetings.where((item) => _isSameDate(item.createdAt, selectedDate)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final selectedDeadlineIds = selectedDeadlineTasks.map((task) => task.taskId).toSet();
    final selectedAssignedOnlyTasks = selectedAssignedTasks.where((task) => !selectedDeadlineIds.contains(task.taskId)).toList();
    final hasSelectedCalendarItems = selectedDeadlineTasks.isNotEmpty || selectedAssignedTasks.isNotEmpty || selectedMeetings.isNotEmpty;
    final showDeadlineSection = _calendarFilter == 'all' || _calendarFilter == 'deadlines';
    final showAssignedSection = _calendarFilter == 'all' || _calendarFilter == 'assigned';
    final showMeetingSection = _calendarFilter == 'all' || _calendarFilter == 'meetings';
    final visibleAssignedTasks = _calendarFilter == 'assigned' ? selectedAssignedTasks : selectedAssignedOnlyTasks;
    final hasVisibleCalendarItems = (showDeadlineSection && selectedDeadlineTasks.isNotEmpty) ||
        (showAssignedSection && visibleAssignedTasks.isNotEmpty) ||
        (showMeetingSection && selectedMeetings.isNotEmpty);
    final assignedDays = <int>{
      for (final task in tasks)
        if (task.createdAt != null && task.createdAt!.year == monthStart.year && task.createdAt!.month == monthStart.month) task.createdAt!.day,
    };
    final deadlineDays = <int>{
      for (final task in tasks.where((task) => task.dueDate.year == monthStart.year && task.dueDate.month == monthStart.month)) task.dueDate.day,
    };
    final meetingDays = <int>{
      for (final item in meetings.where((item) => item.createdAt.year == monthStart.year && item.createdAt.month == monthStart.month)) item.createdAt.day,
    };
    final selectedDay = selectedDate.year == monthStart.year && selectedDate.month == monthStart.month ? selectedDate.day : 0;
    final todayDay = now.year == monthStart.year && now.month == monthStart.month ? now.day : -1;
    final children = <Widget>[
      if (!widget.embedded)
        _ScreenTitle(
          title: _textOf(data, 'title', 'Calendar'),
          subtitle: _textOf(data, 'subtitle', 'Deadlines, assignments and meetings from Firestore'),
        ),
      _Surface(
        theme: theme,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CalendarMonthNavButton(
                  theme: theme,
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _goToMonth(_shiftMonth(monthStart, -1), tasks, meetings),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _showMonthPicker(context, monthStart, tasks, meetings),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: theme.accent.withOpacity(.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: theme.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _monthLabel(monthStart),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.keyboard_arrow_down_rounded, color: theme.accent, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _CalendarMonthNavButton(
                  theme: theme,
                  icon: Icons.chevron_right_rounded,
                  onTap: () => _goToMonth(_shiftMonth(monthStart, 1), tasks, meetings),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _InfoTag(label: '${tasks.length + meetings.length} total items', icon: Icons.event_rounded, theme: theme)),
                const SizedBox(width: 8),
                _InfoTag(label: todayDay > 0 ? 'Today $todayDay' : 'Today', icon: Icons.today_rounded, color: theme.textPrimary.withOpacity(.70), theme: theme),
              ],
            ),
            const SizedBox(height: 10),
            const SizedBox(height: 4),
            _CalendarGrid(
              theme: theme,
              daysInMonth: daysInMonth,
              firstWeekday: monthStart.weekday,
              today: todayDay,
              selectedDay: selectedDay,
              assignedDays: assignedDays,
              deadlineDays: deadlineDays,
              meetingDays: meetingDays,
              onDayTap: (day) => setState(() {
                _selectedDate = DateTime(monthStart.year, monthStart.month, day);
                _calendarFilter = 'all';
              }),
            ),
          ],
        ),
      ),
      _CalendarDateFilterPanel(
        theme: theme,
        selectedDate: selectedDate,
        selectedFilter: _calendarFilter,
        deadlineCount: selectedDeadlineTasks.length,
        assignedCount: selectedAssignedTasks.length,
        meetingCount: selectedMeetings.length,
        onFilterChanged: (filter) => setState(() => _calendarFilter = filter),
      ),
      if (!hasSelectedCalendarItems)
        _referenceModuleCard(
          theme: theme,
          title: 'No tasks on this date',
          subtitle: 'Only tasks with a deadline date or assigned/created date matching the selected calendar date appear here.',
          icon: Icons.event_busy_rounded,
        )
      else if (!hasVisibleCalendarItems)
        _referenceModuleCard(
          theme: theme,
          title: 'No ${_calendarFilter == 'deadlines' ? 'deadlines' : _calendarFilter == 'assigned' ? 'assigned tasks' : 'meetings'} on this date',
          subtitle: 'Change the filter tab to view other calendar items for ${DateText.compact(selectedDate)}.',
          icon: Icons.filter_alt_off_rounded,
        )
      else ...[
        if (showDeadlineSection && selectedDeadlineTasks.isNotEmpty)
          _CalendarTaskSection(
            theme: theme,
            state: state,
            title: 'Deadlines',
            subtitle: 'Deadline items are shown first when a selected date has both deadlines and assigned tasks.',
            tasks: selectedDeadlineTasks,
            isDeadlineSection: true,
          ),
        if (showAssignedSection && visibleAssignedTasks.isNotEmpty)
          _CalendarTaskSection(
            theme: theme,
            state: state,
            title: 'Assigned tasks',
            subtitle: 'Tasks created or assigned on the selected date.',
            tasks: visibleAssignedTasks,
            isDeadlineSection: false,
          ),
        if (showMeetingSection && selectedMeetings.isNotEmpty)
          _CalendarMeetingSection(theme: theme, meetings: selectedMeetings),
      ],
    ];
    return widget.embedded
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)
        : ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(theme.padding), children: children);
  }
}



class _CalendarDateFilterPanel extends StatelessWidget {
  const _CalendarDateFilterPanel({
    required this.theme,
    required this.selectedDate,
    required this.selectedFilter,
    required this.deadlineCount,
    required this.assignedCount,
    required this.meetingCount,
    required this.onFilterChanged,
  });

  final _UiTheme theme;
  final DateTime selectedDate;
  final String selectedFilter;
  final int deadlineCount;
  final int assignedCount;
  final int meetingCount;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final totalCount = deadlineCount + assignedCount + meetingCount;
    return _Surface(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CalendarSectionBadge(label: 'S', color: theme.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Selected date', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('${DateText.compact(selectedDate)} • deadline list first, assigned task list second', style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.2)),
                  ],
                ),
              ),
              _InfoTag(label: '$totalCount item(s)', theme: theme),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CalendarFilterTab(theme: theme, value: 'all', label: 'All', count: totalCount, selected: selectedFilter == 'all', onTap: onFilterChanged),
              _CalendarFilterTab(theme: theme, value: 'deadlines', label: 'Deadlines', count: deadlineCount, selected: selectedFilter == 'deadlines', onTap: onFilterChanged),
              _CalendarFilterTab(theme: theme, value: 'assigned', label: 'Assigned', count: assignedCount, selected: selectedFilter == 'assigned', onTap: onFilterChanged),
              if (meetingCount > 0) _CalendarFilterTab(theme: theme, value: 'meetings', label: 'Meetings', count: meetingCount, selected: selectedFilter == 'meetings', onTap: onFilterChanged),
            ],
          ),
        ],
      ),
    );
  }
}


class _CalendarSectionBadge extends StatelessWidget {
  const _CalendarSectionBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13, height: 1)),
    );
  }
}

class _CalendarCountLabel extends StatelessWidget {
  const _CalendarCountLabel({required this.theme, required this.label, required this.count, required this.icon, required this.color});

  final _UiTheme theme;
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label $count', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CalendarFilterTab extends StatelessWidget {
  const _CalendarFilterTab({required this.theme, required this.value, required this.label, required this.count, required this.selected, required this.onTap});

  final _UiTheme theme;
  final String value;
  final String label;
  final int count;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? theme.accent : theme.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? theme.accent : theme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$label $count', style: TextStyle(color: selected ? Colors.white : theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarTaskSection extends StatelessWidget {
  const _CalendarTaskSection({required this.theme, required this.state, required this.title, required this.subtitle, required this.tasks, required this.isDeadlineSection});

  final _UiTheme theme;
  final WorkspaceState state;
  final String title;
  final String subtitle;
  final List<ProjectTask> tasks;
  final bool isDeadlineSection;

  @override
  Widget build(BuildContext context) {
    final accent = isDeadlineSection ? const Color(0xFFB45309) : theme.accent;
    return _Surface(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CalendarSectionBadge(label: isDeadlineSection ? 'D' : 'A', color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.2)),
                  ],
                ),
              ),
              _InfoTag(label: '${tasks.length}', color: accent, theme: theme),
            ],
          ),
          const SizedBox(height: 12),
          for (final entry in tasks.asMap().entries) ...[
            if (entry.key > 0) Divider(height: 18, color: theme.border),
            _CalendarTaskListRow(theme: theme, state: state, task: entry.value, isDeadline: isDeadlineSection),
          ],
        ],
      ),
    );
  }
}

class _CalendarTaskListRow extends StatelessWidget {
  const _CalendarTaskListRow({required this.theme, required this.state, required this.task, required this.isDeadline});

  final _UiTheme theme;
  final WorkspaceState state;
  final ProjectTask task;
  final bool isDeadline;

  @override
  Widget build(BuildContext context) {
    final accent = isDeadline ? task.priority.color : theme.accent;
    final assignedDate = task.createdAt ?? task.updatedAt ?? task.dueDate;
    final parts = <String>[
      isDeadline ? 'Due ${DateText.compact(task.dueDate)}' : 'Assigned ${DateText.compact(assignedDate)}',
      _projectName(state, task.projectId),
      task.priority.label,
      task.status.label,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: accent.withOpacity(.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: accent.withOpacity(.20))),
          child: Icon(isDeadline ? Icons.flag_rounded : Icons.assignment_turned_in_rounded, color: accent, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14.5)),
              const SizedBox(height: 5),
              Text(parts.join(' • '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12, height: 1.25)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (isDeadline)
          DeadlineCountdownChip(deadline: task.dueDate, completed: task.status == TaskStatus.completed, compact: true)
        else
          _InfoTag(label: 'Assigned', color: theme.accent.withOpacity(.72), theme: theme),
      ],
    );
  }
}

class _CalendarMeetingSection extends StatelessWidget {
  const _CalendarMeetingSection({required this.theme, required this.meetings});

  final _UiTheme theme;
  final List<AppNotification> meetings;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7C3AED);
    return _Surface(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CalendarSectionBadge(label: 'M', color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Meetings', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Meeting invites visible on the selected date.', style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.2)),
                  ],
                ),
              ),
              _InfoTag(label: '${meetings.length}', color: accent, theme: theme),
            ],
          ),
          const SizedBox(height: 12),
          for (final entry in meetings.asMap().entries) ...[
            if (entry.key > 0) Divider(height: 18, color: theme.border),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: accent.withOpacity(.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: accent.withOpacity(.20))),
                  child: const Icon(Icons.video_call_rounded, color: accent, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.value.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14.5)),
                      const SizedBox(height: 5),
                      Text('${DateText.compact(entry.value.createdAt)} • ${entry.value.message}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12, height: 1.25)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CalendarMonthNavButton extends StatelessWidget {
  const _CalendarMonthNavButton({required this.theme, required this.icon, required this.onTap});

  final _UiTheme theme;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.border),
          ),
          child: Icon(icon, color: theme.textPrimary, size: 24),
        ),
      ),
    );
  }
}

class _CalendarMonthPickerSheet extends StatefulWidget {
  const _CalendarMonthPickerSheet({required this.theme, required this.initialMonth, required this.tasks, required this.meetings});

  final _UiTheme theme;
  final DateTime initialMonth;
  final List<ProjectTask> tasks;
  final List<AppNotification> meetings;

  @override
  State<_CalendarMonthPickerSheet> createState() => _CalendarMonthPickerSheetState();
}

class _CalendarMonthPickerSheetState extends State<_CalendarMonthPickerSheet> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initialMonth.year;
  }

  bool _hasItemsInMonth(int month) {
    return widget.tasks.any((task) =>
            (task.dueDate.year == _year && task.dueDate.month == month) ||
            (task.createdAt != null && task.createdAt!.year == _year && task.createdAt!.month == month)) ||
        widget.meetings.any((item) => item.createdAt.year == _year && item.createdAt.month == month);
  }

  @override
  Widget build(BuildContext context) {
    const months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final theme = widget.theme;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: theme.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.10), blurRadius: 26, offset: const Offset(0, 14))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Pick month', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 18))),
                _CalendarMonthNavButton(theme: theme, icon: Icons.chevron_left_rounded, onTap: () => setState(() => _year--)),
                const SizedBox(width: 8),
                Container(
                  height: 44,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.accent.withOpacity(.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: theme.border),
                  ),
                  child: Text('$_year', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 8),
                _CalendarMonthNavButton(theme: theme, icon: Icons.chevron_right_rounded, onTap: () => setState(() => _year++)),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 360 ? 3 : 4;
                final spacing = 10.0;
                final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: List.generate(12, (index) {
                    final month = index + 1;
                    final active = widget.initialMonth.year == _year && widget.initialMonth.month == month;
                    final hasItems = _hasItemsInMonth(month);
                    return SizedBox(
                      width: itemWidth,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.of(context).pop(DateTime(_year, month)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          height: 54,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active
                                ? theme.accent
                                : hasItems
                                    ? theme.accent.withOpacity(.10)
                                    : theme.background,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: active ? theme.accent : theme.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  months[index],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: active ? Colors.white : theme.textPrimary, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.theme,
    required this.daysInMonth,
    required this.firstWeekday,
    required this.today,
    required this.selectedDay,
    required this.assignedDays,
    required this.deadlineDays,
    required this.meetingDays,
    required this.onDayTap,
  });

  final _UiTheme theme;
  final int daysInMonth;
  final int firstWeekday;
  final int today;
  final int selectedDay;
  final Set<int> assignedDays;
  final Set<int> deadlineDays;
  final Set<int> meetingDays;
  final ValueChanged<int> onDayTap;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    const names = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    for (final day in names) {
      cells.add(Center(child: Text(day, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 12))));
    }
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      cells.add(_CalendarDayCell(
        theme: theme,
        day: day,
        isToday: day == today,
        selected: day == selectedDay,
        hasAssigned: assignedDays.contains(day),
        hasDeadline: deadlineDays.contains(day),
        hasMeeting: meetingDays.contains(day),
        onTap: () => onDayTap(day),
      ));
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1,
      children: cells,
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.theme,
    required this.day,
    required this.isToday,
    required this.selected,
    required this.hasAssigned,
    required this.hasDeadline,
    required this.hasMeeting,
    required this.onTap,
  });

  final _UiTheme theme;
  final int day;
  final bool isToday;
  final bool selected;
  final bool hasAssigned;
  final bool hasDeadline;
  final bool hasMeeting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final marked = hasDeadline || hasAssigned || hasMeeting;
    final background = selected
        ? theme.accent
        : hasDeadline
            ? theme.accent
            : marked
                ? theme.accent.withOpacity(.12)
                : isToday
                    ? theme.textPrimary.withOpacity(.045)
                    : Colors.transparent;
    final borderColor = selected
        ? theme.accent
        : isToday
            ? theme.accent
            : marked
                ? theme.accent.withOpacity(.22)
                : Colors.transparent;
    final textColor = selected || hasDeadline ? Colors.white : theme.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Text('$day', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 12)),
        ),
      ),
    );
  }
}


class _TimelineDataJsonScreen extends StatelessWidget {
  const _TimelineDataJsonScreen({required this.state, required this.data, required this.theme, this.embedded = false, this.onExternalAction});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;
  final ValueChanged<String>? onExternalAction;

  @override
  Widget build(BuildContext context) {
    final projects = state.visibleProjects.toList()
      ..sort((a, b) {
        final activeCompare = (b.isActiveWork ? 1 : 0).compareTo(a.isActiveWork ? 1 : 0);
        if (activeCompare != 0) return activeCompare;
        return a.dueDate.compareTo(b.dueDate);
      });
    final tasks = _timelineTasksForState(state);
    final defaultProject = projects.isEmpty ? null : projects.first;
    final visualConfig = _asMap(data['timelineVisualConfig']) ?? _asMap(data['taskProgressConfig']) ?? const <String, dynamic>{};
    final variant = _textOf(data, 'variant', _textOf(visualConfig, 'variant', '')).toLowerCase();
    final milestoneMode = _textOf(visualConfig, 'milestonePageMode', _textOf(data, 'milestonePageMode', '')).replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
    final separateTaskTimeline = _flag(
      data['separateTaskTimeline'] ?? visualConfig['separateTaskTimeline'] ?? visualConfig['taskTimelineSeparateScreen'],
      fallback: milestoneMode == 'projectmilestonesonly',
    );
    final showTaskProgress = _flag(
      data['showTaskProgressInsideMilestones'] ??
          visualConfig['showTaskProgressInsideMilestones'] ??
          data['showTaskProgressCard'] ??
          visualConfig['showTaskProgressCard'] ??
          visualConfig['enabled'] ??
          data['productiveTimeline'],
      fallback: !separateTaskTimeline && (variant == 'productivetimeline' || variant == 'deliverystyle' || variant == 'taskprogresstimeline'),
    );
    final showTimelineBars = _flag(
      data['showTaskTimelineInsideMilestones'] ??
          visualConfig['showTaskTimelineInsideMilestones'] ??
          data['showTaskTimelineBars'] ??
          visualConfig['showTaskTimelineBars'] ??
          visualConfig['timelineBars'],
      fallback: showTaskProgress && !separateTaskTimeline,
    );
    final showMilestones = _flag(data['showMilestones'] ?? visualConfig['showMilestones'], fallback: true);
    final showTaskTimelineButton = _flag(
      data['showTaskTimelineButton'] ?? visualConfig['showTaskTimelineButton'],
      fallback: separateTaskTimeline,
    );
    final taskTimelineAction = _textOf(visualConfig, 'taskTimelineAction', _textOf(data, 'taskTimelineAction', 'openTaskTimeline'));
    final taskTimelineButtonLabel = _textOf(visualConfig, 'taskTimelineButtonLabel', _textOf(data, 'taskTimelineButtonLabel', 'View Task Timeline'));
    final taskTimelineButtonSubtitle = _textOf(visualConfig, 'taskTimelineButtonSubtitle', _textOf(data, 'taskTimelineButtonSubtitle', 'Open task progress chart and due-date bars.'));
    final children = <Widget>[
      if (!embedded)
        _ScreenTitle(
          title: _textOf(data, 'title', 'Timeline'),
          subtitle: _textOf(data, 'subtitle', 'Tap a project milestone to expand tasks and progress'),
        ),
      if (showTaskProgress) _TaskProgressPanelJson(state: state, data: data, theme: theme),
      if (showTimelineBars) _TaskTimelineBarsJson(state: state, data: data, theme: theme),
      if (showTaskTimelineButton)
        _Surface(
          theme: theme,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: theme.accent.withOpacity(.12), borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.view_timeline_rounded, color: theme.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(taskTimelineButtonLabel, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(taskTimelineButtonSubtitle, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onExternalAction?.call(taskTimelineAction);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: theme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Open'),
              ),
            ],
          ),
        ),
      if (projects.isEmpty && tasks.isEmpty)
        _referenceModuleCard(theme: theme, title: 'No timeline data', subtitle: 'Visible projects and assigned tasks will appear here.', icon: Icons.timeline_rounded)
      else if (showMilestones)
        _Surface(
          theme: theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Milestones', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16))),
                  _InfoTag(label: '${projects.length} project(s)', icon: Icons.folder_rounded, theme: theme),
                ],
              ),
              const SizedBox(height: 6),
              Text('Completed tasks show a tick. Open tasks show an empty circle.', style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 14),
              if (projects.isEmpty)
                ...tasks.take(10).toList().asMap().entries.map((entry) => _TaskTimelineRow(
                      theme: theme,
                      task: entry.value,
                      projectName: _projectName(state, entry.value.projectId),
                      isLast: entry.key == tasks.take(10).length - 1,
                    ))
              else
                ...projects.take(12).toList().asMap().entries.map((entry) {
                  final project = entry.value;
                  final projectTasks = state.visibleTasks.where((task) => task.projectId == project.projectId).toList()
                    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
                  return _ExpandableProjectTimelineCard(
                    project: project,
                    tasks: projectTasks,
                    theme: theme,
                    initiallyExpanded: defaultProject?.projectId == project.projectId,
                    isLast: entry.key == projects.take(12).length - 1,
                  );
                }),
            ],
          ),
        ),
    ];
    return embedded
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)
        : ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(theme.padding), children: children);
  }
}


class _TaskTimelineDataJsonScreen extends StatelessWidget {
  const _TaskTimelineDataJsonScreen({required this.state, required this.data, required this.theme, this.embedded = false});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final visualConfig = <String, dynamic>{
      ...(_asMap(data['timelineVisualConfig']) ?? const <String, dynamic>{}),
      ...(_asMap(data['deliveryTimelineConfig']) ?? const <String, dynamic>{}),
      ...data,
    };
    final styleKey = _textOf(
      visualConfig,
      'taskTimelineStyle',
      _textOf(visualConfig, 'visualStyle', _textOf(visualConfig, 'variant', '')),
    ).replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
    final useDeliveryUIKit = _flag(
      visualConfig['deliveryUIKitTimeline'] ?? visualConfig['useDeliveryUIKitTimeline'] ?? visualConfig['referenceDeliveryTimeline'],
      fallback: styleKey.contains('delivery') || styleKey.contains('uikit') || styleKey.contains('referenceapp'),
    );
    if (useDeliveryUIKit) {
      return _DeliveryUIKitTaskTimelineScreen(state: state, data: visualConfig, theme: theme, embedded: embedded);
    }

    final progressData = <String, dynamic>{
      ...visualConfig,
      'progressTitle': _textOf(visualConfig, 'progressTitle', 'Task Progress'),
      'progressNote': _textOf(visualConfig, 'progressNote', 'Live task data'),
    };
    final scheduleData = <String, dynamic>{
      ...visualConfig,
      'timelineBarsTitle': _textOf(visualConfig, 'timelineBarsTitle', 'Task Timeline'),
      'timelineBarsSubtitle': _textOf(visualConfig, 'timelineBarsSubtitle', 'Plan, review and delivery windows'),
      'showReferenceFallbackWhenEmpty': false,
      'referenceFallbackWhenEmpty': false,
    };
    final showHeader = _flag(visualConfig['showScreenHeader'], fallback: !embedded);
    final showDateStrip = _flag(visualConfig['showDateStrip'] ?? visualConfig['showTaskTimelineDateStrip'], fallback: true);
    final showProgress = _flag(visualConfig['showTaskProgressCard'] ?? visualConfig['showProgress'], fallback: true);
    final showSchedule = _flag(visualConfig['showTaskTimelineBars'] ?? visualConfig['showTimelineBars'], fallback: true);
    final showAgenda = _flag(visualConfig['showAgendaList'] ?? visualConfig['showTaskCards'], fallback: true);

    final children = <Widget>[
      if (showHeader)
        _ScreenTitle(
          title: _textOf(visualConfig, 'title', 'Task Timeline'),
          subtitle: _textOf(visualConfig, 'subtitle', 'Task progress and schedule timeline'),
        ),
      if (showDateStrip) _TaskTimelineDateStrip(theme: theme, data: visualConfig),
      if (showProgress) _TaskProgressPanelJson(state: state, data: progressData, theme: theme),
      if (showSchedule) _TaskTimelineScheduleCard(state: state, data: scheduleData, theme: theme),
      if (showAgenda) _TaskTimelineAgendaCard(state: state, data: scheduleData, theme: theme),
    ];

    return embedded
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)
        : ListView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.fromLTRB(theme.padding, theme.padding, theme.padding, theme.padding + 96),
            children: children,
          );
  }
}

class _TaskTimelineDateStrip extends StatelessWidget {
  const _TaskTimelineDateStrip({required this.theme, required this.data});

  final _UiTheme theme;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 2));
    final selectedIndex = _num(data['selectedDateIndex'], 2).round().clamp(0, 5).toInt();
    final weekdays = const <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return SizedBox(
      height: 74,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final date = start.add(Duration(days: index));
          final active = index == selectedIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? theme.accent : theme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: active ? theme.accent : theme.border),
              boxShadow: active ? [BoxShadow(color: theme.accent.withOpacity(.18), blurRadius: 18, offset: const Offset(0, 8))] : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${date.day}', style: TextStyle(color: active ? Colors.white : theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 3),
                Text(weekdays[date.weekday - 1], style: TextStyle(color: active ? Colors.white.withOpacity(.88) : theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 10.5)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TaskTimelineScheduleCard extends StatelessWidget {
  const _TaskTimelineScheduleCard({required this.state, required this.data, required this.theme});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final tasks = _timelineTasksForState(state);
    final limit = _num(data['timelineTaskLimit'], 4).round().clamp(2, 6).toInt();
    final liveItems = tasks.take(limit).map((task) {
      final ratio = _taskProgressForStatus(task.status).clamp(.22, 1.0).toDouble();
      return _TaskTimelineBarItem(
        dayLabel: '${task.dueDate.day}',
        timeLabel: _taskTimelineTimeLabel(task.dueDate),
        title: task.title,
        subtitle: _projectName(state, task.projectId),
        statusLabel: task.status.label,
        ratio: ratio,
        color: task.status == TaskStatus.completed ? const Color(0xFF16A34A) : task.priority.color,
        live: true,
        icon: _iconForTaskStatus(task.status),
      );
    }).toList();
    final showReferenceFallback = _flag(
      data['showReferenceFallbackWhenEmpty'] ?? data['referenceFallbackWhenEmpty'] ?? data['mockPreviewWhenEmpty'],
      fallback: true,
    );
    final items = liveItems.isNotEmpty ? liveItems : (showReferenceFallback ? _referenceTaskTimelineItems(theme, data) : const <_TaskTimelineBarItem>[]);
    final title = _textOf(data, 'timelineBarsTitle', 'Task Timeline');
    final subtitle = liveItems.isEmpty && showReferenceFallback
        ? _textOf(data, 'emptyTimelineSubtitle', 'Reference schedule preview until live tasks arrive')
        : _textOf(data, 'timelineBarsSubtitle', 'Plan, review and delivery windows');

    return _Surface(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: theme.accent.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.view_timeline_rounded, color: theme.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16))),
              Icon(Icons.more_horiz_rounded, color: theme.textSecondary),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 18),
          SizedBox(
            height: 188,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final chartLeft = 30.0;
                final chartRight = width - 8.0;
                final chartWidth = (chartRight - chartLeft).clamp(180.0, width).toDouble();
                final todayX = chartLeft + chartWidth * .72;
                final rows = items.take(4).toList();
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: chartLeft,
                      right: 0,
                      bottom: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) {
                          final day = 12 + index;
                          return Text('$day', style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 10.5));
                        }),
                      ),
                    ),
                    Positioned(
                      left: todayX,
                      top: 20,
                      bottom: 18,
                      child: Column(
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFFEF553D), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
                          Expanded(child: Container(width: 1.5, color: const Color(0xFFEF553D).withOpacity(.56))),
                        ],
                      ),
                    ),
                    ...rows.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final top = 22.0 + (index * 36.0);
                      final start = (.05 + index * .14).clamp(.02, .66).toDouble();
                      final itemWidth = (chartWidth * (.34 + item.ratio * .25)).clamp(86.0, chartWidth * .72).toDouble();
                      final left = chartLeft + (chartWidth * start);
                      final label = item.title.length > 16 ? item.title.substring(0, 16) : item.title;
                      return Positioned(
                        left: left,
                        top: top,
                        width: itemWidth,
                        height: 26,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 380 + (index * 70)),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) => Transform.scale(
                            scaleX: value,
                            alignment: Alignment.centerLeft,
                            child: Opacity(opacity: value, child: child),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 13),
                            decoration: BoxDecoration(
                              color: item.color,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [BoxShadow(color: item.color.withOpacity(.20), blurRadius: 16, offset: const Offset(0, 8))],
                            ),
                            alignment: Alignment.centerLeft,
                            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11.5)),
                          ),
                        ),
                      );
                    }),
                    if (rows.isEmpty)
                      Positioned.fill(
                        child: _referenceModuleCard(theme: theme, title: 'No task timeline', subtitle: 'Assigned tasks will appear here.', icon: Icons.view_timeline_rounded),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTimelineAgendaCard extends StatelessWidget {
  const _TaskTimelineAgendaCard({required this.state, required this.data, required this.theme});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final tasks = _timelineTasksForState(state);
    final limit = _num(data['agendaLimit'], 4).round().clamp(2, 8).toInt();
    final live = tasks.take(limit).toList();
    final fallback = live.isEmpty ? _referenceTaskTimelineItems(theme, data) : const <_TaskTimelineBarItem>[];
    return _Surface(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(_textOf(data, 'agendaTitle', 'Today tasks'), style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16))),
              _InfoTag(label: live.isEmpty ? 'Preview' : '${live.length} live', icon: live.isEmpty ? Icons.auto_awesome_rounded : Icons.task_alt_rounded, color: theme.accent, theme: theme),
            ],
          ),
          const SizedBox(height: 16),
          if (live.isNotEmpty)
            ...live.asMap().entries.map((entry) => _TaskTimelineRow(
                  theme: theme,
                  task: entry.value,
                  projectName: _projectName(state, entry.value.projectId),
                  isLast: entry.key == live.length - 1,
                ))
          else
            ...fallback.asMap().entries.map((entry) => _ReferenceAgendaRow(theme: theme, item: entry.value, isLast: entry.key == fallback.length - 1)),
        ],
      ),
    );
  }
}

class _ReferenceAgendaRow extends StatelessWidget {
  const _ReferenceAgendaRow({required this.theme, required this.item, required this.isLast});

  final _UiTheme theme;
  final _TaskTimelineBarItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(width: 20, height: 20, decoration: BoxDecoration(color: theme.surface, shape: BoxShape.circle, border: Border.all(color: item.color, width: 2))),
              if (!isLast) Expanded(child: Container(width: 1.5, margin: const EdgeInsets.symmetric(vertical: 5), color: item.color.withOpacity(.32))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 13),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: theme.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 18, offset: const Offset(0, 8))]),
              child: Row(
                children: [
                  Container(width: 34, height: 34, decoration: BoxDecoration(color: item.color.withOpacity(.12), borderRadius: BorderRadius.circular(13)), child: Icon(item.icon, color: item.color, size: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 13.5)),
                      const SizedBox(height: 3),
                      Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 11.5)),
                    ]),
                  ),
                  Text(item.timeLabel, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _taskTimelineTimeLabel(DateTime date) {
  final hour = date.hour == 0 ? 9 : date.hour;
  final minute = date.minute;
  final displayHour = hour > 12 ? hour - 12 : hour;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final minText = minute == 0 ? '00' : minute.toString().padLeft(2, '0');
  return '$displayHour:$minText $suffix';
}

IconData _iconForTaskStatus(TaskStatus status) {
  return switch (status) {
    TaskStatus.completed => Icons.check_circle_rounded,
    TaskStatus.inProgress => Icons.data_object_rounded,
    TaskStatus.review || TaskStatus.testing => Icons.rate_review_rounded,
    TaskStatus.backlog || TaskStatus.todo => Icons.flag_rounded,
  };
}


class _ExpandableProjectTimelineCard extends StatefulWidget {
  const _ExpandableProjectTimelineCard({required this.project, required this.tasks, required this.theme, required this.initiallyExpanded, required this.isLast});

  final Project project;
  final List<ProjectTask> tasks;
  final _UiTheme theme;
  final bool initiallyExpanded;
  final bool isLast;

  @override
  State<_ExpandableProjectTimelineCard> createState() => _ExpandableProjectTimelineCardState();
}

class _ExpandableProjectTimelineCardState extends State<_ExpandableProjectTimelineCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant _ExpandableProjectTimelineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.projectId != widget.project.projectId) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = widget.tasks.where((task) => task.status == TaskStatus.completed).length;
    final total = widget.tasks.isEmpty ? widget.project.totalTasks : widget.tasks.length;
    final progress = total <= 0 ? widget.project.progress : ((completed / total) * 100).round().clamp(0, 100).toInt();
    final open = (total - completed).clamp(0, 999).toInt();
    final accent = widget.project.isDelayed ? const Color(0xFFDC2626) : widget.theme.accent;
    final completionRatio = (progress / 100).clamp(0.0, 1.0).toDouble();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _expanded ? accent : accent.withOpacity(.10),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withOpacity(.22)),
                  boxShadow: _expanded ? [BoxShadow(color: accent.withOpacity(.18), blurRadius: 18, offset: const Offset(0, 8))] : null,
                ),
                child: Icon(_expanded ? Icons.folder_open_rounded : Icons.folder_rounded, color: _expanded ? Colors.white : accent, size: 18),
              ),
              if (!widget.isLast) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 5), color: widget.theme.border.withOpacity(.86))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Container(
                margin: EdgeInsets.only(bottom: widget.isLast ? 0 : 14),
                decoration: BoxDecoration(
                  color: widget.theme.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: _expanded ? accent.withOpacity(.26) : widget.theme.border),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(_expanded ? .075 : .045), blurRadius: _expanded ? 28 : 18, offset: Offset(0, _expanded ? 14 : 8))],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(26),
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.project.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15.5, height: 1.12),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Due ${DateText.compact(widget.project.dueDate)} • ${widget.project.status.label}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              AnimatedRotation(
                                turns: _expanded ? .5 : 0,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(color: accent.withOpacity(.09), shape: BoxShape.circle),
                                  child: Icon(Icons.keyboard_arrow_down_rounded, color: accent, size: 22),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: completionRatio,
                                    minHeight: 8,
                                    color: accent,
                                    backgroundColor: accent.withOpacity(.10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text('$progress%', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              _InfoTag(label: '$completed/$total done', icon: Icons.check_circle_rounded, color: const Color(0xFF059669), theme: widget.theme),
                              _InfoTag(label: '$open open', icon: Icons.radio_button_unchecked_rounded, color: widget.theme.textSecondary, theme: widget.theme),
                              if (widget.project.isDelayed) _InfoTag(label: 'Delayed', icon: Icons.warning_amber_rounded, color: const Color(0xFFDC2626), theme: widget.theme),
                            ],
                          ),
                          AnimatedCrossFade(
                            firstChild: const SizedBox.shrink(),
                            secondChild: Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: _ProjectInlineDetails(project: widget.project, tasks: widget.tasks, progress: completionRatio, delayed: widget.project.isDelayed, theme: widget.theme),
                            ),
                            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 260),
                            sizeCurve: Curves.easeOutCubic,
                            firstCurve: Curves.easeOutCubic,
                            secondCurve: Curves.easeOutCubic,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRenderItem {
  const _TimelineRenderItem(this.title, this.subtitle, this.icon, this.color);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _TimelineRenderRow extends StatelessWidget {
  const _TimelineRenderRow({required this.theme, required this.item, required this.isLast});
  final _UiTheme theme;
  final _TimelineRenderItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: item.color.withOpacity(.13), shape: BoxShape.circle),
                child: Icon(item.icon, color: item.color, size: 18),
              ),
              if (!isLast) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: theme.border)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.background.withOpacity(.45),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTimelineRow extends StatelessWidget {
  const _TaskTimelineRow({required this.theme, required this.task, required this.projectName, required this.isLast});

  final _UiTheme theme;
  final ProjectTask task;
  final String projectName;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final completed = task.status == TaskStatus.completed;
    final markerColor = completed ? const Color(0xFF059669) : theme.accent;
    final statusColor = completed ? const Color(0xFF059669) : task.status.color;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: completed ? markerColor : theme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: completed ? markerColor : markerColor.withOpacity(.38), width: completed ? 0 : 2),
                  boxShadow: completed ? [BoxShadow(color: markerColor.withOpacity(.16), blurRadius: 14, offset: const Offset(0, 6))] : null,
                ),
                child: completed ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
              ),
              if (!isLast) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 5), color: theme.border.withOpacity(.86))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
              decoration: BoxDecoration(
                color: completed ? const Color(0xFFFAFFFC) : theme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: completed ? markerColor.withOpacity(.16) : theme.border),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 13.5, height: 1.20),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: statusColor.withOpacity(.20)),
                        ),
                        child: Text(
                          task.status.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _MiniTimelineChip(theme: theme, icon: Icons.calendar_month_rounded, label: 'Due ${DateText.compact(task.dueDate)}'),
                      _MiniTimelineChip(theme: theme, icon: Icons.flag_rounded, label: task.priority.label, color: task.priority.color),
                      if (projectName.trim().isNotEmpty) _MiniTimelineChip(theme: theme, icon: Icons.folder_rounded, label: projectName),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTimelineChip extends StatelessWidget {
  const _MiniTimelineChip({required this.theme, required this.icon, required this.label, this.color});

  final _UiTheme theme;
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? theme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: chipColor.withOpacity(.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: chipColor),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: chipColor, fontWeight: FontWeight.w900, fontSize: 10.5)),
          ),
        ],
      ),
    );
  }
}



class _DeliveryUIKitTaskTimelineScreen extends StatelessWidget {
  const _DeliveryUIKitTaskTimelineScreen({required this.state, required this.data, required this.theme, required this.embedded});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final showHeader = _flag(data['showScreenHeader'], fallback: !embedded);
    final showAgenda = _flag(data['showAgendaList'] ?? data['showTaskCards'], fallback: false);
    final appTitle = _textOf(data, 'appTitle', _textOf(data, 'title', 'Task Timeline'));
    final children = <Widget>[
      if (showHeader) _DeliveryTimelineTopHeader(theme: theme, title: appTitle),
      _DeliveryTaskProgressCard(state: state, data: data, theme: theme),
      _DeliveryTaskTimelineCard(state: state, data: data, theme: theme),
      if (showAgenda) _TaskTimelineAgendaCard(state: state, data: data, theme: theme),
    ];
    return embedded
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)
        : Container(
            color: const Color(0xFFF1F1EF),
            child: ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: EdgeInsets.fromLTRB(20, 18, 20, theme.padding + 96),
              children: children,
            ),
          );
  }
}

class _DeliveryTimelineTopHeader extends StatelessWidget {
  const _DeliveryTimelineTopHeader({required this.theme, required this.title});

  final _UiTheme theme;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 18),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: const BoxDecoration(color: Color(0xFFFFFFFF), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: Color(0xFF111111)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w700, fontSize: 17.2, letterSpacing: -.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryCardSurface extends StatelessWidget {
  const _DeliveryCardSurface({required this.child, this.marginBottom = 12});

  final Widget child;
  final double marginBottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: marginBottom),
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.028), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }
}

class _DeliveryTaskProgressCard extends StatelessWidget {
  const _DeliveryTaskProgressCard({required this.state, required this.data, required this.theme});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final tasks = _timelineTasksForState(state);
    final totalTasks = tasks.length;
    final progress = totalTasks == 0
        ? 0
        : ((tasks.fold<double>(0, (sum, task) => sum + _taskProgressForStatus(task.status)) / totalTasks) * 100).round().clamp(0, 100).toInt();
    final selectedIndex = _deliveryTodayIndexForTasks(tasks);
    final points = _deliveryProgressPoints(tasks: tasks, progress: progress, axisStart: 0, selectedIndex: selectedIndex, theme: theme);
    final note = totalTasks == 0 ? 'No live task data found' : 'Loaded $totalTasks live task${totalTasks == 1 ? '' : 's'}';

    return _DeliveryCardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DeliverySmallIcon(theme: theme, icon: Icons.fact_check_outlined),
              const SizedBox(width: 10),
              Expanded(child: Text(_textOf(data, 'progressTitle', 'Task Progress'), style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16))),
              _DeliveryMoreButton(theme: theme),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: points.isEmpty
                ? _DeliveryTimelineEmpty(theme: theme, message: 'No visible/scoped tasks available for progress chart.')
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: points.asMap().entries.map((entry) {
                      final point = entry.value;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: entry.key == selectedIndex ? 3 : 4),
                          child: _DeliveryProgressColumn(point: point, theme: theme),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 12),
          _DeliveryProgressToast(theme: theme, note: note, trailing: null),
        ],
      ),
    );
  }
}

class _DeliveryTaskTimelineCard extends StatelessWidget {
  const _DeliveryTaskTimelineCard({required this.state, required this.data, required this.theme});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final tasks = _timelineTasksForState(state);
    final barLimit = _num(data['timelineBarLimit'] ?? data['timelineTaskLimit'], 6).round().clamp(1, 8).toInt();
    final liveTasks = tasks.take(barLimit).toList();
    final hasLiveTimelineData = liveTasks.isNotEmpty;
    final axisBaseDate = _deliveryTimelineAxisStartDate(tasks: liveTasks, projects: const <Project>[], todayIndex: _deliveryTodayIndexForTasks(liveTasks));
    final todayIndex = _deliveryTimelineTodayIndex(axisBaseDate, fallback: _deliveryTodayIndexForTasks(liveTasks));
    final bars = _deliveryTimelineBars(tasks: liveTasks, projects: const <Project>[], theme: theme, axisBaseDate: axisBaseDate);
    final title = _textOf(data, 'timelineBarsTitle', 'Task Timeline');

    return _DeliveryCardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DeliverySmallIcon(theme: theme, icon: Icons.calendar_today_outlined),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16))),
              _DeliveryMoreButton(theme: theme),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 155,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final chartLeft = 20.0;
                final chartRight = 7.0;
                final chartWidth = (width - chartLeft - chartRight).clamp(160.0, width).toDouble();
                final todayX = chartLeft + chartWidth * (todayIndex / 5.0).clamp(.0, 1.0);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: chartLeft,
                      right: chartRight,
                      bottom: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) {
                          final liveDay = axisBaseDate.add(Duration(days: index)).day;
                          return Text('$liveDay', style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 10.5));
                        }),
                      ),
                    ),
                    Positioned(
                      left: todayX,
                      top: 0,
                      bottom: 22,
                      child: Column(
                        children: [
                          Container(width: 11, height: 11, decoration: BoxDecoration(color: const Color(0xFFEF553D), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))),
                          Expanded(child: Container(width: 1.5, color: const Color(0xFFEF553D).withOpacity(.62))),
                        ],
                      ),
                    ),
                    Positioned(
                      left: chartLeft,
                      right: chartRight,
                      top: 31,
                      height: 92,
                      child: CustomPaint(painter: _DiagonalHatchPainter(color: theme.border.withOpacity(.28), strokeWidth: 1.2, gap: 8)),
                    ),
                    if (bars.isEmpty)
                      Positioned.fill(
                        child: _DeliveryTimelineEmpty(theme: theme, message: 'No visible/scoped tasks available for timeline bars.'),
                      ),
                    ...bars.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final top = 25.0 + (index * 34.0);
                      final left = chartLeft + chartWidth * item.start;
                      final itemWidth = (chartWidth * item.span).clamp(84.0, chartWidth * .72).toDouble();
                      return Positioned(
                        left: left,
                        top: top,
                        width: itemWidth,
                        height: 26,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 420 + (index * 85)),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) => Transform.scale(
                            scaleX: value,
                            alignment: Alignment.centerLeft,
                            child: Opacity(opacity: value, child: child),
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: item.color,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [BoxShadow(color: item.color.withOpacity(.18), blurRadius: 16, offset: const Offset(0, 8))],
                            ),
                            child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11.5)),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


class _DeliveryTimelineEmpty extends StatelessWidget {
  const _DeliveryTimelineEmpty({required this.theme, required this.message});

  final _UiTheme theme;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.surfaceAlt.withOpacity(.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.border),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
    );
  }
}

class _DeliveryProgressColumn extends StatelessWidget {
  const _DeliveryProgressColumn({required this.point, required this.theme});

  final _DeliveryProgressDayPoint point;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final barHeight = (32 + point.ratio * 80).clamp(36.0, 112.0).toDouble();
    final badgeTop = (104 - barHeight).clamp(8.0, 74.0).toDouble();
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 124,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              if (!point.selected)
                Positioned(
                  bottom: 0,
                  width: 38,
                  height: 104,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: CustomPaint(painter: _DiagonalHatchPainter(color: theme.border.withOpacity(.52), strokeWidth: 1.4, gap: 7)),
                  ),
                ),
              Positioned(
                bottom: 0,
                width: point.selected ? 35 : 24,
                height: point.selected ? 112 : barHeight,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Transform.scale(
                    scaleY: value,
                    alignment: Alignment.bottomCenter,
                    child: Opacity(opacity: value, child: child),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: point.selected ? const Color(0xFF0B0F12) : point.color.withOpacity(.18),
                      borderRadius: BorderRadius.circular(999),
                      border: point.selected ? null : Border.all(color: point.color.withOpacity(.24)),
                    ),
                    child: point.selected
                        ? Align(
                            alignment: Alignment.topCenter,
                            child: Transform.translate(
                              offset: const Offset(0, -4),
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(color: const Color(0xFFEF553D), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              Positioned(
                top: point.selected ? 0 : badgeTop,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: point.selected ? 10 : 7, vertical: point.selected ? 7 : 4),
                  decoration: BoxDecoration(
                    color: point.selected ? const Color(0xFF0B0F12) : point.color,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BoxShadow(color: (point.selected ? Colors.black : point.color).withOpacity(.14), blurRadius: 14, offset: const Offset(0, 8))],
                  ),
                  child: Text(point.percentText, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: point.selected ? 11 : 9.5)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(point.dayLabel, style: TextStyle(color: point.selected ? theme.textPrimary : theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 11)),
      ],
    );
  }
}

class _DeliveryProgressToast extends StatelessWidget {
  const _DeliveryProgressToast({required this.theme, required this.note, required this.trailing});

  final _UiTheme theme;
  final String note;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.14), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          const Text('👍', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 9),
          Expanded(child: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing!, style: TextStyle(color: Colors.white.withOpacity(.72), fontWeight: FontWeight.w800, fontSize: 10)),
          ],
          const SizedBox(width: 8),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: Colors.white.withOpacity(.10), shape: BoxShape.circle),
            child: const Icon(Icons.close_rounded, size: 15, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _DeliverySmallIcon extends StatelessWidget {
  const _DeliverySmallIcon({required this.theme, required this.icon});

  final _UiTheme theme;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(color: theme.background.withOpacity(.92), borderRadius: BorderRadius.circular(10), border: Border.all(color: theme.border.withOpacity(.70))),
      child: Icon(icon, color: theme.textPrimary, size: 14),
    );
  }
}

class _DeliveryMoreButton extends StatelessWidget {
  const _DeliveryMoreButton({required this.theme});

  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 32,
      decoration: BoxDecoration(color: theme.background.withOpacity(.82), borderRadius: BorderRadius.circular(16)),
      child: Icon(Icons.more_horiz_rounded, color: theme.textPrimary.withOpacity(.72), size: 20),
    );
  }
}


List<ProjectTask> _timelineTasksForState(WorkspaceState state) {
  final visible = [...state.visibleTasks]..sort(_sortProjectTaskByDueDate);
  if (visible.isNotEmpty) return visible;

  final member = state.currentMember;
  final visibleProjectIds = state.visibleProjects.map((project) => project.projectId).where((id) => id.trim().isNotEmpty).toSet();
  final memberProjectIds = member.projectIds.where((id) => id.trim().isNotEmpty).toSet();
  final memberTeamIds = member.teamIds.where((id) => id.trim().isNotEmpty).toSet();

  final scoped = state.tasks.where((task) {
    if (task.assignedToIds.contains(member.uid)) return true;
    if (visibleProjectIds.contains(task.projectId)) return true;
    if (memberProjectIds.contains(task.projectId)) return true;
    if (memberTeamIds.contains(task.teamId)) return true;
    if (member.role.isDeliveryManager) return true;
    return false;
  }).toList()..sort(_sortProjectTaskByDueDate);
  return scoped;
}

List<Project> _timelineProjectsForState(WorkspaceState state, {List<ProjectTask> tasks = const <ProjectTask>[]}) {
  final visible = [...state.visibleProjects]..sort(_sortProjectByDueDate);
  if (visible.isNotEmpty) return visible;

  final member = state.currentMember;
  final taskProjectIds = tasks.map((task) => task.projectId).where((id) => id.trim().isNotEmpty).toSet();
  final memberProjectIds = member.projectIds.where((id) => id.trim().isNotEmpty).toSet();
  final memberTeamIds = member.teamIds.where((id) => id.trim().isNotEmpty).toSet();

  return state.projects.where((project) {
    if (project.isArchived) return false;
    if (taskProjectIds.contains(project.projectId)) return true;
    if (memberProjectIds.contains(project.projectId)) return true;
    if (project.teamIds.any(memberTeamIds.contains)) return true;
    if (project.managerIds.contains(member.uid)) return true;
    if (member.role.isDeliveryManager) return true;
    return false;
  }).toList()..sort(_sortProjectByDueDate);
}

int _sortProjectTaskByDueDate(ProjectTask a, ProjectTask b) {
  final due = a.dueDate.compareTo(b.dueDate);
  if (due != 0) return due;
  return a.title.compareTo(b.title);
}

int _sortProjectByDueDate(Project a, Project b) {
  final due = a.dueDate.compareTo(b.dueDate);
  if (due != 0) return due;
  return a.name.compareTo(b.name);
}

class _DeliveryProgressDayPoint {
  const _DeliveryProgressDayPoint({required this.dayLabel, required this.percentText, required this.ratio, required this.color, required this.selected});

  final String dayLabel;
  final String percentText;
  final double ratio;
  final Color color;
  final bool selected;
}

class _DeliveryTimelineBar {
  const _DeliveryTimelineBar({required this.title, required this.start, required this.span, required this.color});

  final String title;
  final double start;
  final double span;
  final Color color;
}

class _DiagonalHatchPainter extends CustomPainter {
  const _DiagonalHatchPainter({required this.color, required this.strokeWidth, required this.gap});

  final Color color;
  final double strokeWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (double x = -size.height; x < size.width + size.height; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalHatchPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth || oldDelegate.gap != gap;
  }
}


List<_DeliveryProgressDayPoint> _deliveryProgressPoints({required List<ProjectTask> tasks, required int progress, required int axisStart, required int selectedIndex, required _UiTheme theme}) {
  if (tasks.isEmpty) return const <_DeliveryProgressDayPoint>[];
  final colors = <Color>[
    const Color(0xFF20B486),
    const Color(0xFF111111),
    const Color(0xFFFF5A3D),
    const Color(0xFF20B486),
    const Color(0xFFFF5A3D),
    const Color(0xFF20B486),
  ];
  final axisBaseDate = _deliveryTimelineAxisStartDate(tasks: tasks, projects: const <Project>[], todayIndex: selectedIndex);
  return List.generate(6, (index) {
    final date = axisBaseDate.add(Duration(days: index));
    final dayTasks = tasks.where((task) => _sameDate(task.dueDate, date)).toList();
    final selected = index == selectedIndex;
    final dayProgress = dayTasks.isEmpty
        ? 0
        : ((dayTasks.fold<double>(0, (sum, task) => sum + _taskProgressForStatus(task.status)) / dayTasks.length) * 100).round().clamp(0, 100).toInt();
    final ratio = math.max(.05, (selected ? progress : dayProgress) / 100.0).clamp(.05, 1.0).toDouble();
    return _DeliveryProgressDayPoint(
      dayLabel: '${date.day}',
      percentText: '${selected ? progress : dayProgress}%',
      ratio: ratio,
      color: dayTasks.any((task) => task.isOverdue) ? const Color(0xFFFF5A3D) : colors[index],
      selected: selected,
    );
  });
}

List<_DeliveryTimelineBar> _deliveryTimelineBars({required List<ProjectTask> tasks, required List<Project> projects, required _UiTheme theme, DateTime? axisBaseDate}) {
  final palette = <Color>[
    const Color(0xFFFF5A3D),
    const Color(0xFF20B486),
    const Color(0xFF6B7BFA),
    const Color(0xFFB98226),
    const Color(0xFF4B73A6),
    const Color(0xFF7455A3),
  ];
  if (tasks.isEmpty) return const <_DeliveryTimelineBar>[];
  return tasks.asMap().entries.map((entry) {
    final index = entry.key;
    final task = entry.value;
    final startDate = _deliveryTaskStartDate(task);
    final start = _deliveryTimelineStartRatio(startDate, axisBaseDate, index).clamp(.0, .88).toDouble();
    final end = _deliveryTimelineStartRatio(task.dueDate, axisBaseDate, index).clamp(start + .08, 1.0).toDouble();
    final span = (end - start).clamp(.18, .78).toDouble();
    final title = task.title.trim().isEmpty ? 'Untitled task' : task.title.trim();
    final color = task.status == TaskStatus.completed
        ? const Color(0xFF20B486)
        : task.isOverdue
            ? const Color(0xFFFF5A3D)
            : palette[index % palette.length];
    return _DeliveryTimelineBar(title: title.length > 22 ? '${title.substring(0, 21)}…' : title, start: start, span: span, color: color);
  }).toList();
}

DateTime _deliveryTaskStartDate(ProjectTask task) {
  final explicit = task.createdAt ?? task.updatedAt;
  if (explicit != null && explicit.isBefore(task.dueDate)) return explicit;
  final estimatedHours = task.estimatedHours.toDouble();
  final fallbackDays = estimatedHours <= 0 ? 1 : (estimatedHours / 8).ceil().clamp(1, 10).toInt();
  return task.dueDate.subtract(Duration(days: fallbackDays));
}

DateTime _deliveryDateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

DateTime _deliveryTimelineAxisStartDate({required List<ProjectTask> tasks, required List<Project> projects, required int todayIndex}) {
  final dates = <DateTime>[
    ...tasks.map((task) => _deliveryDateOnly(task.dueDate)),
    ...tasks.map((task) => _deliveryDateOnly(_deliveryTaskStartDate(task))),
    ...projects.map((project) => _deliveryDateOnly(project.dueDate)),
  ];
  final today = _deliveryDateOnly(DateTime.now());
  if (dates.isEmpty) return today.subtract(Duration(days: todayIndex));
  dates.add(today);
  dates.sort();
  var earliest = dates.first;
  var latest = dates.last;
  if (latest.difference(earliest).inDays < 5) {
    final missing = 5 - latest.difference(earliest).inDays;
    earliest = earliest.subtract(Duration(days: (missing / 2).floor()));
    latest = latest.add(Duration(days: (missing / 2).ceil()));
  }
  return earliest;
}

int _deliveryTimelineTodayIndex(DateTime axisBaseDate, {required int fallback}) {
  final diff = _deliveryDateOnly(DateTime.now()).difference(_deliveryDateOnly(axisBaseDate)).inDays;
  if (diff < 0 || diff > 5) return fallback.clamp(0, 5).toInt();
  return diff.clamp(0, 5).toInt();
}

int _deliveryTodayIndexForTasks(List<ProjectTask> tasks) {
  if (tasks.isEmpty) return 4;
  final axis = _deliveryTimelineAxisStartDate(tasks: tasks, projects: const <Project>[], todayIndex: 4);
  return _deliveryTimelineTodayIndex(axis, fallback: 4);
}

double _deliveryTimelineStartRatio(DateTime dueDate, DateTime? axisBaseDate, int index) {
  if (axisBaseDate == null) return (.02 + index * .18).clamp(.0, .88).toDouble();
  final diff = _deliveryDateOnly(dueDate).difference(_deliveryDateOnly(axisBaseDate)).inDays;
  return (diff / 5.0).clamp(.0, 1.0).toDouble();
}

class _TaskProgressPanelJson extends StatelessWidget {
  const _TaskProgressPanelJson({required this.state, required this.data, required this.theme});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final tasks = _timelineTasksForState(state);
    final projects = _timelineProjectsForState(state, tasks: tasks);
    final totalTasks = tasks.length;
    final completedTasks = tasks.where((task) => task.status == TaskStatus.completed).length;
    final averageTaskProgress = totalTasks == 0
        ? (projects.isEmpty ? 0 : (projects.fold<int>(0, (sum, project) => sum + project.progress) / projects.length).round())
        : ((tasks.fold<double>(0, (sum, task) => sum + _taskProgressForStatus(task.status)) / totalTasks) * 100).round();
    final progress = averageTaskProgress.clamp(0, 100).toInt();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 5));
    final points = List.generate(6, (index) {
      final day = start.add(Duration(days: index));
      final dayTasks = tasks.where((task) => _sameDate(task.dueDate, day)).toList();
      final ratio = dayTasks.isEmpty
          ? (0.18 + (index * 0.08)).clamp(0.18, 0.72).toDouble()
          : (dayTasks.fold<double>(0, (sum, task) => sum + _taskProgressForStatus(task.status)) / dayTasks.length).clamp(0.18, 1.0).toDouble();
      return _ProgressChartPoint(day: day, ratio: ratio, taskCount: dayTasks.length);
    });
    final activeIndex = points.indexWhere((point) => _sameDate(point.day, now));
    final selectedIndex = activeIndex < 0 ? points.length - 1 : activeIndex;
    final title = _textOf(data, 'progressTitle', 'Task Progress');
    final subtitle = totalTasks == 0 ? 'Live progress appears when tasks are assigned.' : '$completedTasks/$totalTasks tasks completed';
    final note = _textOf(data, 'progressNote', totalTasks == 0 ? 'No live task data found' : 'Loaded $totalTasks live task${totalTasks == 1 ? '' : 's'}');

    return _Surface(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: theme.accent.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.insights_rounded, color: theme.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16))),
              _InfoTag(label: '$progress%', icon: Icons.trending_up_rounded, color: progress >= 60 ? theme.accent : const Color(0xFFF97316), theme: theme),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 14),
          SizedBox(
            height: 142,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(points.length, (index) {
                final point = points[index];
                final selected = index == selectedIndex;
                final barHeight = 34 + (point.ratio * 82);
                final percentText = selected ? '$progress%' : '+${(point.ratio * 10).round().clamp(2, 10)}%';
                final barColor = selected ? theme.textPrimary : theme.accent;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                        decoration: BoxDecoration(
                          color: barColor.withOpacity(selected ? 1 : .12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: barColor.withOpacity(selected ? 1 : .22)),
                        ),
                        child: Text(percentText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? Colors.white : barColor, fontWeight: FontWeight.w900, fontSize: selected ? 11 : 10)),
                      ),
                      const SizedBox(height: 7),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        width: selected ? 32 : 22,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: barColor.withOpacity(selected ? .95 : .22),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: barColor.withOpacity(selected ? .95 : .28)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('${point.day.day}', style: TextStyle(color: selected ? theme.textPrimary : theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 11)),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.textPrimary,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: theme.textPrimary.withOpacity(.12), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: Row(
              children: [
                const Text('👍', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(child: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(.10), borderRadius: BorderRadius.circular(999)),
                  child: Text('$completedTasks done', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTimelineBarsJson extends StatelessWidget {
  const _TaskTimelineBarsJson({required this.state, required this.data, required this.theme});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final tasks = _timelineTasksForState(state)
      ..sort((a, b) {
        final statusCompare = _taskProgressForStatus(a.status).compareTo(_taskProgressForStatus(b.status));
        if (statusCompare != 0) return statusCompare;
        return a.dueDate.compareTo(b.dueDate);
      });
    final limit = _num(data['timelineTaskLimit'], 4).round().clamp(2, 8).toInt();
    final items = tasks.take(limit).toList();
    final showReferenceFallback = _flag(
      data['showReferenceFallbackWhenEmpty'] ?? data['referenceFallbackWhenEmpty'] ?? data['mockPreviewWhenEmpty'],
      fallback: true,
    );
    final renderItems = items.isNotEmpty
        ? items.map((task) {
            final ratio = _taskProgressForStatus(task.status).clamp(.16, 1.0).toDouble();
            final color = task.status == TaskStatus.completed ? theme.accent : task.priority.color;
            return _TaskTimelineBarItem(
              dayLabel: '${task.dueDate.day}',
              timeLabel: _textOf(data, 'taskTimeLabel', DateText.compact(task.dueDate)),
              title: task.title,
              subtitle: _projectName(state, task.projectId),
              statusLabel: task.status.label,
              ratio: ratio,
              color: color,
              live: true,
            );
          }).toList()
        : (showReferenceFallback ? _referenceTaskTimelineItems(theme, data) : const <_TaskTimelineBarItem>[]);
    final title = _textOf(data, 'timelineBarsTitle', 'Task Timeline');
    final subtitle = _textOf(
      data,
      'timelineBarsSubtitle',
      items.isEmpty
          ? (showReferenceFallback ? 'Reference timeline preview until live tasks arrive.' : 'No timeline tasks yet.')
          : 'Due dates and status progress',
    );
    final variant = _textOf(data, 'variant', _textOf(data, 'timelineBarsVariant', 'referenceSoftBars')).replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
    final useReferenceStyle = variant.contains('reference') || variant.contains('productive') || variant.contains('delivery');

    return _Surface(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: theme.accent.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.view_timeline_rounded, color: theme.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16))),
              if (items.isEmpty && showReferenceFallback)
                _InfoTag(label: 'Preview', icon: Icons.auto_awesome_rounded, color: theme.accent, theme: theme)
              else
                Icon(Icons.more_horiz_rounded, color: theme.textSecondary),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(height: 16),
          if (renderItems.isEmpty)
            _referenceModuleCard(theme: theme, title: 'No task timeline', subtitle: 'Assigned tasks will appear as progress bars.', icon: Icons.view_timeline_rounded)
          else if (useReferenceStyle)
            _ReferenceTaskTimelineBars(theme: theme, items: renderItems)
          else
            ...renderItems.asMap().entries.map((entry) {
              final item = entry.value;
              return Padding(
                padding: EdgeInsets.only(bottom: entry.key == renderItems.length - 1 ? 0 : 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(item.dayLabel, textAlign: TextAlign.center, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 12.5))),
                              const SizedBox(width: 8),
                              Text('${(item.ratio * 100).round()}%', style: TextStyle(color: item.color, fontWeight: FontWeight.w900, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 7),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final width = (constraints.maxWidth * item.ratio).clamp(54.0, constraints.maxWidth).toDouble();
                              return Stack(
                                alignment: Alignment.centerLeft,
                                children: [
                                  Container(
                                    height: 24,
                                    decoration: BoxDecoration(color: theme.background.withOpacity(.82), borderRadius: BorderRadius.circular(999), border: Border.all(color: theme.border)),
                                  ),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 260),
                                    curve: Curves.easeOutCubic,
                                    width: width,
                                    height: 24,
                                    decoration: BoxDecoration(color: item.color.withOpacity(.88), borderRadius: BorderRadius.circular(999)),
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: Text(item.statusLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10.5)),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ReferenceTaskTimelineBars extends StatelessWidget {
  const _ReferenceTaskTimelineBars({required this.theme, required this.items});

  final _UiTheme theme;
  final List<_TaskTimelineBarItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.asMap().entries.map((entry) {
        final item = entry.value;
        final isLast = entry.key == items.length - 1;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 42,
                  child: Column(
                    children: [
                      Text(item.dayLabel, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 11)),
                      const SizedBox(height: 8),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.surface,
                          border: Border.all(color: item.color, width: 2),
                        ),
                      ),
                      if (!isLast) Expanded(child: Container(width: 1.4, margin: const EdgeInsets.only(top: 4), color: item.color.withOpacity(.34))),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: item.live ? theme.surface : theme.background.withOpacity(.86),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: item.color.withOpacity(item.live ? .22 : .16)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(.045), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(color: item.color.withOpacity(.13), borderRadius: BorderRadius.circular(13)),
                              child: Icon(item.icon, color: item.color, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 13.5)),
                                  const SizedBox(height: 3),
                                  Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 11.5)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(item.timeLabel, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 10.5)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = (constraints.maxWidth * item.ratio).clamp(46.0, constraints.maxWidth).toDouble();
                            return Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                Container(height: 9, decoration: BoxDecoration(color: item.color.withOpacity(.10), borderRadius: BorderRadius.circular(999))),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 420),
                                  curve: Curves.easeOutCubic,
                                  width: width,
                                  height: 9,
                                  decoration: BoxDecoration(color: item.color, borderRadius: BorderRadius.circular(999)),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            _InfoTag(label: item.statusLabel, icon: Icons.flag_rounded, color: item.color, theme: theme),
                            const Spacer(),
                            Text('${(item.ratio * 100).round()}%', style: TextStyle(color: item.color, fontWeight: FontWeight.w900, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TaskTimelineBarItem {
  const _TaskTimelineBarItem({
    required this.dayLabel,
    required this.timeLabel,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.ratio,
    required this.color,
    required this.live,
    this.icon = Icons.task_alt_rounded,
  });

  final String dayLabel;
  final String timeLabel;
  final String title;
  final String subtitle;
  final String statusLabel;
  final double ratio;
  final Color color;
  final bool live;
  final IconData icon;
}

List<_TaskTimelineBarItem> _referenceTaskTimelineItems(_UiTheme theme, Map<String, dynamic> data) {
  final accent = theme.accent;
  final orange = _timelineColorFromHex(_textOf(data, 'referenceOrange', '#F36B3A'), const Color(0xFFF36B3A));
  final blue = _timelineColorFromHex(_textOf(data, 'referenceBlue', '#4F7CCF'), const Color(0xFF4F7CCF));
  final purple = _timelineColorFromHex(_textOf(data, 'referencePurple', '#6B5ED7'), const Color(0xFF6B5ED7));
  return <_TaskTimelineBarItem>[
    _TaskTimelineBarItem(dayLabel: '12', timeLabel: '9:00', title: 'Design system update', subtitle: 'UI/UX redesign', statusLabel: 'Review', ratio: .66, color: accent, live: false, icon: Icons.draw_rounded),
    _TaskTimelineBarItem(dayLabel: '13', timeLabel: '11:30', title: 'Implement login flow', subtitle: 'Website revamp', statusLabel: 'In progress', ratio: .46, color: orange, live: false, icon: Icons.code_rounded),
    _TaskTimelineBarItem(dayLabel: '14', timeLabel: '2:00', title: 'Project status review', subtitle: 'Mobile app', statusLabel: 'Testing', ratio: .58, color: blue, live: false, icon: Icons.article_rounded),
    _TaskTimelineBarItem(dayLabel: '15', timeLabel: '4:30', title: 'Sprint planning', subtitle: 'Q2 sprint', statusLabel: 'Planned', ratio: .38, color: purple, live: false, icon: Icons.flag_rounded),
  ];
}


Color _timelineColorFromHex(String raw, Color fallback) {
  final value = raw.trim();
  if (value.isEmpty) return fallback;
  var hex = value.replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return fallback;
  return Color(int.tryParse(hex, radix: 16) ?? fallback.value);
}

class _ProgressChartPoint {
  const _ProgressChartPoint({required this.day, required this.ratio, required this.taskCount});
  final DateTime day;
  final double ratio;
  final int taskCount;
}

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _FilesDataJsonScreen extends StatelessWidget {
  const _FilesDataJsonScreen({
    required this.state,
    required this.data,
    required this.theme,
    this.embedded = false,
  });

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final visibleTaskIds =
        state.visibleTasks.map((task) => task.taskId).toSet();
    final visibleProjectIds =
        state.visibleProjects.map((project) => project.projectId).toSet();

    final files = state.attachments.where((file) {
      return visibleTaskIds.contains(file.taskId) ||
          visibleProjectIds.contains(file.projectId);
    }).toList();

    final Map<String, List<dynamic>> filesByTask = {};
    final List<dynamic> projectFiles = [];

    for (final file in files) {
      final taskId = file.taskId.toString().trim();

      if (taskId.isNotEmpty && visibleTaskIds.contains(taskId)) {
        filesByTask.putIfAbsent(taskId, () => <dynamic>[]);
        filesByTask[taskId]!.add(file);
      } else {
        projectFiles.add(file);
      }
    }

    for (final entry in filesByTask.entries) {
      entry.value.sort(
        (a, b) => _fileCreatedAt(b).compareTo(_fileCreatedAt(a)),
      );
    }

    final taskGroups = filesByTask.entries.toList()
      ..sort((a, b) {
        final aDate = a.value.isEmpty
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : _fileCreatedAt(a.value.first);
        final bDate = b.value.isEmpty
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : _fileCreatedAt(b.value.first);
        return bDate.compareTo(aDate);
      });

    projectFiles.sort(
      (a, b) => _fileCreatedAt(b).compareTo(_fileCreatedAt(a)),
    );

    final taskFileCount = state.visibleTasks.fold<int>(
      0,
      (sum, task) => sum + task.attachmentsCount,
    );

    final children = <Widget>[
      if (!embedded)
        _ScreenTitle(
          title: _textOf(data, 'title', 'Files & Documents'),
          subtitle: _textOf(
            data,
            'subtitle',
            'Files grouped by task and arranged by upload time',
          ),
        ),
      _referenceModuleSummary(
        theme: theme,
        title: 'Files & Documents',
        subtitle:
            '${files.length} file${files.length == 1 ? '' : 's'} • ${taskGroups.length} task group${taskGroups.length == 1 ? '' : 's'} • $taskFileCount reference${taskFileCount == 1 ? '' : 's'}',
        icon: Icons.folder_open_rounded,
      ),
      const SizedBox(height: 8),
      if (files.isEmpty)
        _referenceModuleCard(
          theme: theme,
          title: 'No files yet',
          subtitle: 'Files uploaded from task details will appear here.',
          icon: Icons.folder_off_rounded,
        )
      else ...[
        ...taskGroups.map((entry) {
          ProjectTask? task;
          for (final item in state.visibleTasks) {
            if (item.taskId == entry.key) {
              task = item;
              break;
            }
          }

          return _FilesTaskGroup(
            theme: theme,
            taskTitle: task?.title ?? 'Task files',
            projectName:
                task == null ? '' : _projectName(state, task.projectId),
            files: entry.value,
          );
        }),
        if (projectFiles.isNotEmpty)
          _FilesProjectGroup(
            theme: theme,
            state: state,
            files: projectFiles,
          ),
      ],
    ];

    return embedded
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          )
        : ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.all(theme.padding),
            children: children,
          );
  }
}

class _FilesTaskGroup extends StatelessWidget {
  const _FilesTaskGroup({
    required this.theme,
    required this.taskTitle,
    required this.projectName,
    required this.files,
  });

  final _UiTheme theme;
  final String taskTitle;
  final String projectName;
  final List<dynamic> files;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.accent.withOpacity(.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.task_alt_rounded,
                    color: theme.accent,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        taskTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (projectName.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.folder_rounded,
                              size: 13,
                              color: theme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                projectName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _FilesCountBadge(
                  theme: theme,
                  count: files.length,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.border),
          ...files.asMap().entries.map(
                (entry) => _FileDocumentRow(
                  theme: theme,
                  file: entry.value,
                  showDivider: entry.key < files.length - 1,
                ),
              ),
        ],
      ),
    );
  }
}

class _FilesProjectGroup extends StatelessWidget {
  const _FilesProjectGroup({
    required this.theme,
    required this.state,
    required this.files,
  });

  final _UiTheme theme;
  final WorkspaceState state;
  final List<dynamic> files;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.accent.withOpacity(.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.folder_special_rounded,
                    color: theme.accent,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Project files',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Files not linked to a specific task',
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _FilesCountBadge(
                  theme: theme,
                  count: files.length,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.border),
          ...files.asMap().entries.map(
                (entry) => _FileDocumentRow(
                  theme: theme,
                  file: entry.value,
                  showDivider: entry.key < files.length - 1,
                ),
              ),
        ],
      ),
    );
  }
}

class _FilesCountBadge extends StatelessWidget {
  const _FilesCountBadge({
    required this.theme,
    required this.count,
  });

  final _UiTheme theme;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: theme.accent.withOpacity(.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: theme.accent,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _FileDocumentRow extends StatelessWidget {
  const _FileDocumentRow({
    required this.theme,
    required this.file,
    required this.showDivider,
  });

  final _UiTheme theme;
  final dynamic file;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final fileName = _fileName(file);
    final fileType = _fileType(file);
    final createdAt = _fileCreatedAt(file);
    final fileUrl = _fileUrl(file);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _fileIconColor(fileType, theme).withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _fileIcon(fileType),
                  color: _fileIconColor(fileType, theme),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName.isEmpty ? 'Unnamed file' : fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (fileType.isNotEmpty)
                          Flexible(
                            child: Text(
                              fileType.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.textSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        if (fileType.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '•',
                              style: TextStyle(
                                color: theme.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            _fileDateTimeText(createdAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: fileUrl == null
                    ? 'Download unavailable'
                    : 'Download file',
                onPressed: fileUrl == null
                    ? () => _showDownloadUnavailable(context)
                    : () => _openFile(context, fileUrl),
                style: IconButton.styleFrom(
                  backgroundColor: theme.accent.withOpacity(.08),
                  foregroundColor: theme.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: Icon(
                  fileUrl == null
                      ? Icons.cloud_off_rounded
                      : Icons.download_rounded,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 70),
            child: Divider(height: 1, color: theme.border),
          ),
      ],
    );
  }

  Future<void> _openFile(BuildContext context, String url) async {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.trim().isEmpty) {
      _showDownloadUnavailable(context);
      return;
    }

    try {
      // Cloudinary secure_url values are direct HTTPS file URLs. Opening the
      // URL externally lets the platform/browser handle the file according to
      // its content type while keeping the renderer compatible with Android,
      // iOS and Flutter Web.
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this file.'),
          ),
        );
      }
    } catch (error) {
      debugPrint('File download/open error: $error');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open this file.'),
          ),
        );
      }
    }
  }

  void _showDownloadUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Download link is not available for this file.'),
      ),
    );
  }
}

DateTime _fileCreatedAt(dynamic file) {
  try {
    final value = file.createdAt;

    if (value is DateTime) return value;

    if (value != null) {
      final parsed = DateTime.tryParse(value.toString());
      if (parsed != null) return parsed;
    }
  } catch (_) {}

  return DateTime.fromMillisecondsSinceEpoch(0);
}

String _fileName(dynamic file) {
  try {
    return file.fileName?.toString().trim() ?? '';
  } catch (_) {
    return '';
  }
}

String _fileType(dynamic file) {
  try {
    return file.fileType?.toString().trim() ?? '';
  } catch (_) {
    return '';
  }
}

String? _fileUrl(dynamic file) {
  final candidates = <dynamic>[];

  // Cloudinary fields.
  try { candidates.add(file.secureUrl); } catch (_) {}
  try { candidates.add(file.secureURL); } catch (_) {}
  try { candidates.add(file.cloudinaryUrl); } catch (_) {}
  try { candidates.add(file.cloudinaryURL); } catch (_) {}

  // Existing/legacy URL fields.
  try { candidates.add(file.downloadUrl); } catch (_) {}
  try { candidates.add(file.downloadURL); } catch (_) {}
  try { candidates.add(file.fileUrl); } catch (_) {}
  try { candidates.add(file.url); } catch (_) {}
  try { candidates.add(file.mediaUrl); } catch (_) {}
  try { candidates.add(file.mediaURL); } catch (_) {}

  for (final candidate in candidates) {
    if (candidate == null) continue;
    final value = candidate.toString().trim();
    if (value.isEmpty) continue;

    final uri = Uri.tryParse(value);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.trim().isNotEmpty) {
      return value;
    }
  }

  return null;
}

IconData _fileIcon(String type) {
  final value = type.toLowerCase();

  if (value.contains('pdf')) return Icons.picture_as_pdf_rounded;

  if (value.contains('image') ||
      value.contains('png') ||
      value.contains('jpg') ||
      value.contains('jpeg') ||
      value.contains('webp')) {
    return Icons.image_rounded;
  }

  if (value.contains('video') ||
      value.contains('mp4') ||
      value.contains('mov') ||
      value.contains('mkv')) {
    return Icons.video_file_rounded;
  }

  if (value.contains('audio') ||
      value.contains('mp3') ||
      value.contains('wav') ||
      value.contains('m4a')) {
    return Icons.audio_file_rounded;
  }

  if (value.contains('doc') || value.contains('word')) {
    return Icons.description_rounded;
  }

  if (value.contains('xls') ||
      value.contains('excel') ||
      value.contains('sheet')) {
    return Icons.table_chart_rounded;
  }

  if (value.contains('zip') ||
      value.contains('rar') ||
      value.contains('7z')) {
    return Icons.folder_zip_rounded;
  }

  return Icons.insert_drive_file_rounded;
}

Color _fileIconColor(String type, _UiTheme theme) {
  final value = type.toLowerCase();

  if (value.contains('pdf')) return const Color(0xFFDC2626);

  if (value.contains('image') ||
      value.contains('png') ||
      value.contains('jpg') ||
      value.contains('jpeg') ||
      value.contains('webp')) {
    return const Color(0xFF2563EB);
  }

  if (value.contains('video')) return const Color(0xFF7C3AED);
  if (value.contains('audio')) return const Color(0xFFDB2777);

  if (value.contains('doc') || value.contains('word')) {
    return const Color(0xFF2563EB);
  }

  if (value.contains('xls') ||
      value.contains('excel') ||
      value.contains('sheet')) {
    return const Color(0xFF16A34A);
  }

  return theme.accent;
}

String _fileDateTimeText(DateTime date) {
  if (date.millisecondsSinceEpoch == 0) {
    return 'Unknown upload time';
  }

  final local = date.toLocal();
  final now = DateTime.now();

  final isToday = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;

  final yesterday = now.subtract(const Duration(days: 1));

  final isYesterday = local.year == yesterday.year &&
      local.month == yesterday.month &&
      local.day == yesterday.day;

  final hour =
      local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);

  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  final time = '$hour:$minute $suffix';

  if (isToday) return 'Today, $time';
  if (isYesterday) return 'Yesterday, $time';

  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  return '${months[local.month - 1]} ${local.day}, ${local.year} • $time';
}

class _TeamMembersDataJsonScreen extends StatelessWidget {
  const _TeamMembersDataJsonScreen({required this.state, required this.data, required this.theme, this.embedded = false});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final visibleTeamIds = state.visibleProjects.expand((project) => project.teamIds).toSet();
    final assignedMemberIds = state.visibleTasks.expand((task) => task.assignedToIds).toSet();
    final members = state.members.where((member) {
      if (member.uid == state.currentMember.uid) return true;
      if (assignedMemberIds.contains(member.uid)) return true;
      return member.teamIds.any(visibleTeamIds.contains);
    }).toList()..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    final online = members.where((member) => member.isOnline).length;
    final children = <Widget>[
      if (!embedded)
        _ScreenTitle(
          title: _textOf(data, 'title', 'Team Members'),
          subtitle: _textOf(data, 'subtitle', 'Workload, role and online status'),
        ),
      _referenceModuleSummary(theme: theme, title: 'Team scope', subtitle: '${members.length} member(s) • $online online', icon: Icons.groups_rounded),
      if (members.isEmpty)
        _referenceModuleCard(theme: theme, title: 'No team members', subtitle: 'Assigned members will appear when project/team links are available.', icon: Icons.person_off_rounded)
      else
        ...members.take(24).map((member) => _referenceModuleCard(
              theme: theme,
              title: member.displayName,
              subtitle: '${member.effectiveJobTitle} • ${member.effectiveDepartment} • ${member.presenceLabel}',
              icon: Icons.person_rounded,
              color: member.isOnline ? const Color(0xFF16A34A) : theme.textSecondary,
              trailing: Icon(member.isOnline ? Icons.circle_rounded : Icons.circle_outlined, color: member.isOnline ? const Color(0xFF16A34A) : theme.textSecondary, size: 16),
            )),
    ];
    return embedded
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)
        : ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(theme.padding), children: children);
  }
}

class _TaskDetailDataJsonScreen extends StatelessWidget {
  const _TaskDetailDataJsonScreen({required this.state, required this.data, required this.theme, required this.previewMode});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool previewMode;

  @override
  Widget build(BuildContext context) {
    final openTasks = state.visibleTasks.where((task) => task.status != TaskStatus.completed).toList()
      ..sort((a, b) => _taskActivityDateForSort(b).compareTo(_taskActivityDateForSort(a)));
    final task = openTasks.isNotEmpty ? openTasks.first : (state.visibleTasks.isEmpty ? null : state.visibleTasks.first);
    final children = <Widget>[
      _ScreenTitle(title: _textOf(data, 'title', 'Task Detail'), subtitle: _textOf(data, 'subtitle', 'Latest assigned task from live workspace data')),
      _EditableTaskCard(
        task: task,
        fields: _mergeStringLists(_fieldsOf(data, fallback: state.mobileUiDesign.taskFields), const <String>['projectName', 'taskTitle', 'description', 'status', 'priority', 'deadlineTimer', 'assigneeCount', 'commentsCount', 'attachmentsCount', 'progress']),
        actions: _mergeStringLists(_actionsOf(data, fallback: state.mobileUiDesign.taskCard['actions']), const <String>['openDetails', 'comment', 'uploadFile']),
        variant: _cardVariant(data['variant'] ?? state.mobileUiDesign.taskCard['variant'], 'modernCard'),
        theme: theme,
        previewMode: previewMode,
        projectName: task == null ? null : _projectName(state, task.projectId),
      ),
    ];
    return ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(theme.padding), children: children);
  }
}

class _ProjectDetailDataJsonScreen extends StatelessWidget {
  const _ProjectDetailDataJsonScreen({required this.state, required this.data, required this.theme});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final projects = state.visibleProjects.toList()
      ..sort((a, b) {
        final activeCompare = (b.isActiveWork ? 1 : 0).compareTo(a.isActiveWork ? 1 : 0);
        if (activeCompare != 0) return activeCompare;
        return a.dueDate.compareTo(b.dueDate);
      });
    final defaultProject = projects.isEmpty ? null : projects.first;
    final fields = _mergeStringLists(
      _fieldsOf(data, fallback: state.mobileUiDesign.projectFields),
      const <String>['projectName', 'description', 'status', 'taskCount', 'completedTaskCount', 'team', 'deadline', 'priority', 'progress'],
    );
    final variant = _cardVariant(data['variant'] ?? state.mobileUiDesign.projectCard['variant'], 'progressCard');
    final children = <Widget>[
      _ScreenTitle(
        title: _textOf(data, 'title', 'Select project'),
        subtitle: _textOf(data, 'subtitle', 'Working projects joined by this employee. Tap a card to expand tasks and timeline.'),
      ),
      if (defaultProject != null)
        _referenceModuleSummary(
          theme: theme,
          title: 'Default working project',
          subtitle: '${defaultProject.name} • ${state.visibleTasks.where((task) => task.projectId == defaultProject.projectId).length} task(s)',
          icon: Icons.folder_special_rounded,
        ),
      if (projects.isEmpty)
        _referenceModuleCard(theme: theme, title: 'No joined projects', subtitle: 'Projects joined by this employee will appear here.', icon: Icons.folder_off_rounded)
      else
        ...projects.take(30).map((project) => _ProjectCard(
              project: project,
              fields: fields,
              variant: variant,
              theme: theme,
              tasks: state.visibleTasks.where((task) => task.projectId == project.projectId).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate)),
              initiallyExpanded: defaultProject?.projectId == project.projectId,
              defaultBadge: defaultProject?.projectId == project.projectId ? 'Working project' : null,
            )),
    ];
    return ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(theme.padding), children: children);
  }
}


class _MeetingDetailDataJsonScreen extends StatelessWidget {
  const _MeetingDetailDataJsonScreen({required this.state, required this.data, required this.theme});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final meetings = state.myNotifications.where((item) => item.isMeetingInvite).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final meeting = meetings.isEmpty ? null : meetings.first;
    final children = <Widget>[
      _ScreenTitle(title: _textOf(data, 'title', 'Meeting Detail'), subtitle: _textOf(data, 'subtitle', 'Latest visible meeting invite')),
      if (meeting == null)
        _referenceModuleCard(theme: theme, title: 'No meeting invite', subtitle: 'Meeting invites from admin will appear here.', icon: Icons.video_camera_front_rounded)
      else
        _Surface(
          theme: theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _referenceModuleIcon(theme, meeting.actionType?.toLowerCase().contains('whatsapp') == true ? Icons.phone_in_talk_rounded : Icons.video_call_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(meeting.title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 8),
                        Text(meeting.message, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, height: 1.35)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoTag(label: DateText.compact(meeting.createdAt), icon: Icons.calendar_month_rounded, theme: theme),
                            if ((meeting.actionUrl ?? '').trim().isNotEmpty) _InfoTag(label: 'Meeting link ready', icon: Icons.link_rounded, theme: theme),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Accept & Join'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Reject'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      if (meeting != null) ...[
        _referenceModuleCard(theme: theme, title: 'Creator', subtitle: 'Platform Super Admin', icon: Icons.admin_panel_settings_rounded),
        _referenceModuleCard(theme: theme, title: 'Link', subtitle: meeting.actionUrl ?? 'No external meeting link stored yet', icon: Icons.link_rounded),
        _referenceModuleCard(theme: theme, title: 'Status', subtitle: meeting.isRead ? 'Accepted / read' : 'Pending action', icon: Icons.pending_actions_rounded),
      ],
    ];
    return ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(theme.padding), children: children);
  }
}


Uri? _safeExternalUri(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  final normalized = lower.startsWith('https://') || lower.startsWith('http://') || lower.startsWith('whatsapp://')
      ? trimmed
      : (lower.startsWith('meet.google.com/') || lower.startsWith('wa.me/') || lower.startsWith('api.whatsapp.com/'))
          ? 'https://$trimmed'
          : '';
  if (normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null || !(scheme == 'https' || scheme == 'http' || scheme == 'whatsapp')) return null;
  return uri;
}


class _MeetingsJsonScreen extends ConsumerStatefulWidget {
  const _MeetingsJsonScreen({
    required this.state,
    required this.data,
    required this.theme,
    this.embedded = false,
    this.runtimeSearchQuery = '',
    this.runtimeContentFilter = 'All',
    this.suppressPageSearchBars = false,
  });

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;
  final String runtimeSearchQuery;
  final String runtimeContentFilter;
  final bool suppressPageSearchBars;

  @override
  ConsumerState<_MeetingsJsonScreen> createState() => _MeetingsJsonScreenState();
}


class _MeetingsJsonScreenState extends ConsumerState<_MeetingsJsonScreen> {
  String _query = '';
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final q = _normalizeSearchQuery(widget.embedded ? widget.runtimeSearchQuery : _query);
    final source = widget.state.myNotifications.where((item) => item.isMeetingInvite).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final activeFilter = _isAllPageFilter(widget.runtimeContentFilter) ? _filter : widget.runtimeContentFilter;
    final scopedSource = _isAllPageFilter(activeFilter)
        ? source
        : source.where((item) => _matchesMeetingFilter(widget.state, item, activeFilter)).toList();
    final meetings = (q.isEmpty ? scopedSource : scopedSource.where((item) => _matchesNotificationQuery(widget.state, item, q)).toList())
        .take(_num(widget.data['limit'], 30).round().clamp(1, 80).toInt())
        .toList();
    final showSearch = !widget.embedded && !widget.suppressPageSearchBars && _flag(widget.data['showSearch'] ?? widget.data['allowPageSearchBar'], fallback: true);
    final children = <Widget>[
      if (!widget.embedded && widget.data['hideTitle'] != true)
        _ScreenTitle(
          title: _textOf(widget.data, 'title', 'Meetings'),
          subtitle: _textOf(widget.data, 'subtitle', 'Meeting links and invites'),
        ),
      if (showSearch)
        _ProjectPageNavSearchBox(
          theme: widget.theme,
          hint: _textOf(_asMap(widget.data['search']) ?? const <String, dynamic>{}, 'hint', 'Search meetings'),
          initialQuery: _query,
          resultCount: meetings.length,
          resultName: 'meeting',
          clearTooltip: 'Clear meeting search',
          onChanged: (value) => setState(() => _query = value),
        ),
      if (!widget.embedded)
        _ReferenceFilterPills(
          theme: widget.theme,
          items: const <String>['All', 'Today', 'Pending', 'Accepted'],
          selected: _filter,
          onChanged: (value) => setState(() => _filter = value),
        ),
      if (meetings.isEmpty)
        _referenceModuleCard(
          theme: widget.theme,
          title: q.isEmpty ? 'No meetings' : 'No matching meetings',
          subtitle: q.isEmpty ? 'Meeting invites sent by managers and admins will appear here.' : 'Try another meeting title, message, link, or provider.',
          icon: Icons.video_call_rounded,
        ),
      ...meetings.map((item) {
        final isWhatsApp = item.actionType?.toLowerCase().contains('whatsapp') == true || (item.actionUrl ?? '').toLowerCase().contains('whatsapp');
        return _SectionResultBadge(
          theme: widget.theme,
          label: 'Meeting section',
          icon: Icons.video_call_rounded,
          visible: _showSourceBadges(embedded: widget.embedded, query: q, filter: activeFilter),
          child: _Surface(
            theme: widget.theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _referenceModuleIcon(widget.theme, isWhatsApp ? Icons.phone_in_talk_rounded : Icons.video_call_rounded),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 6),
                          Text(item.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.3)),
                          const SizedBox(height: 8),
                          Text(DateText.compact(item.createdAt), style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (item.isRead) _InfoTag(label: 'Accepted', icon: Icons.check_circle_rounded, color: const Color(0xFF059669), theme: widget.theme),
                  ],
                ),
                if (!item.isRead && item.hasActionUrl) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            AndroidAlertNotificationService.acceptLoopingAlert(item.notificationId);
                            ref.read(workspaceProvider.notifier).markNotificationRead(item.notificationId);
                            final uri = _safeExternalUri(item.actionUrl);
                            if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                          },
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text((item.actionLabel ?? '').trim().isEmpty ? 'Accept & Join' : item.actionLabel!.trim()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            AndroidAlertNotificationService.acceptLoopingAlert(item.notificationId);
                            ref.read(workspaceProvider.notifier).markNotificationRead(item.notificationId);
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: Text((item.rejectLabel ?? '').trim().isEmpty ? 'Reject' : item.rejectLabel!.trim()),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      }),
      if (!widget.embedded)
        _referenceModuleCard(
          theme: widget.theme,
          title: 'Create meeting',
          subtitle: 'Create meeting links from the admin Meetings page. Employee APK receives Accept & Join / Reject notifications.',
          icon: Icons.add_box_rounded,
        ),
    ];
    return widget.embedded ? Column(children: children) : ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(widget.theme.padding), children: children);
  }
}


class _NotificationMotionHeaderJson extends StatefulWidget {
  const _NotificationMotionHeaderJson();

  static const String remoteMotionUrl =
      'https://miro.medium.com/v2/resize:fit:786/format:webp/1*M9Zhk2sTQ5f5iJY2z1y8uA.gif';

  @override
  State<_NotificationMotionHeaderJson> createState() => _NotificationMotionHeaderJsonState();
}

class _NotificationMotionHeaderJsonState extends State<_NotificationMotionHeaderJson> with SingleTickerProviderStateMixin {
  late final AnimationController _fallbackController;

  @override
  void initState() {
    super.initState();
    _fallbackController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _fallbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE1E6DC)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 86,
              height: 86,
              child: Image.network(
                _NotificationMotionHeaderJson.remoteMotionUrl,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => _fallback(),
                loadingBuilder: (context, child, loadingProgress) => loadingProgress == null ? child : _fallback(),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notification center',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F140F)),
                ),
                SizedBox(height: 5),
                Text(
                  'Task alerts, meeting invites, and action requests appear here.',
                  style: TextStyle(height: 1.25, fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF5F675E)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return AnimatedBuilder(
      animation: _fallbackController,
      builder: (context, child) {
        final scale = 0.92 + (_fallbackController.value * .12);
        return Container(
          color: const Color(0xFFEFF3EB),
          alignment: Alignment.center,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF5F7F55),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: const Color(0xFF5F7F55).withOpacity(.22), blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: const Icon(Icons.notifications_active_rounded, color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}

class _NotificationsJsonScreen extends ConsumerStatefulWidget {
  const _NotificationsJsonScreen({
    required this.state,
    required this.data,
    required this.theme,
    this.embedded = false,
    this.runtimeSearchQuery = '',
    this.runtimeContentFilter = 'All',
    this.suppressPageSearchBars = false,
  });
  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;
  final String runtimeSearchQuery;
  final String runtimeContentFilter;
  final bool suppressPageSearchBars;

  @override
  ConsumerState<_NotificationsJsonScreen> createState() => _NotificationsJsonScreenState();
}


enum _JsonNotificationViewMode { stack, expanded }

class _NotificationsJsonScreenState extends ConsumerState<_NotificationsJsonScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _deckController;

  String _query = '';
  String _filter = 'All';
  _JsonNotificationViewMode _viewMode = _JsonNotificationViewMode.stack;
  bool _deckExpanded = false;
  bool _showExpandedRows = false;

  @override
  void initState() {
    super.initState();
    _deckController = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  }

  @override
  void dispose() {
    _deckController.dispose();
    super.dispose();
  }

  Future<void> _setMode(_JsonNotificationViewMode mode) async {
    if (_viewMode == mode) return;
    HapticFeedback.selectionClick();

    if (mode == _JsonNotificationViewMode.expanded) {
      setState(() {
        _viewMode = _JsonNotificationViewMode.expanded;
        _deckExpanded = true;
        _showExpandedRows = false;
      });
      await _deckController.forward();
      if (!mounted) return;
      setState(() => _showExpandedRows = true);
    } else {
      setState(() {
        _viewMode = _JsonNotificationViewMode.stack;
        _deckExpanded = false;
        _showExpandedRows = false;
      });
      await _deckController.reverse();
    }
  }

  Future<void> _toggleDeck() async {
    HapticFeedback.selectionClick();

    if (_deckExpanded) {
      setState(() {
        _viewMode = _JsonNotificationViewMode.stack;
        _deckExpanded = false;
        _showExpandedRows = false;
      });
      await _deckController.reverse();
      return;
    }

    setState(() {
      _viewMode = _JsonNotificationViewMode.expanded;
      _deckExpanded = true;
      _showExpandedRows = false;
    });
    await _deckController.forward();
    if (!mounted) return;
    setState(() => _showExpandedRows = true);
  }

  @override
  Widget build(BuildContext context) {
    final q = _normalizeSearchQuery(widget.embedded ? widget.runtimeSearchQuery : _query);
    final source = widget.state.myNotifications.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final runtimeScoped = _isAllPageFilter(widget.runtimeContentFilter)
        ? source
        : source.where((item) => _matchesNotificationFilter(widget.state, item, widget.runtimeContentFilter)).toList();
    final localScoped = _jsonNotificationFilter(runtimeScoped, _filter);
    final searched = q.isEmpty ? localScoped : localScoped.where((item) => _matchesNotificationQuery(widget.state, item, q)).toList();
    final limit = _num(widget.data['limit'] ?? widget.data['stackLimit'], 80).round().clamp(1, 120).toInt();
    final notifications = searched.take(limit).toList();
    final unreadTotal = source.where((item) => !item.isRead).length;
    final unreadVisible = notifications.where((item) => !item.isRead).length;
    final deckLimit = _num(widget.data['deckCardLimit'] ?? widget.data['stackCardLimit'] ?? widget.data['notificationDeckLimit'], 4).round().clamp(2, 6).toInt();
    final deckItems = notifications.take(deckLimit).toList(growable: false);
    final expandedRows = _showExpandedRows ? notifications.skip(deckItems.length).toList(growable: false) : const <AppNotification>[];
    final showSearch = !widget.embedded && !widget.suppressPageSearchBars && _flag(widget.data['showSearch'] ?? widget.data['allowPageSearchBar'], fallback: true);
    final stackEnabled = _flag(widget.data['stackNotificationsEnabled'] ?? widget.data['stackedNotificationDeck'] ?? widget.data['useStackNotificationDeck'], fallback: true);
    final showMotionHeader = !stackEnabled && !widget.embedded && widget.data['notificationMotionHeaderEnabled'] != false;

    final children = <Widget>[
      if (!widget.embedded && widget.data['hideTitle'] != true)
        _ScreenTitle(
          title: _textOf(widget.data, 'title', 'Inbox'),
          subtitle: '$unreadTotal unread private notification(s)',
          trailing: unreadTotal > 0
              ? TextButton(
                  onPressed: _markAllUnreadAsRead,
                  child: const Text('Mark all read'),
                )
              : null,
        ),
      if (showMotionHeader) const _NotificationMotionHeaderJson(),
      if (showMotionHeader) const SizedBox(height: 12),
      if (showSearch)
        _ProjectPageNavSearchBox(
          theme: widget.theme,
          hint: _textOf(_asMap(widget.data['search']) ?? const <String, dynamic>{}, 'hint', 'Search inbox notifications'),
          initialQuery: _query,
          resultCount: notifications.length,
          resultName: 'notification',
          clearTooltip: 'Clear inbox search',
          onChanged: (value) => setState(() => _query = value),
        ),
      if (notifications.isEmpty)
        _JsonCard(
          title: q.isEmpty ? (_filter == 'All' ? 'No notifications' : 'No $_filter notifications') : 'No matching notifications',
          subtitle: q.isEmpty ? 'Private task updates will appear here.' : 'Try another title, message, task, project, or type.',
          theme: widget.theme,
        )
      else if (stackEnabled) ...[
        _JsonStackNotificationHeader(
          theme: widget.theme,
          totalCount: source.length,
          visibleCount: notifications.length,
          unreadCount: unreadTotal,
          latestTime: source.isEmpty ? null : source.first.createdAt,
          onMarkAll: unreadTotal > 0 ? _markAllUnreadAsRead : null,
        ),
        const SizedBox(height: 12),
        _JsonNotificationStackFilterBar(
          theme: widget.theme,
          selected: _filter,
          total: runtimeScoped.length,
          unread: runtimeScoped.where((item) => !item.isRead).length,
          taskCount: runtimeScoped.where(_jsonIsTaskNotification).length,
          meetingCount: runtimeScoped.where((item) => item.isMeetingInvite).length,
          mentionCount: runtimeScoped.where(_jsonIsMentionNotification).length,
          onChanged: (value) {
            HapticFeedback.selectionClick();
            setState(() {
              _filter = value;
              _viewMode = _JsonNotificationViewMode.stack;
              _deckExpanded = false;
              _showExpandedRows = false;
              _deckController.value = 0;
            });
          },
        ),
        const SizedBox(height: 12),
        _JsonNotificationModeSelector(
          theme: widget.theme,
          selected: _viewMode,
          visibleCount: notifications.length,
          unreadCount: unreadVisible,
          onSelected: _setMode,
        ),
        const SizedBox(height: 14),
        _JsonStackedNotificationDeck(
          entries: deckItems,
          totalCount: notifications.length,
          controller: _deckController,
          theme: widget.theme,
          onToggle: _toggleDeck,
          onTapNotification: _handleNotificationTap,
          onAction: _handleNotificationAction,
        ),
        if (_showExpandedRows && expandedRows.isNotEmpty) ...[
          const SizedBox(height: 14),
          ..._jsonGroupedExpandedRows(expandedRows).map((row) {
            if (row.label != null) {
              return _JsonNotificationGroupHeader(theme: widget.theme, label: row.label!);
            }
            final notification = row.notification!;
            return _JsonExpandedNotificationCard(
              notification: notification,
              theme: widget.theme,
              onTap: () => _handleNotificationTap(notification),
              onAction: () => _handleNotificationAction(notification),
            );
          }),
        ],
        if (_showExpandedRows && notifications.length <= deckItems.length)
          _JsonStackFooterHint(theme: widget.theme, message: 'All visible notifications are inside the stack.'),
      ] else
        ...notifications.map(_legacyNotificationListItem),
    ];

    return widget.embedded ? Column(children: children) : ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(widget.theme.padding), children: children);
  }

  Widget _legacyNotificationListItem(AppNotification item) {
    return _SectionResultBadge(
      theme: widget.theme,
      label: 'Inbox section',
      icon: Icons.notifications_rounded,
      visible: _showSourceBadges(embedded: widget.embedded, query: _normalizeSearchQuery(widget.embedded ? widget.runtimeSearchQuery : _query), filter: widget.runtimeContentFilter),
      child: _Surface(
        theme: widget.theme,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: item.isRead ? widget.theme.border : widget.theme.accent.withOpacity(.12),
              child: Icon(item.isRead ? Icons.done_rounded : Icons.notifications_active_rounded, color: item.isRead ? widget.theme.textSecondary : widget.theme.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 4),
                Text(item.message, style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
                const SizedBox(height: 6),
                Text(DateText.compact(item.createdAt), style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 11)),
              ]),
            ),
            if (!item.isRead)
              TextButton(
                onPressed: () => _handleNotificationTap(item),
                child: Text(item.hasActionUrl ? ((item.actionLabel ?? '').trim().isEmpty ? 'Join' : item.actionLabel!.trim()) : 'Read'),
              ),
          ],
        ),
      ),
    );
  }

  void _markAllUnreadAsRead() {
    HapticFeedback.mediumImpact();
    for (final notification in widget.state.myNotifications.where((item) => !item.isRead)) {
      AndroidAlertNotificationService.acceptLoopingAlert(notification.notificationId);
    }
    ref.read(workspaceProvider.notifier).markAllMyNotificationsRead();
  }

  void _handleNotificationTap(AppNotification notification) {
    HapticFeedback.selectionClick();
    if (!notification.isRead) {
      AndroidAlertNotificationService.acceptLoopingAlert(notification.notificationId);
      ref.read(workspaceProvider.notifier).markNotificationRead(notification.notificationId);
    }
  }

  Future<void> _handleNotificationAction(AppNotification notification) async {
    AndroidAlertNotificationService.acceptLoopingAlert(notification.notificationId);
    ref.read(workspaceProvider.notifier).markNotificationRead(notification.notificationId);
    final uri = _safeExternalUri(notification.actionUrl);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  List<_JsonNotificationGroupRow> _jsonGroupedExpandedRows(List<AppNotification> source) {
    final rows = <_JsonNotificationGroupRow>[];
    String? lastGroup;
    for (final notification in source) {
      final group = _jsonNotificationGroupLabel(notification.createdAt);
      if (group != lastGroup) {
        rows.add(_JsonNotificationGroupRow.header(group));
        lastGroup = group;
      }
      rows.add(_JsonNotificationGroupRow.card(notification));
    }
    return rows;
  }
}

List<AppNotification> _jsonNotificationFilter(List<AppNotification> source, String filter) {
  switch (filter) {
    case 'Unread':
      return source.where((item) => !item.isRead).toList(growable: false);
    case 'Tasks':
      return source.where(_jsonIsTaskNotification).toList(growable: false);
    case 'Meetings':
      return source.where((item) => item.isMeetingInvite).toList(growable: false);
    case 'Mentions':
      return source.where(_jsonIsMentionNotification).toList(growable: false);
    default:
      return source;
  }
}

bool _jsonIsTaskNotification(AppNotification item) {
  final normalized = item.type.trim().toLowerCase();
  return item.taskId != null ||
      normalized.contains('task') ||
      normalized.contains('assign') ||
      normalized.contains('deadline') ||
      normalized.contains('status');
}

bool _jsonIsMentionNotification(AppNotification item) {
  final text = '${item.type} ${item.title} ${item.message}'.toLowerCase();
  return text.contains('mention') || text.contains('@');
}

String _jsonNotificationGroupLabel(DateTime createdAt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final itemDay = DateTime(createdAt.year, createdAt.month, createdAt.day);
  if (itemDay == today) return 'New today';
  if (itemDay == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return 'Earlier';
}

String _jsonNotificationTimeText(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

class _JsonStackNotificationHeader extends StatelessWidget {
  const _JsonStackNotificationHeader({
    required this.theme,
    required this.totalCount,
    required this.visibleCount,
    required this.unreadCount,
    required this.latestTime,
    required this.onMarkAll,
  });

  final _UiTheme theme;
  final int totalCount;
  final int visibleCount;
  final int unreadCount;
  final DateTime? latestTime;
  final VoidCallback? onMarkAll;

  @override
  Widget build(BuildContext context) {
    final active = unreadCount > 0;
    final accent = active ? const Color(0xFFF59E0B) : theme.accent;
    return Dismissible(
      key: const ValueKey('json_notification_stack_header_swipe'),
      direction: onMarkAll == null ? DismissDirection.none : DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        onMarkAll?.call();
        return false;
      },
      background: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: const Color(0xFF18AD86), borderRadius: BorderRadius.circular(theme.radius + 8)),
        child: const Row(children: [
          Icon(Icons.done_all_rounded, color: Colors.white),
          SizedBox(width: 8),
          Text('Accept all', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ]),
      ),
      child: _Surface(
        theme: theme,
        child: Row(
          children: [
            _JsonHeaderBell(active: active, color: accent, theme: theme),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(active ? '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}' : 'No unread alerts', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 4),
                Text('${visibleCount == totalCount ? totalCount : '$visibleCount / $totalCount'} visible • Latest ${latestTime == null ? '—' : _jsonNotificationTimeText(latestTime!)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
                if (active) ...[
                  const SizedBox(height: 6),
                  Text('Tap the stack to expand. Swipe this header right to accept all unread alerts.', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary.withOpacity(.78), fontWeight: FontWeight.w700, fontSize: 11.5, height: 1.2)),
                ],
              ]),
            ),
            if (onMarkAll != null) ...[
              const SizedBox(width: 8),
              IconButton(tooltip: 'Accept all', onPressed: onMarkAll, icon: Icon(Icons.done_all_rounded, color: theme.accent)),
            ],
          ],
        ),
      ),
    );
  }
}

class _JsonHeaderBell extends StatelessWidget {
  const _JsonHeaderBell({required this.active, required this.color, required this.theme});

  final bool active;
  final Color color;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: active ? 1.07 : 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(width: 58, height: 58, decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(22)), child: Icon(active ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, color: color, size: 30)),
    );
  }
}

class _JsonNotificationStackFilterBar extends StatelessWidget {
  const _JsonNotificationStackFilterBar({
    required this.theme,
    required this.selected,
    required this.total,
    required this.unread,
    required this.taskCount,
    required this.meetingCount,
    required this.mentionCount,
    required this.onChanged,
  });

  final _UiTheme theme;
  final String selected;
  final int total;
  final int unread;
  final int taskCount;
  final int meetingCount;
  final int mentionCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final filters = <({String label, int count, IconData icon})>[
      (label: 'All', count: total, icon: Icons.layers_rounded),
      (label: 'Unread', count: unread, icon: Icons.mark_email_unread_rounded),
      (label: 'Tasks', count: taskCount, icon: Icons.task_alt_rounded),
      (label: 'Meetings', count: meetingCount, icon: Icons.video_call_rounded),
      (label: 'Mentions', count: mentionCount, icon: Icons.alternate_email_rounded),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(children: filters.map((item) {
        final active = selected == item.label;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            selected: active,
            onSelected: (_) => onChanged(item.label),
            avatar: Icon(item.icon, size: 16, color: active ? Colors.white : theme.accent),
            label: Text('${item.label} ${item.count}'),
            selectedColor: theme.accent,
            backgroundColor: theme.surface,
            side: BorderSide(color: active ? theme.accent : theme.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            labelStyle: TextStyle(color: active ? Colors.white : theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 12),
          ),
        );
      }).toList()),
    );
  }
}

class _JsonNotificationModeSelector extends StatelessWidget {
  const _JsonNotificationModeSelector({required this.theme, required this.selected, required this.visibleCount, required this.unreadCount, required this.onSelected});

  final _UiTheme theme;
  final _JsonNotificationViewMode selected;
  final int visibleCount;
  final int unreadCount;
  final ValueChanged<_JsonNotificationViewMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: theme.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 18, offset: const Offset(0, 9))]),
      child: Row(children: [
        Expanded(child: _JsonModePill(label: 'Stack', count: visibleCount, icon: Icons.style_rounded, selected: selected == _JsonNotificationViewMode.stack, theme: theme, onTap: () => onSelected(_JsonNotificationViewMode.stack))),
        Expanded(child: _JsonModePill(label: 'Expanded', count: unreadCount, icon: Icons.format_list_bulleted_rounded, selected: selected == _JsonNotificationViewMode.expanded, theme: theme, onTap: () => onSelected(_JsonNotificationViewMode.expanded))),
      ]),
    );
  }
}

class _JsonModePill extends StatelessWidget {
  const _JsonModePill({required this.label, required this.count, required this.icon, required this.selected, required this.theme, required this.onTap});

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final _UiTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : theme.textSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: selected ? theme.accent : Colors.transparent, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: fg, size: 17),
          const SizedBox(width: 6),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12.5))),
          const SizedBox(width: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: selected ? Colors.white.withOpacity(.18) : theme.background, borderRadius: BorderRadius.circular(999)), child: Text('$count', style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 10.5))),
        ]),
      ),
    );
  }
}

class _JsonStackedNotificationDeck extends StatelessWidget {
  const _JsonStackedNotificationDeck({required this.entries, required this.totalCount, required this.controller, required this.theme, required this.onToggle, required this.onTapNotification, required this.onAction});

  final List<AppNotification> entries;
  final int totalCount;
  final AnimationController controller;
  final _UiTheme theme;
  final VoidCallback onToggle;
  final ValueChanged<AppNotification> onTapNotification;
  final ValueChanged<AppNotification> onAction;

  @override
  Widget build(BuildContext context) {
    final extraCount = math.max(0, totalCount - entries.length);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final progress = Curves.easeOutCubic.transform(controller.value);
          final collapsedHeight = entries.length <= 1 ? 128.0 : 182.0;
          final expandedHeight = entries.length * 132.0 + 52.0;
          final height = collapsedHeight + ((expandedHeight - collapsedHeight) * progress);
          final cardCollapsed = progress < .92;
          return SizedBox(
            height: height,
            child: RepaintBoundary(
              child: Stack(clipBehavior: Clip.none, children: [
                for (var i = entries.length - 1; i >= 0; i--)
                  _JsonDeckCardPosition(
                    index: i,
                    controller: controller,
                    child: _JsonDeckNotificationCard(
                      notification: entries[i],
                      theme: theme,
                      collapsedGetter: () => cardCollapsed,
                      isTop: i == 0,
                      extraCount: extraCount,
                      onTap: () {
                        if (controller.value > .75) {
                          onTapNotification(entries[i]);
                        } else {
                          onToggle();
                        }
                      },
                      onAction: () => onAction(entries[i]),
                    ),
                  ),
                _JsonCollapseChipPositioned(controller: controller, theme: theme, onTap: onToggle),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _JsonDeckCardPosition extends AnimatedWidget {
  const _JsonDeckCardPosition({required this.index, required Animation<double> controller, required this.child}) : super(listenable: controller);

  final int index;
  final Widget child;

  Animation<double> get _controller => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    final progress = Curves.easeOutCubic.transform(_controller.value);
    final expandedTop = index * 132.0;
    final collapsedTop = index * 16.0;
    final top = collapsedTop + ((expandedTop - collapsedTop) * progress);
    final collapsedScale = 1.0 - (index * .04);
    final scale = collapsedScale + ((1.0 - collapsedScale) * progress);
    final collapsedSideInset = index * 7.0;
    final sideInset = collapsedSideInset * (1 - progress);
    return Positioned(left: sideInset, right: sideInset, top: top, child: Transform.scale(scale: scale, alignment: Alignment.topCenter, child: child));
  }
}

class _JsonDeckNotificationCard extends StatelessWidget {
  const _JsonDeckNotificationCard({required this.notification, required this.theme, required this.collapsedGetter, required this.isTop, required this.extraCount, required this.onTap, required this.onAction});

  final AppNotification notification;
  final _UiTheme theme;
  final bool Function() collapsedGetter;
  final bool isTop;
  final int extraCount;
  final VoidCallback onTap;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final collapsed = collapsedGetter();
    final type = _JsonNotificationVisualType.from(notification, theme);
    final accent = type.color;
    return SizedBox(
      height: 118,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            height: 118,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: notification.isRead ? theme.border.withOpacity(.74) : accent, width: notification.isRead ? 1 : 1.35), boxShadow: [BoxShadow(color: Colors.black.withOpacity(isTop ? .055 : .04), blurRadius: isTop ? 16 : 11, offset: Offset(0, isTop ? 8 : 5))]),
            child: Row(children: [
              _JsonNotificationIconBubble(type: type, unread: !notification.isRead, theme: theme),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _JsonNotificationTag(type: type, theme: theme),
                  const SizedBox(width: 8),
                  Expanded(child: Text(collapsed && !isTop ? 'Notification' : notification.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontSize: 14.5, fontWeight: notification.isRead ? FontWeight.w700 : FontWeight.w900))),
                ]),
                const SizedBox(height: 7),
                Text(collapsed && !isTop ? 'Tap to expand the stack' : notification.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontSize: 12.2, height: 1.2, fontWeight: FontWeight.w700)),
                const Spacer(),
                Row(children: [
                  Icon(Icons.schedule_rounded, size: 13, color: theme.textSecondary.withOpacity(.82)),
                  const SizedBox(width: 4),
                  Expanded(child: Text('${_jsonNotificationTimeText(notification.createdAt)} • ${DateText.compact(notification.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary.withOpacity(.82), fontSize: 10.8, fontWeight: FontWeight.w800))),
                ]),
              ])),
              if (isTop) ...[
                const SizedBox(width: 8),
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  InkWell(
                    onTap: notification.hasActionUrl ? onAction : onTap,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(width: 48, height: 48, decoration: BoxDecoration(color: accent.withOpacity(.13), shape: BoxShape.circle), child: Icon(collapsed ? Icons.keyboard_arrow_down_rounded : (notification.hasActionUrl ? Icons.open_in_new_rounded : Icons.check_rounded), color: accent, size: 24)),
                  ),
                  if (collapsed && extraCount > 0) ...[
                    const SizedBox(height: 6),
                    Container(constraints: const BoxConstraints(minWidth: 48), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: accent.withOpacity(.10), borderRadius: BorderRadius.circular(99)), alignment: Alignment.center, child: Text('+$extraCount', style: TextStyle(color: accent, fontSize: 10.5, fontWeight: FontWeight.w900))),
                  ],
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _JsonCollapseChipPositioned extends AnimatedWidget {
  const _JsonCollapseChipPositioned({required Animation<double> controller, required this.theme, required this.onTap}) : super(listenable: controller);

  final _UiTheme theme;
  final VoidCallback onTap;

  Animation<double> get _controller => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    final progress = Curves.easeOutCubic.transform(_controller.value);
    return Positioned(right: 12, bottom: 0, child: IgnorePointer(ignoring: progress < .75, child: Opacity(opacity: progress > .75 ? 1 : 0, child: _JsonCollapseChip(theme: theme, onTap: onTap))));
  }
}

class _JsonCollapseChip extends StatelessWidget {
  const _JsonCollapseChip({required this.theme, required this.onTap});

  final _UiTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(22), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: theme.accent, borderRadius: BorderRadius.circular(22)), child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Text('Collapse', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900)),
      SizedBox(width: 4),
      Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 18),
    ])));
  }
}

class _JsonExpandedNotificationCard extends StatelessWidget {
  const _JsonExpandedNotificationCard({required this.notification, required this.theme, required this.onTap, required this.onAction});

  final AppNotification notification;
  final _UiTheme theme;
  final VoidCallback onTap;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final type = _JsonNotificationVisualType.from(notification, theme);
    final accent = type.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey<String>('json_notification_${notification.notificationId}'),
        direction: notification.isRead ? DismissDirection.none : DismissDirection.startToEnd,
        confirmDismiss: (_) async {
          onTap();
          return false;
        },
        background: Container(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 20), decoration: BoxDecoration(color: const Color(0xFF18AD86), borderRadius: BorderRadius.circular(24)), child: const Row(children: [
          Icon(Icons.done_rounded, color: Colors.white),
          SizedBox(width: 8),
          Text('Accept', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ])),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: notification.isRead ? theme.border : accent.withOpacity(.86)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 14, offset: const Offset(0, 7))]),
              child: Row(children: [
                _JsonNotificationIconBubble(type: type, unread: !notification.isRead, theme: theme),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    _JsonNotificationTag(type: type, theme: theme),
                    const SizedBox(width: 8),
                    Expanded(child: Text(notification.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: notification.isRead ? FontWeight.w700 : FontWeight.w900, fontSize: 14.5))),
                  ]),
                  const SizedBox(height: 6),
                  Text(notification.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12.2, height: 1.2)),
                  const SizedBox(height: 9),
                  Row(children: [
                    Icon(Icons.schedule_rounded, size: 13, color: theme.textSecondary.withOpacity(.84)),
                    const SizedBox(width: 4),
                    Expanded(child: Text('${_jsonNotificationTimeText(notification.createdAt)} • ${DateText.compact(notification.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary.withOpacity(.84), fontWeight: FontWeight.w800, fontSize: 10.8))),
                  ]),
                ])),
                const SizedBox(width: 8),
                if (notification.hasActionUrl)
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, visualDensity: VisualDensity.compact, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                    onPressed: onAction,
                    child: Text((notification.actionLabel ?? '').trim().isEmpty ? 'Join' : notification.actionLabel!.trim()),
                  )
                else if (!notification.isRead)
                  Icon(Icons.swipe_right_alt_rounded, color: accent),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _JsonStackFooterHint extends StatelessWidget {
  const _JsonStackFooterHint({required this.theme, required this.message});

  final _UiTheme theme;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: theme.surfaceAlt.withOpacity(.72), borderRadius: BorderRadius.circular(18), border: Border.all(color: theme.border)), child: Row(children: [
      Icon(Icons.info_outline_rounded, color: theme.textSecondary, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12))),
    ]));
  }
}

class _JsonNotificationGroupHeader extends StatelessWidget {
  const _JsonNotificationGroupHeader({required this.theme, required this.label});

  final _UiTheme theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.fromLTRB(4, 16, 4, 8), child: Text(label, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 12.5)));
  }
}

class _JsonNotificationIconBubble extends StatelessWidget {
  const _JsonNotificationIconBubble({required this.type, required this.unread, required this.theme});

  final _JsonNotificationVisualType type;
  final bool unread;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Container(width: 46, height: 46, decoration: BoxDecoration(color: type.color.withOpacity(unread ? .14 : .08), borderRadius: BorderRadius.circular(18)), child: Icon(type.icon, color: unread ? type.color : theme.textSecondary, size: 23)),
      if (unread)
        Positioned(right: -2, top: -2, child: Container(width: 11, height: 11, decoration: BoxDecoration(color: type.color, shape: BoxShape.circle, border: Border.all(color: theme.surface, width: 2)))),
    ]);
  }
}

class _JsonNotificationTag extends StatelessWidget {
  const _JsonNotificationTag({required this.type, required this.theme});

  final _JsonNotificationVisualType type;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: type.color.withOpacity(.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: type.color.withOpacity(.18))), child: Text(type.label, style: TextStyle(color: type.color, fontWeight: FontWeight.w900, fontSize: 10.5)));
  }
}

class _JsonNotificationVisualType {
  const _JsonNotificationVisualType({required this.color, required this.icon, required this.label});

  final Color color;
  final IconData icon;
  final String label;

  static _JsonNotificationVisualType from(AppNotification notification, _UiTheme theme) {
    final text = '${notification.type} ${notification.title} ${notification.message}'.toLowerCase();
    if (notification.isMeetingInvite) {
      return const _JsonNotificationVisualType(color: Color(0xFF5577F2), icon: Icons.video_call_rounded, label: 'Meeting');
    }
    if (text.contains('deadline') || text.contains('overdue') || text.contains('urgent')) {
      return const _JsonNotificationVisualType(color: Color(0xFFC85F55), icon: Icons.warning_amber_rounded, label: 'Urgent');
    }
    if (text.contains('task') || notification.taskId != null || text.contains('assign')) {
      return _JsonNotificationVisualType(color: theme.accent, icon: Icons.task_alt_rounded, label: 'Task');
    }
    if (text.contains('mention') || text.contains('@')) {
      return const _JsonNotificationVisualType(color: Color(0xFFF59E0B), icon: Icons.alternate_email_rounded, label: 'Mention');
    }
    return const _JsonNotificationVisualType(color: Color(0xFF18AD86), icon: Icons.notifications_active_rounded, label: 'Update');
  }
}

class _JsonNotificationGroupRow {
  const _JsonNotificationGroupRow._({this.label, this.notification});

  factory _JsonNotificationGroupRow.header(String label) => _JsonNotificationGroupRow._(label: label);
  factory _JsonNotificationGroupRow.card(AppNotification notification) => _JsonNotificationGroupRow._(notification: notification);

  final String? label;
  final AppNotification? notification;
}


class _ProfileJsonScreen extends ConsumerWidget {
  const _ProfileJsonScreen({required this.state, required this.data, required this.theme, this.embedded = false, this.previewMode = false});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool embedded;
  final bool previewMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = state.currentMember;
    final alertConfig = state.mobileUiConfig.notificationAlertConfig;
    final hasExplicitNotificationSettings = _containsNotificationAlertSettingsNode(data);
    final forceNotificationInsideSettings = data['notificationSettingsPlacement']?.toString() == 'insideSettingsAccordion' || data['hideStandaloneNotificationSettings'] == true;
    final layoutOrder = _stringList(data['layoutOrder'], fallback: const <String>[]);
    final useSettingsAccordionLayout = forceNotificationInsideSettings ||
        data['settingsPlacement']?.toString() == 'afterProfileActionsBeforeProfileInfo' ||
        layoutOrder.contains('settingsAccordion') ||
        (_num(data['version'], 0) >= 159);
    final showNotificationSettings = alertConfig['enabled'] != false &&
        alertConfig['showInProfile'] != false &&
        (forceNotificationInsideSettings || useSettingsAccordionLayout || !hasExplicitNotificationSettings);
    final activeProjects = state.visibleProjects.where((project) => project.isActiveWork).length;
    final openTasks = state.visibleTasks.where((task) => task.status != TaskStatus.completed).length;
    final unread = state.myUnreadNotificationCount;
    final onlineTeam = state.members.where((teamMember) => teamMember.isOnline).length;

    final body = <Widget>[
      if (!embedded && data['hideTitle'] != true)
        _ScreenTitle(
          title: _textOf(data, 'title', 'Profile'),
          subtitle: 'Private employee workspace profile',
        ),
      _ProfileActionsCard(state: state, theme: theme, previewMode: previewMode, showNotificationSettings: showNotificationSettings),
      if (useSettingsAccordionLayout) ...[
        _ProfileInfoSection(
          theme: theme,
          title: 'Assigned scope',
          items: <_ProfileInfoItem>[
            _ProfileInfoItem(Icons.folder_copy_rounded, 'Projects', '${state.visibleProjects.length} visible project(s)'),
            _ProfileInfoItem(Icons.task_rounded, 'Tasks', '${state.visibleTasks.length} assigned task(s)'),
            _ProfileInfoItem(Icons.group_rounded, 'Teams', '${member.teamIds.length} joined team(s)'),
            _ProfileInfoItem(Icons.verified_user_rounded, 'Access', 'Project-scoped private data'),
          ],
        ),
        _ProfileInfoSection(
          theme: theme,
          title: 'Role',
          items: <_ProfileInfoItem>[
            _ProfileInfoItem(Icons.badge_rounded, 'Role', member.role.label),
            _ProfileInfoItem(Icons.apartment_rounded, 'Department', member.effectiveDepartment),
            _ProfileInfoItem(Icons.work_rounded, 'Job title', member.effectiveJobTitle),
          ],
        ),
        _ProfileInfoSection(
          theme: theme,
          title: 'Company',
          items: <_ProfileInfoItem>[
            _ProfileInfoItem(Icons.business_rounded, 'Company', state.company.name.trim().isEmpty ? 'Company Workspace' : state.company.name),
            _ProfileInfoItem(Icons.location_on_rounded, 'Location', member.location.trim().isEmpty ? 'Remote' : member.location),
            _ProfileInfoItem(Icons.verified_user_rounded, 'Account status', member.status),
          ],
        ),
      ] else ...[
        _ProfileStatsGrid(
          theme: theme,
          items: <_ProfileStatItem>[
            _ProfileStatItem('Projects', '$activeProjects', Icons.folder_rounded, theme.accent),
            _ProfileStatItem('Open tasks', '$openTasks', Icons.task_alt_rounded, const Color(0xFF2563EB)),
            _ProfileStatItem('Inbox', '$unread', Icons.notifications_rounded, const Color(0xFFF59E0B)),
            _ProfileStatItem('Team online', '$onlineTeam', Icons.groups_rounded, const Color(0xFF16A34A)),
          ],
        ),
        _ProfileInfoSection(
          theme: theme,
          title: 'Work profile',
          items: <_ProfileInfoItem>[
            _ProfileInfoItem(Icons.badge_rounded, 'Role', member.role.label),
            _ProfileInfoItem(Icons.apartment_rounded, 'Department', member.effectiveDepartment),
            _ProfileInfoItem(Icons.work_rounded, 'Job title', member.effectiveJobTitle),
            _ProfileInfoItem(Icons.location_on_rounded, 'Location', member.location.trim().isEmpty ? 'Remote' : member.location),
          ],
        ),
        _ProfileInfoSection(
          theme: theme,
          title: 'Assigned scope',
          items: <_ProfileInfoItem>[
            _ProfileInfoItem(Icons.folder_copy_rounded, 'Projects', '${state.visibleProjects.length} visible project(s)'),
            _ProfileInfoItem(Icons.task_rounded, 'Tasks', '${state.visibleTasks.length} assigned task(s)'),
            _ProfileInfoItem(Icons.group_rounded, 'Teams', '${member.teamIds.length} joined team(s)'),
            _ProfileInfoItem(Icons.verified_user_rounded, 'Access', 'Project-scoped private data'),
          ],
        ),
      ],
    ];
    return embedded ? Column(children: body) : ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(theme.padding), children: body);
  }
}

class _ProfileStatItem {
  const _ProfileStatItem(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _ProfileStatsGrid extends StatelessWidget {
  const _ProfileStatsGrid({required this.theme, required this.items});

  final _UiTheme theme;
  final List<_ProfileStatItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(builder: (context, constraints) {
        const gap = 10.0;
        final tileWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: items
              .map((item) => SizedBox(
                    width: tileWidth,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: item.color.withOpacity(.14)),
                        boxShadow: [BoxShadow(color: item.color.withOpacity(.045), blurRadius: 18, offset: const Offset(0, 8))],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: item.color.withOpacity(.10), borderRadius: BorderRadius.circular(16)),
                            child: Icon(item.icon, size: 19, color: item.color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(item.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 20)),
                              const SizedBox(height: 2),
                              Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 11)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        );
      }),
    );
  }
}

class _ProfileInfoItem {
  const _ProfileInfoItem(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _ProfileInfoSection extends StatelessWidget {
  const _ProfileInfoSection({required this.theme, required this.title, required this.items});

  final _UiTheme theme;
  final String title;
  final List<_ProfileInfoItem> items;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: theme.accent.withOpacity(.08), borderRadius: BorderRadius.circular(14)),
                      child: Icon(item.icon, size: 18, color: theme.accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.label, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(item.value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 13)),
                      ]),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}


class _PlainSettingsBadge extends StatelessWidget {
  const _PlainSettingsBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      constraints: const BoxConstraints(minWidth: 28),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(.24)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11, height: 1)),
    );
  }
}

class _NotificationAlertSettingsJsonCard extends ConsumerStatefulWidget {
  const _NotificationAlertSettingsJsonCard({required this.theme, required this.alertConfig, required this.soundOptions, required this.previewMode, this.embedded = false});

  final _UiTheme theme;
  final Map<String, dynamic> alertConfig;
  final Map<String, dynamic> soundOptions;
  final bool previewMode;
  final bool embedded;

  @override
  ConsumerState<_NotificationAlertSettingsJsonCard> createState() => _NotificationAlertSettingsJsonCardState();
}

class _NotificationAlertSettingsJsonCardState extends ConsumerState<_NotificationAlertSettingsJsonCard> {
  String _selectedSound = AndroidAlertNotificationService.defaultAlertSoundName;
  bool _assistantVoice = true;
  bool _notificationsEnabled = false;
  bool _loading = true;
  bool _saving = false;
  late final TextEditingController _windowDaysController;
  late final TextEditingController _windowHoursController;
  String _windowMode = 'currentMonth';
  String _windowSeed = '';

  @override
  void initState() {
    super.initState();
    _windowDaysController = TextEditingController();
    _windowHoursController = TextEditingController();
    _loadPreferences();
  }

  @override
  void dispose() {
    _windowDaysController.dispose();
    _windowHoursController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final sound = await AndroidAlertNotificationService.getPreferredAlertSound();
    final assistantVoice = await AndroidAlertNotificationService.getAssistantVoiceEnabled();
    final notificationsEnabled = await AndroidAlertNotificationService.areNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _selectedSound = sound;
      _assistantVoice = assistantVoice;
      _notificationsEnabled = notificationsEnabled;
      _loading = false;
    });
  }

  Future<void> _enableNotifications() async {
    setState(() => _saving = true);
    final enabled = await AndroidAlertNotificationService.requestPermissionIfNeeded(force: true);
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = enabled;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(enabled ? 'Android notifications enabled.' : 'Notification permission is still off. Enable it from Android App Settings.')),
    );
  }

  Future<void> _saveSound(String soundName) async {
    setState(() {
      _selectedSound = soundName;
      _saving = true;
    });
    final saved = await AndroidAlertNotificationService.setPreferredAlertSound(soundName);
    if (!mounted) return;
    setState(() {
      _selectedSound = saved;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Notification sound set to ${AndroidAlertNotificationService.labelForSound(saved)}.')));
  }

  Future<void> _saveAssistantVoice(bool enabled) async {
    setState(() {
      _assistantVoice = enabled;
      _saving = true;
    });
    final saved = await AndroidAlertNotificationService.setAssistantVoiceEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _assistantVoice = saved;
      _saving = false;
    });
  }

  Future<void> _testSound() async {
    final text = (widget.alertConfig['assistantText']?.toString().trim().isNotEmpty == true)
        ? widget.alertConfig['assistantText'].toString().trim()
        : 'You are assigned a new task. Please accept the notification.';
    setState(() => _saving = true);
    final saved = await AndroidAlertNotificationService.setPreferredAlertSound(_selectedSound);
    final shown = await AndroidAlertNotificationService.testSelectedAlertSound(
      soundName: saved,
      assistantVoice: _assistantVoice,
      assistantText: text,
    );
    final enabled = await AndroidAlertNotificationService.areNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _selectedSound = saved;
      _notificationsEnabled = enabled;
      _saving = false;
    });
    if (!shown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification permission is required before the test alert can show.')),
      );
    }
  }

  void _syncWindowFromState(WorkspaceState state) {
    final prefs = state.user.notificationPreferences;
    final source = prefs.isEmpty ? state.effectiveNotificationDisplayConfig : prefs;
    final mode = _notificationWindowModeForRenderer(source);
    final days = _notificationWindowIntForRenderer(source, const <String>['displayWindowDays', 'notificationDisplayDays', 'visibleDays'], fallback: 31).clamp(1, 3660).toInt();
    final hours = _notificationWindowIntForRenderer(source, const <String>['displayWindowHours', 'notificationDisplayHours', 'visibleHours'], fallback: 24).clamp(1, 24 * 3660).toInt();
    final seed = '$mode:$days:$hours:${prefs.hashCode}';
    if (_windowSeed == seed) return;
    _windowSeed = seed;
    _windowMode = mode;
    _windowDaysController.text = '$days';
    _windowHoursController.text = '$hours';
  }

  Future<void> _saveWindowPreference() async {
    final days = int.tryParse(_windowDaysController.text.trim()) ?? 31;
    final hours = int.tryParse(_windowHoursController.text.trim()) ?? 24;
    ref.read(workspaceProvider.notifier).setMyNotificationDisplayWindow(
          mode: _windowMode,
          days: days,
          hours: hours,
        );
    await AndroidAlertNotificationService.setNotificationDisplayWindowPreference(
      mode: _windowMode,
      days: days,
      hours: hours,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Notification window saved: ${_notificationWindowLabelForRenderer(_windowMode, days: days, hours: hours)}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = AndroidAlertNotificationService.alertSoundOptions;
    final selected = options.firstWhere((option) => option.name == _selectedSound, orElse: () => options.first);
    final showTest = widget.alertConfig['showTestButton'] != false;
    final allowSelection = widget.alertConfig['allowUserSelection'] != false;
    final workspaceState = ref.watch(workspaceProvider);
    final adminConfig = workspaceState.effectiveNotificationAlertConfig;
    final allowUserWindow = _notificationWindowBoolForRenderer(adminConfig, const <String>['allowUserDisplayWindowSelection', 'allowUserNotificationWindow', 'allowUserDisplayWindow'], fallback: true);
    final hasUserWindowOverride = workspaceState.user.notificationPreferences.isNotEmpty;
    final adminMode = _notificationWindowModeForRenderer(adminConfig);
    final adminDays = _notificationWindowIntForRenderer(adminConfig, const <String>['displayWindowDays', 'notificationDisplayDays', 'visibleDays'], fallback: 31);
    final adminHours = _notificationWindowIntForRenderer(adminConfig, const <String>['displayWindowHours', 'notificationDisplayHours', 'visibleHours'], fallback: 24);
    _syncWindowFromState(workspaceState);

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final actionButton = OutlinedButton(
          onPressed: _loading || _saving || _notificationsEnabled ? null : _enableNotifications,
          child: Text(_notificationsEnabled ? 'Enabled' : 'Enable'),
        );
        final permissionText = Text(
          _notificationsEnabled
              ? 'Android notifications enabled. Background and terminated alerts can show.'
              : 'Enable Android notifications once. Without this permission background and terminated alerts cannot appear.',
          maxLines: compact ? 4 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w800, fontSize: compact ? 11.5 : 12),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _PlainSettingsBadge(label: 'AL', color: widget.theme.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Notification alert settings',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w900, fontSize: compact ? 14 : 16),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(fit: BoxFit.scaleDown, child: _InfoTag(label: selected.label, color: widget.theme.accent, theme: widget.theme)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(compact ? 10 : 12),
              decoration: BoxDecoration(
                color: _notificationsEnabled ? const Color(0xFFEAFBF0) : const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: (_notificationsEnabled ? const Color(0xFF22A06B) : const Color(0xFFC08402)).withOpacity(.35)),
              ),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PlainSettingsBadge(label: _notificationsEnabled ? 'ON' : '!', color: _notificationsEnabled ? const Color(0xFF22A06B) : const Color(0xFFC08402)),
                            const SizedBox(width: 10),
                            Expanded(child: permissionText),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(alignment: Alignment.centerRight, child: actionButton),
                      ],
                    )
                  : Row(
                      children: [
                        _PlainSettingsBadge(label: _notificationsEnabled ? 'ON' : '!', color: _notificationsEnabled ? const Color(0xFF22A06B) : const Color(0xFFC08402)),
                        const SizedBox(width: 10),
                        Expanded(child: permissionText),
                        const SizedBox(width: 8),
                        actionButton,
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: _selectedSound,
              decoration: const InputDecoration(labelText: 'Preferred alert sound'),
              items: options
                  .map((option) => DropdownMenuItem<String>(
                        value: option.name,
                        child: Text(widget.soundOptions[option.name]?.toString() ?? option.label, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _loading || _saving || !allowSelection ? null : (value) {
                if (value != null) _saveSound(value);
              },
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _assistantVoice,
              title: const Text('Assistant voice'),
              onChanged: _loading || _saving ? null : _saveAssistantVoice,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(compact ? 10 : 12),
              decoration: BoxDecoration(
                color: widget.theme.accent.withOpacity(.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: widget.theme.accent.withOpacity(.16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _PlainSettingsBadge(label: 'W', color: widget.theme.accent),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Notification display window', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w900))),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: _InfoTag(label: hasUserWindowOverride ? 'User set' : 'Default', color: hasUserWindowOverride ? const Color(0xFF22A06B) : widget.theme.accent, theme: widget.theme),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Company default: ${_notificationWindowLabelForRenderer(adminMode, days: adminDays, hours: adminHours)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _windowMode,
                    decoration: const InputDecoration(labelText: 'Show notifications for'),
                    items: const [
                      DropdownMenuItem(value: 'currentMonth', child: Text('Current month')),
                      DropdownMenuItem(value: 'customDays', child: Text('Last custom days')),
                      DropdownMenuItem(value: 'customHours', child: Text('Last custom hours')),
                      DropdownMenuItem(value: 'all', child: Text('All non-expired notifications')),
                    ],
                    onChanged: _loading || _saving || !allowUserWindow
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _windowMode = value);
                          },
                  ),
                  if (_windowMode == 'customDays') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _windowDaysController,
                      enabled: allowUserWindow && !_loading && !_saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Days'),
                    ),
                  ],
                  if (_windowMode == 'customHours') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _windowHoursController,
                      enabled: allowUserWindow && !_loading && !_saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Hours'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: OutlinedButton(
                        onPressed: _loading || _saving || !allowUserWindow ? null : _saveWindowPreference,
                        child: const Text('Save window'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showTest) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: OutlinedButton(
                    onPressed: _loading || _saving ? null : _testSound,
                    child: Text(_saving ? 'Saving...' : 'Test alert'),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );

    if (widget.embedded) return content;
    return _Surface(theme: widget.theme, child: content);
  }
}


String _notificationWindowModeForRenderer(Map<String, dynamic> config) {
  final raw = (config['displayWindowMode'] ?? config['notificationDisplayWindowMode'] ?? config['notificationHistoryMode'] ?? config['visibleWindowMode'] ?? 'currentMonth').toString();
  final normalized = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
  return switch (normalized) {
    'all' || 'forever' || 'unlimited' || 'none' => 'all',
    'customhours' || 'lasthours' || 'hours' || 'usersethours' => 'customHours',
    'customdays' || 'lastdays' || 'days' || 'usersetdays' || 'retentiondays' => 'customDays',
    _ => 'currentMonth',
  };
}

int _notificationWindowIntForRenderer(Map<String, dynamic> config, List<String> keys, {required int fallback}) {
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

bool _notificationWindowBoolForRenderer(Map<String, dynamic> config, List<String> keys, {required bool fallback}) {
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

String _notificationWindowLabelForRenderer(String mode, {required int days, required int hours}) {
  return switch (mode) {
    'all' => 'All non-expired notifications',
    'customHours' => 'Last $hours hours',
    'customDays' => 'Last $days days',
    _ => 'Current month',
  };
}

class _JsonColumn extends StatelessWidget {
  const _JsonColumn({required this.data, required this.state, required this.theme, required this.renderNode});
  final Map<String, dynamic> data;
  final WorkspaceState state;
  final _UiTheme theme;
  final Widget Function(BuildContext, WorkspaceState, dynamic, _UiTheme) renderNode;

  @override
  Widget build(BuildContext context) {
    if (_flag(data['visible'] ?? data['enabled'], fallback: true) == false) return const SizedBox.shrink();
    final children = _dedupeNotificationAlertSettingsNodes(_orderedItemsOf(data));
    final gap = _num(data['gap'] ?? data['spacing'] ?? data['itemSpacing'], 0).toDouble().clamp(0, 48).toDouble();
    final rendered = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rendered.add(renderNode(context, state, children[i], theme));
      if (gap > 0 && i != children.length - 1) rendered.add(SizedBox(height: gap));
    }
    return Padding(
      padding: _paddingOf(data['margin'], fallback: EdgeInsets.zero),
      child: Padding(
        padding: _paddingOf(data['padding'], fallback: EdgeInsets.zero),
        child: Column(
          crossAxisAlignment: _crossAxis(data['crossAxisAlignment'] ?? data['align']),
          mainAxisSize: _flag(data['min'], fallback: false) ? MainAxisSize.min : MainAxisSize.max,
          children: rendered,
        ),
      ),
    );
  }
}


class _SettingsListJson extends StatefulWidget {
  const _SettingsListJson({required this.data, required this.state, required this.theme, required this.renderNode});

  final Map<String, dynamic> data;
  final WorkspaceState state;
  final _UiTheme theme;
  final Widget Function(BuildContext, WorkspaceState, dynamic, _UiTheme) renderNode;

  @override
  State<_SettingsListJson> createState() => _SettingsListJsonState();
}

class _SettingsListJsonState extends State<_SettingsListJson> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    final collapsed = widget.data['collapsed'] == true;
    final expandedDefault = widget.data['expandedDefault'] == true || widget.data['defaultExpanded'] == true;
    _expanded = expandedDefault || !collapsed;
  }

  @override
  void didUpdateWidget(covariant _SettingsListJson oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data['id'] != widget.data['id']) {
      final collapsed = widget.data['collapsed'] == true;
      final expandedDefault = widget.data['expandedDefault'] == true || widget.data['defaultExpanded'] == true;
      _expanded = expandedDefault || !collapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = _dedupeNotificationAlertSettingsNodes(_orderedItemsOf(widget.data));
    final title = _textOf(widget.data, 'title', 'Settings');
    final subtitle = _textOf(widget.data, 'subtitle', 'Notification alert controls');
    return Padding(
      padding: _paddingOf(widget.data['margin'], fallback: const EdgeInsets.only(bottom: 12)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: widget.theme.background,
          borderRadius: BorderRadius.circular(widget.theme.radius + 2),
          border: Border.all(color: widget.theme.border),
        ),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(widget.theme.radius + 2),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      _PlainSettingsBadge(label: 'SET', color: widget.theme.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 11.5)),
                            ],
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? .5 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: Icon(Icons.keyboard_arrow_down_rounded, color: widget.theme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: children.isEmpty
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: widget.theme.surface, borderRadius: BorderRadius.circular(widget.theme.radius), border: Border.all(color: widget.theme.border)),
                        child: Text('No settings available.', style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
                      )
                    : Column(
                        children: children.map((item) {
                          final renderItem = item is Map
                              ? <String, dynamic>{...item.cast<String, dynamic>(), if (_isNotificationAlertSettingsNode(item)) 'embedded': true}
                              : item;
                          return widget.renderNode(context, widget.state, renderItem, widget.theme);
                        }).toList(),
                      ),
              ),
              crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

class _JsonRow extends StatelessWidget {
  const _JsonRow({required this.data, required this.state, required this.theme, required this.renderNode});
  final Map<String, dynamic> data;
  final WorkspaceState state;
  final _UiTheme theme;
  final Widget Function(BuildContext, WorkspaceState, dynamic, _UiTheme) renderNode;

  @override
  Widget build(BuildContext context) {
    if (_flag(data['visible'] ?? data['enabled'], fallback: true) == false) return const SizedBox.shrink();
    final children = _itemsOf(data);
    final gap = _num(data['gap'] ?? data['spacing'] ?? data['itemSpacing'], 10).toDouble().clamp(0, 48).toDouble();
    final wrap = _flag(data['wrap'] ?? data['responsive'] ?? data['overflowSafe'], fallback: false);
    final widgets = children.map((item) => renderNode(context, state, item, theme)).toList();
    return Padding(
      padding: _paddingOf(data['margin'], fallback: const EdgeInsets.only(bottom: 12)),
      child: Padding(
        padding: _paddingOf(data['padding'], fallback: EdgeInsets.zero),
        child: wrap
            ? Wrap(spacing: gap, runSpacing: gap, children: widgets)
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: widgets.map((child) => Expanded(child: child)).toList()),
      ),
    );
  }
}

class _JsonGrid extends StatelessWidget {
  const _JsonGrid({required this.data, required this.state, required this.theme, required this.renderNode});
  final Map<String, dynamic> data;
  final WorkspaceState state;
  final _UiTheme theme;
  final Widget Function(BuildContext, WorkspaceState, dynamic, _UiTheme) renderNode;

  @override
  Widget build(BuildContext context) {
    if (_flag(data['visible'] ?? data['enabled'], fallback: true) == false) return const SizedBox.shrink();
    final children = _itemsOf(data);
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
      final gap = _num(data['gap'] ?? data['spacing'] ?? data['runSpacing'], 10).toDouble().clamp(0, 48).toDouble();
      final jsonResponsiveGrid = _flag(data['responsive'] ?? data['adaptive'] ?? data['autoColumns'] ?? data['overflowSafe'], fallback: false);
      final explicitColumns = _num(data['columns'], jsonResponsiveGrid ? 0 : 2).round();
      final columns = explicitColumns > 0
          ? explicitColumns.clamp(1, _num(data['maxColumns'], 4).round().clamp(1, 6).toInt()).toInt()
          : _adaptiveJsonColumns(maxWidth, children.length, data);
      final width = columns <= 1 ? maxWidth : (maxWidth - (gap * (columns - 1))) / columns;
      return Padding(
        padding: _paddingOf(data['margin'], fallback: EdgeInsets.zero),
        child: Padding(
          padding: _paddingOf(data['padding'], fallback: EdgeInsets.zero),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: children.map((item) => SizedBox(width: width, child: renderNode(context, state, item, theme))).toList(),
          ),
        ),
      );
    });
  }
}

class _JsonText extends StatelessWidget {
  const _JsonText({required this.data, required this.theme, required this.type});
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final String type;

  @override
  Widget build(BuildContext context) {
    final size = _num(data['size'], type == 'title' ? 24 : type == 'subtitle' ? 13 : 15).toDouble().clamp(10, 42).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        data['text']?.toString() ?? data['title']?.toString() ?? '',
        style: TextStyle(
          color: _color(data['color']?.toString(), type == 'subtitle' ? theme.textSecondary : theme.textPrimary),
          fontSize: size,
          fontWeight: type == 'title' ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    );
  }
}



class _AuthFormJson extends ConsumerStatefulWidget {
  const _AuthFormJson({required this.data, required this.theme, required this.previewMode});

  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool previewMode;

  @override
  ConsumerState<_AuthFormJson> createState() => _AuthFormJsonState();
}

class _AuthFormJsonState extends ConsumerState<_AuthFormJson> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  late bool _signupMode;

  @override
  void initState() {
    super.initState();
    final mode = (widget.data['mode'] ?? widget.data['authMode'] ?? widget.data['initialMode'] ?? '').toString().toLowerCase();
    _signupMode = mode.contains('sign') || mode.contains('register');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final labels = _asMap(widget.data['labels']) ?? const <String, dynamic>{};
    final allowSignUp = _flag(widget.data['allowSignUp'], fallback: true);
    final allowPasswordReset = _flag(widget.data['allowPasswordReset'], fallback: true);
    final providers = _stringList(widget.data['providers'] ?? widget.data['socialProviders'] ?? widget.data['methods'], fallback: const <String>['google', 'apple', 'facebook'])
        .where((item) => _authProviderFromString(item) != null)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(theme.radius),
        border: Border.all(color: theme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (allowSignUp)
            _AuthModeToggleJson(
              theme: theme,
              signupMode: _signupMode,
              loginLabel: _jsonLabel(labels, 'loginTab', 'Login'),
              signupLabel: _jsonLabel(labels, 'signupTab', 'Sign Up'),
              onChanged: _loading ? null : (value) => setState(() => _signupMode = value),
            ),
          if (allowSignUp) const SizedBox(height: 18),
          Text(
            _signupMode ? _jsonLabel(labels, 'signupTitle', 'Create your workspace account') : _jsonLabel(labels, 'loginTitle', 'Welcome back'),
            style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            _signupMode ? _jsonLabel(labels, 'signupSubtitle', 'Create an account with Firebase Auth.') : _jsonLabel(labels, 'loginSubtitle', 'Sign in with Firebase Auth.'),
            style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, height: 1.35),
          ),
          const SizedBox(height: 18),
          if (_signupMode)
            _AuthTextFieldJson(controller: _name, theme: theme, label: _jsonLabel(labels, 'nameLabel', 'Full name'), icon: Icons.person_outline_rounded),
          _AuthTextFieldJson(controller: _email, theme: theme, label: _jsonLabel(labels, 'emailLabel', 'Email'), icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
          _AuthTextFieldJson(controller: _password, theme: theme, label: _jsonLabel(labels, 'passwordLabel', 'Password'), icon: Icons.lock_outline_rounded, obscure: true, onSubmitted: (_) => _submit()),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_signupMode ? Icons.person_add_alt_1_rounded : Icons.login_rounded),
            label: Text(_signupMode ? _jsonLabel(labels, 'signupButton', 'Create account') : _jsonLabel(labels, 'loginButton', 'Login')),
          ),
          if (providers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(children: [Expanded(child: Divider(color: theme.border)), Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(_jsonLabel(labels, 'otherWays', 'Other ways to sign in'), style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12))), Expanded(child: Divider(color: theme.border))]),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: providers.map((provider) => _SocialAuthButtonJson(data: <String, dynamic>{'provider': provider, 'label': _authProviderLabel(provider)}, theme: theme, previewMode: widget.previewMode)).toList(),
            ),
          ],
          if (allowPasswordReset) ...[
            const SizedBox(height: 8),
            TextButton.icon(onPressed: _loading ? null : _resetPassword, icon: const Icon(Icons.password_rounded), label: Text(_jsonLabel(labels, 'forgotPassword', 'Forgot password?'))),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (widget.previewMode) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preview only: Firebase auth is disabled in admin emulator.')));
      return;
    }
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid email and at least 6 characters password.')));
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = ref.read(authServiceProvider);
      if (_signupMode) {
        await auth.signUpEmailPassword(email: email, password: password, displayName: _name.text.trim());
      } else {
        await auth.signInEmailPassword(email: email, password: password);
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthService.friendlyAuthError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (widget.previewMode) return;
    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter email first.')));
      return;
    }
    try {
      await ref.read(authServiceProvider).sendPasswordResetEmail(email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset email sent.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthService.friendlyAuthError(error))));
    }
  }
}

class _AuthTextFieldJson extends StatelessWidget {
  const _AuthTextFieldJson({required this.controller, required this.theme, required this.label, required this.icon, this.obscure = false, this.keyboardType, this.onSubmitted});

  final TextEditingController controller;
  final _UiTheme theme;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        textInputAction: obscure ? TextInputAction.done : TextInputAction.next,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: theme.accent, size: 19),
          filled: true,
          fillColor: theme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: theme.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: theme.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: theme.accent, width: 1.4)),
        ),
      ),
    );
  }
}

class _AuthModeToggleJson extends StatelessWidget {
  const _AuthModeToggleJson({required this.theme, required this.signupMode, required this.loginLabel, required this.signupLabel, required this.onChanged});

  final _UiTheme theme;
  final bool signupMode;
  final String loginLabel;
  final String signupLabel;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: theme.accent.withOpacity(.08), borderRadius: BorderRadius.circular(999), border: Border.all(color: theme.border)),
      child: Row(
        children: [
          Expanded(child: _AuthTogglePillJson(label: loginLabel, active: !signupMode, onTap: onChanged == null ? null : () => onChanged!(false), theme: theme)),
          Expanded(child: _AuthTogglePillJson(label: signupLabel, active: signupMode, onTap: onChanged == null ? null : () => onChanged!(true), theme: theme)),
        ],
      ),
    );
  }
}

class _AuthTogglePillJson extends StatelessWidget {
  const _AuthTogglePillJson({required this.label, required this.active, required this.onTap, required this.theme});

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: active ? theme.accent : Colors.transparent, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(color: active ? Colors.white : theme.textSecondary, fontWeight: FontWeight.w900)),
      ),
    );
  }
}

String _jsonLabel(Map<String, dynamic> labels, String key, String fallback) {
  final value = labels[key]?.toString().trim();
  return value == null || value.isEmpty ? fallback : value;
}

String? _authProviderFromString(String value) {
  final raw = value.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
  if (raw == 'google' || raw == 'googlecom') return 'google';
  if (raw == 'apple' || raw == 'applecom') return 'apple';
  if (raw == 'facebook' || raw == 'facebookcom' || raw == 'fb') return 'facebook';
  return null;
}

String _authProviderLabel(String value) {
  return switch (_authProviderFromString(value)) {
    'google' => 'Google',
    'apple' => 'Apple',
    'facebook' => 'Facebook',
    _ => value,
  };
}

class _AuthLogoJson extends StatelessWidget {
  const _AuthLogoJson({required this.data, required this.theme});
  final Map<String, dynamic> data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final label = _textOf(data, 'label', _textOf(data, 'title', 'PM'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 18, top: 8),
      child: Center(
        child: Column(
          children: [
            Container(
              width: _num(data['size'], 72).toDouble(),
              height: _num(data['size'], 72).toDouble(),
              decoration: BoxDecoration(
                color: theme.accent,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: theme.accent.withOpacity(.18), blurRadius: 22, offset: const Offset(0, 10))],
              ),
              alignment: Alignment.center,
              child: Text(label.substring(0, label.length.clamp(1, 2).toInt()).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
            ),
            const SizedBox(height: 10),
            Text(_textOf(data, 'caption', 'Project Management Dashboard'), textAlign: TextAlign.center, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _InputJson extends StatelessWidget {
  const _InputJson({required this.data, required this.theme, this.obscure = false});
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final label = _textOf(data, 'label', _textOf(data, 'placeholder', obscure ? 'Password' : 'Input'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        enabled: false,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: _textOf(data, 'placeholder', label),
          prefixIcon: Icon(_iconFor(data['icon']?.toString()), color: theme.accent, size: 19),
          suffixIcon: obscure ? Icon(Icons.visibility_off_outlined, color: theme.textSecondary, size: 18) : null,
          filled: true,
          fillColor: theme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: theme.border)),
          disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: theme.border)),
        ),
      ),
    );
  }
}

class _SocialAuthButtonJson extends ConsumerStatefulWidget {
  const _SocialAuthButtonJson({required this.data, required this.theme, required this.previewMode});
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool previewMode;

  @override
  ConsumerState<_SocialAuthButtonJson> createState() => _SocialAuthButtonJsonState();
}

class _SocialAuthButtonJsonState extends ConsumerState<_SocialAuthButtonJson> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final provider = _authProviderFromString((widget.data['provider'] ?? widget.data['action'] ?? widget.data['method'] ?? widget.data['key'] ?? '').toString()) ?? 'google';
    final label = _textOf(widget.data, 'label', _authProviderLabel(provider));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton.icon(
        onPressed: _loading ? null : () => _signIn(provider),
        icon: _loading ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_iconFor(widget.data['icon']?.toString() ?? provider), size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: widget.theme.textPrimary,
          side: BorderSide(color: widget.theme.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        ),
      ),
    );
  }

  Future<void> _signIn(String provider) async {
    if (widget.previewMode) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preview only: $provider sign-in is disabled.')));
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).signInWithProviderId(provider);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthService.friendlyAuthError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _AuthSwitchJson extends StatelessWidget {
  const _AuthSwitchJson({required this.data, required this.theme});
  final Map<String, dynamic> data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_textOf(data, 'text', 'Already have an account?'), style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text(_textOf(data, 'actionLabel', 'Login'), style: TextStyle(color: theme.accent, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _OnboardingJsonScreen extends StatelessWidget {
  const _OnboardingJsonScreen({required this.state, required this.data, required this.theme, required this.previewMode, this.embedded = false, this.onAction});

  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool previewMode;
  final bool embedded;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final member = state.currentMember;
    final projectsReady = state.visibleProjects.isNotEmpty;
    final tasksReady = state.visibleTasks.isNotEmpty;
    final notificationsReady = state.myNotifications.isNotEmpty;
    final profileReady = member.displayName.trim().isNotEmpty && member.email.trim().isNotEmpty;
    final steps = <_OnboardingStepData>[
      _OnboardingStepData('Profile ready', profileReady ? 'Name, email and role are synced.' : 'Complete your employee profile first.', Icons.person_rounded, profileReady),
      _OnboardingStepData('Projects joined', projectsReady ? '${state.visibleProjects.length} visible project(s).' : 'No joined project is visible yet.', Icons.folder_rounded, projectsReady),
      _OnboardingStepData('Tasks assigned', tasksReady ? '${state.visibleTasks.length} assigned task(s).' : 'Assigned tasks will appear after manager assignment.', Icons.task_alt_rounded, tasksReady),
      _OnboardingStepData('Alerts enabled', notificationsReady ? '${state.myNotifications.length} notification(s) synced.' : 'Notifications and meetings will appear here.', Icons.notifications_rounded, notificationsReady),
    ];

    final children = <Widget>[
      if (!embedded && data['hideTitle'] != true)
        _ScreenTitle(
          title: _textOf(data, 'title', 'Welcome'),
          subtitle: _textOf(data, 'subtitle', 'Your project workspace is ready to set up'),
        ),
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(theme.padding + 4),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(theme.radius + 8),
          border: Border.all(color: theme.border),
          boxShadow: [BoxShadow(color: theme.accent.withOpacity(.08), blurRadius: 28, offset: const Offset(0, 14))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(color: theme.accent, borderRadius: BorderRadius.circular(24)),
                  child: const Icon(Icons.dashboard_customize_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(state.company.name.trim().isEmpty ? 'Project Management' : state.company.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 19)),
                    const SizedBox(height: 4),
                    Text('Hi ${member.displayName.trim().isEmpty ? 'there' : member.displayName.split(' ').first}, this APK shows only your assigned project data.', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OnboardingMetricPill(theme: theme, label: '${state.visibleProjects.length} projects', icon: Icons.folder_rounded),
                _OnboardingMetricPill(theme: theme, label: '${state.visibleTasks.length} tasks', icon: Icons.task_alt_rounded),
                _OnboardingMetricPill(theme: theme, label: '${state.myUnreadNotificationCount} unread', icon: Icons.notifications_rounded),
              ],
            ),
            const SizedBox(height: 18),
            ...steps.map((step) => _OnboardingStepTile(theme: theme, step: step)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onAction?.call('home');
                    },
                    icon: const Icon(Icons.home_rounded),
                    label: const Text('Dashboard'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onAction?.call('openProfile');
                    },
                    icon: const Icon(Icons.person_rounded),
                    label: const Text('Profile'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
    return embedded ? Column(children: children) : ListView(physics: const BouncingScrollPhysics(), padding: EdgeInsets.all(theme.padding), children: children);
  }
}

class _OnboardingStepData {
  const _OnboardingStepData(this.title, this.subtitle, this.icon, this.done);
  final String title;
  final String subtitle;
  final IconData icon;
  final bool done;
}

class _OnboardingStepTile extends StatelessWidget {
  const _OnboardingStepTile({required this.theme, required this.step});
  final _UiTheme theme;
  final _OnboardingStepData step;

  @override
  Widget build(BuildContext context) {
    final color = step.done ? const Color(0xFF16A34A) : theme.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: step.done ? const Color(0xFFEAFBF0) : theme.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: step.done ? const Color(0xFF16A34A).withOpacity(.18) : theme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(15)),
            child: Icon(step.done ? Icons.check_rounded : step.icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 13)),
              const SizedBox(height: 3),
              Text(step.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 11)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _OnboardingMetricPill extends StatelessWidget {
  const _OnboardingMetricPill({required this.theme, required this.label, required this.icon});
  final _UiTheme theme;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: theme.accent.withOpacity(.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.accent.withOpacity(.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.accent),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: theme.accent, fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      ),
    );
  }
}

class _DeadlineFromTasksCard extends StatelessWidget {
  const _DeadlineFromTasksCard({required this.state, required this.data, required this.theme, required this.title});
  final WorkspaceState state;
  final Map<String, dynamic> data;
  final _UiTheme theme;
  final String title;

  @override
  Widget build(BuildContext context) {
    final source = '${data['dataSource'] ?? data['source'] ?? data['id'] ?? ''}'.toLowerCase();
    final todayOnly = source.contains('today') || title.toLowerCase().contains('today');
    final openTasks = state.visibleTasks
        .where((task) => task.status != TaskStatus.completed)
        .where((task) => !todayOnly || _isSameDate(task.dueDate, DateTime.now()))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final task = openTasks.isEmpty ? null : openTasks.first;
    final fallbackSubtitle = todayOnly ? 'No open task deadlines.' : 'No open task deadlines.';
    final subtitle = task == null
        ? fallbackSubtitle
        : todayOnly
            ? '${openTasks.length} open task deadline${openTasks.length == 1 ? '' : 's'} today • ${task.title}'
            : '${task.title} • ${_projectName(state, task.projectId)}';
    return _JsonCard(
      title: title,
      subtitle: subtitle,
      theme: theme,
      trailing: task == null
          ? const Icon(Icons.check_circle_rounded)
          : DeadlineCountdownChip(deadline: task.dueDate, completed: false, compact: true),
    );
  }
}

class _OnlineStatusCard extends ConsumerStatefulWidget {
  const _OnlineStatusCard({required this.state, required this.theme, required this.data, required this.previewMode});
  final WorkspaceState state;
  final _UiTheme theme;
  final Map<String, dynamic> data;
  final bool previewMode;

  @override
  ConsumerState<_OnlineStatusCard> createState() => _OnlineStatusCardState();
}

class _OnlineStatusCardState extends ConsumerState<_OnlineStatusCard> {
  late bool _online;

  @override
  void initState() {
    super.initState();
    _online = widget.state.currentMember.isOnline;
  }

  @override
  Widget build(BuildContext context) {
    return _Surface(
      theme: widget.theme,
      child: Row(
        children: [
          Icon(Icons.circle, color: _online ? Colors.green : Colors.grey, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_textOf(widget.data, 'title', 'Online status'), style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(_online ? 'You are online and visible to managers.' : 'You are offline.', style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
          Switch(
            value: _online,
            activeColor: widget.theme.accent,
            onChanged: (value) {
              setState(() => _online = value);
              if (widget.previewMode) {
                _previewSnack(context, true, 'Presence changed in preview only.');
              } else {
                ref.read(workspaceProvider.notifier).setMyOnlineStatus(value);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _EditableTaskCard extends ConsumerStatefulWidget {
  const _EditableTaskCard({required this.task, required this.fields, required this.actions, required this.variant, required this.theme, required this.previewMode, this.projectName});
  final ProjectTask? task;
  final List<String> fields;
  final List<String> actions;
  final String variant;
  final _UiTheme theme;
  final bool previewMode;
  final String? projectName;

  @override
  ConsumerState<_EditableTaskCard> createState() => _EditableTaskCardState();
}

class _EditableTaskCardState extends ConsumerState<_EditableTaskCard> {
  late TaskStatus? _status;

  @override
  void initState() {
    super.initState();
    _status = widget.task?.status;
  }

  @override
  void didUpdateWidget(covariant _EditableTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task?.taskId != widget.task?.taskId) _status = widget.task?.status;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.task;
    if (item == null) return _JsonCard(title: 'No task', subtitle: 'No task is available for this card.', theme: widget.theme);
    final liveState = ref.watch(workspaceProvider);
    final status = _status ?? item.status;
    final projectName = widget.projectName ?? _projectName(liveState, item.projectId);
    final children = <Widget>[];

    if (widget.fields.contains('taskTitle')) {
      children.add(Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)));
    }
    if (widget.fields.contains('projectName')) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(projectName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
      ));
    }
    if (widget.fields.contains('description') && item.description.trim().isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
      ));
    }

    final chips = <Widget>[];
    if (widget.fields.contains('status')) {
      if (widget.actions.contains('changeStatus')) {
        chips.add(_StatusChanger(
          status: status,
          color: status.color,
          onChanged: (next) {
            if (next == null) return;
            setState(() => _status = next);
            if (widget.previewMode) {
              _previewSnack(context, true, 'Task moved to ${next.label} in preview only.');
            } else {
              ref.read(workspaceProvider.notifier).updateTaskStatus(item.taskId, next);
            }
          },
        ));
      } else {
        chips.add(_InfoTag(label: status.label, icon: Icons.verified_rounded, color: status.color, theme: widget.theme));
      }
    }
    if (widget.fields.contains('priority')) chips.add(_InfoTag(label: item.priority.label, icon: Icons.flag_rounded, color: item.priority.color, theme: widget.theme));
    if (widget.fields.contains('deadlineTimer')) chips.add(DeadlineCountdownChip(deadline: item.dueDate, completed: status == TaskStatus.completed, compact: true));
    if (chips.isNotEmpty) children.add(Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 7, runSpacing: 7, children: chips)));

    final detailChips = <Widget>[];
    if (widget.fields.contains('assigneeCount')) detailChips.add(_InfoTag(label: '${item.assignedToIds.length} assigned', icon: Icons.people_alt_rounded, theme: widget.theme));
    if (widget.fields.contains('commentsCount')) detailChips.add(_InfoTag(label: '${item.commentsCount} comments', icon: Icons.comment_rounded, theme: widget.theme));
    if (widget.fields.contains('attachmentsCount') || widget.fields.contains('filesCount')) detailChips.add(_InfoTag(label: '${item.attachmentsCount} files', icon: Icons.attach_file_rounded, theme: widget.theme));
    if (detailChips.isNotEmpty) children.add(Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 7, runSpacing: 7, children: detailChips)));

    if (widget.fields.contains('progress')) {
      final progress = _taskProgressForStatus(status);
      children.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: progress, minHeight: 8, color: widget.theme.accent, backgroundColor: widget.theme.accent.withOpacity(.12)),
        ),
      ));
      children.add(Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text('${(progress * 100).round()}% complete', style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
      ));
    }

    final actionButtons = <Widget>[];
    if (widget.actions.contains('openDetails')) {
      actionButtons.add(OutlinedButton.icon(onPressed: () => _showTaskDetails(item, status, projectName), icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Details')));
    }
    if (widget.actions.contains('comment')) {
      actionButtons.add(OutlinedButton.icon(onPressed: () => widget.previewMode ? _showTaskDetails(item, status, projectName, focus: 'comment') : _addComment(item), icon: const Icon(Icons.comment_rounded, size: 16), label: const Text('Comment')));
    }
    if (widget.actions.contains('uploadFile') || widget.actions.contains('file') || widget.actions.contains('attachFile')) {
      actionButtons.add(OutlinedButton.icon(onPressed: () => widget.previewMode ? _showTaskDetails(item, status, projectName, focus: 'file') : _addFileMetadata(item), icon: const Icon(Icons.attach_file_rounded, size: 16), label: const Text('File')));
    }
    if (actionButtons.isNotEmpty) {
      children.add(Padding(padding: const EdgeInsets.only(top: 12), child: Wrap(spacing: 8, runSpacing: 8, children: actionButtons)));
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(_variantRadius(widget.theme, widget.variant)),
        onTap: () => _showTaskDetails(item, status, projectName),
        child: _VariantSurface(
          theme: widget.theme,
          variant: widget.variant,
          accent: status.color,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children.isEmpty ? [Text(item.title)] : children),
        ),
      ),
    );
  }

  void _showTaskDetails(ProjectTask task, TaskStatus status, String projectName, {String? focus}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TaskDetailsSheet(
        task: task,
        status: status,
        projectName: projectName,
        theme: widget.theme,
        focus: focus,
        previewMode: widget.previewMode,
      ),
    );
  }

  Future<void> _addComment(ProjectTask task) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add comment'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Comment', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final message = controller.text.trim();
              if (message.isEmpty) return;
              ref.read(workspaceProvider.notifier).addTaskComment(task.taskId, message);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _addFileMetadata(ProjectTask task) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(workspaceProvider.notifier).addAttachmentFromDevicePicker(task.taskId);
    if (!mounted) return;
    final error = ref.read(workspaceProvider).lastError;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'File uploaded and attached to task.' : (error ?? 'File selection cancelled.')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}


class _TaskDetailsSheet extends StatelessWidget {
  const _TaskDetailsSheet({required this.task, required this.status, required this.projectName, required this.theme, required this.previewMode, this.focus});

  final ProjectTask task;
  final TaskStatus status;
  final String projectName;
  final _UiTheme theme;
  final bool previewMode;
  final String? focus;

  @override
  Widget build(BuildContext context) {
    final progress = _taskProgressForStatus(status);
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: .78,
        minChildSize: .42,
        maxChildSize: .94,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: theme.border),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.16), blurRadius: 30, offset: const Offset(0, -10))],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(theme.padding + 4, 12, theme.padding + 4, theme.padding + 20),
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(color: theme.border, borderRadius: BorderRadius.circular(999)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(color: theme.accent.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.task_alt_rounded, color: theme.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 5),
                        Text(projectName, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoTag(label: status.label, icon: Icons.verified_rounded, color: status.color, theme: theme),
                  _InfoTag(label: task.priority.label, icon: Icons.flag_rounded, color: task.priority.color, theme: theme),
                  _InfoTag(label: DateText.compact(task.dueDate), icon: Icons.calendar_month_rounded, theme: theme),
                ],
              ),
              const SizedBox(height: 18),
              Text('Description', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 6),
              Text(task.description.trim().isEmpty ? 'No task description added.' : task.description, style: TextStyle(color: theme.textSecondary, height: 1.35, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: progress, minHeight: 10, color: theme.accent, backgroundColor: theme.accent.withOpacity(.12)),
              ),
              const SizedBox(height: 6),
              Text('${(progress * 100).round()}% complete', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 12)),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _DetailMetric(theme: theme, icon: Icons.people_alt_rounded, label: 'Assigned', value: '${task.assignedToIds.length} member(s)'),
                  _DetailMetric(theme: theme, icon: Icons.timer_rounded, label: 'Hours', value: '${task.loggedHours}/${task.estimatedHours}'),
                  _DetailMetric(theme: theme, icon: Icons.comment_rounded, label: 'Comments', value: '${task.commentsCount}'),
                  _DetailMetric(theme: theme, icon: Icons.attach_file_rounded, label: 'Files', value: '${task.attachmentsCount}'),
                ],
              ),
              if (task.tags.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(spacing: 8, runSpacing: 8, children: task.tags.map((tag) => _InfoTag(label: tag, icon: Icons.label_rounded, theme: theme)).toList()),
              ],
              const SizedBox(height: 18),
              _JsonCard(
                title: focus == 'file' ? 'File area' : focus == 'comment' ? 'Comment area' : 'Task actions',
                subtitle: previewMode
                    ? 'Preview only. The production APK opens this same task detail sheet; Firestore writes stay disabled in preview.'
                    : 'Use this sheet to review task details. Status changes are saved from the task card dropdown.',
                theme: theme,
                trailing: Icon(focus == 'file' ? Icons.attach_file_rounded : focus == 'comment' ? Icons.comment_rounded : Icons.info_rounded, color: theme.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({required this.theme, required this.icon, required this.label, required this.value});

  final _UiTheme theme;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 138,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.accent.withOpacity(.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: theme.accent, size: 18),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 11)),
      ]),
    );
  }
}

class _StatusChanger extends StatelessWidget {
  const _StatusChanger({required this.status, required this.color, required this.onChanged});
  final TaskStatus status;
  final Color color;
  final ValueChanged<TaskStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(.18)),
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(.07),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TaskStatus>(
          value: status,
          isDense: true,
          icon: Icon(Icons.swap_vert_rounded, color: color, size: 18),
          items: TaskStatus.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ProfileActionsCard extends ConsumerStatefulWidget {
  const _ProfileActionsCard({required this.state, required this.theme, required this.previewMode, required this.showNotificationSettings});
  final WorkspaceState state;
  final _UiTheme theme;
  final bool previewMode;
  final bool showNotificationSettings;

  @override
  ConsumerState<_ProfileActionsCard> createState() => _ProfileActionsCardState();
}

class _ProfileActionsCardState extends ConsumerState<_ProfileActionsCard> {
  late String _name;
  late String _email;
  late String _department;
  late String _jobTitle;
  late String _location;
  late bool _available;
  late bool _online;
  bool _settingsExpanded = false;

  @override
  void initState() {
    super.initState();
    _load(widget.state);
  }

  @override
  void didUpdateWidget(covariant _ProfileActionsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.currentMember.uid != widget.state.currentMember.uid) _load(widget.state);
  }

  void _load(WorkspaceState state) {
    final member = state.currentMember;
    _name = member.displayName;
    _email = member.email;
    _department = member.effectiveDepartment;
    _jobTitle = member.effectiveJobTitle;
    _location = member.location;
    _available = member.available;
    _online = member.isOnline;
  }

  @override
  Widget build(BuildContext context) {
    final initials = _profileInitials(_name.isEmpty ? _email : _name);
    final biometricCompanyId = widget.state.user.defaultCompanyId.trim().isNotEmpty
        ? widget.state.user.defaultCompanyId.trim()
        : AppConfig.fallbackCompanyId;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(widget.theme.padding + 2),
      decoration: BoxDecoration(
        color: widget.theme.surface,
        borderRadius: BorderRadius.circular(widget.theme.radius + 6),
        border: Border.all(color: widget.theme.border),
        boxShadow: [BoxShadow(color: widget.theme.accent.withOpacity(.08), blurRadius: 28, offset: const Offset(0, 14))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.theme.accent,
                  boxShadow: [BoxShadow(color: widget.theme.accent.withOpacity(.22), blurRadius: 24, offset: const Offset(0, 10))],
                ),
                alignment: Alignment.center,
                child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(_name.isEmpty ? 'Employee' : _name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 20))),
                        _InfoTag(
                          label: _online ? 'Online' : 'Offline',
                          icon: _online ? Icons.circle_rounded : Icons.circle_outlined,
                          color: _online ? const Color(0xFF16A34A) : widget.theme.textSecondary,
                          theme: widget.theme,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('$_jobTitle • $_department', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('$_email • ${_location.trim().isEmpty ? 'Remote' : _location}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ProfileToggleRow(
            theme: widget.theme,
            title: 'Online status',
            subtitle: _online ? 'Managers can see you are active now.' : 'You are hidden from online member lists.',
            icon: Icons.radio_button_checked_rounded,
            value: _online,
            onChanged: (value) {
              setState(() => _online = value);
              if (widget.previewMode) {
                _previewSnack(context, true, 'Online status changed in preview only.');
              } else {
                ref.read(workspaceProvider.notifier).setMyOnlineStatus(value);
              }
            },
          ),
          const SizedBox(height: 10),
          _ProfileToggleRow(
            theme: widget.theme,
            title: 'Availability',
            subtitle: _available ? 'Available for new work.' : 'Marked busy for new assignment.',
            icon: Icons.verified_rounded,
            value: _available,
            onChanged: (value) {
              setState(() => _available = value);
              if (widget.previewMode) {
                _previewSnack(context, true, 'Availability changed in preview only.');
              } else {
                ref.read(workspaceProvider.notifier).setMyAvailability(value);
              }
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final twoCol = constraints.maxWidth > 330;
            final buttonWidth = twoCol ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: buttonWidth,
                  child: _ProfileQuickActionButton(
                    theme: widget.theme,
                    label: 'Edit profile',
                    icon: Icons.edit_rounded,
                    filled: true,
                    onTap: () => _editProfile(context),
                  ),
                ),
                SizedBox(
                  width: buttonWidth,
                  child: _ProfileQuickActionButton(
                    theme: widget.theme,
                    label: 'Copy log',
                    icon: Icons.receipt_long_rounded,
                    onTap: () async {
                      if (widget.previewMode) {
                        _previewSnack(context, true, 'Diagnostic log copy is disabled in preview.');
                        return;
                      }
                      ApkCrashForensics.log('sdui_profile_copy_diagnostic_log_tapped');
                      final flutterLog = await ApkCrashForensics.readLog();
                      final nativeLog = await AndroidAlertNotificationService.readNativeNotificationLog();
                      await Clipboard.setData(ClipboardData(text: '$flutterLog\n\n--- Native Android notification log ---\n$nativeLog'));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diagnostic + native notification log copied.')));
                    },
                  ),
                ),
                SizedBox(
                  width: buttonWidth,
                  child: _ProfileQuickActionButton(
                    theme: widget.theme,
                    label: 'Crashlytics Test',
                    icon: Icons.bug_report_rounded,
                    onTap: () => _runCrashlyticsTest(context),
                  ),
                ),
                SizedBox(
                  width: buttonWidth,
                  child: _ProfileQuickActionButton(
                    theme: widget.theme,
                    label: 'Logout',
                    icon: Icons.logout_rounded,
                    filled: true,
                    onTap: () => _logout(context),
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 12),
          _ProfileSettingsSection(
            theme: widget.theme,
            expanded: _settingsExpanded,
            // Hardcoded app-lock setting: not driven by SDUI JSON. It is always
            // part of the native Profile -> Settings section in APK and in the
            // Admin Mobile UI Designer preview. Preview mode never calls the OS
            // biometric prompt; it only demonstrates the toggle state locally.
            biometricSettings: widget.previewMode || widget.state.user.uid.trim().isNotEmpty
                ? BiometricSettingsTile(
                    uid: widget.previewMode ? 'admin_preview_user' : widget.state.user.uid,
                    companyId: biometricCompanyId,
                    previewMode: widget.previewMode,
                  )
                : null,
            notificationSettings: widget.showNotificationSettings
                ? _NotificationAlertSettingsJsonCard(
                    theme: widget.theme,
                    alertConfig: widget.state.mobileUiConfig.notificationAlertConfig,
                    soundOptions: widget.state.mobileUiConfig.notificationSoundOptions,
                    previewMode: widget.previewMode,
                    embedded: true,
                  )
                : null,
            onToggle: () => setState(() => _settingsExpanded = !_settingsExpanded),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    if (widget.previewMode) {
      _previewSnack(context, true, 'Logout is disabled in preview.');
      return;
    }
    ref.read(workspaceProvider.notifier).setMyOnlineStatus(false);
    if (AppConfig.useFirebase) {
      await FirebaseAuth.instance.signOut();
    } else {
      ref.read(demoLoggedInProvider.notifier).state = false;
    }
  }

  Future<void> _runCrashlyticsTest(BuildContext context) async {
    if (widget.previewMode) {
      _previewSnack(context, true, 'Crashlytics test is disabled in preview. Test it inside APK Profile.');
      return;
    }
    if (!CrashlyticsSdk.isSupported || !AppConfig.useFirebase) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Crashlytics test needs Android/iOS Firebase mode.')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Crashlytics Test'),
        content: const Text('This will intentionally crash the app. Open the app again after it closes so Crashlytics can upload the report.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton.icon(onPressed: () => Navigator.of(dialogContext).pop(true), icon: const Icon(Icons.bug_report_rounded), label: const Text('Crash now')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Triggering Crashlytics test crash...')));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await CrashlyticsSdk.triggerTestCrash(source: 'sdui_profile_apk_button');
  }

  Future<void> _editProfile(BuildContext context) async {
    final name = TextEditingController(text: _name);
    final email = TextEditingController(text: _email);
    final department = TextEditingController(text: _department);
    final jobTitle = TextEditingController(text: _jobTitle);
    final location = TextEditingController(text: _location);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.previewMode ? 'Edit profile preview' : 'Edit profile'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 10),
              TextField(controller: department, decoration: const InputDecoration(labelText: 'Department')),
              const SizedBox(height: 10),
              TextField(controller: jobTitle, decoration: const InputDecoration(labelText: 'Job title')),
              const SizedBox(height: 10),
              TextField(controller: location, decoration: const InputDecoration(labelText: 'Location')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              setState(() {
                _name = name.text.trim().isEmpty ? _name : name.text.trim();
                _email = email.text.trim().isEmpty ? _email : email.text.trim();
                _department = department.text.trim().isEmpty ? _department : department.text.trim();
                _jobTitle = jobTitle.text.trim().isEmpty ? _jobTitle : jobTitle.text.trim();
                _location = location.text.trim().isEmpty ? _location : location.text.trim();
              });
              Navigator.of(dialogContext).pop();
              if (widget.previewMode) {
                _previewSnack(context, true, 'Profile edited in preview only.');
              } else {
                ref.read(workspaceProvider.notifier).updateMyProfile(
                      displayName: _name,
                      email: _email,
                      department: _department,
                      jobTitle: _jobTitle,
                      location: _location,
                    );
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

class _ProfileToggleRow extends StatelessWidget {
  const _ProfileToggleRow({required this.theme, required this.title, required this.subtitle, required this.icon, required this.value, required this.onChanged});

  final _UiTheme theme;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.accent.withOpacity(.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.accent.withOpacity(.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: theme.accent.withOpacity(.10), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, size: 19, color: theme.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 13)),
              const SizedBox(height: 3),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 11)),
            ]),
          ),
          Switch.adaptive(value: value, activeColor: theme.accent, onChanged: onChanged),
        ],
      ),
    );
  }
}


class _ProfileSettingsSection extends StatelessWidget {
  const _ProfileSettingsSection({
    required this.theme,
    required this.expanded,
    required this.onToggle,
    this.notificationSettings,
    this.biometricSettings,
  });

  final _UiTheme theme;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? notificationSettings;
  final Widget? biometricSettings;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(theme.radius + 2),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(theme.radius + 2),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    _PlainSettingsBadge(label: 'SET', color: theme.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Settings', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text('Fingerprint lock and notification controls', style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Icon(Icons.keyboard_arrow_down_rounded, color: theme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: ClipRect(
                child: Column(
                  children: [
                    if (biometricSettings != null) biometricSettings!,
                    if (notificationSettings != null) notificationSettings!,
                    if (biometricSettings == null && notificationSettings == null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.surface,
                          borderRadius: BorderRadius.circular(theme.radius),
                          border: Border.all(color: theme.border),
                        ),
                        child: Text('No settings available.', style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),
            crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

class _ProfileSettingsRow extends StatelessWidget {
  const _ProfileSettingsRow({required this.theme, required this.icon, required this.title, required this.subtitle, required this.onTap, this.danger = false});

  final _UiTheme theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB42318) : theme.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: danger ? const Color(0xFFFFF1F1) : theme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: danger ? const Color(0xFFFFD0D0) : theme.border),
          ),
          child: Row(
            children: [
              _PlainSettingsBadge(label: title.trim().isEmpty ? '•' : title.trim().substring(0, 1).toUpperCase(), color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 11.2)),
                  ],
                ),
              ),
              Text('›', style: TextStyle(color: danger ? const Color(0xFFB42318) : theme.textSecondary, fontWeight: FontWeight.w900, fontSize: 20)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileQuickActionButton extends StatelessWidget {
  const _ProfileQuickActionButton({required this.theme, required this.label, required this.icon, required this.onTap, this.filled = false, this.danger = false});

  final _UiTheme theme;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFDC2626) : theme.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: filled ? color : color.withOpacity(.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: filled ? color : color.withOpacity(.28)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: filled ? Colors.white : color),
              const SizedBox(width: 8),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: filled ? Colors.white : color, fontWeight: FontWeight.w900))),
            ],
          ),
        ),
      ),
    );
  }
}

String _profileInitials(String value) {
  final parts = value.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return 'U';
  if (parts.length == 1) return parts.first.substring(0, parts.first.length.clamp(1, 2).toInt()).toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

class _JsonActionButton extends ConsumerWidget {
  const _JsonActionButton({
    required this.data,
    required this.theme,
    required this.previewMode,
    required this.onExternalAction,
  });

  final Map<String, dynamic> data;
  final _UiTheme theme;
  final bool previewMode;
  final ValueChanged<String>? onExternalAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = _actionFromData(data);
    final label = _textOf(data, 'label', _textOf(data, 'title', _label(action.isEmpty ? 'openDetails' : action)));
    final subtitle = _textOf(data, 'subtitle', _textOf(data, 'description', ''));
    final icon = data['icon'] == null ? _iconForActionName(action) : _iconFor(data['icon']?.toString());
    final type = _canonicalWidgetType(data['type'] ?? data['widget'] ?? data['component'] ?? 'button');
    final asTile = type == 'profileAction' || type == 'settingsTile' || type == 'profileSettingTile' || data['tile'] == true;
    final outlined = data['variant']?.toString() == 'outlined' || type == 'secondaryAction';

    final tap = () => _runAction(context, ref, action, label);
    if (asTile) {
      return _Surface(
        theme: theme,
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(theme.radius),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: theme.accent.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: theme.accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 14)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.textSecondary),
            ],
          ),
        ),
      );
    }

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label, overflow: TextOverflow.ellipsis),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: outlined
          ? OutlinedButton(
              onPressed: tap,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.accent,
                side: BorderSide(color: theme.accent.withOpacity(.45)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
              child: child,
            )
          : FilledButton(
              onPressed: tap,
              style: FilledButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
              child: child,
            ),
    );
  }

  String _actionFromData(Map<String, dynamic> data) {
    // v101: real SDUI runtime action extraction.
    // Older JSON files use many shapes:
    //   {"action":"logout"}
    //   {"onTap":{"action":"logout"}}
    //   {"onTap":{"type":"navigate","route":"projects"}}
    //   {"target":"profile"}
    // The previous renderer called toString() on nested maps, so actions looked
    // like "{action: logout}" and nothing executed. Keep this parser permissive.
    final direct = _extractActionValue(data['action']) ??
        _extractActionValue(data['actionRoute']) ??
        _extractActionValue(data['onTap']) ??
        _extractActionValue(data['tap']) ??
        _extractActionValue(data['handler']) ??
        _extractActionValue(data['route']) ??
        _extractActionValue(data['target']) ??
        _extractActionValue(data['screen']) ??
        _extractActionValue(data['id']);
    final canonical = _canonicalActionName(direct ?? '');
    if (canonical.isNotEmpty) return canonical;

    final title = (data['title'] ?? data['label'] ?? data['text'] ?? '').toString().toLowerCase();
    if (title.contains('logout') || title.contains('sign out')) return 'logout';
    if (title.contains('profile') || title.contains('edit')) return 'updateProfile';
    if (title.contains('notification') || title.contains('alert') || title.contains('test')) return 'testAlert';
    if (title.contains('available') || title.contains('busy')) return 'setAvailability';
    if (title.contains('online') || title.contains('offline') || title.contains('presence')) return 'setPresence';
    if (title.contains('project')) return 'openProjects';
    if (title.contains('task')) return 'openTasks';
    return 'openDetails';
  }

  String? _extractActionValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is String || raw is num || raw is bool) {
      final value = raw.toString().trim();
      return value.isEmpty ? null : value;
    }
    if (raw is Map) {
      final map = raw.map((key, value) => MapEntry(key.toString(), value));
      for (final key in const <String>['action', 'actionName', 'actionType', 'name', 'event', 'handler']) {
        final value = _extractActionValue(map[key]);
        if (value != null && value.isNotEmpty) return value;
      }
      final type = map['type']?.toString().trim().toLowerCase() ?? '';
      final route = _extractActionValue(map['route'] ?? map['screen'] ?? map['target'] ?? map['tab'] ?? map['path']);
      if (type == 'navigate' || type == 'navigation' || type == 'route' || type == 'open') {
        return route == null ? type : 'open:$route';
      }
      if (route != null && route.isNotEmpty) return route;
      final id = _extractActionValue(map['id']);
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  String _canonicalActionName(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    value = value.replaceAll(RegExp(r'^[#/]+' ), '');
    value = value.split('?').first.split(':').last.trim();
    final compact = value.replaceAll(RegExp(r'[\s_\-]+'), '').toLowerCase();
    return switch (compact) {
      'home' || 'openhome' => 'home',
      'task' || 'tasks' || 'opentask' || 'opentasks' || 'tasklist' => 'openTasks',
      'project' || 'projects' || 'openproject' || 'openprojects' || 'projectlist' || 'projectfeed' => 'openProjects',
      'notification' || 'notifications' || 'inbox' || 'openinbox' || 'opennotifications' => 'openInbox',
      'profile' || 'openprofile' => 'openProfile',
      'board' || 'kanban' || 'openboard' => 'openBoard',
      'meeting' || 'meetings' || 'openmeetings' => 'openMeetings',
      'logout' || 'signout' || 'signoff' => 'logout',
      'editprofile' || 'updateprofile' || 'profileedit' => 'updateProfile',
      'availability' || 'setavailability' || 'toggleavailability' => 'setAvailability',
      'presence' || 'setpresence' || 'online' || 'offline' || 'onlinestatus' || 'togglepresence' => 'setPresence',
      'testalert' || 'testnotification' || 'notificationtest' || 'sendtestalert' => 'testAlert',
      'copydiagnostics' || 'copylog' || 'copylogs' => 'copyDiagnostics',
      'createtask' || 'newtask' || 'addtask' => 'createTask',
      'createproject' || 'newproject' || 'addproject' => 'createProject',
      'uploadfile' || 'fileupload' || 'attachfile' => 'uploadFile',
      'smartsearch' || 'search' || 'focussearch' => 'smartSearch',
      'tasktimeline' || 'opentasktimeline' || 'taskprogresstimeline' || 'opentaskprogresstimeline' => 'openTaskTimeline',
      'opendetails' || 'details' => 'openDetails',
      _ => value,
    };
  }

  Future<void> _runAction(BuildContext context, WidgetRef ref, String rawAction, String label) async {
    final action = _canonicalActionName(rawAction.split(':').first.trim());
    HapticFeedback.selectionClick();
    switch (action) {
      case 'home':
        onExternalAction?.call('home');
        return;
      case 'openInbox':
      case 'inbox':
      case 'notifications':
        onExternalAction?.call('openInbox');
        _previewSnack(context, previewMode, 'Opening Inbox.');
        return;
      case 'openProfile':
        onExternalAction?.call('openProfile');
        return;
      case 'openBoard':
        onExternalAction?.call('openBoard');
        return;
      case 'openMeetings':
        onExternalAction?.call('openMeetings');
        return;
      case 'openTaskTimeline':
        onExternalAction?.call('openTaskTimeline');
        return;
      case 'createTask':
      case 'createProject':
      case 'uploadFile':
      case 'smartSearch':
        onExternalAction?.call(action);
        _previewSnack(context, previewMode, '$label action opened.');
        return;
      case 'openTasks':
      case 'tasks':
        onExternalAction?.call('openTasks');
        return;
      case 'openProjects':
      case 'projects':
        onExternalAction?.call('openProjects');
        return;
      case 'updateProfile':
      case 'editProfile':
        await _editProfile(context, ref);
        return;
      case 'setAvailability':
      case 'availability':
        await _setAvailability(context, ref);
        return;
      case 'setPresence':
      case 'onlineStatus':
      case 'presence':
        await _setPresence(context, ref);
        return;
      case 'testAlert':
      case 'notificationTest':
      case 'testNotification':
        await _testAlert(context, ref);
        return;
      case 'copyDiagnostics':
      case 'copyLog':
        await _copyDiagnostics(context);
        return;
      case 'crashlyticsTest':
        _previewSnack(context, previewMode, previewMode ? 'Crashlytics test is disabled in preview.' : 'Use the dedicated Crashlytics Test button below.');
        return;
      case 'logout':
      case 'signOut':
        if (previewMode) {
          _previewSnack(context, true, 'Logout is disabled in preview.');
          return;
        }
        ref.read(workspaceProvider.notifier).setMyOnlineStatus(false);
        if (AppConfig.useFirebase) {
          await FirebaseAuth.instance.signOut();
        } else {
          ref.read(demoLoggedInProvider.notifier).state = false;
        }
        return;
      default:
        onExternalAction?.call(action);
        _previewSnack(context, previewMode, '$label tapped.');
    }
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref) async {
    final member = ref.read(workspaceProvider).currentMember;
    final name = TextEditingController(text: member.displayName);
    final email = TextEditingController(text: member.email);
    final department = TextEditingController(text: member.effectiveDepartment);
    final jobTitle = TextEditingController(text: member.effectiveJobTitle);
    final location = TextEditingController(text: member.location);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(previewMode ? 'Edit profile preview' : 'Edit profile'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 10),
              TextField(controller: department, decoration: const InputDecoration(labelText: 'Department')),
              const SizedBox(height: 10),
              TextField(controller: jobTitle, decoration: const InputDecoration(labelText: 'Job title')),
              const SizedBox(height: 10),
              TextField(controller: location, decoration: const InputDecoration(labelText: 'Location')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (previewMode) {
                _previewSnack(context, true, 'Profile edit works in APK; preview did not write Firestore.');
              } else {
                ref.read(workspaceProvider.notifier).updateMyProfile(
                      displayName: name.text.trim().isEmpty ? member.displayName : name.text.trim(),
                      email: email.text.trim().isEmpty ? member.email : email.text.trim(),
                      department: department.text.trim().isEmpty ? member.effectiveDepartment : department.text.trim(),
                      jobTitle: jobTitle.text.trim().isEmpty ? member.effectiveJobTitle : jobTitle.text.trim(),
                      location: location.text.trim().isEmpty ? member.location : location.text.trim(),
                    );
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _setAvailability(BuildContext context, WidgetRef ref) async {
    final current = ref.read(workspaceProvider).currentMember.available;
    if (previewMode) {
      _previewSnack(context, true, 'Availability toggle works in APK; preview did not write Firestore.');
      return;
    }
    ref.read(workspaceProvider.notifier).setMyAvailability(!current);
    _previewSnack(context, false, !current ? 'Availability set to available.' : 'Availability set to busy.');
  }

  Future<void> _setPresence(BuildContext context, WidgetRef ref) async {
    final current = ref.read(workspaceProvider).currentMember.isOnline;
    if (previewMode) {
      _previewSnack(context, true, 'Online/offline toggle works in APK; preview did not write Firestore.');
      return;
    }
    ref.read(workspaceProvider.notifier).setMyOnlineStatus(!current);
    _previewSnack(context, false, !current ? 'You are online.' : 'You are offline.');
  }

  Future<void> _testAlert(BuildContext context, WidgetRef ref) async {
    if (previewMode) {
      _previewSnack(context, true, 'Test alert is disabled in preview. Test it from the APK Profile screen.');
      return;
    }
    final config = ref.read(workspaceProvider).mobileUiConfig.notificationAlertConfig;
    final text = (config['assistantText']?.toString().trim().isNotEmpty == true)
        ? config['assistantText'].toString().trim()
        : 'You are assigned a new task. Please accept the notification.';
    final sound = await AndroidAlertNotificationService.getPreferredAlertSound();
    final assistantVoice = await AndroidAlertNotificationService.getAssistantVoiceEnabled();
    final shown = await AndroidAlertNotificationService.testSelectedAlertSound(soundName: sound, assistantVoice: assistantVoice, assistantText: text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(shown ? 'Test alert sent. It will ring until Accept.' : 'Notification permission is required before the test alert can show.')),
    );
  }

  Future<void> _copyDiagnostics(BuildContext context) async {
    if (previewMode) {
      _previewSnack(context, true, 'Diagnostic log copy is disabled in preview.');
      return;
    }
    final flutterLog = await ApkCrashForensics.readLog();
    final nativeLog = await AndroidAlertNotificationService.readNativeNotificationLog();
    await Clipboard.setData(ClipboardData(text: '$flutterLog\n\n--- Native Android notification log ---\n$nativeLog'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Diagnostic + native notification log copied.')));
  }

  IconData _iconForActionName(String action) {
    switch (action) {
      case 'logout':
      case 'signOut':
        return Icons.logout_rounded;
      case 'updateProfile':
      case 'editProfile':
        return Icons.edit_rounded;
      case 'setAvailability':
        return Icons.verified_rounded;
      case 'setPresence':
      case 'onlineStatus':
        return Icons.circle_rounded;
      case 'testAlert':
      case 'notificationTest':
        return Icons.notifications_active_rounded;
      case 'copyDiagnostics':
      case 'copyLog':
        return Icons.receipt_long_rounded;
      case 'createProject':
        return Icons.create_new_folder_rounded;
      case 'createTask':
        return Icons.add_task_rounded;
      case 'openInbox':
      case 'inbox':
        return Icons.notifications_rounded;
      default:
        return Icons.touch_app_rounded;
    }
  }

}

class _ProfileRendererDiagnosticsButton extends StatelessWidget {
  const _ProfileRendererDiagnosticsButton({required this.theme, required this.previewMode});

  final _UiTheme theme;
  final bool previewMode;

  Future<void> _copyLog(BuildContext context) async {
    if (previewMode) {
      _previewSnack(context, true, 'Diagnostic log copy is disabled in preview. Use it inside APK Profile.');
      return;
    }
    ApkCrashForensics.log('sdui_profile_copy_diagnostic_log_tapped');
    final flutterLog = await ApkCrashForensics.readLog();
    final nativeLog = await AndroidAlertNotificationService.readNativeNotificationLog();
    await Clipboard.setData(ClipboardData(text: '$flutterLog\n\n--- Native Android notification log ---\n$nativeLog'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic + native notification log copied. Paste it here after testing.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _copyLog(context),
      icon: const Icon(Icons.receipt_long_rounded),
      label: const Text('Copy log'),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.accent,
        side: BorderSide(color: theme.accent.withOpacity(.45)),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _ProfileRendererCrashlyticsTestButton extends StatelessWidget {
  const _ProfileRendererCrashlyticsTestButton({required this.theme, required this.previewMode});

  final _UiTheme theme;
  final bool previewMode;

  Future<void> _runTest(BuildContext context) async {
    if (previewMode) {
      _previewSnack(context, true, 'Crashlytics test is disabled in preview. Test it inside APK Profile.');
      return;
    }
    if (!CrashlyticsSdk.isSupported || !AppConfig.useFirebase) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crashlytics test needs Android/iOS Firebase mode.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Crashlytics Test'),
        content: const Text(
          'This will intentionally crash the app. Open the app again after it closes so Crashlytics can upload the report.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.bug_report_rounded),
            label: const Text('Crash now'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Triggering Crashlytics test crash...')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await CrashlyticsSdk.triggerTestCrash(source: 'sdui_profile_apk_button');
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _runTest(context),
      icon: const Icon(Icons.bug_report_rounded),
      label: const Text('Crashlytics Test'),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.accent,
        side: BorderSide(color: theme.accent.withOpacity(.45)),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _ProfileRendererLogoutCapsule extends StatelessWidget {
  const _ProfileRendererLogoutCapsule({required this.theme, required this.previewMode, required this.onLogout});

  final _UiTheme theme;
  final bool previewMode;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () async => onLogout(),
      icon: const Icon(Icons.logout_rounded),
      label: const Text('Logout'),
      style: FilledButton.styleFrom(
        backgroundColor: theme.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}


class _InfoTag extends StatelessWidget {
  const _InfoTag({required this.label, required this.theme, this.icon, this.color});

  final String label;
  final _UiTheme theme;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tagColor = color ?? theme.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tagColor.withOpacity(.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tagColor.withOpacity(.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: tagColor),
            const SizedBox(width: 5),
          ],
          Text(label, style: TextStyle(color: tagColor, fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatefulWidget {
  const _ProjectCard({
    required this.project,
    required this.fields,
    required this.variant,
    required this.theme,
    required this.tasks,
    this.initiallyExpanded = false,
    this.defaultBadge,
  });

  final Project? project;
  final List<String> fields;
  final String variant;
  final _UiTheme theme;
  final List<ProjectTask> tasks;
  final bool initiallyExpanded;
  final String? defaultBadge;

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant _ProjectCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project?.projectId != widget.project?.projectId) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.project;
    if (item == null) return _JsonCard(title: 'No project', subtitle: 'No project is available for this card.', theme: widget.theme);
    final derivedTaskCount = widget.tasks.isEmpty ? item.totalTasks : widget.tasks.length;
    final derivedCompleted = widget.tasks.isEmpty ? item.completedTasks : widget.tasks.where((task) => task.status == TaskStatus.completed).length;
    final rawProgress = derivedTaskCount <= 0 ? item.progress / 100 : derivedCompleted / derivedTaskCount;
    final progress = rawProgress.clamp(0.0, 1.0).toDouble();
    final delayed = item.isDelayed;
    final accent = delayed ? const Color(0xFFDC2626) : widget.theme.accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(_variantRadius(widget.theme, widget.variant)),
        onTap: () => setState(() => _expanded = !_expanded),
        child: _VariantSurface(
          theme: widget.theme,
          variant: widget.variant,
          accent: accent,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.defaultBadge != null) ...[
                            _InfoTag(label: widget.defaultBadge!, icon: Icons.folder_special_rounded, color: widget.theme.accent, theme: widget.theme),
                            const SizedBox(height: 8),
                          ],
                          if (widget.fields.contains('projectName'))
                            Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 16)),
                          if (widget.fields.contains('description') && item.description.trim().isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.25)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (widget.fields.contains('statusTag') || widget.fields.contains('status'))
                          _InfoTag(label: delayed ? 'Delayed' : item.status.label, icon: delayed ? Icons.warning_amber_rounded : Icons.verified_rounded, color: delayed ? const Color(0xFFDC2626) : item.status.color, theme: widget.theme),
                        const SizedBox(height: 6),
                        AnimatedRotation(
                          turns: _expanded ? .5 : 0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Icon(Icons.keyboard_arrow_down_rounded, color: widget.theme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    if (widget.fields.contains('taskCount')) _InfoTag(label: '$derivedTaskCount tasks', icon: Icons.task_alt_rounded, theme: widget.theme),
                    if (widget.fields.contains('completedTaskCount')) _InfoTag(label: '$derivedCompleted done', icon: Icons.check_circle_rounded, color: const Color(0xFF059669), theme: widget.theme),
                    if (widget.fields.contains('team') || widget.fields.contains('teamCount')) _InfoTag(label: '${item.teamIds.length} teams', icon: Icons.groups_rounded, theme: widget.theme),
                    if (widget.fields.contains('deadline')) _InfoTag(label: DateText.compact(item.dueDate), icon: Icons.calendar_month_rounded, color: delayed ? const Color(0xFFDC2626) : widget.theme.accent, theme: widget.theme),
                    if (widget.fields.contains('priority')) _InfoTag(label: item.priority.label, icon: Icons.flag_rounded, color: item.priority.color, theme: widget.theme),
                  ],
                ),
                if (widget.fields.contains('progress')) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(value: progress, minHeight: 10, color: accent, backgroundColor: widget.theme.accent.withOpacity(.10)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('${(progress * 100).round()}%', style: TextStyle(color: widget.theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('${(progress * 100).round()}% complete', style: TextStyle(color: widget.theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 12)),
                ],
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _ProjectInlineDetails(project: item, tasks: widget.tasks, progress: progress, delayed: delayed, theme: widget.theme),
                  ),
                  crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 240),
                  sizeCurve: Curves.easeOutCubic,
                  firstCurve: Curves.easeOutCubic,
                  secondCurve: Curves.easeOutCubic,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectInlineDetails extends StatelessWidget {
  const _ProjectInlineDetails({required this.project, required this.tasks, required this.progress, required this.delayed, required this.theme});

  final Project project;
  final List<ProjectTask> tasks;
  final double progress;
  final bool delayed;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final completed = tasks.where((task) => task.status == TaskStatus.completed).length;
    final open = (tasks.length - completed).clamp(0, 999).toInt();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.background.withOpacity(.50),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.border.withOpacity(.90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: theme.accent.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.route_rounded, color: theme.accent, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Task timeline', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text('Completed tasks get a tick. Open tasks stay as empty circles.', style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w800, fontSize: 11.5, height: 1.25)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _InfoTag(label: '$completed done', icon: Icons.check_circle_rounded, color: const Color(0xFF059669), theme: theme),
              _InfoTag(label: '$open open', icon: Icons.radio_button_unchecked_rounded, color: theme.textSecondary, theme: theme),
              _InfoTag(label: '${tasks.length} total', icon: Icons.task_alt_rounded, theme: theme),
            ],
          ),
          const SizedBox(height: 14),
          if (tasks.isEmpty)
            _JsonCard(title: 'No tasks yet', subtitle: 'Project tasks will appear here after Firestore sync.', theme: theme)
          else
            ...tasks.asMap().entries.map((entry) => _TaskTimelineRow(
                  theme: theme,
                  task: entry.value,
                  projectName: project.name,
                  isLast: entry.key == tasks.length - 1,
                )),
        ],
      ),
    );
  }
}

class _ProjectDetailsSheet extends StatelessWidget {
  const _ProjectDetailsSheet({
    required this.project,
    required this.tasks,
    required this.progress,
    required this.delayed,
    required this.theme,
  });

  final Project project;
  final List<ProjectTask> tasks;
  final double progress;
  final bool delayed;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final completed = tasks.where((task) => task.status == TaskStatus.completed).length;
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: .72,
        minChildSize: .38,
        maxChildSize: .94,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: theme.border),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.16), blurRadius: 30, offset: const Offset(0, -10))],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(theme.padding + 4, 12, theme.padding + 4, theme.padding + 20),
            children: [
              Center(child: Container(width: 46, height: 5, decoration: BoxDecoration(color: theme.border, borderRadius: BorderRadius.circular(999)))),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(color: theme.accent.withOpacity(.10), borderRadius: BorderRadius.circular(15)),
                    child: Icon(Icons.folder_rounded, color: theme.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(project.name, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 5),
                        Text(project.description.trim().isEmpty ? project.status.label : project.description, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12, height: 1.35)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoTag(label: delayed ? 'Delayed' : project.status.label, icon: delayed ? Icons.warning_amber_rounded : Icons.verified_rounded, color: delayed ? const Color(0xFFDC2626) : project.status.color, theme: theme),
                  _InfoTag(label: '${tasks.length} task(s)', icon: Icons.task_alt_rounded, theme: theme),
                  _InfoTag(label: '$completed done', icon: Icons.check_circle_rounded, color: const Color(0xFF059669), theme: theme),
                  _InfoTag(label: DateText.compact(project.dueDate), icon: Icons.calendar_month_rounded, theme: theme),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: progress, minHeight: 10, color: delayed ? const Color(0xFFDC2626) : theme.accent, backgroundColor: theme.accent.withOpacity(.12)),
              ),
              const SizedBox(height: 6),
              Text('${(progress * 100).round()}% complete', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 12)),
              const SizedBox(height: 18),
              Text('Project tasks', style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 10),
              if (tasks.isEmpty)
                _JsonCard(title: 'No tasks yet', subtitle: 'Project tasks will appear here after Firestore sync.', theme: theme)
              else
                ...tasks.take(8).map((task) => _Surface(
                      theme: theme,
                      child: Row(
                        children: [
                          Icon(Icons.task_alt_rounded, color: task.status.color, size: 19),
                          const SizedBox(width: 10),
                          Expanded(child: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w800))),
                          _InfoTag(label: task.status.label, color: task.status.color, theme: theme),
                        ],
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }
}


class _HeroJsonCard extends StatelessWidget {
  const _HeroJsonCard({required this.data, required this.state, required this.theme});
  final Map<String, dynamic> data;
  final WorkspaceState state;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final title = _textOf(data, 'title', 'My Work');
    final subtitle = _textOf(data, 'subtitle', '${state.visibleTasks.length} tasks • ${state.visibleProjects.length} projects');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(theme.padding + 2),
      decoration: BoxDecoration(
        color: _color(data['color']?.toString(), theme.accent),
        borderRadius: BorderRadius.circular(_num(data['radius'], theme.radius).toDouble()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(.86), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MetricJsonCard extends StatelessWidget {
  const _MetricJsonCard({required this.data, required this.state, required this.theme});
  final Map<String, dynamic> data;
  final WorkspaceState state;
  final _UiTheme theme;

  int _metricValue() {
    final source = '${data['valueSource'] ?? data['dataSource'] ?? data['source'] ?? ''}'.trim().toLowerCase();
    final title = _textOf(data, 'title', 'Metric').toLowerCase();
    if (source.contains('projects.activecount') || title.contains('active project')) {
      return state.visibleProjects.where((project) => project.isActiveWork).length;
    }
    if (source.contains('projects.opencount') || source.contains('projects.open')) {
      return state.visibleProjects.where((project) => project.isOpenWork).length;
    }
    if (source.contains('projects.delayedcount') || source.contains('projects.overdue') || title.contains('delayed project')) {
      return state.visibleProjects.where((project) => project.isDelayed).length;
    }
    if (source.contains('projects.completedcount') || title.contains('completed project')) {
      return state.visibleProjects.where((project) => project.status == ProjectStatus.completed).length;
    }
    if (source.contains('projects.total') || source == 'projects' || title == 'projects') {
      return state.visibleProjects.length;
    }
    if (source.contains('tasks.opencount') || title.contains('open task')) {
      return state.visibleTasks.where((task) => task.status != TaskStatus.completed).length;
    }
    if (source.contains('tasks.today') || title.contains('today')) {
      return state.visibleTasks.where((task) => task.status != TaskStatus.completed && _isSameDate(task.dueDate, DateTime.now())).length;
    }
    if (source.contains('tasks.overdue') || title.contains('overdue')) {
      return state.visibleTasks.where((task) => task.isOverdue).length;
    }
    if (source.contains('tasks.completed') || title.contains('completed task') || title.contains('done task')) {
      return state.visibleTasks.where((task) => task.status == TaskStatus.completed).length;
    }
    if (source.contains('tasks.total') || source == 'tasks' || title == 'tasks') {
      return state.visibleTasks.length;
    }
    if (source.contains('presence.onlinecount') || source.contains('members.online') || title.contains('team online')) {
      return state.members.where((member) => member.isOnline).length;
    }
    if (source.contains('members.total') || title.contains('team member')) {
      return state.members.length;
    }
    if (source.contains('notifications.unread') || title.contains('unread')) {
      return state.myUnreadNotificationCount;
    }
    if (data.containsKey('value')) {
      return _num(data['value'], 0).round();
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final value = _metricValue();
    final iconName = '${data['icon'] ?? ''}'.toLowerCase();
    final icon = iconName.contains('warning')
        ? Icons.warning_amber_rounded
        : iconName.contains('group')
            ? Icons.groups_rounded
            : iconName.contains('task')
                ? Icons.task_alt_rounded
                : Icons.folder_rounded;
    return _Surface(
      theme: theme,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: theme.accent.withOpacity(.10), borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, color: theme.accent, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(_textOf(data, 'title', 'Metric'), style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900))),
          Text('$value', style: TextStyle(color: theme.accent, fontWeight: FontWeight.w900, fontSize: 22)),
        ],
      ),
    );
  }
}


class _FilterChipsJson extends StatefulWidget {
  const _FilterChipsJson({required this.data, required this.theme, this.selected, this.onChanged});

  final Map<String, dynamic> data;
  final _UiTheme theme;
  final String? selected;
  final ValueChanged<String>? onChanged;

  @override
  State<_FilterChipsJson> createState() => _FilterChipsJsonState();
}

class _FilterChipsJsonState extends State<_FilterChipsJson> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final chips = _stringList(widget.data['chips'] ?? widget.data['items'] ?? widget.data['filters'], fallback: const <String>['All', 'In Progress', 'Completed']);
    final fallbackActive = chips.isEmpty ? '' : chips.first;
    final controlled = widget.selected != null;
    final active = controlled ? widget.selected! : (_selected ?? fallbackActive);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips.map((chip) {
          final selected = _samePageFilter(chip, active);
          return ChoiceChip(
            selected: selected,
            label: Text(chip),
            avatar: selected ? Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
            selectedColor: widget.theme.accent,
            backgroundColor: widget.theme.surface,
            labelStyle: TextStyle(color: selected ? Colors.white : widget.theme.textPrimary, fontWeight: FontWeight.w900),
            side: BorderSide(color: selected ? widget.theme.accent : widget.theme.border),
            onSelected: (_) {
              if (controlled) {
                widget.onChanged?.call(chip);
              } else {
                setState(() => _selected = chip);
                widget.onChanged?.call(chip);
              }
            },
          );
        }).toList(),
      ),
    );
  }
}

class _RuntimeSearchBox extends StatefulWidget {
  const _RuntimeSearchBox({
    required this.theme,
    required this.hint,
    required this.onChanged,
    this.initialQuery = '',
  });

  final _UiTheme theme;
  final String hint;
  final String initialQuery;
  final ValueChanged<String> onChanged;

  @override
  State<_RuntimeSearchBox> createState() => _RuntimeSearchBoxState();
}

class _RuntimeSearchBoxState extends State<_RuntimeSearchBox> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
  }

  @override
  void didUpdateWidget(covariant _RuntimeSearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery && widget.initialQuery != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initialQuery,
        selection: TextSelection.collapsed(offset: widget.initialQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onChanged: (value) {
          setState(() {});
          widget.onChanged(value);
        },
        decoration: _runtimeSearchDecoration(
          theme: widget.theme,
          hint: widget.hint,
          hasText: _controller.text.trim().isNotEmpty,
          onClear: () {
            _controller.clear();
            setState(() {});
            widget.onChanged('');
          },
        ),
      ),
    );
  }
}

class _SearchHeaderJson extends ConsumerStatefulWidget {
  const _SearchHeaderJson({required this.data, required this.theme, this.onExternalAction});

  final Map<String, dynamic> data;
  final _UiTheme theme;
  final ValueChanged<String>? onExternalAction;

  @override
  ConsumerState<_SearchHeaderJson> createState() => _SearchHeaderJsonState();
}

class _SearchHeaderJsonState extends ConsumerState<_SearchHeaderJson> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // v110: this JSON searchHeader is no longer universal search.
    // It must not search projects + tasks + inbox together or show inline
    // universal result cards. Page-level filtering is owned by the shell
    // search query that is passed into Projects/Tasks/Board through
    // runtimeSearchQuery. This widget now behaves as a plain page-search input
    // and forwards the typed value to the shell if the shell is listening.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onChanged: (value) {
          setState(() => _query = value);
          widget.onExternalAction?.call('pageSearch:${value.trim()}');
        },
        decoration: _runtimeSearchDecoration(
          theme: widget.theme,
          hint: _textOf(widget.data, 'placeholder', _textOf(widget.data, 'label', 'Search this page')),
          hasText: _controller.text.trim().isNotEmpty,
          onClear: () {
            _controller.clear();
            setState(() => _query = '');
            widget.onExternalAction?.call('pageSearch:');
          },
        ),
      ),
    );
  }
}

InputDecoration _runtimeSearchDecoration({
  required _UiTheme theme,
  required String hint,
  required bool hasText,
  required VoidCallback onClear,
}) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(Icons.search_rounded, color: theme.textSecondary),
    suffixIcon: hasText
        ? IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: onClear,
          )
        : null,
    filled: true,
    fillColor: theme.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: theme.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: theme.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: theme.accent, width: 1.4)),
  );
}

class _InlineSearchResultTile extends StatelessWidget {
  const _InlineSearchResultTile({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final _UiTheme theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: theme.accent.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: theme.accent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: theme.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.data, required this.theme});
  final Map<String, dynamic> data;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    final value = (_num(data['value'], .5) / (_num(data['max'], 1) == 0 ? 1 : _num(data['max'], 1))).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LinearProgressIndicator(value: value, minHeight: _num(data['height'], 8).toDouble(), color: theme.accent),
    );
  }
}

class _ScreenTitle extends StatelessWidget {
  const _ScreenTitle({required this.title, required this.subtitle, this.trailing});
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _JsonCard extends StatelessWidget {
  const _JsonCard({required this.title, required this.subtitle, required this.theme, this.trailing, this.warning = false});

  final String title;
  final String subtitle;
  final _UiTheme theme;
  final Widget? trailing;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      theme: theme,
      warning: warning,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 5),
                Text(subtitle, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}


String _cardVariant(dynamic value, String fallback) {
  final raw = value?.toString().trim() ?? '';
  const supported = <String>{
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
    'teamSetupHero',
    'sitePins',
    'compactMapList',
    'taskDetailHeader',
    'compactHeader',
    'deadlineCalendar',
  };
  return supported.contains(raw) ? raw : fallback;
}

double _variantRadius(_UiTheme theme, String variant) {
  return switch (variant) {
    'compactCard' => (theme.radius - 4).clamp(10, 40).toDouble(),
    'minimalCard' => (theme.radius - 6).clamp(8, 40).toDouble(),
    'nativeListRow' || 'editorialProgressCard' || 'editorialStatusCard' || 'editorialProjectRow' || 'softProgressCard' || 'wireframeProjectFeedCard' || 'wireframeProfileSettings' || 'taskDetailHeader' || 'compactHeader' => (theme.radius + 2).clamp(18, 34).toDouble(),
    _ => theme.radius,
  };
}

class _VariantSurface extends StatelessWidget {
  const _VariantSurface({required this.theme, required this.variant, required this.accent, required this.child});

  final _UiTheme theme;
  final String variant;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = variant == 'compactCard' || variant == 'nativeListRow';
    final minimal = variant == 'minimalCard';
    final timeline = variant == 'timelineCard';
    final advanced = variant == 'advancedProgressCard';
    final progress = variant == 'progressCard' || variant == 'editorialProgressCard' || variant == 'softProgressCard';
    final editorial = variant == 'nativeListRow' || variant == 'editorialProgressCard' || variant == 'editorialStatusCard' || variant == 'editorialProjectRow' || variant == 'softProgressCard' || variant == 'wireframeProjectFeedCard' || variant == 'wireframeProfileSettings' || variant == 'taskDetailHeader' || variant == 'compactHeader';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(compact ? (theme.padding - 2).clamp(8, 32).toDouble() : theme.padding),
      decoration: BoxDecoration(
        color: minimal ? Colors.transparent : theme.surface,
        borderRadius: BorderRadius.circular(_variantRadius(theme, variant)),
        border: Border.all(color: timeline ? accent.withOpacity(.42) : (minimal ? theme.border : theme.border.withOpacity(editorial ? 1 : .85))),
        boxShadow: minimal ? null : [BoxShadow(color: Colors.black.withOpacity(editorial ? .045 : advanced ? .055 : .025), blurRadius: editorial ? 22 : advanced ? 26 : 18, offset: Offset(0, editorial ? 10 : 8))],
      ),
      child: timeline
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 4, height: 88, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999))),
                const SizedBox(width: 12),
                Expanded(child: child),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (advanced || progress)
                  Align(
                    alignment: Alignment.centerRight,
                    child: _InfoTag(label: _variantLabelForCard(variant), icon: Icons.auto_awesome_rounded, color: accent, theme: theme),
                  ),
                child,
              ],
            ),
    );
  }
}

String _variantLabelForCard(String value) {
  return switch (value) {
    'modernCard' => 'Modern',
    'minimalCard' => 'Minimal',
    'compactCard' => 'Compact',
    'timelineCard' => 'Timeline',
    'progressCard' => 'Progress',
    'advancedProgressCard' => 'Advanced',
    'nativeListRow' => 'Native row',
    'editorialProgressCard' => 'Editorial progress',
    'editorialStatusCard' => 'Editorial',
    'editorialProjectRow' => 'Editorial row',
    'darkEditorialHero' => 'Hero',
    'smallMetricTile' => 'Metric',
    'softProgressCard' => 'Soft progress',
    'wireframeProjectFeedCard' => 'Project feed',
    'wireframeProfileSettings' => 'Settings',
    'teamSetupHero' => 'Team setup',
    'sitePins' => 'Site pins',
    'compactMapList' => 'Map list',
    'taskDetailHeader' => 'Task detail',
    'compactHeader' => 'Compact header',
    'deadlineCalendar' => 'Calendar',
    _ => value,
  };
}

class _Surface extends StatelessWidget {
  const _Surface({required this.theme, required this.child, this.warning = false});
  final _UiTheme theme;
  final Widget child;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(theme.padding),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFF7ED) : theme.surface,
        borderRadius: BorderRadius.circular(theme.radius),
        border: Border.all(color: warning ? const Color(0xFFF59E0B).withOpacity(.35) : theme.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.025), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }
}


class _JsonRecoveryNode extends StatelessWidget {
  const _JsonRecoveryNode({required this.error, required this.theme});
  final Object error;
  final _UiTheme theme;

  @override
  Widget build(BuildContext context) {
    return _JsonCard(
      title: 'Skipped broken JSON block',
      subtitle: error.toString(),
      theme: theme,
      warning: true,
    );
  }
}

class _UnsupportedBanner extends StatelessWidget {
  const _UnsupportedBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7ED),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFC2410C), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('$count unsupported JSON item(s). Add matching widgets to APK renderer or use supported keys.', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
          ],
        ),
      ),
    );
  }
}

class _UiTheme {
  const _UiTheme({
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.radius,
    required this.padding,
  });

  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final double radius;
  final double padding;

  factory _UiTheme.fromJson(Map<String, dynamic>? json) {
    final map = json ?? const <String, dynamic>{};
    return _UiTheme(
      accent: _color(map['accent']?.toString(), const Color(0xFF2563EB)),
      background: _color(map['background']?.toString() ?? map['backgroundColor']?.toString(), const Color(0xFFF6F8FB)),
      surface: _color(map['surface']?.toString() ?? map['cardColor']?.toString(), Colors.white),
      surfaceAlt: _color(
        map['surfaceAlt']?.toString() ??
            map['surfaceAlternate']?.toString() ??
            map['mutedSurface']?.toString(),
        const Color(0xFFF1F5F9),
      ),
      textPrimary: _color(map['textPrimary']?.toString(), const Color(0xFF111827)),
      textSecondary: _color(map['textSecondary']?.toString(), const Color(0xFF64748B)),
      border: _color(map['border']?.toString(), const Color(0xFFE2E8F0)),
      radius: _num(map['cardRadius'] ?? map['radius'], 22).toDouble().clamp(8, 40),
      padding: _num(map['cardPadding'] ?? map['padding'], 14).toDouble().clamp(8, 32),
    );
  }
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map) return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  return null;
}

List<dynamic> _itemsOf(Map<String, dynamic> data) {
  for (final key in <String>['children', 'sections', 'items', 'blocks', 'widgets', 'body', 'content', 'nodes']) {
    final value = data[key];
    if (value is List) return value;
  }
  return const <dynamic>[];
}

List<dynamic> _orderedItemsOf(Map<String, dynamic> data) {
  final items = _itemsOf(data);
  if (items.length < 2) return items;
  final explicitOrder = _stringList(
    data['contentOrder'] ?? data['layoutOrder'] ?? data['sectionOrder'] ?? data['pageOrder'] ?? data['order'],
    fallback: const <String>[],
  ).map(_orderToken).where((item) => item.isNotEmpty).toList();
  if (explicitOrder.isEmpty) return items;

  final remaining = List<dynamic>.from(items);
  final ordered = <dynamic>[];
  for (final token in explicitOrder) {
    final index = remaining.indexWhere((item) => _itemMatchesOrderToken(item, token));
    if (index >= 0) ordered.add(remaining.removeAt(index));
  }
  ordered.addAll(remaining);
  return ordered;
}

String _orderToken(Object? value) => value?.toString().trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '') ?? '';

bool _itemMatchesOrderToken(dynamic item, String token) {
  if (item is! Map) return false;
  final map = item.map((key, value) => MapEntry(key.toString(), value));
  final tokens = <String>{
    _orderToken(map['id']),
    _orderToken(map['key']),
    _orderToken(map['name']),
    _orderToken(map['slot']),
    _orderToken(map['section']),
    _orderToken(map['type']),
    _orderToken(map['widget']),
    _orderToken(map['component']),
    _orderToken(map['componentType']),
  }..remove('');

  bool hasAny(Iterable<String> aliases) => tokens.any((value) => aliases.any((alias) => value == alias || value.contains(alias)));

  if (token == 'search' || token == 'pagesearch' || token == 'searchbar') {
    return hasAny(const <String>['search', 'searchheader', 'pagesearch']);
  }
  if (token == 'summary' || token == 'stats' || token == 'metrics') {
    return hasAny(const <String>['summary', 'stats', 'metrics', 'projectstatsgrid', 'taskstatsgrid', 'metric']);
  }
  if (token == 'filter' || token == 'filters' || token == 'tabs' || token == 'chips') {
    return hasAny(const <String>['filter', 'filters', 'tabs', 'chips', 'filterchips']);
  }
  if (token == 'content' || token == 'feed' || token == 'list' || token == 'cards') {
    return hasAny(const <String>['feed', 'list', 'content', 'projectpage', 'taskpage', 'projectlist', 'tasklist', 'kanban', 'calendar', 'files']);
  }
  return tokens.any((value) => value == token || value.contains(token));
}

/// Keeps Notification alert settings to exactly one visible card per rendered list.
///
/// In SDUI JSON, `notificationAlert`, `notificationSoundSelector`, and
/// `notificationDisplayWindow` all map to the same full Android notification
/// settings widget. When admins include more than one,
/// or when `profileSummary` is embedded next to one of them, the card was printed
/// 2-3 times. This de-dupes only that one settings widget and leaves every other
/// JSON block unchanged.
List<dynamic> _dedupeNotificationAlertSettingsNodes(List<dynamic> items) {
  var notificationSettingsRendered = false;
  final next = <dynamic>[];

  for (final item in items) {
    if (_isNotificationAlertSettingsNode(item)) {
      if (notificationSettingsRendered) continue;
      notificationSettingsRendered = true;
    }
    next.add(item);
  }

  return next;
}

bool _containsNotificationAlertSettingsNode(dynamic value) {
  if (_isNotificationAlertSettingsNode(value)) return true;
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (const <String>{
        'children',
        'sections',
        'items',
        'blocks',
        'widgets',
        'body',
        'content',
        'nodes',
      }.contains(key) && _containsNotificationAlertSettingsNode(entry.value)) {
        return true;
      }
    }
  }
  if (value is Iterable) {
    return value.any(_containsNotificationAlertSettingsNode);
  }
  return false;
}

bool _isNotificationAlertSettingsNode(dynamic value) {
  if (value is! Map) return false;
  final map = value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  final type = _canonicalWidgetType(
    map['type'] ?? map['widget'] ?? map['component'] ?? map['componentType'],
  );
  return type == 'notificationAlert' || type == 'notificationSoundSelector' || type == 'notificationDisplayWindow';
}

List<String> _stringList(dynamic value, {required List<String> fallback}) {
  if (value is List) {
    return value
        .map((item) {
          if (item is Map) {
            return item['label'] ?? item['title'] ?? item['name'] ?? item['key'] ?? item['id'] ?? item['value'] ?? '';
          }
          return item;
        })
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }
  return fallback;
}

List<String> _fieldsOf(Map<String, dynamic> data, {required List<String> fallback}) {
  return _stringList(data['showFields'] ?? data['fields'], fallback: fallback);
}

List<String> _actionsOf(Map<String, dynamic> data, {dynamic fallback}) {
  final raw = data['actions'] ?? fallback;
  if (raw is List) return raw.map((item) => item.toString()).toList();
  return const <String>[];
}

List<String> _mergeStringLists(List<String> primary, List<String> requiredItems) {
  final result = <String>[];
  for (final item in [...primary, ...requiredItems]) {
    if (item.trim().isEmpty || result.contains(item)) continue;
    result.add(item);
  }
  return result;
}


double _taskProgressForStatus(TaskStatus status) {
  return switch (status) {
    TaskStatus.completed => 1.0,
    TaskStatus.review => .82,
    TaskStatus.testing => .72,
    TaskStatus.inProgress => .55,
    TaskStatus.todo => .24,
    TaskStatus.backlog => .10,
  };
}

String _textOf(Map<String, dynamic> data, String key, String fallback) {
  final value = data[key] ?? (key == 'title' ? data['label'] : null) ?? (key == 'subtitle' ? data['description'] : null);
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String _label(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '';
  final compact = raw.replaceAll(RegExp(r'[\s_\-:/.]+'), '').toLowerCase();
  return switch (compact) {
    'home' || 'openhome' => 'Home',
    'task' || 'tasks' || 'opentask' || 'opentasks' || 'tasklist' => 'Tasks',
    'project' || 'projects' || 'openproject' || 'openprojects' || 'projectlist' || 'projectfeed' => 'Projects',
    'notification' || 'notifications' || 'inbox' || 'openinbox' || 'opennotifications' => 'Inbox',
    'profile' || 'openprofile' => 'Profile',
    'board' || 'kanban' || 'openboard' => 'Board',
    'meeting' || 'meetings' || 'openmeetings' => 'Meetings',
    'logout' || 'signout' || 'signoff' => 'Logout',
    'editprofile' || 'updateprofile' || 'profileedit' => 'Edit profile',
    'availability' || 'setavailability' || 'toggleavailability' => 'Availability',
    'presence' || 'setpresence' || 'online' || 'offline' || 'onlinestatus' || 'togglepresence' => 'Online status',
    'testalert' || 'testnotification' || 'notificationtest' || 'sendtestalert' => 'Test alert',
    'copydiagnostics' || 'copylog' || 'copylogs' => 'Copy diagnostics',
    'createtask' || 'newtask' || 'addtask' => 'Create task',
    'createproject' || 'newproject' || 'addproject' => 'Create project',
    'uploadfile' || 'fileupload' || 'attachfile' => 'Upload file',
    'smartsearch' || 'search' || 'focussearch' => 'Search',
    'opendetails' || 'details' => 'Open details',
    _ => _humanizeLabel(raw),
  };
}

String _humanizeLabel(String value) {
  final spaced = value
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (match) => '${match.group(1)} ${match.group(2)}')
      .trim();
  if (spaced.isEmpty) return value;
  return spaced[0].toUpperCase() + spaced.substring(1);
}


String _canonicalScreen(dynamic raw) {
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

String _canonicalWidgetType(dynamic raw) {
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
    'button' || 'actionbutton' => 'button',
    'textfield' || 'input' || 'emailfield' => 'textField',
    'passwordfield' || 'passwordinput' => 'passwordField',
    'authlogo' => 'authLogo',
    'authform' || 'loginform' || 'signupform' => 'authForm',
    'wireframeauthscreen' || 'authscreen' || 'login' || 'signup' => 'wireframeAuthScreen',
    'socialauthbutton' || 'socialloginbutton' || 'providerauthbutton' => 'socialAuthButton',
    'authswitch' || 'switchauth' => 'authSwitch',
    'jsonfirstlayoutengine' || 'jsonsectionorder' || 'jsonfirstsafecontrols' || 'renderersafety' || 'jsonrenderpolicy' || 'saferenderer' || 'safenodeboundary' || 'authactionapi' || 'firebaseauthapiactions' || 'emailpasswordauth' || 'passwordresetapi' => 'spacer',
    'chip' => 'chip',
    'badge' => 'badge',
    'progressbar' || 'linearprogress' => 'progressBar',
    'progressring' || 'ringprogress' => 'progressRing',
    'card' || 'panel' || 'surface' => 'card',
    'herocard' || 'herosummary' => 'heroCard',
    'summarycard' => 'summaryCard',
    'metriccard' || 'kpicard' || 'statcard' => 'metricCard',
    'deadlinecard' || 'deadline' => 'deadlineCard',
    'tasklist' || 'myopentasks' => 'taskList',
    'todaytasklist' || 'todaytasks' => 'todayTaskList',
    'taskpage' || 'taskmenu' || 'taskscreen' => 'taskPage',
    'taskcard' => 'taskCard',
    'taskdetail' || 'taskdetails' || 'taskdetailscard' => 'taskDetails',
    'projectcard' => 'projectCard',
    'projectdetail' || 'projectdetails' || 'projectdetailscard' => 'projectDetails',
    'projectlist' || 'projectpage' || 'projectscreen' => 'projectPage',
    'projectprogresscard' || 'projectprogress' => 'projectProgressCard',
    'projectstatsgrid' || 'projectsummarystrip' || 'projectsummarygrid' => 'projectStatsGrid',
    'taskstatsgrid' || 'tasksummarystrip' || 'tasksummarygrid' => 'taskStatsGrid',
    'homemetricstrip' || 'homemetricsstrip' => 'homeMetricStrip',
    'onlinestatuscard' || 'onlinestatus' => 'onlineStatusCard',
    'notificationlist' || 'inbox' => 'notificationList',
    'notificationalert' || 'alertnotification' || 'urgentalert' => 'notificationAlert',
    'notificationsoundselector' || 'soundselector' || 'alertsoundselector' => 'notificationSoundSelector',
    'notificationdisplaywindow' || 'notificationwindow' || 'displaywindow' || 'historywindow' => 'notificationDisplayWindow',
    'profilesummary' || 'profilecard' => 'profileSummary',
    'kanbanboard' || 'board' => 'kanbanBoard',
    'deadlinehero' => 'deadlineHero',
    'metrictile' || 'metric' => 'metricTile',
    'activeprojectsgrid' => 'activeProjectsGrid',
    'filterchips' || 'chips' => 'filterChips',
    'searchheader' || 'searchbar' => 'searchHeader',
    'taskprogresspanel' || 'taskprogresschart' || 'taskprogresscard' || 'taskprogressvisual' => 'taskProgressPanel',
    'tasktimelinebars' || 'timelinebars' || 'taskprogressbars' || 'productivebars' => 'taskTimelineBars',
    'taskprogresstimeline' || 'tasktimelinescreen' || 'productivetasktimeline' => 'taskProgressTimeline',
    'progresstimeline' => 'progressTimeline',
    'statuspill' => 'statusPill',
    'emptystate' => 'emptyState',
    'skeletonloader' || 'shimmer' => 'skeletonLoader',
    'nativesheet' || 'bottomsheet' => 'nativeSheet',
    'filesdocuments' || 'fileslist' => 'filesDocuments',
    'calendarview' || 'calendar' || 'calendardeadlines' => 'calendarView',
    'taskmap' || 'sitemap' || 'taskmapsiteview' => 'taskMap',
    'teammembers' || 'memberslist' => 'teamMembers',
    'onboardingscreen' || 'teamsetuphero' => 'onboardingScreen',
    'dashboardfeed' || 'dashboardprojectfeed' => 'dashboardFeed',
    'projectfeed' => 'projectFeed',
    'productivetimeline' || 'deliverytimeline' => 'progressTimeline',
    'timelinemilestones' || 'timeline' || 'milestones' => 'progressTimeline',
    'floatingreferencebottomnav' => 'floatingBottomNav',
    'contentpassundernav' => 'container',
    'edgetoedgesystembars' || 'systembars' || 'transparentsystembars' => 'edgeToEdgeSystemBars',
    'androidfigureonerightedgetoedge' || 'androidfigureoneedge' || 'figureonerightedgetoedge' => 'androidFigureOneRightEdgeToEdge',
    'scrollawaretoppadding' || 'scrollawareinsets' => 'scrollAwareTopPadding',
    'systembarcontrastscrim' || 'threebuttonnavigationcontrastscrim' => 'systemBarContrastScrim',
    'gestureawarebottomprotection' || 'gestureawareoverlay' => 'gestureAwareBottomProtection',
    'quickcreatebutton' => 'button',
    'mappins' => 'taskMap',
    'quickactiondock' => 'quickActionDock',
    'floatingbottomnav' => 'floatingBottomNav',
    'floatingtopnav' => 'floatingTopNav',
    'bottomnav' || 'bottomnavigation' || 'navigation' => 'bottomNav',
    _ => value.isEmpty ? 'card' : value,
  };
}



Map<String, dynamic> _rendererSafetyOf(Map<String, dynamic> root) {
  return _asMap(root['rendererSafety']) ??
      _asMap(root['jsonFirstControls']) ??
      _asMap(root['jsonRenderPolicy']) ??
      _asMap(root['safeRenderer']) ??
      const <String, dynamic>{};
}

int _adaptiveJsonColumns(double width, int itemCount, Map<String, dynamic> data) {
  if (itemCount <= 1) return 1;
  final small = _num(data['smallColumns'] ?? data['phoneColumns'], width < 330 ? 1 : 2).round().clamp(1, 6).toInt();
  final medium = _num(data['mediumColumns'] ?? data['tabletColumns'], 3).round().clamp(1, 6).toInt();
  final large = _num(data['largeColumns'] ?? data['desktopColumns'], 4).round().clamp(1, 6).toInt();
  if (width < _num(data['smallBreakpoint'], 520)) return small.clamp(1, itemCount).toInt();
  if (width < _num(data['mediumBreakpoint'], 820)) return medium.clamp(1, itemCount).toInt();
  return large.clamp(1, itemCount).toInt();
}

EdgeInsets _paddingOf(dynamic value, {required EdgeInsets fallback}) {
  if (value is num) return EdgeInsets.all(value.toDouble());
  if (value is Map) {
    return EdgeInsets.fromLTRB(
      _num(value['left'], fallback.left).toDouble(),
      _num(value['top'], fallback.top).toDouble(),
      _num(value['right'], fallback.right).toDouble(),
      _num(value['bottom'], fallback.bottom).toDouble(),
    );
  }
  return fallback;
}

Color _color(String? raw, Color fallback) {
  if (raw == null) return fallback;
  final value = raw.trim().replaceAll('#', '');
  if (value.length == 6) {
    final parsed = int.tryParse('FF$value', radix: 16);
    if (parsed != null) return Color(parsed);
  }
  if (value.length == 8) {
    final parsed = int.tryParse(value, radix: 16);
    if (parsed != null) return Color(parsed);
  }
  return fallback;
}

num _num(dynamic value, num fallback) => JsonValue.number(value, fallback: fallback);

bool _flag(dynamic value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == 'yes' || normalized == '1') return true;
    if (normalized == 'false' || normalized == 'no' || normalized == '0') return false;
  }
  return fallback;
}


CrossAxisAlignment _crossAxis(dynamic value) {
  return switch (value?.toString()) {
    'center' => CrossAxisAlignment.center,
    'end' => CrossAxisAlignment.end,
    'stretch' => CrossAxisAlignment.stretch,
    _ => CrossAxisAlignment.start,
  };
}

IconData _iconFor(String? raw) {
  final value = raw?.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '') ?? '';
  return switch (value) {
    'task' || 'tasks' || 'taskalt' || 'assignment' => Icons.task_alt_rounded,
    'project' || 'projects' || 'folder' || 'folderopen' => Icons.folder_rounded,
    'timer' || 'deadline' || 'schedule' || 'clock' => Icons.timer_rounded,
    'person' || 'profile' || 'user' || 'avatar' || 'account' => Icons.person_rounded,
    'bell' || 'notification' || 'notifications' || 'inbox' => Icons.notifications_rounded,
    'check' || 'done' || 'completed' || 'verified' => Icons.check_circle_rounded,
    'warning' || 'alert' || 'delayed' || 'overdue' => Icons.warning_amber_rounded,
    'search' => Icons.search_rounded,
    'settings' => Icons.settings_rounded,
    'edit' => Icons.edit_rounded,
    'logout' => Icons.logout_rounded,
    'meeting' || 'video' || 'videocall' => Icons.video_call_rounded,
    'calendar' || 'calendarmonth' => Icons.calendar_month_rounded,
    'file' || 'files' || 'document' => Icons.folder_open_rounded,
    'group' || 'team' || 'members' => Icons.groups_rounded,
    'chart' || 'graph' || 'average' || 'autoGraph' || 'autograph' => Icons.auto_graph_rounded,
    'bolt' || 'active' => Icons.bolt_rounded,
    _ => Icons.circle_rounded,
  };
}

ProjectTask? _firstTask(WorkspaceState state) => state.visibleTasks.isEmpty ? null : state.visibleTasks.first;
Project? _firstProject(WorkspaceState state) => state.visibleProjects.isEmpty ? null : state.visibleProjects.first;

String _projectName(WorkspaceState state, String projectId) {
  for (final project in state.projects) {
    if (project.projectId == projectId) return project.name;
  }
  return projectId;
}

String _normalizeSearchQuery(String value) => value.trim().toLowerCase();
String _compactFilterToken(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-/]+'), '');

bool _isAllPageFilter(String value) {
  final token = _compactFilterToken(value);
  return token.isEmpty || token == 'all' || token == 'any' || token == 'everything' || token == 'showall';
}

bool _samePageFilter(String a, String b) => _compactFilterToken(a) == _compactFilterToken(b);

bool _containsSearchText(String query, Iterable<Object?> values) {
  if (query.isEmpty) return true;
  return values.where((value) => value != null).map((value) => value.toString()).join(' ').toLowerCase().contains(query);
}

bool _containsFilterText(String filter, Iterable<Object?> values) {
  if (_isAllPageFilter(filter)) return true;
  final q = _normalizeSearchQuery(filter);
  final token = _compactFilterToken(filter);
  final text = values.where((value) => value != null).map((value) => value.toString()).join(' ').toLowerCase();
  final compactText = _compactFilterToken(text);
  return text.contains(q) || compactText.contains(token);
}

String _teamNamesForProject(WorkspaceState state, Project project) {
  return state.teams
      .where((team) => project.teamIds.contains(team.teamId))
      .map((team) => '${team.name} ${team.description}')
      .join(' ');
}

String _managerNamesForProject(WorkspaceState state, Project project) {
  return state.members
      .where((member) => project.managerIds.contains(member.uid))
      .map((member) => '${member.displayName} ${member.email} ${member.role.label} ${member.effectiveDepartment}')
      .join(' ');
}

String _teamNameForTask(WorkspaceState state, ProjectTask task) {
  for (final team in state.teams) {
    if (team.teamId == task.teamId) return '${team.name} ${team.description}';
  }
  return task.teamId;
}

String _assigneeNamesForTask(WorkspaceState state, ProjectTask task) {
  return state.members
      .where((member) => task.assignedToIds.contains(member.uid))
      .map((member) => '${member.displayName} ${member.email} ${member.role.label} ${member.effectiveDepartment}')
      .join(' ');
}

bool _matchesProjectQuery(WorkspaceState state, Project project, String query) {
  return _containsSearchText(query, <Object?>[
    project.projectId,
    project.name,
    project.description,
    project.status.label,
    project.status.value,
    project.priority.label,
    project.priority.value,
    project.progress,
    project.totalTasks,
    project.completedTasks,
    project.budget,
    project.currency,
    DateText.compact(project.dueDate),
    _teamNamesForProject(state, project),
    _managerNamesForProject(state, project),
  ]);
}

bool _matchesTaskQuery(WorkspaceState state, ProjectTask task, String query) {
  return _containsSearchText(query, <Object?>[
    task.taskId,
    task.title,
    task.description,
    task.status.label,
    task.status.value,
    task.priority.label,
    task.priority.value,
    task.estimatedHours,
    task.loggedHours,
    task.attachmentsCount,
    task.commentsCount,
    task.tags.join(' '),
    DateText.compact(task.dueDate),
    _projectName(state, task.projectId),
    _teamNameForTask(state, task),
    _assigneeNamesForTask(state, task),
  ]);
}

bool _matchesProjectFilter(WorkspaceState state, Project project, String filter) {
  if (_isAllPageFilter(filter)) return true;
  final token = _compactFilterToken(filter);
  if (token == 'active' || token == 'inprogress' || token == 'ongoing') return project.isActiveWork || project.status == ProjectStatus.active;
  if (token == 'open') return project.isOpenWork;
  if (token == 'delayed' || token == 'overdue' || token == 'late') return project.isDelayed;
  if (token == 'completed' || token == 'complete' || token == 'done' || token == 'closed') return project.status == ProjectStatus.completed;
  if (token == 'onhold' || token == 'hold' || token == 'paused') return project.status == ProjectStatus.onHold;
  if (token == 'review' || token == 'inreview') return project.status == ProjectStatus.review;
  if (token == 'planning' || token == 'planned') return project.status == ProjectStatus.planning;
  if (token == 'cancelled' || token == 'canceled' || token == 'cancelledprojects') return project.status == ProjectStatus.cancelled;
  return _containsFilterText(filter, <Object?>[
    project.name,
    project.description,
    project.status.label,
    project.status.value,
    project.priority.label,
    project.priority.value,
    project.isOpenWork ? 'open active in progress' : '',
    project.isDelayed ? 'delayed overdue late' : '',
    _teamNamesForProject(state, project),
    _managerNamesForProject(state, project),
  ]);
}

bool _matchesTaskFilter(WorkspaceState state, ProjectTask task, String filter) {
  if (_isAllPageFilter(filter)) return true;
  final token = _compactFilterToken(filter);
  if (token == 'new' || token == 'newarrival' || token == 'open' || token == 'pending') return task.status != TaskStatus.completed;
  if (token == 'completed' || token == 'complete' || token == 'done' || token == 'closed') return task.status == TaskStatus.completed;
  if (token == 'overdue' || token == 'delayed' || token == 'late') return task.isOverdue;
  if (token == 'today') return _isSameDate(task.dueDate, DateTime.now());
  if (token == 'backlog') return task.status == TaskStatus.backlog;
  if (token == 'todo') return task.status == TaskStatus.todo;
  if (token == 'inprogress' || token == 'active') return task.status == TaskStatus.inProgress;
  if (token == 'review' || token == 'inreview') return task.status == TaskStatus.review;
  if (token == 'testing' || token == 'qa') return task.status == TaskStatus.testing;
  if (token == 'low' || token == 'medium' || token == 'high' || token == 'critical') return task.priority.value == token;
  return _containsFilterText(filter, <Object?>[
    task.title,
    task.description,
    task.status.label,
    task.status.value,
    task.priority.label,
    task.priority.value,
    task.tags.join(' '),
    task.isOverdue ? 'overdue delayed late' : '',
    DateText.compact(task.dueDate),
    _projectName(state, task.projectId),
    _teamNameForTask(state, task),
    _assigneeNamesForTask(state, task),
  ]);
}

bool _matchesBoardStatusFilter(WorkspaceState state, TaskStatus status, String filter) {
  if (_isAllPageFilter(filter)) return true;
  final statusMatches = _containsFilterText(filter, <Object?>[status.label, status.value]);
  final taskMatches = state.visibleTasks.any((task) => task.status == status && _matchesTaskFilter(state, task, filter));
  return statusMatches || taskMatches;
}

bool _matchesNotificationFilter(WorkspaceState state, dynamic item, String filter) {
  if (_isAllPageFilter(filter)) return true;
  final token = _compactFilterToken(filter);
  try {
    if (token == 'unread') return item.isRead == false;
    if (token == 'read') return item.isRead == true;
    if (token == 'meeting' || token == 'meetings') return item.isMeetingInvite == true;
  } catch (_) {}
  return _containsFilterText(filter, <Object?>[
    _safeDynamicText(item, 'title'),
    _safeDynamicText(item, 'message'),
    _safeDynamicText(item, 'type'),
    _safeDynamicText(item, 'actionType'),
    _safeDynamicText(item, 'actionLabel'),
    _safeDynamicText(item, 'recipientRole'),
    _safeDynamicText(item, 'recipientRoleGroup'),
    _safeDynamicText(item, 'actionUrl'),
    _safeDynamicBool(item, 'isRead') == true ? 'read' : 'unread',
    _safeDynamicBool(item, 'isMeetingInvite') == true ? 'meeting meet invite' : '',
  ]);
}

bool _matchesMeetingFilter(WorkspaceState state, dynamic item, String filter) {
  if (_isAllPageFilter(filter)) return true;
  final token = _compactFilterToken(filter);
  final actionUrl = _safeDynamicText(item, 'actionUrl').toLowerCase();
  final actionType = _safeDynamicText(item, 'actionType').toLowerCase();
  if (token == 'today') {
    try {
      return _isSameDate(item.createdAt, DateTime.now());
    } catch (_) {
      return false;
    }
  }
  if (token == 'pending') return _safeDynamicBool(item, 'isRead') != true;
  if (token == 'accepted' || token == 'read') return _safeDynamicBool(item, 'isRead') == true;
  if (token == 'googlemeet' || token == 'meet') return actionUrl.contains('meet.google') || actionType.contains('meet');
  if (token == 'whatsapp' || token == 'wa') return actionUrl.contains('wa.me') || actionUrl.contains('whatsapp') || actionType.contains('whatsapp');
  return _matchesNotificationFilter(state, item, filter);
}

String _safeDynamicText(dynamic item, String field) {
  try {
    final value = switch (field) {
      'title' => item.title,
      'message' => item.message,
      'type' => item.type,
      'actionType' => item.actionType,
      'actionLabel' => item.actionLabel,
      'recipientRole' => item.recipientRole,
      'recipientRoleGroup' => item.recipientRoleGroup,
      'actionUrl' => item.actionUrl,
      _ => null,
    };
    return value?.toString() ?? '';
  } catch (_) {
    return '';
  }
}

bool? _safeDynamicBool(dynamic item, String field) {
  try {
    final value = switch (field) {
      'isRead' => item.isRead,
      'isMeetingInvite' => item.isMeetingInvite,
      _ => null,
    };
    return value == true;
  } catch (_) {
    return null;
  }
}

bool _matchesBoardStatusQuery(WorkspaceState state, TaskStatus status, String query) {
  if (query.isEmpty) return true;
  final statusMatches = _containsSearchText(query, <Object?>[status.label, status.value]);
  final taskMatches = state.visibleTasks.any((task) => task.status == status && _matchesTaskQuery(state, task, query));
  return statusMatches || taskMatches;
}

bool _matchesNotificationQuery(WorkspaceState state, dynamic item, String query) {
  String projectName = '';
  String taskTitle = '';
  String actorName = '';
  try {
    final dynamic projectId = item.projectId;
    if (projectId != null && projectId.toString().trim().isNotEmpty) projectName = _projectName(state, projectId.toString());
  } catch (_) {}
  try {
    final dynamic taskId = item.taskId;
    if (taskId != null && taskId.toString().trim().isNotEmpty) {
      ProjectTask? matchedTask;
      for (final task in state.visibleTasks) {
        if (task.taskId == taskId.toString()) {
          matchedTask = task;
          break;
        }
      }
      taskTitle = matchedTask?.title ?? taskId.toString();
    }
  } catch (_) {}
  try {
    final dynamic actorId = item.actorId;
    if (actorId != null && actorId.toString().trim().isNotEmpty) {
      final actor = state.members.where((member) => member.uid == actorId.toString()).toList();
      actorName = actor.isEmpty ? actorId.toString() : actor.first.displayName;
    }
  } catch (_) {}
  return _containsSearchText(query, <Object?>[
    item.notificationId,
    item.title,
    item.message,
    item.type,
    item.actionLabel,
    item.rejectLabel,
    item.actionType,
    item.actionUrl,
    item.recipientRole,
    item.recipientRoleGroup,
    item.isRead ? 'read' : 'unread',
    projectName,
    taskTitle,
    actorName,
  ]);
}

bool _matchesGenericPageItemQuery(WorkspaceState state, dynamic item, String query) {
  if (query.isEmpty) return true;
  if (item is Map && _matchesHomeSectionQuery(state, item, query)) return true;
  return _matchesGenericNodeQuery(item, query);
}

bool _matchesGenericPageItemFilter(WorkspaceState state, dynamic item, String filter) {
  if (_isAllPageFilter(filter)) return true;
  if (item is Map && _matchesHomeSectionFilter(state, item, filter)) return true;
  return _matchesGenericNodeFilter(item, filter);
}

bool _matchesHomeSectionQuery(WorkspaceState state, Map<dynamic, dynamic> section, String query) {
  if (query.isEmpty || _matchesGenericNodeQuery(section, query)) return true;
  final type = _canonicalWidgetType(section['type'] ?? section['widget'] ?? section['component'] ?? section['componentType'] ?? section['id']);
  switch (type) {
    case 'taskList':
    case 'todayTaskList':
    case 'taskPage':
    case 'taskMenu':
      final tasks = type == 'todayTaskList'
          ? state.visibleTasks.where((task) => _isSameDate(task.dueDate, DateTime.now()))
          : state.visibleTasks;
      return tasks.any((task) => _matchesTaskQuery(state, task, query));
    case 'projectPage':
    case 'projectList':
    case 'projectProgressCard':
    case 'activeProjectsGrid':
      return state.visibleProjects.any((project) => _matchesProjectQuery(state, project, query));
    case 'kanbanBoard':
      return TaskStatus.values.any((status) => _matchesBoardStatusQuery(state, status, query));
    case 'notificationList':
      return state.myNotifications.any((item) => _matchesNotificationQuery(state, item, query));
    case 'meetingPage':
    case 'meetingList':
      return state.myNotifications.where((item) => item.isMeetingInvite).any((item) => _matchesNotificationQuery(state, item, query));
    case 'deadlineCard':
    case 'deadlineHero':
      final openTasks = state.visibleTasks.where((task) => task.status != TaskStatus.completed).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      return openTasks.isNotEmpty && _matchesTaskQuery(state, openTasks.first, query);
    case 'onlineStatusCard':
      final member = state.currentMember;
      return _containsSearchText(query, <Object?>[
        member.displayName,
        member.email,
        member.role.label,
        member.effectiveDepartment,
        member.effectiveJobTitle,
        member.presenceLabel,
        member.location,
        member.available ? 'available' : 'unavailable',
      ]);
    case 'heroCard':
    case 'summaryCard':
    case 'metricCard':
    case 'metricTile':
      return _containsSearchText(query, <Object?>[
        state.company.name,
        state.currentMember.displayName,
        state.currentMember.role.label,
        '${state.visibleProjects.length} projects',
        '${state.visibleTasks.length} tasks',
        '${state.myUnreadNotificationCount} notifications',
      ]);
  }
  return false;
}

bool _matchesHomeSectionFilter(WorkspaceState state, Map<dynamic, dynamic> section, String filter) {
  if (_isAllPageFilter(filter)) return true;
  final type = _canonicalWidgetType(section['type'] ?? section['widget'] ?? section['component'] ?? section['componentType'] ?? section['id']);
  switch (type) {
    case 'taskList':
    case 'todayTaskList':
    case 'taskPage':
    case 'taskMenu':
      final tasks = type == 'todayTaskList'
          ? state.visibleTasks.where((task) => _isSameDate(task.dueDate, DateTime.now()))
          : state.visibleTasks;
      return tasks.any((task) => _matchesTaskFilter(state, task, filter));
    case 'projectPage':
    case 'projectList':
    case 'projectProgressCard':
    case 'activeProjectsGrid':
      return state.visibleProjects.any((project) => _matchesProjectFilter(state, project, filter));
    case 'kanbanBoard':
      return TaskStatus.values.any((status) => _matchesBoardStatusFilter(state, status, filter));
    case 'notificationList':
      return state.myNotifications.any((item) => _matchesNotificationFilter(state, item, filter));
    case 'meetingPage':
    case 'meetingList':
      return state.myNotifications.where((item) => item.isMeetingInvite).any((item) => _matchesMeetingFilter(state, item, filter));
    case 'deadlineCard':
    case 'deadlineHero':
      final openTasks = state.visibleTasks.where((task) => task.status != TaskStatus.completed).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      return openTasks.isNotEmpty && _matchesTaskFilter(state, openTasks.first, filter);
    case 'onlineStatusCard':
      final member = state.currentMember;
      return _containsFilterText(filter, <Object?>[
        member.displayName,
        member.email,
        member.role.label,
        member.effectiveDepartment,
        member.effectiveJobTitle,
        member.presenceLabel,
        member.location,
        member.available ? 'available online' : 'unavailable offline',
      ]);
    case 'heroCard':
    case 'summaryCard':
    case 'metricCard':
    case 'metricTile':
      return _matchesGenericNodeFilter(section, filter) || _containsFilterText(filter, <Object?>[
        state.company.name,
        state.currentMember.displayName,
        state.currentMember.role.label,
        '${state.visibleProjects.length} projects',
        '${state.visibleTasks.length} tasks',
        '${state.myUnreadNotificationCount} notifications',
      ]);
  }
  return _matchesGenericNodeFilter(section, filter);
}

bool _matchesGenericNodeQuery(dynamic node, String query) {
  if (query.isEmpty) return true;
  return _genericNodeSearchText(node).toLowerCase().contains(query);
}

bool _matchesGenericNodeFilter(dynamic node, String filter) {
  if (_isAllPageFilter(filter)) return true;
  return _containsFilterText(filter, <Object?>[_genericNodeSearchText(node)]);
}

String _genericNodeSearchText(dynamic node) {
  if (node == null) return '';
  if (node is String || node is num || node is bool) return node.toString();
  if (node is Iterable) return node.map(_genericNodeSearchText).join(' ');
  if (node is Map) {
    return node.entries.map((entry) => '${entry.key} ${_genericNodeSearchText(entry.value)}').join(' ');
  }
  return node.toString();
}

void _previewSnack(BuildContext context, bool previewMode, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(previewMode ? message : message), duration: const Duration(seconds: 1)),
  );
}

bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;


class _SduiRecoveryScreen extends StatelessWidget {
  const _SduiRecoveryScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8F5EF),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFECE7DA)),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.phonelink_setup_rounded, size: 34, color: Color(0xFF111111)),
                SizedBox(height: 12),
                Text(
                  'Mobile UI recovered',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF151515)),
                ),
                SizedBox(height: 6),
                Text(
                  'This SDUI config contains an unsupported or invalid block. The app stayed open instead of crashing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF76736D)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
