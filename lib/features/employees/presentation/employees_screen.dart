import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_theme.dart';
import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/member.dart';

class EmployeesScreen extends ConsumerWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final currentMember = state.currentMember;
    final canInvite = PermissionService.canInviteMembers(currentMember);
    final canChangeRoles = PermissionService.canManagePeople(currentMember);
    final onlineCount = state.onlineMembers.length;
    final offlineCount = state.offlineMembers.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: SectionCard(
        title: 'Employees',
        subtitle: 'Manage employee profiles, workload, availability, roles, and working projects from the admin web panel.',
        trailing: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge(label: '$onlineCount online', color: AppTheme.success),
            StatusBadge(label: '$offlineCount offline', color: AppTheme.muted),
            if (canChangeRoles) StatusBadge(label: 'Role upgrade enabled', color: AppTheme.blue),
            FilledButton.icon(
              onPressed: canInvite ? () => _showInviteDialog(context, ref) : null,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Invite Employee'),
            ),
          ],
        ),
        child: Column(
          children: state.members.map((member) {
            final roleActive = state.isPortalPostActive(member.role);
            final assignedTasks = state.tasks.where((task) => task.assignedToIds.contains(member.uid)).toList();
            final completed = assignedTasks.where((task) => task.status == TaskStatus.completed).length;
            final openTasks = assignedTasks.length - completed;
            final completion = assignedTasks.isEmpty ? 0.0 : completed / assignedTasks.length;
            final workingProjects = state.projects.where((project) => member.projectIds.contains(project.projectId) || assignedTasks.any((task) => task.projectId == project.projectId)).toList();
            final memberTeams = state.teams.where((team) => team.memberIds.contains(member.uid)).toList();
            final capacityUsed = (openTasks * 8 / member.capacityHoursPerWeek).clamp(0, 1).toDouble();
            final canEditThisRole = canChangeRoles && member.uid != state.user.uid;
            return _EmployeeCard(
              member: member,
              roleActive: roleActive,
              openTasks: openTasks,
              assignedTasks: assignedTasks.length,
              completedTasks: completed,
              completion: completion,
              capacityUsed: capacityUsed,
              projects: workingProjects.map((p) => p.name).toList(),
              teams: memberTeams.map((t) => t.name).toList(),
              lastSeenText: _presenceDetail(member),
              canChangeRole: canEditThisRole,
              onChangeRole: () => _showRoleDialog(context, ref, member),
            );
          }).toList(),
        ),
      ),
    );
  }

  static String _presenceDetail(Member member) {
    if (member.isOnline) return member.available ? 'Online • Available' : 'Online • Busy';
    if (member.lastSeenAt == null) return 'Offline';
    return 'Offline • Last seen ${DateText.compact(member.lastSeenAt!)}';
  }

  Future<void> _showRoleDialog(BuildContext context, WidgetRef ref, Member member) async {
    final state = ref.read(workspaceProvider);
    var roleOptions = state.activePortalRoles.toList();
    if (roleOptions.isEmpty) roleOptions = UserRole.values.toList();
    if (state.currentMember.role != UserRole.superAdmin) {
      roleOptions = roleOptions.where((role) => role != UserRole.superAdmin).toList();
    }
    if (!roleOptions.contains(member.role) && state.isPortalPostActive(member.role)) {
      roleOptions = [member.role, ...roleOptions];
    }
    if (roleOptions.isEmpty) roleOptions = [member.role];
    var selectedRole = roleOptions.contains(member.role) ? member.role : roleOptions.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Upgrade / downgrade role'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.displayName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(member.email, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                DropdownButtonFormField<UserRole>(
                  value: selectedRole,
                  decoration: const InputDecoration(labelText: 'New role / post'),
                  items: roleOptions.map((role) => DropdownMenuItem(value: role, child: Text('${role.label} • ${role.department}'))).toList(),
                  onChanged: (value) => setDialogState(() => selectedRole = value ?? selectedRole),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: selectedRole.color.withOpacity(.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: selectedRole.color.withOpacity(.22))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.admin_panel_settings_rounded, color: selectedRole.color),
                      const SizedBox(width: 10),
                      Expanded(child: Text(selectedRole.description, style: const TextStyle(fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: selectedRole == member.role ? null : () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.swap_vert_rounded),
              label: const Text('Apply role'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;
    ref.read(workspaceProvider.notifier).updateMemberRole(uid: member.uid, role: selectedRole);
    final error = ref.read(workspaceProvider).lastError;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? '${member.displayName} role updated to ${selectedRole.label}.')));
  }

  Future<void> _showInviteDialog(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final department = TextEditingController();
    final jobTitle = TextEditingController();
    final location = TextEditingController(text: 'Remote');
    final capacity = TextEditingController(text: '40');
    final taskForceName = TextEditingController();
    final state = ref.read(workspaceProvider);
    var activeRoles = state.activePortalRoles.where((role) => !role.isCorePortalPost || role == UserRole.admin).toList();
    if (activeRoles.isEmpty) activeRoles = <UserRole>[UserRole.employee];
    UserRole role = activeRoles.contains(UserRole.developer) ? UserRole.developer : activeRoles.first;
    bool createTaskForce = false;
    final selectedMemberIds = <String>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add employee / task force'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('HR can add a new employee, choose the post/role, fill personal work details, and optionally create a company task force in the same flow.', style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoCols = constraints.maxWidth > 560;
                      final first = Column(
                        children: [
                          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
                          const SizedBox(height: 12),
                          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<UserRole>(
                            value: role,
                            decoration: const InputDecoration(labelText: 'Role / Post'),
                            items: activeRoles.map((item) => DropdownMenuItem(value: item, child: Text('${item.label} • ${item.department}'))).toList(),
                            onChanged: (value) => setState(() => role = value ?? role),
                          ),
                        ],
                      );
                      final second = Column(
                        children: [
                          TextField(controller: department, decoration: InputDecoration(labelText: 'Department', hintText: role.department)),
                          const SizedBox(height: 12),
                          TextField(controller: jobTitle, decoration: InputDecoration(labelText: 'Job title', hintText: role.label)),
                          const SizedBox(height: 12),
                          TextField(controller: location, decoration: const InputDecoration(labelText: 'Location')),
                          const SizedBox(height: 12),
                          TextField(controller: capacity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacity hours / week')),
                        ],
                      );
                      if (!twoCols) return Column(children: [first, const SizedBox(height: 12), second]);
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: first), const SizedBox(width: 14), Expanded(child: second)]);
                    },
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: createTaskForce,
                    title: const Text('Create company task force now', style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: const Text('Creates a team/task force and adds this employee plus selected members.'),
                    onChanged: (value) => setState(() => createTaskForce = value),
                  ),
                  if (createTaskForce) ...[
                    const SizedBox(height: 8),
                    TextField(controller: taskForceName, decoration: const InputDecoration(labelText: 'Task force name', hintText: 'Example: Mobile Delivery Task Force')),
                    const SizedBox(height: 12),
                    const Text('Add existing members to this task force', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: state.activePortalMembers.map((member) {
                        final selected = selectedMemberIds.contains(member.uid);
                        return FilterChip(
                          selected: selected,
                          label: Text('${member.displayName} • ${member.role.shortLabel}'),
                          avatar: CircleAvatar(backgroundColor: member.role.color, child: Text(member.role.shortLabel.characters.first, style: const TextStyle(color: Colors.white, fontSize: 10))),
                          onSelected: (value) => setState(() {
                            if (value) {
                              selectedMemberIds.add(member.uid);
                            } else {
                              selectedMemberIds.remove(member.uid);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () {
                if (name.text.trim().isEmpty || email.text.trim().isEmpty) return;
                ref.read(workspaceProvider.notifier).addEmployeeWithTaskForce(
                      name: name.text,
                      email: email.text,
                      role: role,
                      department: department.text,
                      jobTitle: jobTitle.text,
                      location: location.text,
                      capacityHoursPerWeek: num.tryParse(capacity.text) ?? 40,
                      taskForceName: createTaskForce ? taskForceName.text : null,
                      taskForceMemberIds: selectedMemberIds.toList(),
                    );
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(createTaskForce ? 'Employee and task force added.' : 'Employee added.')));
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add employee'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.member,
    required this.roleActive,
    required this.openTasks,
    required this.assignedTasks,
    required this.completedTasks,
    required this.completion,
    required this.capacityUsed,
    required this.projects,
    required this.teams,
    required this.lastSeenText,
    required this.canChangeRole,
    required this.onChangeRole,
  });

  final Member member;
  final bool roleActive;
  final int openTasks;
  final int assignedTasks;
  final int completedTasks;
  final double completion;
  final double capacityUsed;
  final List<String> projects;
  final List<String> teams;
  final String lastSeenText;
  final bool canChangeRole;
  final VoidCallback onChangeRole;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(24)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final header = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(radius: 28, backgroundColor: member.role.color.withOpacity(.10), foregroundColor: member.role.color, child: Text(member.displayName.characters.first.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900))),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(member.displayName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(member.email),
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          StatusBadge(label: member.role.label, color: roleActive ? member.role.color : Colors.grey),
                          StatusBadge(label: member.isOnline ? 'Online' : 'Offline', color: member.isOnline ? AppTheme.success : AppTheme.muted),
                          StatusBadge(label: roleActive ? 'Post active' : 'Post off', color: roleActive ? AppTheme.success : AppTheme.danger),
                          StatusBadge(label: member.available ? 'Available' : 'Busy', color: member.available ? AppTheme.success : AppTheme.warning),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
              if (canChangeRole) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onChangeRole,
                  icon: const Icon(Icons.swap_vert_rounded),
                  label: const Text('Upgrade / downgrade role'),
                ),
              ],
            ],
          );

          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoLine(label: 'Job title', value: member.effectiveJobTitle),
              _InfoLine(label: 'Department', value: member.effectiveDepartment),
              _InfoLine(label: 'Location', value: member.location),
              _InfoLine(label: 'Presence', value: lastSeenText),
              _InfoLine(label: 'Teams', value: teams.isEmpty ? 'No team assigned' : teams.join(', ')),
              _InfoLine(label: 'Working projects', value: projects.isEmpty ? 'No active project' : projects.join(', ')),
            ],
          );

          final metrics = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProgressLine(label: 'Task completion', value: completion, text: '$completedTasks/$assignedTasks completed', color: AppTheme.success),
              const SizedBox(height: 12),
              _ProgressLine(label: 'Capacity used', value: capacityUsed, text: '$openTasks open tasks • ${member.capacityHoursPerWeek}h/week', color: capacityUsed > .85 ? AppTheme.danger : AppTheme.blue),
            ],
          );

          if (compact) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [header, const SizedBox(height: 16), info, const SizedBox(height: 16), metrics]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: header), const SizedBox(width: 18), Expanded(flex: 5, child: info), const SizedBox(width: 18), Expanded(flex: 4, child: metrics)]);
        },
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 112, child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w900))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.label, required this.value, required this.text, required this.color});
  final String label;
  final double value;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900))), Text(text, style: Theme.of(context).textTheme.bodySmall)]),
      const SizedBox(height: 8),
      TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => LinearProgressIndicator(value: animated, minHeight: 9, color: color, borderRadius: BorderRadius.circular(999)),
      ),
    ]);
  }
}
