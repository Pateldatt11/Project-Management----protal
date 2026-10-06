import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_theme.dart';
import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_badge.dart';

class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final canCreate = PermissionService.canManageTaskForces(state.currentMember);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: SectionCard(
        title: 'Teams',
        subtitle: 'Create teams with selected members, choose team lead, and monitor delivery progress by team workload.',
        trailing: FilledButton.icon(
          onPressed: canCreate ? () => _showTeamDialog(context, ref) : null,
          icon: const Icon(Icons.group_add_rounded),
          label: const Text('New Team'),
        ),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: state.teams.map((team) {
            final leadMatches = state.members.where((m) => m.uid == team.leadId);
            final lead = leadMatches.isEmpty ? null : leadMatches.first;
            final members = state.members.where((member) => team.memberIds.contains(member.uid)).toList();
            final openTasks = state.visibleTasks.where((task) => task.teamId == team.teamId && !task.isCompleted).length;
            final completedTasks = state.visibleTasks.where((task) => task.teamId == team.teamId && task.isCompleted).length;
            final total = openTasks + completedTasks;
            final completion = total == 0 ? 0.0 : completedTasks / total;
            final activeProjects = state.projects.where((project) => project.teamIds.contains(team.teamId)).length;
            return SizedBox(
              width: 420,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            height: 44,
                            width: 44,
                            decoration: BoxDecoration(color: AppTheme.blueSoft, borderRadius: BorderRadius.circular(15)),
                            child: const Icon(Icons.groups_rounded, color: AppTheme.blue),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(team.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                          StatusBadge(label: '${members.length} members', color: AppTheme.blue),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text('Lead: ${lead?.displayName ?? 'Not assigned'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('Active projects: $activeProjects • Open tasks: $openTasks • Completed: $completedTasks'),
                      const SizedBox(height: 14),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: completion),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => LinearProgressIndicator(value: value, minHeight: 9, borderRadius: BorderRadius.circular(999)),
                      ),
                      const SizedBox(height: 8),
                      Text('Team completion ${(completion * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 14),
                      const Text('Members', style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: members.map((member) => Chip(
                          avatar: CircleAvatar(child: Text(member.displayName.characters.first.toUpperCase())),
                          label: Text('${member.displayName} • ${member.role.shortLabel}'),
                        )).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _showTeamDialog(BuildContext context, WidgetRef ref) async {
    final state = ref.read(workspaceProvider);
    final name = TextEditingController();
    final activeMembers = state.activePortalMembers.where((member) => member.role != UserRole.clientViewer).toList();
    if (activeMembers.isEmpty) return;
    String leadId = activeMembers.firstWhere((member) => member.role == UserRole.teamLead, orElse: () => activeMembers.first).uid;
    final selectedMemberIds = <String>{leadId};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create team'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Team name')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: leadId,
                    decoration: const InputDecoration(labelText: 'Team lead'),
                    items: activeMembers.map((member) => DropdownMenuItem(value: member.uid, child: Text('${member.displayName} • ${member.role.shortLabel}'))).toList(),
                    onChanged: (value) => setState(() {
                      leadId = value ?? leadId;
                      selectedMemberIds.add(leadId);
                    }),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select team members', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: activeMembers.map((member) {
                      final selected = selectedMemberIds.contains(member.uid);
                      return FilterChip(
                        selected: selected,
                        avatar: CircleAvatar(child: Text(member.role.shortLabel.characters.first)),
                        label: Text('${member.displayName} • ${member.effectiveDepartment}'),
                        onSelected: member.uid == leadId
                            ? null
                            : (value) => setState(() => value ? selectedMemberIds.add(member.uid) : selectedMemberIds.remove(member.uid)),
                      );
                    }).toList(),
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
                ref.read(workspaceProvider.notifier).createTeam(name: name.text, leadId: leadId, memberIds: selectedMemberIds.toList());
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
