import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/workspace_state.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/mobile_ui_config.dart';

class MobileUiControlScreen extends ConsumerStatefulWidget {
  const MobileUiControlScreen({super.key});

  @override
  ConsumerState<MobileUiControlScreen> createState() => _MobileUiControlScreenState();
}

class _UiControlFormState {
  late bool enabled;
  late bool compactMode;
  late Set<String> bottomTabs;
  late Set<String> homeCards;
  late Set<String> taskFields;
  late Set<String> projectFields;
  late String taskCardVariant;
  late String projectCardVariant;
  late bool showFloatingTaskTabs;
  late bool newArrivalsFirst;
  late bool showCompletedTaskTab;
  late String taskDefaultTab;
  late String taskCompletedSort;
  late String topNavStyle;
  late bool topNavShowInbox;
  late bool topNavInboxBadge;
  late bool topNavShowCompany;
  late bool topNavShowRole;
  late bool topNavShowPresence;
  late bool topNavShowAvatar;
  late bool topNavPresenceGlow;
  late bool profileShowLogout;
  late String profileLogoutStyle;
  late String profileLogoutPosition;
  int loadedConfigVersion = -1;

  _UiControlFormState.fromConfig(MobileUiConfig config) {
    loadedConfigVersion = config.version;
    enabled = config.enabled;
    compactMode = config.compactMode;
    bottomTabs = config.bottomTabs.toSet();
    homeCards = config.homeCards.toSet();
    taskFields = config.taskCardFields.toSet();
    projectFields = config.projectCardFields.toSet();
    taskCardVariant = MobileUiConfig.allowedCardVariants.contains(config.taskCardVariant) ? config.taskCardVariant : 'modernCard';
    projectCardVariant = MobileUiConfig.allowedCardVariants.contains(config.projectCardVariant) ? config.projectCardVariant : 'progressCard';
    showFloatingTaskTabs = config.taskListConfig['showFloatingTabs'] != false;
    newArrivalsFirst = config.taskListConfig['newArrivalFirst'] != false;
    showCompletedTaskTab = config.taskListConfig['showCompletedTab'] != false;
    taskDefaultTab = const <String>['newArrival', 'completed'].contains(config.taskListConfig['defaultTab']?.toString()) ? config.taskListConfig['defaultTab'].toString() : 'newArrival';
    taskCompletedSort = const <String>['completedAtDesc', 'updatedAtDesc'].contains(config.taskListConfig['completedSort']?.toString()) ? config.taskListConfig['completedSort'].toString() : 'completedAtDesc';
    topNavStyle = config.topNav['style']?.toString() ?? 'glassAdvanced';
    topNavShowInbox = config.topNav['showInbox'] != false;
    topNavInboxBadge = config.topNav['inboxBadge'] != false;
    topNavShowCompany = config.topNav['showCompanyName'] != false;
    topNavShowRole = config.topNav['showUserRole'] != false;
    topNavShowPresence = config.topNav['showOnlineStatus'] != false;
    topNavShowAvatar = config.topNav['showAvatar'] != false;
    topNavPresenceGlow = config.topNav['showPresenceGlow'] != false;
    profileShowLogout = config.profileActions['showLogout'] != false;
    profileLogoutStyle = const <String>['filledIcon', 'v145MatchedPillGrid', 'capsule', 'outlined', 'text'].contains(config.profileActions['logoutStyle']?.toString()) ? config.profileActions['logoutStyle'].toString() : 'filledIcon';
    profileLogoutPosition = const <String>['bottom', 'profileHeader', 'actionsRow', 'profileActionButton'].contains(config.profileActions['logoutPosition']?.toString()) ? config.profileActions['logoutPosition'].toString() : 'bottom';
  }
}

class _MobileUiControlScreenState extends ConsumerState<MobileUiControlScreen> {
  late _UiControlFormState _formState;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _formState = _UiControlFormState.fromConfig(ref.read(workspaceProvider).mobileUiConfig);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    if (state.mobileUiConfig.version != _formState.loadedConfigVersion) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _formState = _UiControlFormState.fromConfig(ref.read(workspaceProvider).mobileUiConfig));
      });
    }
    final canManage = PermissionService.canManageSettings(state.currentMember);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile UI Control'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: StatusBadge(label: _formState.enabled ? 'Enabled' : 'Disabled', color: _formState.enabled ? Colors.green : Colors.orange)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            SectionCard(
              title: 'Server-driven employee mobile UI',
              subtitle: 'Control employee app tabs, home cards, task fields, and project fields from Firestore. Employees receive updates without an APK rebuild.',
              child: Column(
                children: [
                  SwitchListTile(
                    value: _formState.enabled,
                    onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.enabled = value) : null,
                    title: const Text('Enable mobile UI config'),
                    subtitle: const Text('When off, the employee app uses built-in default mobile layout.'),
                  ),
                  SwitchListTile(
                    value: _formState.compactMode,
                    onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.compactMode = value) : null,
                    title: const Text('Compact mobile mode'),
                    subtitle: const Text('Reduces spacing and card height for smaller phones.'),
                  ),
                  const Divider(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: const <String>['glassAdvanced', 'premium', 'glass', 'floating', 'compact', 'standard'].contains(_formState.topNavStyle) ? _formState.topNavStyle : 'glassAdvanced',
                    decoration: const InputDecoration(labelText: 'Top nav style'),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'glassAdvanced', child: Text('Glass advanced capsule')),
                      DropdownMenuItem(value: 'premium', child: Text('Premium glass capsule')),
                      DropdownMenuItem(value: 'glass', child: Text('Simple glass capsule')),
                      DropdownMenuItem(value: 'floating', child: Text('Floating clean capsule')),
                      DropdownMenuItem(value: 'compact', child: Text('Compact capsule')),
                      DropdownMenuItem(value: 'standard', child: Text('Standard')),
                    ],
                    onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.topNavStyle = value ?? 'glassAdvanced') : null,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(label: const Text('Inbox'), selected: _formState.topNavShowInbox, onSelected: canManage && !_isSaving ? (value) => setState(() => _formState.topNavShowInbox = value) : null),
                      FilterChip(label: const Text('Inbox badge'), selected: _formState.topNavInboxBadge, onSelected: canManage && !_isSaving ? (value) => setState(() => _formState.topNavInboxBadge = value) : null),
                      FilterChip(label: const Text('Company'), selected: _formState.topNavShowCompany, onSelected: canManage && !_isSaving ? (value) => setState(() => _formState.topNavShowCompany = value) : null),
                      FilterChip(label: const Text('Role'), selected: _formState.topNavShowRole, onSelected: canManage && !_isSaving ? (value) => setState(() => _formState.topNavShowRole = value) : null),
                      FilterChip(label: const Text('Presence'), selected: _formState.topNavShowPresence, onSelected: canManage && !_isSaving ? (value) => setState(() => _formState.topNavShowPresence = value) : null),
                      FilterChip(label: const Text('Avatar'), selected: _formState.topNavShowAvatar, onSelected: canManage && !_isSaving ? (value) => setState(() => _formState.topNavShowAvatar = value) : null),
                      FilterChip(label: const Text('Glow'), selected: _formState.topNavPresenceGlow, onSelected: canManage && !_isSaving ? (value) => setState(() => _formState.topNavPresenceGlow = value) : null),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Profile actions',
              subtitle: 'Keep logout on the Profile page and control whether it is shown in the employee APK.',
              trailing: StatusBadge(label: _formState.profileShowLogout ? 'Logout in Profile' : 'Hidden', color: Colors.redAccent),
              child: Column(
                children: [
                  SwitchListTile(
                    value: _formState.profileShowLogout,
                    onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.profileShowLogout = value) : null,
                    title: const Text('Show Logout button inside Profile'),
                    subtitle: const Text('Top nav logout remains off; this keeps the UI cleaner.'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _formState.profileLogoutStyle,
                    decoration: const InputDecoration(labelText: 'Profile logout style'),
                    items: const [
                      DropdownMenuItem(value: 'filledIcon', child: Text('Same as Edit Profile')),
                      DropdownMenuItem(value: 'v145MatchedPillGrid', child: Text('Matched pill grid')),
                      DropdownMenuItem(value: 'capsule', child: Text('Capsule')),
                      DropdownMenuItem(value: 'outlined', child: Text('Outlined')),
                      DropdownMenuItem(value: 'text', child: Text('Text button')),
                    ],
                    onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.profileLogoutStyle = value ?? 'filledIcon') : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _formState.profileLogoutPosition,
                    decoration: const InputDecoration(labelText: 'Profile logout position'),
                    items: const [
                      DropdownMenuItem(value: 'bottom', child: Text('Bottom of Profile')),
                      DropdownMenuItem(value: 'profileHeader', child: Text('Profile header')),
                      DropdownMenuItem(value: 'actionsRow', child: Text('Action row')),
                      DropdownMenuItem(value: 'profileActionButton', child: Text('Profile action button grid')),
                    ],
                    onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.profileLogoutPosition = value ?? 'bottom') : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _ChoiceSection(
              title: 'Bottom navigation tabs',
              subtitle: 'Choose which tabs appear in the employee Android/iOS app.',
              values: MobileUiConfig.allowedBottomTabs,
              labels: _labels,
              selected: _formState.bottomTabs,
              canManage: canManage && !_isSaving,
              onChanged: (value) => setState(() => _formState.bottomTabs = value),
            ),
            const SizedBox(height: 18),
            _ChoiceSection(
              title: 'Employee home cards',
              subtitle: 'Choose and order-safe cards for the employee home screen.',
              values: MobileUiConfig.allowedHomeCards,
              labels: _labels,
              selected: _formState.homeCards,
              canManage: canManage && !_isSaving,
              onChanged: (value) => setState(() => _formState.homeCards = value),
            ),
            const SizedBox(height: 18),
            _ChoiceSection(
              title: 'Task card fields',
              subtitle: 'Choose which fields the mobile task/project-task cards can show.',
              values: MobileUiConfig.allowedTaskCardFields,
              labels: _labels,
              selected: _formState.taskFields,
              canManage: canManage && !_isSaving,
              onChanged: (value) => setState(() => _formState.taskFields = value),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Task card visual style',
              subtitle: 'This dropdown now publishes the task card variant to Firestore and the APK renderer uses it in production.',
              trailing: StatusBadge(label: _variantLabel(_formState.taskCardVariant), color: Colors.deepPurple),
              child: DropdownButtonFormField<String>(
                initialValue: MobileUiConfig.allowedCardVariants.contains(_formState.taskCardVariant) ? _formState.taskCardVariant : 'modernCard',
                decoration: const InputDecoration(labelText: 'Task card dropdown design'),
                items: _variantItems(),
                onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.taskCardVariant = value ?? 'modernCard') : null,
              ),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Task menu filter',
              subtitle: 'Control the employee Tasks tab. New/open tasks are sorted by latest arrival and completed tasks move to a separate floating tab.',
              trailing: StatusBadge(label: _formState.showFloatingTaskTabs ? 'Floating tabs' : 'Single list', color: Colors.deepPurple),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _formState.taskDefaultTab,
                    decoration: const InputDecoration(labelText: 'Default task tab'),
                    items: const [
                      DropdownMenuItem(value: 'newArrival', child: Text('New arrival')),
                      DropdownMenuItem(value: 'completed', child: Text('Completed')),
                    ],
                    onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.taskDefaultTab = value ?? 'newArrival') : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _formState.taskCompletedSort,
                    decoration: const InputDecoration(labelText: 'Completed task sort'),
                    items: const [
                      DropdownMenuItem(value: 'completedAtDesc', child: Text('Completed date newest first')),
                      DropdownMenuItem(value: 'updatedAtDesc', child: Text('Last updated newest first')),
                    ],
                    onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.taskCompletedSort = value ?? 'completedAtDesc') : null,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _formState.showFloatingTaskTabs,
                    onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.showFloatingTaskTabs = value) : null,
                    title: const Text('Show floating New / Completed tabs'),
                    subtitle: const Text('Adds a capsule filter at the top of the Tasks screen.'),
                  ),
                  SwitchListTile(
                    value: _formState.newArrivalsFirst,
                    onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.newArrivalsFirst = value) : null,
                    title: const Text('New arrivals first'),
                    subtitle: const Text('Sorts open tasks by createdAt/updatedAt newest first.'),
                  ),
                  SwitchListTile(
                    value: _formState.showCompletedTaskTab,
                    onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.showCompletedTaskTab = value) : null,
                    title: const Text('Show completed task tab'),
                    subtitle: const Text('Completed tasks are separated from the new arrival list.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _ChoiceSection(
              title: 'Project card fields',
              subtitle: 'Choose which fields employee project cards can show.',
              values: MobileUiConfig.allowedProjectCardFields,
              labels: _labels,
              selected: _formState.projectFields,
              canManage: canManage && !_isSaving,
              onChanged: (value) => setState(() => _formState.projectFields = value),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Project card visual style',
              subtitle: 'This dropdown now publishes the project card variant to Firestore and the APK renderer uses it in production.',
              trailing: StatusBadge(label: _variantLabel(_formState.projectCardVariant), color: Colors.teal),
              child: DropdownButtonFormField<String>(
                initialValue: MobileUiConfig.allowedCardVariants.contains(_formState.projectCardVariant) ? _formState.projectCardVariant : 'progressCard',
                decoration: const InputDecoration(labelText: 'Project card dropdown design'),
                items: _variantItems(),
                onChanged: canManage && !_isSaving ? (value) => setState(() => _formState.projectCardVariant = value ?? 'progressCard') : null,
              ),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Preview summary',
              subtitle: 'This is what will be saved to companies/${state.company.companyId}/uiConfigs/mobileEmployee.',
              trailing: FilledButton.icon(
                onPressed: canManage && !_isSaving ? _save : null,
                icon: _isSaving
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_done_rounded),
                label: Text(_isSaving ? 'Saving...' : 'Save mobile UI'),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusBadge(label: '${_formState.bottomTabs.length} tabs', color: Colors.blue),
                  StatusBadge(label: '${_formState.homeCards.length} home cards', color: Colors.indigo),
                  StatusBadge(label: '${_formState.taskFields.length} task fields', color: Colors.deepPurple),
                  StatusBadge(label: _variantLabel(_formState.taskCardVariant), color: Colors.deepPurple),
                  StatusBadge(label: '${_formState.projectFields.length} project fields', color: Colors.teal),
                  StatusBadge(label: _variantLabel(_formState.projectCardVariant), color: Colors.teal),
                  StatusBadge(label: _formState.showFloatingTaskTabs ? 'New/Done task tabs' : 'No task tabs', color: Colors.deepPurple),
                  StatusBadge(label: _formState.compactMode ? 'Compact' : 'Comfortable', color: Colors.blueGrey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final config = MobileUiConfig(
        enabled: _formState.enabled,
        version: ref.read(workspaceProvider).mobileUiConfig.version + 1,
        bottomTabs: _ordered(MobileUiConfig.allowedBottomTabs, _formState.bottomTabs),
        topNav: <String, dynamic>{
          'enabled': true,
          'style': _formState.topNavStyle,
          'density': _formState.compactMode ? 'compact' : 'comfortable',
          'showInbox': _formState.topNavShowInbox,
          'showCompanyName': _formState.topNavShowCompany,
          'showUserRole': _formState.topNavShowRole,
          'showOnlineStatus': _formState.topNavShowPresence,
          'showLogout': false,
          'inboxBadge': _formState.topNavInboxBadge,
          'showAvatar': _formState.topNavShowAvatar,
          'showPresenceGlow': _formState.topNavPresenceGlow,
        },
        homeCards: _ordered(MobileUiConfig.allowedHomeCards, _formState.homeCards),
        taskCardFields: _ordered(MobileUiConfig.allowedTaskCardFields, _formState.taskFields),
        projectCardFields: _ordered(MobileUiConfig.allowedProjectCardFields, _formState.projectFields),
        taskCardVariant: MobileUiConfig.allowedCardVariants.contains(_formState.taskCardVariant) ? _formState.taskCardVariant : 'modernCard',
        projectCardVariant: MobileUiConfig.allowedCardVariants.contains(_formState.projectCardVariant) ? _formState.projectCardVariant : 'progressCard',
        taskListConfig: <String, dynamic>{
          'showFloatingTabs': _formState.showFloatingTaskTabs,
          'defaultTab': _formState.taskDefaultTab,
          'newArrivalFirst': _formState.newArrivalsFirst,
          'showCompletedTab': _formState.showCompletedTaskTab,
          'completedSort': _formState.taskCompletedSort,
        },
        profileActions: <String, dynamic>{
          'showLogout': _formState.profileShowLogout,
          'logoutStyle': _formState.profileLogoutStyle,
          'logoutPosition': _formState.profileLogoutPosition,
          'setOfflineBeforeLogout': true,
        },
        compactMode: _formState.compactMode,
      );

      await ref.read(workspaceProvider.notifier).updateMobileUiConfig(config);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee mobile UI config saved successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save mobile UI config: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  static List<String> _ordered(List<String> allowed, Set<String> selected) {
    final values = allowed.where(selected.contains).toList();
    return values.isEmpty ? allowed.take(1).toList() : values;
  }

  static List<DropdownMenuItem<String>> _variantItems() {
    return MobileUiConfig.allowedCardVariants
        .map((variant) => DropdownMenuItem<String>(value: variant, child: Text(_variantLabel(variant))))
        .toList();
  }

  static String _variantLabel(String value) {
    return switch (value) {
      'modernCard' => 'Modern card',
      'minimalCard' => 'Minimal card',
      'compactCard' => 'Compact card',
      'timelineCard' => 'Timeline card',
      'progressCard' => 'Progress card',
      'advancedProgressCard' => 'Advanced progress card',
      _ => value,
    };
  }

  static String _labels(String value) {
    return switch (value) {
      'home' => 'Home',
      'tasks' => 'Tasks',
      'projects' => 'Projects',
      'board' => 'Board',
      'notifications' => 'Inbox',
      'profile' => 'Profile',
      'deadlineTimer' => 'Deadline timer',
      'myOpenTasks' => 'My open tasks',
      'todayTasks' => 'Today tasks',
      'projectProgress' => 'Project progress',
      'onlineStatus' => 'Online status',
      'projectName' => 'Project name',
      'taskTitle' => 'Task title',
      'status' => 'Status',
      'priority' => 'Priority',
      'progress' => 'Progress',
      'statusTag' => 'Status tag',
      'description' => 'Description',
      'assignedBy' => 'Assigned by',
      'commentsCount' => 'Comments count',
      'filesCount' => 'Files count',
      'attachmentsCount' => 'Attachments count',
      'assigneeCount' => 'Assignee count',
      'taskCount' => 'Task count',
      'deadline' => 'Deadline',
      'team' => 'Team',
      'teamCount' => 'Team count',
      'completedTaskCount' => 'Completed task count',
      _ => value,
    };
  }
}

class _ChoiceSection extends StatelessWidget {
  const _ChoiceSection({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.labels,
    required this.selected,
    required this.canManage,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final List<String> values;
  final String Function(String value) labels;
  final Set<String> selected;
  final bool canManage;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      subtitle: subtitle,
      trailing: StatusBadge(label: '${selected.length}/${values.length}', color: Colors.blueGrey),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: values.map((value) {
          final active = selected.contains(value);
          return FilterChip(
            selected: active,
            label: Text(labels(value)),
            onSelected: canManage
                ? (next) {
                    final copy = selected.toSet();
                    if (next) {
                      copy.add(value);
                    } else {
                      copy.remove(value);
                    }
                    onChanged(copy);
                  }
                : null,
          );
        }).toList(),
      ),
    );
  }
}