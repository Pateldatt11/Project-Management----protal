import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/constants/app_enums.dart';
import '../core/platform/workspace_platform.dart';
import '../core/crash/apk_crash_forensics.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/employee_app/presentation/employee_home_screen.dart';
import '../features/kanban/presentation/kanban_screen.dart';
import '../features/meetings/presentation/meetings_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/projects/presentation/projects_screen.dart';
import '../features/tasks/presentation/tasks_screen.dart';
import '../features/tasks/presentation/task_timeline_screen.dart';
import '../features/timeline/presentation/realtime_timeline_screen.dart';
import '../core/widgets/brew_haven_chat_sheet.dart';
import '../app/workspace_state.dart';
import '../app/app_surface.dart';
import '../data/firebase/auth_service.dart';
import '../data/models/mobile_ui_design.dart';
import 'server_driven/renderer/mobile_json_ui_renderer.dart';
import 'server_driven/sdui_floating_native_shell.dart';
import 'server_driven/sdui_mobile_ui_config.dart';

final employeeTabProvider = StateProvider<String>((ref) => 'home');

/// Search split:
/// - top-nav search opens universal search across projects/tasks/inbox.
/// - page-level search fields filter only their own page data.
final employeeInlineSearchVisibleProvider = StateProvider<bool>((ref) => false);
final employeeInlineSearchQueryProvider = StateProvider<String>((ref) => '');

class EmployeeMobileShell extends ConsumerWidget {
  const EmployeeMobileShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final member = state.currentMember;
    final selectedRaw = ref.watch(employeeTabProvider);
    final selected = _canonicalEmployeeRoute(selectedRaw);
    final inlineSearchVisible = ref.watch(employeeInlineSearchVisibleProvider);
    final inlineSearchQuery = ref.watch(employeeInlineSearchQueryProvider);
    final design = state.mobileUiDesign;
    final mobileConfig = state.mobileUiConfig;
    final useServerDrivenUi = ref.watch(useMobileServerDrivenUiProvider) &&
        (design.enabled || mobileConfig.enabled);
    final configuredTabs = useServerDrivenUi
        ? (design.enabled && design.bottomTabs.isNotEmpty
            ? design.bottomTabs
            : mobileConfig.bottomTabs)
        : (mobileConfig.enabled
            ? mobileConfig.bottomTabs
            : const <String>[
                'home',
                'tasks',
                'projects',
                'notifications',
                'profile'
              ]);
    final safeTabs = configuredTabs
        .map(_canonicalEmployeeRoute)
        .where(_isAllowedTab)
        .toSet()
        .toList();
    // Web employee surface gets the realtime Timeline as a real page without
    // changing the Android/iOS bottom-tab contract.
    if (WorkspacePlatform.isWeb && !safeTabs.contains('timeline'))
      safeTabs.insert(safeTabs.length.clamp(0, 3).toInt(), 'timeline');
    if (safeTabs.isEmpty) safeTabs.add('profile');
    // Inbox is now an upper-nav action, not a bottom-nav item. Keep the
    // notification screen routable even when admins remove notifications from
    // the bottom tab list.
    final contentTabs = <String>{
      ...safeTabs,
      'notifications',
      // Keep all side-menu/nested routes selectable even when they are not
      // published as bottom tabs. Without this, tapping Task Timeline from
      // the side drawer sets the tab for one frame and then the shell
      // normalizes it back to the first bottom tab (Dashboard/Home).
      ...const <String>[
        'taskMap',
        'timeline',
        'taskTimeline',
        'files',
        'calendar',
        'teamMembers',
        'taskDetail',
        'projectDetail',
        'meetingDetail',
        'meetings',
        'board',
        'onboarding',
      ],
      ...mobileConfig.screenConfigs.keys
          .map((key) => _canonicalEmployeeRoute(key.toString())),
      ...design.screenConfigs.keys
          .map((key) => _canonicalEmployeeRoute(key.toString())),
      ...design.screenOverrides.keys.map(_canonicalEmployeeRoute),
    }.map(_canonicalEmployeeRoute).where(_isAllowedTab).toList();
    final navTabs = safeTabs.where((tab) => tab != 'notifications').toList();
    if (navTabs.isEmpty)
      navTabs.addAll(contentTabs.where((tab) => tab != 'notifications'));
    if (navTabs.isEmpty) navTabs.add('profile');
    final safeSelected = contentTabs.contains(selected)
        ? selected
        : (navTabs.contains(selected) ? selected : navTabs.first);
    ApkCrashForensics.setScreen(
        tab: safeSelected, route: 'employee_mobile_shell');

    if (selectedRaw != selected || safeSelected != selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(employeeTabProvider.notifier).state = safeSelected;
      });
    }

    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final unread = state.myUnreadNotificationCount;

    if (useServerDrivenUi) {
      final runtimeSduiConfig =
          SduiMobileUiConfig.fromFirestore(_runtimeSduiJson(state, design));
      // v118: let the shared SDUI shell handle compact bottom dock versus
      // medium/large navigation rail. Do not bypass it on tablets, foldables,
      // desktop windows, or landscape; otherwise APK and live preview drift.
      final useFloatingNativeShell = runtimeSduiConfig.floatingTopEnabled ||
          runtimeSduiConfig.floatingBottomEnabled ||
          runtimeSduiConfig.preserveNativeShell;
      if (useFloatingNativeShell) {
        return SduiFloatingNativeShell(
          config: runtimeSduiConfig,
          currentTab: safeSelected,
          unreadCount: unread,
          userInitials: _userInitials(state),
          onTabSelected: (tab) {
            final route = _canonicalEmployeeRoute(tab);
            ApkCrashForensics.log('employee_tab_selected',
                data: <String, Object?>{'tab': tab, 'route': route});
            if (_isAllowedTab(route)) {
              ref.read(employeeTabProvider.notifier).state = route;
              ApkCrashForensics.log('employee_route_commit_success',
                  data: <String, Object?>{'raw': tab, 'route': route});
              ApkCrashForensics.setScreen(
                  tab: route, route: 'employee_mobile_shell');
            } else {
              ApkCrashForensics.log('employee_route_rejected',
                  data: <String, Object?>{'raw': tab, 'route': route});
            }
            ref.read(employeeInlineSearchQueryProvider.notifier).state = '';
            ref.read(employeeInlineSearchVisibleProvider.notifier).state =
                false;
          },
          onActiveTabRetap: () {
            // The shell consumes repeated active-tab taps. Individual screens can
            // attach scroll-to-top controllers later without changing Firestore JSON.
          },
          onAction: (action) => _handleEditorialAction(context, ref, action),
          searchQuery: inlineSearchQuery,
          onSearchChanged: (value) => ref
              .read(employeeInlineSearchQueryProvider.notifier)
              .state = value,
          onSearchClear: () =>
              ref.read(employeeInlineSearchQueryProvider.notifier).state = '',
          onSearchSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              _openUniversalSearch(context, ref, initialQuery: value.trim());
            }
          },
          child: Stack(
            children: [
              Column(
                children: [
                  if (inlineSearchVisible && inlineSearchQuery.trim().isEmpty)
                    _EmployeeInlineRuntimeSearchBar(
                      tab: safeSelected,
                      query: '',
                      onChanged: (value) {},
                      onClose: () {
                        ref
                            .read(employeeInlineSearchVisibleProvider.notifier)
                            .state = false;
                      },
                    ),
                  Expanded(
                    child: safeSelected == 'taskTimeline'
                        ? const TaskTimelineScreen()
                        : MobileJsonUiRenderer(
                            key:
                                ValueKey<String>('employee-sdui-$safeSelected'),
                            json: _jsonForTabFromSdui(
                                runtimeSduiConfig, design, safeSelected),
                            fallback: _nativeScreenFor(safeSelected),
                            onAction: (action) =>
                                _handleEditorialAction(context, ref, action),
                            // Top pill search is global/universal only. Page filtering is owned
                            // by the page-level search fields inside MobileJsonUiRenderer.
                            runtimeSearchQuery: '',
                            suppressPageSearchBars: false,
                          ),
                  ),
                ],
              ),
              if (inlineSearchQuery.trim().isNotEmpty)
                Positioned(
                  left: 14,
                  right: 14,
                  top: 8,
                  child: _UniversalSearchLiveResults(
                    state: state,
                    query: inlineSearchQuery,
                    onClose: () => ref
                        .read(employeeInlineSearchQueryProvider.notifier)
                        .state = '',
                    onOpenRoute: (route) {
                      ref
                          .read(employeeInlineSearchQueryProvider.notifier)
                          .state = '';
                      ref.read(employeeTabProvider.notifier).state =
                          _canonicalEmployeeRoute(route);
                    },
                  ),
                ),
              if (WorkspacePlatform.isWeb)
                Positioned(
                  key: const ValueKey<String>('employee-web-floating-logout'),
                  right: 18,
                  bottom: 18,
                  child: _EmployeeWebLogoutPill(
                      onTap: () => _employeeWebLogout(ref)),
                ),
              const Positioned(
                right: 18,
                bottom: 112,
                child: BrewHavenChatLauncher(),
              ),
            ],
          ),
        );
      }

      // Employee APK server-driven mode: no fixed admin/web shell is injected.
      // The screen body and nav style are driven by the published mobile JSON design.
      return Scaffold(
        backgroundColor: _color(design.background, const Color(0xFFF6F8FB)),
        body: SafeArea(
          child: Row(
            children: [
              if (isWide)
                _ServerDrivenRail(
                  tabs: navTabs,
                  activeTab: safeSelected,
                  unreadCount: unread,
                  accent: _color(design.accent, const Color(0xFF2563EB)),
                  onChanged: (tab) {
                    ApkCrashForensics.log('employee_rail_tab_selected',
                        data: <String, Object?>{'tab': tab});
                    ref.read(employeeTabProvider.notifier).state =
                        _canonicalEmployeeRoute(tab);
                  },
                ),
              Expanded(
                child: Column(
                  children: [
                    _EmployeeTopNav(
                      state: state,
                      topNav: design.topNav,
                      unreadCount: unread,
                      accent: _color(design.accent, const Color(0xFF2563EB)),
                      surface: _color(design.surface, Colors.white),
                      onInbox: () {
                        HapticFeedback.selectionClick();
                        ApkCrashForensics.log('top_nav_inbox_opened');
                        ref.read(employeeTabProvider.notifier).state =
                            'notifications';
                      },
                      onLogout: () => _employeeWebLogout(ref),
                    ),
                    if (inlineSearchVisible)
                      Row(
                        children: [
                          Expanded(
                            child: _EmployeeInlineRuntimeSearchBar(
                              tab: safeSelected,
                              query: inlineSearchQuery,
                              onChanged: (value) => ref
                                  .read(employeeInlineSearchQueryProvider.notifier)
                                  .state = value,
                              onClose: () {
                                ref
                                    .read(employeeInlineSearchQueryProvider.notifier)
                                    .state = '';
                                ref
                                    .read(
                                        employeeInlineSearchVisibleProvider.notifier)
                                    .state = false;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: BrewHavenChatLauncher.topAligned(),
                          ),
                        ],
                      ),
                    Expanded(
                      child: safeSelected == 'taskTimeline'
                          ? const TaskTimelineScreen()
                          : MobileJsonUiRenderer(
                              key: ValueKey<String>(
                                  'employee-sdui-legacy-$safeSelected'),
                              json: _jsonForTab(design, safeSelected),
                              fallback: _nativeScreenFor(safeSelected),
                              onAction: (action) =>
                                  _handleEditorialAction(context, ref, action),
                              runtimeSearchQuery: '',
                              suppressPageSearchBars: false,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: isWide
            ? null
            : _ServerDrivenBottomNav(
                design: design,
                tabs: navTabs,
                activeTab: safeSelected,
                unreadCount: unread,
                onChanged: (tab) => ref
                    .read(employeeTabProvider.notifier)
                    .state = _canonicalEmployeeRoute(tab),
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            const Icon(Icons.task_alt_rounded),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.company.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    '${member.role.label} • ${WorkspacePlatform.surfaceLabel}${state.mobileUiConfig.enabled ? ' • Remote UI' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              avatar: Icon(
                  member.isOnline ? Icons.circle : Icons.radio_button_unchecked,
                  size: 14,
                  color: member.isOnline ? Colors.green : Colors.grey),
              label: Text(member.isOnline ? 'Online' : 'Offline'),
            ),
          ),
          IconButton(
            tooltip: 'Private notifications',
            onPressed: () {
              HapticFeedback.selectionClick();
              ref.read(employeeTabProvider.notifier).state = 'notifications';
            },
            icon: _EmployeeNotificationBell(unreadCount: unread),
          ),
          if (WorkspacePlatform.isWeb)
            IconButton(
              tooltip: 'Logout employee web session',
              onPressed: () => _employeeWebLogout(ref),
              icon: const Icon(Icons.logout_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: _safeIndex(navTabs, safeSelected),
              extended: true,
              labelType: NavigationRailLabelType.none,
              destinations: navTabs
                  .map((tab) => NavigationRailDestination(
                      icon: Icon(_iconForTab(tab)),
                      label: Text(_labelForTab(tab))))
                  .toList(),
              onDestinationSelected: (index) =>
                  ref.read(employeeTabProvider.notifier).state = navTabs[index],
            ),
          Expanded(child: _nativeScreenFor(safeSelected)),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _safeIndex(navTabs, safeSelected),
              onDestinationSelected: (index) =>
                  ref.read(employeeTabProvider.notifier).state = navTabs[index],
              destinations: navTabs
                  .map((tab) => NavigationDestination(
                      icon: Icon(_iconForTab(tab)), label: _labelForTab(tab)))
                  .toList(),
            ),
      floatingActionButton: const BrewHavenChatLauncher(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  static Map<String, dynamic> _runtimeSduiJson(
      WorkspaceState state, MobileUiDesign design) {
    final config = state.mobileUiConfig;
    final configMap = config.toMap(updatedBy: config.updatedBy);
    final designMap = design.toMap(updatedBy: design.updatedBy);
    final baseMap = design.enabled
        ? <String, dynamic>{...configMap, ...designMap}
        : <String, dynamic>{...designMap, ...configMap};
    final tabs = design.enabled && design.bottomTabs.isNotEmpty
        ? design.bottomTabs
        : config.bottomTabs;
    return <String, dynamic>{
      ...baseMap,
      'enabled': design.enabled || config.enabled,
      'version':
          design.version > config.version ? design.version : config.version,
      'bottomTabs': tabs,
      'topNav': design.enabled && design.topNav.isNotEmpty
          ? design.topNav
          : config.topNav,
      'bottomNav': <String, dynamic>{
        ...config.bottomNav,
        if (design.enabled) ...design.bottomNav,
        'tabs': tabs,
      },
      'designSystem': design.enabled && design.designSystem.isNotEmpty
          ? design.designSystem
          : config.designSystem,
      'animationConfig': design.enabled && design.animationConfig.isNotEmpty
          ? design.animationConfig
          : config.animationConfig,
      'layoutConfig': design.enabled && design.layoutConfig.isNotEmpty
          ? design.layoutConfig
          : config.layoutConfig,
      'navigationConfig': design.enabled && design.navigationConfig.isNotEmpty
          ? design.navigationConfig
          : config.navigationConfig,
      'floatingTopNav': design.enabled && design.floatingTopNav.isNotEmpty
          ? design.floatingTopNav
          : config.floatingTopNav,
      'floatingBottomNav': design.enabled && design.floatingBottomNav.isNotEmpty
          ? design.floatingBottomNav
          : config.floatingBottomNav,
      'quickActionDock': design.enabled && design.quickActionDock.isNotEmpty
          ? design.quickActionDock
          : config.quickActionDock,
      'sideMenuConfig': _mapOf(designMap['sideMenuConfig']).isNotEmpty
          ? _mapOf(designMap['sideMenuConfig'])
          : _mapOf(configMap['sideMenuConfig']),
      'screenRegistry': _mapOf(designMap['screenRegistry']).isNotEmpty
          ? _mapOf(designMap['screenRegistry'])
          : _mapOf(configMap['screenRegistry']),
      'navigationGraph': _mapOf(designMap['navigationGraph']).isNotEmpty
          ? _mapOf(designMap['navigationGraph'])
          : _mapOf(configMap['navigationGraph']),
      'homeLayout': design.enabled && design.homeLayout.isNotEmpty
          ? design.homeLayout
          : config.homeLayout,
      'homeCardConfig': design.enabled && design.homeCardConfig.isNotEmpty
          ? design.homeCardConfig
          : config.homeCardConfig,
      'screenConfigs': design.enabled && design.screenConfigs.isNotEmpty
          ? design.screenConfigs
          : config.screenConfigs,
      'profileCardConfig': design.enabled && design.profileCardConfig.isNotEmpty
          ? design.profileCardConfig
          : config.profileCardConfig,
      'projectListConfig': design.enabled && design.projectListConfig.isNotEmpty
          ? design.projectListConfig
          : config.projectListConfig,
      'dataBindings': design.enabled && design.dataBindings.isNotEmpty
          ? design.dataBindings
          : config.dataBindings,
      'rendererCompatibility':
          design.enabled && design.rendererCompatibility.isNotEmpty
              ? design.rendererCompatibility
              : config.rendererCompatibility,
      'inboxConfig': design.enabled && design.inboxConfig.isNotEmpty
          ? design.inboxConfig
          : config.inboxConfig,
      'supportedWidgets': design.enabled && design.supportedWidgets.isNotEmpty
          ? design.supportedWidgets
          : config.supportedWidgets,
      'profileFields': design.enabled && design.profileFields.isNotEmpty
          ? design.profileFields
          : config.profileFields,
      'notificationAlertConfig':
          design.enabled && design.notificationAlertConfig.isNotEmpty
              ? design.notificationAlertConfig
              : config.notificationAlertConfig,
      'notificationSoundOptions':
          design.enabled && design.notificationSoundOptions.isNotEmpty
              ? design.notificationSoundOptions
              : config.notificationSoundOptions,
      'texts': _mapOf(designMap['texts']).isNotEmpty
          ? _mapOf(designMap['texts'])
          : _mapOf(configMap['texts'] ??
              configMap['text'] ??
              configMap['strings'] ??
              configMap['copy']),
    };
  }

  static bool _shouldUseEditorialNativeParity(
      SduiMobileUiConfig config, MobileUiDesign design) {
    final mode = config.designSystem['mode']?.toString().trim();
    final designId = config.designSystem['id']?.toString().trim();
    final template = design.templateName.trim();
    final rendererCompatibility = config.rendererCompatibility;
    final forceParity = rendererCompatibility['forcePreviewParity'] == true ||
        rendererCompatibility['forceFlutterPreviewParity'] == true;
    return forceParity ||
        template == 'editorialNativeUi' ||
        mode == 'minimalPaperNative' ||
        designId == 'managementEditorialNative2026';
  }

  static void _handleEditorialAction(
      BuildContext context, WidgetRef ref, String action) {
    HapticFeedback.selectionClick();
    final normalized = _canonicalRuntimeAction(action);
    switch (normalized) {
      case 'home':
        ref.read(employeeTabProvider.notifier).state = 'home';
        return;
      case 'inbox':
      case 'openInbox':
        ref.read(employeeTabProvider.notifier).state = 'notifications';
        return;
      case 'openProfile':
        ref.read(employeeTabProvider.notifier).state = 'profile';
        return;
      case 'openBoard':
        ref.read(employeeTabProvider.notifier).state = 'board';
        return;
      case 'openMeetings':
        ref.read(employeeTabProvider.notifier).state = 'meetings';
        return;
      case 'openTaskMap':
        ref.read(employeeTabProvider.notifier).state = 'taskMap';
        return;
      case 'openTimeline':
        ref.read(employeeTabProvider.notifier).state = 'timeline';
        return;
      case 'openTaskTimeline':
        ref.read(employeeTabProvider.notifier).state = 'taskTimeline';
        return;
      case 'openFiles':
        ref.read(employeeTabProvider.notifier).state = 'files';
        return;
      case 'openCalendar':
        ref.read(employeeTabProvider.notifier).state = 'calendar';
        return;
      case 'openTeamMembers':
        ref.read(employeeTabProvider.notifier).state = 'teamMembers';
        return;
      case 'openTaskDetail':
        ref.read(employeeTabProvider.notifier).state = 'taskDetail';
        return;
      case 'openProjectDetail':
        ref.read(employeeTabProvider.notifier).state = 'projectDetail';
        return;
      case 'openMeetingDetail':
        ref.read(employeeTabProvider.notifier).state = 'meetingDetail';
        return;
      case 'createTask':
      case 'openTask':
      case 'openTasks':
        ref.read(employeeTabProvider.notifier).state = 'tasks';
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Open Tasks to create or update work.')));
        return;
      case 'createProject':
      case 'openProject':
      case 'openProjects':
        ref.read(employeeTabProvider.notifier).state = 'projects';
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Open Projects to create or review project work.')));
        return;
      case 'uploadFile':
        ref.read(employeeTabProvider.notifier).state = 'tasks';
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Open a task to upload files.')));
        return;
      case 'smartSearch':
        _openUniversalSearch(context, ref);
        return;
      case 'openProjectAi':
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (sheetContext) => const BrewHavenChatSheet(),
        );
        return;
      case 'logout':
        _employeeWebLogout(ref);
        return;
    }
  }

  static Future<void> _openUniversalSearch(BuildContext context, WidgetRef ref,
      {String initialQuery = ''}) async {
    final state = ref.read(workspaceProvider);
    final controller = TextEditingController(text: initialQuery);
    String query = initialQuery;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final q = query.trim().toLowerCase();
            bool contains(String value) =>
                q.isEmpty || value.toLowerCase().contains(q);

            final projectResults = state.visibleProjects
                .where((project) {
                  return contains(
                      '${project.name} ${project.description} ${project.status.label}');
                })
                .take(6)
                .toList();
            final taskResults = state.visibleTasks
                .where((task) {
                  final projectName =
                      _projectNameForSearch(state, task.projectId);
                  return contains(
                      '${task.title} ${task.description} ${task.status.label} ${task.priority.label} $projectName');
                })
                .take(6)
                .toList();
            final notificationResults = state.myNotifications
                .where((item) {
                  if (item.isMeetingInvite) return false;
                  return contains(
                      '${item.title} ${item.message} ${item.type} ${item.actorId ?? ''}');
                })
                .take(5)
                .toList();
            final meetingResults = state.myNotifications
                .where((item) {
                  if (!item.isMeetingInvite) return false;
                  return contains(
                      '${item.title} ${item.message} ${item.actionUrl ?? ''} ${item.actorId ?? ''} ${item.actionLabel ?? ''}');
                })
                .take(5)
                .toList();

            final hasResults = projectResults.isNotEmpty ||
                taskResults.isNotEmpty ||
                notificationResults.isNotEmpty ||
                meetingResults.isNotEmpty;

            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .82),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Universal search',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.4),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) => setSheetState(() => query = value),
                      decoration: InputDecoration(
                        hintText: 'Search projects, tasks, inbox, meetings...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.trim().isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  controller.clear();
                                  setSheetState(() => query = '');
                                },
                              ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: hasResults
                          ? ListView(
                              shrinkWrap: true,
                              physics: const BouncingScrollPhysics(),
                              children: [
                                if (projectResults.isNotEmpty) ...[
                                  const _SearchSectionTitle('Projects'),
                                  ...projectResults.map((project) =>
                                      _UniversalSearchTile(
                                        icon: Icons.folder_rounded,
                                        title: project.name,
                                        subtitle:
                                            '${project.status.label} • ${project.progress}% complete',
                                        onTap: () {
                                          Navigator.of(sheetContext).pop();
                                          ref
                                              .read(
                                                  employeeTabProvider.notifier)
                                              .state = 'projects';
                                        },
                                      )),
                                ],
                                if (taskResults.isNotEmpty) ...[
                                  const _SearchSectionTitle('Tasks'),
                                  ...taskResults.map((task) =>
                                      _UniversalSearchTile(
                                        icon: Icons.task_alt_rounded,
                                        title: task.title,
                                        subtitle:
                                            '${task.status.label} • ${_projectNameForSearch(state, task.projectId)}',
                                        onTap: () {
                                          Navigator.of(sheetContext).pop();
                                          ref
                                              .read(
                                                  employeeTabProvider.notifier)
                                              .state = 'tasks';
                                        },
                                      )),
                                ],
                                if (notificationResults.isNotEmpty) ...[
                                  const _SearchSectionTitle(
                                      'Inbox / Notifications'),
                                  ...notificationResults.map((item) =>
                                      _UniversalSearchTile(
                                        icon: item.isRead
                                            ? Icons.notifications_none_rounded
                                            : Icons
                                                .notifications_active_rounded,
                                        title: item.title,
                                        subtitle: item.message,
                                        onTap: () {
                                          Navigator.of(sheetContext).pop();
                                          ref
                                              .read(
                                                  employeeTabProvider.notifier)
                                              .state = 'notifications';
                                        },
                                      )),
                                ],
                                if (meetingResults.isNotEmpty) ...[
                                  const _SearchSectionTitle('Meetings'),
                                  ...meetingResults.map((item) =>
                                      _UniversalSearchTile(
                                        icon: Icons.video_call_rounded,
                                        title: item.title,
                                        subtitle:
                                            item.actionUrl?.trim().isNotEmpty ==
                                                    true
                                                ? item.actionUrl!.trim()
                                                : item.message,
                                        onTap: () {
                                          Navigator.of(sheetContext).pop();
                                          ref
                                              .read(
                                                  employeeTabProvider.notifier)
                                              .state = 'meetings';
                                        },
                                      )),
                                ],
                              ],
                            )
                          : const Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
                              child: Center(
                                child: Text(
                                  'No matching projects, tasks, inbox, or meetings.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black54),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _projectNameForSearch(WorkspaceState state, String projectId) {
    for (final project in state.projects) {
      if (project.projectId == projectId) return project.name;
    }
    return projectId;
  }

  static String _canonicalRuntimeAction(String raw) {
    var value = raw.split(':').first.trim();
    value = value.replaceAll(RegExp(r'^[#/]+'), '');
    final compact = value.replaceAll(RegExp(r'[\s_\-]+'), '').toLowerCase();
    return switch (compact) {
      'home' || 'openhome' => 'home',
      'inbox' ||
      'notification' ||
      'notifications' ||
      'openinbox' ||
      'opennotifications' =>
        'openInbox',
      'profile' || 'openprofile' => 'openProfile',
      'board' || 'kanban' || 'openboard' => 'openBoard',
      'meeting' || 'meetings' || 'openmeetings' => 'openMeetings',
      'taskmap' || 'taskmapsiteview' || 'opentaskmap' => 'openTaskMap',
      'tasktimeline' ||
      'taskprogresstimeline' ||
      'opentasktimeline' ||
      'opentaskprogresstimeline' =>
        'openTaskTimeline',
      'timeline' || 'timelinemilestones' || 'opentimeline' => 'openTimeline',
      'files' ||
      'file' ||
      'documents' ||
      'filesdocuments' ||
      'openfiles' =>
        'openFiles',
      'calendar' || 'calendarview' || 'opencalendar' => 'openCalendar',
      'teammembers' || 'members' || 'openteammembers' => 'openTeamMembers',
      'taskdetail' || 'taskdetails' || 'opentaskdetail' => 'openTaskDetail',
      'projectdetail' ||
      'projectdetails' ||
      'openprojectdetail' =>
        'openProjectDetail',
      'meetingdetail' ||
      'meetingdetails' ||
      'openmeetingdetail' =>
        'openMeetingDetail',
      'task' ||
      'tasks' ||
      'opentask' ||
      'opentasks' ||
      'tasklist' =>
        'openTasks',
      'project' ||
      'projects' ||
      'openproject' ||
      'openprojects' ||
      'projectlist' =>
        'openProjects',
      'createtask' || 'newtask' || 'addtask' => 'createTask',
      'createproject' || 'newproject' || 'addproject' => 'createProject',
      'uploadfile' || 'fileupload' || 'attachfile' => 'uploadFile',
      'smartsearch' || 'search' || 'focussearch' => 'smartSearch',
      'openprojectai' || 'projectai' || 'aichat' || 'openaichat' => 'openProjectAi',
      'logout' || 'signout' => 'logout',
      _ => value,
    };
  }

  static String _userInitials(WorkspaceState state) {
    final name = state.currentMember.displayName.trim().isNotEmpty
        ? state.currentMember.displayName.trim()
        : state.user.email.trim();
    if (name.isEmpty) return 'U';
    final parts =
        name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.length >= 2)
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return name.substring(0, 1).toUpperCase();
  }

  static Map<String, dynamic>? _effectiveOverride(
      Map<String, dynamic>? override, String tab) {
    if (override == null) return null;
    final targetTab = tab;
    // Admin emulator/import can accidentally publish a placeholder screen override
    // such as { widgets: ['Card'] } or { type: 'card', title: 'Card' }.
    // That must not replace the real APK Profile/Tasks/Projects screen.
    if (_isGenericPlaceholderOverride(override, targetTab)) return null;
    return override;
  }

  static const Set<String> _overrideChildKeys = <String>{
    'children',
    'sections',
    'items',
    'blocks',
    'widgets',
    'body',
    'content',
    'nodes',
  };

  static bool _isGenericPlaceholderOverride(
      Map<String, dynamic> override, String tab) {
    final type = (override['type'] ??
            override['widget'] ??
            override['component'] ??
            override['componentType'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    final title = (override['title'] ?? override['label'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final childValues = _overrideChildKeys
        .map((key) => override[key])
        .whereType<List>()
        .toList();
    final hasNonGenericChildren =
        childValues.any((list) => !_isGenericPlaceholderList(list));
    if (hasNonGenericChildren) return false;
    final ignoredKeys = <String>{
      'screen',
      'theme',
      'style',
      'type',
      'widget',
      'component',
      'componentType',
      'title',
      'label',
      'subtitle',
      'description',
      '_strictJsonOnly',
      'strictJsonOnly',
      'padding',
      'margin',
      'showStatusBar',
      'statusBar',
      ..._overrideChildKeys,
    };
    final meaningfulKeys = override.keys
        .map((key) => key.toString())
        .where((key) => !ignoredKeys.contains(key))
        .toList();
    final tabType = tab.trim().toLowerCase();
    final genericType = type.isEmpty ||
        type == tabType ||
        type == 'card' ||
        type == 'container' ||
        type == 'surface' ||
        type == 'panel';
    final genericTitle = title.isEmpty ||
        title == 'card' ||
        title == 'container' ||
        title == 'surface' ||
        title == 'panel';
    return tab.isNotEmpty &&
        genericType &&
        genericTitle &&
        meaningfulKeys.isEmpty;
  }

  static bool _isGenericPlaceholderList(List<dynamic> value) {
    if (value.isEmpty) return true;
    return value.every(_isGenericPlaceholderNode);
  }

  static bool _isGenericPlaceholderNode(dynamic node) {
    if (node == null) return true;
    if (node is String) {
      final value = node.trim().toLowerCase();
      return value.isEmpty ||
          value == 'card' ||
          value == 'container' ||
          value == 'surface' ||
          value == 'panel';
    }
    if (node is Map) {
      final map = node.map((key, value) => MapEntry(key.toString(), value));
      return _isGenericPlaceholderOverride(map, 'placeholder');
    }
    return false;
  }

  static String _canonicalEmployeeRoute(String raw) {
    final value = raw.trim();
    final compact = value.replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
    return switch (compact) {
      'home' || 'dashboard' || 'employeehome' => 'home',
      'task' || 'tasks' || 'tasklist' || 'mytasks' => 'tasks',
      'tasktimeline' ||
      'taskprogresstimeline' ||
      'productivetasktimeline' ||
      'deliveryuikittimeline' ||
      'deliveryappuikittimeline' =>
        'taskTimeline',
      'project' || 'projects' || 'projectlist' => 'projects',
      'board' || 'kanban' || 'kanbanboard' => 'board',
      'meeting' || 'meetings' || 'meetinglist' => 'meetings',
      'notification' ||
      'notifications' ||
      'inbox' ||
      'notificationlist' =>
        'notifications',
      'profile' || 'account' || 'myprofile' => 'profile',
      'taskmap' || 'taskmapsiteview' || 'siteview' => 'taskMap',
      'timeline' || 'timelinemilestones' || 'milestones' => 'timeline',
      'files' || 'file' || 'filesdocuments' || 'documents' => 'files',
      'calendar' || 'calendarview' || 'calendardeadlines' => 'calendar',
      'teammembers' || 'teamprojectmembers' || 'members' => 'teamMembers',
      'taskdetail' || 'taskdetails' => 'taskDetail',
      'projectdetail' || 'projectdetails' => 'projectDetail',
      'meetingdetail' || 'meetingdetails' => 'meetingDetail',
      'onboarding' || 'onboardingteamsetup' => 'onboarding',
      _ => value,
    };
  }

  static bool _isAllowedTab(String tab) {
    return const <String>{
      'home',
      'tasks',
      'projects',
      'board',
      'meetings',
      'notifications',
      'profile',
      'taskMap',
      'timeline',
      'taskTimeline',
      'files',
      'calendar',
      'teamMembers',
      'taskDetail',
      'projectDetail',
      'meetingDetail',
      'onboarding',
    }.contains(tab);
  }

  static String _labelForTab(String tab) {
    return switch (tab) {
      'home' => 'Home',
      'tasks' => 'Tasks',
      'projects' => 'Projects',
      'board' => 'Board',
      'meetings' => 'Meetings',
      'notifications' => 'Inbox',
      'profile' => 'Profile',
      'taskMap' => 'Task Map',
      'timeline' => 'Timeline',
      'taskTimeline' => 'Task Timeline',
      'files' => 'Files',
      'calendar' => 'Calendar',
      'teamMembers' => 'Team Members',
      'taskDetail' => 'Task Detail',
      'projectDetail' => 'Project Detail',
      'meetingDetail' => 'Meeting Detail',
      'onboarding' => 'Onboarding',
      _ => tab,
    };
  }

  static IconData _iconForTab(String tab) {
    return switch (tab) {
      'home' => Icons.home_rounded,
      'tasks' => Icons.task_alt_rounded,
      'projects' => Icons.folder_rounded,
      'board' => Icons.view_kanban_rounded,
      'meetings' => Icons.video_call_rounded,
      'notifications' => Icons.notifications_rounded,
      'profile' => Icons.person_rounded,
      'taskMap' => Icons.location_on_outlined,
      'timeline' => Icons.schedule_rounded,
      'taskTimeline' => Icons.view_timeline_rounded,
      'files' => Icons.folder_open_rounded,
      'calendar' => Icons.calendar_month_rounded,
      'teamMembers' => Icons.groups_rounded,
      'taskDetail' => Icons.assignment_rounded,
      'projectDetail' => Icons.folder_special_rounded,
      'meetingDetail' => Icons.video_camera_front_rounded,
      'onboarding' => Icons.flag_rounded,
      _ => Icons.circle_rounded,
    };
  }

  static Map<String, dynamic> _jsonForTabFromSdui(
      SduiMobileUiConfig config, MobileUiDesign design, String tab) {
    final rawScreenOverrides = _mapOf(config.raw['screenOverrides']);
    final rawScreenConfig = _mapOf(config.screenConfigs[tab]);
    final rawConfigOverride =
        _effectiveOverride(_mapOf(rawScreenOverrides[tab]), tab) ??
            _effectiveOverride(
                _mapOf(rawScreenConfig['override'] ??
                    rawScreenConfig['json'] ??
                    rawScreenConfig['body']),
                tab);
    final override = _effectiveOverride(design.screenOverrides[tab], tab) ??
        rawConfigOverride;
    if (override != null) {
      return <String, dynamic>{
        'screen': tab,
        '_strictJsonOnly': true,
        if (!override.containsKey('theme'))
          'theme': _themeFromSdui(config, design),
        ...override,
      };
    }

    final rawTaskCard = _mapOf(config.raw['taskCard']);
    final rawProjectCard = _mapOf(config.raw['projectCard']);
    final taskCard = <String, dynamic>{
      ...design.taskCard,
      ...rawTaskCard,
      'variant': (config.raw['taskCardVariant'] ??
              rawTaskCard['variant'] ??
              design.taskCard['variant'] ??
              'modernCard')
          .toString(),
      'showFields': _listOf(config.raw['taskCardFields'] ??
          rawTaskCard['showFields'] ??
          design.taskFields),
    };
    final projectCard = <String, dynamic>{
      ...design.projectCard,
      ...rawProjectCard,
      'variant': (config.raw['projectCardVariant'] ??
              rawProjectCard['variant'] ??
              design.projectCard['variant'] ??
              'progressCard')
          .toString(),
      'showFields': _listOf(config.raw['projectCardFields'] ??
          rawProjectCard['showFields'] ??
          design.projectFields),
    };

    final base = <String, dynamic>{
      'screen': tab,
      'templateName': config.templateName,
      'templateRendererMode': 'sduiJsonRenderer',
      'theme': _themeFromSdui(config, design),
      'title': config.titleForTab(tab),
      'texts': config.textConfig,
      'designSystem': config.designSystem,
      'layoutConfig': config.layoutConfig,
      'rendererCompatibility': <String, dynamic>{
        ...config.rendererCompatibility,
        'hardcodedBodyRenderer': false,
        'apkPreviewParityMode': 'sharedSduiJson',
      },
    };

    return switch (tab) {
      'home' => <String, dynamic>{
          ...base,
          'type': 'sectionList',
          'sections': _homeSectionsFromSdui(config,
              taskCard: taskCard, projectCard: projectCard),
        },
      'tasks' => <String, dynamic>{
          ...base,
          'type': 'taskPage',
          ...config.taskListConfig,
          'taskCard': taskCard,
          ...taskCard,
        },
      'projects' => <String, dynamic>{
          ...base,
          'type': 'projectPage',
          ...config.projectListConfig,
          'projectCard': projectCard,
          ...projectCard,
        },
      'board' => <String, dynamic>{...base, 'type': 'kanbanBoard'},
      'taskTimeline' => <String, dynamic>{
          ...base,
          'type': 'taskProgressTimeline',
          'variant': 'deliveryAppUIKitTimeline',
          'taskTimelineStyle': 'deliveryAppUIKitTimeline',
          'deliveryUIKitTimeline': true,
          'useDeliveryUIKitTimeline': true,
          'exactReferenceTimeline': false,
          'forceReferenceTimeline': false,
          'liveDataMode': true,
          'appTitle': 'Task Timeline',
          'showScreenHeader': true,
          'title': _designText(design, 'screens.taskTimeline.title',
              fallback: 'Task Timeline'),
          'subtitle': _designText(design, 'screens.taskTimeline.subtitle',
              fallback: ''),
          'axisStartDay': 0,
          'todayAxisIndex': 4,
          'selectedProgressIndex': 4,
          'referenceProgress': 0,
          'showReferenceFallbackWhenEmpty': false,
          'referenceFallbackWhenEmpty': false,
          'timelineTaskLimit': 6,
          'showTaskProgressCard': true,
          'showTaskTimelineBars': true,
          'showAgendaList': false,
          'timelineVisualConfig': <String, dynamic>{
            'enabled': true,
            'variant': 'deliveryAppUIKitTimeline',
            'taskTimelineStyle': 'deliveryAppUIKitTimeline',
            'deliveryUIKitTimeline': true,
            'useDeliveryUIKitTimeline': true,
            'exactReferenceTimeline': false,
            'forceReferenceTimeline': false,
            'liveDataMode': true,
            'taskTimelineActive': true,
            'showTaskProgressCard': true,
            'showTaskTimelineBars': true,
            'showAgendaList': false,
            'timelineTaskLimit': 6,
            'showReferenceFallbackWhenEmpty': false,
          },
        },
      'meetings' => <String, dynamic>{...base, 'type': 'meetingPage'},
      'notifications' => <String, dynamic>{...base, 'type': 'notificationList'},
      'profile' => <String, dynamic>{
          ...base,
          'type': 'profileSummary',
          'profileFields':
              _listOf(config.raw['profileFields'] ?? design.profileFields),
          'profileActions': <String, dynamic>{
            ...design.profileActions,
            ..._mapOf(config.raw['profileActions'])
          },
          'profileCardConfig': config.profileCardConfig,
        },
      'taskMap' => <String, dynamic>{...base, 'type': 'taskMap'},
      'timeline' => <String, dynamic>{...base, 'type': 'progressTimeline'},
      'files' => <String, dynamic>{...base, 'type': 'filesDocuments'},
      'calendar' => <String, dynamic>{...base, 'type': 'calendarView'},
      'teamMembers' => <String, dynamic>{...base, 'type': 'teamMembers'},
      'taskDetail' => <String, dynamic>{...base, 'type': 'taskDetails'},
      'projectDetail' => <String, dynamic>{...base, 'type': 'projectDetails'},
      'meetingDetail' => <String, dynamic>{...base, 'type': 'meetingPage'},
      'onboarding' => <String, dynamic>{...base, 'type': 'onboardingScreen'},
      _ => base,
    };
  }

  static List<Map<String, dynamic>> _homeSectionsFromSdui(
    SduiMobileUiConfig config, {
    required Map<String, dynamic> taskCard,
    required Map<String, dynamic> projectCard,
  }) {
    final requested = _listOf(config.homeLayout['sections']);
    final homeCards = _listOf(config.raw['homeCards']);
    final sectionIds = requested.isNotEmpty ? requested : homeCards;
    final normalized = sectionIds.isEmpty
        ? const <String>[
            'deadlineHero',
            'todayTasks',
            'myOpenTasks',
            'projectProgress'
          ]
        : sectionIds;
    return normalized.map((id) {
      final cardKey = id == 'deadlineHero' ? 'deadlineTimer' : id;
      final cardConfig = _mapOf(config.homeCardConfig[cardKey]);
      switch (id) {
        case 'workSummary':
          return <String, dynamic>{
            'id': 'workSummary',
            'type': 'summaryCard',
            'title': config.text('home.workSummary.title',
                fallback: 'Project Management Dashboard'),
            'subtitle': config.text('home.workSummary.subtitle',
                fallback:
                    'Your assigned work, deadlines, project progress, and team updates in one mobile workspace.'),
            'color': config.designSystem['textPrimary'] ?? '#0A0D0A',
            'radius': config.designSystem['radiusLarge'] ?? 28,
            'visible': true,
          };
        case 'deadlineHero':
        case 'deadlineTimer':
          return <String, dynamic>{
            'id': 'deadlineTimer',
            'type': 'deadlineHero',
            'title': config.text('home.deadlineTimer.title',
                fallback: 'Next deadline'),
            'variant': cardConfig['variant'] ?? 'darkEditorialHero',
            'visible': true,
          };
        case 'activeProjectsGrid':
          return <String, dynamic>{
            'id': 'activeProjectsGrid',
            'type': 'activeProjectsGrid',
            'title': config.text('home.activeProjectsGrid.title',
                fallback: 'Active projects'),
            'projectCard': projectCard,
            'visible': true,
          };
        case 'todayTasks':
          return <String, dynamic>{
            'id': 'todayTasks',
            'type': 'todayTaskList',
            'title': config.text('home.todayTasks.title', fallback: 'Today'),
            'limit': 3,
            'taskCard': taskCard,
            'visible': true,
          };
        case 'myOpenTasks':
          return <String, dynamic>{
            'id': 'myOpenTasks',
            'type': 'taskList',
            'title': config.text('home.myOpenTasks.title',
                fallback: 'My open tasks'),
            'limit': 4,
            'taskCard': taskCard,
            'visible': true,
          };
        case 'projectProgress':
          return <String, dynamic>{
            'id': 'projectProgress',
            'type': 'projectProgressCard',
            'title': config.text('home.projectProgress.title',
                fallback: 'Project progress'),
            'projectCard': projectCard,
            'visible': true,
          };
        case 'onlineStatus':
          return <String, dynamic>{
            'id': 'onlineStatus',
            'type': 'onlineStatusCard',
            'title': 'Status',
            'visible': true,
          };
        default:
          return <String, dynamic>{
            'id': id,
            'type': id,
            'title': id,
            'visible': true,
          };
      }
    }).toList();
  }

  static Map<String, dynamic> _themeFromSdui(
      SduiMobileUiConfig config, MobileUiDesign design) {
    return <String, dynamic>{
      ...design.theme,
      'mode': 'light',
      'background': config.designSystem['surface'] ?? design.background,
      'surface': config.designSystem['card'] ?? design.surface,
      'accent': config.designSystem['accent'] ?? design.accent,
      'textPrimary': config.designSystem['textPrimary'] ?? '#151515',
      'textSecondary': config.designSystem['textSecondary'] ?? '#76736D',
      'border': config.designSystem['border'] ?? '#ECE7DA',
      'cardRadius': config.designSystem['radiusLarge'] ??
          design.theme['cardRadius'] ??
          24,
      'cardPadding': config.layoutConfig['horizontalPadding'] ??
          design.theme['cardPadding'] ??
          16,
      'density': config.compactMode
          ? 'compact'
          : (design.theme['density'] ?? 'comfortable'),
    };
  }

  static Map<String, dynamic> _mapOf(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map)
      return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    return <String, dynamic>{};
  }

  static String _stringOf(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _lookupTextPath(Map<String, dynamic> source, String path) {
    if (path.trim().isEmpty) return '';
    dynamic current = source;
    for (final part in path.split('.')) {
      if (current is Map) {
        current = current[part];
      } else {
        return '';
      }
    }
    return _stringOf(current);
  }

  static String _designText(MobileUiDesign design, String key,
      {String fallback = ''}) {
    final texts = _mapOf(design.texts);
    final candidates = <String>{key, key.replaceAll('.', '_')};
    for (final candidate in candidates) {
      final direct = _stringOf(texts[candidate]);
      if (direct.isNotEmpty) return direct;
      final nested = _lookupTextPath(texts, candidate);
      if (nested.isNotEmpty) return nested;
    }
    return fallback;
  }

  static String _designTitleForTab(MobileUiDesign design, String tab) {
    final routeTitleMap = _mapOf(design.floatingTopNav['routeTitleMap']);
    final fromFloating = _stringOf(routeTitleMap[tab]);
    if (fromFloating.isNotEmpty) return fromFloating;

    final labels =
        _mapOf(design.texts['routeLabels'] ?? design.texts['screenLabels']);
    final fromText = _designText(design, 'routes.$tab',
        fallback: _designText(design, 'screens.$tab.title'));
    if (fromText.isNotEmpty) return fromText;

    final fromLabels = _stringOf(labels[tab]);
    if (fromLabels.isNotEmpty) return fromLabels;

    final screen = _mapOf(design.screenConfigs[tab]);
    final fromScreen = _stringOf(screen['label'] ?? screen['title']);
    if (fromScreen.isNotEmpty) return fromScreen;

    return _labelForTab(tab);
  }

  static List<String> _listOf(dynamic value) {
    if (value is Iterable)
      return value
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList();
    return const <String>[];
  }

  Widget _nativeScreenFor(String tab) {
    return switch (tab) {
      'home' => const EmployeeHomeScreen(),
      'projects' => const ProjectsScreen(),
      'tasks' => const TasksScreen(),
      'board' => const KanbanScreen(),
      'meetings' => const MeetingsScreen(),
      'notifications' => const NotificationsScreen(),
      'profile' => const ProfileScreen(),
      'taskMap' => const TasksScreen(),
      'timeline' => const RealtimeTimelineScreen(),
      'taskTimeline' => const TaskTimelineScreen(),
      'files' => const TasksScreen(),
      'calendar' => const TasksScreen(),
      'teamMembers' => const ProjectsScreen(),
      'taskDetail' => const TasksScreen(),
      'projectDetail' => const ProjectsScreen(),
      'meetingDetail' => const MeetingsScreen(),
      _ => const EmployeeHomeScreen(),
    };
  }

  static Map<String, dynamic> _jsonForTab(MobileUiDesign design, String tab) {
    final override = _effectiveOverride(design.screenOverrides[tab], tab);
    if (override != null) {
      return <String, dynamic>{
        'screen': tab,
        '_strictJsonOnly': true,
        if (!override.containsKey('theme')) 'theme': design.theme,
        ...override,
      };
    }
    final base = <String, dynamic>{
      'screen': tab,
      'theme': design.theme,
      'title': _designTitleForTab(design, tab),
      'texts': design.texts,
    };
    return switch (tab) {
      'home' => <String, dynamic>{...base, 'sections': design.sections},
      'tasks' => <String, dynamic>{
          ...base,
          'type': 'taskPage',
          ...design.taskListConfig,
          'taskCard': design.taskCard,
          ...design.taskCard
        },
      'projects' => <String, dynamic>{
          ...base,
          'type': 'projectPage',
          'projectCard': design.projectCard,
          ...design.projectCard
        },
      'board' => <String, dynamic>{...base, 'type': 'kanbanBoard'},
      'taskTimeline' => <String, dynamic>{
          ...base,
          'type': 'taskProgressTimeline',
          'variant': 'deliveryAppUIKitTimeline',
          'taskTimelineStyle': 'deliveryAppUIKitTimeline',
          'deliveryUIKitTimeline': true,
          'useDeliveryUIKitTimeline': true,
          'exactReferenceTimeline': false,
          'forceReferenceTimeline': false,
          'liveDataMode': true,
          'appTitle': 'Task Timeline',
          'showScreenHeader': true,
          'title': _designText(design, 'screens.taskTimeline.title',
              fallback: 'Task Timeline'),
          'subtitle': _designText(design, 'screens.taskTimeline.subtitle',
              fallback: ''),
          'axisStartDay': 0,
          'todayAxisIndex': 4,
          'selectedProgressIndex': 4,
          'referenceProgress': 0,
          'showReferenceFallbackWhenEmpty': false,
          'referenceFallbackWhenEmpty': false,
          'timelineTaskLimit': 6,
          'showTaskProgressCard': true,
          'showTaskTimelineBars': true,
          'showAgendaList': false,
          'timelineVisualConfig': <String, dynamic>{
            'enabled': true,
            'variant': 'deliveryAppUIKitTimeline',
            'taskTimelineStyle': 'deliveryAppUIKitTimeline',
            'deliveryUIKitTimeline': true,
            'useDeliveryUIKitTimeline': true,
            'exactReferenceTimeline': false,
            'forceReferenceTimeline': false,
            'liveDataMode': true,
            'taskTimelineActive': true,
            'showTaskProgressCard': true,
            'showTaskTimelineBars': true,
            'showAgendaList': false,
            'timelineTaskLimit': 6,
            'showReferenceFallbackWhenEmpty': false,
          },
        },
      'meetings' => <String, dynamic>{...base, 'type': 'meetingPage'},
      'notifications' => <String, dynamic>{...base, 'type': 'notificationList'},
      'profile' => <String, dynamic>{
          ...base,
          'type': 'profileSummary',
          'profileActions': design.profileActions
        },
      'taskMap' => <String, dynamic>{...base, 'type': 'taskMap'},
      'timeline' => <String, dynamic>{...base, 'type': 'progressTimeline'},
      'files' => <String, dynamic>{...base, 'type': 'filesDocuments'},
      'calendar' => <String, dynamic>{...base, 'type': 'calendarView'},
      'teamMembers' => <String, dynamic>{...base, 'type': 'teamMembers'},
      'taskDetail' => <String, dynamic>{...base, 'type': 'taskDetails'},
      'projectDetail' => <String, dynamic>{...base, 'type': 'projectDetails'},
      'meetingDetail' => <String, dynamic>{...base, 'type': 'meetingPage'},
      _ => base,
    };
  }
}

class _EmployeeInlineRuntimeSearchBar extends StatefulWidget {
  const _EmployeeInlineRuntimeSearchBar({
    required this.tab,
    required this.query,
    required this.onChanged,
    required this.onClose,
  });

  final String tab;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  State<_EmployeeInlineRuntimeSearchBar> createState() =>
      _EmployeeInlineRuntimeSearchBarState();
}

class _EmployeeInlineRuntimeSearchBarState
    extends State<_EmployeeInlineRuntimeSearchBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant _EmployeeInlineRuntimeSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hint = _hintForSearchTab(widget.tab);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        textInputAction: TextInputAction.search,
        onChanged: (value) {
          setState(() {});
          widget.onChanged(value);
        },
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon:
              const Icon(Icons.search_rounded, color: Color(0xFF5F6F5E)),
          suffixIcon: _controller.text.trim().isEmpty
              ? IconButton(
                  tooltip: 'Close search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: widget.onClose,
                )
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: Colors.black.withOpacity(.10)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: Colors.black.withOpacity(.10)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(999)),
            borderSide: BorderSide(color: Color(0xFF557847), width: 1.35),
          ),
        ),
      ),
    );
  }
}

String _hintForSearchTab(String tab) {
  final normalized = tab.trim().toLowerCase();
  return switch (normalized) {
    'projects' || 'project' => 'Search project name or details',
    'tasks' || 'task' => 'Search assigned tasks, project or priority',
    'board' || 'kanban' => 'Search board tasks or status',
    'notifications' || 'inbox' => 'Search inbox notifications',
    'meetings' => 'Search meetings',
    _ => 'Search projects, tasks, inbox...',
  };
}

class _UniversalSearchLiveResults extends StatelessWidget {
  const _UniversalSearchLiveResults({
    required this.state,
    required this.query,
    required this.onClose,
    required this.onOpenRoute,
  });

  final WorkspaceState state;
  final String query;
  final VoidCallback onClose;
  final ValueChanged<String> onOpenRoute;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const SizedBox.shrink();
    bool contains(String value) => value.toLowerCase().contains(q);

    final projectResults = state.visibleProjects
        .where((project) {
          final teamText = project.teamIds.join(' ');
          final managerText = project.managerIds.join(' ');
          return contains(
              '${project.name} ${project.description} ${project.status.label} $teamText $managerText');
        })
        .take(4)
        .toList();

    final taskResults = state.visibleTasks
        .where((task) {
          final projectName =
              EmployeeMobileShell._projectNameForSearch(state, task.projectId);
          return contains(
              '${task.title} ${task.description} ${task.status.label} ${task.priority.label} $projectName ${task.assignedToIds.join(' ')}');
        })
        .take(4)
        .toList();

    final notificationResults = state.myNotifications
        .where((item) {
          if (item.isMeetingInvite) return false;
          return contains(
              '${item.title} ${item.message} ${item.type} ${item.actorId ?? ''}');
        })
        .take(3)
        .toList();

    final meetingResults = state.myNotifications
        .where((item) {
          if (!item.isMeetingInvite) return false;
          return contains(
              '${item.title} ${item.message} ${item.actionUrl ?? ''} ${item.actorId ?? ''} ${item.actionLabel ?? ''}');
        })
        .take(3)
        .toList();

    final hasResults = projectResults.isNotEmpty ||
        taskResults.isNotEmpty ||
        notificationResults.isNotEmpty ||
        meetingResults.isNotEmpty;
    final height = MediaQuery.sizeOf(context).height;

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxHeight: height * .58),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.98),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.black.withOpacity(.10)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.18),
              blurRadius: 34,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.manage_search_rounded,
                        color: Color(0xFF557847)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Search all modules',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.2),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: hasResults
                    ? ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          if (projectResults.isNotEmpty) ...[
                            const _SearchSectionTitle('Projects'),
                            ...projectResults
                                .map((project) => _UniversalSearchTile(
                                      icon: Icons.folder_rounded,
                                      title: project.name,
                                      subtitle:
                                          '${project.status.label} • ${project.progress}% complete',
                                      onTap: () => onOpenRoute('projects'),
                                    )),
                          ],
                          if (taskResults.isNotEmpty) ...[
                            const _SearchSectionTitle('Tasks'),
                            ...taskResults.map((task) => _UniversalSearchTile(
                                  icon: Icons.task_alt_rounded,
                                  title: task.title,
                                  subtitle:
                                      '${task.status.label} • ${EmployeeMobileShell._projectNameForSearch(state, task.projectId)}',
                                  onTap: () => onOpenRoute('tasks'),
                                )),
                          ],
                          if (notificationResults.isNotEmpty) ...[
                            const _SearchSectionTitle('Inbox / Notifications'),
                            ...notificationResults
                                .map((item) => _UniversalSearchTile(
                                      icon: item.isRead
                                          ? Icons.notifications_none_rounded
                                          : Icons.notifications_active_rounded,
                                      title: item.title,
                                      subtitle: item.message,
                                      onTap: () => onOpenRoute('notifications'),
                                    )),
                          ],
                          if (meetingResults.isNotEmpty) ...[
                            const _SearchSectionTitle('Meetings'),
                            ...meetingResults
                                .map((item) => _UniversalSearchTile(
                                      icon: Icons.video_call_rounded,
                                      title: item.title,
                                      subtitle:
                                          item.actionUrl?.trim().isNotEmpty ==
                                                  true
                                              ? item.actionUrl!.trim()
                                              : item.message,
                                      onTap: () => onOpenRoute('meetings'),
                                    )),
                          ],
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                        child: Center(
                          child: Text(
                            'No result found for “$query”.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.black54),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchSectionTitle extends StatelessWidget {
  const _SearchSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
      child: Text(
        label,
        style: const TextStyle(
            fontWeight: FontWeight.w900, color: Colors.black54, fontSize: 12),
      ),
    );
  }
}

class _UniversalSearchTile extends StatelessWidget {
  const _UniversalSearchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.black.withOpacity(.08)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEFF4EA),
          child: Icon(icon, color: const Color(0xFF557847)),
        ),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
      ),
    );
  }
}

class _EmployeeTopNav extends StatelessWidget {
  const _EmployeeTopNav({
    required this.state,
    required this.topNav,
    required this.unreadCount,
    required this.accent,
    required this.surface,
    this.onInbox,
    this.onLogout,
  });

  final WorkspaceState state;
  final Map<String, dynamic> topNav;
  final int unreadCount;
  final Color accent;
  final Color surface;
  final VoidCallback? onInbox;
  final VoidCallback? onLogout;

  bool _flag(String key, {bool fallback = true}) {
    final value = topNav[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'yes' || normalized == '1')
        return true;
      if (normalized == 'false' || normalized == 'no' || normalized == '0')
        return false;
    }
    return fallback;
  }

  String _text(String key, {String fallback = ''}) {
    final value = topNav[key];
    final raw = value?.toString().trim() ?? '';
    return raw.isEmpty ? fallback : raw;
  }

  @override
  Widget build(BuildContext context) {
    if (!_flag('enabled')) return const SizedBox.shrink();

    final member = state.currentMember;
    final style = _text('style', fallback: 'glassAdvanced');
    final density = _text('density', fallback: 'comfortable');
    final compact = density == 'compact';
    final showInbox = _flag('showInbox');
    final showCompany = _flag('showCompanyName');
    final showRole = _flag('showUserRole');
    final showOnline = _flag('showOnlineStatus');
    final showAvatar = _flag('showAvatar');
    final showGlow = _flag('showPresenceGlow');
    final useGlass =
        style == 'glassAdvanced' || style == 'glass' || style == 'premium';

    final background =
        _color(state.mobileUiDesign.background, const Color(0xFFF6F8FB));
    final navSurface = useGlass ? Colors.white.withOpacity(.84) : surface;
    final borderColor =
        useGlass ? Colors.white.withOpacity(.72) : const Color(0xFFE2E8F0);
    final shadowColor = accent.withOpacity(useGlass ? .14 : .08);

    final content = Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10, vertical: compact ? 7 : 9),
      decoration: BoxDecoration(
        color: navSurface,
        gradient: useGlass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(.96),
                  Color.lerp(surface, accent, .035)!.withOpacity(.90),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
              color: shadowColor, blurRadius: 24, offset: const Offset(0, 12)),
          BoxShadow(
              color: Colors.white.withOpacity(.65),
              blurRadius: 12,
              offset: const Offset(-6, -6)),
        ],
      ),
      child: Row(
        children: [
          if (showInbox) ...[
            _InboxPill(
              unreadCount: unreadCount,
              accent: accent,
              compact: compact,
              showBadge: _flag('inboxBadge'),
              onTap: onInbox,
            ),
            SizedBox(width: compact ? 8 : 10),
          ],
          if (showAvatar) ...[
            _CompanyAvatar(
                name: state.company.name, accent: accent, compact: compact),
            SizedBox(width: compact ? 8 : 10),
          ],
          Expanded(
            child: _CompanyRoleText(
              companyName: showCompany ? state.company.name : '',
              roleLabel: showRole ? member.role.label : '',
              compact: compact,
            ),
          ),
          if (showOnline) ...[
            SizedBox(width: compact ? 6 : 8),
            _PresenceCapsule(
                online: member.isOnline,
                available: member.available,
                compact: compact,
                glow: showGlow),
          ],
          if (WorkspacePlatform.isWeb && onLogout != null) ...[
            SizedBox(width: compact ? 6 : 8),
            _EmployeeTopNavLogoutButton(compact: compact, onTap: onLogout!),
          ],
        ],
      ),
    );

    return Container(
      width: double.infinity,
      color: background,
      padding: EdgeInsets.fromLTRB(12, compact ? 8 : 10, 12, compact ? 7 : 9),
      child: useGlass
          ? ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: content,
              ),
            )
          : content,
    );
  }
}

class _CompanyAvatar extends StatelessWidget {
  const _CompanyAvatar(
      {required this.name, required this.accent, required this.compact});

  final String name;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final letter =
        name.trim().isEmpty ? 'D' : name.trim().substring(0, 1).toUpperCase();
    final size = compact ? 34.0 : 38.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(.95),
            Color.lerp(accent, Colors.black, .18)!
          ],
        ),
        boxShadow: [
          BoxShadow(
              color: accent.withOpacity(.28),
              blurRadius: 14,
              offset: const Offset(0, 7))
        ],
      ),
      child: Text(letter,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 13 : 15)),
    );
  }
}

class _CompanyRoleText extends StatelessWidget {
  const _CompanyRoleText(
      {required this.companyName,
      required this.roleLabel,
      required this.compact});

  final String companyName;
  final String roleLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final title = companyName.trim().isEmpty ? 'Workspace' : companyName.trim();
    final subtitle = roleLabel.trim().isEmpty ? 'Employee' : roleLabel.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: compact ? 13 : 15,
                letterSpacing: -.2)),
        const SizedBox(height: 2),
        Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w800,
                fontSize: compact ? 10 : 11)),
      ],
    );
  }
}

class _InboxPill extends StatelessWidget {
  const _InboxPill(
      {required this.unreadCount,
      required this.accent,
      required this.compact,
      required this.showBadge,
      this.onTap});

  final int unreadCount;
  final Color accent;
  final bool compact;
  final bool showBadge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 17.0 : 18.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap?.call();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12, vertical: compact ? 7 : 9),
          decoration: BoxDecoration(
            color: accent.withOpacity(.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withOpacity(.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.notifications_rounded,
                      color: accent, size: iconSize),
                  if (showBadge && unreadCount > 0)
                    Positioned(
                      right: -8,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(unreadCount > 9 ? '9+' : '$unreadCount',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900)),
                      ),
                    ),
                ],
              ),
              if (true) ...[
                const SizedBox(width: 7),
                Text('Inbox',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 11 : 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PresenceCapsule extends StatelessWidget {
  const _PresenceCapsule(
      {required this.online,
      required this.available,
      required this.compact,
      required this.glow});

  final bool online;
  final bool available;
  final bool compact;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final color = online ? const Color(0xFF16A34A) : const Color(0xFF64748B);
    final label = online ? (available ? 'Online' : 'Busy') : 'Offline';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 11, vertical: compact ? 7 : 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.24)),
        boxShadow: glow && online
            ? [
                BoxShadow(
                    color: color.withOpacity(.18),
                    blurRadius: 14,
                    offset: const Offset(0, 7))
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 9 : 10,
            height: compact ? 9 : 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: glow && online
                  ? [BoxShadow(color: color.withOpacity(.35), blurRadius: 8)]
                  : null,
            ),
          ),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 11 : 12)),
        ],
      ),
    );
  }
}

class _ServerDrivenBottomNav extends StatelessWidget {
  const _ServerDrivenBottomNav(
      {required this.design,
      required this.tabs,
      required this.activeTab,
      required this.unreadCount,
      required this.onChanged});

  final MobileUiDesign design;
  final List<String> tabs;
  final String activeTab;
  final int unreadCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = design.bottomNav['style']?.toString() ?? 'standard';
    final accent = _color(design.accent, const Color(0xFF2563EB));
    final surface = _color(design.surface, Colors.white);
    final activeIndex = _safeIndex(tabs, activeTab);

    if (style == 'standard') {
      return NavigationBar(
        selectedIndex: activeIndex,
        onDestinationSelected: (index) => onChanged(tabs[index]),
        destinations: tabs
            .map((tab) => NavigationDestination(
                icon: _navIcon(tab, unreadCount),
                label: EmployeeMobileShell._labelForTab(tab)))
            .toList(),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.fromLTRB(
            style == 'compact' ? 12 : 18, 8, style == 'compact' ? 12 : 18, 12),
        padding: EdgeInsets.symmetric(
            horizontal: style == 'compact' ? 8 : 10,
            vertical: style == 'compact' ? 6 : 8),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(.10),
                blurRadius: 24,
                offset: const Offset(0, 10))
          ],
        ),
        child: Row(
          children: tabs.map((tab) {
            final selected = tab == activeTab;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onChanged(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(
                      vertical: style == 'compact' ? 7 : 10, horizontal: 6),
                  decoration: BoxDecoration(
                    color:
                        selected ? accent.withOpacity(.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(EmployeeMobileShell._iconForTab(tab),
                          size: style == 'compact' ? 18 : 20,
                          color: selected ? accent : Colors.black54),
                      if (style != 'compact') ...[
                        const SizedBox(height: 3),
                        Text(EmployeeMobileShell._labelForTab(tab),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: selected ? accent : Colors.black54)),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _navIcon(String tab, int unreadCount) {
    if (tab != 'notifications' || unreadCount <= 0)
      return Icon(EmployeeMobileShell._iconForTab(tab));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(EmployeeMobileShell._iconForTab(tab)),
        Positioned(
          right: -7,
          top: -7,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                color: Colors.red, borderRadius: BorderRadius.circular(999)),
            child: Text(unreadCount > 9 ? '9+' : '$unreadCount',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
  }
}

class _ServerDrivenRail extends StatelessWidget {
  const _ServerDrivenRail(
      {required this.tabs,
      required this.activeTab,
      required this.unreadCount,
      required this.accent,
      required this.onChanged});

  final List<String> tabs;
  final String activeTab;
  final int unreadCount;
  final Color accent;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: _safeIndex(tabs, activeTab),
      extended: true,
      destinations: tabs
          .map((tab) => NavigationRailDestination(
              icon: Icon(EmployeeMobileShell._iconForTab(tab)),
              label: Text(EmployeeMobileShell._labelForTab(tab))))
          .toList(),
      onDestinationSelected: (index) => onChanged(tabs[index]),
    );
  }
}

class _EmployeeNotificationBell extends StatelessWidget {
  const _EmployeeNotificationBell({required this.unreadCount});
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.notifications_none_rounded),
        if (unreadCount > 0)
          Positioned(
            right: -6,
            top: -7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(999)),
              child: Text(unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
            ),
          ),
      ],
    );
  }
}

Color _color(String raw, Color fallback) {
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

int _safeIndex(List<String> tabs, String activeTab) {
  final index = tabs.indexOf(activeTab);
  if (index < 0) return 0;
  if (index >= tabs.length) return tabs.isEmpty ? 0 : tabs.length - 1;
  return index;
}

Future<void> _employeeWebLogout(WidgetRef ref) async {
  ref.read(workspaceProvider.notifier).setMyOnlineStatus(false);
  if (AppConfig.useFirebase) {
    await ref.read(authServiceProvider).signOut();
  } else {
    ref.read(demoLoggedInProvider.notifier).state = false;
  }
}

class _EmployeeWebLogoutPill extends StatelessWidget {
  const _EmployeeWebLogoutPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x220F172A),
                  blurRadius: 22,
                  offset: Offset(0, 12))
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Logout',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeTopNavLogoutButton extends StatelessWidget {
  const _EmployeeTopNavLogoutButton(
      {required this.compact, required this.onTap});

  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: compact ? 34 : 38,
        height: compact ? 34 : 38,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
                color: Color(0x180F172A), blurRadius: 14, offset: Offset(0, 8))
          ],
        ),
        child: const Icon(Icons.logout_rounded, color: Colors.white, size: 18),
      ),
    );
  }
}
