import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/crash/apk_crash_forensics.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/task.dart';

/// Premium hardcoded Task Timeline route for the employee APK.
///
/// This screen is intentionally first-class Flutter UI, not a generic SDUI
/// fallback. It never generates fake task rows. Every chart, bar, count, and
/// title is derived from WorkspaceState.visibleTasks or scoped WorkspaceState
/// task data. If there is no task data, QA gets a clear empty state instead of
/// demo labels.
class TaskTimelineScreen extends ConsumerStatefulWidget {
  const TaskTimelineScreen({super.key, this.onPreviewLog});

  final ValueChanged<String>? onPreviewLog;

  @override
  ConsumerState<TaskTimelineScreen> createState() => _TaskTimelineScreenState();
}

class _TaskTimelineScreenState extends ConsumerState<TaskTimelineScreen> {
  _TimelineFilter _filter = _TimelineFilter.all;
  String _query = '';
  String _selectedProjectId = 'all';
  String? _selectedTaskId;
  _TimelineMapScale _mapScale = _TimelineMapScale.week;
  DateTime _timelineFocusDate = DateTime.now();

  void _previewLog(String message) => widget.onPreviewLog?.call(message);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    _TimelinePalette.applyFromState(state);
    final data = _TimelineDataSet.fromState(state);
    final projects = data.projectOptions;
    final items = data.filteredItems(
      filter: _filter,
      query: _query,
      projectId: _selectedProjectId,
    );
    final allItems = data.items;
    final stats = _TimelineStats.fromItems(items, allItems: allItems);
    final window = _TimelineWindow.calendar(scale: _mapScale, focusDate: _timelineFocusDate);
    final selectedItem = _selectedTimelineItem(items, _selectedTaskId);

    ApkCrashForensics.log(
      'task_timeline_native_build',
      data: <String, Object?>{
        'source': data.source,
        'visibleTasks': data.visibleTaskCount,
        'allTasks': data.allTaskCount,
        'filteredItems': items.length,
        'filter': _filter.name,
        'projectId': _selectedProjectId,
        'query': _query.trim(),
        'selectedTaskId': selectedItem?.id ?? '',
        'selectedTaskTitle': selectedItem?.title ?? '',
        'timelineScale': _mapScale.name,
        'timelineWindow': window.rangeLabel,
      },
    );

    return Scaffold(
      backgroundColor: _TimelinePalette.background,
      body: SafeArea(
        child: Column(
          children: [
            if (state.isSaving)
              const LinearProgressIndicator(
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
              ),
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(_TimelinePalette.screenPadding, 14, _TimelinePalette.screenPadding, 0),
                      child: _TimelineHeader(
                        liveCount: allItems.length,
                        source: data.sourceShort,
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(_TimelinePalette.screenPadding, 16, _TimelinePalette.screenPadding, 0),
                      child: _TimelineHeroCard(stats: stats, data: data),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(_TimelinePalette.screenPadding, 14, _TimelinePalette.screenPadding, 0),
                      child: _TimelineControls(
                        query: _query,
                        selectedProjectId: _selectedProjectId,
                        projects: projects,
                        filter: _filter,
                        stats: _TimelineStats.fromItems(allItems, allItems: allItems),
                        onQueryChanged: (value) {
                          setState(() => _query = value);
                          _previewLog('taskTimeline_search query=${value.trim()}');
                        },
                        onProjectChanged: (value) {
                          setState(() {
                            _selectedProjectId = value ?? 'all';
                            _selectedTaskId = null;
                          });
                          _previewLog('taskTimeline_project_selected project=${value ?? 'all'}');
                        },
                        onFilterChanged: (value) {
                          setState(() {
                            _filter = value;
                            _selectedTaskId = null;
                          });
                          _previewLog('taskTimeline_filter_selected filter=${value.name}');
                        },
                      ),
                    ),
                  ),
                  if (allItems.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(_TimelinePalette.screenPadding, 16, _TimelinePalette.screenPadding, 24),
                        child: _EmptyTimelineState(data: data),
                      ),
                    )
                  else if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(_TimelinePalette.screenPadding, 16, _TimelinePalette.screenPadding, 24),
                        child: _FilteredEmptyState(onClear: () {
                            setState(() {
                              _filter = _TimelineFilter.all;
                              _query = '';
                              _selectedProjectId = 'all';
                            });
                            _previewLog('taskTimeline_filters_cleared');
                          }),
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(_TimelinePalette.screenPadding, 16, _TimelinePalette.screenPadding, 0),
                        child: _GanttCommandCard(
                          items: items,
                          window: window,
                          selectedTaskId: selectedItem?.id,
                          scale: _mapScale,
                          onScaleChanged: (value) {
                            setState(() {
                              _mapScale = value;
                              _timelineFocusDate = DateTime.now();
                            });
                            _previewLog('taskTimeline_map_scale scale=${value.name}');
                          },
                          onWindowShift: (delta) {
                            setState(() => _timelineFocusDate = delta == 0 ? DateTime.now() : _shiftTimelineFocus(_timelineFocusDate, _mapScale, delta));
                            _previewLog('taskTimeline_map_window_shift delta=$delta scale=${_mapScale.name}');
                          },
                          onCalendarTap: () {
                            _previewLog('taskTimeline_calendar_picker_opened scale=${_mapScale.name}');
                            _pickTimelineFocusDate(context);
                          },
                          onTaskSelected: (item) {
                            setState(() => _selectedTaskId = item.id);
                            _previewLog('taskTimeline_gantt_selected task=${item.title}');
                          },
                          onTaskOpened: (item) {
                            _previewLog('taskTimeline_gantt_opened task=${item.title}');
                            _showTaskInsightSheet(context, item);
                          },
                          onViewFullTimeline: () {
                            _previewLog('taskTimeline_full_timeline_opened rows=${items.length}');
                            _showFullTimelineSheet(context, items, window, selectedItem);
                          },
                        ),
                      ),
                    ),
                    if (selectedItem != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(_TimelinePalette.screenPadding, 12, _TimelinePalette.screenPadding, 0),
                          child: _SelectedTaskRevealCard(
                            item: selectedItem,
                            onComment: () {
                              _previewLog('taskTimeline_selected_reveal_comment task=${selectedItem.title}');
                              _showCommentDialog(context, selectedItem);
                            },
                            onAttach: () {
                              _previewLog('taskTimeline_selected_reveal_attach task=${selectedItem.title}');
                              _attachFileToTask(context, selectedItem);
                            },
                            onUpdate: () {
                              _previewLog('taskTimeline_selected_reveal_update task=${selectedItem.title}');
                              _showStatusUpdateSheet(context, selectedItem);
                            },
                            onToggleWorkTimer: () {
                              _previewLog('taskTimeline_selected_reveal_work_timer task=${selectedItem.title} running=${selectedItem.workTimerRunningForCurrentUser}');
                              _toggleWorkTimer(context, selectedItem);
                            },
                            onOpen: () {
                              _previewLog('taskTimeline_selected_reveal_open task=${selectedItem.title}');
                              _showTaskInsightSheet(context, selectedItem);
                            },
                            onClear: () {
                              setState(() => _selectedTaskId = null);
                              _previewLog('taskTimeline_selected_reveal_cleared');
                            },
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(_TimelinePalette.screenPadding, 16, _TimelinePalette.screenPadding, 0),
                        child: _StatusFlowCard(stats: stats),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(_TimelinePalette.screenPadding, 16, _TimelinePalette.screenPadding, 120),
                      sliver: SliverList.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _TaskTimelineTile(
                            item: item,
                            index: index,
                            selected: selectedItem?.id == item.id,
                            onTap: () {
                              setState(() => _selectedTaskId = item.id);
                              _previewLog('taskTimeline_task_selected task=${item.title}');
                            },
                            onOpen: () {
                              _previewLog('taskTimeline_task_insight task=${item.title}');
                              _showTaskInsightSheet(context, item);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _showCommentDialog(BuildContext context, _TimelineItem item) async {
    if (!item.assignedToCurrentUser) return;
    HapticFeedback.selectionClick();
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add comment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            hintText: 'Write task update...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    final text = message?.trim() ?? '';
    if (text.isEmpty || !context.mounted) return;
    ref.read(workspaceProvider.notifier).addTaskComment(item.id, text);
    final error = ref.read(workspaceProvider).lastError;
    _showTimelineSnack(context, error == null ? 'Comment added.' : error);
  }

  Future<void> _attachFileToTask(BuildContext context, _TimelineItem item) async {
    if (!item.assignedToCurrentUser) return;
    HapticFeedback.selectionClick();
    final ok = await ref.read(workspaceProvider.notifier).addAttachmentFromDevicePicker(item.id);
    if (!context.mounted) return;
    final error = ref.read(workspaceProvider).lastError;
    _showTimelineSnack(context, ok ? 'File attached to task.' : (error ?? 'File selection cancelled.'));
  }

  Future<void> _showStatusUpdateSheet(BuildContext context, _TimelineItem item) async {
    if (!item.assignedToCurrentUser) return;
    HapticFeedback.selectionClick();
    final nextStatus = await showModalBottomSheet<TaskStatus>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TaskStatusUpdateSheet(item: item),
    );
    if (nextStatus == null || nextStatus == item.status || !context.mounted) return;
    ref.read(workspaceProvider.notifier).updateTaskStatus(item.id, nextStatus);
    final error = ref.read(workspaceProvider).lastError;
    _showTimelineSnack(context, error == null ? 'Task moved to ${nextStatus.label}.' : error);
  }


  void _toggleWorkTimer(BuildContext context, _TimelineItem item) {
    if (!item.assignedToCurrentUser) return;
    HapticFeedback.selectionClick();
    final controller = ref.read(workspaceProvider.notifier);
    if (item.workTimerRunningForCurrentUser) {
      controller.stopTaskWorkTimer(item.id);
    } else {
      controller.startTaskWorkTimer(item.id);
    }
    final error = ref.read(workspaceProvider).lastError;
    final message = error == null
        ? (item.workTimerRunningForCurrentUser ? 'Work counter stopped and logged.' : 'Work counter started.')
        : error;
    _showTimelineSnack(context, message);
  }

  void _showTimelineSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickTimelineFocusDate(BuildContext context) async {
    final now = DateTime.now();
    final initial = _dateOnly(_timelineFocusDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: _mapScale == _TimelineMapScale.month ? 'Select month' : 'Select week date',
      cancelText: 'Cancel',
      confirmText: 'Apply',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: _TimelinePalette.accentDark,
            onPrimary: Colors.white,
            surface: _TimelinePalette.surface,
            onSurface: _TimelinePalette.ink,
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _timelineFocusDate = _dateOnly(picked));
    _previewLog('taskTimeline_calendar_date_selected date=${picked.toIso8601String()} scale=${_mapScale.name}');
  }

  void _showFullTimelineSheet(BuildContext context, List<_TimelineItem> items, _TimelineWindow window, _TimelineItem? selectedItem) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'taskTimelineFull'),
        builder: (context) => _FullTimelineSheet(
          items: items,
          window: window,
          selectedTaskId: selectedItem?.id,
        ),
      ),
    );
  }

  void _showTaskInsightSheet(BuildContext context, _TimelineItem item) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TaskInsightSheet(item: item),
    );
  }
}

enum _TimelineFilter { all, open, overdue, done }

extension _TimelineFilterX on _TimelineFilter {
  String get label => switch (this) {
        _TimelineFilter.all => 'All',
        _TimelineFilter.open => 'Open',
        _TimelineFilter.overdue => 'Overdue',
        _TimelineFilter.done => 'Done',
      };

  IconData get icon => switch (this) {
        _TimelineFilter.all => Icons.auto_awesome_mosaic_rounded,
        _TimelineFilter.open => Icons.bolt_rounded,
        _TimelineFilter.overdue => Icons.warning_amber_rounded,
        _TimelineFilter.done => Icons.verified_rounded,
      };
}

enum _TimelineMapScale { week, month }

extension _TimelineMapScaleX on _TimelineMapScale {
  String get label => switch (this) {
        _TimelineMapScale.week => 'Week',
        _TimelineMapScale.month => 'Month',
      };

  int get shiftDays => switch (this) {
        _TimelineMapScale.week => 7,
        _TimelineMapScale.month => 31,
      };
}



class _TimelinePalette {
  static Color background = const Color(0xFFF4F5F1);
  static Color surface = const Color(0xFFFFFFFF);
  static Color surfaceAlt = const Color(0xFFF0F3EC);
  static Color ink = const Color(0xFF101410);
  static Color muted = const Color(0xFF667064);
  static Color accent = const Color(0xFF4E8064);
  static Color accentDark = const Color(0xFF315C47);
  static Color border = const Color(0xFFE1E6DC);
  static Color danger = const Color(0xFFFF5639);
  static Color warning = const Color(0xFFF59E0B);
  static Color success = const Color(0xFF18AD86);
  static Color blue = const Color(0xFF5577F2);
  static Color purple = const Color(0xFF7C5CF3);

  static double cardRadius = 30;
  static double controlRadius = 999;
  static double screenPadding = 18;
  static String source = 'native defaults';

  static void applyFromState(WorkspaceState state) {
    final designSystem = <String, dynamic>{
      ...state.mobileUiConfig.designSystem,
      ...state.mobileUiDesign.designSystem,
      ...state.mobileUiDesign.theme,
    };
    final config = _timelineJsonSection(state.mobileUiConfig.screenConfigs['taskTimeline']);
    final override = _timelineJsonSection(state.mobileUiConfig.screenOverrides['taskTimeline']);
    final designConfig = _timelineJsonSection(state.mobileUiDesign.screenConfigs['taskTimeline']);
    final designOverride = _timelineJsonSection(state.mobileUiDesign.screenOverrides['taskTimeline']);
    final themeBlock = <String, dynamic>{
      ...designSystem,
      ..._timelineJsonSection(config['theme']),
      ..._timelineJsonSection(config['colors']),
      ..._timelineJsonSection(config['palette']),
      ..._timelineJsonSection(config['cosmetic']),
      ..._timelineJsonSection(config['taskTimelineTheme']),
      ..._timelineJsonSection(config['taskTimelineColors']),
      ..._timelineJsonSection(override['theme']),
      ..._timelineJsonSection(override['colors']),
      ..._timelineJsonSection(override['palette']),
      ..._timelineJsonSection(override['cosmetic']),
      ..._timelineJsonSection(override['taskTimelineTheme']),
      ..._timelineJsonSection(override['taskTimelineColors']),
      ..._timelineJsonSection(designConfig['theme']),
      ..._timelineJsonSection(designConfig['colors']),
      ..._timelineJsonSection(designConfig['palette']),
      ..._timelineJsonSection(designConfig['cosmetic']),
      ..._timelineJsonSection(designOverride['theme']),
      ..._timelineJsonSection(designOverride['colors']),
      ..._timelineJsonSection(designOverride['palette']),
      ..._timelineJsonSection(designOverride['cosmetic']),
    };

    background = _timelineColor(themeBlock, const ['taskTimelineBackground', 'pageBackground', 'background', 'surface'], background);
    surface = _timelineColor(themeBlock, const ['taskTimelineSurface', 'card', 'cardColor', 'surfaceCard', 'surface'], surface);
    surfaceAlt = _timelineColor(themeBlock, const ['surfaceAlt', 'cardAlt', 'mutedSurface', 'surfaceMuted', 'timelineSurfaceAlt'], surfaceAlt);
    ink = _timelineColor(themeBlock, const ['textPrimary', 'titleColor', 'ink', 'foreground'], ink);
    muted = _timelineColor(themeBlock, const ['textSecondary', 'textMuted', 'muted', 'subtitleColor'], muted);
    accent = _timelineColor(themeBlock, const ['taskTimelineAccent', 'accent', 'primary', 'brand', 'selected'], accent);
    accentDark = _timelineColor(themeBlock, const ['accentDark', 'primaryDark', 'brandDark'], accentDark);
    border = _timelineColor(themeBlock, const ['border', 'stroke', 'divider'], border);
    danger = _timelineColor(themeBlock, const ['danger', 'error', 'overdue', 'risk'], danger);
    warning = _timelineColor(themeBlock, const ['warning', 'watch', 'attention'], warning);
    success = _timelineColor(themeBlock, const ['success', 'done', 'completed'], success);
    blue = _timelineColor(themeBlock, const ['info', 'blue', 'todo', 'open'], blue);
    purple = _timelineColor(themeBlock, const ['purple', 'review', 'testing'], purple);

    cardRadius = _timelineDouble(themeBlock, const ['cardRadius', 'radiusLarge', 'taskTimelineCardRadius'], cardRadius).clamp(18.0, 42.0).toDouble();
    screenPadding = _timelineDouble(themeBlock, const ['screenPadding', 'pagePadding', 'taskTimelinePadding'], screenPadding).clamp(14.0, 26.0).toDouble();
    source = themeBlock.isEmpty ? 'native defaults' : 'JSON cosmetic theme';
  }
}

Map<String, dynamic> _timelineJsonSection(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry(key.toString(), value));
  return const <String, dynamic>{};
}

Color _timelineColor(Map<String, dynamic> map, List<String> keys, Color fallback) {
  for (final key in keys) {
    final value = map[key] ?? map[_lowerFirst(key)] ?? map[_upperFirst(key)];
    final parsed = _timelineParseColor(value);
    if (parsed != null) return parsed;
  }
  return fallback;
}

String _lowerFirst(String value) => value.isEmpty ? value : '${value[0].toLowerCase()}${value.substring(1)}';
String _upperFirst(String value) => value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

double _timelineDouble(Map<String, dynamic> map, List<String> keys, double fallback) {
  for (final key in keys) {
    final value = map[key] ?? map[_lowerFirst(key)] ?? map[_upperFirst(key)];
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return fallback;
}

Color? _timelineParseColor(Object? value) {
  if (value is Color) return value;
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  var hex = raw.replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
  if (hex.length == 3) {
    hex = hex.split('').map((char) => '$char$char').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}

class _TimelineDataSet {
  const _TimelineDataSet({
    required this.tasks,
    required this.projectNameById,
    required this.assigneeNameById,
    required this.currentUserId,
    required this.source,
    required this.visibleTaskCount,
    required this.allTaskCount,
    required this.visibleProjectCount,
  });

  final List<ProjectTask> tasks;
  final Map<String, String> projectNameById;
  final Map<String, String> assigneeNameById;
  final String currentUserId;
  final String source;
  final int visibleTaskCount;
  final int allTaskCount;
  final int visibleProjectCount;

  String get sourceShort {
    if (source.contains('visibleTasks')) return 'visibleTasks';
    if (source.contains('scoped')) return 'scoped tasks';
    return 'no task data';
  }

  List<_ProjectOption> get projectOptions {
    final ids = items.map((item) => item.projectId).where((id) => id.trim().isNotEmpty).toSet().toList()
      ..sort((a, b) => (projectNameById[a] ?? a).compareTo(projectNameById[b] ?? b));
    return <_ProjectOption>[
      const _ProjectOption(id: 'all', label: 'All projects'),
      ...ids.map((id) => _ProjectOption(id: id, label: projectNameById[id] ?? 'Project ${id.substring(0, math.min(id.length, 5))}')),
    ];
  }

  List<_TimelineItem> get items => tasks.map((task) {
        final title = task.title.trim().isEmpty ? 'Untitled task' : task.title.trim();
        final projectName = projectNameById[task.projectId] ?? 'Unlinked project';
        final assignees = task.assignedToIds.map((id) => assigneeNameById[id] ?? id).where((name) => name.trim().isNotEmpty).take(3).toList();
        final start = _taskStartDate(task);
        final progress = _progressForStatus(task.status);
        return _TimelineItem(
          id: task.taskId,
          projectId: task.projectId,
          teamId: task.teamId,
          title: title,
          projectName: projectName,
          assigneeLabel: assignees.isEmpty ? 'Unassigned' : assignees.join(', '),
          assignedToCurrentUser: task.assignedToIds.contains(currentUserId),
          startDate: start,
          dueDate: task.dueDate,
          progress: progress,
          color: _colorForTask(task),
          completed: task.status == TaskStatus.completed,
          overdue: task.isOverdue,
          status: task.status,
          statusLabel: task.status.label,
          priorityLabel: task.priority.label,
          priorityColor: task.priority.color,
          attachmentsCount: task.attachmentsCount,
          commentsCount: task.commentsCount,
          estimatedHours: task.estimatedHours,
          loggedHours: task.loggedHours,
          activeWorkTimerUserId: task.activeWorkTimerUserId,
          activeWorkTimerStartedAt: task.activeWorkTimerStartedAt,
          tags: task.tags,
        );
      }).toList();

  List<_TimelineItem> filteredItems({required _TimelineFilter filter, required String query, required String projectId}) {
    final q = query.trim().toLowerCase();
    return items.where((item) {
      final matchesProject = projectId == 'all' || item.projectId == projectId;
      final matchesFilter = switch (filter) {
        _TimelineFilter.all => true,
        _TimelineFilter.open => !item.completed,
        _TimelineFilter.overdue => item.overdue,
        _TimelineFilter.done => item.completed,
      };
      final matchesQuery = q.isEmpty ||
          item.title.toLowerCase().contains(q) ||
          item.projectName.toLowerCase().contains(q) ||
          item.statusLabel.toLowerCase().contains(q) ||
          item.priorityLabel.toLowerCase().contains(q) ||
          item.assigneeLabel.toLowerCase().contains(q);
      return matchesProject && matchesFilter && matchesQuery;
    }).toList()
      ..sort(_sortTimelineItem);
  }

  factory _TimelineDataSet.fromState(WorkspaceState state) {
    final projectNameById = <String, String>{
      for (final project in state.projects) project.projectId: project.name,
    };
    final assigneeNameById = <String, String>{
      for (final member in state.members) member.uid: member.displayName,
    };
    final currentUserId = state.currentMember.uid.trim().isNotEmpty ? state.currentMember.uid : state.user.uid;
    final visibleTasks = [...state.visibleTasks]..sort(_sortTaskByDueDate);
    if (visibleTasks.isNotEmpty) {
      return _TimelineDataSet(
        tasks: visibleTasks,
        projectNameById: projectNameById,
        assigneeNameById: assigneeNameById,
        currentUserId: currentUserId,
        source: 'WorkspaceState.visibleTasks',
        visibleTaskCount: state.visibleTasks.length,
        allTaskCount: state.tasks.length,
        visibleProjectCount: state.visibleProjects.length,
      );
    }

    final member = state.currentMember;
    final visibleProjectIds = state.visibleProjects.map((project) => project.projectId).where((id) => id.trim().isNotEmpty).toSet();
    final memberProjectIds = member.projectIds.where((id) => id.trim().isNotEmpty).toSet();
    final memberTeamIds = member.teamIds.where((id) => id.trim().isNotEmpty).toSet();

    final scopedTasks = state.tasks.where((task) {
      if (task.assignedToIds.contains(member.uid)) return true;
      if (visibleProjectIds.contains(task.projectId)) return true;
      if (memberProjectIds.contains(task.projectId)) return true;
      if (memberTeamIds.contains(task.teamId)) return true;
      if (member.role.isDeliveryManager) return true;
      return false;
    }).toList()..sort(_sortTaskByDueDate);

    return _TimelineDataSet(
      tasks: scopedTasks,
      projectNameById: projectNameById,
      assigneeNameById: assigneeNameById,
      currentUserId: currentUserId,
      source: scopedTasks.isEmpty ? 'empty: no visible/scoped tasks' : 'scoped WorkspaceState.tasks',
      visibleTaskCount: state.visibleTasks.length,
      allTaskCount: state.tasks.length,
      visibleProjectCount: state.visibleProjects.length,
    );
  }

  static DateTime _taskStartDate(ProjectTask task) {
    final explicit = task.createdAt ?? task.updatedAt;
    if (explicit != null && explicit.isBefore(task.dueDate)) return _dateOnly(explicit);
    final estimatedHours = task.estimatedHours.toDouble();
    final fallbackDays = estimatedHours <= 0 ? 1 : (estimatedHours / 8).ceil().clamp(1, 14).toInt();
    return _dateOnly(task.dueDate).subtract(Duration(days: fallbackDays));
  }

  static int _progressForStatus(TaskStatus status) => switch (status) {
        TaskStatus.backlog => 8,
        TaskStatus.todo => 18,
        TaskStatus.inProgress => 48,
        TaskStatus.review => 68,
        TaskStatus.testing => 82,
        TaskStatus.completed => 100,
      };

  static Color _colorForTask(ProjectTask task) {
    if (task.status == TaskStatus.completed) return _TimelinePalette.success;
    if (task.isOverdue) return _TimelinePalette.danger;
    return switch (task.status) {
      TaskStatus.backlog => const Color(0xFF8B95A1),
      TaskStatus.todo => _TimelinePalette.blue,
      TaskStatus.inProgress => const Color(0xFF2563EB),
      TaskStatus.review => _TimelinePalette.purple,
      TaskStatus.testing => const Color(0xFFF59E0B),
      TaskStatus.completed => _TimelinePalette.success,
    };
  }
}

class _ProjectOption {
  const _ProjectOption({required this.id, required this.label});
  final String id;
  final String label;
}

class _TimelineItem {
  const _TimelineItem({
    required this.id,
    required this.projectId,
    required this.teamId,
    required this.title,
    required this.projectName,
    required this.assigneeLabel,
    required this.assignedToCurrentUser,
    required this.startDate,
    required this.dueDate,
    required this.progress,
    required this.color,
    required this.completed,
    required this.overdue,
    required this.status,
    required this.statusLabel,
    required this.priorityLabel,
    required this.priorityColor,
    required this.attachmentsCount,
    required this.commentsCount,
    required this.estimatedHours,
    required this.loggedHours,
    required this.activeWorkTimerUserId,
    required this.activeWorkTimerStartedAt,
    required this.tags,
  });

  final String id;
  final String projectId;
  final String teamId;
  final String title;
  final String projectName;
  final String assigneeLabel;
  final bool assignedToCurrentUser;
  final DateTime startDate;
  final DateTime dueDate;
  final int progress;
  final Color color;
  final bool completed;
  final bool overdue;
  final TaskStatus status;
  final String statusLabel;
  final String priorityLabel;
  final Color priorityColor;
  final int attachmentsCount;
  final int commentsCount;
  final num estimatedHours;
  final num loggedHours;
  final String? activeWorkTimerUserId;
  final DateTime? activeWorkTimerStartedAt;
  final List<String> tags;

  int get durationDays => math.max(1, _dateOnly(dueDate).difference(_dateOnly(startDate)).inDays + 1);
  int get daysLeft => _dateOnly(dueDate).difference(_dateOnly(DateTime.now())).inDays;
  bool get isWorkTimerRunning => (activeWorkTimerUserId ?? '').trim().isNotEmpty && activeWorkTimerStartedAt != null;
  bool get workTimerRunningForCurrentUser => assignedToCurrentUser && isWorkTimerRunning;
  Duration get activeWorkDuration {
    final startedAt = activeWorkTimerStartedAt;
    if (!isWorkTimerRunning || startedAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }
  num get liveLoggedHours {
    if (!isWorkTimerRunning) return loggedHours;
    return double.parse((loggedHours.toDouble() + activeWorkDuration.inSeconds / 3600.0).toStringAsFixed(2));
  }
  double get effortRatio => estimatedHours == 0 ? 0 : (liveLoggedHours / estimatedHours).clamp(0, 1).toDouble();
}

_TimelineItem? _selectedTimelineItem(List<_TimelineItem> items, String? selectedTaskId) {
  if (selectedTaskId == null || selectedTaskId.trim().isEmpty) return null;
  for (final item in items) {
    if (item.id == selectedTaskId) return item;
  }
  return null;
}

bool _timelineItemIntersectsWindow(_TimelineItem item, _TimelineWindow window) {
  final start = _dateOnly(item.startDate);
  final end = _dateOnly(item.dueDate);
  return !end.isBefore(_dateOnly(window.start)) && !start.isAfter(_dateOnly(window.end));
}


class _TimelineStats {
  const _TimelineStats({
    required this.total,
    required this.open,
    required this.done,
    required this.overdue,
    required this.dueToday,
    required this.highPriority,
    required this.progress,
    required this.allTotal,
  });

  final int total;
  final int open;
  final int done;
  final int overdue;
  final int dueToday;
  final int highPriority;
  final int progress;
  final int allTotal;

  String get riskLabel {
    if (total == 0) return 'No data';
    if (overdue > 0) return 'At risk';
    if (highPriority > 0 && progress < 55) return 'Watch';
    if (progress >= 75) return 'Healthy';
    return 'Stable';
  }

  Color get riskColor => switch (riskLabel) {
        'At risk' => _TimelinePalette.danger,
        'Watch' => _TimelinePalette.warning,
        'Healthy' => _TimelinePalette.success,
        'Stable' => _TimelinePalette.accent,
        _ => _TimelinePalette.muted,
      };

  factory _TimelineStats.fromItems(List<_TimelineItem> items, {required List<_TimelineItem> allItems}) {
    final done = items.where((item) => item.completed).length;
    final overdue = items.where((item) => item.overdue).length;
    final dueToday = items.where((item) => _sameDate(item.dueDate, DateTime.now())).length;
    final highPriority = items.where((item) => item.priorityLabel.toLowerCase().contains('high') || item.priorityLabel.toLowerCase().contains('critical')).length;
    final progress = items.isEmpty ? 0 : (items.fold<int>(0, (sum, item) => sum + item.progress) / items.length).round().clamp(0, 100).toInt();
    return _TimelineStats(
      total: items.length,
      open: items.where((item) => !item.completed).length,
      done: done,
      overdue: overdue,
      dueToday: dueToday,
      highPriority: highPriority,
      progress: progress,
      allTotal: allItems.length,
    );
  }
}

class _TimelineWindow {
  const _TimelineWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  int get spanDays => math.max(1, _dateOnly(end).difference(_dateOnly(start)).inDays);

  double ratioFor(DateTime value) {
    final days = _dateOnly(value).difference(_dateOnly(start)).inDays;
    return (days / spanDays).clamp(0.0, 1.0).toDouble();
  }

  List<DateTime> get ticks => List.generate(6, (index) {
        final dayOffset = ((spanDays * index) / 5).round();
        return _dateOnly(start).add(Duration(days: dayOffset));
      });

  String get rangeLabel => '${DateText.compact(start)} – ${DateText.compact(end)}';

  static _TimelineWindow calendar({required _TimelineMapScale scale, required DateTime focusDate}) {
    final focus = _dateOnly(focusDate);
    if (scale == _TimelineMapScale.week) {
      final weekStart = _calendarWeekStart(focus);
      return _TimelineWindow(start: weekStart, end: weekStart.add(const Duration(days: 6)));
    }
    final monthStart = DateTime(focus.year, focus.month, 1);
    final monthEnd = DateTime(focus.year, focus.month + 1, 0);
    return _TimelineWindow(start: monthStart, end: monthEnd);
  }

  static _TimelineWindow fromItems(List<_TimelineItem> items) {
    final today = _dateOnly(DateTime.now());
    if (items.isEmpty) return _TimelineWindow(start: today.subtract(const Duration(days: 5)), end: today.add(const Duration(days: 5)));
    final dates = <DateTime>[today];
    for (final item in items) {
      dates.add(_dateOnly(item.startDate));
      dates.add(_dateOnly(item.dueDate));
    }
    dates.sort();
    var start = dates.first;
    var end = dates.last;
    if (end.difference(start).inDays < 6) {
      final missing = 6 - end.difference(start).inDays;
      start = start.subtract(Duration(days: (missing / 2).floor()));
      end = end.add(Duration(days: (missing / 2).ceil()));
    }
    start = start.subtract(const Duration(days: 1));
    end = end.add(const Duration(days: 1));
    return _TimelineWindow(start: start, end: end);
  }
}

DateTime _calendarWeekStart(DateTime value) {
  final date = _dateOnly(value);
  return date.subtract(Duration(days: date.weekday - DateTime.monday));
}

DateTime _shiftTimelineFocus(DateTime focus, _TimelineMapScale scale, int delta) {
  if (scale == _TimelineMapScale.week) return _dateOnly(focus).add(Duration(days: 7 * delta));
  return DateTime(focus.year, focus.month + delta, math.min(focus.day, 28));
}


int _sortTaskByDueDate(ProjectTask a, ProjectTask b) {
  final overdue = (b.isOverdue ? 1 : 0).compareTo(a.isOverdue ? 1 : 0);
  if (overdue != 0) return overdue;
  final due = a.dueDate.compareTo(b.dueDate);
  if (due != 0) return due;
  return a.title.compareTo(b.title);
}

int _sortTimelineItem(_TimelineItem a, _TimelineItem b) {
  final overdue = (b.overdue ? 1 : 0).compareTo(a.overdue ? 1 : 0);
  if (overdue != 0) return overdue;
  final due = a.dueDate.compareTo(b.dueDate);
  if (due != 0) return due;
  return a.title.compareTo(b.title);
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

bool _sameDate(DateTime a, DateTime b) {
  final left = _dateOnly(a);
  final right = _dateOnly(b);
  return left.year == right.year && left.month == right.month && left.day == right.day;
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({required this.liveCount, required this.source, required this.onBack});

  final int liveCount;
  final String source;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CircleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Task Timeline', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.ink, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -.5)),
              SizedBox(height: 2),
              Text('Execution map from real workspace tasks • ${_TimelinePalette.source}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.muted, fontSize: 12.2, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(color: _TimelinePalette.accent, borderRadius: BorderRadius.circular(999), boxShadow: [BoxShadow(color: _TimelinePalette.accent.withOpacity(.18), blurRadius: 18, offset: const Offset(0, 8))]),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sensors_rounded, color: Colors.white, size: 14),
              SizedBox(width: 6),
              Text('$liveCount', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _TimelinePalette.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(width: 46, height: 46, child: Icon(icon, color: _TimelinePalette.ink, size: 21)),
      ),
    );
  }
}

class _TimelineHeroCard extends StatelessWidget {
  const _TimelineHeroCard({required this.stats, required this.data});

  final _TimelineStats stats;
  final _TimelineDataSet data;

  @override
  Widget build(BuildContext context) {
    return _AnimatedIn(
      index: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _TimelinePalette.accentDark,
              _TimelinePalette.accent,
              Color.lerp(_TimelinePalette.accent, _TimelinePalette.success, .34) ?? _TimelinePalette.accent,
            ],
          ),
          borderRadius: BorderRadius.circular(_TimelinePalette.cardRadius + 2),
          boxShadow: [BoxShadow(color: _TimelinePalette.accent.withOpacity(.22), blurRadius: 30, offset: const Offset(0, 16))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(.18), borderRadius: BorderRadius.circular(19), border: Border.all(color: Colors.white.withOpacity(.20))),
                  child: Icon(Icons.route_rounded, color: Colors.white, size: 25),
                ),
                SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Delivery cockpit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17.5, letterSpacing: -.35)),
                      SizedBox(height: 3),
                      Text('Live plan, progress and delivery risk', style: TextStyle(color: Color(0xE8FFFFFF), fontWeight: FontWeight.w700, fontSize: 12.2)),
                    ],
                  ),
                ),
                _HeroProgressPill(progress: stats.progress),
              ],
            ),
            SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _HeroMetric(label: 'Open', value: '${stats.open}', icon: Icons.bolt_rounded)),
                SizedBox(width: 10),
                Expanded(child: _HeroMetric(label: 'Due today', value: '${stats.dueToday}', icon: Icons.today_rounded)),
                SizedBox(width: 10),
                Expanded(child: _HeroMetric(label: 'Risk', value: '${stats.overdue}', icon: Icons.warning_amber_rounded)),
              ],
            ),
            SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${data.sourceShort} • ${data.visibleTaskCount} visible • ${data.allTaskCount} total',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(0xE8FFFFFF), fontWeight: FontWeight.w800, fontSize: 11.5),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: stats.riskColor.withOpacity(.20), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withOpacity(.18))),
                  child: Text(stats.riskLabel, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11.5)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroProgressPill extends StatelessWidget {
  const _HeroProgressPill({required this.progress});
  final int progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(color: Colors.white.withOpacity(.16), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(.22))),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              value: progress / 100,
              strokeWidth: 5,
              color: Colors.white,
              backgroundColor: Colors.white.withOpacity(.18),
              strokeCap: StrokeCap.round,
            ),
          ),
          Text('$progress%', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.13), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(.16))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          SizedBox(height: 8),
          Text(value, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, height: 1)),
          SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Color(0xE8FFFFFF), fontWeight: FontWeight.w800, fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _TimelineControls extends StatelessWidget {
  const _TimelineControls({
    required this.query,
    required this.selectedProjectId,
    required this.projects,
    required this.filter,
    required this.stats,
    required this.onQueryChanged,
    required this.onProjectChanged,
    required this.onFilterChanged,
  });

  final String query;
  final String selectedProjectId;
  final List<_ProjectOption> projects;
  final _TimelineFilter filter;
  final _TimelineStats stats;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onProjectChanged;
  final ValueChanged<_TimelineFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return _AnimatedIn(
      index: 1,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(color: _TimelinePalette.surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: _TimelinePalette.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 22, offset: const Offset(0, 10))]),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: _TimelinePalette.accent.withOpacity(.10), borderRadius: BorderRadius.circular(17)),
                  child: Icon(Icons.search_rounded, color: _TimelinePalette.accent, size: 22),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: query)..selection = TextSelection.collapsed(offset: query.length),
                    textInputAction: TextInputAction.search,
                    onChanged: onQueryChanged,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'Search task, project, assignee...',
                      hintStyle: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w700),
                    ),
                    style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(color: _TimelinePalette.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: _TimelinePalette.border)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: projects.any((p) => p.id == selectedProjectId) ? selectedProjectId : 'all',
                      isExpanded: true,
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: _TimelinePalette.accent),
                      items: projects
                          .map((project) => DropdownMenuItem<String>(
                                value: project.id,
                                child: Text(project.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w800, fontSize: 12.5)),
                              ))
                          .toList(),
                      onChanged: onProjectChanged,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              _QuickCountPill(label: 'Done', value: stats.done, color: _TimelinePalette.success),
            ],
          ),
          SizedBox(height: 10),
          SizedBox(
            height: 43,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _TimelineFilter.values.length,
              separatorBuilder: (_, __) => SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _TimelineFilter.values[index];
                return _FilterChipButton(
                  filter: item,
                  selected: filter == item,
                  count: switch (item) {
                    _TimelineFilter.all => stats.allTotal,
                    _TimelineFilter.open => stats.open,
                    _TimelineFilter.overdue => stats.overdue,
                    _TimelineFilter.done => stats.done,
                  },
                  onTap: () => onFilterChanged(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCountPill extends StatelessWidget {
  const _QuickCountPill({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(22), border: Border.all(color: color.withOpacity(.16))),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: color, size: 18),
          SizedBox(width: 7),
          Text('$value $label', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({required this.filter, required this.selected, required this.count, required this.onTap});

  final _TimelineFilter filter;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = filter == _TimelineFilter.overdue ? _TimelinePalette.danger : filter == _TimelineFilter.done ? _TimelinePalette.success : _TimelinePalette.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? color : _TimelinePalette.border),
            boxShadow: selected ? [BoxShadow(color: color.withOpacity(.16), blurRadius: 16, offset: const Offset(0, 7))] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(filter.icon, size: 16, color: selected ? Colors.white : color),
              SizedBox(width: 6),
              Text(filter.label, style: TextStyle(color: selected ? Colors.white : _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 12)),
              SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: selected ? Colors.white.withOpacity(.20) : color.withOpacity(.08), borderRadius: BorderRadius.circular(999)),
                child: Text('$count', style: TextStyle(color: selected ? Colors.white : color, fontWeight: FontWeight.w900, fontSize: 10)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExecutionPulseCard extends StatelessWidget {
  const _ExecutionPulseCard({required this.items, required this.stats, required this.window, this.selectedItem});

  final List<_TimelineItem> items;
  final _TimelineStats stats;
  final _TimelineWindow window;
  final _TimelineItem? selectedItem;

  @override
  Widget build(BuildContext context) {
    return _TimelineCardShell(
      index: 2,
      title: 'Execution pulse',
      subtitle: selectedItem == null ? '${window.rangeLabel} • ${items.length} task${items.length == 1 ? '' : 's'}' : 'Watching ${selectedItem!.title}',
      icon: Icons.auto_graph_rounded,
      trailing: _RiskPill(stats: stats),
      child: Column(
        children: [
          RepaintBoundary(
            child: SizedBox(
              height: 178,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) => TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 720),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => CustomPaint(
                    painter: _ExecutionPulsePainter(items: items, stats: stats, window: window, animation: value),
                    size: Size(constraints.maxWidth, 178),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _MiniKpi(label: 'Progress', value: '${stats.progress}%', color: _TimelinePalette.accent, icon: Icons.trending_up_rounded)),
              SizedBox(width: 10),
              Expanded(child: _MiniKpi(label: 'Overdue', value: '${stats.overdue}', color: _TimelinePalette.danger, icon: Icons.warning_rounded)),
              SizedBox(width: 10),
              Expanded(child: _MiniKpi(label: 'Today', value: '${stats.dueToday}', color: _TimelinePalette.blue, icon: Icons.today_rounded)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiskPill extends StatelessWidget {
  const _RiskPill({required this.stats});
  final _TimelineStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: stats.riskColor.withOpacity(.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: stats.riskColor.withOpacity(.18))),
      child: Text(stats.riskLabel, style: TextStyle(color: stats.riskColor, fontWeight: FontWeight.w900, fontSize: 11)),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  const _MiniKpi({required this.label, required this.value, required this.color, required this.icon});

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(.075), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(.14))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          SizedBox(height: 9),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18, height: 1)),
          SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w800, fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _GanttCommandCard extends StatelessWidget {
  const _GanttCommandCard({
    required this.items,
    required this.window,
    required this.onTaskSelected,
    required this.onTaskOpened,
    required this.onViewFullTimeline,
    required this.scale,
    required this.onScaleChanged,
    required this.onWindowShift,
    required this.onCalendarTap,
    this.selectedTaskId,
  });

  final List<_TimelineItem> items;
  final _TimelineWindow window;
  final String? selectedTaskId;
  final _TimelineMapScale scale;
  final ValueChanged<_TimelineItem> onTaskSelected;
  final ValueChanged<_TimelineItem> onTaskOpened;
  final VoidCallback onViewFullTimeline;
  final ValueChanged<_TimelineMapScale> onScaleChanged;
  final ValueChanged<int> onWindowShift;
  final VoidCallback onCalendarTap;

  @override
  Widget build(BuildContext context) {
    return _TimelineCardShell(
      index: 3,
      title: 'Live Gantt map',
      subtitle: 'Tap a row to reveal task details',
      icon: Icons.view_timeline_rounded,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: _TimelinePalette.accentDark, borderRadius: BorderRadius.circular(999)),
        child: Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final compact = availableWidth < 430;
          final leftPane = _responsiveGanttLeftPane(availableWidth);
          final rowHeight = _responsiveGanttRowHeight(availableWidth);
          final visibleItems = items.where((item) => _timelineItemIntersectsWindow(item, window)).toList();
          final visibleRows = math.min(5, math.max(visibleItems.length, 1));
          final rowsHeight = visibleRows * rowHeight;
          final hasInnerScroll = visibleItems.length > 5;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GanttScaleToolbar(
                scale: scale,
                window: window,
                compact: compact,
                onScaleChanged: onScaleChanged,
                onWindowShift: onWindowShift,
                onCalendarTap: onCalendarTap,
              ),
              SizedBox(height: 8),
              _GanttDateHeader(window: window, leftPane: leftPane, compact: compact),
              SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  height: rowsHeight,
                  color: _TimelinePalette.surfaceAlt.withOpacity(.32),
                  child: _GanttRowsViewport(
                    items: visibleItems,
                    window: window,
                    leftPane: leftPane,
                    rowHeight: rowHeight,
                    selectedTaskId: selectedTaskId,
                    scrollable: hasInnerScroll,
                    compact: compact,
                    onTaskSelected: onTaskSelected,
                    onTaskOpened: onTaskOpened,
                  ),
                ),
              ),
              if (hasInnerScroll) ...[
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.swipe_vertical_rounded, color: _TimelinePalette.accent, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '5 rows visible • scroll for ${visibleItems.length - 5} more.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w800, fontSize: 10.8),
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: 10),
              Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onViewFullTimeline();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('View full timeline', style: TextStyle(color: _TimelinePalette.accentDark, fontWeight: FontWeight.w900, fontSize: 12.4)),
                          SizedBox(width: 7),
                          Icon(Icons.arrow_forward_rounded, color: _TimelinePalette.accentDark, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

double _responsiveGanttLeftPane(double availableWidth) {
  if (availableWidth < 320) return 68;
  if (availableWidth < 350) return 74;
  if (availableWidth < 380) return 82;
  if (availableWidth < 430) return 92;
  if (availableWidth < 520) return 108;
  return 124;
}

double _responsiveGanttRowHeight(double availableWidth) {
  if (availableWidth < 320) return 56;
  if (availableWidth < 380) return 54;
  if (availableWidth < 430) return 52;
  return 50;
}

class _GanttScaleToolbar extends StatelessWidget {
  const _GanttScaleToolbar({required this.scale, required this.window, required this.compact, required this.onScaleChanged, required this.onWindowShift, required this.onCalendarTap});

  final _TimelineMapScale scale;
  final _TimelineWindow window;
  final bool compact;
  final ValueChanged<_TimelineMapScale> onScaleChanged;
  final ValueChanged<int> onWindowShift;
  final VoidCallback onCalendarTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: compact ? 36 : 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _TimelinePalette.surfaceAlt.withOpacity(.75),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _TimelinePalette.border.withOpacity(.80)),
            ),
            child: Row(
              children: [
                for (final item in _TimelineMapScale.values)
                  Expanded(
                    child: _GanttScaleButton(
                      label: item.label,
                      selected: item == scale,
                      compact: compact,
                      onTap: () => onScaleChanged(item),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(width: 8),
        _GanttStepButton(icon: Icons.chevron_left_rounded, compact: compact, onTap: () => onWindowShift(-1)),
        SizedBox(width: 6),
        _GanttStepButton(icon: Icons.calendar_month_rounded, compact: compact, onTap: onCalendarTap),
        SizedBox(width: 6),
        _GanttStepButton(icon: Icons.chevron_right_rounded, compact: compact, onTap: () => onWindowShift(1)),
      ],
    );
  }
}

class _GanttScaleButton extends StatelessWidget {
  const _GanttScaleButton({required this.label, required this.selected, required this.compact, required this.onTap});

  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _TimelinePalette.accentDark : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected ? [BoxShadow(color: _TimelinePalette.accentDark.withOpacity(.14), blurRadius: 12, offset: const Offset(0, 5))] : null,
          ),
          child: Text(label, style: TextStyle(color: selected ? Colors.white : _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: compact ? 11.0 : 11.6)),
        ),
      ),
    );
  }
}

class _GanttStepButton extends StatelessWidget {
  const _GanttStepButton({required this.icon, required this.compact, required this.onTap});

  final IconData icon;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _TimelinePalette.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: compact ? 34 : 38,
          height: compact ? 34 : 38,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: _TimelinePalette.border)),
          child: Icon(icon, color: _TimelinePalette.accentDark, size: compact ? 17 : 18),
        ),
      ),
    );
  }
}

class _GanttDateHeader extends StatelessWidget {
  const _GanttDateHeader({required this.window, required this.leftPane, required this.compact});

  final _TimelineWindow window;
  final double leftPane;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ticks = _ganttHeaderTicks(window, compact: compact);
    final calendarWeek = window.spanDays <= 7;
    return SizedBox(
      height: compact ? 38 : 46,
      child: Row(
        children: [
          SizedBox(
            width: leftPane,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Task',
                    style: TextStyle(
                      color: _TimelinePalette.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 10.0 : 11.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: calendarWeek
                ? Row(
                    children: [
                      for (final tick in ticks)
                        Expanded(
                          child: _GanttDateTick(
                            date: tick,
                            compact: compact,
                            calendarWeek: calendarWeek,
                            active: _sameDate(tick, DateTime.now()),
                          ),
                        ),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final tickWidth = compact ? 32.0 : 46.0;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final tick in ticks)
                            Positioned(
                              left: (constraints.maxWidth * window.ratioFor(tick) - tickWidth / 2)
                                  .clamp(0.0, math.max(0.0, constraints.maxWidth - tickWidth))
                                  .toDouble(),
                              top: 0,
                              width: tickWidth,
                              bottom: 0,
                              child: _GanttDateTick(
                                date: tick,
                                compact: compact,
                                calendarWeek: calendarWeek,
                                active: _sameDate(tick, DateTime.now()),
                              ),
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

class _GanttDateTick extends StatelessWidget {
  const _GanttDateTick({required this.date, required this.compact, required this.calendarWeek, required this.active});

  final DateTime date;
  final bool compact;
  final bool calendarWeek;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final dayText = '${date.day}';
    final weekText = _weekdayShort(date);
    final activeDiameter = compact ? 24.0 : 30.0;
    final normalStyle = TextStyle(
      color: _TimelinePalette.muted,
      fontWeight: FontWeight.w900,
      fontSize: compact ? 8.8 : 9.4,
      height: 1.05,
    );

    if (active) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!compact && calendarWeek) ...[
            Text(
              weekText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _TimelinePalette.muted,
                fontWeight: FontWeight.w900,
                fontSize: 8.4,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Container(
            width: activeDiameter,
            height: activeDiameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _TimelinePalette.surfaceAlt,
              shape: BoxShape.circle,
              border: Border.all(color: _TimelinePalette.border.withOpacity(.92), width: 1),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(.055), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Text(
              dayText,
              style: TextStyle(
                color: _TimelinePalette.ink,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 9.2 : 10.0,
                height: 1,
              ),
            ),
          ),
        ],
      );
    }

    if (calendarWeek && !compact) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(weekText, maxLines: 1, overflow: TextOverflow.ellipsis, style: normalStyle.copyWith(fontSize: 8.4)),
          const SizedBox(height: 3),
          Text(dayText, maxLines: 1, overflow: TextOverflow.ellipsis, style: normalStyle.copyWith(color: _TimelinePalette.ink)),
        ],
      );
    }

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          calendarWeek ? dayText : (compact ? dayText : DateText.compact(date).replaceAll(' ', '\n')),
          textAlign: TextAlign.center,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: normalStyle,
        ),
      ),
    );
  }
}

class _GanttRowsViewport extends StatelessWidget {
  const _GanttRowsViewport({
    required this.items,
    required this.window,
    required this.leftPane,
    required this.rowHeight,
    required this.selectedTaskId,
    required this.scrollable,
    required this.compact,
    required this.onTaskSelected,
    required this.onTaskOpened,
  });

  final List<_TimelineItem> items;
  final _TimelineWindow window;
  final double leftPane;
  final double rowHeight;
  final String? selectedTaskId;
  final bool scrollable;
  final bool compact;
  final ValueChanged<_TimelineItem> onTaskSelected;
  final ValueChanged<_TimelineItem> onTaskOpened;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text('No tasks in this timeline', style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w800, fontSize: 12)),
      );
    }
    return ListView.builder(
      primary: false,
      padding: EdgeInsets.zero,
      physics: scrollable ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
      itemExtent: rowHeight,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _GanttTaskRow(
          item: item,
          window: window,
          leftPane: leftPane,
          rowHeight: rowHeight,
          selected: selectedTaskId == item.id,
          compact: compact,
          onTap: () {
            HapticFeedback.selectionClick();
            onTaskSelected(item);
          },
          onDoubleTap: () {
            HapticFeedback.mediumImpact();
            onTaskOpened(item);
          },
        );
      },
    );
  }
}

class _GanttTaskRow extends StatelessWidget {
  const _GanttTaskRow({
    required this.item,
    required this.window,
    required this.leftPane,
    required this.rowHeight,
    required this.selected,
    required this.compact,
    required this.onTap,
    required this.onDoubleTap,
  });

  final _TimelineItem item;
  final _TimelineWindow window;
  final double leftPane;
  final double rowHeight;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final range = '${DateText.compact(item.startDate)} – ${DateText.compact(item.dueDate)}';
    final selectedColor = item.overdue ? _TimelinePalette.danger : _TimelinePalette.accent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onDoubleTap: onDoubleTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Row(
              children: [
                SizedBox(
                  width: leftPane,
                  child: Padding(
                    padding: EdgeInsets.only(left: compact ? 1 : 4, right: compact ? 6 : 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? Colors.transparent : _TimelinePalette.ink,
                            fontWeight: FontWeight.w900,
                            fontSize: compact ? (leftPane < 78 ? 8.6 : 9.4) : 11.2,
                            height: 1.05,
                          ),
                        ),
                        SizedBox(height: compact ? 2 : 3),
                        Text(
                          DateText.compact(item.dueDate),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? Colors.transparent : _TimelinePalette.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: compact ? (leftPane < 78 ? 7.2 : 8.0) : 9.0,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: _GanttChartRow(item: item, window: window, selected: selected, compact: compact)),
              ],
            ),
          ),
          if (selected)
            Positioned(
              left: 0,
              right: 0,
              top: compact ? 5 : 6,
              height: compact ? 36 : 38,
              child: Container(
                padding: EdgeInsets.only(left: compact ? 12 : 15, right: compact ? 7 : 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      selectedColor.withOpacity(.94),
                      Color.lerp(selectedColor, _TimelinePalette.accentDark, .34) ?? selectedColor,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(.76), width: 1.4),
                  boxShadow: [BoxShadow(color: selectedColor.withOpacity(.26), blurRadius: 18, offset: const Offset(0, 8))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: compact ? 7 : 8,
                      child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: compact ? 11.0 : 12.4)),
                    ),
                    if (!compact) ...[
                      SizedBox(width: 6),
                      Text(range, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(.82), fontWeight: FontWeight.w800, fontSize: 11.2)),
                    ],
                    SizedBox(width: 8),
                    Text('${item.progress}%', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: compact ? 10.2 : 12.0)),
                    SizedBox(width: 6),
                    Container(
                      width: compact ? 28 : 32,
                      height: compact ? 28 : 32,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: selectedColor.withOpacity(.42), width: 1.2)),
                      child: Icon(item.completed ? Icons.check_rounded : Icons.arrow_forward_rounded, color: selectedColor, size: compact ? 16 : 19),
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

class _GanttChartRow extends StatelessWidget {
  const _GanttChartRow({required this.item, required this.window, required this.selected, required this.compact});

  final _TimelineItem item;
  final _TimelineWindow window;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ticks = _ganttTicks(window, compact: compact);
    return LayoutBuilder(
      builder: (context, constraints) {
        final start = constraints.maxWidth * window.ratioFor(item.startDate);
        final end = constraints.maxWidth * window.ratioFor(item.dueDate);
        final barWidth = math.max(compact ? 42.0 : 52.0, end - start).clamp(32.0, constraints.maxWidth - start).toDouble();
        final animatedColor = item.overdue ? _TimelinePalette.danger : _TimelinePalette.accent;
        final todayX = constraints.maxWidth * window.ratioFor(DateTime.now());
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (final tick in ticks)
              Positioned(
                left: constraints.maxWidth * window.ratioFor(tick),
                top: 0,
                bottom: 0,
                child: Container(width: 1, color: _TimelinePalette.border.withOpacity(.52)),
              ),
            Positioned(
              left: todayX,
              top: 0,
              bottom: 0,
              child: Container(width: 1.2, color: _TimelinePalette.danger.withOpacity(.76)),
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 1, color: _TimelinePalette.border.withOpacity(.46))),
            if (!selected)
              Positioned(
                left: start,
                top: compact ? 12 : 13,
                width: barWidth,
                height: compact ? 12 : 14,
                child: Container(
                  decoration: BoxDecoration(
                    color: animatedColor,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BoxShadow(color: animatedColor.withOpacity(.18), blurRadius: 9, offset: const Offset(0, 3))],
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: compact ? 16 : 18,
                      height: compact ? 16 : 18,
                      decoration: BoxDecoration(color: animatedColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.3)),
                      child: Icon(item.completed ? Icons.check_rounded : Icons.circle, size: compact ? 9 : 10, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

List<DateTime> _ganttTicks(_TimelineWindow window, {required bool compact}) {
  if (window.spanDays <= 7) {
    return List.generate(window.spanDays + 1, (index) => _dateOnly(window.start).add(Duration(days: index)));
  }
  final count = compact ? 5 : 6;
  final ticks = <DateTime>{};
  for (var index = 0; index < count; index++) {
    final dayOffset = ((window.spanDays * index) / math.max(1, count - 1)).round();
    ticks.add(_dateOnly(window.start).add(Duration(days: dayOffset)));
  }
  final today = _dateOnly(DateTime.now());
  if (_dateInsideWindow(today, window)) ticks.add(today);
  return ticks.toList()..sort();
}

List<DateTime> _ganttHeaderTicks(_TimelineWindow window, {required bool compact}) {
  if (window.spanDays <= 7) {
    return List.generate(window.spanDays + 1, (index) => _dateOnly(window.start).add(Duration(days: index)));
  }
  return _ganttTicks(window, compact: compact);
}

bool _dateInsideWindow(DateTime date, _TimelineWindow window) {
  final d = _dateOnly(date);
  return !d.isBefore(_dateOnly(window.start)) && !d.isAfter(_dateOnly(window.end));
}

String _weekdayShort(DateTime date) {
  const days = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return days[(date.weekday - 1).clamp(0, 6)];
}

String _weekdayTickLabel(DateTime date, {required bool compact}) {
  const days = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final label = days[(date.weekday - 1).clamp(0, 6)];
  return compact ? '${date.day}' : '$label\n${date.day}';
}

class _StatusFlowCard extends StatelessWidget {
  const _StatusFlowCard({required this.stats});

  final _TimelineStats stats;

  @override
  Widget build(BuildContext context) {
    final lanes = <_FlowLane>[
      _FlowLane('Open', stats.open, _TimelinePalette.blue, Icons.bolt_rounded),
      _FlowLane('Overdue', stats.overdue, _TimelinePalette.danger, Icons.warning_amber_rounded),
      _FlowLane('Done', stats.done, _TimelinePalette.success, Icons.check_circle_rounded),
    ];
    return _TimelineCardShell(
      index: 4,
      title: 'Delivery lanes',
      subtitle: 'Live status distribution for selected tasks',
      icon: Icons.account_tree_rounded,
      child: Row(
        children: lanes.asMap().entries.map((entry) {
          final index = entry.key;
          final lane = entry.value;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: index == 0 ? 0 : 8),
              child: _FlowLaneCard(lane: lane, total: stats.total),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FlowLane {
  const _FlowLane(this.label, this.value, this.color, this.icon);
  final String label;
  final int value;
  final Color color;
  final IconData icon;
}

class _FlowLaneCard extends StatelessWidget {
  const _FlowLaneCard({required this.lane, required this.total});
  final _FlowLane lane;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : (lane.value / total).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: lane.color.withOpacity(.07), borderRadius: BorderRadius.circular(22), border: Border.all(color: lane.color.withOpacity(.14))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(lane.icon, color: lane.color, size: 20),
          SizedBox(height: 10),
          Text('${lane.value}', style: TextStyle(color: lane.color, fontWeight: FontWeight.w900, fontSize: 20, height: 1)),
          SizedBox(height: 4),
          Text(lane.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w800, fontSize: 10.5)),
          SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: ratio, minHeight: 6, color: lane.color, backgroundColor: lane.color.withOpacity(.12)),
          ),
        ],
      ),
    );
  }
}

class _WatchingTaskCard extends StatelessWidget {
  const _WatchingTaskCard({required this.item, required this.onOpen, required this.onClear});

  final _TimelineItem item;
  final VoidCallback onOpen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final days = item.daysLeft;
    final dueText = item.completed
        ? 'Completed flow'
        : days < 0
            ? '${days.abs()} day${days.abs() == 1 ? '' : 's'} overdue'
            : days == 0
                ? 'Due today'
                : '$days day${days == 1 ? '' : 's'} left';
    return _AnimatedIn(
      index: 2,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
        decoration: BoxDecoration(
          color: item.color.withOpacity(.09),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: item.color.withOpacity(.24)),
          boxShadow: [BoxShadow(color: item.color.withOpacity(.10), blurRadius: 24, offset: const Offset(0, 12))],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: item.color, borderRadius: BorderRadius.circular(19)),
              child: Icon(Icons.visibility_rounded, color: Colors.white, size: 22),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Watching now', style: TextStyle(color: item.color, fontWeight: FontWeight.w900, fontSize: 11.5)),
                  SizedBox(height: 3),
                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 14.5)),
                  SizedBox(height: 4),
                  Text('${item.projectName} • $dueText • ${item.progress}%', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w800, fontSize: 11.2)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Open details',
              onPressed: onOpen,
              icon: Icon(Icons.open_in_new_rounded, color: item.color),
            ),
            IconButton(
              tooltip: 'Stop watching',
              onPressed: onClear,
              icon: Icon(Icons.close_rounded, color: _TimelinePalette.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskTimelineTile extends StatelessWidget {
  const _TaskTimelineTile({required this.item, required this.index, required this.selected, required this.onTap, required this.onOpen});

  final _TimelineItem item;
  final int index;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return _AnimatedIn(
      index: 5 + math.min(index, 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          onLongPress: onOpen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: selected ? item.color.withOpacity(.045) : Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: selected ? item.color.withOpacity(.62) : item.overdue ? _TimelinePalette.danger.withOpacity(.24) : _TimelinePalette.border, width: selected ? 1.6 : 1),
              boxShadow: [BoxShadow(color: (selected ? item.color : Colors.black).withOpacity(selected ? .11 : .035), blurRadius: selected ? 24 : 18, offset: const Offset(0, 8))],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: item.color.withOpacity(.11), borderRadius: BorderRadius.circular(19), border: Border.all(color: item.color.withOpacity(.16))),
                  child: Icon(item.completed ? Icons.check_rounded : item.overdue ? Icons.priority_high_rounded : Icons.task_alt_rounded, color: item.color, size: 22),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 14.5)),
                      SizedBox(height: 4),
                      Text('${item.projectName} • ${item.assigneeLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w700, fontSize: 11.5)),
                      SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _MiniTag(label: item.statusLabel, color: item.color),
                          _MiniTag(label: 'Due ${DateText.compact(item.dueDate)}', color: item.overdue ? _TimelinePalette.danger : _TimelinePalette.muted),
                          if (item.commentsCount > 0) _MiniTag(label: '${item.commentsCount} comments', color: _TimelinePalette.blue),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${item.progress}%', style: TextStyle(color: item.color, fontWeight: FontWeight.w900, fontSize: 15)),
                    SizedBox(height: 7),
                    IconButton(
                      tooltip: 'Open task insight',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                      onPressed: onOpen,
                      icon: Icon(selected ? Icons.visibility_rounded : Icons.chevron_right_rounded, color: item.color.withOpacity(.86), size: 22),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(.08), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(.14))),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10.3)),
    );
  }
}

class _SelectedTaskRevealCard extends ConsumerWidget {
  const _SelectedTaskRevealCard({
    required this.item,
    required this.onComment,
    required this.onAttach,
    required this.onUpdate,
    required this.onToggleWorkTimer,
    required this.onOpen,
    required this.onClear,
  });

  final _TimelineItem item;
  final VoidCallback onComment;
  final VoidCallback onAttach;
  final VoidCallback onUpdate;
  final VoidCallback onToggleWorkTimer;
  final VoidCallback onOpen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider);
    final isUploading = workspace.isSaving && workspace.uploadingTaskId == item.id;

    final compact = MediaQuery.sizeOf(context).width < 380;
    final due = DateText.compact(item.dueDate);
    final window = '${DateText.compact(item.startDate)} – $due';
    return _AnimatedIn(
      index: 4,
      child: Container(
        padding: EdgeInsets.fromLTRB(compact ? 13 : 15, 14, compact ? 13 : 15, 14),
        decoration: BoxDecoration(
          color: _TimelinePalette.surface,
          borderRadius: BorderRadius.circular(_TimelinePalette.cardRadius),
          border: Border.all(color: item.color.withOpacity(.18)),
          boxShadow: [BoxShadow(color: item.color.withOpacity(.08), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: compact ? 42 : 48,
                  height: compact ? 42 : 48,
                  decoration: BoxDecoration(color: item.color.withOpacity(.10), borderRadius: BorderRadius.circular(compact ? 16 : 18), border: Border.all(color: item.color.withOpacity(.15))),
                  child: Icon(Icons.view_timeline_rounded, color: item.color, size: compact ? 20 : 22),
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: compact ? 15 : 16.5)),
                      SizedBox(height: 3),
                      Text('${item.projectName} • ${item.assigneeLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w700, fontSize: compact ? 10.6 : 11.4)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${item.progress}%', style: TextStyle(color: item.color, fontWeight: FontWeight.w900, fontSize: compact ? 17 : 20, height: 1)),
                        SizedBox(width: 7),
                        Container(width: compact ? 27 : 30, height: compact ? 27 : 30, decoration: BoxDecoration(color: item.color, shape: BoxShape.circle), child: Icon(item.completed ? Icons.check_rounded : Icons.trending_up_rounded, color: Colors.white, size: compact ? 16 : 18)),
                      ],
                    ),
                    SizedBox(height: 3),
                    Text(item.completed ? 'Complete' : item.statusLabel, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w800, fontSize: 10.5)),
                  ],
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: Icon(Icons.keyboard_arrow_up_rounded, color: _TimelinePalette.ink, size: 22),
                ),
              ],
            ),
            SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _MiniTag(label: item.statusLabel, color: item.color),
                _MiniTag(label: 'Due $due', color: item.overdue ? _TimelinePalette.danger : _TimelinePalette.muted),
                _MiniTag(label: item.priorityLabel, color: item.priorityColor),
                if (item.commentsCount > 0) _MiniTag(label: '${item.commentsCount} comments', color: _TimelinePalette.blue),
                if (item.attachmentsCount > 0) _MiniTag(label: '${item.attachmentsCount} files', color: _TimelinePalette.purple),
              ],
            ),
            SizedBox(height: 13),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: item.progress / 100, minHeight: compact ? 8 : 9, color: item.color, backgroundColor: item.color.withOpacity(.12)),
            ),
            SizedBox(height: 14),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: compact ? 96 : 128,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assignee', style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 12.2)),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            CircleAvatar(radius: compact ? 15 : 17, backgroundColor: item.color.withOpacity(.13), child: Icon(Icons.person_rounded, color: item.color, size: compact ? 16 : 18)),
                            SizedBox(width: 8),
                            Expanded(child: Text(item.assigneeLabel, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w800, fontSize: compact ? 10.6 : 11.2))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 18, thickness: 1, color: _TimelinePalette.border),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Summary', style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 12.2)),
                        SizedBox(height: 7),
                        Text(
                          '${item.title} is linked with ${item.projectName}. Timeline window: $window. Priority is ${item.priorityLabel}.',
                          maxLines: compact ? 4 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _TimelinePalette.ink.withOpacity(.82), fontWeight: FontWeight.w700, fontSize: compact ? 11.0 : 11.8, height: 1.28),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (item.assignedToCurrentUser) ...[
              SizedBox(height: 13),
              _WorkTimerCounterStrip(item: item, onToggle: onToggleWorkTimer),
              SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: _TimelinePalette.surfaceAlt.withOpacity(.52), borderRadius: BorderRadius.circular(18), border: Border.all(color: _TimelinePalette.border.withOpacity(.74))),
                child: Row(
                  children: [
                    Expanded(child: _CompactAction(icon: Icons.chat_bubble_outline_rounded, label: 'Comment', onTap: onComment)),
                    Expanded(
                      child: isUploading
                          ? const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                                ),
                              ),
                            )
                          : _CompactAction(
                              icon: Icons.attach_file_rounded,
                              label: 'Attach',
                              onTap: onAttach,
                            ),
                    ),
                    Expanded(child: _CompactAction(icon: Icons.edit_rounded, label: 'Update', onTap: onUpdate)),
                    Expanded(child: _CompactAction(icon: Icons.more_horiz_rounded, label: 'More', onTap: onOpen)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


String _formatWorkDuration(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
  return '${two(minutes)}:${two(seconds)}';
}

class _WorkTimerCounterStrip extends StatelessWidget {
  const _WorkTimerCounterStrip({required this.item, required this.onToggle});

  final _TimelineItem item;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: item.isWorkTimerRunning ? Stream<int>.periodic(const Duration(seconds: 1), (tick) => tick) : Stream<int>.empty(),
      builder: (context, snapshot) {
        final running = item.workTimerRunningForCurrentUser;
        final elapsed = item.activeWorkDuration;
        final liveHours = item.liveLoggedHours;
        final accent = running ? _TimelinePalette.success : _TimelinePalette.accent;
        final estimate = item.estimatedHours <= 0 ? 'No estimate' : '${item.estimatedHours}h estimate';
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: accent.withOpacity(.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withOpacity(.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: accent.withOpacity(.22), blurRadius: 14, offset: const Offset(0, 7))]),
                child: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 23),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(running ? 'Work counter running' : 'Work counter ready', style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 12.6)),
                    const SizedBox(height: 3),
                    Text('${_formatWorkDuration(elapsed)} • ${liveHours}h logged • $estimate', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w800, fontSize: 10.6)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onToggle,
                icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 17),
                label: Text(running ? 'Stop' : 'Start'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskStatusUpdateSheet extends StatelessWidget {
  const _TaskStatusUpdateSheet({required this.item});

  final _TimelineItem item;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: _TimelinePalette.surface,
          borderRadius: BorderRadius.circular(_TimelinePalette.cardRadius + 2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.16), blurRadius: 30, offset: const Offset(0, 14))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: _TimelinePalette.border, borderRadius: BorderRadius.circular(999)))),
            const SizedBox(height: 16),
            Text('Update task status', style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 4),
            Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 14),
            ...TaskStatus.values.map((status) {
              final selected = status == item.status;
              final color = status == TaskStatus.completed
                  ? _TimelinePalette.success
                  : status == TaskStatus.review || status == TaskStatus.testing
                      ? _TimelinePalette.warning
                      : status == TaskStatus.inProgress
                          ? _TimelinePalette.blue
                          : _TimelinePalette.accent;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selected ? color.withOpacity(.10) : _TimelinePalette.surfaceAlt.withOpacity(.42),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.of(context).pop(status),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: selected ? color.withOpacity(.45) : _TimelinePalette.border),
                      ),
                      child: Row(
                        children: [
                          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: color, size: 19),
                          const SizedBox(width: 10),
                          Expanded(child: Text(status.label, style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 13))),
                          if (selected) Text('Current', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _TimelinePalette.ink, size: 18),
            SizedBox(height: 3),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w800, fontSize: 10.2)),
          ],
        ),
      ),
    );
  }
}

class _FullTimelineSheet extends StatefulWidget {
  const _FullTimelineSheet({required this.items, required this.window, this.selectedTaskId});

  final List<_TimelineItem> items;
  final _TimelineWindow window;
  final String? selectedTaskId;

  @override
  State<_FullTimelineSheet> createState() => _FullTimelineSheetState();
}

class _FullTimelineSheetState extends State<_FullTimelineSheet> {
  late _TimelineMapScale _scale = widget.window.spanDays <= 7 ? _TimelineMapScale.week : _TimelineMapScale.month;
  late DateTime _focusDate = widget.window.start;
  late String? _selectedTaskId = widget.selectedTaskId;

  Future<void> _pickFocusDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOnly(_focusDate),
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: _scale == _TimelineMapScale.month ? 'Select month' : 'Select week date',
      cancelText: 'Cancel',
      confirmText: 'Apply',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: _TimelinePalette.accentDark,
            onPrimary: Colors.white,
            surface: _TimelinePalette.surface,
            onSurface: _TimelinePalette.ink,
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _focusDate = _dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _TimelinePalette.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, hostConstraints) {
            final hostWidth = hostConstraints.maxWidth;
            final hostHeight = hostConstraints.maxHeight;
            final constrainedPreviewHost = hostWidth >= 900;
            final routeWidth = constrainedPreviewHost ? math.min(430.0, hostWidth - 32) : hostWidth;
            final routeHeight = constrainedPreviewHost ? math.min(920.0, hostHeight - 24) : hostHeight;
            final compact = routeWidth < 430;
            final leftPane = _responsiveGanttLeftPane(routeWidth - 56);
            final rowHeight = _responsiveGanttRowHeight(routeWidth - 56);
            final window = _TimelineWindow.calendar(scale: _scale, focusDate: _focusDate);
            final visibleItems = widget.items.where((item) => _timelineItemIntersectsWindow(item, window)).toList();
            final selected = _selectedTimelineItem(widget.items, _selectedTaskId);

            return Center(
              child: SizedBox(
                width: routeWidth,
                height: routeHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _TimelinePalette.background,
                    borderRadius: BorderRadius.circular(constrainedPreviewHost ? 28 : 0),
                    boxShadow: constrainedPreviewHost
                        ? [BoxShadow(color: Colors.black.withOpacity(.13), blurRadius: 30, offset: const Offset(0, 14))]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(constrainedPreviewHost ? 28 : 0),
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(compact ? 14 : 18, 14, compact ? 14 : 18, 8),
                          child: Row(
                            children: [
                              _CircleButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Full Timeline', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.ink, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                                    SizedBox(height: 2),
                                    Text('${_scale.label} view • ${window.rangeLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.muted, fontSize: 12.2, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: _TimelinePalette.accentDark, borderRadius: BorderRadius.circular(999)), child: Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10))),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  _MiniTag(label: 'All ${widget.items.length}', color: _TimelinePalette.accent),
                                  SizedBox(width: 8),
                                  _MiniTag(label: 'Completed ${widget.items.where((item) => item.completed).length}', color: _TimelinePalette.success),
                                  SizedBox(width: 8),
                                  _MiniTag(label: 'Overdue ${widget.items.where((item) => item.overdue).length}', color: _TimelinePalette.danger),
                                ],
                              ),
                              SizedBox(height: 10),
                              _GanttScaleToolbar(
                                scale: _scale,
                                window: window,
                                compact: compact,
                                onScaleChanged: (value) => setState(() {
                                  _scale = value;
                                  _focusDate = DateTime.now();
                                }),
                                onWindowShift: (delta) => setState(() => _focusDate = delta == 0 ? DateTime.now() : _shiftTimelineFocus(_focusDate, _scale, delta)),
                                onCalendarTap: _pickFocusDate,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 10),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(compact ? 14 : 18, 0, compact ? 14 : 18, 14),
                            child: Container(
                              padding: EdgeInsets.all(compact ? 12 : 14),
                              decoration: BoxDecoration(color: _TimelinePalette.surface, borderRadius: BorderRadius.circular(_TimelinePalette.cardRadius), border: Border.all(color: _TimelinePalette.border)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(width: 36, height: 36, decoration: BoxDecoration(color: _TimelinePalette.accent.withOpacity(.10), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.view_timeline_rounded, color: _TimelinePalette.accent, size: 19)),
                                      SizedBox(width: 10),
                                      Expanded(child: Text('Live Gantt Map', style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 16))),
                                      Text(window.rangeLabel, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w800, fontSize: 11)),
                                    ],
                                  ),
                                  SizedBox(height: 12),
                                  _GanttDateHeader(window: window, leftPane: leftPane, compact: compact),
                                  SizedBox(height: 6),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: Container(
                                        color: _TimelinePalette.surfaceAlt.withOpacity(.32),
                                        child: _GanttRowsViewport(
                                          items: visibleItems,
                                          window: window,
                                          leftPane: leftPane,
                                          rowHeight: rowHeight,
                                          selectedTaskId: _selectedTaskId,
                                          scrollable: true,
                                          compact: compact,
                                          onTaskSelected: (item) => setState(() => _selectedTaskId = item.id),
                                          onTaskOpened: (item) => setState(() => _selectedTaskId = item.id),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (selected != null) ...[
                                    SizedBox(height: 12),
                                    Text('Selected: ${selected.title} • ${DateText.compact(selected.startDate)} – ${DateText.compact(selected.dueDate)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected.color, fontWeight: FontWeight.w900, fontSize: 12)),
                                  ],
                                ],
                              ),
                            ),
                          ),
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
}

class _TaskInsightSheet extends StatelessWidget {
  const _TaskInsightSheet({required this.item});
  final _TimelineItem item;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(color: _TimelinePalette.surface, borderRadius: BorderRadius.circular(_TimelinePalette.cardRadius + 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.18), blurRadius: 32, offset: const Offset(0, 16))]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: _TimelinePalette.border, borderRadius: BorderRadius.circular(999)))),
            SizedBox(height: 18),
            Row(
              children: [
                Container(width: 52, height: 52, decoration: BoxDecoration(color: item.color.withOpacity(.12), borderRadius: BorderRadius.circular(20)), child: Icon(Icons.task_alt_rounded, color: item.color, size: 25)),
                SizedBox(width: 13),
                Expanded(child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 17))),
              ],
            ),
            SizedBox(height: 16),
            _InsightLine(icon: Icons.folder_rounded, label: 'Project', value: item.projectName),
            _InsightLine(icon: Icons.person_rounded, label: 'Assignee', value: item.assigneeLabel),
            _InsightLine(icon: Icons.calendar_month_rounded, label: 'Window', value: '${DateText.compact(item.startDate)} → ${DateText.compact(item.dueDate)}'),
            _InsightLine(icon: Icons.bolt_rounded, label: 'Status', value: '${item.statusLabel} • ${item.progress}%'),
            _InsightLine(icon: Icons.flag_rounded, label: 'Priority', value: item.priorityLabel),
            if (item.estimatedHours > 0 || item.liveLoggedHours > 0) _InsightLine(icon: Icons.timer_rounded, label: 'Effort', value: '${item.liveLoggedHours}h / ${item.estimatedHours}h'),
            if (item.isWorkTimerRunning) _InsightLine(icon: Icons.play_circle_fill_rounded, label: 'Counter', value: 'Running for ${_formatWorkDuration(item.activeWorkDuration)}'),
            SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: item.progress / 100, minHeight: 9, color: item.color, backgroundColor: item.color.withOpacity(.12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightLine extends StatelessWidget {
  const _InsightLine({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: _TimelinePalette.accent, size: 18),
          SizedBox(width: 10),
          SizedBox(width: 72, child: Text(label, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w800, fontSize: 12))),
          Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 12.4))),
        ],
      ),
    );
  }
}

class _TimelineCardShell extends StatelessWidget {
  const _TimelineCardShell({required this.index, required this.title, required this.subtitle, required this.icon, required this.child, this.trailing});

  final int index;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _AnimatedIn(
      index: index,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 17),
        decoration: BoxDecoration(color: _TimelinePalette.surface, borderRadius: BorderRadius.circular(_TimelinePalette.cardRadius), border: Border.all(color: _TimelinePalette.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 25, offset: const Offset(0, 12))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 34, height: 34, decoration: BoxDecoration(color: _TimelinePalette.accent.withOpacity(.10), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: _TimelinePalette.accent, size: 19)),
                SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 16)),
                      SizedBox(height: 2),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w700, fontSize: 11.5)),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _AnimatedIn extends StatelessWidget {
  const _AnimatedIn({required this.child, required this.index});
  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + index * 55),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, 18 * (1 - value)), child: child),
      ),
      child: child,
    );
  }
}

class _EmptyTimelineState extends StatelessWidget {
  const _EmptyTimelineState({required this.data});

  final _TimelineDataSet data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(color: _TimelinePalette.surface, borderRadius: BorderRadius.circular(_TimelinePalette.cardRadius + 2), border: Border.all(color: _TimelinePalette.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 58, height: 58, decoration: BoxDecoration(color: _TimelinePalette.accent.withOpacity(.10), borderRadius: BorderRadius.circular(23)), child: Icon(Icons.timeline_rounded, color: _TimelinePalette.accent, size: 30)),
          SizedBox(height: 16),
          Text('No real task timeline data found', style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 18)),
          SizedBox(height: 8),
          Text('This screen does not generate demo bars. Add tasks with assignedToIds/projectId/teamId and dueDate, or check role visibility rules.', style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w700, height: 1.38)),
          SizedBox(height: 16),
          _MiniTag(label: data.source, color: _TimelinePalette.accent),
        ],
      ),
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  const _FilteredEmptyState({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: _TimelinePalette.surface, borderRadius: BorderRadius.circular(_TimelinePalette.cardRadius + 2), border: Border.all(color: _TimelinePalette.border)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.filter_alt_off_rounded, color: _TimelinePalette.accent, size: 38),
          SizedBox(height: 12),
          Text('No tasks match this view', textAlign: TextAlign.center, style: TextStyle(color: _TimelinePalette.ink, fontWeight: FontWeight.w900, fontSize: 17)),
          SizedBox(height: 8),
          Text('Clear search, project or status filters to see the live task timeline again.', textAlign: TextAlign.center, style: TextStyle(color: _TimelinePalette.muted, fontWeight: FontWeight.w700, height: 1.35)),
          SizedBox(height: 16),
          FilledButton.icon(onPressed: onClear, icon: Icon(Icons.refresh_rounded), label: Text('Reset filters')),
        ],
      ),
    );
  }
}

class _ExecutionPulsePainter extends CustomPainter {
  const _ExecutionPulsePainter({required this.items, required this.stats, required this.window, required this.animation});

  final List<_TimelineItem> items;
  final _TimelineStats stats;
  final _TimelineWindow window;
  final double animation;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = Rect.fromLTWH(6, 8, size.width - 12, size.height - 34);
    final gridPaint = Paint()..color = _TimelinePalette.border.withOpacity(.55)..strokeWidth = 1;
    final ticks = window.ticks;
    final tp = TextPainter(textDirection: TextDirection.ltr, textAlign: TextAlign.center);

    for (var i = 0; i < ticks.length; i++) {
      final x = chart.left + chart.width * (i / (ticks.length - 1));
      canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), gridPaint);
      tp.text = TextSpan(text: '${ticks[i].day}', style: TextStyle(color: _TimelinePalette.muted, fontSize: 10, fontWeight: FontWeight.w800));
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chart.bottom + 13));
    }

    final todayX = chart.left + chart.width * window.ratioFor(DateTime.now());
    canvas.drawLine(Offset(todayX, chart.top - 2), Offset(todayX, chart.bottom), Paint()..color = _TimelinePalette.danger.withOpacity(.35)..strokeWidth = 1.6);

    final points = <Offset>[];
    for (var i = 0; i < ticks.length; i++) {
      final date = ticks[i];
      final dayTasks = items.where((item) => _sameDate(item.dueDate, date)).toList();
      final value = dayTasks.isEmpty ? stats.progress : (dayTasks.fold<int>(0, (sum, item) => sum + item.progress) / dayTasks.length).round();
      final x = chart.left + chart.width * (i / (ticks.length - 1));
      final y = chart.bottom - chart.height * (value / 100) * animation;
      points.add(Offset(x, y));
      final color = dayTasks.any((item) => item.overdue) ? _TimelinePalette.danger : _TimelinePalette.accent;
      final barHeight = (chart.bottom - y).clamp(10, chart.height).toDouble();
      final barRect = RRect.fromRectAndRadius(Rect.fromLTWH(x - 12, chart.bottom - barHeight, 24, barHeight), const Radius.circular(12));
      canvas.drawRRect(barRect, Paint()..color = color.withOpacity(.16));
      if (dayTasks.isNotEmpty) {
        _drawPill(canvas, Offset(x - 20, y - 28), '${value.round()}%', color, Colors.white, width: 40, height: 21, fontSize: 9.5);
      }
    }

    if (points.length >= 2) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, Paint()..color = _TimelinePalette.accent..strokeWidth = 3..strokeCap = StrokeCap.round..style = PaintingStyle.stroke);
      for (final point in points) {
        canvas.drawCircle(point, 4.2, Paint()..color = Colors.white);
        canvas.drawCircle(point, 3, Paint()..color = _TimelinePalette.accent);
      }
    }

    final progressX = todayX.clamp(chart.left + 25, chart.right - 55).toDouble();
    final progressY = chart.bottom - chart.height * (stats.progress / 100) * animation;
    _drawPill(canvas, Offset(progressX - 28, math.max(chart.top, progressY - 42)), '${stats.progress}%', _TimelinePalette.ink, Colors.white, width: 56, height: 30, fontSize: 12);
  }

  void _drawPill(Canvas canvas, Offset offset, String text, Color bg, Color fg, {required double width, required double height, required double fontSize}) {
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(offset.dx, offset.dy, width, height), Radius.circular(height / 2));
    canvas.drawRRect(rect, Paint()..color = bg);
    final tp = TextPainter(text: TextSpan(text: text, style: TextStyle(color: fg, fontSize: fontSize, fontWeight: FontWeight.w900)), textDirection: TextDirection.ltr)..layout(maxWidth: width);
    tp.paint(canvas, Offset(offset.dx + (width - tp.width) / 2, offset.dy + (height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant _ExecutionPulsePainter oldDelegate) => oldDelegate.items != items || oldDelegate.stats != stats || oldDelegate.window != window || oldDelegate.animation != animation;
}

class _AdvancedGanttPainter extends CustomPainter {
  const _AdvancedGanttPainter({required this.items, required this.window, required this.animation, this.selectedTaskId});

  final List<_TimelineItem> items;
  final _TimelineWindow window;
  final double animation;
  final String? selectedTaskId;

  @override
  void paint(Canvas canvas, Size size) {
    final leftPane = size.width < 340 ? 104.0 : 124.0;
    final chartLeft = leftPane;
    final chartRight = size.width - 10;
    final top = 18.0;
    final bottom = size.height - 34;
    final chartWidth = math.max(80.0, chartRight - chartLeft);
    final rowHeight = 48.0;
    final ticks = window.ticks;
    final gridPaint = Paint()..color = _TimelinePalette.border.withOpacity(.62)..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);

    final todayRatio = window.ratioFor(DateTime.now());
    final todayX = chartLeft + chartWidth * todayRatio;

    for (var i = 0; i < ticks.length; i++) {
      final x = chartLeft + chartWidth * (i / (ticks.length - 1));
      canvas.drawLine(Offset(x, top), Offset(x, bottom + 12), gridPaint);
      tp.text = TextSpan(text: '${ticks[i].day}', style: TextStyle(color: _sameDate(ticks[i], DateTime.now()) ? _TimelinePalette.ink : _TimelinePalette.muted, fontSize: 10, fontWeight: FontWeight.w900));
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, bottom + 18));
    }

    _paintHatch(canvas, Rect.fromLTRB(todayX, top + 10, chartRight, bottom), _TimelinePalette.border.withOpacity(.30));
    canvas.drawLine(Offset(todayX, top - 7), Offset(todayX, bottom + 12), Paint()..color = _TimelinePalette.danger.withOpacity(.78)..strokeWidth = 2);
    canvas.drawCircle(Offset(todayX, top - 8), 5, Paint()..color = _TimelinePalette.danger);

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final y = top + i * rowHeight + 8;
      if (y + 34 > bottom) break;
      final start = chartLeft + chartWidth * window.ratioFor(item.startDate);
      final end = chartLeft + chartWidth * window.ratioFor(item.dueDate);
      final fullWidth = math.max(64.0, end - start).clamp(64.0, chartRight - start).toDouble();
      final animatedWidth = fullWidth * animation;
      final barRect = RRect.fromRectAndRadius(Rect.fromLTWH(start, y, animatedWidth, 30), const Radius.circular(15));
      final isSelected = selectedTaskId == item.id;

      if (isSelected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(-4, y - 5, size.width + 8, 40), const Radius.circular(18)),
          Paint()..color = item.color.withOpacity(.055),
        );
      }

      tp.text = TextSpan(text: item.title, style: TextStyle(color: isSelected ? item.color : _TimelinePalette.ink, fontSize: 11.2, fontWeight: FontWeight.w900));
      tp.layout(maxWidth: leftPane - 34);
      tp.paint(canvas, Offset(0, y - 1));
      tp.text = TextSpan(text: DateText.compact(item.dueDate), style: TextStyle(color: _TimelinePalette.muted, fontSize: 9.5, fontWeight: FontWeight.w700));
      tp.layout(maxWidth: leftPane - 34);
      tp.paint(canvas, Offset(0, y + 16));
      canvas.drawCircle(Offset(leftPane - 17, y + 15), 8, Paint()..color = item.color.withOpacity(.13));
      canvas.drawCircle(Offset(leftPane - 17, y + 15), 4, Paint()..color = item.color);

      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(start, y, fullWidth, 30), const Radius.circular(15)), Paint()..color = item.color.withOpacity(.09));
      canvas.drawRRect(barRect, Paint()..color = item.color);
      if (isSelected && animatedWidth > 2) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(start - 3, y - 3, animatedWidth + 6, 36), const Radius.circular(18)),
          Paint()
            ..color = item.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
      }
      final progressWidth = math.max(0.0, animatedWidth * (item.progress / 100));
      if (progressWidth > 8) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(start, y, progressWidth, 30), const Radius.circular(15)), Paint()..color = Colors.white.withOpacity(.14));
      }
      final label = item.statusLabel.length > 12 ? '${item.statusLabel.substring(0, 11)}…' : item.statusLabel;
      tp.text = const TextSpan(text: '', style: TextStyle());
      tp.text = TextSpan(text: label, style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900));
      tp.layout(maxWidth: math.max(24, animatedWidth - 18));
      if (animatedWidth > 42) tp.paint(canvas, Offset(start + 10, y + (30 - tp.height) / 2));
    }
  }

  void _paintHatch(Canvas canvas, Rect rect, Color color) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(22)));
    final paint = Paint()..color = color..strokeWidth = 1.4..strokeCap = StrokeCap.round;
    for (var x = rect.left - rect.height; x < rect.right + rect.height; x += 9) {
      canvas.drawLine(Offset(x, rect.bottom), Offset(x + rect.height, rect.top), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AdvancedGanttPainter oldDelegate) => oldDelegate.items != items || oldDelegate.window != window || oldDelegate.animation != animation || oldDelegate.selectedTaskId != selectedTaskId;
}