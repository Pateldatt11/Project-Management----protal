import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:project_management_dashboard/app/workspace_state.dart';
import 'package:project_management_dashboard/core/config/app_config.dart';
import 'package:project_management_dashboard/core/constants/app_enums.dart';
import 'package:project_management_dashboard/core/navigation/navigation_preferences.dart';
import 'package:project_management_dashboard/core/timeline/timeline_preferences.dart';
import 'package:project_management_dashboard/core/permissions/permission_service.dart';
import 'package:project_management_dashboard/core/responsive/responsive.dart';
import 'package:project_management_dashboard/core/widgets/brew_haven_chat_sheet.dart';
import 'package:project_management_dashboard/core/widgets/subscription_gate.dart';
import 'package:project_management_dashboard/data/models/member.dart';
import 'package:project_management_dashboard/features/appraisals/presentation/appraisal_screen.dart';
import 'package:project_management_dashboard/features/auth/presentation/auth_gate.dart';
import 'package:project_management_dashboard/features/dashboard/presentation/dashboard_screen.dart';
import 'package:project_management_dashboard/features/employees/presentation/employees_screen.dart';
import 'package:project_management_dashboard/features/kanban/presentation/kanban_screen.dart';
import 'package:project_management_dashboard/features/meetings/presentation/meetings_screen.dart';
import 'package:project_management_dashboard/features/notifications/presentation/notifications_screen.dart';
import 'package:project_management_dashboard/features/profile/presentation/profile_screen.dart';
import 'package:project_management_dashboard/features/projects/presentation/projects_screen.dart';
import 'package:project_management_dashboard/features/reports/presentation/reports_screen.dart';
import 'package:project_management_dashboard/features/settings/presentation/settings_screen.dart';
import 'package:project_management_dashboard/features/tasks/presentation/tasks_screen.dart';
import 'package:project_management_dashboard/features/tickets/presentation/tickets_screen.dart';
import 'package:project_management_dashboard/features/teams/presentation/teams_screen.dart';
import 'package:project_management_dashboard/features/timeline/presentation/realtime_timeline_screen.dart';
import 'package:project_management_dashboard/features/billing/presentation/billing_screen.dart';
import 'package:project_management_dashboard/features/billing/presentation/plan_selection_screen.dart';
import 'package:project_management_dashboard/features/campaigns/presentation/campaigns_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const double _expandedSidebarWidth = 280;
  static const double _autoCollapseBreakpoint = 1280;

  bool _manuallyCollapsed = false;
  bool _timelineUserExpanded = false;
  bool _hoverExpanded = false;
  MainSection? _previousSectionForMotion;

  @override
  Widget build(BuildContext context) {
    final section = ref.watch(currentSectionProvider);
    final state = ref.watch(workspaceProvider);
    final company = state.company;
    final currentMember = state.currentMember;
    final navigation = kIsWeb
        ? ref.watch(navigationPreferencesProvider)
        : NavigationPreferences.defaults;

    if (kIsWeb) {
      ref.read(navigationPreferencesProvider.notifier).bindWebUser(
            companyId: company.companyId,
            userId: currentMember.uid,
          );
    }

    ref.listen<MainSection>(currentSectionProvider, (previous, next) {
      if (!mounted || previous == next) return;
      _previousSectionForMotion = previous;
      if (next == MainSection.timeline) {
        setState(() {
          _timelineUserExpanded = false;
          _hoverExpanded = false;
        });
      } else if (previous == MainSection.timeline &&
          !navigation.restoreAfterTimeline) {
        setState(() {
          _manuallyCollapsed = true;
          _hoverExpanded = false;
        });
      }
    });

    if (!state.isPortalPostActive(currentMember.role) ||
        !PermissionService.canAccessSection(currentMember, section)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(currentSectionProvider.notifier).state =
            MainSection.dashboard;
      });
    }

    final unreadNotifications = state.myUnreadNotificationCount;
    final isDesktop = Responsive.isDesktop(context);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isTimeline = section == MainSection.timeline;
    final narrowDesktop = viewportWidth < _autoCollapseBreakpoint;
    final placement = _resolveDesktopPlacement(navigation.placement);
    final sidePlacement = placement == NavigationPlacement.left ||
        placement == NavigationPlacement.right;

    final displayModeForcesCollapse =
        navigation.displayMode != NavigationDisplayMode.expanded;
    final timelineAutoCollapse = sidePlacement &&
        isTimeline &&
        navigation.autoCollapseOnTimeline &&
        !_timelineUserExpanded;
    final baseCollapsed = sidePlacement &&
        (narrowDesktop ||
            displayModeForcesCollapse ||
            timelineAutoCollapse ||
            _manuallyCollapsed);
    final hoverOverride = sidePlacement &&
        navigation.expandOnHover &&
        _hoverExpanded &&
        !narrowDesktop;
    final sidebarCollapsed = baseCollapsed && !hoverOverride;
    final collapsedWidth = switch (navigation.displayMode) {
      NavigationDisplayMode.iconsOnly => 76.0,
      NavigationDisplayMode.compact => 104.0,
      NavigationDisplayMode.expanded => 84.0,
    };
    final motion = _NavigationMotion.from(navigation.animationStyle);

    final timelineRouteTransition = isTimeline ||
        _previousSectionForMotion == MainSection.timeline;
    final page = RepaintBoundary(
      child: AnimatedSwitcher(
        duration: timelineRouteTransition
            ? Duration.zero
            : motion.pageDuration,
        switchInCurve: motion.curve,
        switchOutCurve: Curves.easeInCubic,
        child: KeyedSubtree(
          key: ValueKey(section),
          child: _screenFor(section),
        ),
      ),
    );

    final sections = MainSection.values
        .where(
          (item) =>
              state.isPortalPostActive(currentMember.role) &&
              PermissionService.canAccessSection(currentMember, item),
        )
        .toList(growable: false);

    final desktopBody = _DesktopNavigationLayout(
      placement: placement,
      motion: motion,
      timelineOverlayMode: isTimeline && sidePlacement,
      collapsedSideWidth: collapsedWidth,
      sideNavigation: _SideBar(
        selected: section,
        member: currentMember,
        collapsed: sidebarCollapsed,
        displayMode: navigation.displayMode,
        expandedWidth: _expandedSidebarWidth,
        collapsedWidth: collapsedWidth,
        automaticallyCollapsed: narrowDesktop || timelineAutoCollapse,
        placeOnRight: placement == NavigationPlacement.right,
        timelineOverlayPerformanceMode: isTimeline && sidePlacement,
        motion: motion,
        onHoverChanged: (hovering) {
          if (!navigation.expandOnHover || _hoverExpanded == hovering) return;
          setState(() => _hoverExpanded = hovering);
        },
        onToggle: () {
          setState(() {
            _hoverExpanded = false;
            if (isTimeline && navigation.autoCollapseOnTimeline) {
              if (!narrowDesktop) {
                _timelineUserExpanded = !_timelineUserExpanded;
              }
            } else {
              _manuallyCollapsed = !_manuallyCollapsed;
            }
          });
        },
      ),
      horizontalNavigation: _HorizontalNavigationBar(
        selected: section,
        sections: sections,
        placement: placement,
        displayMode: navigation.displayMode,
        motion: motion,
        onSelected: (value) {
          ref.read(currentSectionProvider.notifier).state = value;
        },
      ),
      content: page,
    );

    if (_previousSectionForMotion != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _previousSectionForMotion = null;
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(company.name),
        actions: [
          if (currentMember.role.isAdminLike) ...[
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BillingScreen()),
                );
              },
              icon: const Icon(Icons.receipt_long_rounded, size: 16, color: Colors.purple),
              label: const Text('Billing', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PlanSelectionScreen()),
                );
              },
              icon: const Icon(Icons.upgrade_rounded, size: 16, color: Colors.amber),
              label: const Text('Upgrade Plan', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
          ],
          if (isDesktop)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: CircleAvatar(
                  backgroundColor: currentMember.role.color,
                  child: Text(
                    currentMember.role.shortLabel.characters.first,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
                label: Text(currentMember.role.label),
              ),
            ),
          if (isDesktop)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: Icon(
                  currentMember.isOnline
                      ? Icons.circle
                      : Icons.radio_button_unchecked,
                  size: 14,
                  color:
                      currentMember.isOnline ? Colors.green : Colors.grey,
                ),
                label: Text(
                  currentMember.isOnline ? 'Online' : 'Offline',
                ),
              ),
            ),
          IconButton(
            tooltip: 'Private notifications',
            onPressed: () {
              ref.read(currentSectionProvider.notifier).state =
                  MainSection.notifications;
            },
            icon: _NotificationBell(
              unreadCount: unreadNotifications,
            ),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              ref
                  .read(workspaceProvider.notifier)
                  .setMyOnlineStatus(false);
              if (AppConfig.useFirebase) {
                await ref.read(authServiceProvider).signOut();
              } else {
                ref.read(demoLoggedInProvider.notifier).state = false;
              }
            },
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      drawer: isDesktop
          ? null
          : Drawer(
              child: SafeArea(
                child: _NavList(
                  selected: section,
                  member: currentMember,
                  collapsed: false,
                  displayMode: NavigationDisplayMode.expanded,
                  showToggle: false,
                  onToggle: null,
                  motion: motion,
                ),
              ),
            ),
      body: SubscriptionGate(
        child: isDesktop ? desktopBody : page,
      ),
      floatingActionButton: const BrewHavenChatLauncher(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  NavigationPlacement _resolveDesktopPlacement(
    NavigationPlacement requested,
  ) {
    if (requested != NavigationPlacement.automatic) return requested;
    return NavigationPlacement.left;
  }

  Widget _screenFor(MainSection section) {
    return switch (section) {
      MainSection.dashboard => const DashboardScreen(),
      MainSection.projects => const ProjectsScreen(),
      MainSection.tasks => const TasksScreen(),
      MainSection.kanban => const KanbanScreen(),
      MainSection.timeline => const RealtimeTimelineScreen(),
      MainSection.appraisals => const AppraisalScreen(),
      MainSection.meetings => const MeetingsScreen(),
      MainSection.teams => const TeamsScreen(),
      MainSection.employees => const EmployeesScreen(),
      MainSection.tickets => const TicketsScreen(),
      MainSection.reports => const ReportsScreen(),
      MainSection.notifications => const NotificationsScreen(),
      MainSection.campaigns => const CampaignsScreen(),
      MainSection.settings => const SettingsScreen(),
      MainSection.profile => const ProfileScreen(),
    };
  }
}

class _NavigationMotion {
  const _NavigationMotion({
    required this.resizeDuration,
    required this.placementDuration,
    required this.contentDuration,
    required this.pageDuration,
    required this.curve,
  });

  final Duration resizeDuration;
  final Duration placementDuration;
  final Duration contentDuration;
  final Duration pageDuration;
  final Curve curve;

  factory _NavigationMotion.from(NavigationAnimationStyle style) {
    return switch (style) {
      NavigationAnimationStyle.disabled => const _NavigationMotion(
          resizeDuration: Duration.zero,
          placementDuration: Duration.zero,
          contentDuration: Duration.zero,
          pageDuration: Duration.zero,
          curve: Curves.linear,
        ),
      NavigationAnimationStyle.fast => const _NavigationMotion(
          resizeDuration: Duration(milliseconds: 150),
          placementDuration: Duration(milliseconds: 190),
          contentDuration: Duration(milliseconds: 110),
          pageDuration: Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        ),
      NavigationAnimationStyle.system => const _NavigationMotion(
          resizeDuration: Duration(milliseconds: 220),
          placementDuration: Duration(milliseconds: 260),
          contentDuration: Duration(milliseconds: 160),
          pageDuration: Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      NavigationAnimationStyle.smooth => const _NavigationMotion(
          resizeDuration: Duration(milliseconds: 280),
          placementDuration: Duration(milliseconds: 320),
          contentDuration: Duration(milliseconds: 170),
          pageDuration: Duration(milliseconds: 200),
          curve: Cubic(0.16, 1.0, 0.30, 1.0),
        ),
    };
  }
}

class _DesktopNavigationLayout extends StatelessWidget {
  const _DesktopNavigationLayout({
    required this.placement,
    required this.motion,
    required this.timelineOverlayMode,
    required this.collapsedSideWidth,
    required this.sideNavigation,
    required this.horizontalNavigation,
    required this.content,
  });

  final NavigationPlacement placement;
  final _NavigationMotion motion;
  final bool timelineOverlayMode;
  final double collapsedSideWidth;
  final Widget sideNavigation;
  final Widget horizontalNavigation;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    if (timelineOverlayMode &&
        (placement == NavigationPlacement.left ||
            placement == NavigationPlacement.right ||
            placement == NavigationPlacement.automatic)) {
      return _TimelineNavigationOverlayLayout(
        placeOnRight: placement == NavigationPlacement.right,
        collapsedSideWidth: collapsedSideWidth,
        sideNavigation: sideNavigation,
        content: content,
      );
    }

    final layout = switch (placement) {
      NavigationPlacement.right => Row(
          key: const ValueKey('navigation-right'),
          children: [
            Expanded(child: content),
            sideNavigation,
          ],
        ),
      NavigationPlacement.top => Column(
          key: const ValueKey('navigation-top'),
          children: [
            horizontalNavigation,
            Expanded(child: content),
          ],
        ),
      NavigationPlacement.bottom => Column(
          key: const ValueKey('navigation-bottom'),
          children: [
            Expanded(child: content),
            horizontalNavigation,
          ],
        ),
      NavigationPlacement.automatic => Row(
          key: const ValueKey('navigation-left'),
          children: [
            sideNavigation,
            Expanded(child: content),
          ],
        ),
      NavigationPlacement.left => Row(
          key: const ValueKey('navigation-left'),
          children: [
            sideNavigation,
            Expanded(child: content),
          ],
        ),
    };

    return AnimatedSwitcher(
      duration: motion.placementDuration,
      switchInCurve: motion.curve,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final offset = switch (placement) {
          NavigationPlacement.right => const Offset(.025, 0),
          NavigationPlacement.top => const Offset(0, -.025),
          NavigationPlacement.bottom => const Offset(0, .025),
          NavigationPlacement.automatic => const Offset(-.025, 0),
          NavigationPlacement.left => const Offset(-.025, 0),
        };
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: offset,
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: motion.curve),
            ),
            child: child,
          ),
        );
      },
      child: layout,
    );
  }
}

class _TimelineNavigationOverlayLayout extends StatelessWidget {
  const _TimelineNavigationOverlayLayout({
    required this.placeOnRight,
    required this.collapsedSideWidth,
    required this.sideNavigation,
    required this.content,
  });

  final bool placeOnRight;
  final double collapsedSideWidth;
  final Widget sideNavigation;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          left: placeOnRight ? 0 : collapsedSideWidth,
          right: placeOnRight ? collapsedSideWidth : 0,
          child: RepaintBoundary(child: content),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: placeOnRight ? null : 0,
          right: placeOnRight ? 0 : null,
          child: RepaintBoundary(child: sideNavigation),
        ),
      ],
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.unreadCount});

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
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SideBar extends StatefulWidget {
  const _SideBar({
    required this.selected,
    required this.member,
    required this.collapsed,
    required this.displayMode,
    required this.expandedWidth,
    required this.collapsedWidth,
    required this.automaticallyCollapsed,
    required this.placeOnRight,
    required this.timelineOverlayPerformanceMode,
    required this.motion,
    required this.onHoverChanged,
    required this.onToggle,
  });

  final MainSection selected;
  final Member member;
  final bool collapsed;
  final NavigationDisplayMode displayMode;
  final double expandedWidth;
  final double collapsedWidth;
  final bool automaticallyCollapsed;
  final bool placeOnRight;
  final bool timelineOverlayPerformanceMode;
  final _NavigationMotion motion;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onToggle;

  @override
  State<_SideBar> createState() => _SideBarState();
}

class _SideBarState extends State<_SideBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late CurvedAnimation _curved;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.motion.resizeDuration,
      value: widget.collapsed ? 1.0 : 0.0,
    );
    _curved = CurvedAnimation(
      parent: _controller,
      curve: widget.motion.curve,
    );
  }

  @override
  void didUpdateWidget(covariant _SideBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion.resizeDuration != widget.motion.resizeDuration) {
      _controller.duration = widget.motion.resizeDuration;
    }
    if (oldWidget.motion.curve != widget.motion.curve) {
      _curved.dispose();
      _curved = CurvedAnimation(
        parent: _controller,
        curve: widget.motion.curve,
      );
    }
    if (oldWidget.collapsed != widget.collapsed) {
      if (widget.motion.resizeDuration == Duration.zero) {
        _controller.value = widget.collapsed ? 1.0 : 0.0;
      } else {
        _controller.animateTo(
          widget.collapsed ? 1.0 : 0.0,
          duration: widget.motion.resizeDuration,
          curve: Curves.linear,
        );
      }
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.timelineOverlayPerformanceMode) {
      return _buildTimelineCompositedRail(context);
    }
    return _buildStandardAnimatedRail(context);
  }

  Widget _buildTimelineCompositedRail(BuildContext context) {
    const sideInset = 14.0;
    final hiddenDistance = widget.expandedWidth - widget.collapsedWidth;

    final expandedNavigation = Padding(
      padding: const EdgeInsets.all(14),
      child: _NavList(
        selected: widget.selected,
        member: widget.member,
        collapsed: false,
        displayMode: widget.displayMode,
        showToggle: true,
        automaticallyCollapsed: widget.automaticallyCollapsed,
        onToggle: widget.onToggle,
        motion: widget.motion,
      ),
    );

    final collapsedNavigation = Align(
      alignment: widget.placeOnRight ? Alignment.centerLeft : Alignment.centerRight,
      child: SizedBox(
        width: widget.collapsedWidth - sideInset,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: _NavList(
            selected: widget.selected,
            member: widget.member,
            collapsed: true,
            displayMode: widget.displayMode,
            showToggle: true,
            automaticallyCollapsed: widget.automaticallyCollapsed,
            onToggle: widget.onToggle,
            motion: widget.motion,
          ),
        ),
      ),
    );

    return MouseRegion(
      onEnter: (_) => widget.onHoverChanged(true),
      onExit: (_) => widget.onHoverChanged(false),
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _curved,
          builder: (context, _) {
            final collapseT = _curved.value.clamp(0.0, 1.0);
            final translateX = (widget.placeOnRight ? 1.0 : -1.0) * hiddenDistance * collapseT;
            final expandedOpacity = (1.0 - (collapseT / 0.72)).clamp(0.0, 1.0);
            final collapsedOpacity = ((collapseT - 0.18) / 0.82).clamp(0.0, 1.0);

            return Transform.translate(
              offset: Offset(translateX, 0),
              transformHitTests: true,
              child: SizedBox(
                width: widget.expandedWidth,
                child: Card(
                  clipBehavior: Clip.hardEdge,
                  margin: widget.placeOnRight
                      ? const EdgeInsets.fromLTRB(0, 12, sideInset, 14)
                      : const EdgeInsets.fromLTRB(sideInset, 12, 0, 14),
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        IgnorePointer(
                          ignoring: collapseT > 0.52,
                          child: Opacity(opacity: expandedOpacity, child: expandedNavigation),
                        ),
                        IgnorePointer(
                          ignoring: collapseT < 0.48,
                          child: Opacity(opacity: collapsedOpacity, child: collapsedNavigation),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStandardAnimatedRail(BuildContext context) {
    const sideInset = 14.0;
    final expandedContentWidth = widget.expandedWidth - sideInset;
    final collapsedContentWidth = widget.collapsedWidth - sideInset;

    final expandedNavigation = Padding(
      padding: const EdgeInsets.all(14),
      child: _NavList(
        selected: widget.selected,
        member: widget.member,
        collapsed: false,
        displayMode: widget.displayMode,
        showToggle: true,
        automaticallyCollapsed: widget.automaticallyCollapsed,
        onToggle: widget.onToggle,
        motion: widget.motion,
      ),
    );

    final collapsedNavigation = Padding(
      padding: const EdgeInsets.all(8),
      child: _NavList(
        selected: widget.selected,
        member: widget.member,
        collapsed: true,
        displayMode: widget.displayMode,
        showToggle: true,
        automaticallyCollapsed: widget.automaticallyCollapsed,
        onToggle: widget.onToggle,
        motion: widget.motion,
      ),
    );

    return MouseRegion(
      onEnter: (_) => widget.onHoverChanged(true),
      onExit: (_) => widget.onHoverChanged(false),
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _curved,
          builder: (context, _) {
            final collapseT = _curved.value.clamp(0.0, 1.0);
            final railWidth = Tween<double>(
              begin: widget.expandedWidth,
              end: widget.collapsedWidth,
            ).transform(collapseT);

            final expandedOpacity = (1.0 - (collapseT / 0.64)).clamp(0.0, 1.0);
            final collapsedOpacity = ((collapseT - 0.24) / 0.76).clamp(0.0, 1.0);
            final expandedShift = (widget.placeOnRight ? 1.0 : -1.0) * 10.0 * collapseT;
            final collapsedShift = (widget.placeOnRight ? -1.0 : 1.0) * 8.0 * (1.0 - collapseT);

            return SizedBox(
              width: railWidth,
              child: Card(
                clipBehavior: Clip.hardEdge,
                margin: widget.placeOnRight
                    ? const EdgeInsets.fromLTRB(0, 12, sideInset, 14)
                    : const EdgeInsets.fromLTRB(sideInset, 12, 0, 14),
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: widget.placeOnRight ? null : 0,
                        right: widget.placeOnRight ? 0 : null,
                        width: expandedContentWidth,
                        child: IgnorePointer(
                          ignoring: collapseT > 0.50,
                          child: Opacity(
                            opacity: expandedOpacity,
                            child: Transform.translate(
                              offset: Offset(expandedShift, 0),
                              child: expandedNavigation,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: widget.placeOnRight ? null : 0,
                        right: widget.placeOnRight ? 0 : null,
                        width: collapsedContentWidth,
                        child: IgnorePointer(
                          ignoring: collapseT < 0.50,
                          child: Opacity(
                            opacity: collapsedOpacity,
                            child: Transform.translate(
                              offset: Offset(collapsedShift, 0),
                              child: collapsedNavigation,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NavList extends ConsumerWidget {
  const _NavList({
    required this.selected,
    required this.member,
    required this.collapsed,
    required this.displayMode,
    required this.showToggle,
    required this.onToggle,
    required this.motion,
    this.automaticallyCollapsed = false,
  });

  final MainSection selected;
  final Member member;
  final bool collapsed;
  final NavigationDisplayMode displayMode;
  final bool showToggle;
  final bool automaticallyCollapsed;
  final VoidCallback? onToggle;
  final _NavigationMotion motion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider);
    final companyName = workspace.company.name.isNotEmpty && workspace.company.name != 'Company Workspace'
        ? workspace.company.name
        : (workspace.company.companyId != 'platform' ? workspace.company.name : 'Company Workspace');

    final sections = MainSection.values
        .where(
          (item) =>
              workspace.isPortalPostActive(member.role) &&
              PermissionService.canAccessSection(member, item),
        )
        .toList(growable: false);
    final compactLabels = collapsed && displayMode == NavigationDisplayMode.compact;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: motion.contentDuration,
          switchInCurve: motion.curve,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axis: Axis.horizontal,
                axisAlignment: -1,
                child: child,
              ),
            );
          },
          child: collapsed
              ? Tooltip(
                  key: const ValueKey('collapsed-brand'),
                  message: '$companyName\n${member.role.label}',
                  child: const SizedBox(
                    height: 52,
                    child: Center(
                      child: CircleAvatar(
                        child: Icon(Icons.workspaces_rounded),
                      ),
                    ),
                  ),
                )
              : ListTile(
                  key: const ValueKey('expanded-brand'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: const CircleAvatar(
                    child: Icon(Icons.workspaces_rounded),
                  ),
                  title: Text(
                    companyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    member.role.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {},
                ),
        ),
        if (showToggle) ...[
          const SizedBox(height: 6),
          AnimatedAlign(
            duration: motion.resizeDuration,
            curve: motion.curve,
            alignment: collapsed ? Alignment.center : Alignment.centerRight,
            child: Tooltip(
              message: automaticallyCollapsed && collapsed
                  ? 'Expand navigation temporarily'
                  : collapsed
                      ? 'Expand navigation'
                      : 'Collapse navigation',
              child: IconButton(
                onPressed: onToggle,
                icon: AnimatedRotation(
                  duration: motion.contentDuration,
                  turns: collapsed ? 0 : .5,
                  child: const Icon(Icons.chevron_right_rounded),
                ),
              ),
            ),
          ),
        ],
        SizedBox(height: collapsed ? 8 : 12),
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: AnimatedSwitcher(
              duration: motion.contentDuration,
              switchInCurve: motion.curve,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axis: Axis.horizontal,
                    axisAlignment: -1,
                    child: child,
                  ),
                );
              },
              child: collapsed
                  ? _CollapsedNavItem(
                      key: ValueKey('collapsed-${section.name}'),
                      section: section,
                      selected: selected == section,
                      showLabel: compactLabels,
                      onTap: () => _openSection(context, ref, section),
                    )
                  : ListTile(
                      key: ValueKey('expanded-${section.name}'),
                      selected: selected == section,
                      selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(.10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: Icon(section.icon),
                      title: Text(
                        section.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _openSection(context, ref, section),
                    ),
            ),
          ),
      ],
    );
  }

  void _openSection(
    BuildContext context,
    WidgetRef ref,
    MainSection section,
  ) {
    ref.read(currentSectionProvider.notifier).state = section;
    if (Scaffold.maybeOf(context)?.hasDrawer ?? false) {
      Navigator.pop(context);
    }
  }
}

class _CollapsedNavItem extends StatelessWidget {
  const _CollapsedNavItem({
    super.key,
    required this.section,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final MainSection section;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: section.label,
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: selected ? colorScheme.primary.withOpacity(.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: showLabel ? 58 : 48,
            child: Center(
              child: showLabel
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          section.icon,
                          size: 20,
                          color: selected ? colorScheme.primary : null,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          section.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: selected ? colorScheme.primary : null,
                          ),
                        ),
                      ],
                    )
                  : Icon(
                      section.icon,
                      color: selected ? colorScheme.primary : null,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizontalNavigationBar extends StatelessWidget {
  const _HorizontalNavigationBar({
    required this.selected,
    required this.sections,
    required this.placement,
    required this.displayMode,
    required this.motion,
    required this.onSelected,
  });

  final MainSection selected;
  final List<MainSection> sections;
  final NavigationPlacement placement;
  final NavigationDisplayMode displayMode;
  final _NavigationMotion motion;
  final ValueChanged<MainSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final isTop = placement == NavigationPlacement.top;
    final showLabels = displayMode != NavigationDisplayMode.iconsOnly;
    final compact = displayMode == NavigationDisplayMode.compact;
    final height = compact ? 66.0 : 74.0;

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: motion.resizeDuration,
        curve: motion.curve,
        height: height,
        margin: EdgeInsets.fromLTRB(
          14,
          isTop ? 12 : 0,
          14,
          isTop ? 0 : 14,
        ),
        child: Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: CircleAvatar(
                  radius: 18,
                  child: Icon(Icons.workspaces_rounded, size: 19),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      for (final section in sections)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 8,
                          ),
                          child: _HorizontalNavItem(
                            section: section,
                            selected: selected == section,
                            showLabel: showLabels,
                            compact: compact,
                            motion: motion,
                            onTap: () => onSelected(section),
                          ),
                        ),
                    ],
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

class _HorizontalNavItem extends StatelessWidget {
  const _HorizontalNavItem({
    required this.section,
    required this.selected,
    required this.showLabel,
    required this.compact,
    required this.motion,
    required this.onTap,
  });

  final MainSection section;
  final bool selected;
  final bool showLabel;
  final bool compact;
  final _NavigationMotion motion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Tooltip(
      message: section.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: motion.contentDuration,
            curve: motion.curve,
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? (compact ? 10 : 13) : 12,
              vertical: compact ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: selected ? scheme.primary.withOpacity(.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(section.icon, size: 20, color: foreground),
                AnimatedSize(
                  duration: motion.contentDuration,
                  curve: motion.curve,
                  child: showLabel
                      ? Row(
                          children: [
                            const SizedBox(width: 7),
                            Text(
                              section.label,
                              style: TextStyle(
                                color: foreground,
                                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}