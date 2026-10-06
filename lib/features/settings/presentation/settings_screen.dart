import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/workspace_state.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/navigation/navigation_preferences.dart';
import '../../../core/timeline/timeline_preferences.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_badge.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final member = state.currentMember;
    final canViewAudit = PermissionService.canViewAuditLogs(member);
    final canManageSettings = PermissionService.canManageSettings(member);
    final companyConfigured = state.company.companyId != 'platform' && state.company.status == 'active';
    
    // Fallback company name or active workspace name matching user's requirements
    final companyName = state.company.name.isNotEmpty && state.company.name != 'Company Workspace'
        ? state.company.name
        : (state.company.companyId != 'platform' ? state.company.name : 'Company Workspace');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          if (member.role == UserRole.superAdmin && AppConfig.useFirebase) ...[
            const _SuperAdminCompanySetupControl(),
            const SizedBox(height: 18),
          ],
          SectionCard(
            title: 'Company Settings',
            subtitle: 'Workspace, timezone, notification, security, storage, and IT settings. Firebase mode will enforce these rules server-side.',
            child: Column(
              children: [
                ListTile(leading: const Icon(Icons.business_rounded), title: const Text('Company'), subtitle: Text(companyName)),
                ListTile(leading: const Icon(Icons.public_rounded), title: const Text('Timezone'), subtitle: Text(state.company.timezone)),
                ListTile(leading: const Icon(Icons.verified_user_rounded), title: const Text('Current access'), subtitle: Text('${member.role.label} • ${member.effectiveDepartment}')),
                SwitchListTile(value: true, onChanged: canManageSettings ? (_) {} : null, title: const Text('Enable realtime notifications')),
                SwitchListTile(value: true, onChanged: canManageSettings ? (_) {} : null, title: const Text('Require audit logs for sensitive actions')),
                SwitchListTile(value: true, onChanged: PermissionService.canManageInfrastructure(member) ? (_) {} : null, title: const Text('Restrict storage uploads by file type and size')),
              ],
            ),
          ),
          if (companyConfigured) ...[
            const SizedBox(height: 18),
            if (kIsWeb) ...[
              const _NavigationPersonalizationControl(),
              const SizedBox(height: 18),
              const _TimelineSettingsControl(),
              const SizedBox(height: 18),
            ],
            const _DemoDataControl(),
            const SizedBox(height: 18),
            
            const _PortalPostControl(),
          ],
          if (companyConfigured) ...[
            const SizedBox(height: 18),
            SectionCard(
              title: 'Industrial Role Permission Matrix',
              subtitle: 'Permissions are applied only when the post is active. Deactivated posts disappear from login, invite, task assignment, and portal navigation.',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Post')),
                    DataColumn(label: Text('Portal')),
                    DataColumn(label: Text('Projects')),
                    DataColumn(label: Text('Tasks')),
                    DataColumn(label: Text('Kanban')),
                    DataColumn(label: Text('People')),
                    DataColumn(label: Text('Reports')),
                    DataColumn(label: Text('Settings')),
                  ],
                  rows: UserRole.values.map((role) {
                    final fake = member.copyWith(role: role);
                    final active = state.isPortalPostActive(role);
                    return DataRow(cells: [
                      DataCell(Row(children: [StatusBadge(label: role.shortLabel, color: active ? role.color : Colors.grey), const SizedBox(width: 8), Text(role.label)])),
                      DataCell(Text(active ? 'Active' : 'Deactivated')),
                      DataCell(Text(!active ? 'Off' : PermissionService.canManageProjects(fake) ? 'Manage' : role == UserRole.clientViewer ? 'View shared' : 'Assigned scope')),
                      DataCell(Text(!active ? 'Off' : PermissionService.canCreateTasks(fake) ? 'Create/assign' : PermissionService.canUpdateOwnTask(fake) ? 'Own tasks' : 'Read only')),
                      DataCell(Text(!active ? 'Off' : PermissionService.canMoveKanban(fake) ? 'Move cards' : 'No move')),
                      DataCell(Text(!active ? 'Off' : PermissionService.canManagePeople(fake) ? 'Manage' : 'Directory scope')),
                      DataCell(Text(!active ? 'Off' : PermissionService.canGenerateReports(fake) ? 'Generate' : PermissionService.canViewReports(fake) ? 'View' : 'Denied')),
                      DataCell(Text(!active ? 'Off' : PermissionService.canManageSettings(fake) ? 'Manage' : 'Denied')),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
          if (companyConfigured) ...[
            const SizedBox(height: 18),
            SectionCard(
              title: 'Audit Logs',
              subtitle: canViewAudit ? 'Append-only industrial audit trail for sensitive actions.' : 'Only Super Admin, Company Admin, and IT Admin can view detailed audit logs.',
              child: canViewAudit
                  ? Column(
                      children: state.auditLogs.take(12).map((log) => ListTile(
                            leading: const Icon(Icons.verified_user_rounded),
                            title: Text(log.action),
                            subtitle: Text('${log.targetType} • ${log.actorId} • ${DateText.compact(log.createdAt)}'),
                          )).toList(),
                    )
                  : const ListTile(
                      leading: Icon(Icons.lock_rounded),
                      title: Text('Audit log locked'),
                      subtitle: Text('Use an Admin or IT Admin login to view audit history.'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DemoDataControl extends ConsumerWidget {
  const _DemoDataControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final member = state.currentMember;
    final canManage = PermissionService.canManageSettings(member);
    final firestoreOnly = AppConfig.useFirebase && !state.demoDataEnabled;
    final nextEnabled = !state.demoDataEnabled;

    return SectionCard(
      title: 'Admin Data Source Control',
      subtitle: 'Enable demo overlay for training/testing, or disable it so the portal displays only real Firestore documents.',
      trailing: StatusBadge(
        label: firestoreOnly ? 'Firestore only' : state.demoDataEnabled ? 'Demo overlay on' : 'Demo off',
        color: firestoreOnly ? Colors.green : Colors.orange,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: firestoreOnly ? Colors.green.withOpacity(.08) : Colors.orange.withOpacity(.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: firestoreOnly ? Colors.green.withOpacity(.18) : Colors.orange.withOpacity(.18)),
            ),
            child: Row(
              children: [
                Icon(firestoreOnly ? Icons.cloud_done_rounded : Icons.science_rounded, color: firestoreOnly ? Colors.green : Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    firestoreOnly
                        ? 'Demo data is disabled. Projects, tasks, members, teams, reports, notifications, and logs now come only from Firestore streams.'
                        : 'Demo data is enabled. The app can show demo records alongside Firestore records for training and presentation.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              StatusBadge(label: state.dataSourceLabel, color: firestoreOnly ? Colors.green : Colors.orange),
              StatusBadge(label: '${state.projects.length} projects loaded', color: Colors.blueGrey),
              StatusBadge(label: '${state.tasks.length} tasks loaded', color: Colors.blueGrey),
              StatusBadge(label: '${state.members.length} members loaded', color: Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final toggle = SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.demoDataEnabled,
                onChanged: canManage ? (value) => ref.read(workspaceProvider.notifier).setDemoDataEnabled(value) : null,
                title: const Text('Show demo data overlay'),
                subtitle: const Text('Turn this off before production testing so only Firestore data is visible.'),
              );
              final button = FilledButton.icon(
                onPressed: canManage ? () => ref.read(workspaceProvider.notifier).setDemoDataEnabled(nextEnabled) : null,
                icon: Icon(nextEnabled ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                label: Text(nextEnabled ? 'Enable demo data' : 'Disable demo data'),
              );
              if (compact) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [toggle, const SizedBox(height: 10), button]);
              }
              return Row(children: [Expanded(child: toggle), const SizedBox(width: 12), button]);
            },
          ),
          if (!canManage) ...[
            const SizedBox(height: 10),
            const Text('Only Super Admin, Company Admin, and IT Admin can change this setting.', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}

class _PortalPostControl extends ConsumerWidget {
  const _PortalPostControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final member = state.currentMember;
    final canManage = PermissionService.canManageSettings(member);
    final activeCount = state.activePortalRoles.length;
    final totalCount = UserRole.values.length;
    return SectionCard(
      title: 'IT Admin Portal Post Control',
      subtitle: 'Choose exactly which posts/roles are active in this company portal. Disabled posts cannot login in demo mode, cannot be invited, cannot receive task assignment, and should be blocked by Firestore settings in production.',
      trailing: StatusBadge(label: '$activeCount/$totalCount active', color: activeCount == totalCount ? Colors.green : Colors.orange),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withOpacity(.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blueGrey.withOpacity(.12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Protected posts cannot be turned off: Super Admin, Company Admin, and IT Admin. This prevents company lockout.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 780;
              final cards = UserRole.values.map((role) => _PortalPostTile(role: role, canManage: canManage)).toList();
              if (compact) {
                return Column(children: cards.map((card) => Padding(padding: const EdgeInsets.only(bottom: 10), child: card)).toList());
              }
              return Wrap(spacing: 12, runSpacing: 12, children: cards.map((card) => SizedBox(width: 360, child: card)).toList());
            },
          ),
        ],
      ),
    );
  }
}

class _PortalPostTile extends ConsumerWidget {
  const _PortalPostTile({required this.role, required this.canManage});
  final UserRole role;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final active = state.isPortalPostActive(role);
    final memberCount = state.members.where((member) => member.role == role).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: active ? role.color.withOpacity(.26) : Colors.grey.withOpacity(.26)),
        color: active ? role.color.withOpacity(.07) : Colors.grey.withOpacity(.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(backgroundColor: active ? role.color : Colors.grey, child: Text(role.shortLabel.characters.first, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(role.label, style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('$memberCount member${memberCount == 1 ? '' : 's'} • ${role.department}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Switch(
                value: active,
                onChanged: !canManage || !role.canBePortalDeactivated ? null : (value) => ref.read(workspaceProvider.notifier).setPortalPostActive(role, value),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(role.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusBadge(label: active ? 'Active in portal' : 'Deactivated', color: active ? Colors.green : Colors.redAccent),
              if (role.isCorePortalPost) const StatusBadge(label: 'Protected', color: Colors.black54),
              if (!role.isCorePortalPost) StatusBadge(label: active ? 'Can login' : 'Login hidden', color: active ? role.color : Colors.grey),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuperAdminCompanySetupControl extends ConsumerStatefulWidget {
  const _SuperAdminCompanySetupControl();

  @override
  ConsumerState<_SuperAdminCompanySetupControl> createState() => _SuperAdminCompanySetupControlState();
}

class _SuperAdminCompanySetupControlState extends ConsumerState<_SuperAdminCompanySetupControl> {
  final _companyName = TextEditingController();
  final _legalName = TextEditingController();
  final _industry = TextEditingController(text: 'Software');
  final _timezone = TextEditingController(text: 'Asia/Kolkata');
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _stateName = TextEditingController();
  final _country = TextEditingController(text: 'India');
  final _ownerName = TextEditingController();

  @override
  void dispose() {
    _companyName.dispose();
    _legalName.dispose();
    _industry.dispose();
    _timezone.dispose();
    _email.dispose();
    _phone.dispose();
    _website.dispose();
    _address.dispose();
    _city.dispose();
    _stateName.dispose();
    _country.dispose();
    _ownerName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final isConfigured = state.company.companyId != 'platform' && state.company.status == 'active';
    final companyName = state.company.name.isNotEmpty ? state.company.name : 'Company Workspace';

    return SectionCard(
      title: 'Super Admin Company Setup',
      subtitle: 'Fill company information once. The app will create the company, Super Admin member, settings, membership, and bootstrap docs in Firestore automatically.',
      trailing: StatusBadge(label: isConfigured ? 'Company ready' : 'Setup required', color: isConfigured ? Colors.green : Colors.orange),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isConfigured ? Colors.green.withOpacity(.08) : Colors.orange.withOpacity(.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isConfigured ? Colors.green.withOpacity(.18) : Colors.orange.withOpacity(.18)),
            ),
            child: Row(
              children: [
                Icon(isConfigured ? Icons.verified_rounded : Icons.admin_panel_settings_rounded, color: isConfigured ? Colors.green : Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isConfigured
                        ? '$companyName is configured. You can now add HR/Admin/Team Lead/Developer employees from the Employees page.'
                        : 'Only the manually-created Platform Super Admin can see this setup card. Complete it once to generate all company Firestore documents.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!isConfigured) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final twoCols = constraints.maxWidth >= 760;
                final fields = <Widget>[
                  TextField(controller: _companyName, decoration: const InputDecoration(labelText: 'Company name *')),
                  TextField(controller: _ownerName, decoration: const InputDecoration(labelText: 'Owner / Admin Name *')),
                  TextField(controller: _legalName, decoration: const InputDecoration(labelText: 'Legal company name')),
                  TextField(controller: _industry, decoration: const InputDecoration(labelText: 'Industry')),
                  TextField(controller: _timezone, decoration: const InputDecoration(labelText: 'Timezone')),
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Company email')),
                  TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Company phone')),
                  TextField(controller: _website, decoration: const InputDecoration(labelText: 'Website')),
                  TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
                  TextField(controller: _city, decoration: const InputDecoration(labelText: 'City')),
                  TextField(controller: _stateName, decoration: const InputDecoration(labelText: 'State')),
                  TextField(controller: _country, decoration: const InputDecoration(labelText: 'Country')),
                ];
                if (!twoCols) {
                  return Column(children: fields.map((field) => Padding(padding: const EdgeInsets.only(bottom: 12), child: field)).toList());
                }
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: fields.map((field) => SizedBox(width: (constraints.maxWidth - 12) / 2, child: field)).toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: state.isSaving
                    ? null
                    : () => ref.read(workspaceProvider.notifier).completeCompanySetupFromSuperAdmin(
                          companyName: _companyName.text,
                          legalName: _legalName.text,
                          industry: _industry.text,
                          timezone: _timezone.text,
                          email: _email.text,
                          phone: _phone.text,
                          website: _website.text,
                          address: _address.text,
                          city: _city.text,
                          stateName: _stateName.text,
                          country: _country.text,
                          ownerName: _ownerName.text,
                        ),
                icon: state.isSaving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_done_rounded),
                label: const Text('Create company docs'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineSettingsControl extends ConsumerStatefulWidget {
  const _TimelineSettingsControl();

  @override
  ConsumerState<_TimelineSettingsControl> createState() =>
      _TimelineSettingsControlState();
}

class _TimelineSettingsControlState
    extends ConsumerState<_TimelineSettingsControl> {
  bool _saving = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final member = workspace.currentMember;
    final preferences = ref.watch(timelinePreferencesProvider);
    final controller = ref.read(timelinePreferencesProvider.notifier);
    final canManage = kIsWeb;

    controller.bindWebUser(
      companyId: workspace.company.companyId,
      userId: member.uid,
    );

    return SectionCard(
      title: 'Timeline settings',
      subtitle:
          'Configure the realtime Gantt view, project original plan, baselines, critical path, today marker, scale, and grouping.',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          StatusBadge(
            label: preferences.enabled ? 'Enabled' : 'Disabled',
            color: preferences.enabled ? Colors.green : Colors.grey,
          ),
          const StatusBadge(label: 'Web timeline', color: Colors.indigo),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF2563EB).withOpacity(.16),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.timeline_rounded, color: Color(0xFF2563EB)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'The original project start and due dates are shown as a striped plan bar. Live task dates are shown as the solid realtime bar, so schedule drift is visible immediately.',
                    style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: preferences.enabled,
            onChanged: canManage
                ? (value) => controller.preview(
                    preferences.copyWith(enabled: value),
                  )
                : null,
            title: const Text('Enable realtime Timeline'),
            subtitle: const Text(
              'When disabled, Timeline is removed from the web navigation for this user.',
            ),
          ),
          const Divider(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final tiles = <Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.showOriginalProjectPlan,
                  onChanged: canManage && preferences.enabled
                      ? (value) => controller.preview(
                            preferences.copyWith(
                              showOriginalProjectPlan: value,
                            ),
                          )
                      : null,
                  title: const Text('Show original project plan'),
                  subtitle: const Text(
                    'Uses each project startDate and dueDate, including projects with no tasks.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.autoFitOriginalProjectPlan,
                  onChanged: canManage &&
                          preferences.enabled &&
                          preferences.showOriginalProjectPlan
                      ? (value) => controller.preview(
                            preferences.copyWith(
                              autoFitOriginalProjectPlan: value,
                            ),
                          )
                      : null,
                  title: const Text('Auto-fit project plan'),
                  subtitle: const Text(
                    'Expands the visible range so original project dates are not outside the Gantt viewport.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.showTaskBaselines,
                  onChanged: canManage && preferences.enabled
                      ? (value) => controller.preview(
                            preferences.copyWith(showTaskBaselines: value),
                          )
                      : null,
                  title: const Text('Show task baselines'),
                  subtitle: const Text(
                    'Displays stored baselineStartDate and baselineDueDate behind each task.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.showCriticalPath,
                  onChanged: canManage && preferences.enabled
                      ? (value) => controller.preview(
                            preferences.copyWith(showCriticalPath: value),
                          )
                      : null,
                  title: const Text('Show critical path'),
                  subtitle: const Text(
                    'Draws dependency connectors for critical and delayed work.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.showTodayLine,
                  onChanged: canManage && preferences.enabled
                      ? (value) => controller.preview(
                            preferences.copyWith(showTodayLine: value),
                          )
                      : null,
                  title: const Text('Show today line'),
                  subtitle: const Text(
                    'Keeps the current-date marker visible across all rows.',
                  ),
                ),
              ];

              if (constraints.maxWidth < 900) {
                return Column(children: tiles);
              }
              return Wrap(
                spacing: 18,
                runSpacing: 4,
                children: tiles
                    .map(
                      (tile) => SizedBox(
                        width: (constraints.maxWidth - 18) / 2,
                        child: tile,
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Default scale',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<TimelineDefaultScale>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: TimelineDefaultScale.day,
                  label: Text('Day'),
                ),
                ButtonSegment(
                  value: TimelineDefaultScale.week,
                  label: Text('Week'),
                ),
                ButtonSegment(
                  value: TimelineDefaultScale.month,
                  label: Text('Month'),
                ),
                ButtonSegment(
                  value: TimelineDefaultScale.quarter,
                  label: Text('Quarter'),
                ),
              ],
              selected: <TimelineDefaultScale>{preferences.defaultScale},
              onSelectionChanged: canManage && preferences.enabled
                  ? (selection) {
                      if (selection.isEmpty) return;
                      controller.preview(
                        preferences.copyWith(defaultScale: selection.first),
                      );
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Default grouping',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<TimelineDefaultGrouping>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: TimelineDefaultGrouping.project,
                  label: Text('Project'),
                ),
                ButtonSegment(
                  value: TimelineDefaultGrouping.assignee,
                  label: Text('Assignee'),
                ),
                ButtonSegment(
                  value: TimelineDefaultGrouping.status,
                  label: Text('Status'),
                ),
                ButtonSegment(
                  value: TimelineDefaultGrouping.department,
                  label: Text('Department'),
                ),
              ],
              selected: <TimelineDefaultGrouping>{
                preferences.defaultGrouping,
              },
              onSelectionChanged: canManage && preferences.enabled
                  ? (selection) {
                      if (selection.isEmpty) return;
                      controller.preview(
                        preferences.copyWith(
                          defaultGrouping: selection.first,
                        ),
                      );
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 18),
          _TimelineSettingsPreview(preferences: preferences),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              style: TextStyle(
                color: _message!.startsWith('Unable')
                    ? Theme.of(context).colorScheme.error
                    : Colors.green.shade700,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: canManage && !_saving
                      ? () {
                          controller.preview(TimelinePreferences.defaults);
                          setState(() => _message = null);
                        }
                      : null,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Reset preview'),
                ),
                FilledButton.icon(
                  onPressed: canManage && !_saving
                      ? () => _apply(
                            workspace.company.companyId,
                            member.uid,
                            preferences,
                          )
                      : null,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Saving…' : 'Save Timeline settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(
    String companyId,
    String userId,
    TimelinePreferences preferences,
  ) async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await ref.read(timelinePreferencesProvider.notifier).saveForWebUser(
            companyId: companyId,
            userId: userId,
            preferences: preferences,
          );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Timeline settings saved for this web dashboard.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Unable to save Timeline settings: $error';
      });
    }
  }
}

class _TimelineSettingsPreview extends StatelessWidget {
  const _TimelineSettingsPreview({required this.preferences});

  final TimelinePreferences preferences;

  @override
  Widget build(BuildContext context) {
    final muted = !preferences.enabled;
    return AnimatedOpacity(
      opacity: muted ? .45 : 1,
      duration: const Duration(milliseconds: 220),
      child: Container(
        height: 180,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDCE6F3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.preview_rounded, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Realtime Timeline preview',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text(
                  '${preferences.defaultGrouping.name} • ${preferences.defaultScale.name}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 150,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Column(
                      children: [
                        _TimelinePreviewRow(label: 'Project Alpha'),
                        _TimelinePreviewRow(label: 'Design task'),
                        _TimelinePreviewRow(label: 'Build task'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Stack(
                        children: [
                          Row(
                            children: List.generate(
                              8,
                              (index) => Expanded(
                                child: Container(
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (preferences.showOriginalProjectPlan)
                            Positioned(
                              left: 12,
                              right: 22,
                              top: 12,
                              child: Container(
                                height: 15,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF94A3B8).withOpacity(.22),
                                  border: Border.all(
                                    color: const Color(0xFF64748B),
                                    width: 1.2,
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          Positioned(
                            left: 46,
                            right: 58,
                            top: 35,
                            child: Container(
                              height: 15,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                          if (preferences.showTaskBaselines)
                            Positioned(
                              left: 28,
                              right: 92,
                              top: 62,
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF94A3B8).withOpacity(.4),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          Positioned(
                            left: 38,
                            right: 110,
                            top: 75,
                            child: Container(
                              height: 15,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F766E),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                          if (preferences.showTodayLine)
                            Positioned(
                              left: 178,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 2,
                                color: const Color(0xFFEF4444),
                              ),
                            ),
                        ],
                      ),
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

class _TimelinePreviewRow extends StatelessWidget {
  const _TimelinePreviewRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _NavigationPersonalizationControl extends ConsumerStatefulWidget {
  const _NavigationPersonalizationControl();

  @override
  ConsumerState<_NavigationPersonalizationControl> createState() =>
      _NavigationPersonalizationControlState();
}

class _NavigationPersonalizationControlState
    extends ConsumerState<_NavigationPersonalizationControl> {
  bool _saving = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final member = workspace.currentMember;
    final canManage = kIsWeb;
    final preferences = ref.watch(navigationPreferencesProvider);
    final controller = ref.read(navigationPreferencesProvider.notifier);

    controller.bindWebUser(
      companyId: workspace.company.companyId,
      userId: member.uid,
    );

    return SectionCard(
      title: 'Navigation personalization',
      subtitle:
          'Windows 11 Insider-style placement, display mode, motion, and live preview for your web dashboard only.',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [
          StatusBadge(label: 'Web only', color: Colors.indigo),
          StatusBadge(label: 'Personal setting', color: Colors.green),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(.14),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.devices_rounded),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Changes preview immediately. Press Apply to save the layout for your web dashboard in this browser. Android and iOS APK navigation is not changed.',
                    style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Navigation position',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<NavigationPlacement>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: NavigationPlacement.automatic,
                  icon: Icon(Icons.auto_awesome_rounded),
                  label: Text('Automatic'),
                ),
                ButtonSegment(
                  value: NavigationPlacement.left,
                  icon: Icon(Icons.arrow_back_rounded),
                  label: Text('Left'),
                ),
                ButtonSegment(
                  value: NavigationPlacement.right,
                  icon: Icon(Icons.arrow_forward_rounded),
                  label: Text('Right'),
                ),
                ButtonSegment(
                  value: NavigationPlacement.top,
                  icon: Icon(Icons.vertical_align_top_rounded),
                  label: Text('Top'),
                ),
                ButtonSegment(
                  value: NavigationPlacement.bottom,
                  icon: Icon(Icons.vertical_align_bottom_rounded),
                  label: Text('Bottom'),
                ),
              ],
              selected: <NavigationPlacement>{preferences.placement},
              onSelectionChanged: canManage
                  ? (selection) {
                      if (selection.isEmpty) return;
                      controller.preview(
                        preferences.copyWith(placement: selection.first),
                      );
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Navigation size',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<NavigationDisplayMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: NavigationDisplayMode.expanded,
                  icon: Icon(Icons.view_sidebar_rounded),
                  label: Text('Expanded'),
                ),
                ButtonSegment(
                  value: NavigationDisplayMode.compact,
                  icon: Icon(Icons.view_week_rounded),
                  label: Text('Compact'),
                ),
                ButtonSegment(
                  value: NavigationDisplayMode.iconsOnly,
                  icon: Icon(Icons.apps_rounded),
                  label: Text('Icons only'),
                ),
              ],
              selected: <NavigationDisplayMode>{preferences.displayMode},
              onSelectionChanged: canManage
                  ? (selection) {
                      if (selection.isEmpty) return;
                      controller.preview(
                        preferences.copyWith(displayMode: selection.first),
                      );
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Animation',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<NavigationAnimationStyle>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: NavigationAnimationStyle.system,
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: NavigationAnimationStyle.smooth,
                  label: Text('Smooth'),
                ),
                ButtonSegment(
                  value: NavigationAnimationStyle.fast,
                  label: Text('Fast'),
                ),
                ButtonSegment(
                  value: NavigationAnimationStyle.disabled,
                  label: Text('Off'),
                ),
              ],
              selected: <NavigationAnimationStyle>{
                preferences.animationStyle,
              },
              onSelectionChanged: canManage
                  ? (selection) {
                      if (selection.isEmpty) return;
                      controller.preview(
                        preferences.copyWith(animationStyle: selection.first),
                      );
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final tiles = <Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.autoCollapseOnTimeline,
                  onChanged: canManage
                      ? (value) => controller.preview(
                            preferences.copyWith(
                              autoCollapseOnTimeline: value,
                            ),
                          )
                      : null,
                  title: const Text('Automatically collapse on Timeline'),
                  subtitle: const Text(
                    'Gives the Gantt canvas maximum horizontal space.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.expandOnHover,
                  onChanged: canManage
                      ? (value) => controller.preview(
                            preferences.copyWith(expandOnHover: value),
                          )
                      : null,
                  title: const Text('Expand side navigation on hover'),
                  subtitle: const Text(
                    'Temporary expansion; the saved compact mode is preserved.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: preferences.restoreAfterTimeline,
                  onChanged: canManage
                      ? (value) => controller.preview(
                            preferences.copyWith(
                              restoreAfterTimeline: value,
                            ),
                          )
                      : null,
                  title: const Text('Restore after leaving Timeline'),
                  subtitle: const Text(
                    'Returns to the normal navigation state automatically.',
                  ),
                ),
              ];

              if (constraints.maxWidth < 840) {
                return Column(children: tiles);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < tiles.length; index++) ...[
                    Expanded(child: tiles[index]),
                    if (index < tiles.length - 1) const SizedBox(width: 18),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _NavigationLivePreview(preferences: preferences),
          const SizedBox(height: 18),
          if (_message != null) ...[
            Text(
              _message!,
              style: TextStyle(
                color: _message!.startsWith('Unable')
                    ? Theme.of(context).colorScheme.error
                    : Colors.green.shade700,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: canManage && !_saving
                      ? () {
                          controller.preview(NavigationPreferences.defaults);
                          setState(() => _message = null);
                        }
                      : null,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Reset preview'),
                ),
                FilledButton.icon(
                  onPressed: canManage && !_saving
                      ? () => _apply(
                            workspace.company.companyId,
                            member.uid,
                            preferences,
                          )
                      : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.publish_rounded),
                  label: Text(_saving ? 'Applying…' : 'Apply to web'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(
    String companyId,
    String updatedBy,
    NavigationPreferences preferences,
  ) async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await ref.read(navigationPreferencesProvider.notifier).saveForWebUser(
            companyId: companyId,
            userId: updatedBy,
            preferences: preferences,
          );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Web navigation preference saved. The APK remains unchanged.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'Unable to save web navigation preference: $error';
      });
    }
  }
}

class _NavigationLivePreview extends StatelessWidget {
  const _NavigationLivePreview({required this.preferences});

  final NavigationPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final placement = preferences.placement == NavigationPlacement.automatic
        ? NavigationPlacement.left
        : preferences.placement;
    final duration = switch (preferences.animationStyle) {
      NavigationAnimationStyle.disabled => Duration.zero,
      NavigationAnimationStyle.fast => const Duration(milliseconds: 150),
      NavigationAnimationStyle.system => const Duration(milliseconds: 220),
      NavigationAnimationStyle.smooth => const Duration(milliseconds: 340),
    };
    final curve = preferences.animationStyle ==
            NavigationAnimationStyle.smooth
        ? Curves.easeInOutCubicEmphasized
        : Curves.easeOutCubic;
    final expanded =
        preferences.displayMode == NavigationDisplayMode.expanded;
    final compact = preferences.displayMode == NavigationDisplayMode.compact;

    Widget nav({required bool horizontal}) {
      final children = <Widget>[
        for (final item in const [
          (Icons.dashboard_rounded, 'Home'),
          (Icons.task_alt_rounded, 'Tasks'),
          (Icons.timeline_rounded, 'Timeline'),
          (Icons.settings_rounded, 'Settings'),
        ])
          AnimatedContainer(
            duration: duration,
            curve: curve,
            margin: const EdgeInsets.all(3),
            padding: EdgeInsets.symmetric(
              horizontal: horizontal ? 9 : 7,
              vertical: horizontal ? 7 : 8,
            ),
            decoration: BoxDecoration(
              color: item.$2 == 'Home'
                  ? Theme.of(context).colorScheme.primary.withOpacity(.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: horizontal
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.$1, size: 17),
                      if (preferences.displayMode !=
                          NavigationDisplayMode.iconsOnly) ...[
                        const SizedBox(width: 5),
                        Text(
                          item.$2,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  )
                : compact
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item.$1, size: 17),
                          const SizedBox(height: 2),
                          Text(
                            item.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(item.$1, size: 17),
                          if (expanded) ...[
                            const SizedBox(width: 7),
                            Text(
                              item.$2,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ],
                      ),
          ),
      ];

      return AnimatedContainer(
        duration: duration,
        curve: curve,
        width: horizontal
            ? double.infinity
            : expanded
                ? 132
                : compact
                    ? 72
                    : 52,
        height: horizontal ? 48 : double.infinity,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: horizontal
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: children),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
      );
    }

    final content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 92,
                height: 12,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(.18),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Spacer(),
              const CircleAvatar(radius: 9),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _PreviewCard(heightFactor: .78)),
                const SizedBox(width: 8),
                Expanded(child: _PreviewCard(heightFactor: .56)),
                const SizedBox(width: 8),
                Expanded(child: _PreviewCard(heightFactor: .68)),
              ],
            ),
          ),
        ],
      ),
    );

    final layout = switch (placement) {
      NavigationPlacement.right => Row(
          key: const ValueKey('preview-right'),
          children: [
            Expanded(child: content),
            const SizedBox(width: 8),
            nav(horizontal: false),
          ],
        ),
      NavigationPlacement.top => Column(
          key: const ValueKey('preview-top'),
          children: [
            nav(horizontal: true),
            const SizedBox(height: 8),
            Expanded(child: content),
          ],
        ),
      NavigationPlacement.bottom => Column(
          key: const ValueKey('preview-bottom'),
          children: [
            Expanded(child: content),
            const SizedBox(height: 8),
            nav(horizontal: true),
          ],
        ),
      NavigationPlacement.automatic => Row(
          key: const ValueKey('preview-left'),
          children: [
            nav(horizontal: false),
            const SizedBox(width: 8),
            Expanded(child: content),
          ],
        ),
      NavigationPlacement.left => Row(
          key: const ValueKey('preview-left'),
          children: [
            nav(horizontal: false),
            const SizedBox(width: 8),
            Expanded(child: content),
          ],
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Live preview',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 8),
            StatusBadge(
              label: preferences.placement == NavigationPlacement.automatic
                  ? 'Automatic preview: Left'
                  : preferences.placement.name,
              color: Colors.blueGrey,
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final proportionalHeight = constraints.maxWidth * 7 / 16;
            final previewHeight = proportionalHeight.clamp(260.0, 430.0).toDouble();
            return SizedBox(
              height: previewHeight,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FB),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFDCE4EF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x140F172A),
                      blurRadius: 24,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: curve,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: .985, end: 1)
                            .animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: layout,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.heightFactor});

  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: heightFactor,
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(.22),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 4),
            FractionallySizedBox(
              widthFactor: .68,
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}