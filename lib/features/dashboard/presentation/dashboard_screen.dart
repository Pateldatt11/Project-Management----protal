import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_theme.dart';
import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/dashboard_charts.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/member.dart';
import '../../../data/models/task.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final stats = state.stats;
    final tasks = state.visibleTasks;
    final totalTasks = tasks.length;
    final completedTasks = stats.completedTasks;
    final activeTasks = tasks.where((task) => task.status != TaskStatus.completed).length;
    final reviewQueue = tasks.where((task) => task.status == TaskStatus.review || task.status == TaskStatus.testing).length;
    final completionRate = totalTasks == 0 ? 0 : ((completedTasks / totalTasks) * 100).round();
    final upcoming = tasks.where((task) => task.status != TaskStatus.completed).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final statusSegments = _statusSegments(tasks);
    final completionTrend = _completionTrend(tasks);
    final projectProgress = _projectProgress(state);
    final employeeWorkload = _employeeWorkload(state);

    // Dynamic company name from workspace state (avoids touching users collection)
    final companyName = state.company.name.isNotEmpty && state.company.name != 'Company Workspace'
        ? state.company.name
        : (state.company.companyId != 'platform' ? state.company.name : 'Company Workspace');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DashboardHeader(
            completionRate: completionRate,
            companyName: companyName,
            roleDescription: state.user.role.description,
          ),
          const SizedBox(height: 20),
          _MyPresencePanel(member: state.currentMember, onlineCount: state.onlineMembers.length, offlineCount: state.offlineMembers.length),
          const SizedBox(height: 20),
          ResponsiveGrid(
            minTileWidth: 220,
            children: [
              StatCard(
                title: 'Total Tasks',
                value: '$totalTasks',
                subtitle: 'Across active workspaces',
                trendLabel: '+${completedTasks.clamp(0, 99)} done',
                icon: Icons.checklist_rounded,
                color: AppTheme.blue,
              ),
              StatCard(
                title: 'Completion Rate',
                value: '$completionRate%',
                subtitle: 'Calculated from completed tasks',
                trendLabel: completionRate >= 60 ? 'Healthy' : 'Needs focus',
                trendUp: completionRate >= 60,
                icon: Icons.speed_rounded,
                color: AppTheme.success,
              ),
              StatCard(
                title: 'Open Tasks',
                value: '$activeTasks',
                subtitle: 'Backlog to testing',
                trendLabel: '${stats.overdueTasks} overdue',
                trendUp: stats.overdueTasks == 0,
                icon: Icons.pending_actions_rounded,
                color: AppTheme.warning,
              ),
              StatCard(
                title: 'Review Queue',
                value: '$reviewQueue',
                subtitle: 'Review + testing stages',
                trendLabel: reviewQueue <= 5 ? 'Controlled' : 'Heavy',
                trendUp: reviewQueue <= 5,
                icon: Icons.rate_review_rounded,
                color: AppTheme.violet,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _ExecutiveOverview(
            completedTasks: completedTasks,
            totalTasks: totalTasks,
            activeProjects: stats.activeProjects,
            delayedProjects: stats.delayedProjects,
            overdueTasks: stats.overdueTasks,
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth > 980;
              final left = SectionCard(
                title: 'Task Completion Trend',
                subtitle: 'This line updates when tasks move into Completed.',
                trailing: const StatusBadge(label: 'Live', color: AppTheme.success),
                child: TrendLineChart(points: completionTrend),
              );
              final right = SectionCard(
                title: 'Task Status Distribution',
                subtitle: 'Realtime count by Kanban stage.',
                child: StatusDonutChart(segments: statusSegments),
              );
              if (!twoColumns) return Column(children: [left, const SizedBox(height: 20), right]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: left), const SizedBox(width: 20), Expanded(flex: 5, child: right)]);
            },
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth > 980;
              final projectCard = SectionCard(
                title: 'Project Progress',
                subtitle: 'Progress is recalculated from completed tasks per project.',
                child: ProfessionalBarChart(items: projectProgress, showPercentOfTotal: true),
              );
              final workloadCard = SectionCard(
                title: 'Employee Workload',
                subtitle: 'Open assigned tasks by employee.',
                child: ProfessionalBarChart(items: employeeWorkload),
              );
              if (!twoColumns) return Column(children: [projectCard, const SizedBox(height: 20), workloadCard]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: projectCard), const SizedBox(width: 20), Expanded(child: workloadCard)]);
            },
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth > 980;
              final deadlines = SectionCard(
                title: 'Upcoming Deadlines',
                subtitle: 'Sorted by nearest due date.',
                child: Column(
                  children: upcoming.take(6).map((task) => _DeadlineRow(task: task)).toList(),
                ),
              );
              final stages = SectionCard(
                title: 'Project Stage Health',
                subtitle: 'Counts by planning, active, hold, review, completed, and cancelled stages.',
                child: ProfessionalBarChart(items: _projectStageHealth(state)),
              );
              if (!twoColumns) return Column(children: [deadlines, const SizedBox(height: 20), stages]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: deadlines), const SizedBox(width: 20), Expanded(child: stages)]);
            },
          ),
        ],
      ),
    );
  }

  static List<StatusSegment> _statusSegments(List<ProjectTask> tasks) {
    return TaskStatus.values.map((status) {
      final count = tasks.where((task) => task.status == status).length;
      return StatusSegment(label: status.label, value: count, color: status.color);
    }).toList();
  }

  static List<TrendPoint> _completionTrend(List<ProjectTask> tasks) {
    final now = DateTime.now();
    final months = List.generate(6, (index) => DateTime(now.year, now.month - 5 + index));
    return months.map((month) {
      final completed = tasks.where((task) => task.status == TaskStatus.completed && _sameMonth(task.dueDate, month)).length;
      return TrendPoint(label: _monthLabel(month), value: completed.toDouble());
    }).toList();
  }

  static List<BarMetric> _projectProgress(WorkspaceState state) {
    return state.visibleProjects.map((project) {
      final projectTasks = state.visibleTasks.where((task) => task.projectId == project.projectId).toList();
      final total = projectTasks.length;
      final completed = projectTasks.where((task) => task.status == TaskStatus.completed).length;
      final percent = total == 0 ? 0.0 : (completed / total) * 100;
      return BarMetric(label: project.name, value: percent, total: 100, color: project.status.color);
    }).toList();
  }

  static List<BarMetric> _employeeWorkload(WorkspaceState state) {
    final bars = state.activePortalMembers.map((member) {
      final activeCount = state.visibleTasks.where((task) => task.assignedToIds.contains(member.uid) && task.status != TaskStatus.completed).length;
      return BarMetric(label: member.displayName, value: activeCount.toDouble(), color: AppTheme.cyan);
    }).where((bar) => bar.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return bars.take(6).toList();
  }

  static List<BarMetric> _projectStageHealth(WorkspaceState state) {
    return ProjectStatus.values.map((status) {
      final count = state.visibleProjects.where((project) => project.status == status).length;
      return BarMetric(label: status.label, value: count.toDouble(), color: status.color);
    }).toList();
  }

  static bool _sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

  static String _monthLabel(DateTime date) {
    const labels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return labels[date.month - 1];
  }
}


class _MyPresencePanel extends ConsumerWidget {
  const _MyPresencePanel({required this.member, required this.onlineCount, required this.offlineCount});

  final Member member;
  final int onlineCount;
  final int offlineCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastSeenText = member.lastSeenAt == null ? 'Not recorded yet' : DateText.compact(member.lastSeenAt!);
    return SectionCard(
      title: 'My private dashboard status',
      subtitle: 'Control whether you are shown as online or offline to the company workspace.',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          StatusBadge(label: '$onlineCount online', color: AppTheme.success),
          StatusBadge(label: '$offlineCount offline', color: AppTheme.muted),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final statusCard = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: member.isOnline ? AppTheme.success.withOpacity(.06) : AppTheme.cardAlt,
              border: Border.all(color: member.isOnline ? AppTheme.success.withOpacity(.20) : AppTheme.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(color: member.isOnline ? AppTheme.success.withOpacity(.14) : AppTheme.slate200, shape: BoxShape.circle),
                  child: Icon(member.isOnline ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded, color: member.isOnline ? AppTheme.success : AppTheme.muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.isOnline ? 'You are online' : 'You are offline', style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(member.isOnline ? '${member.effectiveJobTitle} • ${member.effectiveDepartment}' : 'Last seen: $lastSeenText', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                StatusBadge(label: member.available ? 'Available' : 'Busy', color: member.available ? AppTheme.success : AppTheme.warning),
              ],
            ),
          );
          final controls = Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: member.isOnline,
                title: const Text('Show me online'),
                subtitle: const Text('Turn off when you do not want to appear active in employee/private dashboards.'),
                onChanged: (value) => ref.read(workspaceProvider.notifier).setMyOnlineStatus(value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: member.available,
                title: const Text('Available for work'),
                subtitle: const Text('Online means active; available means ready to take work.'),
                onChanged: (value) => ref.read(workspaceProvider.notifier).setMyAvailability(value),
              ),
            ],
          );
          if (compact) return Column(children: [statusCard, const SizedBox(height: 12), controls]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: statusCard), const SizedBox(width: 18), Expanded(child: controls)]);
        },
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.completionRate, required this.companyName, required this.roleDescription});
  final int completionRate;
  final String companyName;
  final String roleDescription;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.navy,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: AppTheme.navy.withOpacity(.08), blurRadius: 24, offset: const Offset(0, 14)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: Colors.white.withOpacity(.10), borderRadius: BorderRadius.circular(999)),
                child: const Text('Enterprise Project Control Center', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              const SizedBox(height: 14),
              Text('Dashboard • $companyName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 32, letterSpacing: -0.8)),
              const SizedBox(height: 8),
              Text(
                roleDescription,
                style: TextStyle(color: Colors.white.withOpacity(.76), height: 1.45),
              ),
            ],
          );
          final badge = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(.08), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white.withOpacity(.12))),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_graph_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$completionRate%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
                    Text('Live completion', style: TextStyle(color: Colors.white.withOpacity(.70), fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          );
          if (compact) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [content, const SizedBox(height: 18), badge]);
          return Row(children: [Expanded(child: content), const SizedBox(width: 20), badge]);
        },
      ),
    );
  }
}

class _ExecutiveOverview extends StatelessWidget {
  const _ExecutiveOverview({
    required this.completedTasks,
    required this.totalTasks,
    required this.activeProjects,
    required this.delayedProjects,
    required this.overdueTasks,
  });

  final int completedTasks;
  final int totalTasks;
  final int activeProjects;
  final int delayedProjects;
  final int overdueTasks;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Execution Health',
      subtitle: 'All values below are calculated from the current task and project state.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 840;
          final chart = Center(child: CompletionDonutChart(completed: completedTasks, total: totalTasks));
          final metrics = Column(
            children: [
              MetricPill(label: 'Active projects', value: '$activeProjects', icon: Icons.folder_open_rounded, color: AppTheme.blue),
              const SizedBox(height: 10),
              MetricPill(label: 'Delayed projects', value: '$delayedProjects', icon: Icons.warning_amber_rounded, color: AppTheme.warning),
              const SizedBox(height: 10),
              MetricPill(label: 'Overdue tasks', value: '$overdueTasks', icon: Icons.timer_off_rounded, color: AppTheme.danger),
            ],
          );
          if (compact) return Column(children: [chart, const SizedBox(height: 18), metrics]);
          return Row(children: [chart, const SizedBox(width: 26), Expanded(child: metrics)]);
        },
      ),
    );
  }
}

class _DeadlineRow extends StatelessWidget {
  const _DeadlineRow({required this.task});
  final ProjectTask task;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: task.isOverdue ? AppTheme.danger.withOpacity(.06) : AppTheme.cardAlt,
        border: Border.all(color: task.isOverdue ? AppTheme.danger.withOpacity(.14) : AppTheme.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(color: task.priority.color.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.flag_rounded, color: task.priority.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('Due ${DateText.compact(task.dueDate)}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Wrap(spacing: 8, children: [
            StatusBadge(label: task.status.label, color: task.status.color),
            StatusBadge(label: task.priority.label, color: task.priority.color),
          ]),
        ],
      ),
    );
  }
}