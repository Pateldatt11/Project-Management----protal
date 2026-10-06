import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/workspace_state.dart';
import '../../core/constants/app_enums.dart';
import '../../features/settings/presentation/mobile_ui_control_screen.dart';
import '../../features/settings/presentation/mobile_ui_designer_screen.dart';

/// Platform-only host for the employee APK emulator / SDUI designer.
///
/// A Platform Super Admin can choose a tenant workspace for preview data.
/// Mobile UI publishing is platform-global: one Release publish is consumed by
/// every customer app through the shared platformUiConfigs documents.
class PlatformApkEmulatorScreen extends ConsumerStatefulWidget {
  const PlatformApkEmulatorScreen({super.key});

  @override
  ConsumerState<PlatformApkEmulatorScreen> createState() => _PlatformApkEmulatorScreenState();
}

class _PlatformApkEmulatorScreenState extends ConsumerState<PlatformApkEmulatorScreen> {
  String? _selectedCompanyId;
  String? _connectingCompanyId;
  String? _error;

  Future<void> _connectToCompany(String companyId) async {
    final cleanId = companyId.trim();
    if (cleanId.isEmpty || _connectingCompanyId == cleanId) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Your Platform Super Admin session has expired. Sign in again.');
      return;
    }

    setState(() {
      _selectedCompanyId = cleanId;
      _connectingCompanyId = cleanId;
      _error = null;
    });

    try {
      await ref.read(workspaceProvider.notifier).connectFirebaseUser(
            uid: user.uid,
            email: user.email ?? '',
            displayName: user.displayName,
            companyIdOverride: cleanId,
          );

      final state = ref.read(workspaceProvider);
      if (state.currentMember.role != UserRole.superAdmin) {
        throw StateError('Platform Super Admin role is required for APK Emulator access.');
      }
      if (state.company.companyId != cleanId) {
        throw StateError('Could not switch the emulator to the selected workspace.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _connectingCompanyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('companies').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Unable to load workspaces: ${snapshot.error}'));
        }

        final companies = snapshot.data?.docs.toList() ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        companies.sort((a, b) {
          final an = (a.data()['name'] ?? a.id).toString().toLowerCase();
          final bn = (b.data()['name'] ?? b.id).toString().toLowerCase();
          return an.compareTo(bn);
        });

        if (companies.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text('No company workspace exists yet. Create a workspace before opening the APK Emulator.'),
            ),
          );
        }

        final companyIds = companies.map((doc) => doc.id).toSet();
        var targetId = _selectedCompanyId;
        if (targetId == null || !companyIds.contains(targetId)) {
          final loadedId = workspace.company.companyId;
          targetId = companyIds.contains(loadedId) ? loadedId : companies.first.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedCompanyId != targetId) {
              _connectToCompany(targetId!);
            }
          });
        }

        final isConnected = workspace.company.companyId == targetId &&
            workspace.currentMember.role == UserRole.superAdmin &&
            _connectingCompanyId == null;

        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Wrap(
                spacing: 18,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone_android_rounded, color: Color(0xFF673AB7)),
                      SizedBox(width: 10),
                      Text(
                        'Platform APK Emulator • Global Mobile UI',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E1E26)),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 360,
                    child: DropdownButtonFormField<String>(
                      value: targetId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Workspace data to preview (publishing is global)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: companies.map((doc) {
                        final data = doc.data();
                        final name = (data['name'] ?? data['companyName'] ?? doc.id).toString();
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text('$name  •  ${doc.id}', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: _connectingCompanyId == null
                          ? (value) {
                              if (value != null) _connectToCompany(value);
                            }
                          : null,
                    ),
                  ),
                  if (_connectingCompanyId != null)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Loading workspace APK configuration…'),
                      ],
                    )
                  else if (isConnected) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.green.withOpacity(.2)),
                      ),
                      child: const Text(
                        'SUPER ADMIN • GLOBAL PUBLISH',
                        style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w900),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const MobileUiControlScreen()),
                      ),
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Global Quick Control'),
                    ),
                  ],
                ],
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(.18)),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
              ),
            Expanded(
              child: isConnected
                  ? const MobileUiDesignerScreen()
                  : const Center(child: CircularProgressIndicator()),
            ),
          ],
        );
      },
    );
  }
}
