import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_theme.dart';
import '../../../app/workspace_state.dart';
import '../../../core/config/app_config.dart';
import '../../../core/crash/crashlytics_sdk.dart';
import '../../../core/crash/apk_crash_forensics.dart';
import '../../../core/platform/android_alert_notification_service.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/presentation/auth_gate.dart';
import '../../../data/models/member.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _name;
  late TextEditingController _email;
  late TextEditingController _phone;
  late TextEditingController _department;
  late TextEditingController _jobTitle;
  late TextEditingController _location;
  String _seedUid = '__unseeded__';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _department.dispose();
    _jobTitle.dispose();
    _location.dispose();
    super.dispose();
  }

  void _ensureControllers() {
    final state = ref.read(workspaceProvider);
    final user = state.user;
    final member = state.currentMember;
    if (_seedUid == user.uid) return;
    _seedUid = user.uid;
    _name = TextEditingController(text: user.displayName);
    _email = TextEditingController(text: user.email);
    _phone = TextEditingController(text: user.phone ?? '');
    _department = TextEditingController(text: member.effectiveDepartment);
    _jobTitle = TextEditingController(text: member.effectiveJobTitle);
    _location = TextEditingController(text: member.location);
  }


  Future<void> _logout() async {
    ref.read(workspaceProvider.notifier).setMyOnlineStatus(false);
    if (AppConfig.useFirebase) {
      await FirebaseAuth.instance.signOut();
    } else {
      ref.read(demoLoggedInProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllers();
    final state = ref.watch(workspaceProvider);
    final user = state.user;
    final member = state.currentMember;
    final assignedTasks = state.tasks.where((task) => task.assignedToIds.contains(member.uid)).toList();
    final projects = state.projects.where((project) => member.projectIds.contains(project.projectId) || assignedTasks.any((task) => task.projectId == project.projectId)).toList();
    final completed = assignedTasks.where((task) => task.status == TaskStatus.completed).length;
    final completion = assignedTasks.isEmpty ? 0.0 : completed / assignedTasks.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: SectionCard(
        title: 'Profile',
        subtitle: 'These personal details auto-fill the Employees tab and are ready to persist in Firebase member/user documents.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 38, child: Text((user.displayName.trim().isEmpty ? 'U' : user.displayName.characters.first), style: const TextStyle(fontSize: 28))),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user.displayName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    Text(user.email),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      StatusBadge(label: user.role.label, color: user.role.color),
                      StatusBadge(label: member.isOnline ? 'Online' : 'Offline', color: member.isOnline ? AppTheme.success : AppTheme.muted),
                      StatusBadge(label: member.available ? 'Available' : 'Busy', color: member.available ? AppTheme.success : AppTheme.warning),
                      StatusBadge(label: member.effectiveDepartment, color: user.role.color),
                    ]),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final two = constraints.maxWidth > 850;
                final profileForm = Column(
                  children: [
                    TextField(controller: _name, decoration: const InputDecoration(labelText: 'Display name')),
                    const SizedBox(height: 14),
                    TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
                    const SizedBox(height: 14),
                    TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
                    const SizedBox(height: 14),
                    TextField(controller: _jobTitle, decoration: const InputDecoration(labelText: 'Job title / post name')),
                    const SizedBox(height: 14),
                    TextField(controller: _department, decoration: const InputDecoration(labelText: 'Department')),
                    const SizedBox(height: 14),
                    TextField(controller: _location, decoration: const InputDecoration(labelText: 'Location')),
                    const SizedBox(height: 14),
                    TextField(controller: TextEditingController(text: user.role.description), maxLines: 2, readOnly: true, decoration: const InputDecoration(labelText: 'Role permission summary')),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () {
                          ref.read(workspaceProvider.notifier).updateMyProfile(
                                displayName: _name.text,
                                email: _email.text,
                                phone: _phone.text,
                                department: _department.text,
                                jobTitle: _jobTitle.text,
                                location: _location.text,
                              );
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved. Employees tab is updated automatically.')));
                        },
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save Profile'),
                      ),
                    ),
                  ],
                );
                final workPanel = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProfileSettingsSection(member: member, onLogout: _logout),
                    const SizedBox(height: 12),
                    _PresenceControlCard(member: member),
                    if (!kIsWeb) ...[
                      const SizedBox(height: 12),
                      const _CrashlyticsDiagnosticsCard(),
                    ],
                    if (CrashlyticsSdk.isSupported) ...[
                      const SizedBox(height: 12),
                      const _CrashlyticsTestCard(),
                    ],
                    const SizedBox(height: 12),
                    _WorkCard(label: 'Assigned tasks', value: '${assignedTasks.length}', icon: Icons.task_alt_rounded),
                    const SizedBox(height: 12),
                    _WorkCard(label: 'Completed tasks', value: '$completed', icon: Icons.check_circle_rounded),
                    const SizedBox(height: 12),
                    _WorkCard(label: 'Completion rate', value: '${(completion * 100).round()}%', icon: Icons.auto_graph_rounded),
                    const SizedBox(height: 18),
                    Text('Working projects', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    if (projects.isEmpty) const Text('No working project assigned yet.'),
                    ...projects.map((project) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.folder_rounded, color: project.status.color),
                          title: Text(project.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text('${project.status.label} • ${project.progress}%'),
                        )),
                  ],
                );
                if (!two) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [profileForm, const SizedBox(height: 24), workPanel]);
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: profileForm), const SizedBox(width: 24), Expanded(flex: 4, child: workPanel)]);
              },
            ),
          ],
        ),
      ),
    );
  }
}




class _SettingsTextBadge extends StatelessWidget {
  const _SettingsTextBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      constraints: const BoxConstraints(minWidth: 28),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11, height: 1)),
    );
  }
}

class _ProfileSettingsSection extends StatelessWidget {
  const _ProfileSettingsSection({required this.member, required this.onLogout});

  final Member member;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.blueSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.settings_rounded, color: AppTheme.blue),
          ),
          title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(
            '${member.isOnline ? 'Online' : 'Offline'} • Account controls',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700),
          ),
          children: [
            _SettingsInfoRow(
              icon: Icons.verified_user_rounded,
              title: 'Session status',
              subtitle: member.isOnline ? 'Your account is visible as online.' : 'Your account is currently offline.',
            ),
            const SizedBox(height: 8),
            const _NotificationSoundPreferenceCard(compact: true),
            const SizedBox(height: 8),
            const _NotificationDisplayWindowPreferenceCard(compact: true),
            const SizedBox(height: 8),
            _SettingsActionRow(
              icon: Icons.logout_rounded,
              title: 'Logout',
              subtitle: 'Sets you offline, then closes the current session.',
              onTap: () async => onLogout(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.slate700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.navy)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async => onTap(),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.danger.withOpacity(.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.danger.withOpacity(.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppTheme.danger.withOpacity(.10), shape: BoxShape.circle),
                child: Icon(icon, color: AppTheme.danger),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.navy)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.danger),
            ],
          ),
        ),
      ),
    );
  }
}


class _PresenceControlCard extends ConsumerWidget {
  const _PresenceControlCard({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastSeenText = member.lastSeenAt == null ? 'Not recorded yet' : DateText.compact(member.lastSeenAt!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: member.isOnline ? AppTheme.success : AppTheme.muted,
                    shape: BoxShape.circle,
                    boxShadow: member.isOnline ? [BoxShadow(color: AppTheme.success.withOpacity(.35), blurRadius: 10)] : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('Private dashboard presence', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                StatusBadge(label: member.isOnline ? 'Online' : 'Offline', color: member.isOnline ? AppTheme.success : AppTheme.muted),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              member.isOnline ? 'Your team can see you are online now.' : 'Your team will see you as offline. Last seen: $lastSeenText',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: member.isOnline,
              title: const Text('Show me online'),
              subtitle: const Text('Controls the online/offline badge shown in Employees and private dashboard.'),
              onChanged: (value) => ref.read(workspaceProvider.notifier).setMyOnlineStatus(value),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: member.available,
              title: const Text('Available for work'),
              subtitle: const Text('Use this separately from online status when you are busy but still logged in.'),
              onChanged: (value) => ref.read(workspaceProvider.notifier).setMyAvailability(value),
            ),
          ],
        ),
      ),
    );
  }
}


class _NotificationDisplayWindowPreferenceCard extends ConsumerStatefulWidget {
  const _NotificationDisplayWindowPreferenceCard({this.compact = false});

  final bool compact;

  @override
  ConsumerState<_NotificationDisplayWindowPreferenceCard> createState() => _NotificationDisplayWindowPreferenceCardState();
}

class _NotificationDisplayWindowPreferenceCardState extends ConsumerState<_NotificationDisplayWindowPreferenceCard> {
  late final TextEditingController _daysController;
  late final TextEditingController _hoursController;
  String _mode = 'currentMonth';
  String _seed = '';

  @override
  void initState() {
    super.initState();
    _daysController = TextEditingController();
    _hoursController = TextEditingController();
  }

  @override
  void dispose() {
    _daysController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  void _syncFromState(WorkspaceState state) {
    final prefs = state.user.notificationPreferences;
    final config = state.effectiveNotificationDisplayConfig;
    final mode = _notificationWindowMode(prefs.isEmpty ? config : prefs);
    final days = _notificationWindowInt(prefs.isEmpty ? config : prefs, const <String>['displayWindowDays', 'notificationDisplayDays', 'visibleDays'], fallback: 31).clamp(1, 3660).toInt();
    final hours = _notificationWindowInt(prefs.isEmpty ? config : prefs, const <String>['displayWindowHours', 'notificationDisplayHours', 'visibleHours'], fallback: 24).clamp(1, 24 * 3660).toInt();
    final seed = '$mode:$days:$hours:${prefs.hashCode}';
    if (_seed == seed) return;
    _seed = seed;
    _mode = mode;
    _daysController.text = '$days';
    _hoursController.text = '$hours';
  }

  Future<void> _save() async {
    final days = int.tryParse(_daysController.text.trim()) ?? 31;
    final hours = int.tryParse(_hoursController.text.trim()) ?? 24;
    ref.read(workspaceProvider.notifier).setMyNotificationDisplayWindow(
          mode: _mode,
          days: days,
          hours: hours,
        );
    await AndroidAlertNotificationService.setNotificationDisplayWindowPreference(
      mode: _mode,
      days: days,
      hours: hours,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Notification window saved: ${_notificationWindowLabel(_mode, days: days, hours: hours)}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final adminConfig = state.effectiveNotificationAlertConfig;
    final allowUserWindow = _notificationWindowBool(adminConfig, const <String>['allowUserDisplayWindowSelection', 'allowUserNotificationWindow', 'allowUserDisplayWindow'], fallback: true);
    _syncFromState(state);
    final hasUserOverride = state.user.notificationPreferences.isNotEmpty;
    final adminMode = _notificationWindowMode(adminConfig);
    final adminDays = _notificationWindowInt(adminConfig, const <String>['displayWindowDays', 'notificationDisplayDays', 'visibleDays'], fallback: 31);
    final adminHours = _notificationWindowInt(adminConfig, const <String>['displayWindowHours', 'notificationDisplayHours', 'visibleHours'], fallback: 24);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _SettingsTextBadge(label: 'W', color: AppTheme.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Notification display window',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                StatusBadge(label: hasUserOverride ? 'User set' : 'Company default', color: hasUserOverride ? AppTheme.success : AppTheme.blue),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              allowUserWindow
                  ? 'Choose how long old notifications stay visible in your Inbox, unread badge, meetings, and search. Expired notification documents are still hidden first.'
                  : 'Your company admin has locked the notification history window.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppTheme.muted),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.blue.withOpacity(.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.blue.withOpacity(.20)),
              ),
              child: Row(
                children: [
                  const _SettingsTextBadge(label: 'C', color: AppTheme.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Company default: ${_notificationWindowLabel(adminMode, days: adminDays, hours: adminHours)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _mode,
              decoration: const InputDecoration(labelText: 'Show notifications for'),
              items: const [
                DropdownMenuItem(value: 'currentMonth', child: Text('Current month')),
                DropdownMenuItem(value: 'customDays', child: Text('Last custom days')),
                DropdownMenuItem(value: 'customHours', child: Text('Last custom hours')),
                DropdownMenuItem(value: 'all', child: Text('All non-expired notifications')),
              ],
              onChanged: allowUserWindow
                  ? (value) {
                      if (value == null) return;
                      setState(() => _mode = value);
                    }
                  : null,
            ),
            if (_mode == 'customDays') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _daysController,
                enabled: allowUserWindow,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Days', helperText: 'Example: 7, 15, 30, 60'),
              ),
            ],
            if (_mode == 'customHours') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _hoursController,
                enabled: allowUserWindow,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Hours', helperText: 'Example: 6, 12, 24, 72'),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: allowUserWindow ? _save : null,
                child: const Text('Save window'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _notificationWindowMode(Map<String, dynamic> config) {
  final raw = (config['displayWindowMode'] ?? config['notificationDisplayWindowMode'] ?? config['notificationHistoryMode'] ?? config['visibleWindowMode'] ?? 'currentMonth').toString();
  final normalized = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
  return switch (normalized) {
    'all' || 'forever' || 'unlimited' || 'none' => 'all',
    'customhours' || 'lasthours' || 'hours' || 'usersethours' => 'customHours',
    'customdays' || 'lastdays' || 'days' || 'usersetdays' || 'retentiondays' => 'customDays',
    _ => 'currentMonth',
  };
}

int _notificationWindowInt(Map<String, dynamic> config, List<String> keys, {required int fallback}) {
  for (final key in keys) {
    final value = config[key];
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return fallback;
}

bool _notificationWindowBool(Map<String, dynamic> config, List<String> keys, {required bool fallback}) {
  for (final key in keys) {
    final value = config[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'yes' || normalized == '1' || normalized == 'on') return true;
      if (normalized == 'false' || normalized == 'no' || normalized == '0' || normalized == 'off') return false;
    }
  }
  return fallback;
}

String _notificationWindowLabel(String mode, {required int days, required int hours}) {
  return switch (mode) {
    'all' => 'All non-expired notifications',
    'customHours' => 'Last $hours hours',
    'customDays' => 'Last $days days',
    _ => 'Current month',
  };
}


class _NotificationSoundPreferenceCard extends StatefulWidget {
  const _NotificationSoundPreferenceCard({this.compact = false});

  final bool compact;

  @override
  State<_NotificationSoundPreferenceCard> createState() => _NotificationSoundPreferenceCardState();
}

class _NotificationSoundPreferenceCardState extends State<_NotificationSoundPreferenceCard> {
  String _selectedSound = AndroidAlertNotificationService.defaultAlertSoundName;
  bool _assistantVoice = true;
  bool _notificationsEnabled = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final sound = await AndroidAlertNotificationService.getPreferredAlertSound();
    final assistantVoice = await AndroidAlertNotificationService.getAssistantVoiceEnabled();
    final notificationsEnabled = await AndroidAlertNotificationService.areNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _selectedSound = sound;
      _assistantVoice = assistantVoice;
      _notificationsEnabled = notificationsEnabled;
      _loading = false;
    });
  }

  Future<void> _enableNotifications() async {
    setState(() => _saving = true);
    final enabled = await AndroidAlertNotificationService.requestPermissionIfNeeded(force: true);
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = enabled;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(enabled ? 'Android notifications enabled. Background and terminated alerts can now show.' : 'Notification permission is still off. Enable it from Android App Settings.')),
    );
  }

  Future<void> _savePreference(String soundName) async {
    setState(() {
      _selectedSound = soundName;
      _saving = true;
    });
    final saved = await AndroidAlertNotificationService.setPreferredAlertSound(soundName);
    if (!mounted) return;
    setState(() {
      _selectedSound = saved;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sound saved')),
    );
  }

  Future<void> _saveAssistantVoice(bool enabled) async {
    setState(() {
      _assistantVoice = enabled;
      _saving = true;
    });
    final saved = await AndroidAlertNotificationService.setAssistantVoiceEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _assistantVoice = saved;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved ? 'Voice on' : 'Voice off')),
    );
  }

  Future<void> _testSound() async {
    setState(() => _saving = true);
    final saved = await AndroidAlertNotificationService.setPreferredAlertSound(_selectedSound);
    final shown = await AndroidAlertNotificationService.testSelectedAlertSound(
      soundName: saved,
      assistantVoice: _assistantVoice,
      assistantText: 'You are assigned a new task. Please accept the notification.',
    );
    final enabled = await AndroidAlertNotificationService.areNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _selectedSound = saved;
      _notificationsEnabled = enabled;
      _saving = false;
    });
    if (!shown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification permission is required before the test alert can show.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = AndroidAlertNotificationService.alertSoundOptions.firstWhere(
      (option) => option.name == _selectedSound,
      orElse: () => AndroidAlertNotificationService.alertSoundOptions.first,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _SettingsTextBadge(label: 'AL', color: AppTheme.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Notification alert sound',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                StatusBadge(label: selected.label, color: AppTheme.blue),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _notificationsEnabled ? AppTheme.success.withOpacity(.08) : AppTheme.warning.withOpacity(.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: (_notificationsEnabled ? AppTheme.success : AppTheme.warning).withOpacity(.35)),
              ),
              child: Row(
                children: [
                  _SettingsTextBadge(label: _notificationsEnabled ? 'ON' : '!', color: _notificationsEnabled ? AppTheme.success : AppTheme.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _notificationsEnabled
                          ? 'Android notifications are enabled. Alerts can show in foreground, minimized, background, and terminated states.'
                          : 'Android notification permission is off. Enable it once, otherwise background/terminated alerts cannot appear.',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _loading || _saving || _notificationsEnabled ? null : _enableNotifications,
                    child: Text(_notificationsEnabled ? 'Enabled' : 'Enable'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedSound,
              decoration: const InputDecoration(labelText: 'Preferred alert sound'),
              items: AndroidAlertNotificationService.alertSoundOptions
                  .map((option) => DropdownMenuItem<String>(
                        value: option.name,
                        child: Text(option.label),
                      ))
                  .toList(),
              onChanged: _loading || _saving ? null : (value) {
                if (value != null) _savePreference(value);
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _assistantVoice,
              title: const Text('Assistant voice'),
              onChanged: _loading || _saving ? null : _saveAssistantVoice,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: _loading || _saving ? null : _testSound,
                child: Text(_saving ? 'Saving...' : 'Test sound'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class _CrashlyticsDiagnosticsCard extends StatelessWidget {
  const _CrashlyticsDiagnosticsCard();

  Future<void> _copyLog(BuildContext context) async {
    ApkCrashForensics.log('profile_copy_diagnostic_log_tapped');
    final flutterLog = await ApkCrashForensics.readLog();
    final nativeLog = await AndroidAlertNotificationService.readNativeNotificationLog();
    await Clipboard.setData(ClipboardData(text: '$flutterLog\n\n--- Native Android notification log ---\n$nativeLog'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic + native notification log copied. Paste it here after testing.')),
    );
  }

  Future<void> _clearLog(BuildContext context) async {
    await ApkCrashForensics.clearLog();
    await AndroidAlertNotificationService.clearNativeNotificationLog();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local diagnostic log cleared. Reproduce the crash again.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_rounded, color: Colors.indigo),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'APK Diagnostic Log',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                StatusBadge(label: 'No ADB', color: Colors.indigo),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Use this when the app closes but Crashlytics does not show the real crash. Reopen the app, tap Copy log, and paste the copied text here.',
              style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _clearLog(context),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Clear log'),
                ),
                FilledButton.icon(
                  onPressed: () => _copyLog(context),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy log'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CrashlyticsTestCard extends StatelessWidget {
  const _CrashlyticsTestCard();

  Future<void> _runTest(BuildContext context) async {
    if (!CrashlyticsSdk.isSupported || !AppConfig.useFirebase) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crashlytics test needs Android/iOS Firebase mode.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Crashlytics Test'),
        content: const Text(
          'This will intentionally crash the app so Firebase Crashlytics can verify the connection. '
          'After the app closes, open it again once to upload the crash report.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.bug_report_rounded),
            label: const Text('Crash now'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Triggering Crashlytics test crash...')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await CrashlyticsSdk.triggerTestCrash(source: 'profile_apk_button');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bug_report_rounded, color: Colors.redAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Crashlytics Test',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                StatusBadge(label: 'SDK test', color: Colors.redAccent),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Use this only for QA. It intentionally crashes the APK, then Crashlytics uploads the report when you open the app again.',
              style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _runTest(context),
                icon: const Icon(Icons.bug_report_rounded),
                label: const Text('Crashlytics Test'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkCard extends StatelessWidget {
  const _WorkCard({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [Icon(icon), const SizedBox(width: 12), Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))), Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))]),
      ),
    );
  }
}
