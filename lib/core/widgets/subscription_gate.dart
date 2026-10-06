import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/workspace_state.dart';
import '../../features/billing/presentation/billing_screen.dart';

class SubscriptionGate extends ConsumerWidget {
  const SubscriptionGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final company = state.company;

    // Check if the workspace is fully restricted (Reached 5 warnings)
    if (company.isRestricted) {
      return Scaffold(
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(32),
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.red.withOpacity(0.3), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.1),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_rounded,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 20),
                Text(
                  'Workspace Access Locked',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your subscription has reached the maximum renewal warning threshold (5 / 5 warnings missed). All workspace actions have been temporarily suspended until payment is verified.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, height: 1.4),
                ),
                const SizedBox(height: 28),
                // Directly embed the billing payment panel here so they can pay immediately
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Navigate or display billing screen modal
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Dialog(
                          child: BillingScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.payment_rounded),
                    label: const Text('Open Renewal & Billing Portal'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // If not restricted, render the normal app child
    return child;
  }
}