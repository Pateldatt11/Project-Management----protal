import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_theme.dart';
import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/task.dart';

class KanbanScreen extends ConsumerStatefulWidget {
  const KanbanScreen({super.key});

  @override
  ConsumerState<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends ConsumerState<KanbanScreen> {
  String? _projectFilter;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final canMove = PermissionService.canMoveKanban(state.currentMember);
    final visibleProjects = state.visibleProjects;
    final tasks = state.visibleTasks.where((task) => _projectFilter == null || task.projectId == _projectFilter).toList();
    final total = tasks.length;
    final completed = tasks.where((task) => task.status == TaskStatus.completed).length;
    final completion = total == 0 ? 0.0 : completed / total;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Kanban Board', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String?>(
                  initialValue: _projectFilter,
                  decoration: const InputDecoration(labelText: 'Filter project'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All visible projects')),
                    ...visibleProjects.map((project) => DropdownMenuItem<String?>(value: project.projectId, child: Text(project.name))),
                  ],
                  onChanged: (value) => setState(() => _projectFilter = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(canMove ? 'Drag tasks between stages. Project progress, dashboard charts, activity logs, audit logs, and private notifications update immediately.' : 'This role can view Kanban but cannot move tasks.'),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                Expanded(child: _KanbanMetric(label: 'Visible tasks', value: '$total', icon: Icons.view_kanban_rounded)),
                Expanded(child: _KanbanMetric(label: 'Completed', value: '$completed', icon: Icons.check_circle_rounded)),
                Expanded(child: _KanbanMetric(label: 'Progress', value: '${(completion * 100).round()}%', icon: Icons.auto_graph_rounded)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: TaskStatus.values.map((status) {
                    final columnTasks = tasks.where((task) => task.status == status).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
                    return _KanbanColumn(status: status, tasks: columnTasks, canMove: canMove);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KanbanMetric extends StatelessWidget {
  const _KanbanMetric({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: AppTheme.blue),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), Text(label, style: Theme.of(context).textTheme.bodySmall)]),
    ]);
  }
}

class _KanbanColumn extends ConsumerWidget {
  const _KanbanColumn({required this.status, required this.tasks, required this.canMove});
  final TaskStatus status;
  final List<ProjectTask> tasks;
  final bool canMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<ProjectTask>(
      onAcceptWithDetails: canMove ? (details) => ref.read(workspaceProvider.notifier).updateTaskStatus(details.data.taskId, status) : null,
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 330,
          margin: const EdgeInsets.only(right: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: candidate.isNotEmpty ? status.color.withOpacity(.12) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: candidate.isNotEmpty ? status.color : status.color.withOpacity(.22), width: candidate.isNotEmpty ? 2 : 1),
            boxShadow: candidate.isNotEmpty ? [BoxShadow(color: status.color.withOpacity(.10), blurRadius: 18, offset: const Offset(0, 10))] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: status.color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(status.label, style: const TextStyle(fontWeight: FontWeight.w900))),
                StatusBadge(label: '${tasks.length}', color: status.color),
              ]),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: tasks.map((task) => canMove
                      ? Draggable<ProjectTask>(
                          data: task,
                          feedback: Material(elevation: 12, borderRadius: BorderRadius.circular(18), child: SizedBox(width: 300, child: _TaskKanbanCard(task: task))),
                          childWhenDragging: Opacity(opacity: .35, child: _TaskKanbanCard(task: task)),
                          child: _TaskKanbanCard(task: task),
                        )
                      : _TaskKanbanCard(task: task)).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskKanbanCard extends ConsumerWidget {
  const _TaskKanbanCard({required this.task});
  final ProjectTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final project = state.projects.where((project) => project.projectId == task.projectId);
    final team = state.teams.where((team) => team.teamId == task.teamId);
    final assignees = state.members.where((member) => task.assignedToIds.contains(member.uid)).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w900))),
              Icon(Icons.drag_indicator_rounded, color: Colors.black.withOpacity(.28)),
            ]),
            const SizedBox(height: 8),
            Text(task.description, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            Text(project.isEmpty ? 'No project' : project.first.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(height: 4),
            Text('${team.isEmpty ? 'No team' : team.first.name} • ${assignees.isEmpty ? 'Unassigned' : assignees.map((m) => m.displayName).join(', ')}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              StatusBadge(label: task.priority.label, color: task.priority.color),
              StatusBadge(label: 'Due ${DateText.compact(task.dueDate)}', color: task.isOverdue ? AppTheme.danger : AppTheme.muted),
              if (task.attachmentsCount > 0) StatusBadge(label: '${task.attachmentsCount} files', color: AppTheme.blue),
              if (task.commentsCount > 0) StatusBadge(label: '${task.commentsCount} comments', color: AppTheme.violet),
            ]),
          ],
        ),
      ),
    );
  }
}
