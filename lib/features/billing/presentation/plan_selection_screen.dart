import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../app/workspace_state.dart';

class PlanSelectionScreen extends ConsumerStatefulWidget {
  const PlanSelectionScreen({super.key});

  @override
  ConsumerState<PlanSelectionScreen> createState() => _PlanSelectionScreenState();
}

class _PlanSelectionScreenState extends ConsumerState<PlanSelectionScreen> {
  bool _isSendingRequest = false;

  Future<void> _sendUpgradeRequestToAdmin(String planTitle, String price) async {
    final state = ref.read(workspaceProvider);
    final company = state.company;
    final currentMember = state.currentMember;

    setState(() => _isSendingRequest = true);

    try {
      await FirebaseFirestore.instance
          .collection('companies')
          .doc(company.companyId)
          .collection('notifications')
          .add({
        'notificationId': 'req_${DateTime.now().millisecondsSinceEpoch}',
        'title': 'Plan Upgrade Request',
        'message': 'Workspace admin ${currentMember.displayName} (${currentMember.email}) requested an upgrade to $planTitle ($price).',
        'type': 'securityAlert',
        'recipientRoleGroup': 'admins',
        'companyId': company.companyId,
        'actorId': currentMember.uid,
        'createdAt': DateTime.now().toIso8601String(),
        'isRead': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upgrade request for $planTitle sent successfully to the platform admin!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send upgrade request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingRequest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final company = state.company;

    // Stream live company document from Firestore to ensure real-time plan sync
    return Scaffold(
      appBar: AppBar(
        title: Text('Workspace Plans (${company.name})'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E1E26),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF4F6F9),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('companies').doc(company.companyId).snapshots(),
        builder: (context, snapshot) {
          String currentPlan = 'free';
          String subscriptionStatus = 'active';

          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data();
            if (data != null) {
              currentPlan = (data['plan'] ?? 'free').toString().toLowerCase();
              subscriptionStatus = (data['subscriptionStatus'] ?? 'active').toString().toLowerCase();
            }
          } else {
            // Fallback to local workspace state if stream is loading
            currentPlan = (company.plan ?? 'free').toLowerCase();
            subscriptionStatus = (company.subscriptionStatus ?? 'active').toLowerCase();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Choose Your Workspace Tier',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E1E26)),
                    ),
                    Row(
                      children: [
                        Chip(
                          label: Text('Active Plan: ${currentPlan.toUpperCase()}'),
                          backgroundColor: Colors.purple.shade50,
                          labelStyle: const TextStyle(color: Color(0xFF673AB7), fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text('Status: ${subscriptionStatus.toUpperCase()}'),
                          backgroundColor: subscriptionStatus == 'active' ? Colors.green.shade50 : Colors.red.shade50,
                          labelStyle: TextStyle(
                            color: subscriptionStatus == 'active' ? Colors.green.shade800 : Colors.red.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Review synchronized workspace tiers and request changes directly from your platform administrator.',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 28),

                LayoutBuilder(
                  builder: (context, constraints) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildPlanCard(
                            title: 'Free Allocation',
                            price: '₹0',
                            period: '/ month',
                            description: 'Standard allocation for small teams getting started.',
                            limits: ['Up to 10 Team Members', '5 GB Cloud Storage', 'Core Projects & Tasks'],
                            isCurrent: currentPlan == 'free',
                            color: const Color(0xFF673AB7),
                            onPressed: null,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _buildPlanCard(
                            title: 'Pro Tier',
                            price: '₹999',
                            period: '/ month',
                            description: 'Advanced features and modules for growing engineering teams.',
                            limits: ['Up to 50 Team Members', '50 GB Cloud Storage', 'All Modules (Timeline, Reports, Appraisal)'],
                            isCurrent: currentPlan == 'pro',
                            isPopular: true,
                            color: Colors.amber.shade700,
                            onPressed: _isSendingRequest ? null : () => _sendUpgradeRequestToAdmin('Pro Tier', '₹999/mo'),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _buildPlanCard(
                            title: 'Enterprise Tier',
                            price: '₹1,999',
                            period: '/ month',
                            description: 'Maximum security, compliance, and dedicated SLA support.',
                            limits: ['Unlimited Team Members', '500 GB Cloud Storage', 'Priority 24/7 Support & SLA'],
                            isCurrent: currentPlan == 'enterprise',
                            color: Colors.blue.shade700,
                            onPressed: _isSendingRequest ? null : () => _sendUpgradeRequestToAdmin('Enterprise Tier', '₹1,999/mo'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String price,
    required String period,
    required String description,
    required List<String> limits,
    required bool isCurrent,
    required Color color,
    bool isPopular = false,
    VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isPopular ? color : Colors.grey.shade200, width: isPopular ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Text('Most Popular', style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF1E1E26))),
              Text(period, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.8)),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1, color: Color(0xFFEEEEEE))),
          ...limits.map((limit) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: color),
                    const SizedBox(width: 10),
                    Expanded(child: Text(limit, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
                  ],
                ),
              )),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: isCurrent
                ? OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Current Active Plan', style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                : ElevatedButton(
                    onPressed: onPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Request Plan Upgrade', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
          ),
        ],
      ),
    );
  }
}