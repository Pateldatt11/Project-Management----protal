import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/timeline/timeline_preferences.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/member.dart';
import '../../../data/models/project.dart';
import '../../../data/models/task.dart';

class RealtimeTimelineScreen extends ConsumerStatefulWidget {
  const RealtimeTimelineScreen({super.key});

  @override
  ConsumerState<RealtimeTimelineScreen> createState() => _RealtimeTimelineScreenState();
}

class _RealtimeTimelineScreenState extends ConsumerState<RealtimeTimelineScreen>
    with AutomaticKeepAliveClientMixin<RealtimeTimelineScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _headerHorizontalController = ScrollController();
  final ScrollController _bodyHorizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  bool _syncingHorizontal = false;
  bool _showCriticalPath = true;
  bool _showBaseline = true;
  bool _showOriginalProjectPlan = true;
  bool _autoFitOriginalProjectPlan = true;
  bool _showTodayLine = true;
  bool _modifiedView = true;
  TimelinePreferences? _lastAppliedPreferences;
  String _projectFilter = 'all';
  String _query = '';
  String _searchHighlightQuery = '';
  _TimelineScale _scale = _TimelineScale.week;
  _TimelineGroupMode _groupMode = _TimelineGroupMode.project;
  DateTime _focusDate = DateTime.now();
  TaskStatus? _statusFilter;
  TaskPriority? _priorityFilter;
  final Set<String> _collapsedGroupIds = <String>{};
  String? _selectedTaskId;

  @override
  void initState() {
    super.initState();
    _headerHorizontalController.addListener(() => _syncHorizontal(_headerHorizontalController, _bodyHorizontalController));
    _bodyHorizontalController.addListener(() => _syncHorizontal(_bodyHorizontalController, _headerHorizontalController));
  }

  void _syncHorizontal(ScrollController source, ScrollController target) {
    if (_syncingHorizontal || !source.hasClients || !target.hasClients) return;
    _syncingHorizontal = true;
    final next = source.offset.clamp(target.position.minScrollExtent, target.position.maxScrollExtent).toDouble();
    if ((target.offset - next).abs() > .5) target.jumpTo(next);
    _syncingHorizontal = false;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _headerHorizontalController.dispose();
    _bodyHorizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _schedulePreferenceSync(TimelinePreferences preferences) {
    final previous = _lastAppliedPreferences;
    if (previous == preferences) return;
    _lastAppliedPreferences = preferences;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showOriginalProjectPlan = preferences.showOriginalProjectPlan;
        _autoFitOriginalProjectPlan =
            preferences.autoFitOriginalProjectPlan;
        _showBaseline = preferences.showTaskBaselines;
        _showCriticalPath = preferences.showCriticalPath;
        _showTodayLine = preferences.showTodayLine;
        if (previous == null ||
            previous.defaultScale != preferences.defaultScale) {
          _scale = _scaleFromPreference(preferences.defaultScale);
        }
        if (previous == null ||
            previous.defaultGrouping != preferences.defaultGrouping) {
          _groupMode = _groupModeFromPreference(
            preferences.defaultGrouping,
          );
          _collapsedGroupIds.clear();
        }
      });
    });
  }

  Future<void> _openTimelineSettingsDialog({
    required WorkspaceState state,
    required TimelinePreferences preferences,
  }) async {
    var draft = preferences;
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              setDialogState(() => saving = true);
              await ref
                  .read(timelinePreferencesProvider.notifier)
                  .saveForWebUser(
                    companyId: state.company.companyId,
                    userId: state.currentMember.uid,
                    preferences: draft,
                  );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Timeline settings saved.'),
                  duration: Duration(seconds: 2),
                ),
              );
            }

            return AlertDialog(
              insetPadding: const EdgeInsets.all(20),
              titlePadding: EdgeInsets.zero,
              contentPadding: EdgeInsets.zero,
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              title: Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 18, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.settings_suggest_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Timeline settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Original plan, realtime bars, intelligence and viewport defaults',
                            style: TextStyle(
                              color: Color(0xFFDBEAFE),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 720,
                  maxHeight: 660,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFFBFDBFE),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Color(0xFF2563EB),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Striped bar = original project start/due dates. Solid bar = realtime roll-up from live task dates.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: draft.enabled,
                        onChanged: (value) => setDialogState(
                          () => draft = draft.copyWith(enabled: value),
                        ),
                        title: const Text('Enable realtime Timeline'),
                        subtitle: const Text(
                          'Controls the Timeline entry in web navigation.',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: draft.showOriginalProjectPlan,
                        onChanged: draft.enabled
                            ? (value) => setDialogState(
                                  () => draft = draft.copyWith(
                                    showOriginalProjectPlan: value,
                                  ),
                                )
                            : null,
                        title: const Text('Show original project timeline'),
                        subtitle: const Text(
                          'Render project.startDate to project.dueDate even when the project has no tasks.',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: draft.autoFitOriginalProjectPlan,
                        onChanged:
                            draft.enabled && draft.showOriginalProjectPlan
                                ? (value) => setDialogState(
                                      () => draft = draft.copyWith(
                                        autoFitOriginalProjectPlan: value,
                                      ),
                                    )
                                : null,
                        title: const Text('Auto-fit original project timeline'),
                        subtitle: const Text(
                          'Automatically includes project dates in the visible Gantt range.',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: draft.showTaskBaselines,
                        onChanged: draft.enabled
                            ? (value) => setDialogState(
                                  () => draft = draft.copyWith(
                                    showTaskBaselines: value,
                                  ),
                                )
                            : null,
                        title: const Text('Show task baselines'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: draft.showCriticalPath,
                        onChanged: draft.enabled
                            ? (value) => setDialogState(
                                  () => draft = draft.copyWith(
                                    showCriticalPath: value,
                                  ),
                                )
                            : null,
                        title: const Text('Show critical path'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: draft.showTodayLine,
                        onChanged: draft.enabled
                            ? (value) => setDialogState(
                                  () => draft = draft.copyWith(
                                    showTodayLine: value,
                                  ),
                                )
                            : null,
                        title: const Text('Show today line'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<TimelineDefaultScale>(
                        value: draft.defaultScale,
                        decoration: const InputDecoration(
                          labelText: 'Default scale',
                          border: OutlineInputBorder(),
                        ),
                        items: TimelineDefaultScale.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(_timelineScalePreferenceLabel(value)),
                              ),
                            )
                            .toList(),
                        onChanged: draft.enabled
                            ? (value) {
                                if (value == null) return;
                                setDialogState(
                                  () => draft = draft.copyWith(
                                    defaultScale: value,
                                  ),
                                );
                              }
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<TimelineDefaultGrouping>(
                        value: draft.defaultGrouping,
                        decoration: const InputDecoration(
                          labelText: 'Default grouping',
                          border: OutlineInputBorder(),
                        ),
                        items: TimelineDefaultGrouping.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(
                                  _timelineGroupingPreferenceLabel(value),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: draft.enabled
                            ? (value) {
                                if (value == null) return;
                                setDialogState(
                                  () => draft = draft.copyWith(
                                    defaultGrouping: value,
                                  ),
                                );
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => setDialogState(
                            () => draft = TimelinePreferences.defaults,
                          ),
                  child: const Text('Reset'),
                ),
                OutlinedButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'Saving…' : 'Save settings'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(workspaceProvider);
    final member = state.currentMember;
    final timelinePreferences = ref.watch(timelinePreferencesProvider);
    ref.read(timelinePreferencesProvider.notifier).bindWebUser(
          companyId: state.company.companyId,
          userId: member.uid,
        );
    _schedulePreferenceSync(timelinePreferences);

    final canEdit = PermissionService.canEditTimeline(member);
    final projects = state.visibleProjects;
    final projectMap = <String, Project>{
      for (final project in projects) project.projectId: project,
    };
    final filteredTasks = _filteredTasks(state, projectMap);
    final selectedProject = projectMap[_projectFilter];
    final visibleProjectMap =
        _projectFilter == 'all' || selectedProject == null
            ? projectMap
            : <String, Project>{
                selectedProject.projectId: selectedProject,
              };
    final range = _TimelineRange.fromTasks(
      filteredTasks,
      visibleProjectMap,
      _scale,
      _focusDate,
      includeOriginalProjectPlan: _showOriginalProjectPlan,
      autoFitOriginalProjectPlan: _autoFitOriginalProjectPlan,
    );
    final allRows = _timelineRowsForMode(
      state: state,
      tasks: filteredTasks,
      projects: visibleProjectMap,
      mode: _groupMode,
      includeOriginalProjectPlan: _showOriginalProjectPlan,
    );
    final rows = _visibleTimelineRows(allRows, _collapsedGroupIds);
    final completed = filteredTasks.where((task) => task.status == TaskStatus.completed).length;
    final progress = filteredTasks.isEmpty ? 0 : ((completed / filteredTasks.length) * 100).round();
    ProjectTask? selectedTask;
    for (final task in filteredTasks) {
      if (task.taskId == _selectedTaskId) {
        selectedTask = task;
        break;
      }
    }

    final viewportWidth = MediaQuery.sizeOf(context).width;
    final pagePadding = viewportWidth < 760
        ? 8.0
        : viewportWidth < 1180
            ? 12.0
            : 18.0;

    return Scaffold(
      backgroundColor: const Color(0xFFEAF4FF),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TimelineWorkItemToolbar(
                projects: projects,
                queryController: _searchController,
                selectedProjectId: _projectFilter,
                groupMode: _groupMode,
                scale: _scale,
                focusDate: _focusDate,
                modifiedView: _modifiedView,
                showCriticalPath: _showCriticalPath,
                showBaseline: _showBaseline,
                showOriginalProjectPlan: _showOriginalProjectPlan,
                statusFilter: _statusFilter,
                priorityFilter: _priorityFilter,
                canEdit: canEdit,
                onQueryChanged: (value) => _query = value,
                onSearchPressed: () =>
                    _runTimelineSearch(state, filteredTasks, projectMap),
                onProjectChanged: (value) => setState(() {
                  _projectFilter = value;
                  final project = projectMap[value];
                  if (project != null && _autoFitOriginalProjectPlan) {
                    _focusDate = project.startDate;
                  }
                }),
                onGroupModeChanged: (value) => setState(() {
                  _groupMode = value;
                  _collapsedGroupIds.clear();
                }),
                onScaleChanged: (value) => setState(() => _scale = value),
                onPrevious: () => setState(
                  () => _focusDate = _shiftFocus(_focusDate, _scale, -1),
                ),
                onNext: () => setState(
                  () => _focusDate = _shiftFocus(_focusDate, _scale, 1),
                ),
                onToday: () => setState(() => _focusDate = DateTime.now()),
                onCriticalPathChanged: (value) =>
                    setState(() => _showCriticalPath = value),
                onBaselineChanged: (value) =>
                    setState(() => _showBaseline = value),
                onOriginalProjectPlanChanged: (value) =>
                    setState(() => _showOriginalProjectPlan = value),
                onModifiedViewChanged: (value) =>
                    setState(() => _modifiedView = value),
                onStatusFilterChanged: (value) =>
                    setState(() => _statusFilter = value),
                onPriorityFilterChanged: (value) =>
                    setState(() => _priorityFilter = value),
                onClearFilters: () => setState(() {
                  _query = '';
                  _searchHighlightQuery = '';
                  _selectedTaskId = null;
                  _searchController.clear();
                  _projectFilter = 'all';
                  _statusFilter = null;
                  _priorityFilter = null;
                }),
                onExport: () =>
                    _copyTimelineCsv(context, filteredTasks, projectMap),
                onSettings: () => _openTimelineSettingsDialog(
                  state: state,
                  preferences: timelinePreferences,
                ),
              ),
              const SizedBox(height: 12),
              _TimelineSummaryStrip(
                member: member,
                canEdit: canEdit,
                tasks: filteredTasks,
                projects: projects,
                progress: progress,
              ),
              const SizedBox(height: 10),
              _TimelineIntelligenceStrip(tasks: filteredTasks),
              const SizedBox(height: 10),
              Expanded(
                child: RepaintBoundary(
                  child: _TaskfordTimelineBoard(
                    key: const ValueKey('realtime-timeline-board'),
                    state: state,
                    rows: rows,
                    projects: projectMap,
                    range: range,
                    canEdit: canEdit,
                    showCriticalPath: _showCriticalPath,
                    showBaseline: _showBaseline,
                    showOriginalProjectPlan: _showOriginalProjectPlan,
                    showTodayLine: _showTodayLine,
                    headerHorizontalController: _headerHorizontalController,
                    bodyHorizontalController: _bodyHorizontalController,
                    verticalController: _verticalController,
                    collapsedGroupIds: _collapsedGroupIds,
                    onGroupToggle: (groupId) => setState(() {
                      if (_collapsedGroupIds.contains(groupId)) {
                        _collapsedGroupIds.remove(groupId);
                      } else {
                        _collapsedGroupIds.add(groupId);
                      }
                    }),
                    selectedTaskId: _selectedTaskId,
                    searchHighlightQuery: _searchHighlightQuery,
                    onTaskSelected: (task) =>
                        setState(() => _selectedTaskId = task.taskId),
                    onTaskDateShift: _shiftTaskDates,
                    onStatusChanged: (task, status) => ref
                        .read(workspaceProvider.notifier)
                        .updateTaskStatus(task.taskId, status),
                  ),
                ),
              ),
              if (selectedTask != null) ...[
                const SizedBox(height: 10),
                _TimelineBottomTaskDetailPanel(
                  task: selectedTask,
                  project: projectMap[selectedTask.projectId],
                  members: _membersForTask(state, selectedTask),
                  canEdit: canEdit,
                  onClose: () => setState(() => _selectedTaskId = null),
                  onStatusChanged: (status) => ref
                      .read(workspaceProvider.notifier)
                      .updateTaskStatus(selectedTask!.taskId, status),
                  onConfigure: () =>
                      _openTaskIntelligenceDialog(state, selectedTask!),
                  onSetBaseline: () => ref
                      .read(workspaceProvider.notifier)
                      .setTaskBaselineFromCurrent(selectedTask!.taskId),
                  onClearBaseline: () => ref
                      .read(workspaceProvider.notifier)
                      .updateTaskTimelineConfiguration(
                        taskId: selectedTask!.taskId,
                        clearBaseline: true,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _runTimelineSearch(WorkspaceState state, List<ProjectTask> visibleTasks, Map<String, Project> projectMap) {
    final query = _searchController.text.trim();
    ProjectTask? firstMatch;
    if (query.isNotEmpty) {
      for (final task in visibleTasks) {
        if (_matchesTimelineSearch(state, task, projectMap, query)) {
          firstMatch = task;
          break;
        }
      }
    }

    String? matchingGroupId;
    DateTime? matchingFocusDate;
    final matchedTask = firstMatch;
    if (matchedTask != null) {
      final allRows = _timelineRowsForMode(
        state: state,
        tasks: visibleTasks,
        projects: projectMap,
        mode: _groupMode,
      );
      final taskRowIndex = allRows.indexWhere((row) => row.task?.taskId == matchedTask.taskId);
      if (taskRowIndex >= 0) {
        for (var index = taskRowIndex - 1; index >= 0; index--) {
          if (allRows[index].isGroup) {
            matchingGroupId = allRows[index].id;
            break;
          }
        }
      }
      matchingFocusDate = _taskStartDate(matchedTask, projectMap);
    }

    setState(() {
      _query = query;
      _searchHighlightQuery = query;
      _selectedTaskId = firstMatch?.taskId;
      if (matchingGroupId != null) _collapsedGroupIds.remove(matchingGroupId);
      if (matchingFocusDate != null) _focusDate = matchingFocusDate!;
    });
    if (firstMatch != null) {
      _focusTaskInBoard(state, visibleTasks, projectMap, firstMatch);
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          query.isEmpty
              ? 'Search cleared.'
              : (firstMatch == null
                  ? 'No task matched "$query".'
                  : 'Highlighted "${firstMatch.title}" in the timeline.'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _focusTaskInBoard(
    WorkspaceState state,
    List<ProjectTask> tasks,
    Map<String, Project> projects,
    ProjectTask task,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final allRows = _timelineRowsForMode(state: state, tasks: tasks, projects: projects, mode: _groupMode);
      final rows = _visibleTimelineRows(allRows, _collapsedGroupIds);
      final rowIndex = rows.indexWhere((row) => row.task?.taskId == task.taskId);
      if (rowIndex >= 0 && _verticalController.hasClients) {
        final target = (rowIndex * 48.0 - 96).clamp(
          _verticalController.position.minScrollExtent,
          _verticalController.position.maxScrollExtent,
        ).toDouble();
        _verticalController.animateTo(target, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      }
      if (_bodyHorizontalController.hasClients) {
        final range = _TimelineRange.fromTasks(tasks, projects, _scale, _focusDate);
        final estimatedDayWidth = _estimatedDayWidth(_scale, MediaQuery.sizeOf(context).width);
        final target = (range.indexOf(_taskStartDate(task, projects)) * estimatedDayWidth - 120).clamp(
          _bodyHorizontalController.position.minScrollExtent,
          _bodyHorizontalController.position.maxScrollExtent,
        ).toDouble();
        _bodyHorizontalController.animateTo(target, duration: const Duration(milliseconds: 460), curve: Curves.easeOutCubic);
      }
    });
  }

  Future<void> _openTaskIntelligenceDialog(WorkspaceState state, ProjectTask task) async {
    final request = await showDialog<_TaskIntelligenceRequest>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TaskIntelligenceDialog(task: task, tasks: state.visibleTasks),
    );
    if (request == null || !mounted) return;
    ref.read(workspaceProvider.notifier).updateTaskTimelineConfiguration(
          taskId: task.taskId,
          dependencyTaskIds: request.dependencyTaskIds,
          isMilestone: request.isMilestone,
          progressPercent: request.progressPercent,
          riskLevel: request.riskLevel,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${task.title} timeline intelligence saved.')),
    );
  }

  List<ProjectTask> _filteredTasks(WorkspaceState state, Map<String, Project> projectMap) {
    final tasks = state.visibleTasks.where((task) {
      if (_projectFilter != 'all' && task.projectId != _projectFilter) return false;
      if (_statusFilter != null && task.status != _statusFilter) return false;
      if (_priorityFilter != null && task.priority != _priorityFilter) return false;
      // Text search is now a highlight/jump action, not a destructive filter.
      // Keeping all rows visible preserves Gantt context while the matching task is emphasized.
      return true;
    }).toList();
    tasks.sort((a, b) {
      final projectCompare = _projectName(projectMap, a.projectId).compareTo(_projectName(projectMap, b.projectId));
      if (projectCompare != 0) return projectCompare;
      final dateCompare = _taskStartDate(a, projectMap).compareTo(_taskStartDate(b, projectMap));
      if (dateCompare != 0) return dateCompare;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return tasks;
  }

  void _shiftTaskDates(ProjectTask task, Map<String, Project> projects, int deltaDays) {
    if (deltaDays == 0) return;
    final start = _taskStartDate(task, projects).add(Duration(days: deltaDays));
    final due = task.dueDate.add(Duration(days: deltaDays));
    ref.read(workspaceProvider.notifier).updateTaskTimelineDates(task.taskId, startDate: start, dueDate: due);
  }

  Future<void> _copyTimelineCsv(BuildContext context, List<ProjectTask> tasks, Map<String, Project> projectMap) async {
    final rows = <String>['Project,Task,Status,Priority,Start,Due,Progress'];
    for (final task in tasks) {
      rows.add([
        _csv(projectMap[task.projectId]?.name ?? task.projectId),
        _csv(task.title),
        _csv(task.status.label),
        _csv(task.priority.label),
        DateText.compact(_taskStartDate(task, projectMap)),
        DateText.compact(task.dueDate),
        '${_taskProgress(task)}%',
      ].join(','));
    }
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Timeline CSV copied to clipboard.')));
  }
}

class _TimelineBottomTaskDetailPanel extends StatelessWidget {
  const _TimelineBottomTaskDetailPanel({
    required this.task,
    required this.project,
    required this.members,
    required this.canEdit,
    required this.onClose,
    required this.onStatusChanged,
    required this.onConfigure,
    required this.onSetBaseline,
    required this.onClearBaseline,
  });

  final ProjectTask task;
  final Project? project;
  final List<Member> members;
  final bool canEdit;
  final VoidCallback onClose;
  final ValueChanged<TaskStatus> onStatusChanged;
  final VoidCallback onConfigure;
  final VoidCallback onSetBaseline;
  final VoidCallback onClearBaseline;

  @override
  Widget build(BuildContext context) {
    final color = _colorForTask(task);
    final start = _taskStartDate(task, project == null ? const <String, Project>{} : <String, Project>{project!.projectId: project!});
    final assigneeText = members.isEmpty ? 'Unassigned' : members.map((member) => member.displayName).join(', ');
    final risk = task.riskLevel.trim().isEmpty ? 'normal' : task.riskLevel.trim().toLowerCase();
    final riskColor = _riskColor(risk);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(15)),
                  child: Icon(task.isMilestone ? Icons.diamond_rounded : task.status == TaskStatus.completed ? Icons.verified_rounded : Icons.task_alt_rounded, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                      const SizedBox(height: 3),
                      Text(project?.name ?? 'No project', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800, fontSize: 12)),
                    ],
                  ),
                ),
                _DetailPill(label: task.status.label, color: task.status.color),
                const SizedBox(width: 6),
                _DetailPill(label: risk.toUpperCase(), color: riskColor),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded), tooltip: 'Close details'),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _DetailInfo(icon: Icons.people_rounded, label: assigneeText),
                _DetailInfo(icon: Icons.date_range_rounded, label: '${DateText.compact(start)} → ${DateText.compact(task.dueDate)}'),
                _DetailInfo(icon: Icons.percent_rounded, label: '${_taskProgress(task)}% complete'),
                _DetailInfo(icon: Icons.account_tree_rounded, label: '${task.dependencyTaskIds.length} dependencies'),
                _DetailInfo(icon: Icons.compare_arrows_rounded, label: task.hasBaseline ? 'Baseline configured' : 'No baseline'),
                if (task.isMilestone) const _DetailInfo(icon: Icons.diamond_rounded, label: 'Milestone'),
              ],
            ),
            if (task.description.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(task.description, maxLines: narrow ? 1 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, height: 1.25)),
            ],
          ],
        );

        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            if (canEdit)
              PopupMenuButton<TaskStatus>(
                tooltip: 'Change task status',
                onSelected: onStatusChanged,
                itemBuilder: (context) => TaskStatus.values.map((status) => PopupMenuItem(value: status, child: Text(status.label))).toList(),
                child: const _TimelineActionButton(icon: Icons.swap_horiz_rounded, label: 'Status'),
              ),
            if (canEdit)
              _TimelineActionButton(icon: Icons.psychology_alt_rounded, label: 'Configure', onTap: onConfigure, active: true),
            if (canEdit && !task.hasBaseline)
              _TimelineActionButton(icon: Icons.add_chart_rounded, label: 'Set baseline', onTap: onSetBaseline),
            if (canEdit && task.hasBaseline)
              _TimelineActionButton(icon: Icons.layers_clear_rounded, label: 'Clear baseline', onTap: onClearBaseline),
          ],
        );

        return Container(
          constraints: BoxConstraints(minHeight: 126, maxHeight: narrow ? 240 : 190),
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _selectedBorderColor(task)),
            boxShadow: const [BoxShadow(color: Color(0x160F172A), blurRadius: 22, offset: Offset(0, 10))],
          ),
          child: narrow
              ? SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [details, const SizedBox(height: 10), actions]))
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: details), const SizedBox(width: 14), SizedBox(width: 300, child: actions)]),
        );
      },
    );
  }
}

Color _selectedBorderColor(ProjectTask task) {
  if (task.isOverdue) return const Color(0xFFFCA5A5);
  if (task.dependencyTaskIds.isNotEmpty) return const Color(0xFF99F6E4);
  return const Color(0xFFD5E0EC);
}

Color _riskColor(String risk) {
  return switch (risk.trim().toLowerCase()) {
    'critical' || 'blocked' => const Color(0xFFDC2626),
    'high' => const Color(0xFFF97316),
    'medium' => const Color(0xFFF59E0B),
    'low' => const Color(0xFF0EA5E9),
    _ => const Color(0xFF16A34A),
  };
}

class _TimelineActionButton extends StatelessWidget {
  const _TimelineActionButton({required this.icon, required this.label, this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: active ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? const Color(0xFF2563EB) : const Color(0xFF475569)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: active ? const Color(0xFF2563EB) : const Color(0xFF475569), fontWeight: FontWeight.w900, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _DetailInfo extends StatelessWidget {
  const _DetailInfo({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF64748B)),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w800, fontSize: 12)),
        ),
      ],
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(.18))),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11)),
    );
  }
}


class _TaskIntelligenceRequest {
  const _TaskIntelligenceRequest({
    required this.dependencyTaskIds,
    required this.isMilestone,
    required this.progressPercent,
    required this.riskLevel,
  });

  final List<String> dependencyTaskIds;
  final bool isMilestone;
  final int progressPercent;
  final String riskLevel;
}

class _TaskIntelligenceDialog extends StatefulWidget {
  const _TaskIntelligenceDialog({required this.task, required this.tasks});

  final ProjectTask task;
  final List<ProjectTask> tasks;

  @override
  State<_TaskIntelligenceDialog> createState() => _TaskIntelligenceDialogState();
}

class _TaskIntelligenceDialogState extends State<_TaskIntelligenceDialog> {
  late final Set<String> _dependencyIds = widget.task.dependencyTaskIds.toSet();
  late bool _isMilestone = widget.task.isMilestone;
  late double _progress = _taskProgress(widget.task).toDouble();
  late String _riskLevel = widget.task.riskLevel.trim().isEmpty ? 'normal' : widget.task.riskLevel.trim().toLowerCase();
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final candidates = widget.tasks.where((task) {
      if (task.taskId == widget.task.taskId) return false;
      if (_wouldCreateDependencyCycle(
        targetTaskId: widget.task.taskId,
        predecessorTaskId: task.taskId,
        tasks: widget.tasks,
      )) {
        return false;
      }
      final query = _search.trim().toLowerCase();
      return query.isEmpty || '${task.title} ${task.status.label} ${task.priority.label}'.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.psychology_alt_rounded, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Timeline intelligence', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF0F172A))),
                        Text(widget.task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 250,
                    child: DropdownButtonFormField<String>(
                      value: _riskLevel,
                      decoration: const InputDecoration(labelText: 'Schedule risk', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'normal', child: Text('Normal')),
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                        DropdownMenuItem(value: 'medium', child: Text('Medium')),
                        DropdownMenuItem(value: 'high', child: Text('High')),
                        DropdownMenuItem(value: 'critical', child: Text('Critical')),
                        DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                      ],
                      onChanged: (value) => setState(() => _riskLevel = value ?? 'normal'),
                    ),
                  ),
                  FilterChip(
                    selected: _isMilestone,
                    onSelected: (value) => setState(() => _isMilestone = value),
                    avatar: const Icon(Icons.diamond_rounded, size: 17),
                    label: const Text('Milestone'),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: Text('${_progress.round()}% progress', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155))),
                  ),
                ],
              ),
              Slider(
                value: _progress,
                min: 0,
                max: 100,
                divisions: 20,
                label: '${_progress.round()}%',
                onChanged: (value) => setState(() => _progress = value),
              ),
              const SizedBox(height: 6),
              const Text('Predecessor dependencies', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0F172A))),
              const SizedBox(height: 4),
              const Text(
                'Tasks that would create a circular dependency are hidden automatically.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  hintText: 'Find a predecessor task',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: candidates.isEmpty
                    ? const Center(child: Text('No dependency candidates found.'))
                    : ListView.separated(
                        itemCount: candidates.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          final selected = _dependencyIds.contains(candidate.taskId);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (value) => setState(() {
                              if (value == true) {
                                _dependencyIds.add(candidate.taskId);
                              } else {
                                _dependencyIds.remove(candidate.taskId);
                              }
                            }),
                            secondary: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(color: _colorForTask(candidate).withOpacity(.12), borderRadius: BorderRadius.circular(11)),
                              child: Icon(candidate.isMilestone ? Icons.diamond_rounded : Icons.task_alt_rounded, color: _colorForTask(candidate), size: 18),
                            ),
                            title: Text(candidate.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text('${candidate.status.label} • ${DateText.compact(candidate.dueDate)}'),
                            controlAffinity: ListTileControlAffinity.trailing,
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('${_dependencyIds.length} selected', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800)),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      _TaskIntelligenceRequest(
                        dependencyTaskIds: _dependencyIds.toList()..sort(),
                        isMilestone: _isMilestone,
                        progressPercent: _progress.round(),
                        riskLevel: _riskLevel,
                      ),
                    ),
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save intelligence'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineSearchBox extends StatefulWidget {
  const _TimelineSearchBox({
    required this.width,
    required this.controller,
    required this.onChanged,
    required this.onSearch,
  });

  final double width;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;

  @override
  State<_TimelineSearchBox> createState() => _TimelineSearchBoxState();
}

class _TimelineSearchBoxState extends State<_TimelineSearchBox> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'timelineSearch');
  bool _hovered = false;

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _TimelineSearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    final active = focused || _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: widget.width,
        height: 44,
        decoration: BoxDecoration(
          color: focused ? Colors.white : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: focused
                ? const Color(0xFF2563EB)
                : active
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFFD5DFEA),
            width: focused ? 1.5 : 1,
          ),
          boxShadow: focused
              ? const [
                  BoxShadow(
                    color: Color(0x242563EB),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x0A0F172A),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              const SizedBox(width: 13),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: Icon(
                  focused ? Icons.manage_search_rounded : Icons.search_rounded,
                  key: ValueKey(focused),
                  size: 20,
                  color: focused ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  onChanged: widget.onChanged,
                  onSubmitted: (_) => widget.onSearch(),
                  onTapOutside: (_) => _focusNode.unfocus(),
                  textInputAction: TextInputAction.search,
                  cursorColor: const Color(0xFF2563EB),
                  cursorWidth: 1.6,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    hintText: 'Search tasks, people or projects',
                    hintStyle: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _hasText
                    ? Tooltip(
                        key: const ValueKey('timeline-search-clear'),
                        message: 'Clear search',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: _clear,
                          child: const SizedBox(
                            width: 30,
                            height: 34,
                            child: Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                          ),
                        ),
                      )
                    : const SizedBox(key: ValueKey('timeline-search-empty'), width: 4),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Tooltip(
                  message: 'Find and highlight task',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: widget.onSearch,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: focused || _hasText ? const Color(0xFF2563EB) : const Color(0xFFE8F0FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 19,
                        color: focused || _hasText ? Colors.white : const Color(0xFF2563EB),
                      ),
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

class _TimelineWorkItemToolbar extends StatelessWidget {
  const _TimelineWorkItemToolbar({
    required this.projects,
    required this.queryController,
    required this.selectedProjectId,
    required this.groupMode,
    required this.scale,
    required this.focusDate,
    required this.modifiedView,
    required this.showCriticalPath,
    required this.showBaseline,
    required this.showOriginalProjectPlan,
    required this.statusFilter,
    required this.priorityFilter,
    required this.canEdit,
    required this.onQueryChanged,
    required this.onSearchPressed,
    required this.onProjectChanged,
    required this.onGroupModeChanged,
    required this.onScaleChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onCriticalPathChanged,
    required this.onBaselineChanged,
    required this.onOriginalProjectPlanChanged,
    required this.onModifiedViewChanged,
    required this.onStatusFilterChanged,
    required this.onPriorityFilterChanged,
    required this.onClearFilters,
    required this.onExport,
    required this.onSettings,
  });

  final List<Project> projects;
  final TextEditingController queryController;
  final String selectedProjectId;
  final _TimelineGroupMode groupMode;
  final _TimelineScale scale;
  final DateTime focusDate;
  final bool modifiedView;
  final bool showCriticalPath;
  final bool showBaseline;
  final bool showOriginalProjectPlan;
  final TaskStatus? statusFilter;
  final TaskPriority? priorityFilter;
  final bool canEdit;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onSearchPressed;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<_TimelineGroupMode> onGroupModeChanged;
  final ValueChanged<_TimelineScale> onScaleChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<bool> onCriticalPathChanged;
  final ValueChanged<bool> onBaselineChanged;
  final ValueChanged<bool> onOriginalProjectPlanChanged;
  final ValueChanged<bool> onModifiedViewChanged;
  final ValueChanged<TaskStatus?> onStatusFilterChanged;
  final ValueChanged<TaskPriority?> onPriorityFilterChanged;
  final VoidCallback onClearFilters;
  final VoidCallback onExport;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final filterActive = statusFilter != null || priorityFilter != null || selectedProjectId != 'all';
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
        final compact = maxWidth < 980;
        final tight = maxWidth < 680;
        final searchWidth = tight ? (maxWidth < 200 ? maxWidth : math.max(180.0, math.min(maxWidth, 520.0))) : (compact ? 300.0 : 320.0);
        final projectLabel = selectedProjectId == 'all' ? 'All Projects' : _selectedProjectLabel(projects, selectedProjectId);

        final controls = <Widget>[
          _TimelineSearchBox(
            width: searchWidth,
            controller: queryController,
            onChanged: onQueryChanged,
            onSearch: onSearchPressed,
          ),
          PopupMenuButton<String>(
            tooltip: 'Project filter',
            onSelected: onProjectChanged,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All projects')),
              ...projects.map((project) => PopupMenuItem(value: project.projectId, child: Text(project.name))),
            ],
            child: _ToolbarChip(icon: Icons.filter_list_rounded, label: projectLabel),
          ),
          PopupMenuButton<bool>(
            tooltip: 'Timeline view',
            onSelected: onModifiedViewChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: false, child: Text('View: Default')),
              PopupMenuItem(value: true, child: Text('View: Modified')),
            ],
            child: _ToolbarChip(icon: Icons.view_list_rounded, label: 'View: Default', badge: modifiedView ? 'MODIFIED' : null),
          ),
          PopupMenuButton<_TimelineGroupMode>(
            tooltip: 'Group timeline',
            onSelected: onGroupModeChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: _TimelineGroupMode.project, child: Text('Group by project')),
              PopupMenuItem(value: _TimelineGroupMode.assignee, child: Text('Group by assignee')),
              PopupMenuItem(value: _TimelineGroupMode.status, child: Text('Group by status')),
              PopupMenuItem(value: _TimelineGroupMode.department, child: Text('Group by department')),
            ],
            child: _ToolbarChip(icon: Icons.segment_rounded, label: 'Group by ${_groupModeLabel(groupMode)}'),
          ),
          _ToolbarButton(
            icon: Icons.tune_rounded,
            label: filterActive ? 'Filter active' : 'Filter',
            active: filterActive,
            onTap: () => _showTimelineFilterSheet(context),
          ),
          _ToolbarButton(
            icon: Icons.account_tree_rounded,
            label: compact ? 'Critical' : 'Critical path',
            active: showCriticalPath,
            onTap: () => onCriticalPathChanged(!showCriticalPath),
          ),
          _ToolbarButton(
            icon: Icons.view_timeline_rounded,
            label: 'Baseline',
            active: showBaseline,
            onTap: () => onBaselineChanged(!showBaseline),
          ),
          _ToolbarButton(
            icon: Icons.date_range_rounded,
            label: compact ? 'Plan' : 'Original plan',
            active: showOriginalProjectPlan,
            onTap: () => onOriginalProjectPlanChanged(
              !showOriginalProjectPlan,
            ),
          ),
          _IconToolbarButton(icon: Icons.chevron_left_rounded, onTap: onPrevious, tooltip: 'Previous'),
          PopupMenuButton<_TimelineScale>(
            tooltip: 'Timeline scale',
            onSelected: onScaleChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: _TimelineScale.day, child: Text('Day / 2 weeks')),
              PopupMenuItem(value: _TimelineScale.week, child: Text('Week / 6 weeks')),
              PopupMenuItem(value: _TimelineScale.month, child: Text('Month / quarter')),
              PopupMenuItem(value: _TimelineScale.quarter, child: Text('Quarter / year')),
            ],
            child: _RangeChip(label: _rangeLabel(scale, focusDate), scale: scale),
          ),
          _IconToolbarButton(icon: Icons.chevron_right_rounded, onTap: onNext, tooltip: 'Next'),
          _ToolbarButton(icon: Icons.today_rounded, label: 'Today', active: true, onTap: onToday),
          _IconToolbarButton(icon: Icons.file_download_outlined, onTap: onExport, tooltip: 'Copy CSV export'),
          _IconToolbarButton(
            icon: Icons.upload_file_outlined,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import uses your existing project/task Firestore data.'))),
            tooltip: 'Import info',
          ),
          _IconToolbarButton(
            icon: Icons.settings_suggest_rounded,
            onTap: onSettings,
            tooltip: 'Timeline settings',
          ),
        ];

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFDCE6F3)),
            boxShadow: const [BoxShadow(color: Color(0x120F172A), blurRadius: 20, offset: Offset(0, 12))],
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: controls,
          ),
        );
      },
    );
  }

  Future<void> _showTimelineFilterSheet(BuildContext context) async {
    var nextStatus = statusFilter;
    var nextPriority = priorityFilter;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            margin: const EdgeInsets.all(18),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: const [BoxShadow(color: Color(0x330F172A), blurRadius: 26, offset: Offset(0, 12))]),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Timeline filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                DropdownButtonFormField<TaskStatus?>(
                  value: nextStatus,
                  decoration: const InputDecoration(labelText: 'Task status', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<TaskStatus?>(value: null, child: Text('Any status')),
                    ...TaskStatus.values.map((status) => DropdownMenuItem<TaskStatus?>(value: status, child: Text(status.label))),
                  ],
                  onChanged: (value) => setSheetState(() => nextStatus = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TaskPriority?>(
                  value: nextPriority,
                  decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem<TaskPriority?>(value: null, child: Text('Any priority')),
                    ...TaskPriority.values.map((priority) => DropdownMenuItem<TaskPriority?>(value: priority, child: Text(priority.label))),
                  ],
                  onChanged: (value) => setSheetState(() => nextPriority = value),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(onPressed: () { onClearFilters(); Navigator.of(sheetContext).pop(); }, child: const Text('Clear all')),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        onStatusFilterChanged(nextStatus);
                        onPriorityFilterChanged(nextPriority);
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Apply filters'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TimelineSummaryStrip extends StatelessWidget {
  const _TimelineSummaryStrip({required this.member, required this.canEdit, required this.tasks, required this.projects, required this.progress});

  final Member member;
  final bool canEdit;
  final List<ProjectTask> tasks;
  final List<Project> projects;
  final int progress;

  @override
  Widget build(BuildContext context) {
    final overdue = tasks.where((task) => task.isOverdue).length;
    final critical = tasks.where((task) => task.priority == TaskPriority.critical || task.priority == TaskPriority.high).length;
    final cards = <Widget>[
      _AccessSummaryCard(member: member, canEdit: canEdit),
      _MiniMetricCard(icon: Icons.folder_rounded, label: 'Projects', value: '${projects.length}', color: const Color(0xFF2563EB)),
      _MiniMetricCard(icon: Icons.workspaces_rounded, label: 'Work items', value: '${tasks.length}/${tasks.length}', color: const Color(0xFF0F172A)),
      _MiniMetricCard(icon: Icons.warning_amber_rounded, label: 'Critical path', value: '$critical', color: const Color(0xFFF97316)),
      _MiniMetricCard(icon: Icons.schedule_rounded, label: 'Late', value: '$overdue', color: const Color(0xFFEF4444)),
      _MiniMetricCard(icon: Icons.auto_graph_rounded, label: 'Done', value: '$progress%', color: const Color(0xFF16A34A)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
        if (maxWidth >= 1100) {
          return Row(
            children: [
              Expanded(flex: 2, child: cards[0]),
              for (var i = 1; i < cards.length; i++) ...[
                const SizedBox(width: 10),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        final columns = maxWidth < 620 ? 1 : maxWidth < 860 ? 2 : 3;
        final rawWidth = (maxWidth - (columns - 1) * 10) / columns;
        final width = maxWidth < 260 ? maxWidth : rawWidth.clamp(240.0, maxWidth).toDouble();
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards.map((card) => SizedBox(width: width, child: card)).toList(),
        );
      },
    );
  }
}

class _TimelineIntelligenceStrip extends StatelessWidget {
  const _TimelineIntelligenceStrip({required this.tasks});

  final List<ProjectTask> tasks;

  @override
  Widget build(BuildContext context) {
    final dependencyCount = tasks.fold<int>(0, (sum, task) => sum + task.dependencyTaskIds.length);
    final milestoneCount = tasks.where((task) => task.isMilestone).length;
    final baselineCount = tasks.where((task) => task.hasBaseline).length;
    final riskCount = tasks.where((task) {
      final risk = task.riskLevel.trim().toLowerCase();
      return task.isOverdue || risk == 'high' || risk == 'critical' || risk == 'blocked';
    }).length;
    final baselineCoverage = tasks.isEmpty ? 0 : (baselineCount * 100 / tasks.length).round();
    final scheduleHealth = tasks.isEmpty
        ? 100
        : (100 - ((riskCount * 65 + tasks.where((task) => task.isOverdue).length * 35) / tasks.length)).round().clamp(0, 100);

    final items = <({IconData icon, String label, String value, Color color})>[
      (icon: Icons.account_tree_rounded, label: 'Dependencies', value: '$dependencyCount', color: const Color(0xFF0F9F91)),
      (icon: Icons.diamond_rounded, label: 'Milestones', value: '$milestoneCount', color: const Color(0xFF7C3AED)),
      (icon: Icons.compare_arrows_rounded, label: 'Baseline coverage', value: '$baselineCoverage%', color: const Color(0xFF2563EB)),
      (icon: Icons.crisis_alert_rounded, label: 'At risk', value: '$riskCount', color: const Color(0xFFEF4444)),
      (icon: Icons.health_and_safety_rounded, label: 'Schedule health', value: '$scheduleHealth%', color: scheduleHealth >= 75 ? const Color(0xFF16A34A) : const Color(0xFFF59E0B)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF07152E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x2607152E), blurRadius: 18, offset: Offset(0, 10))],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 840;
          final itemWidth = compact ? math.max(150.0, (constraints.maxWidth - 10) / 2) : math.max(150.0, (constraints.maxWidth - 40) / 5);
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items.map((item) {
              return SizedBox(
                width: itemWidth,
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.07),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withOpacity(.10)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: item.color.withOpacity(.22), borderRadius: BorderRadius.circular(11)),
                        child: Icon(item.icon, color: item.color, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                            Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB8C6DA), fontWeight: FontWeight.w700, fontSize: 10.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _TaskfordTimelineBoard extends StatefulWidget {
  const _TaskfordTimelineBoard({
    super.key,
    required this.state,
    required this.rows,
    required this.projects,
    required this.range,
    required this.canEdit,
    required this.showCriticalPath,
    required this.showBaseline,
    required this.showOriginalProjectPlan,
    required this.showTodayLine,
    required this.headerHorizontalController,
    required this.bodyHorizontalController,
    required this.verticalController,
    required this.collapsedGroupIds,
    required this.onGroupToggle,
    required this.selectedTaskId,
    required this.searchHighlightQuery,
    required this.onTaskSelected,
    required this.onTaskDateShift,
    required this.onStatusChanged,
  });

  final WorkspaceState state;
  final List<_TimelineRowData> rows;
  final Map<String, Project> projects;
  final _TimelineRange range;
  final bool canEdit;
  final bool showCriticalPath;
  final bool showBaseline;
  final bool showOriginalProjectPlan;
  final bool showTodayLine;
  final ScrollController headerHorizontalController;
  final ScrollController bodyHorizontalController;
  final ScrollController verticalController;
  final Set<String> collapsedGroupIds;
  final ValueChanged<String> onGroupToggle;
  final String? selectedTaskId;
  final String searchHighlightQuery;
  final ValueChanged<ProjectTask> onTaskSelected;
  final void Function(ProjectTask task, Map<String, Project> projects, int deltaDays) onTaskDateShift;
  final void Function(ProjectTask task, TaskStatus status) onStatusChanged;

  @override
  State<_TaskfordTimelineBoard> createState() => _TaskfordTimelineBoardState();
}

class _TaskfordTimelineBoardState extends State<_TaskfordTimelineBoard> {
  static const double _defaultDayWidth = 46;
  static const double _defaultRowHeight = 48;
  static const double _defaultHeaderHeight = 86;

  double? _rowNumberWidth;
  double? _workItemWidth;
  double? _assigneeWidth;
  double? _progressWidth;

  // Keep only the fully built board cache. The Timeline must always consume
  // the live parent width so a collapsed navigation rail immediately releases
  // its space to the Gantt surface. Width stabilization previously preserved
  // the old expanded-rail constraint and left a large empty strip.
  Widget? _cachedBoard;
  double? _cachedBoardWidth;
  double? _cachedBoardHeight;

  Timer? _viewportSettleTimer;
  double? _committedViewportWidth;
  double? _pendingViewportWidth;
  static const Duration _viewportSettleDelay =
      Duration(milliseconds: 120);

  double? _cachedCompactWorkWidth;
  double? _cachedRegularWorkWidth;
  double? _cachedCompactAssigneeWidth;
  double? _cachedRegularAssigneeWidth;

  @override
  void dispose() {
    _viewportSettleTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TaskfordTimelineBoard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final rowsChanged =
        _rowsSignature(oldWidget.rows) != _rowsSignature(widget.rows);
    final membersChanged =
        _membersSignature(oldWidget.state.members) !=
            _membersSignature(widget.state.members);

    final boardInputsChanged =
        rowsChanged ||
        membersChanged ||
        _projectsSignature(oldWidget.projects) !=
            _projectsSignature(widget.projects) ||
        _rangeSignature(oldWidget.range) != _rangeSignature(widget.range) ||
        oldWidget.canEdit != widget.canEdit ||
        oldWidget.showCriticalPath != widget.showCriticalPath ||
        oldWidget.showBaseline != widget.showBaseline ||
        oldWidget.showOriginalProjectPlan !=
            widget.showOriginalProjectPlan ||
        oldWidget.showTodayLine != widget.showTodayLine ||
        oldWidget.selectedTaskId != widget.selectedTaskId ||
        oldWidget.searchHighlightQuery != widget.searchHighlightQuery ||
        _stringSetSignature(oldWidget.collapsedGroupIds) !=
            _stringSetSignature(widget.collapsedGroupIds);

    if (boardInputsChanged) {
      _invalidateBoardCache();
    }

    if (rowsChanged) {
      _cachedCompactWorkWidth = null;
      _cachedRegularWorkWidth = null;
    }

    if (membersChanged) {
      _cachedCompactAssigneeWidth = null;
      _cachedRegularAssigneeWidth = null;
    }
  }

  int _rowsSignature(List<_TimelineRowData> rows) {
    return Object.hashAll(
      rows.map(
        (row) => Object.hash(
          row.id,
          row.number,
          row.title,
          row.depth,
          row.progress,
          row.taskCount,
          row.startDate?.millisecondsSinceEpoch,
          row.endDate?.millisecondsSinceEpoch,
          row.originalStartDate?.millisecondsSinceEpoch,
          row.originalEndDate?.millisecondsSinceEpoch,
          row.groupIcon.codePoint,
          row.groupColor.value,
          row.task == null
              ? null
              : Object.hash(
                  row.task!.taskId,
                  row.task!.title,
                  row.task!.status,
                  row.task!.priority,
                  row.task!.progressPercent,
                  row.task!.startDate?.millisecondsSinceEpoch,
                  row.task!.dueDate.millisecondsSinceEpoch,
                  row.task!.baselineStartDate?.millisecondsSinceEpoch,
                  row.task!.baselineDueDate?.millisecondsSinceEpoch,
                  row.task!.isMilestone,
                  row.task!.riskLevel,
                  Object.hashAll(row.task!.dependencyTaskIds),
                  Object.hashAll(row.task!.assignedToIds),
                ),
        ),
      ),
    );
  }

  int _membersSignature(List<Member> members) {
    return Object.hashAll(
      members.map(
        (member) => Object.hash(
          member.uid,
          member.displayName,
          member.role,
          member.effectiveDepartment,
        ),
      ),
    );
  }

  int _projectsSignature(Map<String, Project> projects) {
    final entries = projects.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Object.hashAll(
      entries.map(
        (entry) => Object.hash(
          entry.key,
          entry.value.name,
          entry.value.startDate.millisecondsSinceEpoch,
          entry.value.dueDate.millisecondsSinceEpoch,
          entry.value.progress,
          entry.value.status,
        ),
      ),
    );
  }

  int _rangeSignature(_TimelineRange range) {
    return Object.hash(
      range.scale,
      range.days.length,
      range.start.millisecondsSinceEpoch,
      range.end.millisecondsSinceEpoch,
    );
  }

  int _stringSetSignature(Set<String> values) {
    final sorted = values.toList()..sort();
    return Object.hashAll(sorted);
  }

  void _invalidateBoardCache() {
    _cachedBoard = null;
    _cachedBoardWidth = null;
    _cachedBoardHeight = null;
  }

  double _measureText(String value, TextStyle style, {double extra = 0}) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width + extra;
  }

  double _autoWorkItemWidth(bool compact) {
    final cached = compact
        ? _cachedCompactWorkWidth
        : _cachedRegularWorkWidth;
    if (cached != null) return cached;

    const style = TextStyle(fontWeight: FontWeight.w800, fontSize: 13);
    var longest = _measureText('Work item', style, extra: 54);
    for (final row in widget.rows) {
      final label = row.isGroup
          ? row.title
          : (row.task?.title.trim().isNotEmpty == true
              ? row.task!.title
              : row.title);
      final indent = row.isGroup ? 42.0 : 58.0;
      longest = math.max(
        longest,
        _measureText(label, style, extra: indent),
      );
    }
    final result = longest
        .clamp(compact ? 180.0 : 220.0, compact ? 390.0 : 520.0)
        .toDouble();
    if (compact) {
      _cachedCompactWorkWidth = result;
    } else {
      _cachedRegularWorkWidth = result;
    }
    return result;
  }

  double _autoAssigneeWidth(bool compact) {
    final cached = compact
        ? _cachedCompactAssigneeWidth
        : _cachedRegularAssigneeWidth;
    if (cached != null) return cached;

    const style = TextStyle(fontWeight: FontWeight.w700, fontSize: 12);
    var longest = _measureText('Assignee', style, extra: 34);
    for (final member in widget.state.members) {
      longest = math.max(
        longest,
        _measureText(member.displayName, style, extra: 52),
      );
    }
    final result = longest
        .clamp(compact ? 108.0 : 130.0, compact ? 220.0 : 280.0)
        .toDouble();
    if (compact) {
      _cachedCompactAssigneeWidth = result;
    } else {
      _cachedRegularAssigneeWidth = result;
    }
    return result;
  }

  double _fitWidth(String column, bool compact) {
    return switch (column) {
      'number' => compact ? 54.0 : 70.0,
      'work' => _autoWorkItemWidth(compact),
      'assignee' => _autoAssigneeWidth(compact),
      'progress' => compact ? 132.0 : 176.0,
      _ => 120.0,
    };
  }

  void _resizeColumn(String column, double delta, bool compact) {
    setState(() {
      _invalidateBoardCache();
      switch (column) {
        case 'number':
          _rowNumberWidth = ((_rowNumberWidth ?? _fitWidth('number', compact)) + delta).clamp(42.0, 110.0).toDouble();
          break;
        case 'work':
          _workItemWidth = ((_workItemWidth ?? _fitWidth('work', compact)) + delta).clamp(140.0, 680.0).toDouble();
          break;
        case 'assignee':
          _assigneeWidth = ((_assigneeWidth ?? _fitWidth('assignee', compact)) + delta).clamp(92.0, 360.0).toDouble();
          break;
        case 'progress':
          _progressWidth = ((_progressWidth ?? _fitWidth('progress', compact)) + delta).clamp(112.0, 300.0).toDouble();
          break;
      }
    });
  }

  void _resetColumn(String column) {
    setState(() {
      _invalidateBoardCache();
      switch (column) {
        case 'number': _rowNumberWidth = null; break;
        case 'work': _workItemWidth = null; break;
        case 'assignee': _assigneeWidth = null; break;
        case 'progress': _progressWidth = null; break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = (constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width)
            .floorToDouble();
        final availableHeight = (constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height)
            .floorToDouble();

        _committedViewportWidth ??= availableWidth;
        _pendingViewportWidth = availableWidth;

        final widthIsMoving =
            (_committedViewportWidth! - availableWidth).abs() >= 1.0;

        if (widthIsMoving) {
          _viewportSettleTimer?.cancel();
          _viewportSettleTimer = Timer(_viewportSettleDelay, () {
            if (!mounted) return;
            final settledWidth = _pendingViewportWidth;
            if (settledWidth == null) return;

            setState(() {
              _committedViewportWidth = settledWidth;
              _invalidateBoardCache();
            });
          });
        }

        final committedWidth =
            math.max(1.0, _committedViewportWidth!).floorToDouble();

        final cacheMatches = _cachedBoard != null &&
            _cachedBoardWidth == committedWidth &&
            _cachedBoardHeight == availableHeight;

        if (!cacheMatches) {
          _cachedBoard = _buildBoardForWidth(committedWidth);
          _cachedBoardWidth = committedWidth;
          _cachedBoardHeight = availableHeight;
        }

        final horizontalFit =
            (availableWidth / committedWidth).clamp(0.60, 1.40).toDouble();

        return SizedBox.expand(
          child: RepaintBoundary(
            child: ClipRect(
              child: Transform(
                alignment: Alignment.topLeft,
                transform: Matrix4.diagonal3Values(
                  horizontalFit,
                  1.0,
                  1.0,
                ),
                transformHitTests: false,
                child: SizedBox(
                  width: committedWidth,
                  height: availableHeight,
                  child: _cachedBoard!,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBoardForWidth(double availableWidth) {
        final compact = availableWidth < 980;
        final veryCompact = availableWidth < 720;

        var rowNumberWidth = _rowNumberWidth ?? _fitWidth('number', compact);
        var workItemWidth = _workItemWidth ?? _fitWidth('work', compact);
        var assigneeWidth = _assigneeWidth ?? _fitWidth('assignee', compact);
        var progressWidth = _progressWidth ?? _fitWidth('progress', compact);

        // The final frozen-table column sits directly against the Gantt area.
        // Reserve the divider/resize gutter and round every width to a whole
        // logical pixel so the header and body cannot disagree by 1 px.
        const double frozenBoundaryGutter = 18.0;
        const double frozenRoundingSafety = 2.0;
        final minTimelineViewport = veryCompact ? 150.0 : compact ? 210.0 : 300.0;
        final maxFrozenWidth = math.max(
          340.0,
          availableWidth -
              minTimelineViewport -
              frozenBoundaryGutter -
              frozenRoundingSafety,
        ).floorToDouble();

        const double minRowNumberWidth = 44.0;
        const double minWorkItemWidth = 112.0;
        const double minAssigneeWidth = 76.0;
        const double minProgressWidth = 104.0;

        rowNumberWidth = rowNumberWidth.floorToDouble();
        workItemWidth = workItemWidth.floorToDouble();
        assigneeWidth = assigneeWidth.floorToDouble();
        progressWidth = progressWidth.floorToDouble();

        var remainingOverflow = math.max(
          0.0,
          rowNumberWidth +
              workItemWidth +
              assigneeWidth +
              progressWidth -
              maxFrozenWidth,
        );

        double reduceColumn(double current, double minimum) {
          if (remainingOverflow <= 0) return current.floorToDouble();
          final reducible = math.max(0.0, current - minimum);
          final reduction = math.min(remainingOverflow, reducible);
          remainingOverflow -= reduction;
          return (current - reduction).floorToDouble();
        }

        // Reduce the flexible columns first. The final Progress column is then
        // recalculated from the exact remaining width instead of accumulated
        // floating-point values.
        workItemWidth = reduceColumn(workItemWidth, minWorkItemWidth);
        assigneeWidth = reduceColumn(assigneeWidth, minAssigneeWidth);
        rowNumberWidth = reduceColumn(rowNumberWidth, minRowNumberWidth);

        final widthBeforeProgress =
            rowNumberWidth + workItemWidth + assigneeWidth;
        final availableProgressWidth =
            (maxFrozenWidth - widthBeforeProgress).floorToDouble();

        progressWidth = math.max(
          minProgressWidth,
          math.min(progressWidth, availableProgressWidth),
        ).floorToDouble();

        var frozenWidth = (rowNumberWidth +
                workItemWidth +
                assigneeWidth +
                progressWidth)
            .floorToDouble();

        // Absolute last-line protection. This also covers the 1 px border at
        // the Progress/Gantt boundary on fractional browser scale factors.
        if (frozenWidth > maxFrozenWidth) {
          final excess = frozenWidth - maxFrozenWidth;
          progressWidth = math.max(
            minProgressWidth,
            progressWidth - excess - 1.0,
          ).floorToDouble();
          frozenWidth = (rowNumberWidth +
                  workItemWidth +
                  assigneeWidth +
                  progressWidth)
              .floorToDouble();
        }

        final dayWidth = switch (widget.range.scale) {
          _TimelineScale.day => veryCompact ? 42.0 : compact ? 50.0 : 62.0,
          _TimelineScale.week => veryCompact ? 34.0 : compact ? 38.0 : _defaultDayWidth,
          _TimelineScale.month => veryCompact ? 18.0 : compact ? 22.0 : 26.0,
          _TimelineScale.quarter => veryCompact ? 9.0 : compact ? 11.0 : 13.0,
        };
        final rowHeight = veryCompact ? 42.0 : compact ? 44.0 : _defaultRowHeight;
        final groupRowHeight = rowHeight;
        final headerHeight = compact ? 80.0 : _defaultHeaderHeight;
        final timelineWidth = math.max(availableWidth < 900 ? 640.0 : 900.0, widget.range.days.length * dayWidth);
        final bodyHeight = widget.rows.fold<double>(0, (sum, row) => sum + (row.isGroup ? groupRowHeight : rowHeight));

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD5E0EC)),
            boxShadow: const [BoxShadow(color: Color(0x160F172A), blurRadius: 24, offset: Offset(0, 14))],
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.rows.isEmpty
              ? const _EmptyTimeline()
              : Column(
                  children: [
                    SizedBox(
                      height: headerHeight,
                      child: Row(
                        children: [
                          SizedBox(
                            width: frozenWidth.floorToDouble(),
                            child: ClipRect(
                              child: _FrozenTableHeader(
                                rowNumberWidth: rowNumberWidth,
                                workItemWidth: workItemWidth,
                                assigneeWidth: assigneeWidth,
                                progressWidth: progressWidth,
                                height: headerHeight,
                                itemCount: widget.rows.where((row) => !row.isGroup).length,
                                onResize: (column, delta) => _resizeColumn(column, delta, compact),
                                onAutoFit: _resetColumn,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Scrollbar(
                              controller: widget.headerHorizontalController,
                              thumbVisibility: false,
                              child: SingleChildScrollView(
                                controller: widget.headerHorizontalController,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(width: timelineWidth, child: _TimelineDateHeader(range: widget.range, dayWidth: dayWidth, height: headerHeight)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: widget.verticalController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: widget.verticalController,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: frozenWidth.floorToDouble(),
                                child: Column(
                                  children: [
                                    for (var i = 0; i < widget.rows.length; i++)
                                      _TimelineLeftRow(
                                        row: widget.rows[i],
                                        visibleIndex: i,
                                        state: widget.state,
                                        rowNumberWidth: rowNumberWidth,
                                        workItemWidth: workItemWidth,
                                        assigneeWidth: assigneeWidth,
                                        progressWidth: progressWidth,
                                        rowHeight: widget.rows[i].isGroup ? groupRowHeight : rowHeight,
                                        canEdit: widget.canEdit,
                                        selected: widget.rows[i].task?.taskId == widget.selectedTaskId,
                                        highlighted: _rowMatchesSearch(widget.state, widget.rows[i], widget.projects, widget.searchHighlightQuery),
                                        collapsed: widget.collapsedGroupIds.contains(widget.rows[i].id),
                                        onGroupToggle: () => widget.onGroupToggle(widget.rows[i].id),
                                        onTaskSelected: widget.onTaskSelected,
                                        onStatusChanged: widget.onStatusChanged,
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Scrollbar(
                                  controller: widget.bodyHorizontalController,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: widget.bodyHorizontalController,
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: timelineWidth,
                                      height: bodyHeight,
                                      child: Stack(
                                        children: [
                                          Column(
                                            children: [
                                              for (var i = 0; i < widget.rows.length; i++)
                                                _TimelineRightRow(
                                                  row: widget.rows[i],
                                                  projects: widget.projects,
                                                  range: widget.range,
                                                  dayWidth: dayWidth,
                                                  rowHeight: widget.rows[i].isGroup ? groupRowHeight : rowHeight,
                                                  canEdit: widget.canEdit,
                                                  selected: widget.rows[i].task?.taskId == widget.selectedTaskId,
                                                  highlighted: _rowMatchesSearch(widget.state, widget.rows[i], widget.projects, widget.searchHighlightQuery),
                                                  showBaseline: widget.showBaseline,
                                                  showOriginalProjectPlan: widget.showOriginalProjectPlan,
                                                  onTaskSelected: widget.onTaskSelected,
                                                  onTaskDateShift: widget.onTaskDateShift,
                                                ),
                                            ],
                                          ),
                                          if (widget.showCriticalPath)
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: CustomPaint(
                                                  painter: _DependencyLinePainter(
                                                    rows: widget.rows,
                                                    range: widget.range,
                                                    projects: widget.projects,
                                                    dayWidth: dayWidth,
                                                    rowHeight: rowHeight,
                                                    groupRowHeight: groupRowHeight,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (widget.showTodayLine)
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: CustomPaint(
                                                  painter: _TodayLinePainter(
                                                    range: widget.range,
                                                    dayWidth: dayWidth,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        );
  }
}

class _FrozenTableHeader extends StatelessWidget {
  const _FrozenTableHeader({
    required this.rowNumberWidth,
    required this.workItemWidth,
    required this.assigneeWidth,
    required this.progressWidth,
    required this.height,
    required this.itemCount,
    required this.onResize,
    required this.onAutoFit,
  });

  final double rowNumberWidth;
  final double workItemWidth;
  final double assigneeWidth;
  final double progressWidth;
  final double height;
  final int itemCount;
  final void Function(String column, double delta) onResize;
  final ValueChanged<String> onAutoFit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFBFCFE),
        border: Border(right: BorderSide(color: Color(0xFFD5E0EC)), bottom: BorderSide(color: Color(0xFFD5E0EC))),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: Row(
              children: [
                const SizedBox(width: 18),
                const Icon(Icons.fact_check_outlined, size: 16, color: Color(0xFF334155)),
                const SizedBox(width: 8),
                Expanded(child: Text('$itemCount/$itemCount work items', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF64748B), fontSize: 13))),
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Tooltip(message: 'Drag column borders to resize. Double-click a border to auto-fit.', child: Icon(Icons.drag_indicator_rounded, size: 16, color: Color(0xFF94A3B8))),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFD5E0EC)),
          Expanded(
            child: Row(
              children: [
                _ResizableHeaderCell(width: rowNumberWidth, label: '#', columnId: 'number', alignCenter: true, onResize: onResize, onAutoFit: onAutoFit),
                _ResizableHeaderCell(width: workItemWidth, label: 'Work item', columnId: 'work', icon: Icons.keyboard_double_arrow_up_rounded, onResize: onResize, onAutoFit: onAutoFit),
                _ResizableHeaderCell(width: assigneeWidth, label: 'Assignee', columnId: 'assignee', onResize: onResize, onAutoFit: onAutoFit),
                // The last column must absorb the exact remaining width from
                // the parent Row. Keeping it fixed can overflow by one physical
                // pixel on browser zoom / non-integer device-pixel ratios.
                Expanded(
                  child: _ResizableHeaderCell(
                    width: progressWidth,
                    label: 'Progress',
                    columnId: 'progress',
                    onResize: onResize,
                    onAutoFit: onAutoFit,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _ResizableHeaderCell extends StatelessWidget {
  const _ResizableHeaderCell({
    required this.width,
    required this.label,
    required this.columnId,
    required this.onResize,
    required this.onAutoFit,
    this.icon,
    this.alignCenter = false,
  });

  final double width;
  final String label;
  final String columnId;
  final IconData? icon;
  final bool alignCenter;
  final void Function(String column, double delta) onResize;
  final ValueChanged<String> onAutoFit;

  @override
  Widget build(BuildContext context) {
    final safeWidth = math.max(1.0, width.floorToDouble());

    return SizedBox(
      width: safeWidth,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: alignCenter ? 4 : 10,
              right: 8,
            ),
            child: Align(
              alignment: alignCenter
                  ? Alignment.center
                  : Alignment.centerLeft,
              child: icon != null && safeWidth > 82
                  ? Row(
                      children: [
                        Icon(
                          icon,
                          size: 15,
                          color: const Color(0xFF334155),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      textAlign: alignCenter ? TextAlign.center : TextAlign.left,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF334155),
                      ),
                    ),
            ),
          ),

          // Draw the divider inside the allocated cell width. It must not be
          // another Row child because that would add one extra logical pixel.
          const Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: SizedBox(
              width: 1,
              child: ColoredBox(color: Color(0xFFE2E8F0)),
            ),
          ),

          // The resize target overlays the cell; it never consumes layout width.
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: 8,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  onResize(columnId, details.delta.dx);
                },
                onDoubleTap: () => onAutoFit(columnId),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 3,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(999),
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

class _TimelineDateHeader extends StatelessWidget {
  const _TimelineDateHeader({required this.range, required this.dayWidth, required this.height});

  final _TimelineRange range;
  final double dayWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final periods = _timelineHeaderPeriods(range);
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Column(
            children: [
              SizedBox(
                height: 38,
                child: Stack(
                  children: [
                    for (final period in periods)
                      Positioned(
                        left: range.indexOf(period.start) * dayWidth,
                        width: math.max(dayWidth, dayWidth * period.dayCount),
                        top: 0,
                        bottom: 0,
                        child: Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 12),
                          decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFD5E0EC)))),
                          child: Text(
                            period.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                          ),
                        ),
                      ),
                    for (final marker in _importantDates(range.days))
                      Positioned(
                        left: range.indexOf(marker) * dayWidth + dayWidth / 2 - 5,
                        top: 8,
                        child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFD5E0EC)),
              Expanded(
                child: Row(
                  children: [
                    for (final day in range.days)
                      Container(
                        width: dayWidth,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _sameDay(day, DateTime.now()) ? const Color(0xFFFFF1F2) : _isWeekend(day) ? const Color(0xFFF8FAFC) : Colors.white,
                          border: const Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: Text(
                          _timelineDayLabel(range.scale, day, dayWidth),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _sameDay(day, DateTime.now()) ? const Color(0xFFEF4444) : const Color(0xFF334155),
                            fontSize: dayWidth < 15 ? 8 : 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (range.contains(DateTime.now()))
            Positioned(
              left: range.indexOf(DateTime.now()) * dayWidth,
              top: 44,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(color: Color(0xFFEF4444), borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
                child: const Text('Today', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineLeftRow extends StatelessWidget {
  const _TimelineLeftRow({required this.row, required this.visibleIndex, required this.state, required this.rowNumberWidth, required this.workItemWidth, required this.assigneeWidth, required this.progressWidth, required this.rowHeight, required this.canEdit, required this.selected, required this.highlighted, required this.collapsed, required this.onGroupToggle, required this.onTaskSelected, required this.onStatusChanged});

  final _TimelineRowData row;
  final int visibleIndex;
  final WorkspaceState state;
  final double rowNumberWidth;
  final double workItemWidth;
  final double assigneeWidth;
  final double progressWidth;
  final double rowHeight;
  final bool canEdit;
  final bool selected;
  final bool highlighted;
  final bool collapsed;
  final VoidCallback onGroupToggle;
  final ValueChanged<ProjectTask> onTaskSelected;
  final void Function(ProjectTask task, TaskStatus status) onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final task = row.task;
    final members = task == null ? const <Member>[] : _membersForTask(state, task);
    final rowColor = row.isGroup ? const Color(0xFFFBFCFE) : Colors.white;
    return Material(
      color: selected
          ? const Color(0xFFEFF6FF)
          : (highlighted ? const Color(0xFFFFFBEB) : Colors.transparent),
      child: InkWell(
        onTap: task == null ? null : () => onTaskSelected(task),
        child: SizedBox(
          height: rowHeight,
          child: Row(
        children: [
          _NumberCell(width: rowNumberWidth, row: row, index: visibleIndex),
          _WorkItemCell(width: workItemWidth, row: row, highlighted: highlighted, collapsed: collapsed, onGroupToggle: row.isGroup ? onGroupToggle : null),
          _AssigneeCell(width: assigneeWidth, members: members, row: row),
          // Fill the exact remainder instead of applying another fixed
          // width. This removes the one-pixel RenderFlex overflow that appears
          // at the Progress/Gantt boundary on Chrome at fractional scaling.
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: rowColor,
                border: const Border(
                  right: BorderSide(
                    color: Color(0xFFD5E0EC),
                    width: 1,
                  ),
                  bottom: BorderSide(
                    color: Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final available = constraints.maxWidth.floorToDouble();
                  final showMenu =
                      canEdit && task != null && available >= 152;

                  return Padding(
                    padding: EdgeInsets.only(
                      left: available < 120 ? 5 : 8,
                      right: showMenu ? 2 : 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Expanded(
                          child: ClipRect(
                            child: _InlineProgress(
                              value: row.progress,
                              isGroup: row.isGroup,
                              compact: available < 142,
                            ),
                          ),
                        ),
                        if (showMenu)
                          SizedBox(
                            width: 30,
                            height: 36,
                            child: PopupMenuButton<TaskStatus>(
                              padding: EdgeInsets.zero,
                              tooltip: 'Change status',
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                size: 17,
                                color: Color(0xFF64748B),
                              ),
                              onSelected: (status) {
                                onStatusChanged(task, status);
                              },
                              itemBuilder: (context) => TaskStatus.values
                                  .map(
                                    (status) => PopupMenuItem<TaskStatus>(
                                      value: status,
                                      child: Text(status.label),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  );
                },
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

class _NumberCell extends StatelessWidget {
  const _NumberCell({required this.width, required this.row, required this.index});
  final double width;
  final _TimelineRowData row;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: row.isGroup ? const Color(0xFFFBFCFE) : Colors.white, border: const Border(right: BorderSide(color: Color(0xFFE2E8F0)), bottom: BorderSide(color: Color(0xFFE2E8F0)))),
      child: Text(row.number.isEmpty ? '${index + 1}' : row.number, style: TextStyle(fontWeight: row.isGroup ? FontWeight.w900 : FontWeight.w700, color: const Color(0xFF334155), fontSize: 12)),
    );
  }
}

class _WorkItemCell extends StatelessWidget {
  const _WorkItemCell({required this.width, required this.row, required this.highlighted, required this.collapsed, this.onGroupToggle});
  final double width;
  final _TimelineRowData row;
  final bool highlighted;
  final bool collapsed;
  final VoidCallback? onGroupToggle;

  @override
  Widget build(BuildContext context) {
    final task = row.task;
    final indent = 16.0 + row.depth * 22.0;
    final color = task == null ? const Color(0xFF2563EB) : _colorForTask(task);
    final background = highlighted ? const Color(0xFFFFFBEB) : (row.isGroup ? const Color(0xFFFBFCFE) : Colors.white);
    return Container(
      width: width,
      decoration: BoxDecoration(color: background, border: Border(right: const BorderSide(color: Color(0xFFE2E8F0)), bottom: const BorderSide(color: Color(0xFFE2E8F0)), left: highlighted ? const BorderSide(color: Color(0xFFF59E0B), width: 3) : BorderSide.none)),
      child: Stack(
        children: [
          if (row.depth > 0)
            Positioned(
              left: indent - 12,
              top: 0,
              bottom: 0,
              child: Container(width: 1, color: const Color(0xFFD5E0EC)),
            ),
          Positioned(
            left: indent,
            right: 10,
            top: 0,
            bottom: 0,
            child: Row(
              children: [
                if (row.isGroup) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onGroupToggle,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(collapsed ? Icons.chevron_right_rounded : Icons.keyboard_arrow_down_rounded, size: 20, color: const Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(row.groupIcon, size: 18, color: row.groupColor),
                ] else ...[
                  Icon(row.taskIcon, size: 16, color: color),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: row.isGroup ? FontWeight.w900 : FontWeight.w700, color: const Color(0xFF0F172A), fontSize: row.isGroup ? 14 : 13),
                  ),
                ),
                if (highlighted)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(.14), borderRadius: BorderRadius.circular(999)),
                      child: const Text('MATCH', style: TextStyle(color: Color(0xFFB45309), fontSize: 9, fontWeight: FontWeight.w900)),
                    ),
                  ),
                if (task?.priority == TaskPriority.critical || task?.isOverdue == true)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(task!.isOverdue ? Icons.warning_amber_rounded : Icons.priority_high_rounded, color: const Color(0xFFF97316), size: 18),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssigneeCell extends StatelessWidget {
  const _AssigneeCell({required this.width, required this.members, required this.row});
  final double width;
  final List<Member> members;
  final _TimelineRowData row;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: row.isGroup ? const Color(0xFFFBFCFE) : Colors.white, border: const Border(right: BorderSide(color: Color(0xFFE2E8F0)), bottom: BorderSide(color: Color(0xFFE2E8F0)))),
      child: row.isGroup
          ? Text('${row.taskCount} item${row.taskCount == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF64748B)))
          : _AssigneeDots(members: members),
    );
  }
}

class _TimelineRightRow extends StatefulWidget {
  const _TimelineRightRow({required this.row, required this.projects, required this.range, required this.dayWidth, required this.rowHeight, required this.canEdit, required this.selected, required this.highlighted, required this.showBaseline, required this.showOriginalProjectPlan, required this.onTaskSelected, required this.onTaskDateShift});

  final _TimelineRowData row;
  final Map<String, Project> projects;
  final _TimelineRange range;
  final double dayWidth;
  final double rowHeight;
  final bool canEdit;
  final bool selected;
  final bool highlighted;
  final bool showBaseline;
  final bool showOriginalProjectPlan;
  final ValueChanged<ProjectTask> onTaskSelected;
  final void Function(ProjectTask task, Map<String, Project> projects, int deltaDays) onTaskDateShift;

  @override
  State<_TimelineRightRow> createState() => _TimelineRightRowState();
}

class _TimelineRightRowState extends State<_TimelineRightRow> {
  double _dragOffset = 0;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final task = row.task;
    final width = widget.range.days.length * widget.dayWidth;
    return SizedBox(
      width: width,
      height: widget.rowHeight,
      child: Stack(
        children: [
          _TimelineGrid(dayWidth: widget.dayWidth),
          if (widget.highlighted)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(.10),
                  border: const Border.symmetric(horizontal: BorderSide(color: Color(0xFFFDE68A))),
                ),
              ),
            ),
          if (row.isGroup)
            _GroupTimelineBar(
              row: row,
              range: widget.range,
              dayWidth: widget.dayWidth,
              height: widget.rowHeight,
              showOriginalProjectPlan: widget.showOriginalProjectPlan,
            )
          else if (task != null) ...[
            if (widget.showBaseline) _BaselineBar(task: task, projects: widget.projects, range: widget.range, dayWidth: widget.dayWidth, rowHeight: widget.rowHeight),
            _DraggableTaskBar(
              task: task,
              projects: widget.projects,
              range: widget.range,
              dayWidth: widget.dayWidth,
              rowHeight: widget.rowHeight,
              canEdit: widget.canEdit,
              selected: widget.selected,
              highlighted: widget.highlighted,
              dragOffset: _dragOffset,
              onTap: () => widget.onTaskSelected(task),
              onDragUpdate: (delta) => setState(() => _dragOffset += delta),
              onDragEnd: () {
                final days = (_dragOffset / widget.dayWidth).round();
                setState(() => _dragOffset = 0);
                if (days != 0) {
                  HapticFeedback.selectionClick();
                  widget.onTaskDateShift(task, widget.projects, days);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupTimelineBar extends StatelessWidget {
  const _GroupTimelineBar({
    required this.row,
    required this.range,
    required this.dayWidth,
    required this.height,
    required this.showOriginalProjectPlan,
  });

  final _TimelineRowData row;
  final _TimelineRange range;
  final double dayWidth;
  final double height;
  final bool showOriginalProjectPlan;

  @override
  Widget build(BuildContext context) {
    // Project rows intentionally use the original project plan as the
    // primary bar. This restores the compact grey project-bar style from the
    // previous Timeline while task rows continue to show realtime schedules.
    final originalGeometry = showOriginalProjectPlan && row.isProjectGroup
        ? _geometry(row.originalStartDate, row.originalEndDate)
        : null;
    final realtimeGeometry = _geometry(row.startDate, row.endDate);
    final primaryGeometry = originalGeometry ?? realtimeGeometry;

    if (primaryGeometry == null) {
      return const SizedBox.shrink();
    }

    final rawStart = originalGeometry != null
        ? row.originalStartDate
        : row.startDate;
    final rawEnd = originalGeometry != null
        ? row.originalEndDate
        : row.endDate;
    final tooltipPrefix = originalGeometry != null
        ? 'Original project plan'
        : 'Realtime project roll-up';

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: primaryGeometry.left,
            top: height / 2 - 9,
            child: Tooltip(
              message: rawStart != null && rawEnd != null
                  ? '$tooltipPrefix • ${DateText.compact(rawStart)} – ${DateText.compact(rawEnd)}'
                  : tooltipPrefix,
              child: Container(
                width: primaryGeometry.width,
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFF707B8C),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x180F172A),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),

          // Keep the realtime roll-up available as a subtle marker when it
          // differs from the original project plan. It does not compete with
          // the main grey project bar.
          if (originalGeometry != null &&
              realtimeGeometry != null &&
              (realtimeGeometry.left - originalGeometry.left).abs() > 1)
            Positioned(
              left: realtimeGeometry.left,
              top: height / 2 + 12,
              child: Container(
                width: realtimeGeometry.width,
                height: 3,
                decoration: BoxDecoration(
                  color: row.groupColor.withOpacity(.70),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
        ],
      ),
    );
  }

  _TimelineBarGeometry? _geometry(DateTime? rawStart, DateTime? rawEnd) {
    if (rawStart == null || rawEnd == null) return null;
    final start = DateTime(rawStart.year, rawStart.month, rawStart.day);
    final candidateEnd = DateTime(rawEnd.year, rawEnd.month, rawEnd.day);
    final end = candidateEnd.isBefore(start) ? start : candidateEnd;
    if (end.isBefore(range.start) || start.isAfter(range.end)) return null;

    final visibleStart = start.isBefore(range.start) ? range.start : start;
    final visibleEnd = end.isAfter(range.end) ? range.end : end;
    final left = range.indexOf(visibleStart) * dayWidth + 2;
    final duration = math.max(
      1,
      visibleEnd.difference(visibleStart).inDays + 1,
    );
    final width = math.max(dayWidth, duration * dayWidth - 4);
    return _TimelineBarGeometry(left: left, width: width);
  }
}

class _TimelineBarGeometry {
  const _TimelineBarGeometry({required this.left, required this.width});

  final double left;
  final double width;
}

class _BaselineBar extends StatelessWidget {
  const _BaselineBar({required this.task, required this.projects, required this.range, required this.dayWidth, required this.rowHeight});

  final ProjectTask task;
  final Map<String, Project> projects;
  final _TimelineRange range;
  final double dayWidth;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final rawStart = task.baselineStartDate;
    final rawEnd = task.baselineDueDate;
    if (rawStart == null && rawEnd == null) return const SizedBox.shrink();
    final DateTime start = rawStart ?? rawEnd!;
    final DateTime candidateEnd = rawEnd ?? rawStart!;
    final DateTime end = candidateEnd.isBefore(start) ? start : candidateEnd;
    if (end.isBefore(range.start) || start.isAfter(range.end)) return const SizedBox.shrink();
    final visibleStart = start.isBefore(range.start) ? range.start : start;
    final visibleEnd = end.isAfter(range.end) ? range.end : end;
    final left = range.indexOf(visibleStart) * dayWidth + 4;
    final duration = math.max(1, DateTime(visibleEnd.year, visibleEnd.month, visibleEnd.day).difference(DateTime(visibleStart.year, visibleStart.month, visibleStart.day)).inDays + 1);
    final width = math.max(dayWidth, duration * dayWidth - 8);
    return Positioned(
      left: left,
      top: rowHeight / 2 - 14,
      child: CustomPaint(
        painter: _BaselineStripePainter(color: const Color(0xFF94A3B8).withOpacity(.25)),
        child: SizedBox(width: width, height: 28),
      ),
    );
  }
}

class _DraggableTaskBar extends StatelessWidget {
  const _DraggableTaskBar({required this.task, required this.projects, required this.range, required this.dayWidth, required this.rowHeight, required this.canEdit, required this.selected, required this.highlighted, required this.dragOffset, required this.onTap, required this.onDragUpdate, required this.onDragEnd});

  final ProjectTask task;
  final Map<String, Project> projects;
  final _TimelineRange range;
  final double dayWidth;
  final double rowHeight;
  final bool canEdit;
  final bool selected;
  final bool highlighted;
  final double dragOffset;
  final VoidCallback onTap;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final start = _taskStartDate(task, projects);
    final end = task.dueDate.isBefore(start) ? start : task.dueDate;
    if (end.isBefore(range.start) || start.isAfter(range.end)) return const SizedBox.shrink();
    final visibleStart = start.isBefore(range.start) ? range.start : start;
    final visibleEnd = end.isAfter(range.end) ? range.end : end;
    final startIndex = range.indexOf(visibleStart);
    final duration = math.max(1, DateTime(visibleEnd.year, visibleEnd.month, visibleEnd.day).difference(DateTime(visibleStart.year, visibleStart.month, visibleStart.day)).inDays + 1);
    final left = startIndex * dayWidth + dragOffset + 4;
    final width = math.max(dayWidth, duration * dayWidth - 8);
    final progress = _taskProgress(task);
    final color = _colorForTask(task);
    final critical = task.priority == TaskPriority.critical || task.isOverdue;

    if (task.isMilestone) {
      if (!range.contains(task.dueDate)) return const SizedBox.shrink();
      final milestoneLeft = range.indexOf(task.dueDate) * dayWidth + dragOffset + dayWidth / 2 - 13;
      return Positioned(
        left: milestoneLeft,
        top: rowHeight / 2 - 13,
        child: MouseRegion(
          cursor: canEdit ? SystemMouseCursors.grab : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            onHorizontalDragUpdate: canEdit ? (details) => onDragUpdate(details.delta.dx) : null,
            onHorizontalDragEnd: canEdit ? (_) => onDragEnd() : null,
            child: Tooltip(
              message: '${task.title} • milestone • ${DateText.compact(task.dueDate)}',
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Transform.rotate(
                    angle: math.pi / 4,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: highlighted ? const Color(0xFFF59E0B) : Colors.white, width: highlighted ? 3 : 2),
                        boxShadow: [BoxShadow(color: color.withOpacity(.32), blurRadius: selected || highlighted ? 16 : 9, offset: const Offset(0, 5))],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 31,
                    top: 2,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                      child: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Positioned(
      left: left,
      top: rowHeight / 2 - 13,
      child: MouseRegion(
        cursor: canEdit ? SystemMouseCursors.grab : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onTap,
          onHorizontalDragUpdate: canEdit ? (details) => onDragUpdate(details.delta.dx) : null,
          onHorizontalDragEnd: canEdit ? (_) => onDragEnd() : null,
          child: Tooltip(
            message: canEdit
                ? 'Drag to reschedule • ${DateText.compact(start)} - ${DateText.compact(end)}'
                : 'View only • ${DateText.compact(start)} - ${DateText.compact(end)}',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: width,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withOpacity(highlighted ? .30 : .18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: highlighted
                          ? const Color(0xFFF59E0B)
                          : (selected ? const Color(0xFF2563EB) : (critical ? const Color(0xFF0F172A) : color.withOpacity(.45))),
                      width: highlighted ? 2.4 : (selected ? 2.2 : (critical ? 1.4 : 1)),
                    ),
                    boxShadow: highlighted
                        ? const [BoxShadow(color: Color(0x40F59E0B), blurRadius: 18, offset: Offset(0, 8))]
                        : (selected
                            ? const [BoxShadow(color: Color(0x332563EB), blurRadius: 14, offset: Offset(0, 6))]
                            : (critical ? const [BoxShadow(color: Color(0x220F172A), blurRadius: 10, offset: Offset(0, 5))] : const [BoxShadow(color: Color(0x100F172A), blurRadius: 8, offset: Offset(0, 4))])),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      FractionallySizedBox(
                        widthFactor: (progress / 100).clamp(.04, 1.0).toDouble(),
                        child: Container(decoration: BoxDecoration(color: color.withOpacity(.88), borderRadius: BorderRadius.circular(999))),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: progress > 18 ? Colors.white : const Color(0xFF334155), fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (highlighted)
                  Positioned(
                    right: -10,
                    top: -9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(999), boxShadow: const [BoxShadow(color: Color(0x33F59E0B), blurRadius: 8)]),
                      child: const Text('SEARCH', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                    ),
                  ),
                Positioned(
                  right: -8,
                  top: 7,
                  child: Transform.rotate(
                    angle: math.pi / 4,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        border: Border.all(color: Colors.white, width: 2),
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
  }
}

class _DependencyLinePainter extends CustomPainter {
  const _DependencyLinePainter({
    required this.rows,
    required this.range,
    required this.projects,
    required this.dayWidth,
    required this.rowHeight,
    required this.groupRowHeight,
  });

  final List<_TimelineRowData> rows;
  final _TimelineRange range;
  final Map<String, Project> projects;
  final double dayWidth;
  final double rowHeight;
  final double groupRowHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final rowIndexByTaskId = <String, int>{};
    for (var index = 0; index < rows.length; index++) {
      final task = rows[index].task;
      if (task != null) rowIndexByTaskId[task.taskId] = index;
    }

    for (var targetIndex = 0; targetIndex < rows.length; targetIndex++) {
      final target = rows[targetIndex].task;
      if (target == null || target.dependencyTaskIds.isEmpty) continue;
      for (final predecessorId in target.dependencyTaskIds) {
        final sourceIndex = rowIndexByTaskId[predecessorId];
        if (sourceIndex == null) continue;
        final source = rows[sourceIndex].task;
        if (source == null) continue;

        final targetStart = _taskStartDate(target, projects);
        if (!range.contains(source.dueDate) || !range.contains(targetStart)) continue;
        final sourceY = _rowCenterY(sourceIndex);
        final targetY = _rowCenterY(targetIndex);
        final sourceX = (range.indexOf(source.dueDate) + 1) * dayWidth - 5;
        final targetX = range.indexOf(targetStart) * dayWidth + 5;
        final isCritical = _isCriticalConnector(source, target) ||
            source.riskLevel == 'critical' ||
            target.riskLevel == 'critical';
        final color = isCritical ? const Color(0xFFEF4444) : const Color(0xFF0F9F91);
        final paint = Paint()
          ..color = color
          ..strokeWidth = isCritical ? 2.4 : 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        final arrowPaint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        final bendX = math.max(sourceX + 16, (sourceX + targetX) / 2);
        final path = Path()
          ..moveTo(sourceX, sourceY)
          ..lineTo(bendX, sourceY)
          ..lineTo(bendX, targetY)
          ..lineTo(targetX, targetY);
        canvas.drawPath(path, paint);
        canvas.drawCircle(Offset(sourceX, sourceY), 3, arrowPaint);
        canvas.drawPath(
          Path()
            ..moveTo(targetX, targetY)
            ..lineTo(targetX - 8, targetY - 5)
            ..lineTo(targetX - 8, targetY + 5)
            ..close(),
          arrowPaint,
        );
      }
    }
  }

  double _rowCenterY(int targetIndex) {
    var y = 0.0;
    for (var index = 0; index < rows.length; index++) {
      final height = rows[index].isGroup ? groupRowHeight : rowHeight;
      if (index == targetIndex) return y + height / 2;
      y += height;
    }
    return y;
  }

  @override
  bool shouldRepaint(covariant _DependencyLinePainter oldDelegate) {
    return oldDelegate.rows != rows ||
        oldDelegate.range != range ||
        oldDelegate.dayWidth != dayWidth ||
        oldDelegate.rowHeight != rowHeight ||
        oldDelegate.groupRowHeight != groupRowHeight;
  }
}

class _TodayLinePainter extends CustomPainter {
  const _TodayLinePainter({required this.range, required this.dayWidth});

  final _TimelineRange range;
  final double dayWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final today = DateUtils.dateOnly(DateTime.now());
    if (!range.contains(today)) return;

    final left = range.indexOf(today) * dayWidth;
    final rect = Rect.fromLTWH(left, 0, dayWidth, size.height);

    // Light red full-cell highlight. The existing setting name and all
    // other Timeline behaviour remain unchanged.
    final fillPaint = Paint()
      ..color = const Color(0x12EF4444)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fillPaint);

    // Soft side boundaries make the current day easy to scan without the
    // strong single red line used previously.
    final edgePaint = Paint()
      ..color = const Color(0x30EF4444)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, 0), Offset(left, size.height), edgePaint);
    canvas.drawLine(Offset(left + dayWidth, 0), Offset(left + dayWidth, size.height), edgePaint);
  }

  @override
  bool shouldRepaint(covariant _TodayLinePainter oldDelegate) {
    return oldDelegate.range != range || oldDelegate.dayWidth != dayWidth;
  }
}

class _TimelineGrid extends StatelessWidget {
  const _TimelineGrid({required this.dayWidth});
  final double dayWidth;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _TimelineGridPainter(dayWidth), child: const SizedBox.expand());
}

class _TimelineGridPainter extends CustomPainter {
  const _TimelineGridPainter(this.dayWidth);
  final double dayWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = const Color(0xFFE2E8F0)..strokeWidth = 1;
    final weekend = Paint()..color = const Color(0xFFFAFAFA);
    for (double x = 0; x <= size.width; x += dayWidth) {
      final index = (x / dayWidth).round();
      if (index % 7 == 0 || index % 7 == 6) canvas.drawRect(Rect.fromLTWH(x, 0, dayWidth, size.height), weekend);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), line);
  }

  @override
  bool shouldRepaint(covariant _TimelineGridPainter oldDelegate) => oldDelegate.dayWidth != dayWidth;
}

class _BaselineStripePainter extends CustomPainter {
  const _BaselineStripePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = color.withOpacity(.35);
    final stripe = Paint()..color = color;
    final rect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas.drawRRect(rect, base);
    canvas.save();
    canvas.clipRRect(rect);
    for (double x = -size.height; x < size.width + size.height; x += 10) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), stripe..strokeWidth = 2);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BaselineStripePainter oldDelegate) => oldDelegate.color != color;
}

class _AssigneeDots extends StatelessWidget {
  const _AssigneeDots({required this.members});
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final visible = members.take(3).toList();
    if (visible.isEmpty) return const Text('Unassigned', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w800, fontSize: 12));
    return SizedBox(
      height: 30,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * 22,
              child: Tooltip(
                message: visible[i].displayName,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: visible[i].role.color.withOpacity(.18),
                  child: Text(_initial(visible[i].displayName), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: visible[i].role.color)),
                ),
              ),
            ),
          if (members.length > 3)
            Positioned(left: visible.length * 22, child: CircleAvatar(radius: 14, backgroundColor: const Color(0xFFE2E8F0), child: Text('+${members.length - 3}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)))),
        ],
      ),
    );
  }
}

class _InlineProgress extends StatelessWidget {
  const _InlineProgress({required this.value, required this.isGroup, this.compact = false});
  final int value;
  final bool isGroup;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(999)),
            clipBehavior: Clip.antiAlias,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (value / 100).clamp(0.0, 1.0).toDouble(),
              child: Container(color: isGroup ? const Color(0xFF64748B) : const Color(0xFF334155)),
            ),
          ),
        ),
        SizedBox(width: compact ? 5 : 8),
        SizedBox(width: compact ? 34 : 44, child: Text('$value%', maxLines: 1, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, color: const Color(0xFF334155), fontSize: compact ? 10 : 12))),
      ],
    );
  }
}

class _AccessSummaryCard extends StatelessWidget {
  const _AccessSummaryCard({required this.member, required this.canEdit});
  final Member member;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final color = canEdit ? const Color(0xFF15803D) : const Color(0xFF2563EB);
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFDCE6F3))),
      child: Row(
          children: [
            CircleAvatar(radius: 19, backgroundColor: color.withOpacity(.10), child: Icon(canEdit ? Icons.edit_calendar_rounded : Icons.visibility_rounded, color: color, size: 19)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(canEdit ? 'Can Edit Schedule' : 'View Only Timeline', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
                  Text('${member.displayName} • ${member.role.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
  }
}

class _MiniMetricCard extends StatelessWidget {
  const _MiniMetricCard({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFDCE6F3))),
      child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A))),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
  }
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({required this.icon, required this.label, this.badge});
  final IconData icon;
  final String label;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0F172A)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155))),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(999)),
              child: Text(badge!, style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w900, fontSize: 10)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: active ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(7), border: Border.all(color: active ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: active ? const Color(0xFF2563EB) : const Color(0xFF334155)),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(fontWeight: FontWeight.w900, color: active ? const Color(0xFF2563EB) : const Color(0xFF334155))),
          ],
        ),
      ),
    );
  }
}

class _IconToolbarButton extends StatelessWidget {
  const _IconToolbarButton({required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Icon(icon, size: 20, color: const Color(0xFF0F172A)),
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.label, required this.scale});
  final String label;
  final _TimelineScale scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155))),
          const SizedBox(width: 10),
          Text(_scaleLabel(scale), style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800, fontSize: 12)),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
        ],
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timeline_rounded, color: Color(0xFF94A3B8), size: 48),
          SizedBox(height: 12),
          Text('No timeline work items found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          SizedBox(height: 6),
          Text('Realtime project/task data will appear here after Firestore sync.'),
        ],
      ),
    );
  }
}

class _TimelineRowData {
  const _TimelineRowData({
    required this.id,
    required this.number,
    required this.title,
    required this.depth,
    required this.progress,
    required this.taskCount,
    this.task,
    this.startDate,
    this.endDate,
    this.originalStartDate,
    this.originalEndDate,
    this.groupIcon = Icons.folder_rounded,
    this.groupColor = const Color(0xFF2563EB),
  });

  final String id;
  final String number;
  final String title;
  final int depth;
  final int progress;
  final int taskCount;
  final ProjectTask? task;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? originalStartDate;
  final DateTime? originalEndDate;
  final IconData groupIcon;
  final Color groupColor;

  bool get isGroup => task == null;
  bool get isProjectGroup =>
      isGroup && originalStartDate != null && originalEndDate != null;
  IconData get taskIcon {
    final item = task;
    if (item == null) return Icons.folder_rounded;
    return switch (item.status) {
      TaskStatus.backlog => Icons.bolt_outlined,
      TaskStatus.todo => Icons.check_box_outline_blank_rounded,
      TaskStatus.inProgress => Icons.sync_rounded,
      TaskStatus.review => Icons.rate_review_rounded,
      TaskStatus.testing => Icons.bug_report_rounded,
      TaskStatus.completed => Icons.check_box_rounded,
    };
  }
}

enum _TimelineScale { day, week, month, quarter }
enum _TimelineGroupMode { project, assignee, status, department }

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

_TimelineScale _scaleFromPreference(TimelineDefaultScale value) {
  return switch (value) {
    TimelineDefaultScale.day => _TimelineScale.day,
    TimelineDefaultScale.week => _TimelineScale.week,
    TimelineDefaultScale.month => _TimelineScale.month,
    TimelineDefaultScale.quarter => _TimelineScale.quarter,
  };
}

_TimelineGroupMode _groupModeFromPreference(
  TimelineDefaultGrouping value,
) {
  return switch (value) {
    TimelineDefaultGrouping.project => _TimelineGroupMode.project,
    TimelineDefaultGrouping.assignee => _TimelineGroupMode.assignee,
    TimelineDefaultGrouping.status => _TimelineGroupMode.status,
    TimelineDefaultGrouping.department => _TimelineGroupMode.department,
  };
}

String _timelineScalePreferenceLabel(TimelineDefaultScale value) {
  return switch (value) {
    TimelineDefaultScale.day => 'Day / 2 weeks',
    TimelineDefaultScale.week => 'Week / 6 weeks',
    TimelineDefaultScale.month => 'Month / quarter',
    TimelineDefaultScale.quarter => 'Quarter / year',
  };
}

String _timelineGroupingPreferenceLabel(TimelineDefaultGrouping value) {
  return switch (value) {
    TimelineDefaultGrouping.project => 'Project',
    TimelineDefaultGrouping.assignee => 'Assignee',
    TimelineDefaultGrouping.status => 'Status',
    TimelineDefaultGrouping.department => 'Department',
  };
}

class _TimelineRange {
  const _TimelineRange({required this.days, required this.scale});

  final List<DateTime> days;
  final _TimelineScale scale;

  static _TimelineRange fromTasks(
    List<ProjectTask> tasks,
    Map<String, Project> projects,
    _TimelineScale scale,
    DateTime focusDate, {
    bool includeOriginalProjectPlan = false,
    bool autoFitOriginalProjectPlan = false,
  }) {
    final normalizedFocus = _dateOnly(focusDate);
    late DateTime baseStart;
    late DateTime baseEnd;

    switch (scale) {
      case _TimelineScale.day:
        baseStart = normalizedFocus.subtract(const Duration(days: 3));
        baseEnd = baseStart.add(const Duration(days: 13));
        break;
      case _TimelineScale.week:
        baseStart =
            _startOfWeek(normalizedFocus).subtract(const Duration(days: 7));
        baseEnd = baseStart.add(const Duration(days: 41));
        break;
      case _TimelineScale.month:
        baseStart = DateTime(
          normalizedFocus.year,
          normalizedFocus.month - 1,
          1,
        );
        baseEnd = DateTime(
          normalizedFocus.year,
          normalizedFocus.month + 3,
          0,
        );
        break;
      case _TimelineScale.quarter:
        final quarterStartMonth =
            ((normalizedFocus.month - 1) ~/ 3) * 3 + 1;
        baseStart = DateTime(
          normalizedFocus.year,
          quarterStartMonth - 3,
          1,
        );
        baseEnd = DateTime(
          normalizedFocus.year,
          quarterStartMonth + 9,
          0,
        );
        break;
    }

    var start = baseStart;
    var end = baseEnd;

    if (autoFitOriginalProjectPlan) {
      final starts = <DateTime>[];
      final ends = <DateTime>[];

      for (final task in tasks) {
        starts.add(_taskStartDate(task, projects));
        ends.add(_dateOnly(task.dueDate));
      }

      if (includeOriginalProjectPlan) {
        for (final project in projects.values) {
          starts.add(_dateOnly(project.startDate));
          ends.add(_dateOnly(project.dueDate));
        }
      }

      if (starts.isNotEmpty && ends.isNotEmpty) {
        starts.sort();
        ends.sort();
        final paddingDays = switch (scale) {
          _TimelineScale.day => 2,
          _TimelineScale.week => 7,
          _TimelineScale.month => 14,
          _TimelineScale.quarter => 30,
        };
        final dataStart = starts.first.subtract(Duration(days: paddingDays));
        final dataEnd = ends.last.add(Duration(days: paddingDays));
        if (dataStart.isBefore(start)) start = dataStart;
        if (dataEnd.isAfter(end)) end = dataEnd;
      }
    }

    // Prevent malformed or extremely old Firestore dates from constructing a
    // multi-thousand-column Gantt canvas. The selected/focus date remains in
    // the retained window while normal project plans are shown in full.
    final maximumDays = switch (scale) {
      _TimelineScale.day => 180,
      _TimelineScale.week => 550,
      _TimelineScale.month => 900,
      _TimelineScale.quarter => 1100,
    };
    var length = end.difference(start).inDays + 1;
    if (length > maximumDays) {
      final half = maximumDays ~/ 2;
      start = normalizedFocus.subtract(Duration(days: half));
      end = start.add(Duration(days: maximumDays - 1));
      length = maximumDays;
    }
    length = math.max(1, length);

    return _TimelineRange(
      scale: scale,
      days: List<DateTime>.generate(
        length,
        (index) => start.add(Duration(days: index)),
      ),
    );
  }

  DateTime get start => days.first;
  DateTime get end => days.last;

  int indexOf(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.difference(start).inDays.clamp(0, math.max(0, days.length - 1)).toInt();
  }

  bool contains(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return !normalized.isBefore(days.first) && !normalized.isAfter(days.last);
  }
}

List<_TimelineRowData> _timelineRowsForMode({required WorkspaceState state, required List<ProjectTask> tasks, required Map<String, Project> projects, required _TimelineGroupMode mode, bool includeOriginalProjectPlan = true}) {
  switch (mode) {
    case _TimelineGroupMode.project:
      return _projectGroupedRows(
        tasks,
        projects,
        includeOriginalProjectPlan: includeOriginalProjectPlan,
      );
    case _TimelineGroupMode.assignee:
      return _assigneeGroupedRows(state, tasks, projects);
    case _TimelineGroupMode.status:
      return _statusGroupedRows(tasks, projects);
    case _TimelineGroupMode.department:
      return _departmentGroupedRows(state, tasks, projects);
  }
}


List<_TimelineRowData> _visibleTimelineRows(List<_TimelineRowData> rows, Set<String> collapsedGroupIds) {
  final output = <_TimelineRowData>[];
  var hideChildren = false;
  for (final row in rows) {
    if (row.isGroup) {
      hideChildren = collapsedGroupIds.contains(row.id);
      output.add(row);
      continue;
    }
    if (!hideChildren) output.add(row);
  }
  return output;
}

String _selectedProjectLabel(List<Project> projects, String selectedProjectId) {
  for (final project in projects) {
    if (project.projectId == selectedProjectId) return project.name;
  }
  return 'Project Selected';
}

String _groupModeLabel(_TimelineGroupMode mode) {
  return switch (mode) {
    _TimelineGroupMode.project => 'Project',
    _TimelineGroupMode.assignee => 'Assignee',
    _TimelineGroupMode.status => 'Status',
    _TimelineGroupMode.department => 'Department',
  };
}

List<_TimelineRowData> _projectGroupedRows(
  List<ProjectTask> tasks,
  Map<String, Project> projects, {
  required bool includeOriginalProjectPlan,
}) {
  final grouped = <String, List<ProjectTask>>{};
  for (final task in tasks) {
    grouped.putIfAbsent(task.projectId, () => <ProjectTask>[]).add(task);
  }

  final projectIds = <String>{...grouped.keys};
  if (includeOriginalProjectPlan) {
    projectIds.addAll(projects.keys);
  }
  final sortedProjectIds = projectIds.toList()
    ..sort(
      (a, b) =>
          _projectName(projects, a).compareTo(_projectName(projects, b)),
    );

  final rows = <_TimelineRowData>[];
  var projectNumber = 1;
  for (final projectId in sortedProjectIds) {
    final project = projects[projectId];
    final list = List<ProjectTask>.from(
      grouped[projectId] ?? const <ProjectTask>[],
    )..sort(
        (a, b) => _taskStartDate(a, projects).compareTo(
          _taskStartDate(b, projects),
        ),
      );

    if (project == null && list.isEmpty) continue;

    rows.add(
      _TimelineRowData(
        id: 'project-$projectId',
        number: '$projectNumber',
        title: project?.name ??
            (projectId.trim().isEmpty
                ? 'Unassigned project'
                : 'Project $projectId'),
        depth: 0,
        progress: list.isEmpty
            ? (project?.progress ?? 0).clamp(0, 100).toInt()
            : _averageProgress(list),
        taskCount: list.length,
        startDate: _groupStart(list, projects),
        endDate: _groupEnd(list),
        originalStartDate: project?.startDate,
        originalEndDate: project?.dueDate,
        groupIcon: Icons.workspaces_rounded,
        groupColor: project?.status.color ?? const Color(0xFF2563EB),
      ),
    );

    for (var i = 0; i < list.length; i++) {
      final task = list[i];
      rows.add(
        _TimelineRowData(
          id: task.taskId,
          number: '$projectNumber.${i + 1}',
          title: task.title,
          depth: 1,
          progress: _taskProgress(task),
          taskCount: 1,
          task: task,
          startDate: _taskStartDate(task, projects),
          endDate: task.dueDate,
        ),
      );
    }
    projectNumber++;
  }
  return rows;
}

List<_TimelineRowData> _assigneeGroupedRows(WorkspaceState state, List<ProjectTask> tasks, Map<String, Project> projects) {
  final grouped = <String, List<ProjectTask>>{};
  for (final task in tasks) {
    final key = task.assignedToIds.isEmpty ? 'unassigned' : task.assignedToIds.first;
    grouped.putIfAbsent(key, () => <ProjectTask>[]).add(task);
  }
  final rows = <_TimelineRowData>[];
  var groupNumber = 1;
  for (final entry in grouped.entries) {
    final member = _memberById(state, entry.key);
    final title = member?.displayName ?? 'Unassigned';
    final list = entry.value..sort((a, b) => _taskStartDate(a, projects).compareTo(_taskStartDate(b, projects)));
    rows.add(_TimelineRowData(id: 'assignee-${entry.key}', number: '$groupNumber', title: title, depth: 0, progress: _averageProgress(list), taskCount: list.length, startDate: _groupStart(list, projects), endDate: _groupEnd(list), groupIcon: Icons.person_rounded, groupColor: member?.role.color ?? const Color(0xFF64748B)));
    for (var i = 0; i < list.length; i++) {
      final task = list[i];
      rows.add(_TimelineRowData(id: task.taskId, number: '$groupNumber.${i + 1}', title: task.title, depth: 1, progress: _taskProgress(task), taskCount: 1, task: task, startDate: _taskStartDate(task, projects), endDate: task.dueDate));
    }
    groupNumber++;
  }
  return rows;
}

List<_TimelineRowData> _departmentGroupedRows(WorkspaceState state, List<ProjectTask> tasks, Map<String, Project> projects) {
  final grouped = <String, List<ProjectTask>>{};
  for (final task in tasks) {
    final departments = task.assignedToIds
        .map((uid) => _memberById(state, uid)?.effectiveDepartment.trim() ?? '')
        .where((department) => department.isNotEmpty)
        .toSet();
    final key = departments.isEmpty ? 'Unassigned department' : departments.first;
    grouped.putIfAbsent(key, () => <ProjectTask>[]).add(task);
  }
  final entries = grouped.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  final rows = <_TimelineRowData>[];
  var groupNumber = 1;
  for (final entry in entries) {
    final list = entry.value..sort((a, b) => _taskStartDate(a, projects).compareTo(_taskStartDate(b, projects)));
    final color = _departmentColor(entry.key);
    rows.add(_TimelineRowData(
      id: 'department-${entry.key.toLowerCase().replaceAll(' ', '-')}',
      number: '$groupNumber',
      title: entry.key,
      depth: 0,
      progress: _averageProgress(list),
      taskCount: list.length,
      startDate: _groupStart(list, projects),
      endDate: _groupEnd(list),
      groupIcon: Icons.apartment_rounded,
      groupColor: color,
    ));
    for (var i = 0; i < list.length; i++) {
      final task = list[i];
      rows.add(_TimelineRowData(
        id: task.taskId,
        number: '$groupNumber.${i + 1}',
        title: task.title,
        depth: 1,
        progress: _taskProgress(task),
        taskCount: 1,
        task: task,
        startDate: _taskStartDate(task, projects),
        endDate: task.dueDate,
      ));
    }
    groupNumber++;
  }
  return rows;
}

Color _departmentColor(String department) {
  const palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF0F9F91),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFFDC2626),
  ];
  final seed = department.codeUnits.fold<int>(0, (sum, value) => sum + value);
  return palette[seed % palette.length];
}

List<_TimelineRowData> _statusGroupedRows(List<ProjectTask> tasks, Map<String, Project> projects) {
  final rows = <_TimelineRowData>[];
  var groupNumber = 1;
  for (final status in TaskStatus.values) {
    final list = tasks.where((task) => task.status == status).toList()..sort((a, b) => _taskStartDate(a, projects).compareTo(_taskStartDate(b, projects)));
    if (list.isEmpty) continue;
    rows.add(_TimelineRowData(id: 'status-${status.value}', number: '$groupNumber', title: status.label, depth: 0, progress: _averageProgress(list), taskCount: list.length, startDate: _groupStart(list, projects), endDate: _groupEnd(list), groupIcon: Icons.label_rounded, groupColor: status.color));
    for (var i = 0; i < list.length; i++) {
      final task = list[i];
      rows.add(_TimelineRowData(id: task.taskId, number: '$groupNumber.${i + 1}', title: task.title, depth: 1, progress: _taskProgress(task), taskCount: 1, task: task, startDate: _taskStartDate(task, projects), endDate: task.dueDate));
    }
    groupNumber++;
  }
  return rows;
}

DateTime? _groupStart(List<ProjectTask> tasks, Map<String, Project> projects) {
  if (tasks.isEmpty) return null;
  final starts = tasks.map((task) => _taskStartDate(task, projects)).toList()..sort();
  return starts.first;
}

DateTime? _groupEnd(List<ProjectTask> tasks) {
  if (tasks.isEmpty) return null;
  final ends = tasks.map((task) => task.dueDate).toList()..sort();
  return ends.last;
}

int _averageProgress(List<ProjectTask> tasks) => tasks.isEmpty ? 0 : (tasks.fold<int>(0, (sum, task) => sum + _taskProgress(task)) / tasks.length).round();

DateTime _taskStartDate(ProjectTask task, Map<String, Project> projects) {
  final projectStart = projects[task.projectId]?.startDate;
  final raw = task.startDate ?? task.createdAt ?? projectStart ?? task.dueDate.subtract(const Duration(days: 2));
  return DateTime(raw.year, raw.month, raw.day);
}

bool _matchesTimelineSearch(WorkspaceState state, ProjectTask task, Map<String, Project> projects, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  final projectName = projects[task.projectId]?.name ?? '';
  final assignees = _membersForTask(state, task).map((member) => member.displayName).join(' ');
  final haystack = '${task.title} ${task.description} $projectName $assignees ${task.status.label} ${task.priority.label}'.toLowerCase();
  return haystack.contains(q);
}

bool _rowMatchesSearch(WorkspaceState state, _TimelineRowData row, Map<String, Project> projects, String query) {
  final task = row.task;
  if (task != null) return _matchesTimelineSearch(state, task, projects, query);
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  return row.title.toLowerCase().contains(q);
}

String _projectName(Map<String, Project> projects, String projectId) => projects[projectId]?.name.toLowerCase() ?? projectId.toLowerCase();

int _taskProgress(ProjectTask task) {
  final explicit = task.progressPercent;
  if (explicit != null) return explicit.clamp(0, 100).toInt();
  return switch (task.status) {
    TaskStatus.backlog => 0,
    TaskStatus.todo => 15,
    TaskStatus.inProgress => 55,
    TaskStatus.review => 75,
    TaskStatus.testing => 90,
    TaskStatus.completed => 100,
  };
}

Color _colorForTask(ProjectTask task) {
  if (task.isOverdue) return const Color(0xFFEF4444);
  if (task.priority == TaskPriority.critical) return const Color(0xFFF97316);

  // Taskford-style view: avoid every completed task becoming the same green bar.
  // Status still influences the palette, but the task id/title creates variation
  // so parallel work items are easier to distinguish visually.
  const palette = <Color>[
    Color(0xFF2563EB), // blue
    Color(0xFF10B981), // emerald
    Color(0xFF7C3AED), // violet
    Color(0xFFF59E0B), // amber
    Color(0xFF06B6D4), // cyan
    Color(0xFFEC4899), // pink
    Color(0xFF14B8A6), // teal
    Color(0xFF6366F1), // indigo
  ];

  final seed = (task.taskId.isEmpty ? task.title : task.taskId).codeUnits.fold<int>(0, (sum, unit) => sum + unit);
  final offset = switch (task.status) {
    TaskStatus.backlog => 0,
    TaskStatus.todo => 1,
    TaskStatus.inProgress => 2,
    TaskStatus.review => 3,
    TaskStatus.testing => 4,
    TaskStatus.completed => 5,
  };
  return palette[(seed + offset) % palette.length];
}

bool _wouldCreateDependencyCycle({
  required String targetTaskId,
  required String predecessorTaskId,
  required List<ProjectTask> tasks,
}) {
  if (targetTaskId == predecessorTaskId) return true;
  final dependenciesByTask = <String, List<String>>{
    for (final task in tasks) task.taskId: task.dependencyTaskIds,
  };
  final visited = <String>{};
  final stack = <String>[predecessorTaskId];

  while (stack.isNotEmpty) {
    final current = stack.removeLast();
    if (!visited.add(current)) continue;
    if (current == targetTaskId) return true;
    for (final dependencyId in dependenciesByTask[current] ?? const <String>[]) {
      if (!visited.contains(dependencyId)) stack.add(dependencyId);
    }
  }
  return false;
}

bool _isCriticalConnector(ProjectTask a, ProjectTask b) {
  if (a.isOverdue || b.isOverdue) return true;
  if (a.priority == TaskPriority.critical || b.priority == TaskPriority.critical) return true;
  if (a.priority == TaskPriority.high && b.priority == TaskPriority.high) return true;
  return a.dueDate.isAfter(b.startDate ?? b.dueDate.subtract(const Duration(days: 2)));
}

DateTime _startOfWeek(DateTime date) => DateTime(date.year, date.month, date.day).subtract(Duration(days: date.weekday - 1));

DateTime _shiftFocus(DateTime date, _TimelineScale scale, int direction) {
  return switch (scale) {
    _TimelineScale.day => date.add(Duration(days: 7 * direction)),
    _TimelineScale.week => date.add(Duration(days: 7 * direction)),
    _TimelineScale.month => DateTime(date.year, date.month + direction, math.min(date.day, 28)),
    _TimelineScale.quarter => DateTime(date.year, date.month + (3 * direction), math.min(date.day, 28)),
  };
}

String _rangeLabel(_TimelineScale scale, DateTime focusDate) {
  final range = _TimelineRange.fromTasks(const <ProjectTask>[], const <String, Project>{}, scale, focusDate);
  return '${DateText.compact(range.start)}  |  ${DateText.compact(range.days.last)}';
}

String _scaleLabel(_TimelineScale scale) => switch (scale) {
  _TimelineScale.day => 'Day',
  _TimelineScale.week => 'Week',
  _TimelineScale.month => 'Month',
  _TimelineScale.quarter => 'Quarter',
};

double _estimatedDayWidth(_TimelineScale scale, double viewportWidth) {
  final compact = viewportWidth < 980;
  final veryCompact = viewportWidth < 720;
  return switch (scale) {
    _TimelineScale.day => veryCompact ? 42.0 : compact ? 50.0 : 62.0,
    _TimelineScale.week => veryCompact ? 34.0 : compact ? 38.0 : 46.0,
    _TimelineScale.month => veryCompact ? 18.0 : compact ? 22.0 : 26.0,
    _TimelineScale.quarter => veryCompact ? 9.0 : compact ? 11.0 : 13.0,
  };
}

String _monthShort(DateTime day) => const <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][day.month - 1];

class _TimelineHeaderPeriod {
  const _TimelineHeaderPeriod({required this.start, required this.dayCount, required this.label});
  final DateTime start;
  final int dayCount;
  final String label;
}

List<_TimelineHeaderPeriod> _timelineHeaderPeriods(_TimelineRange range) {
  if (range.scale == _TimelineScale.day || range.scale == _TimelineScale.week) {
    final starts = _weekStarts(range.days);
    return <_TimelineHeaderPeriod>[
      for (var index = 0; index < starts.length; index++)
        _TimelineHeaderPeriod(
          start: starts[index],
          dayCount: index + 1 < starts.length
              ? starts[index + 1].difference(starts[index]).inDays
              : range.days.last.difference(starts[index]).inDays + 1,
          label: range.scale == _TimelineScale.day
              ? '${_monthShort(starts[index])} ${starts[index].day}'
              : 'Week ${_weekNumber(starts[index])} • ${_monthShort(starts[index])} \'${starts[index].year.toString().substring(2)}',
        ),
    ];
  }
  final starts = range.days.where((day) => day.day == 1).toList();
  if (starts.isEmpty || !_sameDay(starts.first, range.days.first)) starts.insert(0, range.days.first);
  return <_TimelineHeaderPeriod>[
    for (var index = 0; index < starts.length; index++)
      _TimelineHeaderPeriod(
        start: starts[index],
        dayCount: index + 1 < starts.length
            ? starts[index + 1].difference(starts[index]).inDays
            : range.days.last.difference(starts[index]).inDays + 1,
        label: '${_monthShort(starts[index])} ${starts[index].year}',
      ),
  ];
}

String _timelineDayLabel(_TimelineScale scale, DateTime day, double dayWidth) {
  if (scale == _TimelineScale.quarter) {
    if (day.day == 1) return '1';
    if (day.day == 15) return '15';
    return '';
  }
  if (scale == _TimelineScale.month && dayWidth < 20 && day.day.isEven) return '';
  return '${day.day}';
}

int _weekNumber(DateTime date) {
  final firstDay = DateTime(date.year, 1, 1);
  return ((date.difference(firstDay).inDays + firstDay.weekday) / 7).ceil();
}

List<DateTime> _weekStarts(List<DateTime> days) {
  final output = <DateTime>[];
  for (final day in days) {
    if (day.weekday == DateTime.monday || output.isEmpty) output.add(day);
  }
  return output;
}

List<DateTime> _importantDates(List<DateTime> days) {
  if (days.isEmpty) return const <DateTime>[];
  final output = <DateTime>[];
  for (var i = 6; i < days.length; i += 8) {
    output.add(days[i]);
  }
  return output.take(8).toList();
}

bool _isWeekend(DateTime day) => day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _initial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.substring(0, 1).toUpperCase();
}

List<Member> _membersForTask(WorkspaceState state, ProjectTask task) {
  final members = <Member>[];
  for (final id in task.assignedToIds) {
    for (final member in state.members) {
      if (member.uid == id) {
        members.add(member);
        break;
      }
    }
  }
  return members;
}

Member? _memberById(WorkspaceState state, String id) {
  for (final member in state.members) {
    if (member.uid == id) return member;
  }
  return null;
}

String _csv(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
