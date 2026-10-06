import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../admin_app/services/oracle_notification_backend_service.dart';
import '../../../app/workspace_state.dart';
import '../../../core/config/notification_backend_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/platform/android_alert_notification_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../data/models/app_notification.dart';

enum _NotificationViewMode { stack, expanded }

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _deckController;

  _NotificationViewMode _viewMode = _NotificationViewMode.stack;
  bool _deckExpanded = false;
  bool _showExpandedRows = false;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _deckController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
  }

  @override
  void dispose() {
    _deckController.dispose();
    super.dispose();
  }

  Future<void> _setMode(_NotificationViewMode mode) async {
    if (_viewMode == mode) return;
    HapticFeedback.selectionClick();

    if (mode == _NotificationViewMode.expanded) {
      setState(() {
        _viewMode = _NotificationViewMode.expanded;
        _deckExpanded = true;
        _showExpandedRows = false;
      });
      await _deckController.forward();
      if (!mounted) return;
      setState(() => _showExpandedRows = true);
    } else {
      setState(() {
        _viewMode = _NotificationViewMode.stack;
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
        _viewMode = _NotificationViewMode.stack;
        _deckExpanded = false;
        _showExpandedRows = false;
      });
      await _deckController.reverse();
      return;
    }

    setState(() {
      _viewMode = _NotificationViewMode.expanded;
      _deckExpanded = true;
      _showExpandedRows = false;
    });
    await _deckController.forward();
    if (!mounted) return;
    setState(() => _showExpandedRows = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final style = _StackNotificationStyle.fromState(state);
    final allNotifications = state.myNotifications.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final notifications = _filterNotifications(allNotifications, _filter);
    final unread = allNotifications.where((notification) => !notification.isRead).length;
    final filteredUnread = notifications.where((notification) => !notification.isRead).length;
    final deckLimit = style.deckCardLimit.clamp(2, 6).toInt();
    final deckItems = notifications.take(deckLimit).toList(growable: false);
    final expandedRows = _showExpandedRows ? notifications.skip(deckItems.length).toList(growable: false) : const <AppNotification>[];

    return Container(
      color: style.background,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(style.screenPadding, style.screenPadding, style.screenPadding, style.screenPadding + 92),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NotificationStackHeader(
              style: style,
              totalCount: allNotifications.length,
              visibleCount: notifications.length,
              unreadCount: unread,
              latestTime: allNotifications.isEmpty ? null : allNotifications.first.createdAt,
              onMarkAll: unread > 0 ? _markAllUnreadAsRead : null,
            ),
            if (state.currentMember.role.isDeliveryManager) ...[
              const SizedBox(height: 12),
              _AdminNotificationEscalationPanel(
                companyId: state.company.companyId,
              ),
            ],
            const SizedBox(height: 12),
            _NotificationStackFilterBar(
              style: style,
              selected: _filter,
              total: allNotifications.length,
              unread: unread,
              taskCount: allNotifications.where(_isTaskNotification).length,
              meetingCount: allNotifications.where((item) => item.isMeetingInvite).length,
              onChanged: (value) {
                HapticFeedback.selectionClick();
                setState(() {
                  _filter = value;
                  _viewMode = _NotificationViewMode.stack;
                  _deckExpanded = false;
                  _showExpandedRows = false;
                  _deckController.value = 0;
                });
              },
            ),
            const SizedBox(height: 12),
            _NotificationModeSelector(
              style: style,
              selected: _viewMode,
              visibleCount: notifications.length,
              unreadCount: filteredUnread,
              onSelected: _setMode,
            ),
            const SizedBox(height: 14),
            if (notifications.isEmpty)
              EmptyState(
                icon: Icons.notifications_off_rounded,
                title: _filter == 'All' ? 'No notifications' : 'No $_filter notifications',
                message: _filter == 'All' ? 'New task alerts, meeting invites, and approval requests appear here.' : 'Change filter to see more notifications.',
              )
            else
              _StackedNotificationDeck(
                entries: deckItems,
                totalCount: notifications.length,
                controller: _deckController,
                style: style,
                onToggle: _toggleDeck,
                onTapNotification: _handleNotificationTap,
                onAction: _handleNotificationAction,
              ),
            if (_showExpandedRows && expandedRows.isNotEmpty) ...[
              const SizedBox(height: 14),
              ..._groupedExpandedRows(expandedRows).map((row) {
                if (row.label != null) {
                  return _NotificationGroupHeader(style: style, label: row.label!);
                }
                final notification = row.notification!;
                return _ExpandedNotificationCard(
                  notification: notification,
                  style: style,
                  onTap: () => _handleNotificationTap(notification),
                  onAction: () => _handleNotificationAction(notification),
                );
              }),
            ],
            if (_showExpandedRows && notifications.length <= deckItems.length)
              _StackFooterHint(style: style, message: 'All visible notifications are inside the stack.'),
          ],
        ),
      ),
    );
  }

  List<AppNotification> _filterNotifications(List<AppNotification> source, String filter) {
    switch (filter) {
      case 'Unread':
        return source.where((item) => !item.isRead).toList(growable: false);
      case 'Tasks':
        return source.where(_isTaskNotification).toList(growable: false);
      case 'Meetings':
        return source.where((item) => item.isMeetingInvite).toList(growable: false);
      case 'Mentions':
        return source.where(_isMentionNotification).toList(growable: false);
      default:
        return source;
    }
  }

  static bool _isTaskNotification(AppNotification item) {
    final normalized = item.type.trim().toLowerCase();
    return item.taskId != null ||
        normalized.contains('task') ||
        normalized.contains('assign') ||
        normalized.contains('deadline') ||
        normalized.contains('status');
  }

  static bool _isMentionNotification(AppNotification item) {
    final text = '${item.type} ${item.title} ${item.message}'.toLowerCase();
    return text.contains('mention') || text.contains('@');
  }

  List<_NotificationGroupRow> _groupedExpandedRows(List<AppNotification> source) {
    final rows = <_NotificationGroupRow>[];
    String? lastGroup;
    for (final notification in source) {
      final group = _groupLabel(notification.createdAt);
      if (group != lastGroup) {
        rows.add(_NotificationGroupRow.header(group));
        lastGroup = group;
      }
      rows.add(_NotificationGroupRow.card(notification));
    }
    return rows;
  }

  String _groupLabel(DateTime createdAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDay = DateTime(createdAt.year, createdAt.month, createdAt.day);
    if (itemDay == today) return 'New today';
    if (itemDay == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return 'Earlier';
  }

  void _markAllUnreadAsRead() {
    HapticFeedback.mediumImpact();
    AndroidAlertNotificationService.cancelLoopingAlert();
    ref.read(workspaceProvider.notifier).markAllMyNotificationsRead();
  }

  void _handleNotificationTap(AppNotification notification) {
    HapticFeedback.selectionClick();
    if (!notification.isRead) {
      AndroidAlertNotificationService.acceptLoopingAlert(notification.notificationId);
      ref.read(workspaceProvider.notifier).acceptNotificationAndStartWorkCounter(notification.notificationId);
    }
  }

  Future<void> _handleNotificationAction(AppNotification notification) async {
    AndroidAlertNotificationService.acceptLoopingAlert(notification.notificationId);
    ref.read(workspaceProvider.notifier).acceptNotificationAndStartWorkCounter(notification.notificationId);
    final uri = _safeUri(notification.actionUrl);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open link')),
      );
    }
  }
}

class _StackNotificationStyle {
  const _StackNotificationStyle({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.cardRadius,
    required this.screenPadding,
    required this.deckCardLimit,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final double cardRadius;
  final double screenPadding;
  final int deckCardLimit;

  static _StackNotificationStyle fromState(WorkspaceState state) {
    final config = state.mobileUiConfig;
    final override = _map(config.screenOverrides['notifications']);
    final overrideTheme = _map(override['theme']);
    final stackConfig = _map(override['notificationStackConfig'] ?? override['stackNotificationConfig']);
    final stackColors = _map(stackConfig['colors']);
    final design = _map(config.designSystem);
    final designColors = _map(design['colors']);

    Object? value(String key, {Object? fallback}) =>
        stackColors[key] ?? stackConfig[key] ?? overrideTheme[key] ?? designColors[key] ?? design[key] ?? fallback;

    final radius = _number(value('cardRadius', fallback: 30), 30).clamp(18, 38).toDouble();
    final padding = _number(value('screenPadding', fallback: 18), 18).clamp(12, 28).toDouble();

    return _StackNotificationStyle(
      background: _color(value('notificationBackground', fallback: value('background')), const Color(0xFFF4F5F1)),
      surface: _color(value('notificationSurface', fallback: value('surface')), Colors.white),
      surfaceAlt: _color(value('surfaceAlt'), const Color(0xFFEEF2EA)),
      textPrimary: _color(value('textPrimary'), const Color(0xFF0F140F)),
      textSecondary: _color(value('textSecondary'), const Color(0xFF5F675E)),
      border: _color(value('border'), const Color(0xFFD8DED4)),
      accent: _color(value('notificationAccent', fallback: value('accent')), const Color(0xFF5F7F55)),
      success: _color(value('success'), const Color(0xFF18AD86)),
      warning: _color(value('warning'), const Color(0xFFF59E0B)),
      danger: _color(value('danger'), const Color(0xFFC85F55)),
      info: _color(value('info'), const Color(0xFF5577F2)),
      cardRadius: radius,
      screenPadding: padding,
      deckCardLimit: _number(value('deckCardLimit', fallback: 4), 4).round().clamp(2, 6).toInt(),
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, value) => MapEntry(key.toString(), value));
    return const <String, dynamic>{};
  }

  static num _number(Object? value, num fallback) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  static Color _color(Object? value, Color fallback) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return fallback;
    var hex = raw.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return fallback;
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }
}

class _NotificationStackHeader extends StatelessWidget {
  const _NotificationStackHeader({
    required this.style,
    required this.totalCount,
    required this.visibleCount,
    required this.unreadCount,
    required this.latestTime,
    required this.onMarkAll,
  });

  final _StackNotificationStyle style;
  final int totalCount;
  final int visibleCount;
  final int unreadCount;
  final DateTime? latestTime;
  final VoidCallback? onMarkAll;

  @override
  Widget build(BuildContext context) {
    final active = unreadCount > 0;
    final accent = active ? style.warning : style.accent;

    return Dismissible(
      key: const ValueKey('notification_stack_header_swipe'),
      direction: onMarkAll == null ? DismissDirection.none : DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        onMarkAll?.call();
        return false;
      },
      background: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: style.success, borderRadius: BorderRadius.circular(style.cardRadius)),
        child: const Row(
          children: [
            Icon(Icons.done_all_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text('Accept all', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: style.surface,
          borderRadius: BorderRadius.circular(style.cardRadius),
          border: Border.all(color: accent.withOpacity(.18)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.045), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Row(
          children: [
            _HeaderBell(active: active, color: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active ? '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}' : 'No unread alerts',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: style.textPrimary, fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${visibleCount == totalCount ? totalCount : '$visibleCount / $totalCount'} visible • Latest ${latestTime == null ? '—' : _timeText(latestTime!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: style.textSecondary, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  if (active) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Tap the stack to expand. Swipe this header right to accept all unread alerts.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: style.textSecondary.withOpacity(.78), fontWeight: FontWeight.w700, fontSize: 11.5, height: 1.2),
                    ),
                  ],
                ],
              ),
            ),
            if (onMarkAll != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Accept all',
                onPressed: onMarkAll,
                icon: Icon(Icons.done_all_rounded, color: style.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderBell extends StatelessWidget {
  const _HeaderBell({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: active ? 1.07 : 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(22)),
        child: Icon(active ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, color: color, size: 30),
      ),
    );
  }
}

class _NotificationStackFilterBar extends StatelessWidget {
  const _NotificationStackFilterBar({
    required this.style,
    required this.selected,
    required this.total,
    required this.unread,
    required this.taskCount,
    required this.meetingCount,
    required this.onChanged,
  });

  final _StackNotificationStyle style;
  final String selected;
  final int total;
  final int unread;
  final int taskCount;
  final int meetingCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final filters = <({String label, int count, IconData icon})>[
      (label: 'All', count: total, icon: Icons.layers_rounded),
      (label: 'Unread', count: unread, icon: Icons.mark_email_unread_rounded),
      (label: 'Tasks', count: taskCount, icon: Icons.task_alt_rounded),
      (label: 'Meetings', count: meetingCount, icon: Icons.video_call_rounded),
      (label: 'Mentions', count: 0, icon: Icons.alternate_email_rounded),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: filters.map((item) {
          final active = selected == item.label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: active,
              onSelected: (_) => onChanged(item.label),
              avatar: Icon(item.icon, size: 16, color: active ? Colors.white : style.accent),
              label: Text(item.label == 'Mentions' ? 'Mentions' : '${item.label} ${item.count}'),
              selectedColor: style.accent,
              backgroundColor: style.surface,
              side: BorderSide(color: active ? style.accent : style.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              labelStyle: TextStyle(color: active ? Colors.white : style.textPrimary, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NotificationModeSelector extends StatelessWidget {
  const _NotificationModeSelector({
    required this.style,
    required this.selected,
    required this.visibleCount,
    required this.unreadCount,
    required this.onSelected,
  });

  final _StackNotificationStyle style;
  final _NotificationViewMode selected;
  final int visibleCount;
  final int unreadCount;
  final ValueChanged<_NotificationViewMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: style.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 18, offset: const Offset(0, 9))],
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModePill(
              label: 'Stack',
              count: visibleCount,
              icon: Icons.style_rounded,
              selected: selected == _NotificationViewMode.stack,
              style: style,
              onTap: () => onSelected(_NotificationViewMode.stack),
            ),
          ),
          Expanded(
            child: _ModePill(
              label: 'Expanded',
              count: unreadCount,
              icon: Icons.format_list_bulleted_rounded,
              selected: selected == _NotificationViewMode.expanded,
              style: style,
              onTap: () => onSelected(_NotificationViewMode.expanded),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final _StackNotificationStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : style.textSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: selected ? style.accent : Colors.transparent, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 17),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12.5))),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: selected ? Colors.white.withOpacity(.18) : style.background, borderRadius: BorderRadius.circular(999)),
              child: Text('$count', style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 10.5)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StackedNotificationDeck extends StatelessWidget {
  const _StackedNotificationDeck({
    required this.entries,
    required this.totalCount,
    required this.controller,
    required this.style,
    required this.onToggle,
    required this.onTapNotification,
    required this.onAction,
  });

  final List<AppNotification> entries;
  final int totalCount;
  final AnimationController controller;
  final _StackNotificationStyle style;
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
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = entries.length - 1; i >= 0; i--)
                    _DeckCardPosition(
                      index: i,
                      controller: controller,
                      child: _DeckNotificationCard(
                        notification: entries[i],
                        style: style,
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
                  _CollapseChipPositioned(controller: controller, style: style, onTap: onToggle),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DeckCardPosition extends AnimatedWidget {
  const _DeckCardPosition({required this.index, required Animation<double> controller, required this.child}) : super(listenable: controller);

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

    return Positioned(
      left: sideInset,
      right: sideInset,
      top: top,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

class _DeckNotificationCard extends StatelessWidget {
  const _DeckNotificationCard({
    required this.notification,
    required this.style,
    required this.collapsedGetter,
    required this.isTop,
    required this.extraCount,
    required this.onTap,
    required this.onAction,
  });

  final AppNotification notification;
  final _StackNotificationStyle style;
  final bool Function() collapsedGetter;
  final bool isTop;
  final int extraCount;
  final VoidCallback onTap;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final collapsed = collapsedGetter();
    final type = _NotificationVisualType.from(notification, style);
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
            decoration: BoxDecoration(
              color: style.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: notification.isRead ? style.border.withOpacity(.74) : accent, width: notification.isRead ? 1 : 1.35),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isTop ? .055 : .04), blurRadius: isTop ? 16 : 11, offset: Offset(0, isTop ? 8 : 5))],
            ),
            child: Row(
              children: [
                _NotificationIconBubble(type: type, unread: !notification.isRead, style: style),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _NotificationTag(type: type, style: style),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              collapsed && !isTop ? 'Notification' : notification.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: style.textPrimary, fontSize: 14.5, fontWeight: notification.isRead ? FontWeight.w700 : FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        collapsed && !isTop ? 'Tap to expand the stack' : notification.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: style.textSecondary, fontSize: 12.2, height: 1.2, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded, size: 13, color: style.textSecondary.withOpacity(.82)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${_timeText(notification.createdAt)} • ${DateText.compact(notification.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: style.textSecondary.withOpacity(.82), fontSize: 10.8, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isTop) ...[
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: notification.hasActionUrl ? onAction : onTap,
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: accent.withOpacity(.13), shape: BoxShape.circle),
                          child: Icon(collapsed ? Icons.keyboard_arrow_down_rounded : (notification.hasActionUrl ? Icons.open_in_new_rounded : Icons.check_rounded), color: accent, size: 24),
                        ),
                      ),
                      if (collapsed && extraCount > 0) ...[
                        const SizedBox(height: 6),
                        Container(
                          constraints: const BoxConstraints(minWidth: 48),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(color: accent.withOpacity(.10), borderRadius: BorderRadius.circular(99)),
                          alignment: Alignment.center,
                          child: Text('+$extraCount', style: TextStyle(color: accent, fontSize: 10.5, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollapseChipPositioned extends AnimatedWidget {
  const _CollapseChipPositioned({required Animation<double> controller, required this.style, required this.onTap}) : super(listenable: controller);

  final _StackNotificationStyle style;
  final VoidCallback onTap;

  Animation<double> get _controller => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    final progress = Curves.easeOutCubic.transform(_controller.value);
    return Positioned(
      right: 12,
      bottom: 0,
      child: IgnorePointer(
        ignoring: progress < .75,
        child: Opacity(opacity: progress > .75 ? 1 : 0, child: _CollapseChip(style: style, onTap: onTap)),
      ),
    );
  }
}

class _CollapseChip extends StatelessWidget {
  const _CollapseChip({required this.style, required this.onTap});

  final _StackNotificationStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: style.accent, borderRadius: BorderRadius.circular(22)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Collapse', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900)),
            SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ExpandedNotificationCard extends StatelessWidget {
  const _ExpandedNotificationCard({
    required this.notification,
    required this.style,
    required this.onTap,
    required this.onAction,
  });

  final AppNotification notification;
  final _StackNotificationStyle style;
  final VoidCallback onTap;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final type = _NotificationVisualType.from(notification, style);
    final accent = type.color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey<String>('notification_${notification.notificationId}'),
        direction: notification.isRead ? DismissDirection.none : DismissDirection.startToEnd,
        confirmDismiss: (_) async {
          onTap();
          return false;
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: style.success, borderRadius: BorderRadius.circular(24)),
          child: const Row(
            children: [
              Icon(Icons.done_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Accept', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: style.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: notification.isRead ? style.border : accent.withOpacity(.86)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 14, offset: const Offset(0, 7))],
              ),
              child: Row(
                children: [
                  _NotificationIconBubble(type: type, unread: !notification.isRead, style: style),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          _NotificationTag(type: type, style: style),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(notification.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: style.textPrimary, fontWeight: notification.isRead ? FontWeight.w700 : FontWeight.w900, fontSize: 14.5)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(notification.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: style.textSecondary, fontWeight: FontWeight.w700, fontSize: 12.2, height: 1.2)),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            Icon(Icons.schedule_rounded, size: 13, color: style.textSecondary.withOpacity(.84)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text('${_timeText(notification.createdAt)} • ${DateText.compact(notification.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: style.textSecondary.withOpacity(.84), fontWeight: FontWeight.w800, fontSize: 10.8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (notification.hasActionUrl)
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, visualDensity: VisualDensity.compact, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
                      onPressed: onAction,
                      child: Text((notification.actionLabel ?? '').trim().isEmpty ? 'Join' : notification.actionLabel!.trim()),
                    )
                  else if (!notification.isRead)
                    Icon(Icons.swipe_right_alt_rounded, color: accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StackFooterHint extends StatelessWidget {
  const _StackFooterHint({required this.style, required this.message});

  final _StackNotificationStyle style;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: style.surfaceAlt.withOpacity(.72), borderRadius: BorderRadius.circular(18), border: Border.all(color: style.border)),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: style.textSecondary, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: style.textSecondary, fontWeight: FontWeight.w800, fontSize: 12))),
        ],
      ),
    );
  }
}

class _NotificationGroupHeader extends StatelessWidget {
  const _NotificationGroupHeader({required this.style, required this.label});

  final _StackNotificationStyle style;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(label, style: TextStyle(color: style.textSecondary, fontWeight: FontWeight.w900, fontSize: 12.5)),
    );
  }
}

class _NotificationIconBubble extends StatelessWidget {
  const _NotificationIconBubble({required this.type, required this.unread, required this.style});

  final _NotificationVisualType type;
  final bool unread;
  final _StackNotificationStyle style;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: type.color.withOpacity(unread ? .14 : .08), borderRadius: BorderRadius.circular(18)),
          child: Icon(type.icon, color: unread ? type.color : style.textSecondary, size: 23),
        ),
        if (unread)
          Positioned(
            right: -2,
            top: -2,
            child: Container(width: 11, height: 11, decoration: BoxDecoration(color: type.color, shape: BoxShape.circle, border: Border.all(color: style.surface, width: 2))),
          ),
      ],
    );
  }
}

class _NotificationTag extends StatelessWidget {
  const _NotificationTag({required this.type, required this.style});

  final _NotificationVisualType type;
  final _StackNotificationStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: type.color.withOpacity(.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: type.color.withOpacity(.18))),
      child: Text(type.label, style: TextStyle(color: type.color, fontWeight: FontWeight.w900, fontSize: 10.5)),
    );
  }
}

class _NotificationVisualType {
  const _NotificationVisualType({required this.color, required this.icon, required this.label});

  final Color color;
  final IconData icon;
  final String label;

  static _NotificationVisualType from(AppNotification notification, _StackNotificationStyle style) {
    final text = '${notification.type} ${notification.title} ${notification.message}'.toLowerCase();
    if (notification.isMeetingInvite) {
      return _NotificationVisualType(color: style.info, icon: Icons.video_call_rounded, label: 'Meeting');
    }
    if (text.contains('deadline') || text.contains('overdue') || text.contains('urgent')) {
      return _NotificationVisualType(color: style.danger, icon: Icons.warning_amber_rounded, label: 'Urgent');
    }
    if (text.contains('task') || notification.taskId != null || text.contains('assign')) {
      return _NotificationVisualType(color: style.accent, icon: Icons.task_alt_rounded, label: 'Task');
    }
    if (text.contains('mention') || text.contains('@')) {
      return _NotificationVisualType(color: style.warning, icon: Icons.alternate_email_rounded, label: 'Mention');
    }
    return _NotificationVisualType(color: style.success, icon: Icons.notifications_active_rounded, label: 'Update');
  }
}

class _NotificationGroupRow {
  const _NotificationGroupRow._({this.label, this.notification});

  factory _NotificationGroupRow.header(String label) => _NotificationGroupRow._(label: label);
  factory _NotificationGroupRow.card(AppNotification notification) => _NotificationGroupRow._(notification: notification);

  final String? label;
  final AppNotification? notification;
}

String _timeText(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

Uri? _safeUri(String? raw) {
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


class _AdminNotificationEscalationPanel extends StatefulWidget {
  const _AdminNotificationEscalationPanel({required this.companyId});

  final String companyId;

  @override
  State<_AdminNotificationEscalationPanel> createState() =>
      _AdminNotificationEscalationPanelState();
}

class _AdminNotificationEscalationPanelState
    extends State<_AdminNotificationEscalationPanel> {
  late final OracleNotificationBackendService _backend;
  final Set<String> _busyIds = <String>{};

  @override
  void initState() {
    super.initState();
    _backend = OracleNotificationBackendService();
  }

  @override
  void dispose() {
    _backend.close();
    super.dispose();
  }

  Future<void> _resend(String notificationId) async {
    if (_busyIds.contains(notificationId)) return;
    setState(() => _busyIds.add(notificationId));
    try {
      await _backend.resendNotification(
        companyId: widget.companyId,
        notificationId: notificationId,
        resetAttempts: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification queued for a fresh three-attempt cycle.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(notificationId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('companies')
        .doc(widget.companyId)
        .collection('notificationLogs')
        .where('adminAttentionRequired', isEqualTo: true)
        .limit(20)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _EscalationBanner(
            icon: Icons.warning_amber_rounded,
            title: 'Notification escalation feed unavailable',
            message: '${snapshot.error}',
          );
        }
        final documents = snapshot.data?.docs.toList() ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        documents.sort((a, b) {
          final aTime = a.data()['escalatedAt'];
          final bTime = b.data()['escalatedAt'];
          final aMillis = aTime is Timestamp ? aTime.millisecondsSinceEpoch : 0;
          final bMillis = bTime is Timestamp ? bTime.millisecondsSinceEpoch : 0;
          return bMillis.compareTo(aMillis);
        });
        if (documents.isEmpty) {
          return _EscalationBanner(
            icon: Icons.verified_rounded,
            title: 'No notification escalations',
            message: 'Employees have no unanswered three-attempt alerts.',
          );
        }

        final colors = Theme.of(context).colorScheme;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.errorContainer.withOpacity(0.58),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.error.withOpacity(0.22)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.notification_important_rounded, color: colors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Needs admin attention (${documents.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...documents.take(8).map((document) {
                  final data = document.data();
                  final notificationId =
                      (data['notificationId'] as String?)?.trim().isNotEmpty == true
                          ? (data['notificationId'] as String).trim()
                          : document.id;
                  final title = (data['title'] as String?)?.trim();
                  final recipientId = (data['recipientId'] as String?)?.trim() ?? '';
                  final reason = (data['reason'] as String?)?.trim() ?? 'No employee response';
                  final attempts = data['attemptCount'] is num
                      ? (data['attemptCount'] as num).toInt()
                      : 0;
                  final maximum = data['maxAttempts'] is num
                      ? (data['maxAttempts'] as num).toInt()
                      : 3;
                  final busy = _busyIds.contains(notificationId);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title?.isNotEmpty == true ? title! : 'Unanswered notification',
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Employee: $recipientId • Attempts: $attempts/$maximum',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    reason.replaceAll('_', ' '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: colors.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.tonalIcon(
                              onPressed: NotificationBackendConfig.isConfigured && !busy
                                  ? () => _resend(notificationId)
                                  : null,
                              icon: busy
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                              label: const Text('Resend'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                if (!NotificationBackendConfig.isConfigured)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Resend is disabled until NOTIFICATION_BACKEND_BASE_URL is supplied while building the admin web app.',
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EscalationBanner extends StatelessWidget {
  const _EscalationBanner({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
