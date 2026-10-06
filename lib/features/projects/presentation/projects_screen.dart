import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_surface.dart';
import '../../../app/app_theme.dart';
import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/mobile_ui_config.dart';
import '../../../data/models/project.dart';
import 'project_details_screen.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final useMobileSdui = ref.watch(useMobileServerDrivenUiProvider);
    final currentMember = state.currentMember;
    final canCreate = PermissionService.canManageProjects(currentMember);
    final canEdit = PermissionService.canEditProject(currentMember);
    final projects = _filterProjects(state.visibleProjects, state, _query);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Projects',
            subtitle: 'Searchable project portfolio with 3-card desktop layout, live task progress, stage controls, and quick details access.',
            trailing: FilledButton.icon(
              onPressed: canCreate ? () => _showProjectDialog(context, ref) : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Project'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProjectSearchBar(
                  controller: _searchController,
                  resultCount: projects.length,
                  totalCount: state.visibleProjects.length,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  onClear: () => setState(() {
                    _searchController.clear();
                    _query = '';
                  }),
                ),
                const SizedBox(height: 18),
                if (projects.isEmpty)
                  const _EmptyProjectsCard()
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = _gridCountForWidth(constraints.maxWidth);
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: projects.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: crossAxisCount == 1 ? 1.75 : 1.08,
                        ),
                        itemBuilder: (context, index) {
                          final project = projects[index];
                          final metrics = _projectMetrics(project, state);
                          return _ProjectGridCard(
                            project: project,
                            metrics: metrics,
                            projectCardFields: useMobileSdui ? state.mobileUiConfig.projectCardFields : MobileUiConfig.allowedProjectCardFields,
                            compactMode: useMobileSdui && state.mobileUiConfig.compactMode,
                            canEdit: canEdit,
                            canArchive: canCreate,
                            onOpen: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ProjectDetailsScreen(projectId: project.projectId)),
                            ),
                            onStatus: (status) => ref.read(workspaceProvider.notifier).updateProjectStatus(project.projectId, status),
                            onArchive: () => ref.read(workspaceProvider.notifier).archiveProject(project.projectId),
                          );
                        },
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static int _gridCountForWidth(double width) {
    if (width >= 1120) return 3;
    if (width >= 720) return 2;
    return 1;
  }

  static List<Project> _filterProjects(List<Project> projects, WorkspaceState state, String query) {
    if (query.isEmpty) return projects;
    final normalized = query.toLowerCase();
    return projects.where((project) {
      final teamNames = state.teams.where((team) => project.teamIds.contains(team.teamId)).map((team) => team.name).join(' ');
      final managerNames = state.members.where((member) => project.managerIds.contains(member.uid)).map((member) => member.displayName).join(' ');
      final searchable = [
        project.name,
        project.description,
        project.status.label,
        project.priority.label,
        teamNames,
        managerNames,
      ].join(' ').toLowerCase();
      return searchable.contains(normalized);
    }).toList();
  }

  static _ProjectMetrics _projectMetrics(Project project, WorkspaceState state) {
    final tasks = state.visibleTasks.where((task) => task.projectId == project.projectId).toList();
    final completedTasks = tasks.where((task) => task.status == TaskStatus.completed).length;
    final overdueTasks = tasks.where((task) => task.isOverdue).length;
    final progress = tasks.isEmpty ? project.progress.clamp(0, 100) : ((completedTasks / tasks.length) * 100).round().clamp(0, 100);

    final teamMemberIds = <String>{};
    for (final team in state.teams.where((team) => project.teamIds.contains(team.teamId))) {
      teamMemberIds.addAll(team.memberIds);
    }
    teamMemberIds.addAll(project.managerIds);
    for (final task in tasks) {
      teamMemberIds.addAll(task.assignedToIds);
    }

    return _ProjectMetrics(
      taskCount: tasks.length,
      completedTasks: completedTasks,
      overdueTasks: overdueTasks,
      memberCount: teamMemberIds.length,
      progress: progress,
    );
  }

  Future<void> _showProjectDialog(BuildContext context, WidgetRef ref) async {
    final state = ref.read(workspaceProvider);
    final name = TextEditingController();
    final description = TextEditingController();
    final budget = TextEditingController(text: '250000');
    TaskPriority priority = TaskPriority.medium;
    DateTime dueDate = DateTime.now().add(const Duration(days: 30));
    final selectedTeamIds = <String>{};
    final selectedManagerIds = <String>{state.user.uid};
    final managerOptions = state.activePortalMembers.where((member) => [UserRole.admin, UserRole.itAdmin, UserRole.projectManager, UserRole.teamLead].contains(member.role)).toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create project'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Project name')),
                  const SizedBox(height: 12),
                  TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
                  const SizedBox(height: 12),
                  TextField(controller: budget, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Budget')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<TaskPriority>(
                    initialValue: priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: TaskPriority.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
                    onChanged: (value) => setState(() => priority = value ?? priority),
                  ),
                  const SizedBox(height: 12),
                  const Text('Assign teams', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: state.teams.map((team) {
                      final selected = selectedTeamIds.contains(team.teamId);
                      return FilterChip(
                        selected: selected,
                        label: Text(team.name),
                        onSelected: (value) => setState(() => value ? selectedTeamIds.add(team.teamId) : selectedTeamIds.remove(team.teamId)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('Project managers / leads', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: managerOptions.map((member) {
                      final selected = selectedManagerIds.contains(member.uid);
                      return FilterChip(
                        selected: selected,
                        label: Text('${member.displayName} • ${member.role.shortLabel}'),
                        onSelected: (value) => setState(() => value ? selectedManagerIds.add(member.uid) : selectedManagerIds.remove(member.uid)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Due date'),
                    subtitle: Text(DateText.compact(dueDate)),
                    trailing: const Icon(Icons.calendar_month_rounded),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 900)),
                        initialDate: dueDate,
                      );
                      if (picked != null) setState(() => dueDate = picked);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                ref.read(workspaceProvider.notifier).createProject(
                      name: name.text,
                      description: description.text.isEmpty ? 'No description provided.' : description.text,
                      dueDate: dueDate,
                      priority: priority,
                      budget: num.tryParse(budget.text) ?? 0,
                      teamIds: selectedTeamIds.toList(),
                      managerIds: selectedManagerIds.toList(),
                    );
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectSearchBar extends StatelessWidget {
  const _ProjectSearchBar({
    required this.controller,
    required this.resultCount,
    required this.totalCount,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final int resultCount;
  final int totalCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardAlt,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: controller.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClear),
                hintText: 'Search project name, status, priority, team, or manager',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
            child: Text('$resultCount / $totalCount projects', style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _ProjectGridCard extends StatelessWidget {
  const _ProjectGridCard({
    required this.project,
    required this.metrics,
    required this.projectCardFields,
    required this.compactMode,
    required this.canEdit,
    required this.canArchive,
    required this.onOpen,
    required this.onStatus,
    required this.onArchive,
  });

  final Project project;
  final _ProjectMetrics metrics;
  final List<String> projectCardFields;
  final bool compactMode;
  final bool canEdit;
  final bool canArchive;
  final VoidCallback onOpen;
  final ValueChanged<ProjectStatus> onStatus;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final status = project.status;
    final progress = metrics.progress.clamp(0, 100) / 100;
    final initial = project.name.trim().isEmpty ? 'P' : project.name.trim().substring(0, 1).toUpperCase();
    final showProjectName = projectCardFields.contains('projectName');
    final showTaskCount = projectCardFields.contains('taskCount');
    final showProgress = projectCardFields.contains('progress');
    final showDeadline = projectCardFields.contains('deadline');
    final showStatus = projectCardFields.contains('status');
    final showTeam = projectCardFields.contains('team');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(compactMode ? 14 : 18),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 22, offset: const Offset(0, 12)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: status.color.withOpacity(.10),
                    foregroundColor: status.color,
                    child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: 'Project actions',
                    onSelected: (value) {
                      if (value == 'open') onOpen();
                      if (value == 'planning') onStatus(ProjectStatus.planning);
                      if (value == 'active') onStatus(ProjectStatus.active);
                      if (value == 'hold') onStatus(ProjectStatus.onHold);
                      if (value == 'review') onStatus(ProjectStatus.review);
                      if (value == 'completed') onStatus(ProjectStatus.completed);
                      if (value == 'archive') onArchive();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'open', child: Text('Open details')),
                      if (canEdit) const PopupMenuDivider(),
                      if (canEdit) const PopupMenuItem(value: 'planning', child: Text('Move to Planning')),
                      if (canEdit) const PopupMenuItem(value: 'active', child: Text('Move to Active')),
                      if (canEdit) const PopupMenuItem(value: 'hold', child: Text('Move to On Hold')),
                      if (canEdit) const PopupMenuItem(value: 'review', child: Text('Move to Review')),
                      if (canEdit) const PopupMenuItem(value: 'completed', child: Text('Mark Completed')),
                      if (canArchive) const PopupMenuDivider(),
                      if (canArchive) const PopupMenuItem(value: 'archive', child: Text('Archive')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (showProjectName) ...[
                Text(
                  project.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
                ),
                const SizedBox(height: 10),
              ],
              if (showStatus || showTeam)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (showStatus) StatusBadge(label: status.label, color: status.color),
                    if (showStatus) StatusBadge(label: project.priority.label, color: project.priority.color),
                    if (showTeam) StatusBadge(label: '${metrics.memberCount} members', color: Colors.blueGrey),
                  ],
                ),
              const Spacer(),
              if (showTaskCount || showTeam)
                Row(
                  children: [
                    if (showTaskCount) _MetricPill(icon: Icons.task_alt_rounded, label: '${metrics.taskCount}', subLabel: 'Tasks'),
                    if (showTaskCount && showTeam) const SizedBox(width: 8),
                    if (showTeam) _MetricPill(icon: Icons.groups_rounded, label: '${metrics.memberCount}', subLabel: 'Members'),
                  ],
                ),
              if (showProgress) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 780),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: compactMode ? 8 : 10,
                          borderRadius: BorderRadius.circular(999),
                          color: status.color,
                          backgroundColor: status.color.withOpacity(.12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${metrics.progress}%', style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
              if (showDeadline) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${metrics.completedTasks} completed • Due ${DateText.compact(project.dueDate)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: project.isDelayed ? AppTheme.danger : AppTheme.muted, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label, required this.subLabel});

  final IconData icon;
  final String label;
  final String subLabel;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: AppTheme.cardAlt, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppTheme.blue),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w900, height: 1)),
                  const SizedBox(height: 2),
                  Text(subLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProjectsCard extends StatelessWidget {
  const _EmptyProjectsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppTheme.border)),
      child: const Column(
        children: [
          Icon(Icons.folder_off_rounded, size: 42, color: AppTheme.muted),
          SizedBox(height: 10),
          Text('No matching projects', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          SizedBox(height: 4),
          Text('Create a project or clear the search filter.'),
        ],
      ),
    );
  }
}

class _ProjectMetrics {
  const _ProjectMetrics({
    required this.taskCount,
    required this.completedTasks,
    required this.overdueTasks,
    required this.memberCount,
    required this.progress,
  });

  final int taskCount;
  final int completedTasks;
  final int overdueTasks;
  final int memberCount;
  final int progress;
}
