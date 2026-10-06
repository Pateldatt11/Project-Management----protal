import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/permissions/permission_service.dart';

class CampaignsScreen extends ConsumerStatefulWidget {
  const CampaignsScreen({super.key});

  @override
  ConsumerState<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends ConsumerState<CampaignsScreen> {
  String _statusFilter = 'all';

  CollectionReference<Map<String, dynamic>> _ref(String companyId) =>
      FirebaseFirestore.instance
          .collection('companies')
          .doc(companyId)
          .collection('inAppCampaigns');

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final member = workspace.currentMember;
    final companyId = workspace.company.companyId.trim();

    if (!PermissionService.canManageCampaigns(member)) {
      return const Center(
        child: Text('Only Company Admin or Platform Super Admin can manage campaigns.'),
      );
    }

    if (companyId.isEmpty || companyId == 'platform') {
      return const Center(child: Text('Select a company workspace to manage campaigns.'));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _ref(companyId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Unable to load campaigns: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final campaigns = snapshot.data?.docs
                    .map(_CampaignRecord.fromDoc)
                    .toList() ??
                <_CampaignRecord>[];
            campaigns.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

            final visible = _statusFilter == 'all'
                ? campaigns
                : campaigns.where((item) => item.status == _statusFilter).toList();

            final running = campaigns.where((item) => item.status == 'running').length;
            final drafts = campaigns.where((item) => item.status == 'draft').length;
            final paused = campaigns.where((item) => item.status == 'paused').length;
            final ended = campaigns.where((item) => item.status == 'ended').length;

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
                  sliver: SliverToBoxAdapter(
                    child: _Hero(
                      companyName: workspace.company.name,
                      running: running,
                      drafts: drafts,
                      paused: paused,
                      ended: ended,
                      onCreate: () => _openEditor(context),
                      onQuickTemplate: (template) => _openEditor(context, template: template),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverToBoxAdapter(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final filter in const ['all', 'draft', 'running', 'paused', 'ended'])
                          ChoiceChip(
                            selected: _statusFilter == filter,
                            label: Text(filter == 'all' ? 'All campaigns' : _statusLabel(filter)),
                            onSelected: (_) => setState(() => _statusFilter = filter),
                          ),
                      ],
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(onCreate: () => _openEditor(context)),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.crossAxisExtent >= 1180
                            ? 3
                            : constraints.crossAxisExtent >= 760
                                ? 2
                                : 1;
                        return SliverGrid.builder(
                          itemCount: visible.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            mainAxisExtent: 320,
                          ),
                          itemBuilder: (context, index) {
                            final campaign = visible[index];
                            return _CampaignCard(
                              campaign: campaign,
                              onEdit: () => _openEditor(context, campaign: campaign),
                              onRun: () => _runCampaign(campaign),
                              onPause: () => _pauseCampaign(campaign),
                              onEnd: () => _endCampaign(campaign),
                              onDelete: () => _deleteCampaign(campaign),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: MediaQuery.sizeOf(context).width < 700
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New campaign'),
            )
          : null,
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    _CampaignRecord? campaign,
    String? template,
  }) async {
    final workspace = ref.read(workspaceProvider);
    final companyId = workspace.company.companyId.trim();
    final member = workspace.currentMember;

    final values = _templateValues(template);
    final title = TextEditingController(text: campaign?.title ?? values.$1);
    final body = TextEditingController(text: campaign?.body ?? values.$2);
    final cta = TextEditingController(text: campaign?.ctaLabel ?? values.$3);
    final ctaUrl = TextEditingController(text: campaign?.ctaUrl ?? '');

    String type = campaign?.type ?? (template ?? 'promotion');
    String presentation = campaign?.presentation ?? 'modal';
    String frequency = campaign?.frequency ?? 'once';
    int durationDays = campaign?.durationDays ?? 7;
    final selectedRoles = <String>{...(campaign?.audienceRoles ?? <String>[])};
    bool allUsers = selectedRoles.isEmpty;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(campaign == null ? 'Create in-app campaign' : 'Edit campaign'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create company-specific in-app content. The APK layout stays global, while this campaign appears only to this company.',
                    style: TextStyle(color: Color(0xFF64748B), height: 1.45),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          value: type,
                          decoration: const InputDecoration(labelText: 'Campaign type', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'promotion', child: Text('Promotion / offer')),
                            DropdownMenuItem(value: 'announcement', child: Text('Announcement')),
                            DropdownMenuItem(value: 'onboarding', child: Text('Onboarding')),
                            DropdownMenuItem(value: 'update', child: Text('Product / app update')),
                            DropdownMenuItem(value: 'maintenance', child: Text('Maintenance notice')),
                            DropdownMenuItem(value: 'custom', child: Text('Custom message')),
                          ],
                          onChanged: (value) => setLocalState(() => type = value ?? type),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          value: presentation,
                          decoration: const InputDecoration(labelText: 'Display style', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'modal', child: Text('Center modal')),
                            DropdownMenuItem(value: 'banner', child: Text('Top banner')),
                            DropdownMenuItem(value: 'bottomCard', child: Text('Bottom card')),
                          ],
                          onChanged: (value) => setLocalState(() => presentation = value ?? presentation),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          value: frequency,
                          decoration: const InputDecoration(labelText: 'Frequency', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'once', child: Text('Show once per user')),
                            DropdownMenuItem(value: 'everySession', child: Text('Once per app session')),
                          ],
                          onChanged: (value) => setLocalState(() => frequency = value ?? frequency),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: title,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Headline', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: body,
                    minLines: 4,
                    maxLines: 7,
                    maxLength: 700,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cta,
                          maxLength: 32,
                          decoration: const InputDecoration(labelText: 'Button label (optional)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: ctaUrl,
                          decoration: const InputDecoration(
                            labelText: 'Button URL (optional)',
                            hintText: 'https://example.com',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: durationDays,
                    decoration: const InputDecoration(labelText: 'Run duration', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 day')),
                      DropdownMenuItem(value: 3, child: Text('3 days')),
                      DropdownMenuItem(value: 7, child: Text('7 days')),
                      DropdownMenuItem(value: 14, child: Text('14 days')),
                      DropdownMenuItem(value: 30, child: Text('30 days')),
                      DropdownMenuItem(value: 0, child: Text('Until manually ended')),
                    ],
                    onChanged: (value) => setLocalState(() => durationDays = value ?? durationDays),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: allUsers,
                    title: const Text('Show to all company users'),
                    subtitle: const Text('Turn off to target selected employee roles.'),
                    onChanged: (value) => setLocalState(() {
                      allUsers = value;
                      if (value) selectedRoles.clear();
                    }),
                  ),
                  if (!allUsers)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: UserRole.values
                          .where((role) => role != UserRole.superAdmin && role != UserRole.clientViewer)
                          .map((role) => FilterChip(
                                label: Text(role.label),
                                selected: selectedRoles.contains(role.value),
                                onSelected: (selected) => setLocalState(() {
                                  if (selected) {
                                    selectedRoles.add(role.value);
                                  } else {
                                    selectedRoles.remove(role.value);
                                  }
                                }),
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () {
                if (title.text.trim().length < 3 || body.text.trim().length < 5) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Add a headline and message before saving.')),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.save_rounded),
              label: Text(campaign == null ? 'Save draft' : 'Save changes'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final doc = campaign == null ? _ref(companyId).doc() : _ref(companyId).doc(campaign.id);
      final payload = <String, dynamic>{
        'campaignId': doc.id,
        'companyId': companyId,
        'type': type,
        'presentation': presentation,
        'title': title.text.trim(),
        'body': body.text.trim(),
        'ctaLabel': cta.text.trim(),
        'ctaUrl': ctaUrl.text.trim(),
        'audienceRoles': allUsers ? <String>[] : selectedRoles.toList()..sort(),
        'frequency': frequency,
        'durationDays': durationDays,
        'updatedBy': member.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        if (campaign == null) ...{
          'status': 'draft',
          'createdBy': member.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'runCount': 0,
        },
      };
      await doc.set(payload, SetOptions(merge: true));
    }

    title.dispose();
    body.dispose();
    cta.dispose();
    ctaUrl.dispose();
  }

  Future<void> _runCampaign(_CampaignRecord campaign) async {
    final workspace = ref.read(workspaceProvider);
    final now = DateTime.now();
    await _ref(workspace.company.companyId).doc(campaign.id).update({
      'status': 'running',
      'startedAt': Timestamp.fromDate(now),
      'endsAt': campaign.durationDays > 0
          ? Timestamp.fromDate(now.add(Duration(days: campaign.durationDays)))
          : null,
      'runCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': workspace.currentMember.uid,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“${campaign.title}” is now live in ${workspace.company.name}.')),
      );
    }
  }

  Future<void> _pauseCampaign(_CampaignRecord campaign) async {
    final workspace = ref.read(workspaceProvider);
    await _ref(workspace.company.companyId).doc(campaign.id).update({
      'status': 'paused',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': workspace.currentMember.uid,
    });
  }

  Future<void> _endCampaign(_CampaignRecord campaign) async {
    final workspace = ref.read(workspaceProvider);
    await _ref(workspace.company.companyId).doc(campaign.id).update({
      'status': 'ended',
      'endedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': workspace.currentMember.uid,
    });
  }

  Future<void> _deleteCampaign(_CampaignRecord campaign) async {
    final workspace = ref.read(workspaceProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete campaign?'),
        content: Text('Delete “${campaign.title}”? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await _ref(workspace.company.companyId).doc(campaign.id).delete();
    }
  }

  (String, String, String) _templateValues(String? template) {
    return switch (template) {
      'announcement' => ('Important company update', 'We have an important update for everyone. Tap below to learn more.', 'Learn more'),
      'onboarding' => ('Welcome to the team', 'Complete the next onboarding step and get familiar with your workspace.', 'Continue'),
      'update' => ('A new app update is ready', 'Discover the latest improvements available in your company workspace.', 'See what’s new'),
      'maintenance' => ('Scheduled maintenance', 'Some services may be temporarily unavailable during the maintenance window.', 'View details'),
      _ => ('Special offer for our team', 'Share your promotional message, benefit, event, or limited-time offer here.', 'View offer'),
    };
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.companyName,
    required this.running,
    required this.drafts,
    required this.paused,
    required this.ended,
    required this.onCreate,
    required this.onQuickTemplate,
  });

  final String companyName;
  final int running;
  final int drafts;
  final int paused;
  final int ended;
  final VoidCallback onCreate;
  final ValueChanged<String> onQuickTemplate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF311B92), Color(0xFF5B3FD3), Color(0xFF5D7EF7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 18,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 680,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('IN-APP CAMPAIGNS', style: TextStyle(color: Color(0xFFD8D4FF), fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                    const SizedBox(height: 8),
                    Text('Reach people inside $companyName', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text(
                      'Run promotions, onboarding prompts, announcements, product updates, maintenance notices, and custom messages directly inside your company app.',
                      style: TextStyle(color: Color(0xFFE8E5FF), height: 1.45),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onCreate,
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF4430B8), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17)),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('New campaign', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(label: 'Running', value: running, color: const Color(0xFF36D399)),
              _Metric(label: 'Drafts', value: drafts, color: const Color(0xFFB7C3FF)),
              _Metric(label: 'Paused', value: paused, color: const Color(0xFFFFCC66)),
              _Metric(label: 'Ended', value: ended, color: const Color(0xFFD8D4FF)),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Quickstart templates', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: () => onQuickTemplate('promotion'), child: const Text('Promotion / offer')),
              OutlinedButton(onPressed: () => onQuickTemplate('announcement'), child: const Text('Important update')),
              OutlinedButton(onPressed: () => onQuickTemplate('onboarding'), child: const Text('Onboarding')),
              OutlinedButton(onPressed: () => onQuickTemplate('maintenance'), child: const Text('Maintenance notice')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(.16))),
        child: Text('$value  $label', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
      );
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.campaign,
    required this.onEdit,
    required this.onRun,
    required this.onPause,
    required this.onEnd,
    required this.onDelete,
  });

  final _CampaignRecord campaign;
  final VoidCallback onEdit;
  final VoidCallback onRun;
  final VoidCallback onPause;
  final VoidCallback onEnd;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (campaign.status) {
      'running' => Colors.green,
      'paused' => Colors.orange,
      'ended' => Colors.blueGrey,
      _ => Colors.indigo,
    };

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Color(0xFFE6EAF2))),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(backgroundColor: statusColor.withOpacity(.10), child: Icon(_typeIcon(campaign.type), color: statusColor)),
                const SizedBox(width: 10),
                Expanded(child: Text(campaign.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(campaign.body, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), height: 1.45)),
            const Spacer(),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _Pill(_statusLabel(campaign.status), statusColor),
                _Pill(_typeLabel(campaign.type), Colors.deepPurple),
                _Pill(_presentationLabel(campaign.presentation), Colors.blue),
                _Pill(campaign.audienceRoles.isEmpty ? 'All users' : '${campaign.audienceRoles.length} roles', Colors.teal),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: campaign.status == 'running'
                      ? OutlinedButton.icon(onPressed: onPause, icon: const Icon(Icons.pause_rounded), label: const Text('Pause'))
                      : FilledButton.icon(onPressed: onRun, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Run campaign')),
                ),
                if (campaign.status == 'running' || campaign.status == 'paused') ...[
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: onEnd, child: const Text('End')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.campaign_outlined, size: 58, color: Color(0xFF6B5DCC)),
            const SizedBox(height: 12),
            const Text('No campaigns here yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Create a draft, preview the message, then press Run Campaign.'),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add_rounded), label: const Text('Create campaign')),
          ],
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: color.withOpacity(.09), borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      );
}

class _CampaignRecord {
  const _CampaignRecord({
    required this.id,
    required this.type,
    required this.presentation,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.ctaUrl,
    required this.audienceRoles,
    required this.frequency,
    required this.durationDays,
    required this.status,
    required this.updatedAt,
  });

  final String id;
  final String type;
  final String presentation;
  final String title;
  final String body;
  final String ctaLabel;
  final String ctaUrl;
  final List<String> audienceRoles;
  final String frequency;
  final int durationDays;
  final String status;
  final DateTime updatedAt;

  factory _CampaignRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final roles = (data['audienceRoles'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
    return _CampaignRecord(
      id: doc.id,
      type: data['type']?.toString() ?? 'promotion',
      presentation: data['presentation']?.toString() ?? 'modal',
      title: data['title']?.toString() ?? 'Untitled campaign',
      body: data['body']?.toString() ?? '',
      ctaLabel: data['ctaLabel']?.toString() ?? '',
      ctaUrl: data['ctaUrl']?.toString() ?? '',
      audienceRoles: roles,
      frequency: data['frequency']?.toString() ?? 'once',
      durationDays: (data['durationDays'] as num?)?.toInt() ?? 7,
      status: data['status']?.toString() ?? 'draft',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

String _statusLabel(String value) => switch (value) {
      'running' => 'Running',
      'paused' => 'Paused',
      'ended' => 'Ended',
      _ => 'Draft',
    };

String _typeLabel(String value) => switch (value) {
      'announcement' => 'Announcement',
      'onboarding' => 'Onboarding',
      'update' => 'Update',
      'maintenance' => 'Maintenance',
      'custom' => 'Custom',
      _ => 'Promotion',
    };

String _presentationLabel(String value) => switch (value) {
      'banner' => 'Banner',
      'bottomCard' => 'Bottom card',
      _ => 'Modal',
    };

IconData _typeIcon(String value) => switch (value) {
      'announcement' => Icons.campaign_rounded,
      'onboarding' => Icons.rocket_launch_rounded,
      'update' => Icons.auto_awesome_rounded,
      'maintenance' => Icons.construction_rounded,
      'custom' => Icons.widgets_rounded,
      _ => Icons.local_offer_rounded,
    };
