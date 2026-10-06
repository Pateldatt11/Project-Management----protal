
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../data/models/app_notification.dart';
import '../../../data/models/member.dart';

class MeetingsScreen extends ConsumerStatefulWidget {
  const MeetingsScreen({super.key});

  @override
  ConsumerState<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends ConsumerState<MeetingsScreen> {
  final _titleController = TextEditingController(text: 'Project meeting');
  final _agendaController = TextEditingController();
  final _linkController = TextEditingController();
  final Set<String> _selectedRecipientIds = <String>{};
  bool _includeAdmins = true;

  @override
  void dispose() {
    _titleController.dispose();
    _agendaController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final member = state.currentMember;
    final canCreateMeetings = PermissionService.canCreateMeetings(member);
    final meetingNotifications = state.myNotifications.where((item) => item.isMeetingInvite).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recipients = state.activePortalMembers
        .where((item) => item.uid != state.user.uid && !item.role.isReadOnly)
        .toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5EF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(canCreateMeetings: canCreateMeetings),
              const SizedBox(height: 18),
              if (!canCreateMeetings)
                const _InfoCard(
                  icon: Icons.lock_rounded,
                  title: 'Meeting access is restricted',
                  message: 'Only Super Admin, Admin, IT Admin, Project Manager, and Team Lead accounts can create meeting links.',
                )
              else
                _CreateMeetingCard(
                  titleController: _titleController,
                  agendaController: _agendaController,
                  linkController: _linkController,
                  recipients: recipients,
                  selectedRecipientIds: _selectedRecipientIds,
                  includeAdmins: _includeAdmins,
                  onIncludeAdminsChanged: (value) => setState(() => _includeAdmins = value),
                  onRecipientChanged: (uid, selected) {
                    setState(() {
                      if (selected) {
                        _selectedRecipientIds.add(uid);
                      } else {
                        _selectedRecipientIds.remove(uid);
                      }
                    });
                  },
                  onSend: _sendMeetingInvite,
                ),
              const SizedBox(height: 20),
              _MeetingListCard(meetings: meetingNotifications, members: state.members),
            ],
          ),
        ),
      ),
    );
  }

  void _sendMeetingInvite() {
    ref.read(workspaceProvider.notifier).createMeetingInvite(
          title: _titleController.text,
          agenda: _agendaController.text,
          meetingLink: _linkController.text,
          recipientIds: _selectedRecipientIds.toList(),
          includeAdmins: _includeAdmins,
        );

    final error = ref.read(workspaceProvider).lastError;
    if (error != null && error.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Meeting invite sent. Users will receive Accept & Join / Reject actions.')),
    );
    _agendaController.clear();
    _linkController.clear();
    setState(_selectedRecipientIds.clear);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.canCreateMeetings});

  final bool canCreateMeetings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 28, offset: Offset(0, 14))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(.12), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.video_call_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Meetings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26)),
                    Text(
                      canCreateMeetings ? 'Create Google Meet or WhatsApp links and send native Android invite actions.' : 'View your meeting invites.',
                      style: const TextStyle(color: Color(0xFFC9C3B8), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _HeaderPill(icon: Icons.notifications_active_rounded, label: 'Android notification'),
              _HeaderPill(icon: Icons.check_circle_rounded, label: 'Accept & Join'),
              _HeaderPill(icon: Icons.close_rounded, label: 'Reject'),
              _HeaderPill(icon: Icons.admin_panel_settings_rounded, label: 'Admin access'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.10), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CreateMeetingCard extends StatelessWidget {
  const _CreateMeetingCard({
    required this.titleController,
    required this.agendaController,
    required this.linkController,
    required this.recipients,
    required this.selectedRecipientIds,
    required this.includeAdmins,
    required this.onIncludeAdminsChanged,
    required this.onRecipientChanged,
    required this.onSend,
  });

  final TextEditingController titleController;
  final TextEditingController agendaController;
  final TextEditingController linkController;
  final List<Member> recipients;
  final Set<String> selectedRecipientIds;
  final bool includeAdmins;
  final ValueChanged<bool> onIncludeAdminsChanged;
  final void Function(String uid, bool selected) onRecipientChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Create meeting link',
      subtitle: 'Super Admin/Admin can send meeting invites directly from this dedicated page.',
      icon: Icons.add_link_rounded,
      child: Column(
        children: [
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Meeting title',
              hintText: 'Sprint planning / Daily standup / Client review',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: agendaController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Agenda / message',
              hintText: 'Tell the user why they need to join.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: linkController,
            decoration: const InputDecoration(
              labelText: 'Google Meet / WhatsApp meeting link',
              hintText: 'https://meet.google.com/... or https://wa.me/...',
              prefixIcon: Icon(Icons.link_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            value: includeAdmins,
            onChanged: onIncludeAdminsChanged,
            contentPadding: EdgeInsets.zero,
            title: const Text('Give meeting access to admins also', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Includes Super Admin, Company Admin, and IT Admin in the invite recipients.'),
          ),
          const Divider(height: 26),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Recipients', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          if (recipients.isEmpty)
            const _InfoCard(icon: Icons.people_outline_rounded, title: 'No active recipients', message: 'Create active employees/members first, or keep admin access enabled.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: recipients.map((member) {
                final selected = selectedRecipientIds.contains(member.uid);
                return FilterChip(
                  selected: selected,
                  avatar: CircleAvatar(backgroundColor: member.role.color, child: Text(member.role.shortLabel.characters.first, style: const TextStyle(color: Colors.white, fontSize: 10))),
                  label: Text(member.displayName),
                  tooltip: member.role.label,
                  onSelected: (value) => onRecipientChanged(member.uid, value),
                );
              }).toList(),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Send meeting invite'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetingListCard extends StatelessWidget {
  const _MeetingListCard({required this.meetings, required this.members});

  final List<AppNotification> meetings;
  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Meeting invites',
      subtitle: 'Native notification payloads that support Accept & Join and Reject.',
      icon: Icons.video_chat_rounded,
      child: meetings.isEmpty
          ? const _InfoCard(icon: Icons.event_available_rounded, title: 'No meetings yet', message: 'Create a meeting link to send invites to users and admins.')
          : Column(
              children: meetings.take(30).map((meeting) {
                final recipient = _memberName(meeting.recipientId);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFF111111),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(_iconFor(meeting.actionType), color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(meeting.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 3),
                            Text('To: $recipient • ${meeting.actionLabel ?? 'Accept & Join'} / ${meeting.rejectLabel ?? 'Reject'}', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                            if ((meeting.actionUrl ?? '').isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(meeting.actionUrl!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.w700)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(meeting.isRead ? 'Read' : 'Sent'),
                        backgroundColor: meeting.isRead ? const Color(0xFFE2E8F0) : const Color(0xFFEAF7EF),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  String _memberName(String uid) {
    final match = members.where((member) => member.uid == uid).toList();
    if (match.isEmpty) return uid.isEmpty ? 'Unknown' : uid;
    return match.first.displayName;
  }

  IconData _iconFor(String? actionType) {
    final normalized = (actionType ?? '').toLowerCase();
    if (normalized.contains('whatsapp')) return Icons.phone_in_talk_rounded;
    return Icons.video_call_rounded;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.subtitle, required this.icon, required this.child});

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFECE7DA)),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF1EFE7), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: const Color(0xFF111111)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF111111))),
                    Text(subtitle, style: const TextStyle(color: Color(0xFF76736D), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF475569)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                const SizedBox(height: 3),
                Text(message, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
