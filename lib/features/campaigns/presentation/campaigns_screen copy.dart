// import 'dart:math' as math;

// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';

// import '../../../app/workspace_state.dart';
// import '../../../core/constants/app_enums.dart';
// import '../../../core/permissions/permission_service.dart';

// class CampaignsScreen extends ConsumerStatefulWidget {
//   const CampaignsScreen({super.key});

//   @override
//   ConsumerState<CampaignsScreen> createState() => _CampaignsScreenState();
// }

// class _CampaignsScreenState extends ConsumerState<CampaignsScreen> {
//   static const _navy = Color(0xFF0A1530);
//   static const _blue = Color(0xFF4B9CF5);
//   static const _cyan = Color(0xFF55D6D1);
//   static const _page = Color(0xFFF3F7FD);
//   static const _border = Color(0xFFE2E9F3);

//   String _statusFilter = 'all';
//   String _activeSection = 'Campaigns';
//   String _dateFilter = 'Last 7 Days';
//   String _deviceFilter = 'All devices';
//   String _osFilter = 'All OS';
//   String _formatFilter = 'All formats';

//   CollectionReference<Map<String, dynamic>> _ref(String companyId) =>
//       FirebaseFirestore.instance
//           .collection('companies')
//           .doc(companyId)
//           .collection('inAppCampaigns');

//   @override
//   Widget build(BuildContext context) {
//     final workspace = ref.watch(workspaceProvider);
//     final member = workspace.currentMember;
//     final companyId = workspace.company.companyId.trim();

//     if (!PermissionService.canManageCampaigns(member)) {
//       return const Center(
//         child: Text(
//           'Only Company Admin or Platform Super Admin can manage campaigns.',
//         ),
//       );
//     }

//     if (companyId.isEmpty || companyId == 'platform') {
//       return const Center(
//         child: Text('Select a company workspace to manage campaigns.'),
//       );
//     }

//     return Scaffold(
//       backgroundColor: const Color(0xFF8298B3),
//       body: SafeArea(
//         child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//           stream: _ref(companyId).snapshots(),
//           builder: (context, snapshot) {
//             if (snapshot.hasError) {
//               return _ErrorState(
//                 message: 'Unable to load campaigns: ${snapshot.error}',
//               );
//             }
//             if (snapshot.connectionState == ConnectionState.waiting) {
//               return const Center(child: CircularProgressIndicator());
//             }

//             final campaigns = snapshot.data?.docs
//                     .map(_CampaignRecord.fromDoc)
//                     .toList() ??
//                 <_CampaignRecord>[];
//             campaigns.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

//             final visible = _statusFilter == 'all'
//                 ? campaigns
//                 : campaigns
//                     .where((item) => item.status == _statusFilter)
//                     .toList();

//             final running =
//                 campaigns.where((item) => item.status == 'running').length;
//             final drafts =
//                 campaigns.where((item) => item.status == 'draft').length;
//             final paused =
//                 campaigns.where((item) => item.status == 'paused').length;
//             final ended =
//                 campaigns.where((item) => item.status == 'ended').length;

//             return LayoutBuilder(
//               builder: (context, constraints) {
//                 final desktop = constraints.maxWidth >= 1050;
//                 final tablet = constraints.maxWidth >= 760;

//                 if (!desktop) {
//                   return _ResponsiveCampaignDashboard(
//                     campaigns: campaigns,
//                     visible: visible,
//                     running: running,
//                     drafts: drafts,
//                     paused: paused,
//                     ended: ended,
//                     companyName: workspace.company.name,
//                     statusFilter: _statusFilter,
//                     dateFilter: _dateFilter,
//                     deviceFilter: _deviceFilter,
//                     osFilter: _osFilter,
//                     formatFilter: _formatFilter,
//                     onStatusChanged: (v) => setState(() => _statusFilter = v),
//                     onDateChanged: (v) => setState(() => _dateFilter = v),
//                     onDeviceChanged: (v) => setState(() => _deviceFilter = v),
//                     onOsChanged: (v) => setState(() => _osFilter = v),
//                     onFormatChanged: (v) => setState(() => _formatFilter = v),
//                     onCreate: () => _openEditor(context),
//                     onEdit: (c) => _openEditor(context, campaign: c),
//                     onRun: _runCampaign,
//                     onPause: _pauseCampaign,
//                     onEnd: _endCampaign,
//                     onDelete: _deleteCampaign,
//                     compact: !tablet,
//                   );
//                 }

//                 return Padding(
//                   padding: const EdgeInsets.all(18),
//                   child: ClipRRect(
//                     borderRadius: BorderRadius.circular(13),
//                     child: Container(
//                       color: const Color(0xFFF2F6FC),
//                       child: Row(
//                         children: [
//                           SizedBox(
//                             width: 135,
//                             child: _ReferenceSideBar(
//                               activeSection: _activeSection,
//                               onSelect: (value) =>
//                                   setState(() => _activeSection = value),
//                             ),
//                           ),
//                           Expanded(
//                             child: Column(
//                               children: [
//                                 _ReferenceTopBar(
//                                   companyName: workspace.company.name,
//                                   onCreate: () => _openEditor(context),
//                                 ),
//                                 Expanded(
//                                   child: Row(
//                                     crossAxisAlignment:
//                                         CrossAxisAlignment.stretch,
//                                     children: [
//                                       SizedBox(
//                                         width: 195,
//                                         child: _ReferenceFilterPanel(
//                                           dateFilter: _dateFilter,
//                                           deviceFilter: _deviceFilter,
//                                           osFilter: _osFilter,
//                                           formatFilter: _formatFilter,
//                                           onDateChanged: (v) => setState(
//                                             () => _dateFilter = v,
//                                           ),
//                                           onDeviceChanged: (v) => setState(
//                                             () => _deviceFilter = v,
//                                           ),
//                                           onOsChanged: (v) => setState(
//                                             () => _osFilter = v,
//                                           ),
//                                           onFormatChanged: (v) => setState(
//                                             () => _formatFilter = v,
//                                           ),
//                                         ),
//                                       ),
//                                       Expanded(
//                                         child: CustomScrollView(
//                                           slivers: [
//                                             SliverPadding(
//                                               padding: const EdgeInsets.fromLTRB(
//                                                 27,
//                                                 24,
//                                                 27,
//                                                 0,
//                                               ),
//                                               sliver: SliverToBoxAdapter(
//                                                 child: _ReferenceChart(
//                                                   campaigns: campaigns,
//                                                   dateFilter: _dateFilter,
//                                                 ),
//                                               ),
//                                             ),
//                                             SliverPadding(
//                                               padding: const EdgeInsets.fromLTRB(
//                                                 27,
//                                                 18,
//                                                 27,
//                                                 0,
//                                               ),
//                                               sliver: SliverToBoxAdapter(
//                                                 child: _ReferenceMetricStrip(
//                                                   campaigns: campaigns,
//                                                 ),
//                                               ),
//                                             ),
//                                             SliverPadding(
//                                               padding: const EdgeInsets.fromLTRB(
//                                                 27,
//                                                 18,
//                                                 27,
//                                                 28,
//                                               ),
//                                               sliver: SliverToBoxAdapter(
//                                                 child: _DashboardLowerSection(
//                                                   campaigns: campaigns,
//                                                   visible: visible,
//                                                   statusFilter: _statusFilter,
//                                                   deviceFilter: _deviceFilter,
//                                                   osFilter: _osFilter,
//                                                   formatFilter: _formatFilter,
//                                                   onStatusChanged: (v) =>
//                                                       setState(() =>
//                                                           _statusFilter = v),
//                                                   onOsChanged: (v) => setState(
//                                                     () => _osFilter = v,
//                                                   ),
//                                                   onFormatChanged: (v) =>
//                                                       setState(() =>
//                                                           _formatFilter = v),
//                                                   onCreate: () =>
//                                                       _openEditor(context),
//                                                   onEdit: (c) => _openEditor(
//                                                     context,
//                                                     campaign: c,
//                                                   ),
//                                                   onRun: _runCampaign,
//                                                   onPause: _pauseCampaign,
//                                                   onEnd: _endCampaign,
//                                                   onDelete: _deleteCampaign,
//                                                 ),
//                                               ),
//                                             ),
//                                           ],
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 );
//               },
//             );
//           },
//         ),
//       ),
//     );
//   }

//   Future<void> _openEditor(
//     BuildContext context, {
//     _CampaignRecord? campaign,
//     String? template,
//   }) async {
//     final workspace = ref.read(workspaceProvider);
//     final companyId = workspace.company.companyId.trim();
//     final member = workspace.currentMember;

//     final values = _templateValues(template);
//     final title = TextEditingController(text: campaign?.title ?? values.$1);
//     final body = TextEditingController(text: campaign?.body ?? values.$2);
//     final cta = TextEditingController(text: campaign?.ctaLabel ?? values.$3);
//     final ctaUrl = TextEditingController(text: campaign?.ctaUrl ?? '');

//     String type = campaign?.type ?? (template ?? 'promotion');
//     String presentation = campaign?.presentation ?? 'modal';
//     String frequency = campaign?.frequency ?? 'once';
//     int durationDays = campaign?.durationDays ?? 7;
//     final selectedRoles = <String>{...(campaign?.audienceRoles ?? <String>[])};
//     bool allUsers = selectedRoles.isEmpty;

//     final saved = await showDialog<bool>(
//       context: context,
//       barrierDismissible: false,
//       builder: (dialogContext) => StatefulBuilder(
//         builder: (context, setLocalState) => Dialog(
//           backgroundColor: Colors.transparent,
//           insetPadding: const EdgeInsets.all(20),
//           child: ConstrainedBox(
//             constraints: const BoxConstraints(maxWidth: 820),
//             child: Container(
//               decoration: BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.circular(24),
//                 boxShadow: const [
//                   BoxShadow(
//                     blurRadius: 40,
//                     offset: Offset(0, 18),
//                     color: Color(0x300B1631),
//                   ),
//                 ],
//               ),
//               child: SingleChildScrollView(
//                 child: Padding(
//                   padding: const EdgeInsets.all(26),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         children: [
//                           Container(
//                             width: 44,
//                             height: 44,
//                             decoration: BoxDecoration(
//                               color: _blue.withOpacity(.10),
//                               borderRadius: BorderRadius.circular(13),
//                             ),
//                             child: const Icon(
//                               Icons.campaign_rounded,
//                               color: _blue,
//                             ),
//                           ),
//                           const SizedBox(width: 13),
//                           Expanded(
//                             child: Column(
//                               crossAxisAlignment: CrossAxisAlignment.start,
//                               children: [
//                                 Text(
//                                   campaign == null
//                                       ? 'Create campaign'
//                                       : 'Edit campaign',
//                                   style: const TextStyle(
//                                     fontSize: 22,
//                                     fontWeight: FontWeight.w900,
//                                     color: _navy,
//                                   ),
//                                 ),
//                                 const SizedBox(height: 3),
//                                 Text(
//                                   'Publish company-specific content inside ${workspace.company.name}.',
//                                   style: const TextStyle(
//                                     color: Color(0xFF718096),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ),
//                           IconButton(
//                             onPressed: () => Navigator.pop(dialogContext, false),
//                             icon: const Icon(Icons.close_rounded),
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: 24),
//                       Wrap(
//                         spacing: 12,
//                         runSpacing: 12,
//                         children: [
//                           _EditorDropDown(
//                             width: 235,
//                             label: 'Campaign type',
//                             value: type,
//                             items: const [
//                               ('promotion', 'Promotion / offer'),
//                               ('announcement', 'Announcement'),
//                               ('onboarding', 'Onboarding'),
//                               ('update', 'Product / app update'),
//                               ('maintenance', 'Maintenance notice'),
//                               ('custom', 'Custom message'),
//                             ],
//                             onChanged: (value) =>
//                                 setLocalState(() => type = value),
//                           ),
//                           _EditorDropDown(
//                             width: 235,
//                             label: 'Display style',
//                             value: presentation,
//                             items: const [
//                               ('modal', 'Center modal'),
//                               ('banner', 'Top banner'),
//                               ('bottomCard', 'Bottom card'),
//                             ],
//                             onChanged: (value) => setLocalState(
//                               () => presentation = value,
//                             ),
//                           ),
//                           _EditorDropDown(
//                             width: 235,
//                             label: 'Frequency',
//                             value: frequency,
//                             items: const [
//                               ('once', 'Show once per user'),
//                               ('everySession', 'Once per app session'),
//                             ],
//                             onChanged: (value) =>
//                                 setLocalState(() => frequency = value),
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: 14),
//                       _EditorTextField(
//                         controller: title,
//                         label: 'Headline',
//                         maxLength: 80,
//                       ),
//                       const SizedBox(height: 12),
//                       _EditorTextField(
//                         controller: body,
//                         label: 'Message',
//                         minLines: 4,
//                         maxLines: 7,
//                         maxLength: 700,
//                       ),
//                       const SizedBox(height: 12),
//                       Row(
//                         children: [
//                           Expanded(
//                             child: _EditorTextField(
//                               controller: cta,
//                               label: 'Button label',
//                               maxLength: 32,
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           Expanded(
//                             child: _EditorTextField(
//                               controller: ctaUrl,
//                               label: 'Button URL',
//                               hint: 'https://example.com',
//                             ),
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: 12),
//                       _EditorDropDown(
//                         width: double.infinity,
//                         label: 'Run duration',
//                         value: durationDays.toString(),
//                         items: const [
//                           ('1', '1 day'),
//                           ('3', '3 days'),
//                           ('7', '7 days'),
//                           ('14', '14 days'),
//                           ('30', '30 days'),
//                           ('0', 'Until manually ended'),
//                         ],
//                         onChanged: (value) =>
//                             setLocalState(() => durationDays = int.parse(value)),
//                       ),
//                       const SizedBox(height: 10),
//                       SwitchListTile.adaptive(
//                         contentPadding: EdgeInsets.zero,
//                         value: allUsers,
//                         activeColor: _blue,
//                         title: const Text(
//                           'Show to all company users',
//                           style: TextStyle(fontWeight: FontWeight.w800),
//                         ),
//                         subtitle: const Text(
//                           'Turn off to target selected employee roles.',
//                         ),
//                         onChanged: (value) => setLocalState(() {
//                           allUsers = value;
//                           if (value) selectedRoles.clear();
//                         }),
//                       ),
//                       if (!allUsers) ...[
//                         const SizedBox(height: 8),
//                         Wrap(
//                           spacing: 8,
//                           runSpacing: 8,
//                           children: UserRole.values
//                               .where(
//                                 (role) =>
//                                     role != UserRole.superAdmin &&
//                                     role != UserRole.clientViewer,
//                               )
//                               .map(
//                                 (role) => FilterChip(
//                                   label: Text(role.label),
//                                   selected: selectedRoles.contains(role.value),
//                                   onSelected: (selected) =>
//                                       setLocalState(() {
//                                     if (selected) {
//                                       selectedRoles.add(role.value);
//                                     } else {
//                                       selectedRoles.remove(role.value);
//                                     }
//                                   }),
//                                 ),
//                               )
//                               .toList(),
//                         ),
//                       ],
//                       const SizedBox(height: 24),
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.end,
//                         children: [
//                           TextButton(
//                             onPressed: () =>
//                                 Navigator.pop(dialogContext, false),
//                             child: const Text('Cancel'),
//                           ),
//                           const SizedBox(width: 10),
//                           FilledButton.icon(
//                             onPressed: () {
//                               if (title.text.trim().length < 3 ||
//                                   body.text.trim().length < 5) {
//                                 ScaffoldMessenger.of(context).showSnackBar(
//                                   const SnackBar(
//                                     content: Text(
//                                       'Add a headline and message before saving.',
//                                     ),
//                                   ),
//                                 );
//                                 return;
//                               }
//                               Navigator.pop(dialogContext, true);
//                             },
//                             style: FilledButton.styleFrom(
//                               backgroundColor: _blue,
//                               padding: const EdgeInsets.symmetric(
//                                 horizontal: 20,
//                                 vertical: 14,
//                               ),
//                             ),
//                             icon: const Icon(Icons.save_rounded),
//                             label: Text(
//                               campaign == null
//                                   ? 'Save draft'
//                                   : 'Save changes',
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ),
//       ),
//     );

//     if (saved == true) {
//       final doc = campaign == null
//           ? _ref(companyId).doc()
//           : _ref(companyId).doc(campaign.id);

//       final payload = <String, dynamic>{
//         'campaignId': doc.id,
//         'companyId': companyId,
//         'type': type,
//         'presentation': presentation,
//         'title': title.text.trim(),
//         'body': body.text.trim(),
//         'ctaLabel': cta.text.trim(),
//         'ctaUrl': ctaUrl.text.trim(),
//         'audienceRoles': allUsers ? <String>[] : selectedRoles.toList()..sort(),
//         'frequency': frequency,
//         'durationDays': durationDays,
//         'updatedBy': member.uid,
//         'updatedAt': FieldValue.serverTimestamp(),
//         if (campaign == null) ...{
//           'status': 'draft',
//           'createdBy': member.uid,
//           'createdAt': FieldValue.serverTimestamp(),
//           'runCount': 0,
//         },
//       };

//       await doc.set(payload, SetOptions(merge: true));
//     }

//     title.dispose();
//     body.dispose();
//     cta.dispose();
//     ctaUrl.dispose();
//   }

//   Future<void> _runCampaign(_CampaignRecord campaign) async {
//     final workspace = ref.read(workspaceProvider);
//     final now = DateTime.now();

//     await _ref(workspace.company.companyId).doc(campaign.id).update({
//       'status': 'running',
//       'startedAt': Timestamp.fromDate(now),
//       'endsAt': campaign.durationDays > 0
//           ? Timestamp.fromDate(
//               now.add(Duration(days: campaign.durationDays)),
//             )
//           : null,
//       'runCount': FieldValue.increment(1),
//       'updatedAt': FieldValue.serverTimestamp(),
//       'updatedBy': workspace.currentMember.uid,
//     });

//     if (mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text(
//             '“${campaign.title}” is now live in ${workspace.company.name}.',
//           ),
//         ),
//       );
//     }
//   }

//   Future<void> _pauseCampaign(_CampaignRecord campaign) async {
//     final workspace = ref.read(workspaceProvider);

//     await _ref(workspace.company.companyId).doc(campaign.id).update({
//       'status': 'paused',
//       'updatedAt': FieldValue.serverTimestamp(),
//       'updatedBy': workspace.currentMember.uid,
//     });
//   }

//   Future<void> _endCampaign(_CampaignRecord campaign) async {
//     final workspace = ref.read(workspaceProvider);

//     await _ref(workspace.company.companyId).doc(campaign.id).update({
//       'status': 'ended',
//       'endedAt': FieldValue.serverTimestamp(),
//       'updatedAt': FieldValue.serverTimestamp(),
//       'updatedBy': workspace.currentMember.uid,
//     });
//   }

//   Future<void> _deleteCampaign(_CampaignRecord campaign) async {
//     final workspace = ref.read(workspaceProvider);

//     final confirmed = await showDialog<bool>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Delete campaign?'),
//         content: Text('Delete “${campaign.title}”? This cannot be undone.'),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context, false),
//             child: const Text('Cancel'),
//           ),
//           FilledButton(
//             onPressed: () => Navigator.pop(context, true),
//             child: const Text('Delete'),
//           ),
//         ],
//       ),
//     );

//     if (confirmed == true) {
//       await _ref(workspace.company.companyId).doc(campaign.id).delete();
//     }
//   }

//   (String, String, String) _templateValues(String? template) {
//     return switch (template) {
//       'announcement' => (
//           'Important company update',
//           'We have an important update for everyone. Tap below to learn more.',
//           'Learn more',
//         ),
//       'onboarding' => (
//           'Welcome to the team',
//           'Complete the next onboarding step and get familiar with your workspace.',
//           'Continue',
//         ),
//       'update' => (
//           'A new app update is ready',
//           'Discover the latest improvements available in your company workspace.',
//           'See what’s new',
//         ),
//       'maintenance' => (
//           'Scheduled maintenance',
//           'Some services may be temporarily unavailable during the maintenance window.',
//           'View details',
//         ),
//       _ => (
//           'Special offer for our team',
//           'Share your promotional message, benefit, event, or limited-time offer here.',
//           'View offer',
//         ),
//     };
//   }
// }

// class _ReferenceSideBar extends StatelessWidget {
//   const _ReferenceSideBar({required this.activeSection, required this.onSelect});

//   final String activeSection;
//   final ValueChanged<String> onSelect;

//   @override
//   Widget build(BuildContext context) {
//     const items = [
//       (Icons.grid_view_rounded, 'Overview'),
//       (Icons.campaign_outlined, 'Campaigns'),
//       (Icons.auto_awesome_outlined, 'Creatives'),
//       (Icons.groups_outlined, 'Audience'),
//       (Icons.bar_chart_outlined, 'Finance'),
//       (Icons.support_agent_outlined, 'Support'),
//     ];

//     return Container(
//       color: const Color(0xFF09152D),
//       child: Column(
//         children: [
//           const SizedBox(height: 17),
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 17),
//             child: Row(
//               children: [
//                 const Text(
//                   'claro',
//                   style: TextStyle(
//                     color: Colors.white,
//                     fontSize: 21,
//                     fontWeight: FontWeight.w900,
//                     letterSpacing: -1,
//                   ),
//                 ),
//                 const Text(
//                   '•x',
//                   style: TextStyle(
//                     color: Color(0xFF6CCBFF),
//                     fontSize: 20,
//                     fontWeight: FontWeight.w900,
//                   ),
//                 ),
//                 const Spacer(),
//                 Icon(Icons.menu_rounded, color: Color(0xFF70829F), size: 18),
//               ],
//             ),
//           ),
//           const SizedBox(height: 42),
//           for (final item in items)
//             _ReferenceNavItem(
//               icon: item.$1,
//               label: item.$2,
//               selected: activeSection == item.$2,
//               onTap: () => onSelect(item.$2),
//             ),
//           const Spacer(),
//           Container(
//             margin: const EdgeInsets.fromLTRB(12, 0, 12, 15),
//             padding: const EdgeInsets.all(10),
//             decoration: BoxDecoration(
//               color: const Color(0xFF12203C),
//               borderRadius: BorderRadius.circular(7),
//             ),
//             child: const Column(
//               children: [
//                 CircleAvatar(
//                   radius: 20,
//                   backgroundColor: Color(0xFFE4EAF2),
//                   child: Icon(Icons.person, color: Color(0xFF26364E)),
//                 ),
//                 SizedBox(height: 8),
//                 Text(
//                   'Campaign Manager',
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(
//                     color: Colors.white,
//                     fontSize: 9,
//                     fontWeight: FontWeight.w800,
//                   ),
//                 ),
//                 SizedBox(height: 3),
//                 Text(
//                   'Account Manager',
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(color: Color(0xFF8090AA), fontSize: 8),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _ReferenceNavItem extends StatelessWidget {
//   const _ReferenceNavItem({
//     required this.icon,
//     required this.label,
//     required this.selected,
//     required this.onTap,
//   });

//   final IconData icon;
//   final String label;
//   final bool selected;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onTap,
//       child: SizedBox(
//         height: 45,
//         child: Stack(
//           children: [
//             if (selected)
//               Positioned(
//                 left: 0,
//                 top: 7,
//                 bottom: 7,
//                 child: Container(
//                   width: 3,
//                   decoration: const BoxDecoration(
//                     color: Color(0xFF4EA5F8),
//                     borderRadius: BorderRadius.horizontal(
//                       right: Radius.circular(4),
//                     ),
//                   ),
//                 ),
//               ),
//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 17),
//               child: Row(
//                 children: [
//                   Icon(
//                     icon,
//                     size: 17,
//                     color: selected
//                         ? const Color(0xFF4EA5F8)
//                         : const Color(0xFF657793),
//                   ),
//                   const SizedBox(width: 12),
//                   Text(
//                     label,
//                     style: TextStyle(
//                       color: selected
//                           ? const Color(0xFF4EA5F8)
//                           : const Color(0xFF71819C),
//                       fontSize: 11,
//                       fontWeight:
//                           selected ? FontWeight.w800 : FontWeight.w600,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _ReferenceTopBar extends StatelessWidget {
//   const _ReferenceTopBar({required this.companyName, required this.onCreate});

//   final String companyName;
//   final VoidCallback onCreate;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: 58,
//       color: Colors.white,
//       padding: const EdgeInsets.symmetric(horizontal: 14),
//       child: Row(
//         children: [
//           Row(
//             children: [
//               Icon(Icons.home_rounded, size: 12, color: Color(0xFF6B8BB0)),
//               const SizedBox(width: 4),
//               const Text(
//                 'Go back to main site',
//                 style: TextStyle(
//                   color: Color(0xFF667B96),
//                   fontSize: 9,
//                   fontWeight: FontWeight.w700,
//                 ),
//               ),
//             ],
//           ),
//           const Spacer(),
//           SizedBox(
//             height: 28,
//             child: FilledButton(
//               onPressed: onCreate,
//               style: FilledButton.styleFrom(
//                 backgroundColor: const Color(0xFF4B9CF5),
//                 padding: const EdgeInsets.symmetric(horizontal: 13),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(4),
//                 ),
//               ),
//               child: const Text(
//                 'Create Campaign',
//                 style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
//               ),
//             ),
//           ),
//           const SizedBox(width: 9),
//           Container(
//             height: 28,
//             padding: const EdgeInsets.symmetric(horizontal: 10),
//             alignment: Alignment.center,
//             decoration: BoxDecoration(
//               color: const Color(0xFFF1F6FC),
//               borderRadius: BorderRadius.circular(4),
//             ),
//             child: const Text.rich(
//               TextSpan(
//                 text: 'Balance: ',
//                 style: TextStyle(
//                   color: Color(0xFF8292A8),
//                   fontSize: 9,
//                   fontWeight: FontWeight.w600,
//                 ),
//                 children: [
//                   TextSpan(
//                     text: '\$12,468.00',
//                     style: TextStyle(
//                       color: Color(0xFF4B9CF5),
//                       fontWeight: FontWeight.w900,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           const SizedBox(width: 12),
//           const Icon(Icons.chat_bubble_outline_rounded,
//               size: 15, color: Color(0xFF6C7E95)),
//           const SizedBox(width: 13),
//           const Icon(Icons.share_outlined,
//               size: 15, color: Color(0xFF6C7E95)),
//           const SizedBox(width: 13),
//           const Text('🇺🇸', style: TextStyle(fontSize: 14)),
//           const SizedBox(width: 9),
//           const CircleAvatar(
//             radius: 12,
//             backgroundColor: Color(0xFF4B9CF5),
//             child: Icon(Icons.person_rounded, size: 13, color: Colors.white),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _ReferenceFilterPanel extends StatelessWidget {
//   const _ReferenceFilterPanel({
//     required this.dateFilter,
//     required this.deviceFilter,
//     required this.osFilter,
//     required this.formatFilter,
//     required this.onDateChanged,
//     required this.onDeviceChanged,
//     required this.onOsChanged,
//     required this.onFormatChanged,
//   });

//   final String dateFilter;
//   final String deviceFilter;
//   final String osFilter;
//   final String formatFilter;
//   final ValueChanged<String> onDateChanged;
//   final ValueChanged<String> onDeviceChanged;
//   final ValueChanged<String> onOsChanged;
//   final ValueChanged<String> onFormatChanged;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       color: const Color(0xFFF8FAFD),
//       padding: const EdgeInsets.fromLTRB(15, 23, 15, 16),
//       child: SingleChildScrollView(
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Text(
//               'Filter',
//               style: TextStyle(
//                 color: Color(0xFF56677F),
//                 fontSize: 12,
//                 fontWeight: FontWeight.w800,
//               ),
//             ),
//             const SizedBox(height: 12),
//             _ReferenceInput(
//               label: dateFilter,
//               icon: Icons.calendar_today_outlined,
//               onTap: () => _choose(
//                 context,
//                 'Date Range',
//                 const ['Today', 'Last 7 Days', 'Last 30 Days', 'This year'],
//                 dateFilter,
//                 onDateChanged,
//               ),
//             ),
//             const SizedBox(height: 9),
//             _ReferenceInput(
//               label: 'Choose a Country',
//               icon: Icons.search_rounded,
//               onTap: () {},
//             ),
//             const SizedBox(height: 13),
//             const _ReferenceFilterTitle('Device'),
//             _ReferenceChoiceGrid(
//               values: const ['Desktop', 'Tablet', 'Mobile'],
//               icons: const [
//                 Icons.desktop_windows_outlined,
//                 Icons.tablet_mac_outlined,
//                 Icons.phone_iphone_outlined,
//               ],
//               selected: deviceFilter,
//               onChanged: onDeviceChanged,
//             ),
//             const SizedBox(height: 12),
//             const _ReferenceFilterTitle('OS'),
//             _ReferenceChoiceGrid(
//               values: const ['Android', 'Linux', 'Windows', 'MacOS', 'iOS'],
//               icons: const [
//                 Icons.android,
//                 Icons.computer_outlined,
//                 Icons.window_outlined,
//                 Icons.laptop_mac_outlined,
//                 Icons.phone_iphone_outlined,
//               ],
//               selected: osFilter,
//               onChanged: onOsChanged,
//               columns: 3,
//             ),
//             const SizedBox(height: 12),
//             const _ReferenceFilterTitle('Browsers'),
//             _ReferenceChoiceGrid(
//               values: const ['Chrome', 'Firefox', 'Safari', 'More'],
//               icons: const [
//                 Icons.language,
//                 Icons.public,
//                 Icons.explore_outlined,
//                 Icons.more_horiz,
//               ],
//               selected: 'All',
//               onChanged: (_) {},
//               columns: 3,
//             ),
//             const SizedBox(height: 12),
//             const _ReferenceFilterTitle('Format'),
//             _ReferenceChoiceGrid(
//               values: const ['Native', 'Video', 'Push'],
//               icons: const [
//                 Icons.auto_awesome_outlined,
//                 Icons.play_circle_outline,
//                 Icons.dashboard_customize_outlined,
//               ],
//               selected: formatFilter,
//               onChanged: onFormatChanged,
//             ),
//             const SizedBox(height: 16),
//             SizedBox(
//               width: double.infinity,
//               height: 31,
//               child: FilledButton(
//                 onPressed: () {},
//                 style: FilledButton.styleFrom(
//                   backgroundColor: const Color(0xFF4B9CF5),
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(3),
//                   ),
//                 ),
//                 child: const Text(
//                   'Reset Filters',
//                   style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   void _choose(
//     BuildContext context,
//     String title,
//     List<String> items,
//     String current,
//     ValueChanged<String> onChanged,
//   ) async {
//     final value = await showModalBottomSheet<String>(
//       context: context,
//       builder: (context) => SafeArea(
//         child: ListView(
//           shrinkWrap: true,
//           children: [
//             Padding(
//               padding: const EdgeInsets.all(18),
//               child: Text(title,
//                   style: const TextStyle(fontWeight: FontWeight.w800)),
//             ),
//             for (final item in items)
//               ListTile(
//                 title: Text(item),
//                 trailing: item == current
//                     ? const Icon(Icons.check, color: Color(0xFF4B9CF5))
//                     : null,
//                 onTap: () => Navigator.pop(context, item),
//               ),
//           ],
//         ),
//       ),
//     );
//     if (value != null) onChanged(value);
//   }
// }

// class _ReferenceFilterTitle extends StatelessWidget {
//   const _ReferenceFilterTitle(this.text);
//   final String text;

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.only(left: 2, bottom: 6),
//       child: Text(
//         text,
//         style: const TextStyle(
//           color: Color(0xFF56677F),
//           fontSize: 10,
//           fontWeight: FontWeight.w800,
//         ),
//       ),
//     );
//   }
// }

// class _ReferenceInput extends StatelessWidget {
//   const _ReferenceInput({required this.label, required this.icon, required this.onTap});
//   final String label;
//   final IconData icon;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onTap,
//       child: Container(
//         height: 35,
//         padding: const EdgeInsets.symmetric(horizontal: 9),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           border: Border.all(color: const Color(0xFFE2E8F0)),
//           borderRadius: BorderRadius.circular(4),
//         ),
//         child: Row(
//           children: [
//             Expanded(
//               child: Text(
//                 label,
//                 overflow: TextOverflow.ellipsis,
//                 style: const TextStyle(
//                   color: Color(0xFF8796AA),
//                   fontSize: 9,
//                 ),
//               ),
//             ),
//             Icon(icon, size: 14, color: const Color(0xFF8C9BB0)),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _ReferenceChoiceGrid extends StatelessWidget {
//   const _ReferenceChoiceGrid({
//     required this.values,
//     required this.icons,
//     required this.selected,
//     required this.onChanged,
//     this.columns = 3,
//   });

//   final List<String> values;
//   final List<IconData> icons;
//   final String selected;
//   final ValueChanged<String> onChanged;
//   final int columns;

//   @override
//   Widget build(BuildContext context) {
//     return Wrap(
//       spacing: 3,
//       runSpacing: 3,
//       children: List.generate(values.length, (index) {
//         final value = values[index];
//         final active = selected == value ||
//             (selected == 'All devices' && value == 'Desktop');
//         return InkWell(
//           onTap: () => onChanged(value),
//           borderRadius: BorderRadius.circular(4),
//           child: Container(
//             width: columns == 3 ? 51 : 50,
//             height: 52,
//             decoration: BoxDecoration(
//               color: active ? const Color(0xFFF0F6FD) : Colors.transparent,
//               borderRadius: BorderRadius.circular(4),
//             ),
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Icon(
//                   icons[index],
//                   size: 17,
//                   color: active
//                       ? const Color(0xFF4B9CF5)
//                       : const Color(0xFF8A98AA),
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   value,
//                   textAlign: TextAlign.center,
//                   style: TextStyle(
//                     color: active
//                         ? const Color(0xFF4B6688)
//                         : const Color(0xFF8997AA),
//                     fontSize: 7.5,
//                     fontWeight: active ? FontWeight.w800 : FontWeight.w600,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         );
//       }),
//     );
//   }
// }

// class _ReferenceChart extends StatelessWidget {
//   const _ReferenceChart({required this.campaigns, required this.dateFilter});
//   final List<_CampaignRecord> campaigns;
//   final String dateFilter;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: 300,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         border: Border.all(color: const Color(0xFFE2E8F0)),
//         borderRadius: BorderRadius.circular(3),
//       ),
//       padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               const _ReferenceTab('Impressions', active: true),
//               const _ReferenceTab('Clicks'),
//               const _ReferenceTab('CTR'),
//               const _ReferenceTab('Views'),
//               const _ReferenceTab('Conversion'),
//               const _ReferenceTab('Total Spent'),
//               const Spacer(),
//               _ReferenceMiniSelect(value: dateFilter),
//             ],
//           ),
//           const SizedBox(height: 8),
//           Expanded(
//             child: Row(
//               children: [
//                 const SizedBox(
//                   width: 31,
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       Text('500', style: _referenceAxis),
//                       Text('400', style: _referenceAxis),
//                       Text('300', style: _referenceAxis),
//                       Text('200', style: _referenceAxis),
//                       Text('100', style: _referenceAxis),
//                       Text('50', style: _referenceAxis),
//                     ],
//                   ),
//                 ),
//                 Expanded(
//                   child: CustomPaint(
//                     painter: _ReferenceLinePainter(seed: campaigns.length),
//                     child: const SizedBox.expand(),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(height: 4),
//           const Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               _LegendDot(color: Color(0xFF55D6D1), label: 'Click'),
//               SizedBox(width: 16),
//               _LegendDot(color: Color(0xFF4B9CF5), label: 'View'),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   static const _referenceAxis = TextStyle(
//     color: Color(0xFF9BA9BB),
//     fontSize: 8,
//   );
// }

// class _ReferenceTab extends StatelessWidget {
//   const _ReferenceTab(this.text, {this.active = false});
//   final String text;
//   final bool active;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       margin: const EdgeInsets.only(right: 25),
//       padding: const EdgeInsets.only(bottom: 9),
//       decoration: BoxDecoration(
//         border: active
//             ? const Border(
//                 bottom: BorderSide(color: Color(0xFF4B9CF5), width: 2),
//               )
//             : null,
//       ),
//       child: Text(
//         text,
//         style: TextStyle(
//           color: active ? const Color(0xFF4B9CF5) : const Color(0xFF7D8BA0),
//           fontSize: 9,
//           fontWeight: active ? FontWeight.w800 : FontWeight.w600,
//         ),
//       ),
//     );
//   }
// }

// class _ReferenceMiniSelect extends StatelessWidget {
//   const _ReferenceMiniSelect({required this.value});
//   final String value;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: 23,
//       padding: const EdgeInsets.symmetric(horizontal: 8),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         border: Border.all(color: const Color(0xFFE1E7EF)),
//         borderRadius: BorderRadius.circular(3),
//       ),
//       child: Row(
//         children: [
//           Text(value,
//               style: const TextStyle(color: Color(0xFF64748A), fontSize: 8)),
//           const SizedBox(width: 6),
//           const Icon(Icons.keyboard_arrow_down_rounded,
//               size: 13, color: Color(0xFF8090A5)),
//         ],
//       ),
//     );
//   }
// }

// class _ReferenceLinePainter extends CustomPainter {
//   _ReferenceLinePainter({required this.seed});
//   final int seed;

//   @override
//   void paint(Canvas canvas, Size size) {
//     final grid = Paint()
//       ..color = const Color(0xFFE9EEF4)
//       ..strokeWidth = 1;

//     for (int i = 0; i < 6; i++) {
//       final y = size.height * i / 5;
//       canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
//     }
//     for (int i = 0; i < 12; i++) {
//       final x = size.width * i / 11;
//       canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
//     }

//     final blueValues = [
//       .22, .29, .25, .36, .33, .45, .43, .51, .49, .57, .50, .59,
//       .55, .62, .58, .68, .60, .69, .63, .72, .66, .74, .70, .78,
//     ];
//     final tealValues = [
//       .21, .42, .34, .37, .52, .44, .30, .25, .27, .34, .28, .31,
//       .24, .38, .34, .46, .42, .36, .31, .29, .38, .34, .24, .18,
//     ];

//     Path pathFor(List<double> values) {
//       final path = Path();
//       for (int i = 0; i < values.length; i++) {
//         final x = size.width * i / (values.length - 1);
//         final y = size.height * (1 - values[i]);
//         if (i == 0) {
//           path.moveTo(x, y);
//         } else {
//           final px = size.width * (i - 1) / (values.length - 1);
//           final py = size.height * (1 - values[i - 1]);
//           final mid = (px + x) / 2;
//           path.cubicTo(mid, py, mid, y, x, y);
//         }
//       }
//       return path;
//     }

//     final blue = Paint()
//       ..color = const Color(0xFF4B9CF5)
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 2.4
//       ..strokeCap = StrokeCap.round;
//     final teal = Paint()
//       ..color = const Color(0xFF58D3D0)
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 2.1
//       ..strokeCap = StrokeCap.round;
//     final fill = Paint()
//       ..color = const Color(0xFF4B9CF5).withOpacity(.10)
//       ..style = PaintingStyle.fill;

//     final first = pathFor(blueValues);
//     final area = Path.from(first)
//       ..lineTo(size.width, size.height)
//       ..lineTo(0, size.height)
//       ..close();
//     canvas.drawPath(area, fill);
//     canvas.drawPath(first, blue);
//     canvas.drawPath(pathFor(tealValues), teal);

//     const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
//     for (int i = 0; i < months.length; i++) {
//       final tp = TextPainter(
//         text: TextSpan(
//           text: months[i],
//           style: const TextStyle(color: Color(0xFF9AA8B9), fontSize: 7),
//         ),
//         textDirection: TextDirection.ltr,
//       )..layout();
//       final x = size.width * i / 11 - tp.width / 2;
//       tp.paint(canvas, Offset(x, size.height + 7));
//     }
//   }

//   @override
//   bool shouldRepaint(covariant _ReferenceLinePainter oldDelegate) =>
//       oldDelegate.seed != seed;
// }

// class _ReferenceMetricStrip extends StatelessWidget {
//   const _ReferenceMetricStrip({required this.campaigns});
//   final List<_CampaignRecord> campaigns;

//   @override
//   Widget build(BuildContext context) {
//     final impressions = campaigns.fold<int>(0, (sum, c) => sum + 100 + c.audienceRoles.length * 25);
//     final clicks = campaigns.fold<int>(0, (sum, c) => sum + (c.status == 'running' ? 12 : 4));
//     final ctr = impressions == 0 ? '0.00%' : '${(clicks / impressions * 100).toStringAsFixed(2)}%';

//     final items = [
//       ('Impressions', _compactNumber(impressions), '8.5% ↑'),
//       ('Clicks', _compactNumber(clicks), '8.5% ↑'),
//       ('CTR', ctr, '8.5% ↓'),
//       ('Total Spent', '—', '8.5% ↑'),
//       ('Visite', '${campaigns.length * 24}', '8.5% ↓'),
//       ('Conversions', '—', '8.5% ↑'),
//     ];

//     return Container(
//       height: 76,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         border: Border.all(color: const Color(0xFFE2E8F0)),
//         borderRadius: BorderRadius.circular(3),
//       ),
//       child: Row(
//         children: [
//           for (int i = 0; i < items.length; i++)
//             Expanded(
//               child: Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
//                 decoration: i == 0
//                     ? null
//                     : const BoxDecoration(
//                         border: Border(left: BorderSide(color: Color(0xFFE9EDF3))),
//                       ),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Text(items[i].$1, style: const TextStyle(color: Color(0xFF8997AA), fontSize: 8)),
//                     const SizedBox(height: 3),
//                     Text(items[i].$2, style: const TextStyle(color: Color(0xFF27374E), fontSize: 17, fontWeight: FontWeight.w800)),
//                     const SizedBox(height: 2),
//                     Text(items[i].$3, style: TextStyle(color: items[i].$3.contains('↓') ? const Color(0xFFE38A7F) : const Color(0xFF62A37A), fontSize: 7, fontWeight: FontWeight.w700)),
//                   ],
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }

//   String _compactNumber(int value) {
//     if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
//     if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
//     return value.toString();
//   }
// }

// class _ResponsiveCampaignDashboard extends StatelessWidget {
//   const _ResponsiveCampaignDashboard({
//     required this.campaigns,
//     required this.visible,
//     required this.running,
//     required this.drafts,
//     required this.paused,
//     required this.ended,
//     required this.companyName,
//     required this.statusFilter,
//     required this.dateFilter,
//     required this.deviceFilter,
//     required this.osFilter,
//     required this.formatFilter,
//     required this.onStatusChanged,
//     required this.onDateChanged,
//     required this.onDeviceChanged,
//     required this.onOsChanged,
//     required this.onFormatChanged,
//     required this.onCreate,
//     required this.onEdit,
//     required this.onRun,
//     required this.onPause,
//     required this.onEnd,
//     required this.onDelete,
//     required this.compact,
//   });

//   final List<_CampaignRecord> campaigns;
//   final List<_CampaignRecord> visible;
//   final int running;
//   final int drafts;
//   final int paused;
//   final int ended;
//   final String companyName;
//   final String statusFilter;
//   final String dateFilter;
//   final String deviceFilter;
//   final String osFilter;
//   final String formatFilter;
//   final ValueChanged<String> onStatusChanged;
//   final ValueChanged<String> onDateChanged;
//   final ValueChanged<String> onDeviceChanged;
//   final ValueChanged<String> onOsChanged;
//   final ValueChanged<String> onFormatChanged;
//   final VoidCallback onCreate;
//   final ValueChanged<_CampaignRecord> onEdit;
//   final ValueChanged<_CampaignRecord> onRun;
//   final ValueChanged<_CampaignRecord> onPause;
//   final ValueChanged<_CampaignRecord> onEnd;
//   final ValueChanged<_CampaignRecord> onDelete;
//   final bool compact;

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         _TopBar(companyName: companyName, onCreate: onCreate, onBack: () {}),
//         Expanded(
//           child: ListView(
//             padding: const EdgeInsets.all(16),
//             children: [
//               _ReferenceFilterPanel(
//                 dateFilter: dateFilter,
//                 deviceFilter: deviceFilter,
//                 osFilter: osFilter,
//                 formatFilter: formatFilter,
//                 onDateChanged: onDateChanged,
//                 onDeviceChanged: onDeviceChanged,
//                 onOsChanged: onOsChanged,
//                 onFormatChanged: onFormatChanged,
//               ),
//               const SizedBox(height: 14),
//               _ReferenceChart(campaigns: campaigns, dateFilter: dateFilter),
//               const SizedBox(height: 14),
//               _ReferenceMetricStrip(campaigns: campaigns),
//               const SizedBox(height: 14),
//               _DashboardLowerSection(
//                 campaigns: campaigns,
//                 visible: visible,
//                 statusFilter: statusFilter,
//                 deviceFilter: deviceFilter,
//                 osFilter: osFilter,
//                 formatFilter: formatFilter,
//                 onStatusChanged: onStatusChanged,
//                 onOsChanged: onOsChanged,
//                 onFormatChanged: onFormatChanged,
//                 onCreate: onCreate,
//                 onEdit: onEdit,
//                 onRun: onRun,
//                 onPause: onPause,
//                 onEnd: onEnd,
//                 onDelete: onDelete,
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

// class _SideBar extends StatelessWidget {
//   const _SideBar({
//     required this.activeSection,
//     required this.onSelect,
//     required this.compact,
//   });

//   final String activeSection;
//   final ValueChanged<String> onSelect;
//   final bool compact;

//   static const _navy = Color(0xFF0A1530);

//   @override
//   Widget build(BuildContext context) {
//     final items = const [
//       (Icons.dashboard_rounded, 'Overview'),
//       (Icons.campaign_rounded, 'Campaigns'),
//       (Icons.auto_awesome_rounded, 'Creatives'),
//       (Icons.groups_rounded, 'Audience'),
//       (Icons.bar_chart_rounded, 'Finance'),
//       (Icons.support_agent_rounded, 'Support'),
//     ];

//     return Container(
//       width: compact ? 72 : 205,
//       color: _navy,
//       child: Column(
//         children: [
//           Padding(
//             padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 18, 12, 22),
//             child: Row(
//               children: [
//                 const Icon(
//                   Icons.bubble_chart_rounded,
//                   color: Colors.white,
//                   size: 27,
//                 ),
//                 if (!compact) ...[
//                   const SizedBox(width: 8),
//                   const Text(
//                     'Claro•x',
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 21,
//                       fontWeight: FontWeight.w900,
//                       letterSpacing: -.6,
//                     ),
//                   ),
//                 ],
//                 const Spacer(),
//                 if (!compact)
//                   const Icon(
//                     Icons.menu_rounded,
//                     color: Color(0xFF8FA0BF),
//                     size: 20,
//                   ),
//               ],
//             ),
//           ),
//           for (final item in items)
//             _SideBarItem(
//               icon: item.$1,
//               label: item.$2,
//               selected: activeSection == item.$2,
//               compact: compact,
//               onTap: () => onSelect(item.$2),
//             ),
//           const Spacer(),
//           if (!compact)
//             Container(
//               margin: const EdgeInsets.all(14),
//               padding: const EdgeInsets.all(12),
//               decoration: BoxDecoration(
//                 color: const Color(0xFF121F3D),
//                 borderRadius: BorderRadius.circular(15),
//               ),
//               child: const Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   CircleAvatar(
//                     radius: 20,
//                     child: Icon(Icons.person_rounded),
//                   ),
//                   SizedBox(height: 9),
//                   Text(
//                     'Campaign Manager',
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontWeight: FontWeight.w800,
//                       fontSize: 12,
//                     ),
//                   ),
//                   SizedBox(height: 3),
//                   Text(
//                     'Company Admin',
//                     style: TextStyle(
//                       color: Color(0xFF8EA0C0),
//                       fontSize: 11,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }

// class _SideBarItem extends StatelessWidget {
//   const _SideBarItem({
//     required this.icon,
//     required this.label,
//     required this.selected,
//     required this.compact,
//     required this.onTap,
//   });

//   final IconData icon;
//   final String label;
//   final bool selected;
//   final bool compact;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onTap,
//       child: Container(
//         height: 52,
//         margin: EdgeInsets.symmetric(
//           horizontal: compact ? 8 : 12,
//           vertical: 2,
//         ),
//         decoration: BoxDecoration(
//           color: selected ? const Color(0xFF172744) : Colors.transparent,
//           borderRadius: BorderRadius.circular(10),
//         ),
//         child: Row(
//           mainAxisAlignment:
//               compact ? MainAxisAlignment.center : MainAxisAlignment.start,
//           children: [
//             if (selected)
//               Container(
//                 width: 3,
//                 height: 30,
//                 margin: const EdgeInsets.only(right: 10),
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF4B9CF5),
//                   borderRadius: BorderRadius.circular(4),
//                 ),
//               ),
//             Icon(
//               icon,
//               size: 19,
//               color: selected
//                   ? const Color(0xFF4B9CF5)
//                   : const Color(0xFF8191B0),
//             ),
//             if (!compact) ...[
//               const SizedBox(width: 12),
//               Text(
//                 label,
//                 style: TextStyle(
//                   color: selected ? Colors.white : const Color(0xFF8191B0),
//                   fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
//                   fontSize: 13,
//                 ),
//               ),
//             ],
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _TopBar extends StatelessWidget {
//   const _TopBar({
//     required this.companyName,
//     required this.onCreate,
//     required this.onBack,
//   });

//   final String companyName;
//   final VoidCallback onCreate;
//   final VoidCallback onBack;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: 64,
//       decoration: const BoxDecoration(
//         color: Colors.white,
//         border: Border(
//           bottom: BorderSide(color: Color(0xFFE5EAF2)),
//         ),
//       ),
//       child: Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 20),
//         child: Row(
//           children: [
//             InkWell(
//               onTap: onBack,
//               borderRadius: BorderRadius.circular(8),
//               child: const Padding(
//                 padding: EdgeInsets.symmetric(horizontal: 7, vertical: 8),
//                 child: Row(
//                   children: [
//                     Icon(
//                       Icons.home_rounded,
//                       size: 15,
//                       color: Color(0xFF6B7B96),
//                     ),
//                     SizedBox(width: 6),
//                     Text(
//                       'Go back to main site',
//                       style: TextStyle(
//                         color: Color(0xFF657590),
//                         fontSize: 11,
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//             const Spacer(),
//             FilledButton(
//               onPressed: onCreate,
//               style: FilledButton.styleFrom(
//                 backgroundColor: const Color(0xFF4B9CF5),
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 16,
//                   vertical: 12,
//                 ),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(7),
//                 ),
//               ),
//               child: const Text(
//                 'Create Campaign',
//                 style: TextStyle(
//                   fontSize: 12,
//                   fontWeight: FontWeight.w800,
//                 ),
//               ),
//             ),
//             const SizedBox(width: 10),
//             Container(
//               padding: const EdgeInsets.symmetric(
//                 horizontal: 13,
//                 vertical: 10,
//               ),
//               decoration: BoxDecoration(
//                 color: const Color(0xFFF2F7FD),
//                 borderRadius: BorderRadius.circular(7),
//               ),
//               child: const Text(
//                 'Balance:  12,468.00',
//                 style: TextStyle(
//                   color: Color(0xFF54718F),
//                   fontSize: 11,
//                   fontWeight: FontWeight.w800,
//                 ),
//               ),
//             ),
//             const SizedBox(width: 12),
//             const Icon(Icons.chat_bubble_outline_rounded, size: 19),
//             const SizedBox(width: 15),
//             const Icon(Icons.share_outlined, size: 19),
//             const SizedBox(width: 15),
//             const Text('🇺🇸', style: TextStyle(fontSize: 17)),
//             const SizedBox(width: 12),
//             const CircleAvatar(
//               radius: 15,
//               backgroundColor: Color(0xFF4B9CF5),
//               child: Icon(
//                 Icons.person_rounded,
//                 size: 16,
//                 color: Colors.white,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _PageHeading extends StatelessWidget {
//   const _PageHeading({
//     required this.companyName,
//     required this.onCreate,
//   });

//   final String companyName;
//   final VoidCallback onCreate;

//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               const Text(
//                 'Campaign overview',
//                 style: TextStyle(
//                   fontSize: 26,
//                   fontWeight: FontWeight.w900,
//                   color: Color(0xFF18263D),
//                 ),
//               ),
//               const SizedBox(height: 5),
//               Text(
//                 'Monitor and run in-app campaigns for $companyName.',
//                 style: const TextStyle(
//                   color: Color(0xFF73819A),
//                   fontSize: 13,
//                 ),
//               ),
//             ],
//           ),
//         ),
//         OutlinedButton.icon(
//           onPressed: onCreate,
//           icon: const Icon(Icons.add_rounded, size: 18),
//           label: const Text('New campaign'),
//         ),
//       ],
//     );
//   }
// }

// class _FilterBar extends StatelessWidget {
//   const _FilterBar({
//     required this.dateFilter,
//     required this.deviceFilter,
//     required this.onDateChanged,
//     required this.onDeviceChanged,
//   });

//   final String dateFilter;
//   final String deviceFilter;
//   final ValueChanged<String> onDateChanged;
//   final ValueChanged<String> onDeviceChanged;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(13),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: const Color(0xFFE3EAF3)),
//       ),
//       child: Wrap(
//         spacing: 10,
//         runSpacing: 10,
//         crossAxisAlignment: WrapCrossAlignment.center,
//         children: [
//           _FilterDropDown(
//             icon: Icons.calendar_month_outlined,
//             value: dateFilter,
//             items: const [
//               'Today',
//               'Last 7 Days',
//               'Last 30 Days',
//               'This year',
//             ],
//             onChanged: onDateChanged,
//           ),
//           _FilterDropDown(
//             icon: Icons.devices_other_rounded,
//             value: deviceFilter,
//             items: const [
//               'All devices',
//               'Desktop',
//               'Tablet',
//               'Mobile',
//             ],
//             onChanged: onDeviceChanged,
//           ),
//           const _FilterSearchBox(),
//           TextButton.icon(
//             onPressed: () {},
//             icon: const Icon(Icons.restart_alt_rounded, size: 17),
//             label: const Text('Reset filters'),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _FilterDropDown extends StatelessWidget {
//   const _FilterDropDown({
//     required this.icon,
//     required this.value,
//     required this.items,
//     required this.onChanged,
//   });

//   final IconData icon;
//   final String value;
//   final List<String> items;
//   final ValueChanged<String> onChanged;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       constraints: const BoxConstraints(minWidth: 160),
//       padding: const EdgeInsets.symmetric(horizontal: 10),
//       decoration: BoxDecoration(
//         border: Border.all(color: const Color(0xFFDCE4EF)),
//         borderRadius: BorderRadius.circular(8),
//       ),
//       child: DropdownButtonHideUnderline(
//         child: DropdownButton<String>(
//           value: value,
//           isDense: true,
//           icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
//           items: items
//               .map(
//                 (item) => DropdownMenuItem(
//                   value: item,
//                   child: Row(
//                     children: [
//                       Icon(icon, size: 15, color: const Color(0xFF71809A)),
//                       const SizedBox(width: 7),
//                       Text(item, style: const TextStyle(fontSize: 12)),
//                     ],
//                   ),
//                 ),
//               )
//               .toList(),
//           onChanged: (v) {
//             if (v != null) onChanged(v);
//           },
//         ),
//       ),
//     );
//   }
// }

// class _FilterSearchBox extends StatelessWidget {
//   const _FilterSearchBox();

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: 190,
//       height: 38,
//       padding: const EdgeInsets.symmetric(horizontal: 11),
//       decoration: BoxDecoration(
//         border: Border.all(color: const Color(0xFFDCE4EF)),
//         borderRadius: BorderRadius.circular(8),
//       ),
//       child: const Row(
//         children: [
//           Icon(Icons.search_rounded, size: 17, color: Color(0xFF8795A9)),
//           SizedBox(width: 7),
//           Expanded(
//             child: Text(
//               'Search campaigns',
//               style: TextStyle(
//                 fontSize: 12,
//                 color: Color(0xFF8795A9),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _AnalyticsChartCard extends StatelessWidget {
//   const _AnalyticsChartCard({
//     required this.campaigns,
//     required this.dateFilter,
//   });

//   final List<_CampaignRecord> campaigns;
//   final String dateFilter;

//   @override
//   Widget build(BuildContext context) {
//     final running = campaigns.where((c) => c.status == 'running').length;
//     final total = campaigns.length;

//     return Container(
//       height: 345,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: const Color(0xFFE3EAF3)),
//       ),
//       child: Padding(
//         padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
//         child: Column(
//           children: [
//             Row(
//               children: [
//                 const Expanded(
//                   child: _AnalyticsTabs(),
//                 ),
//                 _SmallDropDown(
//                   value: dateFilter,
//                   items: const [
//                     'Today',
//                     'Last 7 Days',
//                     'Last 30 Days',
//                     'This year',
//                   ],
//                 ),
//               ],
//             ),
//             const SizedBox(height: 8),
//             Expanded(
//               child: Row(
//                 children: [
//                   const SizedBox(
//                     width: 44,
//                     child: Column(
//                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                       children: [
//                         Text('100%', style: _axisStyle),
//                         Text('75%', style: _axisStyle),
//                         Text('50%', style: _axisStyle),
//                         Text('25%', style: _axisStyle),
//                         Text('0%', style: _axisStyle),
//                       ],
//                     ),
//                   ),
//                   Expanded(
//                     child: CustomPaint(
//                       painter: _LineChartPainter(
//                         seed: total + running * 3,
//                       ),
//                       child: const SizedBox.expand(),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 4),
//             const Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 _LegendDot(color: Color(0xFF4B9CF5), label: 'Campaign activity'),
//                 SizedBox(width: 20),
//                 _LegendDot(color: Color(0xFF55D6D1), label: 'Audience reach'),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   static const _axisStyle = TextStyle(
//     color: Color(0xFFA0ADBE),
//     fontSize: 9,
//   );
// }

// class _AnalyticsTabs extends StatelessWidget {
//   const _AnalyticsTabs();

//   @override
//   Widget build(BuildContext context) {
//     const tabs = [
//       'Impressions',
//       'Clicks',
//       'CTR',
//       'Views',
//       'Conversion',
//       'Total Spent',
//     ];

//     return Wrap(
//       spacing: 24,
//       runSpacing: 8,
//       children: [
//         for (int i = 0; i < tabs.length; i++)
//           Container(
//             padding: const EdgeInsets.only(bottom: 9),
//             decoration: BoxDecoration(
//               border: i == 0
//                   ? const Border(
//                       bottom: BorderSide(
//                         color: Color(0xFF4B9CF5),
//                         width: 2,
//                       ),
//                     )
//                   : null,
//             ),
//             child: Text(
//               tabs[i],
//               style: TextStyle(
//                 color: i == 0
//                     ? const Color(0xFF4B9CF5)
//                     : const Color(0xFF7C899C),
//                 fontSize: 11,
//                 fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
//               ),
//             ),
//           ),
//       ],
//     );
//   }
// }

// class _LineChartPainter extends CustomPainter {
//   _LineChartPainter({required this.seed});

//   final int seed;

//   @override
//   void paint(Canvas canvas, Size size) {
//     final gridPaint = Paint()
//       ..color = const Color(0xFFE8EDF4)
//       ..strokeWidth = 1;

//     final first = <double>[
//       .28,
//       .31,
//       .27,
//       .39,
//       .35,
//       .47,
//       .44,
//       .53,
//       .50,
//       .56,
//       .48,
//       .60,
//       .55,
//       .63,
//       .59,
//       .68,
//       .61,
//       .70,
//       .65,
//       .73,
//     ];

//     final second = <double>[
//       .20,
//       .35,
//       .42,
//       .37,
//       .45,
//       .32,
//       .29,
//       .38,
//       .34,
//       .28,
//       .24,
//       .30,
//       .27,
//       .40,
//       .37,
//       .49,
//       .44,
//       .36,
//       .31,
//       .26,
//     ];

//     final shift = (seed % 5) * .012;
//     final p1 = Paint()
//       ..color = const Color(0xFF4B9CF5)
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 2.6
//       ..strokeCap = StrokeCap.round
//       ..strokeJoin = StrokeJoin.round;

//     final p2 = Paint()
//       ..color = const Color(0xFF55D6D1)
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 2.2
//       ..strokeCap = StrokeCap.round
//       ..strokeJoin = StrokeJoin.round;

//     final fill1 = Paint()
//       ..color = const Color(0xFF4B9CF5).withOpacity(.10)
//       ..style = PaintingStyle.fill;

//     for (int i = 0; i < 5; i++) {
//       final y = size.height * i / 4;
//       canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
//     }

//     Path makePath(List<double> values) {
//       final path = Path();
//       for (int i = 0; i < values.length; i++) {
//         final x = size.width * i / (values.length - 1);
//         final y = size.height * (1 - (values[i] + shift).clamp(.04, .92));
//         if (i == 0) {
//           path.moveTo(x, y);
//         } else {
//           final previousX =
//               size.width * (i - 1) / (values.length - 1);
//           final previousY = size.height *
//               (1 -
//                   (values[i - 1] + shift).clamp(.04, .92));
//           final mid = (previousX + x) / 2;
//           path.cubicTo(mid, previousY, mid, y, x, y);
//         }
//       }
//       return path;
//     }

//     final path1 = makePath(first);
//     final fillPath = Path.from(path1)
//       ..lineTo(size.width, size.height)
//       ..lineTo(0, size.height)
//       ..close();

//     canvas.drawPath(fillPath, fill1);
//     canvas.drawPath(path1, p1);
//     canvas.drawPath(makePath(second), p2);
//   }

//   @override
//   bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
//       oldDelegate.seed != seed;
// }

// class _MetricRow extends StatelessWidget {
//   const _MetricRow({
//     required this.running,
//     required this.drafts,
//     required this.paused,
//     required this.ended,
//     required this.totalAudience,
//   });

//   final int running;
//   final int drafts;
//   final int paused;
//   final int ended;
//   final int totalAudience;

//   @override
//   Widget build(BuildContext context) {
//     final metrics = [
//       ('Running', '$running', 'Live campaigns', Icons.play_circle_outline_rounded),
//       ('Drafts', '$drafts', 'Waiting to launch', Icons.edit_note_rounded),
//       ('Paused', '$paused', 'Temporarily stopped', Icons.pause_circle_outline_rounded),
//       ('Ended', '$ended', 'Completed campaigns', Icons.check_circle_outline_rounded),
//       ('Audience', '$totalAudience', 'Audience groups', Icons.groups_outlined),
//     ];

//     return LayoutBuilder(
//       builder: (context, constraints) {
//         final columns = constraints.maxWidth >= 1100
//             ? 5
//             : constraints.maxWidth >= 700
//                 ? 3
//                 : 1;

//         return GridView.builder(
//           itemCount: metrics.length,
//           shrinkWrap: true,
//           physics: const NeverScrollableScrollPhysics(),
//           gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
//             crossAxisCount: columns,
//             crossAxisSpacing: 12,
//             mainAxisSpacing: 12,
//             mainAxisExtent: 90,
//           ),
//           itemBuilder: (context, index) {
//             final item = metrics[index];
//             return Container(
//               padding: const EdgeInsets.all(15),
//               decoration: BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.circular(12),
//                 border: Border.all(color: const Color(0xFFE3EAF3)),
//               ),
//               child: Row(
//                 children: [
//                   Container(
//                     width: 42,
//                     height: 42,
//                     decoration: BoxDecoration(
//                       color: const Color(0xFF4B9CF5).withOpacity(.10),
//                       borderRadius: BorderRadius.circular(11),
//                     ),
//                     child: Icon(
//                       item.$4,
//                       color: const Color(0xFF4B9CF5),
//                       size: 21,
//                     ),
//                   ),
//                   const SizedBox(width: 11),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: [
//                         Text(
//                           item.$1,
//                           style: const TextStyle(
//                             color: Color(0xFF7D8A9D),
//                             fontSize: 11,
//                             fontWeight: FontWeight.w700,
//                           ),
//                         ),
//                         const SizedBox(height: 3),
//                         Text(
//                           item.$2,
//                           style: const TextStyle(
//                             color: Color(0xFF18263D),
//                             fontSize: 20,
//                             fontWeight: FontWeight.w900,
//                           ),
//                         ),
//                         Text(
//                           item.$3,
//                           style: const TextStyle(
//                             color: Color(0xFF9AA6B6),
//                             fontSize: 9,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             );
//           },
//         );
//       },
//     );
//   }
// }

// class _DashboardLowerSection extends StatelessWidget {
//   const _DashboardLowerSection({
//     required this.campaigns,
//     required this.visible,
//     required this.statusFilter,
//     required this.deviceFilter,
//     required this.osFilter,
//     required this.formatFilter,
//     required this.onStatusChanged,
//     required this.onOsChanged,
//     required this.onFormatChanged,
//     required this.onCreate,
//     required this.onEdit,
//     required this.onRun,
//     required this.onPause,
//     required this.onEnd,
//     required this.onDelete,
//   });

//   final List<_CampaignRecord> campaigns;
//   final List<_CampaignRecord> visible;
//   final String statusFilter;
//   final String deviceFilter;
//   final String osFilter;
//   final String formatFilter;
//   final ValueChanged<String> onStatusChanged;
//   final ValueChanged<String> onOsChanged;
//   final ValueChanged<String> onFormatChanged;
//   final VoidCallback onCreate;
//   final ValueChanged<_CampaignRecord> onEdit;
//   final ValueChanged<_CampaignRecord> onRun;
//   final ValueChanged<_CampaignRecord> onPause;
//   final ValueChanged<_CampaignRecord> onEnd;
//   final ValueChanged<_CampaignRecord> onDelete;

//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         final wide = constraints.maxWidth >= 1050;

//         final right = Column(
//           children: [
//             _Panel(
//               title: 'Campaign type breakdown',
//               trailing: const _PanelSelect(label: 'All time'),
//               child: _TypeBreakdown(campaigns: campaigns),
//             ),
//             const SizedBox(height: 14),
//             _Panel(
//               title: 'Recent campaigns',
//               trailing: TextButton(
//                 onPressed: onCreate,
//                 child: const Text('Create new'),
//               ),
//               child: _RecentCampaignList(
//                 campaigns: campaigns.take(4).toList(),
//                 onEdit: onEdit,
//                 onRun: onRun,
//               ),
//             ),
//           ],
//         );

//         final left = Column(
//           children: [
//             _Panel(
//               title: 'Campaign performance',
//               trailing: const _PanelSelect(label: 'All campaigns'),
//               child: _CampaignPerformance(
//                 campaigns: campaigns,
//               ),
//             ),
//             const SizedBox(height: 14),
//             _Panel(
//               title: 'Operating devices',
//               trailing: const _PanelSelect(label: 'Last 7 Days'),
//               child: const _DeviceBreakdown(),
//             ),
//           ],
//         );

//         if (wide) {
//           return Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Expanded(child: left),
//               const SizedBox(width: 14),
//               SizedBox(width: 390, child: right),
//             ],
//           );
//         }

//         return Column(
//           children: [
//             left,
//             const SizedBox(height: 14),
//             right,
//             const SizedBox(height: 16),
//             _CampaignTable(
//               visible: visible,
//               statusFilter: statusFilter,
//               osFilter: osFilter,
//               formatFilter: formatFilter,
//               onStatusChanged: onStatusChanged,
//               onOsChanged: onOsChanged,
//               onFormatChanged: onFormatChanged,
//               onCreate: onCreate,
//               onEdit: onEdit,
//               onRun: onRun,
//               onPause: onPause,
//               onEnd: onEnd,
//               onDelete: onDelete,
//             ),
//           ],
//         );
//       },
//     );
//   }
// }

// class _Panel extends StatelessWidget {
//   const _Panel({
//     required this.title,
//     required this.trailing,
//     required this.child,
//   });

//   final String title;
//   final Widget trailing;
//   final Widget child;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: const Color(0xFFE3EAF3)),
//       ),
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Expanded(
//                   child: Text(
//                     title,
//                     style: const TextStyle(
//                       color: Color(0xFF43516A),
//                       fontSize: 14,
//                       fontWeight: FontWeight.w900,
//                     ),
//                   ),
//                 ),
//                 trailing,
//               ],
//             ),
//             const SizedBox(height: 15),
//             child,
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _CampaignPerformance extends StatelessWidget {
//   const _CampaignPerformance({required this.campaigns});

//   final List<_CampaignRecord> campaigns;

//   @override
//   Widget build(BuildContext context) {
//     if (campaigns.isEmpty) {
//       return const _MiniEmpty();
//     }

//     final rows = campaigns.take(5).toList();

//     return Column(
//       children: [
//         for (int i = 0; i < rows.length; i++) ...[
//           _PerformanceRow(
//             campaign: rows[i],
//             rank: i + 1,
//           ),
//           if (i != rows.length - 1)
//             const Divider(height: 20, color: Color(0xFFEAEFF5)),
//         ],
//       ],
//     );
//   }
// }

// class _PerformanceRow extends StatelessWidget {
//   const _PerformanceRow({
//     required this.campaign,
//     required this.rank,
//   });

//   final _CampaignRecord campaign;
//   final int rank;

//   @override
//   Widget build(BuildContext context) {
//     final progress = (0.25 + ((campaign.title.length * 7) % 70) / 100)
//         .clamp(.2, .95);

//     return Row(
//       children: [
//         SizedBox(
//           width: 25,
//           child: Text(
//             '$rank',
//             style: const TextStyle(
//               color: Color(0xFF9AA6B6),
//               fontWeight: FontWeight.w800,
//             ),
//           ),
//         ),
//         CircleAvatar(
//           radius: 17,
//           backgroundColor: const Color(0xFF4B9CF5).withOpacity(.10),
//           child: Icon(
//             _typeIcon(campaign.type),
//             size: 17,
//             color: const Color(0xFF4B9CF5),
//           ),
//         ),
//         const SizedBox(width: 10),
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 campaign.title,
//                 maxLines: 1,
//                 overflow: TextOverflow.ellipsis,
//                 style: const TextStyle(
//                   color: Color(0xFF33425B),
//                   fontSize: 12,
//                   fontWeight: FontWeight.w800,
//                 ),
//               ),
//               const SizedBox(height: 5),
//               ClipRRect(
//                 borderRadius: BorderRadius.circular(10),
//                 child: LinearProgressIndicator(
//                   minHeight: 5,
//                   value: progress,
//                   backgroundColor: const Color(0xFFEAF0F7),
//                   valueColor: const AlwaysStoppedAnimation(
//                     Color(0xFF4B9CF5),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(width: 14),
//         _Pill(
//           _statusLabel(campaign.status),
//           _statusColor(campaign.status),
//         ),
//       ],
//     );
//   }
// }

// class _TypeBreakdown extends StatelessWidget {
//   const _TypeBreakdown({required this.campaigns});

//   final List<_CampaignRecord> campaigns;

//   @override
//   Widget build(BuildContext context) {
//     final counts = <String, int>{};
//     for (final campaign in campaigns) {
//       counts[campaign.type] = (counts[campaign.type] ?? 0) + 1;
//     }

//     if (counts.isEmpty) return const _MiniEmpty();

//     final sorted = counts.entries.toList()
//       ..sort((a, b) => b.value.compareTo(a.value));

//     return Row(
//       children: [
//         SizedBox(
//           width: 120,
//           height: 120,
//           child: CustomPaint(
//             painter: _DonutPainter(values: sorted.map((e) => e.value).toList()),
//           ),
//         ),
//         const SizedBox(width: 20),
//         Expanded(
//           child: Column(
//             children: [
//               for (final entry in sorted.take(5))
//                 Padding(
//                   padding: const EdgeInsets.symmetric(vertical: 4),
//                   child: Row(
//                     children: [
//                       Container(
//                         width: 8,
//                         height: 8,
//                         decoration: BoxDecoration(
//                           color: _typeColor(entry.key),
//                           shape: BoxShape.circle,
//                         ),
//                       ),
//                       const SizedBox(width: 8),
//                       Expanded(
//                         child: Text(
//                           _typeLabel(entry.key),
//                           style: const TextStyle(
//                             color: Color(0xFF71809A),
//                             fontSize: 11,
//                             fontWeight: FontWeight.w600,
//                           ),
//                         ),
//                       ),
//                       Text(
//                         '${entry.value}',
//                         style: const TextStyle(
//                           color: Color(0xFF33425B),
//                           fontSize: 11,
//                           fontWeight: FontWeight.w900,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

// class _DonutPainter extends CustomPainter {
//   _DonutPainter({required this.values});

//   final List<int> values;

//   @override
//   void paint(Canvas canvas, Size size) {
//     final total = values.fold<int>(0, (a, b) => a + b);
//     if (total == 0) return;

//     final colors = const [
//       Color(0xFF4B9CF5),
//       Color(0xFF55D6D1),
//       Color(0xFF6675D9),
//       Color(0xFFFFC65C),
//       Color(0xFF8FA3BF),
//     ];

//     final rect = Offset.zero & size;
//     final paint = Paint()
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = 18
//       ..strokeCap = StrokeCap.butt;

//     double start = -math.pi / 2;

//     for (int i = 0; i < values.length; i++) {
//       final sweep = math.pi * 2 * values[i] / total;
//       paint.color = colors[i % colors.length];
//       canvas.drawArc(rect.deflate(12), start, sweep, false, paint);
//       start += sweep;
//     }

//     final center = Offset(size.width / 2, size.height / 2);
//     final textPainter = TextPainter(
//       text: TextSpan(
//         text: '$total',
//         style: const TextStyle(
//           color: Color(0xFF4A5870),
//           fontSize: 18,
//           fontWeight: FontWeight.w900,
//         ),
//       ),
//       textDirection: TextDirection.ltr,
//     )..layout();

//     textPainter.paint(
//       canvas,
//       center - Offset(textPainter.width / 2, textPainter.height / 2),
//     );
//   }

//   @override
//   bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
//       oldDelegate.values != values;
// }

// class _DeviceBreakdown extends StatelessWidget {
//   const _DeviceBreakdown();

//   @override
//   Widget build(BuildContext context) {
//     const values = [
//       ('Mobile', .62, Color(0xFF4B9CF5)),
//       ('Desktop', .27, Color(0xFF6675D9)),
//       ('Tablet', .11, Color(0xFF55D6D1)),
//     ];

//     return Column(
//       children: [
//         for (final item in values)
//           Padding(
//             padding: const EdgeInsets.symmetric(vertical: 7),
//             child: Row(
//               children: [
//                 SizedBox(
//                   width: 65,
//                   child: Text(
//                     item.$1,
//                     style: const TextStyle(
//                       color: Color(0xFF71809A),
//                       fontSize: 11,
//                       fontWeight: FontWeight.w700,
//                     ),
//                   ),
//                 ),
//                 Expanded(
//                   child: ClipRRect(
//                     borderRadius: BorderRadius.circular(9),
//                     child: LinearProgressIndicator(
//                       minHeight: 8,
//                       value: item.$2,
//                       backgroundColor: const Color(0xFFEAF0F7),
//                       valueColor: AlwaysStoppedAnimation(item.$3),
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 10),
//                 SizedBox(
//                   width: 38,
//                   child: Text(
//                     '${(item.$2 * 100).round()}%',
//                     textAlign: TextAlign.right,
//                     style: const TextStyle(
//                       color: Color(0xFF4B5870),
//                       fontSize: 10,
//                       fontWeight: FontWeight.w900,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//       ],
//     );
//   }
// }

// class _RecentCampaignList extends StatelessWidget {
//   const _RecentCampaignList({
//     required this.campaigns,
//     required this.onEdit,
//     required this.onRun,
//   });

//   final List<_CampaignRecord> campaigns;
//   final ValueChanged<_CampaignRecord> onEdit;
//   final ValueChanged<_CampaignRecord> onRun;

//   @override
//   Widget build(BuildContext context) {
//     if (campaigns.isEmpty) return const _MiniEmpty();

//     return Column(
//       children: [
//         for (final campaign in campaigns)
//           Padding(
//             padding: const EdgeInsets.symmetric(vertical: 7),
//             child: InkWell(
//               onTap: () => onEdit(campaign),
//               borderRadius: BorderRadius.circular(9),
//               child: Row(
//                 children: [
//                   CircleAvatar(
//                     radius: 17,
//                     backgroundColor: const Color(0xFF4B9CF5).withOpacity(.10),
//                     child: Icon(
//                       _typeIcon(campaign.type),
//                       size: 16,
//                       color: const Color(0xFF4B9CF5),
//                     ),
//                   ),
//                   const SizedBox(width: 9),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           campaign.title,
//                           maxLines: 1,
//                           overflow: TextOverflow.ellipsis,
//                           style: const TextStyle(
//                             color: Color(0xFF3D4A60),
//                             fontSize: 11,
//                             fontWeight: FontWeight.w800,
//                           ),
//                         ),
//                         const SizedBox(height: 3),
//                         Text(
//                           _typeLabel(campaign.type),
//                           style: const TextStyle(
//                             color: Color(0xFF98A4B5),
//                             fontSize: 9,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   if (campaign.status == 'draft')
//                     IconButton(
//                       tooltip: 'Run',
//                       onPressed: () => onRun(campaign),
//                       icon: const Icon(
//                         Icons.play_circle_outline_rounded,
//                         size: 20,
//                         color: Color(0xFF4B9CF5),
//                       ),
//                     )
//                   else
//                     _Pill(
//                       _statusLabel(campaign.status),
//                       _statusColor(campaign.status),
//                     ),
//                 ],
//               ),
//             ),
//           ),
//       ],
//     );
//   }
// }

// class _CampaignTable extends StatelessWidget {
//   const _CampaignTable({
//     required this.visible,
//     required this.statusFilter,
//     required this.osFilter,
//     required this.formatFilter,
//     required this.onStatusChanged,
//     required this.onOsChanged,
//     required this.onFormatChanged,
//     required this.onCreate,
//     required this.onEdit,
//     required this.onRun,
//     required this.onPause,
//     required this.onEnd,
//     required this.onDelete,
//   });

//   final List<_CampaignRecord> visible;
//   final String statusFilter;
//   final String osFilter;
//   final String formatFilter;
//   final ValueChanged<String> onStatusChanged;
//   final ValueChanged<String> onOsChanged;
//   final ValueChanged<String> onFormatChanged;
//   final VoidCallback onCreate;
//   final ValueChanged<_CampaignRecord> onEdit;
//   final ValueChanged<_CampaignRecord> onRun;
//   final ValueChanged<_CampaignRecord> onPause;
//   final ValueChanged<_CampaignRecord> onEnd;
//   final ValueChanged<_CampaignRecord> onDelete;

//   @override
//   Widget build(BuildContext context) {
//     return _Panel(
//       title: 'Campaigns',
//       trailing: Wrap(
//         spacing: 7,
//         children: [
//           _SmallSelect(
//             value: statusFilter == 'all' ? 'All campaigns' : _statusLabel(statusFilter),
//             items: const [
//               'All campaigns',
//               'Draft',
//               'Running',
//               'Paused',
//               'Ended',
//             ],
//             onChanged: (value) {
//               const map = {
//                 'All campaigns': 'all',
//                 'Draft': 'draft',
//                 'Running': 'running',
//                 'Paused': 'paused',
//                 'Ended': 'ended',
//               };
//               onStatusChanged(map[value] ?? 'all');
//             },
//           ),
//           _SmallSelect(
//             value: osFilter,
//             items: const ['All OS', 'Android', 'iOS', 'Windows', 'Linux'],
//             onChanged: onOsChanged,
//           ),
//           _SmallSelect(
//             value: formatFilter,
//             items: const ['All formats', 'Modal', 'Banner', 'Bottom card'],
//             onChanged: onFormatChanged,
//           ),
//         ],
//       ),
//       child: Column(
//         children: [
//           if (visible.isEmpty)
//             _MiniEmpty(onCreate: onCreate)
//           else
//             for (final campaign in visible)
//               _CampaignListRow(
//                 campaign: campaign,
//                 onEdit: () => onEdit(campaign),
//                 onRun: () => onRun(campaign),
//                 onPause: () => onPause(campaign),
//                 onEnd: () => onEnd(campaign),
//                 onDelete: () => onDelete(campaign),
//               ),
//         ],
//       ),
//     );
//   }
// }

// class _CampaignListRow extends StatelessWidget {
//   const _CampaignListRow({
//     required this.campaign,
//     required this.onEdit,
//     required this.onRun,
//     required this.onPause,
//     required this.onEnd,
//     required this.onDelete,
//   });

//   final _CampaignRecord campaign;
//   final VoidCallback onEdit;
//   final VoidCallback onRun;
//   final VoidCallback onPause;
//   final VoidCallback onEnd;
//   final VoidCallback onDelete;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(vertical: 12),
//       decoration: const BoxDecoration(
//         border: Border(
//           bottom: BorderSide(color: Color(0xFFEAEFF5)),
//         ),
//       ),
//       child: Row(
//         children: [
//           CircleAvatar(
//             radius: 20,
//             backgroundColor: const Color(0xFF4B9CF5).withOpacity(.10),
//             child: Icon(
//               _typeIcon(campaign.type),
//               color: const Color(0xFF4B9CF5),
//               size: 19,
//             ),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             flex: 3,
//             child: InkWell(
//               onTap: onEdit,
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     campaign.title,
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis,
//                     style: const TextStyle(
//                       color: Color(0xFF33425B),
//                       fontSize: 12,
//                       fontWeight: FontWeight.w900,
//                     ),
//                   ),
//                   const SizedBox(height: 3),
//                   Text(
//                     '${_typeLabel(campaign.type)} • ${_presentationLabel(campaign.presentation)}',
//                     style: const TextStyle(
//                       color: Color(0xFF98A4B5),
//                       fontSize: 9,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           _Pill(
//             _statusLabel(campaign.status),
//             _statusColor(campaign.status),
//           ),
//           const SizedBox(width: 8),
//           PopupMenuButton<String>(
//             onSelected: (value) {
//               switch (value) {
//                 case 'edit':
//                   onEdit();
//                   break;
//                 case 'run':
//                   onRun();
//                   break;
//                 case 'pause':
//                   onPause();
//                   break;
//                 case 'end':
//                   onEnd();
//                   break;
//                 case 'delete':
//                   onDelete();
//                   break;
//               }
//             },
//             itemBuilder: (_) => const [
//               PopupMenuItem(value: 'edit', child: Text('Edit')),
//               PopupMenuItem(value: 'run', child: Text('Run')),
//               PopupMenuItem(value: 'pause', child: Text('Pause')),
//               PopupMenuItem(value: 'end', child: Text('End')),
//               PopupMenuItem(value: 'delete', child: Text('Delete')),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _EditorDropDown extends StatelessWidget {
//   const _EditorDropDown({
//     required this.width,
//     required this.label,
//     required this.value,
//     required this.items,
//     required this.onChanged,
//   });

//   final double width;
//   final String label;
//   final String value;
//   final List<(String, String)> items;
//   final ValueChanged<String> onChanged;

//   @override
//   Widget build(BuildContext context) {
//     return SizedBox(
//       width: width == double.infinity ? null : width,
//       child: DropdownButtonFormField<String>(
//         value: value,
//         decoration: InputDecoration(
//           labelText: label,
//           border: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(10),
//           ),
//         ),
//         items: items
//             .map(
//               (item) => DropdownMenuItem(
//                 value: item.$1,
//                 child: Text(item.$2),
//               ),
//             )
//             .toList(),
//         onChanged: (value) {
//           if (value != null) onChanged(value);
//         },
//       ),
//     );
//   }
// }

// class _EditorTextField extends StatelessWidget {
//   const _EditorTextField({
//     required this.controller,
//     required this.label,
//     this.hint,
//     this.minLines,
//     this.maxLines = 1,
//     this.maxLength,
//   });

//   final TextEditingController controller;
//   final String label;
//   final String? hint;
//   final int? minLines;
//   final int maxLines;
//   final int? maxLength;

//   @override
//   Widget build(BuildContext context) {
//     return TextField(
//       controller: controller,
//       minLines: minLines,
//       maxLines: maxLines,
//       maxLength: maxLength,
//       decoration: InputDecoration(
//         labelText: label,
//         hintText: hint,
//         alignLabelWithHint: minLines != null,
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(10),
//         ),
//       ),
//     );
//   }
// }

// class _SmallDropDown extends StatelessWidget {
//   const _SmallDropDown({
//     required this.value,
//     required this.items,
//   });

//   final String value;
//   final List<String> items;

//   @override
//   Widget build(BuildContext context) {
//     return _SmallSelect(
//       value: value,
//       items: items,
//       onChanged: (_) {},
//     );
//   }
// }

// class _SmallSelect extends StatelessWidget {
//   const _SmallSelect({
//     required this.value,
//     required this.items,
//     required this.onChanged,
//   });

//   final String value;
//   final List<String> items;
//   final ValueChanged<String> onChanged;

//   @override
//   Widget build(BuildContext context) {
//     final safeValue = items.contains(value) ? value : items.first;

//     return Container(
//       constraints: const BoxConstraints(minWidth: 105),
//       padding: const EdgeInsets.symmetric(horizontal: 8),
//       decoration: BoxDecoration(
//         border: Border.all(color: const Color(0xFFDCE4EF)),
//         borderRadius: BorderRadius.circular(7),
//       ),
//       child: DropdownButtonHideUnderline(
//         child: DropdownButton<String>(
//           value: safeValue,
//           isDense: true,
//           icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
//           style: const TextStyle(
//             color: Color(0xFF637189),
//             fontSize: 10,
//             fontWeight: FontWeight.w700,
//           ),
//           items: items
//               .map(
//                 (item) => DropdownMenuItem(
//                   value: item,
//                   child: Text(item),
//                 ),
//               )
//               .toList(),
//           onChanged: (v) {
//             if (v != null) onChanged(v);
//           },
//         ),
//       ),
//     );
//   }
// }

// class _PanelSelect extends StatelessWidget {
//   const _PanelSelect({required this.label});

//   final String label;

//   @override
//   Widget build(BuildContext context) {
//     return _SmallSelect(
//       value: label,
//       items: [label],
//       onChanged: (_) {},
//     );
//   }
// }

// class _LegendDot extends StatelessWidget {
//   const _LegendDot({
//     required this.color,
//     required this.label,
//   });

//   final Color color;
//   final String label;

//   @override
//   Widget build(BuildContext context) {
//     return Row(
//       children: [
//         Container(
//           width: 8,
//           height: 8,
//           decoration: BoxDecoration(
//             color: color,
//             shape: BoxShape.circle,
//           ),
//         ),
//         const SizedBox(width: 5),
//         Text(
//           label,
//           style: const TextStyle(
//             color: Color(0xFF8B98AA),
//             fontSize: 9,
//             fontWeight: FontWeight.w700,
//           ),
//         ),
//       ],
//     );
//   }
// }

// class _Pill extends StatelessWidget {
//   const _Pill(this.label, this.color);

//   final String label;
//   final Color color;

//   @override
//   Widget build(BuildContext context) => Container(
//         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
//         decoration: BoxDecoration(
//           color: color.withOpacity(.09),
//           borderRadius: BorderRadius.circular(99),
//         ),
//         child: Text(
//           label,
//           style: TextStyle(
//             color: color,
//             fontSize: 9,
//             fontWeight: FontWeight.w800,
//           ),
//         ),
//       );
// }

// class _MiniEmpty extends StatelessWidget {
//   const _MiniEmpty({this.onCreate});

//   final VoidCallback? onCreate;

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.all(24),
//       child: Column(
//         children: [
//           const Icon(
//             Icons.campaign_outlined,
//             size: 38,
//             color: Color(0xFF8DA0BC),
//           ),
//           const SizedBox(height: 8),
//           const Text(
//             'No campaigns yet',
//             style: TextStyle(
//               color: Color(0xFF52627B),
//               fontWeight: FontWeight.w800,
//             ),
//           ),
//           if (onCreate != null) ...[
//             const SizedBox(height: 9),
//             FilledButton.icon(
//               onPressed: onCreate,
//               icon: const Icon(Icons.add_rounded, size: 17),
//               label: const Text('Create campaign'),
//             ),
//           ],
//         ],
//       ),
//     );
//   }
// }

// class _ErrorState extends StatelessWidget {
//   const _ErrorState({required this.message});

//   final String message;

//   @override
//   Widget build(BuildContext context) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(24),
//         child: Text(
//           message,
//           textAlign: TextAlign.center,
//           style: const TextStyle(color: Color(0xFFB42318)),
//         ),
//       ),
//     );
//   }
// }

// class _CampaignRecord {
//   const _CampaignRecord({
//     required this.id,
//     required this.type,
//     required this.presentation,
//     required this.title,
//     required this.body,
//     required this.ctaLabel,
//     required this.ctaUrl,
//     required this.audienceRoles,
//     required this.frequency,
//     required this.durationDays,
//     required this.status,
//     required this.updatedAt,
//   });

//   final String id;
//   final String type;
//   final String presentation;
//   final String title;
//   final String body;
//   final String ctaLabel;
//   final String ctaUrl;
//   final List<String> audienceRoles;
//   final String frequency;
//   final int durationDays;
//   final String status;
//   final DateTime updatedAt;

//   factory _CampaignRecord.fromDoc(
//     DocumentSnapshot<Map<String, dynamic>> doc,
//   ) {
//     final data = doc.data() ?? <String, dynamic>{};
//     final roles = (data['audienceRoles'] as List?)
//             ?.map((e) => e.toString())
//             .toList() ??
//         <String>[];

//     return _CampaignRecord(
//       id: doc.id,
//       type: data['type']?.toString() ?? 'promotion',
//       presentation: data['presentation']?.toString() ?? 'modal',
//       title: data['title']?.toString() ?? 'Untitled campaign',
//       body: data['body']?.toString() ?? '',
//       ctaLabel: data['ctaLabel']?.toString() ?? '',
//       ctaUrl: data['ctaUrl']?.toString() ?? '',
//       audienceRoles: roles,
//       frequency: data['frequency']?.toString() ?? 'once',
//       durationDays: (data['durationDays'] as num?)?.toInt() ?? 7,
//       status: data['status']?.toString() ?? 'draft',
//       updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ??
//           (data['createdAt'] as Timestamp?)?.toDate() ??
//           DateTime.fromMillisecondsSinceEpoch(0),
//     );
//   }
// }

// String _statusLabel(String value) => switch (value) {
//       'running' => 'Running',
//       'paused' => 'Paused',
//       'ended' => 'Ended',
//       _ => 'Draft',
//     };

// String _typeLabel(String value) => switch (value) {
//       'announcement' => 'Announcement',
//       'onboarding' => 'Onboarding',
//       'update' => 'Update',
//       'maintenance' => 'Maintenance',
//       'custom' => 'Custom',
//       _ => 'Promotion',
//     };

// String _presentationLabel(String value) => switch (value) {
//       'banner' => 'Banner',
//       'bottomCard' => 'Bottom card',
//       _ => 'Modal',
//     };

// IconData _typeIcon(String value) => switch (value) {
//       'announcement' => Icons.campaign_rounded,
//       'onboarding' => Icons.rocket_launch_rounded,
//       'update' => Icons.auto_awesome_rounded,
//       'maintenance' => Icons.construction_rounded,
//       'custom' => Icons.widgets_rounded,
//       _ => Icons.local_offer_rounded,
//     };

// Color _statusColor(String value) => switch (value) {
//       'running' => const Color(0xFF20A36A),
//       'paused' => const Color(0xFFD88A12),
//       'ended' => const Color(0xFF718096),
//       _ => const Color(0xFF5367D8),
//     };

// Color _typeColor(String value) => switch (value) {
//       'announcement' => const Color(0xFF55D6D1),
//       'onboarding' => const Color(0xFFFFC65C),
//       'update' => const Color(0xFF6675D9),
//       'maintenance' => const Color(0xFF8FA3BF),
//       'custom' => const Color(0xFF8B67D8),
//       _ => const Color(0xFF4B9CF5),
//     };
