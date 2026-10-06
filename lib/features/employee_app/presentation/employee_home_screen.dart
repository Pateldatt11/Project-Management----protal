import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/deadline_countdown_chip.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/project.dart';
import '../../../data/models/task.dart';


const Color _pmdCanvas = Color(0xFFF3F4F1);
const Color _pmdInk = Color(0xFF0A0D0A);
const Color _pmdDeep = Color(0xFF344D50);
const Color _pmdMoss = Color(0xFF405446);
const Color _pmdSage = Color(0xFF8F9168);
const Color _pmdMuted = Color(0xFF687269);
const Color _pmdBorder = Color(0xFFD9DFDA);

class EmployeeHomeScreen extends ConsumerWidget {
  const EmployeeHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final config = state.mobileUiConfig;
    final cards = (config.enabled ? config.homeCards : <String>['deadlineTimer', 'myOpenTasks', 'todayTasks', 'projectProgress', 'onlineStatus']).where((card) => card != 'workSummary').toList();
    final compact = config.compactMode;
    return ColoredBox(
      color: _pmdCanvas,
      child: ListView(
      padding: EdgeInsets.all(compact ? 14 : 18),
      children: [
        _HeaderCard(compact: compact),
        SizedBox(height: compact ? 10 : 14),
        for (final card in cards) ...[
          _buildCard(card, compact),
          SizedBox(height: compact ? 10 : 14),
        ],
      ],
      ),
    );
  }

  Widget _buildCard(String card, bool compact) {
    return switch (card) {
      'deadlineTimer' => _DeadlineCard(compact: compact),
      'myOpenTasks' => _OpenTasksCard(compact: compact),
      'todayTasks' => _TodayTasksCard(compact: compact),
      'projectProgress' => _ProjectProgressCard(compact: compact),
      'onlineStatus' => _OnlineStatusCard(compact: compact),
      _ => const SizedBox.shrink(),
    };
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final member = state.currentMember;
    final openTasks = state.visibleTasks.where((task) => task.status != TaskStatus.completed).length;
    final activeProjects = state.visibleProjects.where((project) => project.status != ProjectStatus.completed).length;
    return Container(
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        color: _pmdInk,
        borderRadius: BorderRadius.circular(compact ? 28 : 34),
        boxShadow: [BoxShadow(color: _pmdInk.withOpacity(.20), blurRadius: 30, offset: const Offset(0, 18))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: compact ? 22 : 26,
                backgroundColor: const Color(0xFFCCD2CD),
                child: Text(
                  member.displayName.isEmpty ? 'E' : member.displayName.characters.first.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900, color: _pmdInk),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Project Management Dashboard', style: TextStyle(color: Colors.white.withOpacity(.72), fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Hi, ${member.displayName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -.6)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: member.available ? const Color(0xFFCCD2CD) : _pmdSage.withOpacity(.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(member.available ? 'Available' : 'Busy', style: const TextStyle(color: _pmdInk, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Track assigned work, project progress, deadlines, and team updates in one calm mobile workspace.',
            style: TextStyle(color: Colors.white.withOpacity(.76), height: 1.35, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _HeroMetric(label: 'Open tasks', value: '$openTasks')),
              const SizedBox(width: 10),
              Expanded(child: _HeroMetric(label: 'Projects', value: '$activeProjects')),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(.70), fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _DeadlineCard extends ConsumerWidget {
  const _DeadlineCard({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = _visibleTasks(ref).where((task) => task.status != TaskStatus.completed).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final task = tasks.isEmpty ? null : tasks.first;
    return _SurfaceCard(
      compact: compact,
      title: 'Closest deadline',
      icon: Icons.timer_rounded,
      child: task == null
          ? const Text('No open task deadlines.', style: TextStyle(color: _pmdMuted, fontWeight: FontWeight.w700))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  DeadlineCountdownChip(deadline: task.dueDate, compact: compact),
                  StatusBadge(label: task.priority.label, color: task.priority.color),
                ]),
              ],
            ),
    );
  }
}

class _OpenTasksCard extends ConsumerWidget {
  const _OpenTasksCard({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = _visibleTasks(ref).where((task) => task.status != TaskStatus.completed).toList();
    return _MetricCard(compact: compact, icon: Icons.task_alt_rounded, title: 'My open tasks', value: '${tasks.length}', subtitle: 'Assigned and not completed');
  }
}

class _TodayTasksCard extends ConsumerWidget {
  const _TodayTasksCard({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final tasks = _visibleTasks(ref).where((task) => task.dueDate.year == now.year && task.dueDate.month == now.month && task.dueDate.day == now.day).toList();
    return _SurfaceCard(
      compact: compact,
      title: 'Today tasks',
      icon: Icons.today_rounded,
      child: tasks.isEmpty
          ? const Text('No tasks due today.', style: TextStyle(color: _pmdMuted, fontWeight: FontWeight.w700))
          : Column(
              children: tasks.take(4).map((task) => ListTile(
                    dense: compact,
                    contentPadding: EdgeInsets.zero,
                    title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(DateText.compact(task.dueDate)),
                    trailing: StatusBadge(label: task.status.label, color: task.status.color),
                  )).toList(),
            ),
    );
  }
}

class _ProjectProgressCard extends ConsumerWidget {
  const _ProjectProgressCard({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final projects = state.visibleProjects.take(4).toList();
    return _SurfaceCard(
      compact: compact,
      title: 'My project progress',
      icon: Icons.folder_copy_rounded,
      child: projects.isEmpty
          ? const Text('No visible projects yet.', style: TextStyle(color: _pmdMuted, fontWeight: FontWeight.w700))
          : Column(
              children: projects.map((project) => _ProjectProgressRow(project: project, compact: compact)).toList(),
            ),
    );
  }
}

class _OnlineStatusCard extends ConsumerWidget {
  const _OnlineStatusCard({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final member = state.currentMember;
    return _SurfaceCard(
      compact: compact,
      title: 'Online status',
      icon: Icons.wifi_tethering_rounded,
      child: Row(
        children: [
          Icon(member.isOnline ? Icons.circle : Icons.radio_button_unchecked, color: member.isOnline ? _pmdMoss : Colors.grey, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(member.isOnline ? 'You are online' : 'You are offline', style: const TextStyle(fontWeight: FontWeight.w900))),
          StatusBadge(label: member.available ? 'Available' : 'Busy', color: member.available ? _pmdMoss : _pmdSage),
        ],
      ),
    );
  }
}

class _ProjectProgressRow extends ConsumerWidget {
  const _ProjectProgressRow({required this.project, required this.compact});
  final Project project;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final tasks = state.visibleTasks.where((task) => task.projectId == project.projectId).toList();
    final completed = tasks.where((task) => task.status == TaskStatus.completed).length;
    final progress = tasks.isEmpty ? project.progress / 100 : completed / tasks.length;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 10 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
            Text('${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress.clamp(0, 1).toDouble(), minHeight: compact ? 7 : 9, borderRadius: BorderRadius.circular(999)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.compact, required this.icon, required this.title, required this.value, required this.subtitle});
  final bool compact;
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      compact: compact,
      title: title,
      icon: icon,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(width: 10),
          Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(subtitle, style: const TextStyle(color: _pmdMuted, fontWeight: FontWeight.w700)))),
        ],
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.compact, required this.child, this.title, this.icon});
  final bool compact;
  final Widget child;
  final String? title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _pmdBorder),
        borderRadius: BorderRadius.circular(compact ? 24 : 28),
        boxShadow: [BoxShadow(color: _pmdInk.withOpacity(.045), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(children: [
              if (icon != null) ...[Container(width: 34, height: 34, decoration: BoxDecoration(color: const Color(0xFFCCD2CD).withOpacity(.55), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: _pmdDeep, size: 18)), const SizedBox(width: 10)],
              Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
            ]),
            SizedBox(height: compact ? 10 : 14),
          ],
          child,
        ],
      ),
    );
  }
}

List<ProjectTask> _visibleTasks(WidgetRef ref) => ref.watch(workspaceProvider).visibleTasks;
