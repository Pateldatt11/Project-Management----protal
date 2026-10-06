import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';

class _TicketTypeOption {
  const _TicketTypeOption({
    required this.category,
    required this.team,
    required this.teamLabel,
    required this.prefix,
  });

  final String category;
  final String team;
  final String teamLabel;
  final String prefix;
}

const _ticketTypes = <_TicketTypeOption>[
  _TicketTypeOption(category: 'IT Support', team: 'itSupport', teamLabel: 'IT Support', prefix: 'IT'),
  _TicketTypeOption(category: 'QA / Bug Report', team: 'qualityAssurance', teamLabel: 'QA / Testing', prefix: 'QA'),
  _TicketTypeOption(category: 'Project / Delivery Blocker', team: 'projectManagement', teamLabel: 'Project Management', prefix: 'PRJ'),
  _TicketTypeOption(category: 'Access / Permission', team: 'itSupport', teamLabel: 'IT & Access', prefix: 'ACC'),
  _TicketTypeOption(category: 'Infrastructure / DevOps', team: 'devOps', teamLabel: 'DevOps / Infrastructure', prefix: 'OPS'),
  _TicketTypeOption(category: 'Production Incident', team: 'incidentResponse', teamLabel: 'Incident Response', prefix: 'INC'),
  _TicketTypeOption(category: 'Security / Compliance', team: 'security', teamLabel: 'Security / Admin', prefix: 'SEC'),
  _TicketTypeOption(category: 'Data / Reporting', team: 'projectManagement', teamLabel: 'Project Management', prefix: 'DATA'),
];

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key, this.showBackButton = false});

  final bool showBackButton;

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  String _statusFilter = 'all';
  bool _creating = false;

  static const _queueViewerRoles = <UserRole>{
    UserRole.superAdmin,
    UserRole.admin,
    UserRole.itAdmin,
    UserRole.devOps,
    UserRole.projectManager,
    UserRole.teamLead,
    UserRole.qaTester,
  };

  static const _ticketManagerRoles = <UserRole>{
    UserRole.superAdmin,
    UserRole.admin,
    UserRole.itAdmin,
    UserRole.devOps,
  };

  static const _expandedTicketRaiserRoles = <UserRole>{
    UserRole.superAdmin,
    UserRole.admin,
    UserRole.itAdmin,
    UserRole.devOps,
    UserRole.teamLead,
    UserRole.qaTester,
  };

  bool _canViewQueue(UserRole role) => _queueViewerRoles.contains(role);
  bool _canManageTickets(UserRole role) => _ticketManagerRoles.contains(role);
  bool _canRaiseExpandedTicketTypes(UserRole role) => _expandedTicketRaiserRoles.contains(role);

  CollectionReference<Map<String, dynamic>> _ticketsRef(String companyId) =>
      FirebaseFirestore.instance.collection('companies').doc(companyId).collection('tickets');

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final member = workspace.currentMember;
    final companyId = workspace.company.companyId.trim();
    final canViewQueue = _canViewQueue(member.role);
    final canManage = _canManageTickets(member.role);

    if (companyId.isEmpty || companyId == 'platform') {
      return const Center(child: Text('Select a company workspace to use Support tickets.'));
    }

    Query<Map<String, dynamic>> query = _ticketsRef(companyId);
    if (!canViewQueue) {
      query = query.where('createdBy', isEqualTo: member.uid);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: widget.showBackButton
          ? AppBar(
              title: const Text('Support Tickets'),
              leading: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            )
          : null,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorState(message: snapshot.error.toString());
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final tickets = snapshot.data?.docs.map(_TicketRecord.fromDoc).toList() ?? <_TicketRecord>[];
            tickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            final visible = _statusFilter == 'all'
                ? tickets
                : tickets.where((ticket) => ticket.status == _statusFilter).toList();

            return LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth >= 1100 ? 34.0 : 18.0;
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 14),
                      sliver: SliverToBoxAdapter(
                        child: _TicketHero(
                          companyName: workspace.company.name,
                          roleLabel: member.role.label,
                          canViewQueue: canViewQueue,
                          canManage: canManage,
                          total: tickets.length,
                          open: tickets.where((ticket) => ticket.status == 'open').length,
                          inProgress: tickets.where((ticket) => ticket.status == 'inProgress').length,
                          resolved: tickets.where((ticket) => ticket.status == 'resolved' || ticket.status == 'closed').length,
                          onRaise: _creating ? null : () => _showCreateTicket(context),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                      sliver: SliverToBoxAdapter(
                        child: _TicketFilters(
                          selected: _statusFilter,
                          onChanged: (value) => setState(() => _statusFilter = value),
                        ),
                      ),
                    ),
                    if (visible.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyTickets(
                          canViewQueue: canViewQueue,
                          onRaise: () => _showCreateTicket(context),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 32),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.crossAxisExtent;
                            final columns = width >= 1180 ? 3 : width >= 760 ? 2 : 1;
                            if (columns == 1) {
                              return SliverList.separated(
                                itemCount: visible.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) => _TicketCard(
                                  ticket: visible[index],
                                  showOwner: canViewQueue,
                                  onTap: () => _openTicket(context, visible[index], canManage),
                                ),
                              );
                            }
                            return SliverGrid.builder(
                              itemCount: visible.length,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                mainAxisExtent: 274,
                              ),
                              itemBuilder: (context, index) => _TicketCard(
                                ticket: visible[index],
                                showOwner: canViewQueue,
                                onTap: () => _openTicket(context, visible[index], canManage),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: MediaQuery.sizeOf(context).width < 680
          ? FloatingActionButton.extended(
              onPressed: _creating ? null : () => _showCreateTicket(context),
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Raise ticket'),
            )
          : null,
    );
  }

  Future<void> _showCreateTicket(BuildContext context) async {
    final workspace = ref.read(workspaceProvider);
    final member = workspace.currentMember;
    final subject = TextEditingController();
    final description = TextEditingController();
    final canRaiseExpandedTypes = _canRaiseExpandedTicketTypes(member.role);
    final availableTypes = canRaiseExpandedTypes ? _ticketTypes : <_TicketTypeOption>[_ticketTypes.first];
    String selectedCategory = availableTypes.first.category;
    String priority = 'medium';

    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final selectedType = availableTypes.firstWhere((type) => type.category == selectedCategory);
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            title: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFE8F0FF),
                  child: Icon(Icons.support_agent_rounded, color: Color(0xFF2556D8)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    canRaiseExpandedTypes ? 'Raise Support / Operations Ticket' : 'Raise IT Support Ticket',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F7FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFD7E7FF)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF2556D8)),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              canRaiseExpandedTypes
                                  ? 'Choose the ticket type. Project Managers, Team Leads, QA/Testers, Admins and IT/DevOps can review the shared queue.'
                                  : 'Your account can raise IT Support tickets. The request is routed to the authorized support queue.',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF24446F)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (canRaiseExpandedTypes) ...[
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(labelText: 'Ticket type', border: OutlineInputBorder()),
                        items: availableTypes
                            .map((type) => DropdownMenuItem<String>(
                                  value: type.category,
                                  child: Text(type.category),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setLocalState(() => selectedCategory = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Routes to: ${selectedType.teamLabel}',
                        style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: subject,
                      maxLength: 100,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        hintText: 'Example: Release is blocked by a login issue',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      minLines: 5,
                      maxLines: 8,
                      maxLength: 1500,
                      decoration: const InputDecoration(
                        labelText: 'Describe the issue',
                        hintText: 'Explain what happened, impact, when it started, and any error or evidence...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: priority,
                      decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Low — general request')),
                        DropdownMenuItem(value: 'medium', child: Text('Medium — work affected')),
                        DropdownMenuItem(value: 'high', child: Text('High — work blocked')),
                        DropdownMenuItem(value: 'urgent', child: Text('Urgent — critical incident / outage')),
                      ],
                      onChanged: (value) {
                        if (value != null) setLocalState(() => priority = value);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton.icon(
                onPressed: () {
                  if (subject.text.trim().length < 4 || description.text.trim().length < 10) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Add a clear subject and issue description.')),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.send_rounded),
                label: const Text('Raise Ticket'),
              ),
            ],
          );
        },
      ),
    );

    if (submitted != true || !mounted) {
      subject.dispose();
      description.dispose();
      return;
    }

    setState(() => _creating = true);
    try {
      final companyId = workspace.company.companyId.trim();
      final now = DateTime.now();
      final ticketType = availableTypes.firstWhere((type) => type.category == selectedCategory);
      final ref = _ticketsRef(companyId).doc();
      final tail = now.millisecondsSinceEpoch.toString();
      final ticketNumber = '${ticketType.prefix}-${tail.substring(tail.length - 7)}';

      await ref.set({
        'ticketId': ref.id,
        'ticketNumber': ticketNumber,
        'companyId': companyId,
        'subject': subject.text.trim(),
        'description': description.text.trim(),
        'priority': priority,
        'status': 'open',
        'category': ticketType.category,
        'assignedTeam': ticketType.team,
        'assignedTeamLabel': ticketType.teamLabel,
        'createdBy': member.uid,
        'createdByName': member.displayName.trim().isEmpty ? workspace.user.email : member.displayName.trim(),
        'createdByEmail': workspace.user.email,
        'createdByRole': member.role.value,
        'source': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'assignedToId': '',
        'assignedToName': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$ticketNumber raised successfully as ${ticketType.category}.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not raise ticket: $error')));
      }
    } finally {
      subject.dispose();
      description.dispose();
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openTicket(BuildContext context, _TicketRecord ticket, bool canManage) async {
    final workspace = ref.read(workspaceProvider);
    final width = MediaQuery.sizeOf(context).width;
    final child = _TicketDetailPanel(
      ticketId: ticket.id,
      companyId: workspace.company.companyId,
      currentUid: workspace.currentMember.uid,
      currentName: workspace.currentMember.displayName.trim().isEmpty
          ? workspace.user.email
          : workspace.currentMember.displayName.trim(),
      currentRole: workspace.currentMember.role,
      canManage: canManage,
    );

    if (width >= 760) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(28),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(width: 860, height: MediaQuery.sizeOf(context).height * .84, child: child),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SizedBox(height: MediaQuery.sizeOf(context).height * .92, child: child),
      );
    }
  }
}

class _TicketHero extends StatelessWidget {
  const _TicketHero({
    required this.companyName,
    required this.roleLabel,
    required this.canViewQueue,
    required this.canManage,
    required this.total,
    required this.open,
    required this.inProgress,
    required this.resolved,
    required this.onRaise,
  });

  final String companyName;
  final String roleLabel;
  final bool canViewQueue;
  final bool canManage;
  final int total;
  final int open;
  final int inProgress;
  final int resolved;
  final VoidCallback? onRaise;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F1E45), Color(0xFF1E3A8A), Color(0xFF2855C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x241E3A8A), blurRadius: 32, offset: Offset(0, 16))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.support_agent_rounded, color: Color(0xFF9FC0FF)),
                        SizedBox(width: 8),
                        Text('SUPPORT & OPERATIONS DESK', style: TextStyle(color: Color(0xFFC7D8FF), fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      canViewQueue ? 'Shared support & operations ticket queue' : 'Need help? Raise a support ticket',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.08),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      canViewQueue
                          ? '$roleLabel access • $companyName • ${canManage ? 'You can manage and resolve tickets.' : 'You can review the shared ticket queue.'}'
                          : 'Your IT Support ticket is visible to the authorized support queue. Track its status and reply from this page.',
                      style: const TextStyle(color: Color(0xFFD5E2FF), height: 1.45, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E3A8A),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
                ),
                onPressed: onRaise,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Raise Ticket', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroMetric(label: 'Total', value: total, icon: Icons.confirmation_number_outlined),
              _HeroMetric(label: 'Open', value: open, icon: Icons.mark_email_unread_outlined),
              _HeroMetric(label: 'In progress', value: inProgress, icon: Icons.engineering_outlined),
              _HeroMetric(label: 'Resolved', value: resolved, icon: Icons.task_alt_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value, required this.icon});
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFBFD2FF), size: 18),
          const SizedBox(width: 8),
          Text('$value', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Color(0xFFD6E2FF), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TicketFilters extends StatelessWidget {
  const _TicketFilters({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const filters = <String, String>{
      'all': 'All',
      'open': 'Open',
      'inProgress': 'In progress',
      'waitingForUser': 'Waiting for user',
      'resolved': 'Resolved',
      'closed': 'Closed',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(entry.value),
                  selected: selected == entry.key,
                  onSelected: (_) => onChanged(entry.key),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.showOwner, required this.onTap});
  final _TicketRecord ticket;
  final bool showOwner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = _TicketVisuals.status(ticket.status);
    final priority = _TicketVisuals.priority(ticket.priority);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5EAF2)),
            boxShadow: const [BoxShadow(color: Color(0x0B0F172A), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(9)),
                    child: Text(ticket.ticketNumber, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF334155))),
                  ),
                  const Spacer(),
                  _MiniBadge(label: priority.$1, color: priority.$2),
                ],
              ),
              const SizedBox(height: 10),
              _MiniBadge(label: ticket.category, color: _TicketVisuals.category(ticket.category)),
              const SizedBox(height: 10),
              Text(ticket.subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), height: 1.2)),
              const SizedBox(height: 8),
              Text(ticket.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), height: 1.4)),
              const Spacer(),
              if (showOwner) ...[
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 17, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(ticket.createdByName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)))),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  _MiniBadge(label: status.$1, color: status.$2),
                  const Spacer(),
                  Text(DateFormat('dd MMM • hh:mm a').format(ticket.createdAt.toLocal()), style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(.11), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

class _TicketDetailPanel extends StatefulWidget {
  const _TicketDetailPanel({
    required this.ticketId,
    required this.companyId,
    required this.currentUid,
    required this.currentName,
    required this.currentRole,
    required this.canManage,
  });

  final String ticketId;
  final String companyId;
  final String currentUid;
  final String currentName;
  final UserRole currentRole;
  final bool canManage;

  @override
  State<_TicketDetailPanel> createState() => _TicketDetailPanelState();
}

class _TicketDetailPanelState extends State<_TicketDetailPanel> {
  final _reply = TextEditingController();
  bool _sending = false;

  DocumentReference<Map<String, dynamic>> get _ticketRef => FirebaseFirestore.instance
      .collection('companies')
      .doc(widget.companyId)
      .collection('tickets')
      .doc(widget.ticketId);

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _ticketRef.snapshots(),
      builder: (context, ticketSnapshot) {
        if (!ticketSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final doc = ticketSnapshot.data!;
        if (!doc.exists) return const Center(child: Text('Ticket no longer exists.'));
        final ticket = _TicketRecord.fromDoc(doc);
        final status = _TicketVisuals.status(ticket.status);
        final priority = _TicketVisuals.priority(ticket.priority);

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF101D3D), Color(0xFF244CB0)]),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.support_agent_rounded, color: Color(0xFF2149A3))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ticket.ticketNumber, style: const TextStyle(color: Color(0xFFBBD0FF), fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(ticket.subject, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MiniBadge(label: status.$1, color: status.$2),
                      _MiniBadge(label: priority.$1, color: priority.$2),
                      _MiniBadge(label: ticket.category, color: _TicketVisuals.category(ticket.category)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ticket.description, style: const TextStyle(color: Color(0xFF334155), height: 1.5, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 14,
                          runSpacing: 8,
                          children: [
                            _InfoLine(icon: Icons.person_outline_rounded, text: ticket.createdByName),
                            _InfoLine(icon: Icons.alternate_email_rounded, text: ticket.createdByEmail),
                            _InfoLine(icon: Icons.schedule_rounded, text: DateFormat('dd MMM yyyy, hh:mm a').format(ticket.createdAt.toLocal())),
                            _InfoLine(icon: Icons.groups_2_outlined, text: 'Queue: ${ticket.assignedTeamLabel}'),
                            if (ticket.assignedToName.isNotEmpty) _InfoLine(icon: Icons.engineering_rounded, text: 'Assigned to ${ticket.assignedToName}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.canManage) ...[
                    const SizedBox(height: 16),
                    _ManagementControls(ticket: ticket, ticketRef: _ticketRef, currentUid: widget.currentUid, currentName: widget.currentName),
                  ],
                  const SizedBox(height: 20),
                  const Text('Conversation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  const SizedBox(height: 10),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _ticketRef.collection('messages').orderBy('createdAt').snapshots(),
                    builder: (context, messageSnapshot) {
                      if (messageSnapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                      }
                      final docs = messageSnapshot.data?.docs ?? const [];
                      if (docs.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(14)),
                          child: const Text('No replies yet. Send a message below.', style: TextStyle(color: Color(0xFF64748B))),
                        );
                      }
                      return Column(
                        children: docs.map((doc) {
                          final data = doc.data();
                          final mine = (data['senderId'] ?? '').toString() == widget.currentUid;
                          final timestamp = data['createdAt'];
                          final createdAt = timestamp is Timestamp ? timestamp.toDate() : DateTime.now();
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 560),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: mine ? const Color(0xFFE8F0FF) : Colors.white,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: mine ? const Color(0xFFC9DBFF) : const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text((data['senderName'] ?? 'User').toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF475569))),
                                  const SizedBox(height: 5),
                                  Text((data['body'] ?? '').toString(), style: const TextStyle(color: Color(0xFF1E293B), height: 1.4)),
                                  const SizedBox(height: 5),
                                  Text(DateFormat('dd MMM • hh:mm a').format(createdAt.toLocal()), style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (ticket.createdBy == widget.currentUid || widget.canManage)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reply,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(hintText: 'Reply to this ticket…', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      tooltip: 'Send reply',
                      onPressed: _sending ? null : _sendReply,
                      icon: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: Color(0xFFF8FAFC), border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
                child: const Text(
                  'Queue review access is read-only. The ticket owner and authorized support handlers can reply.',
                  style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _sendReply() async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _ticketRef.collection('messages').add({
        'senderId': widget.currentUid,
        'senderName': widget.currentName,
        'senderRole': widget.currentRole.value,
        'body': body,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _reply.clear();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send reply: $error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _ManagementControls extends StatelessWidget {
  const _ManagementControls({required this.ticket, required this.ticketRef, required this.currentUid, required this.currentName});
  final _TicketRecord ticket;
  final DocumentReference<Map<String, dynamic>> ticketRef;
  final String currentUid;
  final String currentName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFDE68A))),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Ticket controls', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF854D0E))),
          DropdownButton<String>(
            value: <String>{'open', 'inProgress', 'waitingForUser', 'resolved', 'closed'}.contains(ticket.status) ? ticket.status : 'open',
            items: const [
              DropdownMenuItem(value: 'open', child: Text('Open')),
              DropdownMenuItem(value: 'inProgress', child: Text('In progress')),
              DropdownMenuItem(value: 'waitingForUser', child: Text('Waiting for user')),
              DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
              DropdownMenuItem(value: 'closed', child: Text('Closed')),
            ],
            onChanged: (value) async {
              if (value == null || value == ticket.status) return;
              await ticketRef.update({'status': value, 'updatedAt': FieldValue.serverTimestamp()});
            },
          ),
          OutlinedButton.icon(
            onPressed: ticket.assignedToId == currentUid
                ? null
                : () => ticketRef.update({
                      'assignedToId': currentUid,
                      'assignedToName': currentName,
                      'status': ticket.status == 'open' ? 'inProgress' : ticket.status,
                      'updatedAt': FieldValue.serverTimestamp(),
                    }),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(ticket.assignedToId == currentUid ? 'Assigned to you' : 'Assign to me'),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _EmptyTickets extends StatelessWidget {
  const _EmptyTickets({required this.canViewQueue, required this.onRaise});
  final bool canViewQueue;
  final VoidCallback onRaise;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(radius: 34, backgroundColor: Color(0xFFEFF4FF), child: Icon(Icons.support_agent_rounded, size: 34, color: Color(0xFF3159C6))),
            const SizedBox(height: 14),
            Text(canViewQueue ? 'No tickets in this view' : 'No support tickets yet', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(canViewQueue ? 'New support and operational requests will appear here automatically.' : 'If you have an access, device, software, or network problem, raise an IT Support ticket.', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRaise, icon: const Icon(Icons.add_comment_rounded), label: const Text('Raise Ticket')),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFFCA5A5))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 34),
          const SizedBox(height: 10),
          const Text('Ticket queue could not load', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B))),
        ]),
      ),
    );
  }
}

class _TicketRecord {
  const _TicketRecord({
    required this.id,
    required this.ticketNumber,
    required this.subject,
    required this.description,
    required this.priority,
    required this.status,
    required this.category,
    required this.assignedTeamLabel,
    required this.createdBy,
    required this.createdByName,
    required this.createdByEmail,
    required this.assignedToId,
    required this.assignedToName,
    required this.createdAt,
  });

  final String id;
  final String ticketNumber;
  final String subject;
  final String description;
  final String priority;
  final String status;
  final String category;
  final String assignedTeamLabel;
  final String createdBy;
  final String createdByName;
  final String createdByEmail;
  final String assignedToId;
  final String assignedToName;
  final DateTime createdAt;

  factory _TicketRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final timestamp = data['createdAt'];
    return _TicketRecord(
      id: doc.id,
      ticketNumber: (data['ticketNumber'] ?? 'IT-${doc.id.length > 7 ? doc.id.substring(0, 7) : doc.id}').toString(),
      subject: (data['subject'] ?? 'IT support request').toString(),
      description: (data['description'] ?? '').toString(),
      priority: (data['priority'] ?? 'medium').toString(),
      status: (data['status'] ?? 'open').toString(),
      category: (data['category'] ?? 'IT Support').toString(),
      assignedTeamLabel: (data['assignedTeamLabel'] ?? 'IT Support').toString(),
      createdBy: (data['createdBy'] ?? '').toString(),
      createdByName: (data['createdByName'] ?? 'User').toString(),
      createdByEmail: (data['createdByEmail'] ?? '').toString(),
      assignedToId: (data['assignedToId'] ?? '').toString(),
      assignedToName: (data['assignedToName'] ?? '').toString(),
      createdAt: timestamp is Timestamp ? timestamp.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

abstract final class _TicketVisuals {
  static (String, Color) status(String value) => switch (value) {
        'inProgress' => ('In progress', const Color(0xFF2563EB)),
        'waitingForUser' => ('Waiting for user', const Color(0xFFD97706)),
        'resolved' => ('Resolved', const Color(0xFF059669)),
        'closed' => ('Closed', const Color(0xFF64748B)),
        _ => ('Open', const Color(0xFF7C3AED)),
      };

  static Color category(String value) => switch (value) {
        'QA / Bug Report' => const Color(0xFF7C3AED),
        'Project / Delivery Blocker' => const Color(0xFFEA580C),
        'Access / Permission' => const Color(0xFF2563EB),
        'Infrastructure / DevOps' => const Color(0xFF0F766E),
        'Production Incident' => const Color(0xFFDC2626),
        'Security / Compliance' => const Color(0xFFBE123C),
        'Data / Reporting' => const Color(0xFF4F46E5),
        _ => const Color(0xFF0284C7),
      };

  static (String, Color) priority(String value) => switch (value) {
        'low' => ('Low', const Color(0xFF059669)),
        'high' => ('High', const Color(0xFFEA580C)),
        'urgent' => ('Urgent', const Color(0xFFDC2626)),
        _ => ('Medium', const Color(0xFF2563EB)),
      };
}
