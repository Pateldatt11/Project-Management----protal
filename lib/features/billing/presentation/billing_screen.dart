import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../app/workspace_state.dart';
import '../../../core/config/razorpay_config.dart';
import '../../../core/services/razorpay_service.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  late final RazorpayService _razorpayService;

  @override
  void initState() {
    super.initState();
    _razorpayService = RazorpayService(
      onPaymentSuccess: _handlePaymentSuccess,
      onPaymentError: _handlePaymentError,
      onExternalWallet: _handleExternalWallet,
    );
  }

  @override
  void dispose() {
    _razorpayService.dispose();
    super.dispose();
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse paymentResponse) async {
    final state = ref.read(workspaceProvider);
    final company = state.company;

    try {
      // 1. Write the transaction record directly to Firestore (streams live to Super Admin Tab 6)
      await FirebaseFirestore.instance.collection('billing_records').doc(paymentResponse.paymentId).set({
        'paymentId': paymentResponse.paymentId ?? 'unknown_id',
        'orderId': paymentResponse.orderId ?? 'client_direct_test_order',
        'companyId': company.companyId,
        'amount': 999,
        'currency': 'INR',
        'status': 'SUCCEEDED',
        'createdAt': DateTime.now().toIso8601String(),
      });

      // 2. Reset company warning count and restore active subscription status in Firestore
      await FirebaseFirestore.instance.collection('companies').doc(company.companyId).set({
        'renewalWarningCount': 0,
        'subscriptionStatus': 'active',
        'currentPeriodEnd': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      // 3. Trigger local workspace state refresh
      ref.read(workspaceProvider.notifier).simulateSuccessfulRenewal();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment successful & recorded! ID: ${paymentResponse.paymentId}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to log billing record: $e');
    }
  }

  void _handlePaymentError(PaymentFailureResponse errorResponse) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${errorResponse.message ?? 'Unknown error'}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse walletResponse) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External wallet selected: ${walletResponse.walletName}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final company = state.company;
    final warningCount = company.renewalWarningCount;
    final isRestricted = company.isRestricted;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Subscription & Billing',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1E1E26),
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Manage your workspace license, renewal cycles, and billing security status.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // Warning / Restriction Status Banner
          if (warningCount > 0)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: isRestricted ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                border: Border.all(
                  color: isRestricted ? Colors.red : Colors.orange,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    isRestricted ? Icons.block_rounded : Icons.warning_amber_rounded,
                    color: isRestricted ? Colors.red : Colors.orange,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isRestricted
                              ? 'Workspace Restricted (Warning $warningCount / 5)'
                              : 'Renewal Warning ($warningCount / 5)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isRestricted ? Colors.red.shade800 : Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isRestricted
                              ? 'Your workspace has reached the maximum warning threshold. Complete payment immediately to restore full access.'
                              : 'Please renew your subscription to avoid automated workspace feature restrictions after 5 warnings.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isRestricted ? Colors.red.shade900 : Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Plan Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Enterprise Workspace Plan',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Chip(
                        label: Text(company.subscriptionStatus.toUpperCase()),
                        backgroundColor: company.subscriptionStatus == 'active'
                            ? Colors.green.withOpacity(0.2)
                            : Colors.orange.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: company.subscriptionStatus == 'active' ? Colors.green.shade800 : Colors.orange.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '₹999 / month • Billed monthly via Razorpay Checkout (${RazorpayConfig.displayName})',
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {
                      _razorpayService.openCheckout(
                        companyId: company.companyId,
                        companyName: company.name,
                        adminEmail: state.user.email,
                        adminPhone: '9876543210',
                        amountInINR: 999,
                      );
                    },
                    icon: const Icon(Icons.payment_rounded),
                    label: const Text('Renew Subscription Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF673AB7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Developer Test Controls for Dunning & Warning Automation
          const Text(
            'Developer Test Controls (Dunning Simulation)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref.read(workspaceProvider.notifier).simulateRenewalWarning();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Simulated Missed Payment (+1 Warning Added)')),
                    );
                  },
                  icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  label: Text('Simulate Warning ($warningCount/5)'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.orange),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ref.read(workspaceProvider.notifier).simulateSuccessfulRenewal();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Simulated Payment Success! Warnings Cleared.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Simulate Success'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}