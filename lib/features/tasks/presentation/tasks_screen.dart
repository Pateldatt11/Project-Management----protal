import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:project_management_dashboard/core/widgets/notification_live_preview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_surface.dart';
import '../../../app/app_theme.dart';
import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/deadline_countdown_chip.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/file_attachment.dart';
import '../../../data/models/member.dart';
import '../../../data/models/mobile_ui_config.dart';
import '../../../data/models/notification_template.dart';
import '../../../data/models/project.dart';
import '../../../data/models/task.dart';
import '../../../data/models/team.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final useMobileSdui = ref.watch(useMobileServerDrivenUiProvider);
    final currentMember = state.currentMember;
    final canCreate = PermissionService.canCreateTasks(currentMember);
    final canViewFullProgress = PermissionService.canViewFullProjectProgress(currentMember);
    final baseProjects = state.visibleProjects.isEmpty
        ? state.projects.where((project) => !project.isArchived).toList()
        : state.visibleProjects.where((project) => !project.isArchived).toList();

    final projects = canViewFullProgress
        ? baseProjects
        : baseProjects
            .where(
              (project) => state.tasks.any(
                (task) =>
                    task.projectId == project.projectId &&
                    task.assignedToIds.contains(currentMember.uid),
              ),
            )
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: SectionCard(
        title: 'Tasks',
        subtitle: canViewFullProgress
            ? 'Admin view: project cards show full task count and full project progress. Tap a card to open task details and timeline.'
            : 'Assigned view: project cards show only your assigned task count and assigned-task progress. Tap a card to open your task details and timeline.',
        child: _TaskMenuBody(
          ref: ref,
          state: state,
          projects: projects,
          currentMember: currentMember,
          canViewFullProgress: canViewFullProgress,
          canCreate: canCreate,
          useMobileSdui: useMobileSdui,
        ),
      ),
    );
  }

  static double _cardWidth(double maxWidth, double gap) {
    if (maxWidth >= 1120) return (maxWidth - (gap * 2)) / 3;
    if (maxWidth >= 740) return (maxWidth - gap) / 2;
    return maxWidth;
  }

  static List<ProjectTask> _scopedProjectTasks({
    required String projectId,
    required List<ProjectTask> allTasks,
    required Member currentMember,
    required bool canViewFullProgress,
  }) {
    final projectTasks = allTasks.where((task) => task.projectId == projectId).toList();
    final scoped = canViewFullProgress
        ? projectTasks
        : projectTasks.where((task) => task.assignedToIds.contains(currentMember.uid)).toList();

    scoped.sort(_taskMenuSort);

    return scoped;
  }

  static double _taskProgress(List<ProjectTask> tasks) {
    if (tasks.isEmpty) return 0;
    final completed = tasks.where((task) => task.status == TaskStatus.completed).length;
    return (completed / tasks.length).clamp(0.0, 1.0);
  }

  static int _taskMenuSort(ProjectTask a, ProjectTask b) {
    final completedCompare = (a.status == TaskStatus.completed ? 1 : 0).compareTo(b.status == TaskStatus.completed ? 1 : 0);
    if (completedCompare != 0) return completedCompare;
    return _taskActivityDate(b).compareTo(_taskActivityDate(a));
  }

  static DateTime _taskActivityDate(ProjectTask task) {
    return task.createdAt ?? task.updatedAt ?? task.completedAt ?? task.dueDate;
  }

  static List<ProjectTask> _newArrivalTasks(List<ProjectTask> tasks) {
    final items = tasks.where((task) => task.status != TaskStatus.completed).toList();
    items.sort((a, b) => _taskActivityDate(b).compareTo(_taskActivityDate(a)));
    return items;
  }

  static List<ProjectTask> _completedArrivalTasks(List<ProjectTask> tasks) {
    final items = tasks.where((task) => task.status == TaskStatus.completed).toList();
    items.sort((a, b) => (b.completedAt ?? b.updatedAt ?? b.createdAt ?? b.dueDate).compareTo(a.completedAt ?? a.updatedAt ?? a.createdAt ?? b.dueDate));
    return items;
  }

  static Future<void> _showProjectTaskDetails(BuildContext context, WidgetRef ref, Project project) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(workspaceProvider);
          final currentMember = state.currentMember;
          final canViewFullProgress = PermissionService.canViewFullProjectProgress(currentMember);
          final canCreate = PermissionService.canCreateTasks(currentMember);
          final canMove = PermissionService.canMoveKanban(currentMember);
          final tasks = _scopedProjectTasks(
            projectId: project.projectId,
            allTasks: state.tasks,
            currentMember: currentMember,
            canViewFullProgress: canViewFullProgress,
          );

          final progress = _taskProgress(tasks);
          final completed = tasks.where((task) => task.status == TaskStatus.completed).length;
          final overdue = tasks.where((task) => task.isOverdue).length;
          final totalEstimatedHours = tasks.fold<num>(0, (sum, task) => sum + task.estimatedHours);
          final totalLoggedHours = tasks.fold<num>(0, (sum, task) => sum + task.loggedHours);
          
          final projectAttachments = state.attachments.where((a) => a.projectId == project.projectId).toList();
          final fileCount = projectAttachments.isNotEmpty
              ? projectAttachments.length
              : tasks.fold<int>(0, (sum, task) => sum + (task.attachments.isNotEmpty ? task.attachments.length : task.attachmentsCount));

          final commentCount = tasks.fold<int>(0, (sum, task) => sum + task.commentsCount);
          final projectTeams = state.teams.where((team) => project.teamIds.contains(team.teamId)).toList();
          final managerMembers = _managerMembers(project, state.members);
          final visibleMembers = _projectVisibleMembers(
            project,
            tasks,
            projectTeams,
            state.members,
            canViewFullProgress,
            currentMember,
          );
          final departments = visibleMembers.map((member) => member.effectiveDepartment).toSet().toList()..sort();

          return Dialog(
            insetPadding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 820),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
                    child: Row(
                      children: [
                        Container(
                          height: 46,
                          width: 46,
                          decoration: BoxDecoration(
                            color: AppTheme.blue.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.task_alt_rounded, color: AppTheme.blue),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                project.name,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                canViewFullProgress ? 'Full project task details' : 'Your assigned task details',
                                style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        if (canCreate)
                          FilledButton.icon(
                            onPressed: () => _showTaskDialogForProject(context, ref, project),
                            icon: const Icon(Icons.add_task_rounded),
                            label: const Text('Add task'),
                          ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ProjectDetailSummary(
                            taskCount: tasks.length,
                            completedTaskCount: completed,
                            progress: progress,
                            teams: projectTeams,
                            status: project.status,
                          ),
                          const SizedBox(height: 18),
                          _ProjectWorkDetailsPanel(
                            project: project,
                            teams: projectTeams,
                            managers: managerMembers,
                            members: visibleMembers,
                            departments: departments,
                            overdueTaskCount: overdue,
                            estimatedHours: totalEstimatedHours,
                            loggedHours: totalLoggedHours,
                            fileCount: fileCount,
                            commentCount: commentCount,
                            canViewFullProgress: canViewFullProgress,
                            projectAttachments: projectAttachments,
                          ),
                          const SizedBox(height: 18),
                          _TaskTimeline(tasks: tasks),
                          const SizedBox(height: 18),
                          Text(
                            'Task details',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          if (tasks.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppTheme.cardAlt,
                                border: Border.all(color: AppTheme.border),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Text('No visible tasks in this project yet.'),
                            )
                          else
                            ...tasks.map((task) {
                              final team = _teamFor(state.teams, task.teamId);
                              final assignees = _assignedMembers(task, state.members);
                              final canUpdateThisTask =
                                  canMove && (canViewFullProgress || task.assignedToIds.contains(currentMember.uid));

                              return _TaskDetailTile(
                                task: task,
                                team: team,
                                assignees: assignees,
                                canUpdateStatus: canUpdateThisTask,
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<void> _showTaskDialogForProject(BuildContext context, WidgetRef ref, Project project) async {
    final state = ref.read(workspaceProvider);
    final title = TextEditingController();
    final description = TextEditingController();
    final hours = TextEditingController(text: '8');
    final meetingLink = TextEditingController();

    final pushTitle = TextEditingController();
    final pushMessage = TextEditingController();

    final projectTeams = state.teams.where((team) => project.teamIds.contains(team.teamId)).toList();
    final visibleTeams = projectTeams.isEmpty ? state.teams : projectTeams;

    if (visibleTeams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a team first before adding tasks.')),
      );
      return;
    }

    String teamId = visibleTeams.first.teamId;
    final assignableMembers = state.activePortalMembers.where((member) => member.role != UserRole.clientViewer).toList();
    String assigneeId = _initialAssignee(assignableMembers, visibleTeams.first, project.projectId, state.currentMember.uid);
    TaskPriority priority = TaskPriority.medium;
    DateTime dueDate = DateTime.now().add(const Duration(days: 7));
    bool notifyAdminsForMeeting = true;

    NotificationTemplate activeTemplate = NotificationPresets.templates.first;
    bool isCustomNotification = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final selectedTeam = visibleTeams.firstWhere((team) => team.teamId == teamId, orElse: () => visibleTeams.first);
          final teamMembers = assignableMembers
              .where(
                (member) =>
                    selectedTeam.memberIds.contains(member.uid) ||
                    member.projectIds.contains(project.projectId) ||
                    project.managerIds.contains(member.uid),
              )
              .toList();
          final finalMembers = teamMembers.isEmpty ? assignableMembers : teamMembers;

          if (finalMembers.isNotEmpty && !finalMembers.any((member) => member.uid == assigneeId)) {
            assigneeId = finalMembers.first.uid;
          }

          final assignedMember = state.members.where((m) => m.uid == assigneeId).firstOrNull;
          final isSenderAdmin = state.currentMember.role.isAdminLike;

          void syncNotification() {
            final currentTaskTitle = title.text.trim();
            final currentDescription = description.text.trim();
            final currentHours = hours.text.trim();
            final assigneeName = assignedMember?.displayName ?? 'You';
            final formattedDueDate = DateText.compact(dueDate);
            final adminName = state.currentMember.displayName.isNotEmpty
                ? state.currentMember.displayName
                : state.user.displayName;
            final currentMeeting = meetingLink.text.trim();

            if (!isCustomNotification) {
              pushTitle.text = activeTemplate.formatTitle(
                taskTitle: currentTaskTitle,
                priority: priority.label,
              );

              pushMessage.text = activeTemplate.formatBody(
                taskTitle: currentTaskTitle,
                adminName: adminName,
                projectName: project.name,
                dueDate: formattedDueDate,
                assigneeName: assigneeName,
                priority: priority.label,
                estimatedHours: currentHours,
                teamName: selectedTeam.name,
                description: currentDescription,
                meetingLink: currentMeeting,
                adminMeetingAccess: notifyAdminsForMeeting,
                isSenderAdmin: isSenderAdmin,
              );
            }
          }

          if (pushTitle.text.isEmpty && pushMessage.text.isEmpty) {
            syncNotification();
          }

          final screenWidth = MediaQuery.of(context).size.width;
          final isWide = screenWidth >= 920;

          Widget buildFormFields() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Project: ${project.name}', style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Task title', hintText: 'e.g., Implement GraphQL API'),
                  onChanged: (val) => setState(syncNotification),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                  onChanged: (val) => setState(syncNotification),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: teamId,
                  decoration: const InputDecoration(labelText: 'Team'),
                  items: visibleTeams
                      .map((team) => DropdownMenuItem(value: team.teamId, child: Text(team.name)))
                      .toList(),
                  onChanged: (value) => setState(() {
                    teamId = value ?? teamId;
                    final nextTeam = visibleTeams.firstWhere((team) => team.teamId == teamId, orElse: () => visibleTeams.first);
                    assigneeId = _initialAssignee(assignableMembers, nextTeam, project.projectId, state.currentMember.uid);
                    syncNotification();
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: finalMembers.any((member) => member.uid == assigneeId) ? assigneeId : null,
                  decoration: const InputDecoration(labelText: 'Assign member'),
                  items: finalMembers
                      .map(
                        (member) => DropdownMenuItem(
                          value: member.uid,
                          child: Text('${member.displayName} • ${member.role.shortLabel}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    assigneeId = value ?? assigneeId;
                    syncNotification();
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TaskPriority>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: TaskPriority.values
                      .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
                      .toList(),
                  onChanged: (value) => setState(() {
                    priority = value ?? priority;
                    syncNotification();
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hours,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Estimated hours'),
                  onChanged: (val) => setState(syncNotification),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: meetingLink,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Meeting link optional',
                    hintText: 'Google Meet or WhatsApp meeting link',
                    prefixIcon: Icon(Icons.video_call_rounded),
                  ),
                  onChanged: (val) => setState(syncNotification),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: notifyAdminsForMeeting,
                  title: const Text('Give meeting access to admins also'),
                  subtitle: const Text('Admins receive Accept & Join / Reject notification with the same link.'),
                  onChanged: (value) => setState(() {
                    notifyAdminsForMeeting = value ?? true;
                    syncNotification();
                  }),
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
                    if (picked != null) {
                      setState(() {
                        dueDate = picked;
                        syncNotification();
                      });
                    }
                  },
                ),
              ],
            );
          }

          Widget buildNotificationPanel() {
            final currentTaskTitle = title.text.trim().isEmpty ? 'Untitled Task' : title.text.trim();
            final currentDesc = description.text.trim().isEmpty ? 'No description provided' : description.text.trim();
            final currentHours = hours.text.trim().isEmpty ? '8' : hours.text.trim();
            final assigneeName = assignedMember?.displayName ?? 'Unassigned';
            final adminName = state.currentMember.displayName.isNotEmpty
                ? state.currentMember.displayName
                : state.user.displayName;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardAlt,
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notifications_active_rounded, size: 18, color: AppTheme.blue),
                      SizedBox(width: 8),
                      Text('Push Alert Live Preview', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: NotificationPresets.templates.map((tpl) {
                        final isSelected = !isCustomNotification && activeTemplate.id == tpl.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(tpl.label),
                            selected: isSelected,
                            selectedColor: AppTheme.blue,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : AppTheme.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  isCustomNotification = false;
                                  activeTemplate = tpl;
                                  syncNotification();
                                });
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  NotificationLivePreview(
                    taskTitle: currentTaskTitle,
                    priority: priority.label,
                    assignerName: adminName,
                    assigneeName: assigneeName,
                    projectName: project.name,
                    teamName: selectedTeam.name,
                    description: currentDesc,
                    estimatedHours: currentHours,
                    dueDate: DateText.compact(dueDate),
                    meetingLink: meetingLink.text.trim(),
                    adminMeetingAccess: notifyAdminsForMeeting,
                    isSenderAdmin: isSenderAdmin,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: pushTitle,
                    decoration: const InputDecoration(
                      labelText: 'Push title override',
                      hintText: 'Edit notification title...',
                    ),
                    onChanged: (val) {
                      setState(() {
                        isCustomNotification = true;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pushMessage,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Push message override',
                      hintText: 'Edit notification message...',
                    ),
                    onChanged: (val) {
                      setState(() {
                        isCustomNotification = true;
                      });
                    },
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            title: Text('Add task to ${project.name}'),
            content: SizedBox(
              width: isWide ? 960 : 540,
              child: SingleChildScrollView(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: buildFormFields()),
                          const SizedBox(width: 20),
                          Expanded(flex: 5, child: buildNotificationPanel()),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          buildFormFields(),
                          const SizedBox(height: 18),
                          buildNotificationPanel(),
                        ],
                      ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (title.text.trim().isEmpty || assigneeId.isEmpty) return;

                  final finalPushTitle = pushTitle.text.trim().isNotEmpty
                      ? pushTitle.text.trim()
                      : activeTemplate.formatTitle(
                          taskTitle: title.text.trim(),
                          priority: priority.label,
                        );

                  final finalPushMessage = pushMessage.text.trim().isNotEmpty
                      ? pushMessage.text.trim()
                      : activeTemplate.formatBody(
                          taskTitle: title.text.trim(),
                          adminName: state.currentMember.displayName,
                          projectName: project.name,
                          dueDate: DateText.compact(dueDate),
                          assigneeName: assignedMember?.displayName ?? 'You',
                          priority: priority.label,
                          estimatedHours: hours.text.trim(),
                          teamName: selectedTeam.name,
                          description: description.text.trim(),
                          meetingLink: meetingLink.text.trim(),
                          adminMeetingAccess: notifyAdminsForMeeting,
                          isSenderAdmin: isSenderAdmin,
                        );

                  ref.read(workspaceProvider.notifier).createTask(
                        title: title.text.trim(),
                        description: description.text.trim().isEmpty ? 'No description provided.' : description.text.trim(),
                        projectId: project.projectId,
                        teamId: teamId,
                        priority: priority,
                        dueDate: dueDate,
                        assignedToIds: [assigneeId],
                        estimatedHours: num.tryParse(hours.text) ?? 0,
                        meetingLink: meetingLink.text.trim(),
                        includeAdminsInMeetingInvite: notifyAdminsForMeeting,
                        customPushTitle: finalPushTitle,
                        customPushMessage: finalPushMessage,
                      );

                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Task added to ${project.name} and notification sent.')),
                  );
                },
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('Add task'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _initialAssignee(List<Member> members, Team team, String projectId, String fallbackUid) {
    final preferred = members.where((member) => team.memberIds.contains(member.uid) || member.projectIds.contains(projectId)).toList();
    if (preferred.isNotEmpty) return preferred.first.uid;
    if (members.any((member) => member.uid == fallbackUid)) return fallbackUid;
    return members.isEmpty ? '' : members.first.uid;
  }

  static Team? _teamFor(List<Team> teams, String teamId) {
    final matches = teams.where((team) => team.teamId == teamId).toList();
    return matches.isEmpty ? null : matches.first;
  }

  static List<Member> _assignedMembers(ProjectTask task, List<Member> members) {
    return task.assignedToIds
        .map((id) {
          final matches = members.where((member) => member.uid == id).toList();
          return matches.isEmpty ? null : matches.first;
        })
        .whereType<Member>()
        .toList();
  }

  static List<Member> _managerMembers(Project project, List<Member> members) {
    final managers = members.where((member) => project.managerIds.contains(member.uid)).toList();
    managers.sort((a, b) => a.displayName.compareTo(b.displayName));
    return managers;
  }

  static List<Member> _projectVisibleMembers(
    Project project,
    List<ProjectTask> visibleTasks,
    List<Team> teams,
    List<Member> members,
    bool canViewFullProgress,
    Member currentMember,
  ) {
    final ids = <String>{};
    ids.addAll(visibleTasks.expand((task) => task.assignedToIds));

    if (canViewFullProgress) {
      ids.addAll(project.managerIds);
      ids.addAll(teams.expand((team) => team.memberIds));
    } else {
      ids.add(currentMember.uid);
    }

    final scopedMembers = members.where((member) => ids.contains(member.uid)).toList();
    scopedMembers.sort((a, b) => a.displayName.compareTo(b.displayName));
    return scopedMembers;
  }
}

enum _TaskMenuTab { newArrival, completed }

class _TaskMenuBody extends StatefulWidget {
  const _TaskMenuBody({
    required this.ref,
    required this.state,
    required this.projects,
    required this.currentMember,
    required this.canViewFullProgress,
    required this.canCreate,
    required this.useMobileSdui,
  });

  final WidgetRef ref;
  final WorkspaceState state;
  final List<Project> projects;
  final Member currentMember;
  final bool canViewFullProgress;
  final bool canCreate;
  final bool useMobileSdui;

  @override
  State<_TaskMenuBody> createState() => _TaskMenuBodyState();
}

class _TaskMenuBodyState extends State<_TaskMenuBody> {
  _TaskMenuTab _tab = _TaskMenuTab.newArrival;

  @override
  Widget build(BuildContext context) {
    final visibleTasks = widget.state.visibleTasks;
    final taskListConfig = widget.state.mobileUiConfig.taskListConfig;
    final showFloatingTabs = taskListConfig['showFloatingTabs'] != false;
    final showCompletedTab = taskListConfig['showCompletedTab'] != false;
    final newTasks = TasksScreen._newArrivalTasks(visibleTasks);
    final completedTasks = TasksScreen._completedArrivalTasks(visibleTasks);
    final activeTab = showCompletedTab ? _tab : _TaskMenuTab.newArrival;
    final selectedTasks = showFloatingTabs ? (activeTab == _TaskMenuTab.newArrival ? newTasks : completedTasks) : <ProjectTask>[...newTasks, ...completedTasks];
    final canMove = PermissionService.canMoveKanban(widget.currentMember);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showFloatingTabs) ...[
          _FloatingTaskTabBar(
            selected: activeTab,
            newCount: newTasks.length,
            completedCount: completedTasks.length,
            showCompleted: showCompletedTab,
            onChanged: (value) => setState(() => _tab = value),
          ),
          const SizedBox(height: 16),
        ],
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: selectedTasks.isEmpty
              ? Container(
                  key: const ValueKey('_task-empty-state'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.cardAlt,
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Icon(_tab == _TaskMenuTab.newArrival ? Icons.fiber_new_rounded : Icons.check_circle_outline_rounded, color: AppTheme.muted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _tab == _TaskMenuTab.newArrival ? 'No new/open tasks available right now.' : 'No completed tasks yet.',
                          style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  key: ValueKey(activeTab),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...selectedTasks.map((task) {
                      final team = TasksScreen._teamFor(widget.state.teams, task.teamId);
                      final assignees = TasksScreen._assignedMembers(task, widget.state.members);
                      final canUpdateThisTask = canMove && (widget.canViewFullProgress || task.assignedToIds.contains(widget.currentMember.uid));
                      return AnimatedScale(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        scale: 1,
                        child: _TaskDetailTile(
                          task: task,
                          team: team,
                          assignees: assignees,
                          canUpdateStatus: canUpdateThisTask,
                        ),
                      );
                    }),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Project task boards',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            StatusBadge(label: '${widget.projects.length} projects', color: AppTheme.blue),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.projects.isEmpty)
          const ListTile(
            leading: Icon(Icons.folder_off_rounded),
            title: Text('No task projects available'),
            subtitle: Text('Projects appear here only when the login has visible task scope.'),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final gap = 16.0;
              final cardWidth = TasksScreen._cardWidth(constraints.maxWidth, gap);

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: widget.projects.map((project) {
                  final scopedTasks = TasksScreen._scopedProjectTasks(
                    projectId: project.projectId,
                    allTasks: widget.state.tasks,
                    currentMember: widget.currentMember,
                    canViewFullProgress: widget.canViewFullProgress,
                  );
                  final progress = TasksScreen._taskProgress(scopedTasks);

                  return AnimatedScale(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    scale: 1,
                    child: SizedBox(
                      width: cardWidth,
                      child: _ProjectTaskCard(
                        project: project,
                        taskCount: scopedTasks.length,
                        progress: progress,
                        projectCardFields: widget.useMobileSdui ? widget.state.mobileUiConfig.projectCardFields : MobileUiConfig.allowedProjectCardFields,
                        compactMode: widget.useMobileSdui && widget.state.mobileUiConfig.compactMode,
                        canCreateTask: widget.canCreate,
                        onOpenDetails: () => TasksScreen._showProjectTaskDetails(context, widget.ref, project),
                        onAddTask: widget.canCreate ? () => TasksScreen._showTaskDialogForProject(context, widget.ref, project) : null,
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }
}

class _FloatingTaskTabBar extends StatelessWidget {
  const _FloatingTaskTabBar({required this.selected, required this.newCount, required this.completedCount, required this.showCompleted, required this.onChanged});

  final _TaskMenuTab selected;
  final int newCount;
  final int completedCount;
  final bool showCompleted;
  final ValueChanged<_TaskMenuTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FloatingTaskTab(
            label: 'New arrival',
            count: newCount,
            icon: Icons.fiber_new_rounded,
            selected: selected == _TaskMenuTab.newArrival,
            onTap: () => onChanged(_TaskMenuTab.newArrival),
          ),
          if (showCompleted)
            _FloatingTaskTab(
              label: 'Completed',
              count: completedCount,
              icon: Icons.check_circle_rounded,
              selected: selected == _TaskMenuTab.completed,
              onTap: () => onChanged(_TaskMenuTab.completed),
            ),
        ],
      ),
    );
  }
}

class _FloatingTaskTab extends StatelessWidget {
  const _FloatingTaskTab({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppTheme.blue : Colors.transparent;
    final fg = selected ? Colors.white : AppTheme.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w900)),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: .20) : AppTheme.cardAlt,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectTaskCard extends StatelessWidget {
  const _ProjectTaskCard({
    required this.project,
    required this.taskCount,
    required this.progress,
    required this.projectCardFields,
    required this.compactMode,
    required this.canCreateTask,
    required this.onOpenDetails,
    required this.onAddTask,
  });

  final Project project;
  final int taskCount;
  final double progress;
  final List<String> projectCardFields;
  final bool compactMode;
  final bool canCreateTask;
  final VoidCallback onOpenDetails;
  final VoidCallback? onAddTask;

  @override
  Widget build(BuildContext context) {
    final progressPercent = (progress * 100).round();
    final showProjectName = projectCardFields.contains('projectName') || projectCardFields.isEmpty;
    final showTaskCount = projectCardFields.contains('taskCount') || projectCardFields.isEmpty;
    final showProgress = projectCardFields.contains('progress') || projectCardFields.isEmpty;
    final showDeadline = projectCardFields.contains('deadline');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onOpenDetails,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(compactMode ? 14 : 18),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .04),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: showProjectName
                        ? Text(
                            project.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                          )
                        : const Text('Project', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  IconButton.filledTonal(
                    tooltip: canCreateTask ? 'Add task to this project' : 'Your role cannot add tasks',
                    onPressed: onAddTask,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              SizedBox(height: compactMode ? 12 : 18),
              if (showTaskCount || showProgress)
                Row(
                  children: [
                    if (showTaskCount) Expanded(child: _MetricBlock(label: 'Tasks', value: '$taskCount')),
                    if (showTaskCount && showProgress) const SizedBox(width: 12),
                    if (showProgress) Expanded(child: _MetricBlock(label: 'Progress', value: '$progressPercent%')),
                  ],
                ),
              if (showDeadline) ...[
                const SizedBox(height: 12),
                _Pill(icon: Icons.calendar_today_rounded, text: 'Due ${DateText.compact(project.dueDate)}'),
              ],
              if (showProgress) ...[
                SizedBox(height: compactMode ? 12 : 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: compactMode ? 8 : 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardAlt,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.muted)),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _ProjectDetailSummary extends StatelessWidget {
  const _ProjectDetailSummary({
    required this.taskCount,
    required this.completedTaskCount,
    required this.progress,
    required this.teams,
    required this.status,
  });

  final int taskCount;
  final int completedTaskCount;
  final double progress;
  final List<Team> teams;
  final ProjectStatus status;

  @override
  Widget build(BuildContext context) {
    final progressPercent = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardAlt,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _MetricBlock(label: 'Tasks', value: '$taskCount')),
              const SizedBox(width: 12),
              Expanded(child: _MetricBlock(label: 'Done', value: '$completedTaskCount')),
              const SizedBox(width: 12),
              Expanded(child: _MetricBlock(label: 'Progress', value: '$progressPercent%')),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(value: value, minHeight: 10),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(label: status.label, color: status.color),
              ...teams.map((team) => _Pill(icon: Icons.groups_rounded, text: team.name)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectWorkDetailsPanel extends StatelessWidget {
  const _ProjectWorkDetailsPanel({
    required this.project,
    required this.teams,
    required this.managers,
    required this.members,
    required this.departments,
    required this.overdueTaskCount,
    required this.estimatedHours,
    required this.loggedHours,
    required this.fileCount,
    required this.commentCount,
    required this.canViewFullProgress,
    required this.projectAttachments,
  });

  final Project project;
  final List<Team> teams;
  final List<Member> managers;
  final List<Member> members;
  final List<String> departments;
  final int overdueTaskCount;
  final num estimatedHours;
  final num loggedHours;
  final int fileCount;
  final int commentCount;
  final bool canViewFullProgress;
  final List<FileAttachment> projectAttachments;

  Future<void> _openFileUrl(BuildContext context, String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;
    final uri = Uri.tryParse(cleanUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final daysLeft = project.dueDate.difference(DateTime(today.year, today.month, today.day)).inDays;
    final effortPercent = estimatedHours == 0 ? 0 : ((loggedHours / estimatedHours) * 100).clamp(0, 999).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Project work details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              StatusBadge(label: project.priority.label, color: project.priority.color),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            project.description.trim().isEmpty ? 'No project description added yet.' : project.description,
            style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, height: 1.35),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 820;
              final children = [
                _DetailInfoCard(
                  title: 'Delivery',
                  icon: Icons.flag_rounded,
                  children: [
                    _DetailLine(label: 'Status', value: project.status.label),
                    _DetailLine(label: 'Start date', value: DateText.compact(project.startDate)),
                    _DetailLine(label: 'Due date', value: DateText.compact(project.dueDate)),
                    _DetailLine(label: 'Days left', value: daysLeft < 0 ? '${daysLeft.abs()} days overdue' : '$daysLeft days'),
                    _DetailLine(label: 'Budget', value: '${project.currency} ${project.budget}'),
                  ],
                ),
                _DetailInfoCard(
                  title: 'People',
                  icon: Icons.groups_rounded,
                  children: [
                    _DetailLine(label: 'Managers', value: managers.isEmpty ? 'Not assigned' : managers.map((m) => m.displayName).join(', ')),
                    _DetailLine(label: 'Visible members', value: '${members.length}'),
                    _DetailLine(label: 'Teams', value: teams.isEmpty ? 'No team' : teams.map((team) => team.name).join(', ')),
                    _DetailLine(label: 'Departments', value: departments.isEmpty ? 'No department' : departments.join(', ')),
                    _DetailLine(label: 'Scope', value: canViewFullProgress ? 'Full project' : 'Assigned work only'),
                  ],
                ),
                _DetailInfoCard(
                  title: 'Workload',
                  icon: Icons.speed_rounded,
                  children: [
                    _DetailLine(label: 'Estimated', value: '${estimatedHours.toStringAsFixed(estimatedHours % 1 == 0 ? 0 : 1)} hrs'),
                    _DetailLine(label: 'Logged', value: '${loggedHours.toStringAsFixed(loggedHours % 1 == 0 ? 0 : 1)} hrs'),
                    _DetailLine(label: 'Effort used', value: '$effortPercent%'),
                    _DetailLine(label: 'Overdue tasks', value: '$overdueTaskCount'),
                    _DetailLine(label: 'Files / comments', value: '$fileCount files • $commentCount comments'),
                  ],
                ),
              ];

              if (wide) {
                return Row(
                  children: children
                      .map((child) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: child)))
                      .toList(),
                );
              }

              return Column(
                children: children.map((child) => Padding(padding: const EdgeInsets.only(bottom: 12), child: child)).toList(),
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...members.take(8).map((member) => _Pill(icon: Icons.person_rounded, text: '${member.displayName} • ${member.role.shortLabel}')),
              if (members.length > 8) _Pill(icon: Icons.more_horiz_rounded, text: '+${members.length - 8} more'),
            ],
          ),

          if (projectAttachments.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.folder_shared_rounded, size: 18, color: AppTheme.blue),
                const SizedBox(width: 8),
                Text(
                  'Project Files & Documents (${projectAttachments.length})',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: projectAttachments.map((file) {
                final isImage = file.isImage;
                final sizeLabel = file.fileSize > 0 ? ' • ${file.formattedSize}' : '';

                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: file.secureUrl.isNotEmpty ? () => _openFileUrl(context, file.secureUrl) : null,
                  child: _Pill(
                    icon: isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded,
                    text: '${file.fileName}$sizeLabel',
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailInfoCard extends StatelessWidget {
  const _DetailInfoCard({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardAlt,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.blue),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
        ],
      ),
    );
  }
}

class _TaskTimeline extends StatelessWidget {
  const _TaskTimeline({required this.tasks});

  final List<ProjectTask> tasks;

  @override
  Widget build(BuildContext context) {
    final total = tasks.isEmpty ? 1 : tasks.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Task timeline', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;

              if (compact) {
                return Column(
                  children: TaskStatus.values
                      .map((status) => _TimelineStage(status: status, count: _count(status), total: total))
                      .toList(),
                );
              }

              return Row(
                children: TaskStatus.values
                    .map((status) => Expanded(child: _TimelineStage(status: status, count: _count(status), total: total)))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  int _count(TaskStatus status) => tasks.where((task) => task.status == status).length;
}

class _TimelineStage extends StatelessWidget {
  const _TimelineStage({required this.status, required this.count, required this.total});

  final TaskStatus status;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : count / total;

    return Container(
      margin: const EdgeInsets.all(5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: .07),
        border: Border.all(color: status.color.withValues(alpha: .16)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: status.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(status.label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
              Text('$count', style: TextStyle(color: status.color, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: share),
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(value: value, minHeight: 7, color: status.color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskDetailTile extends ConsumerStatefulWidget {
  const _TaskDetailTile({
    required this.task,
    required this.team,
    required this.assignees,
    required this.canUpdateStatus,
  });

  final ProjectTask task;
  final Team? team;
  final List<Member> assignees;
  final bool canUpdateStatus;

  @override
  ConsumerState<_TaskDetailTile> createState() => _TaskDetailTileState();
}

class _TaskDetailTileState extends ConsumerState<_TaskDetailTile> {
  bool _isUploading = false;
  bool _isCompleted = false;
  double _uploadProgress = 0.0;
  int _uploadedBytes = 0;
  int _totalUploadBytes = 0;

  Future<void> _openAttachmentUrl(BuildContext context, String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File link is not available.')),
      );
      return;
    }
    final uri = Uri.tryParse(cleanUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open file link.')),
        );
      }
    }
  }

  Future<void> _handleAttachFile() async {
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isUploading = true;
      _isCompleted = false;
      _uploadProgress = 0.0;
      _uploadedBytes = 0;
      _totalUploadBytes = 0;
    });

    final ok = await ref.read(workspaceProvider.notifier).addAttachmentFromDevicePicker(
      widget.task.taskId,
      onProgress: (sentBytes, totalBytes) {
        if (!mounted) return;
        setState(() {
          _uploadedBytes = sentBytes;
          _totalUploadBytes = totalBytes;
          _uploadProgress = totalBytes <= 0
              ? 0.0
              : (sentBytes / totalBytes).clamp(0.0, 1.0);
        });
      },
    );

    if (!mounted) return;

    if (ok) {
      setState(() {
        _uploadProgress = 1.0;
        _uploadedBytes = _totalUploadBytes;
        _isCompleted = true;
      });

      // Keep the success state visible briefly; the upload itself is already
      // complete and its Cloudinary metadata has been persisted at this point.
      await Future<void>.delayed(const Duration(milliseconds: 700));

      if (mounted) {
        setState(() {
          _isUploading = false;
          _isCompleted = false;
          _uploadProgress = 0.0;
          _uploadedBytes = 0;
          _totalUploadBytes = 0;
        });
      }
    } else {
      final error = ref.read(workspaceProvider).lastError;
      setState(() {
        _isUploading = false;
        _isCompleted = false;
        _uploadProgress = 0.0;
        _uploadedBytes = 0;
        _totalUploadBytes = 0;
      });
      if (error != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(error),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final task = widget.task;

    final effortPercent = task.estimatedHours == 0 ? 0 : ((task.loggedHours / task.estimatedHours) * 100).clamp(0, 999).round();
    final assigneeNames = widget.assignees.isEmpty ? 'Unassigned' : widget.assignees.map((member) => member.displayName).join(', ');
    final assigneeEmails = widget.assignees.isEmpty ? '-' : widget.assignees.map((member) => member.email).join(', ');
    final departments = widget.assignees.isEmpty ? '-' : widget.assignees.map((member) => member.effectiveDepartment).toSet().join(', ');
    final roles = widget.assignees.isEmpty ? '-' : widget.assignees.map((member) => member.role.shortLabel).toSet().join(', ');

    final taskDirectAttachments = task.attachments;
    final workspaceScopedAttachments = workspace.attachments.where((a) => a.taskId == task.taskId).toList();
    
    final attachmentMap = <String, FileAttachment>{};
    for (final att in workspaceScopedAttachments) {
      attachmentMap[att.attachmentId] = att;
    }
    for (final att in taskDirectAttachments) {
      attachmentMap[att.attachmentId] = att;
    }
    final combinedAttachments = attachmentMap.values.toList();
    final hasAttachments = combinedAttachments.isNotEmpty || task.attachmentNames.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .025), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
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
                    Text(task.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                      task.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  DeadlineCountdownChip(
                    deadline: task.dueDate,
                    completed: task.status == TaskStatus.completed,
                    compact: true,
                  ),
                  StatusBadge(label: task.priority.label, color: task.priority.color),
                  widget.canUpdateStatus ? _StatusDropdown(task: task) : StatusBadge(label: task.status.label, color: task.status.color),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final blocks = [
                _TaskDetailBlock(
                  title: 'Assignment',
                  icon: Icons.assignment_ind_rounded,
                  lines: [
                    _DetailLine(label: 'Assignee', value: assigneeNames),
                    _DetailLine(label: 'Email', value: assigneeEmails),
                    _DetailLine(label: 'Role', value: roles),
                    _DetailLine(label: 'Department', value: departments),
                    _DetailLine(label: 'Team', value: widget.team?.name ?? 'No team'),
                  ],
                ),
                _TaskDetailBlock(
                  title: 'Schedule',
                  icon: Icons.calendar_month_rounded,
                  lines: [
                    _DetailLine(label: 'Due date', value: DateText.compact(task.dueDate)),
                    DeadlineCountdownChip(deadline: task.dueDate, completed: task.status == TaskStatus.completed),
                    _DetailLine(label: 'Created', value: DateText.compact(task.createdAt)),
                    _DetailLine(label: 'Updated', value: DateText.compact(task.updatedAt)),
                    _DetailLine(label: 'Completed', value: _dateOrDash(task.completedAt)),
                    _DetailLine(label: 'Overdue', value: task.isOverdue ? 'Yes' : 'No'),
                  ],
                ),
                _TaskDetailBlock(
                  title: 'Work data',
                  icon: Icons.analytics_rounded,
                  lines: [
                    _DetailLine(label: 'Estimate', value: '${task.estimatedHours} hrs'),
                    _DetailLine(label: 'Logged', value: '${task.loggedHours} hrs'),
                    _DetailLine(label: 'Effort', value: '$effortPercent%'),
                    _DetailLine(label: 'Comments', value: '${task.commentsCount}'),
                    _DetailLine(label: 'Files', value: '${combinedAttachments.isNotEmpty ? combinedAttachments.length : task.attachmentsCount}'),
                  ],
                ),
              ];

              if (compact) {
                return Column(
                  children: blocks
                      .map((block) => Padding(padding: const EdgeInsets.only(bottom: 10), child: block))
                      .toList(),
                );
              }

              return Row(
                children: blocks
                    .map((block) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 10), child: block)))
                    .toList(),
              );
            },
          ),
          if (task.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: task.tags.map((tag) => _Pill(icon: Icons.local_offer_rounded, text: tag)).toList(),
            ),
          ],
          if (hasAttachments) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.attach_file_rounded, size: 16, color: AppTheme.blue),
                const SizedBox(width: 6),
                Text(
                  'Attached files (${combinedAttachments.isNotEmpty ? combinedAttachments.length : task.attachmentNames.length})',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: combinedAttachments.isNotEmpty
                  ? combinedAttachments.map((file) {
                      final isImage = file.fileType.startsWith('image/') ||
                          ['jpg', 'jpeg', 'png', 'webp', 'gif'].any((ext) => file.fileName.toLowerCase().endsWith(ext));
                      final sizeText = file.fileSize > 0
                          ? ' • ${(file.fileSize / 1024).toStringAsFixed(0)} KB'
                          : '';

                      return InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: file.secureUrl.isNotEmpty
                            ? () => _openAttachmentUrl(context, file.secureUrl)
                            : null,
                        child: _Pill(
                          icon: isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded,
                          text: '${file.fileName}$sizeText',
                        ),
                      );
                    }).toList()
                  : task.attachmentNames.map((name) => _Pill(
                        icon: Icons.insert_drive_file_rounded,
                        text: name,
                      )).toList(),
            ),
          ],
          const SizedBox(height: 12),

          // Google Drive + WhatsApp Style Animated Upload Card
          if (_isUploading)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TaskDriveWhatsAppUploadCard(
                progress: _uploadProgress,
                isCompleted: _isCompleted,
                uploadedBytes: _uploadedBytes,
                totalBytes: _totalUploadBytes,
              ),
            ),

          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(
                _isUploading ? 'Uploading...' : 'Attach file',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: _isUploading ? null : _handleAttachFile,
            ),
          ),
        ],
      ),
    );
  }

  static String _dateOrDash(DateTime? value) {
    if (value == null) return '-';
    return DateText.compact(value);
  }
}

/// Google Drive + WhatsApp Style Hybrid Upload Card
class _TaskDriveWhatsAppUploadCard extends StatelessWidget {
  final double progress;
  final bool isCompleted;
  final int uploadedBytes;
  final int totalBytes;

  const _TaskDriveWhatsAppUploadCard({
    required this.progress,
    required this.isCompleted,
    required this.uploadedBytes,
    required this.totalBytes,
  });

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final percentage = (progress.clamp(0.0, 1.0) * 100).toInt();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isCompleted
            ? Colors.green.shade50.withValues(alpha: 0.8)
            : AppTheme.cardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? Colors.green.shade400
              : AppTheme.blue.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: isCompleted
                ? Colors.green.withValues(alpha: 0.08)
                : AppTheme.blue.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: isCompleted
                ? Container(
                    key: const ValueKey('done_icon'),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.green, size: 24),
                  )
                : Container(
                    key: const ValueKey('upload_icon'),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.insert_drive_file_rounded,
                      color: AppTheme.blue,
                      size: 22,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        isCompleted ? 'Uploaded successfully' : 'Uploading attachment...',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: isCompleted ? Colors.green.shade800 : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!isCompleted)
                      Text(
                        '$percentage%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.blue,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (!isCompleted) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppTheme.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.blue),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  isCompleted
                      ? 'Ready in task attachments'
                      : totalBytes > 0
                          ? 'Uploading • ${_formatBytes(uploadedBytes)} / ${_formatBytes(totalBytes)}'
                          : 'Preparing upload...',
                  style: TextStyle(
                    fontSize: 11,
                    color: isCompleted ? Colors.green.shade700 : AppTheme.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskDetailBlock extends StatelessWidget {
  const _TaskDetailBlock({required this.title, required this.icon, required this.lines});

  final String title;
  final IconData icon;
  final List<Widget> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardAlt,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppTheme.blue),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          ...lines,
        ],
      ),
    );
  }
}

class _StatusDropdown extends ConsumerWidget {
  const _StatusDropdown({required this.task});

  final ProjectTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: task.status.color.withValues(alpha: .18)),
        borderRadius: BorderRadius.circular(999),
        color: task.status.color.withValues(alpha: .07),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TaskStatus>(
          value: task.status,
          isDense: true,
          icon: Icon(Icons.swap_vert_rounded, color: task.status.color, size: 18),
          items: TaskStatus.values
              .map((status) => DropdownMenuItem(value: status, child: Text(status.label)))
              .toList(),
          onChanged: (status) {
            if (status != null) {
              ref.read(workspaceProvider.notifier).updateTaskStatus(task.taskId, status);
            }
          },
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, this.warning = false});

  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? AppTheme.danger : AppTheme.muted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: warning ? AppTheme.danger.withValues(alpha: .06) : AppTheme.cardAlt,
        border: Border.all(color: warning ? AppTheme.danger.withValues(alpha: .18) : AppTheme.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}