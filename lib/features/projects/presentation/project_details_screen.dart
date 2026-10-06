import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_theme.dart';
import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/dashboard_charts.dart';
import '../../../core/widgets/progress_chip.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_badge.dart';

class ProjectDetailsScreen extends ConsumerWidget {
  const ProjectDetailsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final project = state.projects.firstWhere((p) => p.projectId == projectId);
    final currentMember = state.currentMember;
    final canEditProject = PermissionService.canEditProject(currentMember);
    final canMoveTasks = PermissionService.canMoveKanban(currentMember);
    final canViewAudit = PermissionService.canViewAuditLogs(currentMember);
    final tasks = state.visibleTasks.where((task) => task.projectId == projectId).toList();
    final attachments = state.attachments.where((item) => item.projectId == projectId).toList();
    final teams = state.teams.where((team) => project.teamIds.contains(team.teamId)).toList();
    final managers = state.members.where((member) => project.managerIds.contains(member.uid)).toList();
    final projectAudit = state.auditLogs.where((item) => item.targetId == projectId || tasks.any((task) => task.taskId == item.targetId)).take(8).toList();
    final completed = tasks.where((task) => task.status == TaskStatus.completed).length;
    final overdue = tasks.where((task) => task.isOverdue).length;
    final review = tasks.where((task) => task.status == TaskStatus.review || task.status == TaskStatus.testing).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          if (canEditProject)
            PopupMenuButton<ProjectStatus>(
              tooltip: 'Change project status',
              onSelected: (status) => ref.read(workspaceProvider.notifier).updateProjectStatus(project.projectId, status),
              itemBuilder: (_) => ProjectStatus.values.map((status) => PopupMenuItem(value: status, child: Text(status.label))).toList(),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            SectionCard(
              title: project.name,
              subtitle: project.description,
              trailing: Wrap(spacing: 8, children: [StatusBadge(label: project.status.label, color: project.status.color), ProgressChip(value: project.progress)]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: project.progress / 100),
                    duration: const Duration(milliseconds: 750),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(value: value, minHeight: 12, color: project.status.color, borderRadius: BorderRadius.circular(999)),
                  ),
                  const SizedBox(height: 8),
                  Text('${project.status.progressMeaning} • Stage-based progress uses project status + completed tasks.', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _InfoTile(label: 'Start Date', value: DateText.compact(project.startDate)),
                      _InfoTile(label: 'Due Date', value: DateText.compact(project.dueDate)),
                      _InfoTile(label: 'Budget', value: '${project.currency} ${project.budget}'),
                      _InfoTile(label: 'Tasks', value: '$completed/${tasks.length} completed'),
                      _InfoTile(label: 'Review Queue', value: '$review'),
                      _InfoTile(label: 'Overdue', value: '$overdue'),
                      _InfoTile(label: 'Managers', value: managers.isEmpty ? 'Unassigned' : managers.map((m) => m.displayName).join(', ')),
                      _InfoTile(label: 'Teams', value: teams.isEmpty ? 'No team' : teams.map((t) => t.name).join(', ')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final two = constraints.maxWidth > 900;
                final statusChart = SectionCard(
                  title: 'Task Status Mix',
                  subtitle: 'Live by task stage.',
                  child: StatusDonutChart(segments: TaskStatus.values.map((status) => StatusSegment(label: status.label, value: tasks.where((task) => task.status == status).length, color: status.color)).toList()),
                );
                final teamChart = SectionCard(
                  title: 'Team Workload',
                  subtitle: 'Open tasks by team in this project.',
                  child: ProfessionalBarChart(
                    items: teams.map((team) {
                      final count = tasks.where((task) => task.teamId == team.teamId && task.status != TaskStatus.completed).length;
                      return BarMetric(label: team.name, value: count.toDouble(), color: AppTheme.blue);
                    }).toList(),
                  ),
                );
                if (!two) return Column(children: [statusChart, const SizedBox(height: 18), teamChart]);
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: statusChart), const SizedBox(width: 18), Expanded(child: teamChart)]);
              },
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Project Tasks',
              subtitle: 'Status changes here update dashboard charts and stage-based project progress.',
              child: Column(
                children: tasks.map((task) {
                  final assignees = state.members.where((member) => task.assignedToIds.contains(member.uid)).toList();
                  final team = state.teams.where((team) => team.teamId == task.teamId);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppTheme.cardAlt, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(task.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 5),
                            Text('${team.isEmpty ? 'No team' : team.first.name} • ${assignees.isEmpty ? 'Unassigned' : assignees.map((m) => m.displayName).join(', ')} • Due ${DateText.compact(task.dueDate)}'),
                            Text('${task.commentsCount} comments • ${task.attachmentsCount} files'),
                          ]),
                        ),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusBadge(label: task.status.label, color: task.status.color),
                            StatusBadge(label: task.priority.label, color: task.priority.color),
                            if (canMoveTasks)
                              DropdownButton<TaskStatus>(
                                value: task.status,
                                underline: const SizedBox.shrink(),
                                items: TaskStatus.values.map((status) => DropdownMenuItem(value: status, child: Text(status.label))).toList(),
                                onChanged: (status) {
                                  if (status != null) ref.read(workspaceProvider.notifier).updateTaskStatus(task.taskId, status);
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Project Files',
              subtitle: 'Picked files are now securely uploaded and managed via Cloudinary.',
              child: attachments.isEmpty
                  ? const ListTile(leading: Icon(Icons.folder_off_rounded), title: Text('No files attached yet'))
                  : Column(
                      children: attachments.map((file) => ListTile(
                            leading: const Icon(Icons.description_rounded),
                            title: Text(file.fileName),
                            subtitle: Text('${file.fileType} • ${(file.fileSize / 1024).round()} KB'),
                            // Updated this line to use file.publicId instead of file.storagePath
                            trailing: SizedBox(width: 260, child: Text(file.publicId, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end)),
                          )).toList(),
                    ),
            ),
            if (canViewAudit) ...[
              const SizedBox(height: 18),
              SectionCard(
                title: 'Audit Trail',
                subtitle: 'Append-only audit events for project and task changes.',
                child: Column(
                  children: projectAudit.map((log) => ListTile(
                        leading: const Icon(Icons.verified_user_rounded),
                        title: Text(log.action),
                        subtitle: Text('${log.targetType} • ${DateText.compact(log.createdAt)}'),
                      )).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), const SizedBox(height: 6), Text(value, style: const TextStyle(fontWeight: FontWeight.w900), maxLines: 2, overflow: TextOverflow.ellipsis)]),
        ),
      ),
    );
  }
}