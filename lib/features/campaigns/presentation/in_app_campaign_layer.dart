import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/workspace_state.dart';
import '../../../core/constants/app_enums.dart';

class CompanyInAppCampaignLayer extends ConsumerStatefulWidget {
  const CompanyInAppCampaignLayer({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CompanyInAppCampaignLayer> createState() => _CompanyInAppCampaignLayerState();
}

class _CompanyInAppCampaignLayerState extends ConsumerState<CompanyInAppCampaignLayer> {
  final Set<String> _sessionSeen = <String>{};
  String? _lastCompanyId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final authUser = authSnapshot.data;
        if (authUser == null) return widget.child;

        final workspace = ref.watch(workspaceProvider);
        final companyId = workspace.company.companyId.trim();
        final member = workspace.currentMember;

        if (companyId.isEmpty || companyId == 'platform' || member.uid.trim().isEmpty) {
          return widget.child;
        }

        if (_lastCompanyId != companyId) {
          _lastCompanyId = companyId;
          _sessionSeen.clear();
        }

        final campaigns = FirebaseFirestore.instance
            .collection('companies')
            .doc(companyId)
            .collection('inAppCampaigns')
            .where('status', isEqualTo: 'running');

        final receipts = FirebaseFirestore.instance
            .collection('companies')
            .doc(companyId)
            .collection('members')
            .doc(member.uid)
            .collection('campaignReceipts');

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: campaigns.snapshots(),
          builder: (context, campaignSnapshot) {
            if (!campaignSnapshot.hasData || campaignSnapshot.hasError) return widget.child;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: receipts.snapshots(),
              builder: (context, receiptSnapshot) {
                final seenForever = receiptSnapshot.data?.docs.map((doc) => doc.id).toSet() ?? <String>{};
                final now = DateTime.now();
                final eligible = campaignSnapshot.data!.docs
                    .map(_LiveCampaign.fromDoc)
                    .where((campaign) => campaign.isActiveAt(now))
                    .where((campaign) => campaign.targetsRole(member.role.value))
                    .where((campaign) {
                      if (campaign.frequency == 'everySession') {
                        return !_sessionSeen.contains(campaign.id);
                      }
                      return !seenForever.contains(campaign.id);
                    })
                    .toList()
                  ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

                if (eligible.isEmpty) return widget.child;
                return _CampaignOverlay(
                  campaign: eligible.first,
                  child: widget.child,
                  onDismiss: () => _complete(eligible.first, clicked: false),
                  onAction: () => _complete(eligible.first, clicked: true),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _complete(_LiveCampaign campaign, {required bool clicked}) async {
    final workspace = ref.read(workspaceProvider);
    final companyId = workspace.company.companyId.trim();
    final uid = workspace.currentMember.uid.trim();

    setState(() => _sessionSeen.add(campaign.id));

    if (campaign.frequency != 'everySession' && companyId.isNotEmpty && uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('companies')
            .doc(companyId)
            .collection('members')
            .doc(uid)
            .collection('campaignReceipts')
            .doc(campaign.id)
            .set({
          'campaignId': campaign.id,
          'companyId': companyId,
          'userId': uid,
          'clicked': clicked,
          'seenAt': FieldValue.serverTimestamp(),
          if (clicked) 'clickedAt': FieldValue.serverTimestamp(),
          if (!clicked) 'dismissedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {
        // The in-memory session state still prevents repeated overlays if a receipt write fails.
      }
    }

    if (clicked && campaign.ctaUrl.trim().isNotEmpty) {
      final uri = Uri.tryParse(campaign.ctaUrl.trim());
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}

class _CampaignOverlay extends StatelessWidget {
  const _CampaignOverlay({
    required this.campaign,
    required this.child,
    required this.onDismiss,
    required this.onAction,
  });

  final _LiveCampaign campaign;
  final Widget child;
  final VoidCallback onDismiss;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    if (campaign.presentation == 'banner') {
      return Stack(
        children: [
          child,
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.paddingOf(context).top + 10,
            child: _CampaignCard(campaign: campaign, compact: true, onDismiss: onDismiss, onAction: onAction),
          ),
        ],
      );
    }

    if (campaign.presentation == 'bottomCard') {
      return Stack(
        children: [
          child,
          Positioned(
            left: 14,
            right: 14,
            bottom: MediaQuery.paddingOf(context).bottom + 18,
            child: _CampaignCard(campaign: campaign, compact: false, onDismiss: onDismiss, onAction: onAction),
          ),
        ],
      );
    }

    return Stack(
      children: [
        child,
        Positioned.fill(child: ColoredBox(color: Colors.black.withOpacity(.42))),
        Positioned.fill(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: _CampaignCard(campaign: campaign, compact: false, onDismiss: onDismiss, onAction: onAction),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.campaign,
    required this.compact,
    required this.onDismiss,
    required this.onAction,
  });

  final _LiveCampaign campaign;
  final bool compact;
  final VoidCallback onDismiss;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(campaign.type);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(compact ? 14 : 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(compact ? 18 : 24),
          border: Border.all(color: accent.withOpacity(.18)),
          boxShadow: const [BoxShadow(color: Color(0x280F172A), blurRadius: 30, offset: Offset(0, 14))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: compact ? 38 : 46,
                  height: compact ? 38 : 46,
                  decoration: BoxDecoration(color: accent.withOpacity(.10), borderRadius: BorderRadius.circular(14)),
                  child: Icon(_iconFor(campaign.type), color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(campaign.title, style: TextStyle(fontSize: compact ? 16 : 20, fontWeight: FontWeight.w900, color: const Color(0xFF172033))),
                      if (!compact) ...[
                        const SizedBox(height: 5),
                        Text(_labelFor(campaign.type), style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                IconButton(onPressed: onDismiss, tooltip: 'Dismiss', icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 10),
            Text(campaign.body, maxLines: compact ? 3 : 8, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF5F6B7E), height: 1.45)),
            if (campaign.ctaLabel.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(backgroundColor: accent, padding: const EdgeInsets.symmetric(vertical: 13)),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(campaign.ctaLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveCampaign {
  const _LiveCampaign({
    required this.id,
    required this.type,
    required this.presentation,
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.ctaUrl,
    required this.audienceRoles,
    required this.frequency,
    required this.startedAt,
    required this.endsAt,
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
  final DateTime startedAt;
  final DateTime? endsAt;

  factory _LiveCampaign.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return _LiveCampaign(
      id: doc.id,
      type: data['type']?.toString() ?? 'promotion',
      presentation: data['presentation']?.toString() ?? 'modal',
      title: data['title']?.toString() ?? 'Company update',
      body: data['body']?.toString() ?? '',
      ctaLabel: data['ctaLabel']?.toString() ?? '',
      ctaUrl: data['ctaUrl']?.toString() ?? '',
      audienceRoles: (data['audienceRoles'] as List?)?.map((e) => e.toString()).toList() ?? <String>[],
      frequency: data['frequency']?.toString() ?? 'once',
      startedAt: (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      endsAt: (data['endsAt'] as Timestamp?)?.toDate(),
    );
  }

  bool targetsRole(String role) => audienceRoles.isEmpty || audienceRoles.contains(role);

  bool isActiveAt(DateTime now) {
    if (startedAt.isAfter(now)) return false;
    return endsAt == null || endsAt!.isAfter(now);
  }
}

Color _accentFor(String type) => switch (type) {
      'announcement' => const Color(0xFF2563EB),
      'onboarding' => const Color(0xFF7C3AED),
      'update' => const Color(0xFF0F9F7F),
      'maintenance' => const Color(0xFFE07B24),
      'custom' => const Color(0xFF475569),
      _ => const Color(0xFFE54874),
    };

IconData _iconFor(String type) => switch (type) {
      'announcement' => Icons.campaign_rounded,
      'onboarding' => Icons.rocket_launch_rounded,
      'update' => Icons.auto_awesome_rounded,
      'maintenance' => Icons.construction_rounded,
      'custom' => Icons.widgets_rounded,
      _ => Icons.local_offer_rounded,
    };

String _labelFor(String type) => switch (type) {
      'announcement' => 'ANNOUNCEMENT',
      'onboarding' => 'ONBOARDING',
      'update' => 'UPDATE',
      'maintenance' => 'MAINTENANCE',
      'custom' => 'IN-APP MESSAGE',
      _ => 'PROMOTION',
    };
