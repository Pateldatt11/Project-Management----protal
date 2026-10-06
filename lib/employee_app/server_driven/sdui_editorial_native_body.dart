import 'package:flutter/material.dart';

import '../../app/workspace_state.dart';
import '../../core/constants/app_enums.dart';
import '../../data/models/project.dart';
import '../../data/models/task.dart';
import 'sdui_mobile_ui_config.dart';

/// Production renderer for the Editorial Native SDUI template.
///
/// The HTML/admin preview and APK were previously using two different render
/// paths. This body intentionally mirrors the preview layout in Flutter while
/// still reading real WorkspaceState data, so the released APK looks the same
/// as the admin/mobile preview instead of falling back to older generic cards.
class SduiEditorialNativeBody extends StatelessWidget {
  const SduiEditorialNativeBody({
    super.key,
    required this.config,
    required this.state,
    required this.currentTab,
    this.onAction,
  });

  final SduiMobileUiConfig config;
  final WorkspaceState state;
  final String currentTab;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: config.mediumAnimationDuration,
      switchInCurve: config.defaultCurve,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey<String>(currentTab),
        child: switch (currentTab) {
          'tasks' => _EditorialTasksTab(config: config, state: state, onAction: onAction),
          'projects' => _EditorialProjectsTab(config: config, state: state, onAction: onAction),
          'profile' => _EditorialProfileTab(config: config, state: state, onAction: onAction),
          'notifications' => _EditorialInboxTab(config: config, state: state, onAction: onAction),
          'home' || _ => _EditorialHomeTab(config: config, state: state, onAction: onAction),
        },
      ),
    );
  }
}

class _EditorialHomeTab extends StatelessWidget {
  const _EditorialHomeTab({required this.config, required this.state, this.onAction});

  final SduiMobileUiConfig config;
  final WorkspaceState state;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final tasks = _sortedOpenTasks(state.visibleTasks);
    final projects = _sortedOpenProjects(state.visibleProjects);
    final nextTask = tasks.isNotEmpty ? tasks.first : null;
    final todayCount = state.visibleTasks.where((task) => _isSameDate(task.dueDate, DateTime.now()) && !task.isCompleted).length;
    final openCount = tasks.length;
    final primaryProject = projects.isNotEmpty ? projects.first : null;

    return _EditorialListView(
      config: config,
      children: [
        _DeadlineHeroCard(
          title: nextTask?.title ?? 'No urgent deadline',
          subtitle: nextTask == null ? 'All clear for now' : _projectName(state, nextTask.projectId),
          countdown: nextTask == null ? '--' : _deadlineShort(nextTask.dueDate),
          priority: nextTask?.priority.label ?? 'Ready',
          urgent: nextTask?.isOverdue ?? false,
          onTap: () => onAction?.call('openTask'),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                title: 'Today',
                value: todayCount.toString().padLeft(2, '0'),
                label: 'Tasks',
                icon: Icons.today_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                title: 'Open',
                value: openCount.toString().padLeft(2, '0'),
                label: 'Assigned',
                icon: Icons.task_alt_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _SectionTitle('Current work'),
        const SizedBox(height: 10),
        if (tasks.isEmpty)
          const _EmptyEditorialCard(title: 'No open tasks', subtitle: 'New assigned work will appear here.')
        else
          ...tasks.take(3).map(
                (task) => _TaskStatusRow(
                  title: task.title,
                  subtitle: _projectName(state, task.projectId),
                  tag: task.priority.label,
                  progress: _taskProgress(task),
                  accent: task.priority.color,
                  overdue: task.isOverdue,
                  onTap: () => onAction?.call('openTask:${task.taskId}'),
                ),
              ),
        const SizedBox(height: 18),
        const _SectionTitle('Project progress'),
        const SizedBox(height: 10),
        if (primaryProject == null)
          const _EmptyEditorialCard(title: 'No projects', subtitle: 'Assigned projects will appear here.')
        else
          _ProjectProgressRow(
            title: primaryProject.name,
            subtitle: '${primaryProject.completedTasks} of ${primaryProject.totalTasks} tasks completed',
            progress: (primaryProject.progress / 100).clamp(0.0, 1.0).toDouble(),
            status: primaryProject.status.label,
            onTap: () => onAction?.call('openProject:${primaryProject.projectId}'),
          ),
      ],
    );
  }
}

class _EditorialTasksTab extends StatelessWidget {
  const _EditorialTasksTab({required this.config, required this.state, this.onAction});

  final SduiMobileUiConfig config;
  final WorkspaceState state;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final openTasks = _sortedOpenTasks(state.visibleTasks);
    final completedTasks = state.visibleTasks.where((task) => task.isCompleted).toList()
      ..sort((a, b) => (b.completedAt ?? b.dueDate).compareTo(a.completedAt ?? a.dueDate));
    final visible = <ProjectTask>[...openTasks.take(8), ...completedTasks.take(2)];

    return _EditorialListView(
      config: config,
      children: [
        _SearchPill(label: 'Search tasks', onTap: () => onAction?.call('smartSearch')),
        const SizedBox(height: 14),
        const _ChipRow(chips: ['New Arrival', 'In Progress', 'Completed']),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          const _EmptyEditorialCard(title: 'No tasks found', subtitle: 'Assigned tasks will appear here.')
        else
          ...visible.map(
            (task) => _TaskStatusRow(
              title: task.title,
              subtitle: '${_projectName(state, task.projectId)} • ${task.status.label}',
              tag: task.priority.label,
              progress: _taskProgress(task),
              accent: task.priority.color,
              overdue: task.isOverdue,
              completed: task.isCompleted,
              onTap: () => onAction?.call('openTask:${task.taskId}'),
            ),
          ),
      ],
    );
  }
}

class _EditorialProjectsTab extends StatelessWidget {
  const _EditorialProjectsTab({required this.config, required this.state, this.onAction});

  final SduiMobileUiConfig config;
  final WorkspaceState state;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final projects = _sortedOpenProjects(state.visibleProjects);
    return _EditorialListView(
      config: config,
      children: [
        _SearchPill(label: 'Search projects', onTap: () => onAction?.call('smartSearch')),
        const SizedBox(height: 14),
        const _ChipRow(chips: ['All', 'In Progress', 'Completed']),
        const SizedBox(height: 16),
        if (projects.isEmpty)
          const _EmptyEditorialCard(title: 'No projects found', subtitle: 'Project access will appear here.')
        else
          ...projects.map(
            (project) => _ProjectProgressRow(
              title: project.name,
              subtitle: _projectSubtitle(project),
              progress: (project.progress / 100).clamp(0.0, 1.0).toDouble(),
              status: project.status.label,
              onTap: () => onAction?.call('openProject:${project.projectId}'),
            ),
          ),
      ],
    );
  }
}

class _EditorialProfileTab extends StatelessWidget {
  const _EditorialProfileTab({required this.config, required this.state, this.onAction});

  final SduiMobileUiConfig config;
  final WorkspaceState state;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final member = state.currentMember;
    final initials = _initials(member.displayName.isNotEmpty ? member.displayName : member.email);
    return _EditorialListView(
      config: config,
      children: [
        _EditorialCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: const Color(0xFF151515),
                        child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      ),
                      Positioned(
                        right: -1,
                        bottom: 1,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: member.isOnline ? const Color(0xFF6FAF8D) : const Color(0xFFB8B3A9),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _StatusPill(label: member.presenceLabel, color: member.isOnline ? const Color(0xFF6FAF8D) : const Color(0xFFB8B3A9)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                member.displayName.isEmpty ? 'Employee' : member.displayName,
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.8),
              ),
              const SizedBox(height: 5),
              Text(
                '${member.effectiveJobTitle} • ${state.company.name}',
                style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              _ProfileLine(label: 'Email', value: member.email),
              _ProfileLine(label: 'Company', value: state.company.name),
              _ProfileLine(label: 'Department', value: member.effectiveDepartment),
              _ProfileLine(label: 'Role', value: member.role.label),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _EditorialCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.logout_rounded, color: Color(0xFFD87465)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Logout', style: TextStyle(fontWeight: FontWeight.w900))),
              IconButton(onPressed: () => onAction?.call('logout'), icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16)),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditorialInboxTab extends StatelessWidget {
  const _EditorialInboxTab({required this.config, required this.state, this.onAction});

  final SduiMobileUiConfig config;
  final WorkspaceState state;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final notifications = state.myNotifications.take(20).toList();
    return _EditorialListView(
      config: config,
      children: [
        if (notifications.isEmpty)
          const _EmptyEditorialCard(title: 'Inbox is clear', subtitle: 'New task alerts and updates will appear here.')
        else
          ...notifications.map(
            (notification) => _EditorialCard(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(notification.isRead ? Icons.mark_email_read_rounded : Icons.notifications_active_rounded, color: const Color(0xFF151515)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(notification.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(notification.message, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _EditorialListView extends StatelessWidget {
  const _EditorialListView({required this.config, required this.children});

  final SduiMobileUiConfig config;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        config.horizontalPadding,
        0,
        config.horizontalPadding,
        10,
      ),
      children: children,
    );
  }
}

class _DeadlineHeroCard extends StatelessWidget {
  const _DeadlineHeroCard({required this.title, required this.subtitle, required this.countdown, required this.priority, required this.urgent, this.onTap});

  final String title;
  final String subtitle;
  final String countdown;
  final String priority;
  final bool urgent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.13), blurRadius: 28, offset: const Offset(0, 15))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Deadline timer', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                const Spacer(),
                _DarkPill(label: urgent ? 'Overdue' : priority),
              ],
            ),
            const SizedBox(height: 12),
            Text(countdown, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
            const SizedBox(height: 6),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.title, required this.value, required this.label, required this.icon});

  final String title;
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _EditorialCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Text(title, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w800)), const Spacer(), Icon(icon, size: 18, color: const Color(0xFF9C978D))]),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -1)),
          Text(label, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TaskStatusRow extends StatelessWidget {
  const _TaskStatusRow({required this.title, required this.subtitle, required this.tag, required this.progress, required this.accent, this.overdue = false, this.completed = false, this.onTap});

  final String title;
  final String subtitle;
  final String tag;
  final double progress;
  final Color accent;
  final bool overdue;
  final bool completed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final barColor = completed ? const Color(0xFF6FAF8D) : overdue ? const Color(0xFFD87465) : const Color(0xFF151515);
    return GestureDetector(
      onTap: onTap,
      child: _EditorialCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.2))),
                _StatusPill(label: completed ? 'Done' : overdue ? 'Late' : tag, color: completed ? const Color(0xFF6FAF8D) : overdue ? const Color(0xFFD87465) : accent),
              ],
            ),
            const SizedBox(height: 5),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0).toDouble(),
                minHeight: 8,
                backgroundColor: const Color(0xFFF0ECE3),
                color: barColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectProgressRow extends StatelessWidget {
  const _ProjectProgressRow({required this.title, required this.subtitle, required this.progress, required this.status, this.onTap});

  final String title;
  final String subtitle;
  final double progress;
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _EditorialCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            SizedBox(
              height: 50,
              width: 50,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(value: progress.clamp(0.0, 1.0).toDouble(), strokeWidth: 6, backgroundColor: const Color(0xFFF0ECE3), color: const Color(0xFF151515)),
                  Text('${(progress * 100).round()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.2))), _StatusPill(label: status)]),
                  const SizedBox(height: 5),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Color(0xFF9C978D)),
          ],
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _EditorialCard(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: Color(0xFF76736D)),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.chips});

  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: chips.asMap().entries.map((entry) {
          final selected = entry.key == 0;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF151515) : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFECE7DA)),
              ),
              child: Text(entry.value, style: TextStyle(color: selected ? Colors.white : const Color(0xFF76736D), fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EditorialCard extends StatelessWidget {
  const _EditorialCard({required this.child, this.padding = EdgeInsets.zero, this.margin = EdgeInsets.zero, this.radius = 24});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFECE7DA)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.045), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.45));
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, this.color = const Color(0xFF151515)});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(999)),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

class _DarkPill extends StatelessWidget {
  const _DarkPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w700))),
          Expanded(child: Text(value.isEmpty ? '-' : value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }
}

class _EmptyEditorialCard extends StatelessWidget {
  const _EmptyEditorialCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _EditorialCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.inbox_rounded, color: Color(0xFF9C978D)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

List<ProjectTask> _sortedOpenTasks(List<ProjectTask> tasks) {
  final open = tasks.where((task) => !task.isCompleted).toList();
  open.sort((a, b) {
    final due = a.dueDate.compareTo(b.dueDate);
    if (due != 0) return due;
    return b.priority.index.compareTo(a.priority.index);
  });
  return open;
}

List<Project> _sortedOpenProjects(List<Project> projects) {
  final open = projects.where((project) => !project.isArchived).toList();
  open.sort((a, b) {
    if (a.isDelayed != b.isDelayed) return a.isDelayed ? -1 : 1;
    final due = a.dueDate.compareTo(b.dueDate);
    if (due != 0) return due;
    return b.progress.compareTo(a.progress);
  });
  return open;
}

String _projectName(WorkspaceState state, String projectId) {
  for (final project in state.visibleProjects) {
    if (project.projectId == projectId) return project.name;
  }
  for (final project in state.projects) {
    if (project.projectId == projectId) return project.name;
  }
  return 'General work';
}

String _projectSubtitle(Project project) {
  if (project.totalTasks > 0) return '${project.completedTasks} of ${project.totalTasks} tasks completed';
  return '${project.priority.label} priority • ${_deadlineShort(project.dueDate)}';
}

double _taskProgress(ProjectTask task) {
  if (task.isCompleted) return 1;
  if (task.effortUsage > 0) return task.effortUsage;
  return switch (task.status) {
    TaskStatus.backlog => 0.10,
    TaskStatus.todo => 0.20,
    TaskStatus.inProgress => 0.55,
    TaskStatus.review => 0.78,
    TaskStatus.testing => 0.88,
    TaskStatus.completed => 1.0,
  };
}

String _deadlineShort(DateTime dueDate) {
  final now = DateTime.now();
  final diff = dueDate.difference(now);
  final overdue = diff.isNegative;
  final absolute = overdue ? now.difference(dueDate) : diff;
  if (absolute.inDays >= 1) return overdue ? '${absolute.inDays}d late' : '${absolute.inDays}d ${absolute.inHours % 24}h';
  if (absolute.inHours >= 1) return overdue ? '${absolute.inHours}h late' : '${absolute.inHours}h ${absolute.inMinutes % 60}m';
  final minutes = absolute.inMinutes.clamp(0, 59).toInt();
  return overdue ? '${minutes}m late' : '${minutes}m';
}

bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return 'U';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}
