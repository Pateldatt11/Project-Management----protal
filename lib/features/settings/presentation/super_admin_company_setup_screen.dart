import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_theme.dart';
import '../../../app/workspace_state.dart';
import '../../../core/widgets/status_badge.dart';

class SuperAdminCompanySetupScreen extends ConsumerStatefulWidget {
  const SuperAdminCompanySetupScreen({super.key});

  @override
  ConsumerState<SuperAdminCompanySetupScreen> createState() => _SuperAdminCompanySetupScreenState();
}

class _SuperAdminCompanySetupScreenState extends ConsumerState<SuperAdminCompanySetupScreen> {
  final _companyName = TextEditingController();
  final _ownerName = TextEditingController();
  final _legalName = TextEditingController();
  final _industry = TextEditingController(text: 'Software');
  final _timezone = TextEditingController(text: 'Asia/Kolkata');
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _stateName = TextEditingController();
  final _country = TextEditingController(text: 'India');

  @override
  void initState() {
    super.initState();
    final state = ref.read(workspaceProvider);
    _email.text = state.user.email;
    if (state.user.displayName.isNotEmpty && state.user.displayName != 'Not signed in') {
      _ownerName.text = state.user.displayName;
    }
  }

  @override
  void dispose() {
    _companyName.dispose();
    _ownerName.dispose();
    _legalName.dispose();
    _industry.dispose();
    _timezone.dispose();
    _email.dispose();
    _phone.dispose();
    _website.dispose();
    _address.dispose();
    _city.dispose();
    _stateName.dispose();
    _country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final user = state.user;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: const BorderSide(color: AppTheme.border)),
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            height: 56,
                            width: 56,
                            decoration: BoxDecoration(color: AppTheme.blue.withOpacity(.10), borderRadius: BorderRadius.circular(18)),
                            child: const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.blue, size: 30),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Company setup required', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Text('Signed in as ${user.email}. Fill this once and the app will create all required Firestore company documents automatically.', style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          const StatusBadge(label: 'Super Admin', color: AppTheme.danger),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => FirebaseAuth.instance.signOut(),
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Sign out'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(.08),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.orange.withOpacity(.18)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.orange),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No company workspace is configured yet. After you submit this form, the app creates companies/company_001, the Super Admin member, user membership, bootstrap settings, portal post settings, and demo-data settings.',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (state.lastError != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withOpacity(.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.danger.withOpacity(.20)),
                          ),
                          child: Text(state.lastError!, style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w800)),
                        ),
                      ],
                      const SizedBox(height: 22),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final twoCols = constraints.maxWidth >= 760;
                          final fields = <Widget>[
                            TextField(controller: _companyName, decoration: const InputDecoration(labelText: 'Company name *', prefixIcon: Icon(Icons.business_rounded))),
                            TextField(controller: _ownerName, decoration: const InputDecoration(labelText: 'Owner / Admin Name *', prefixIcon: Icon(Icons.person_rounded))),
                            TextField(controller: _legalName, decoration: const InputDecoration(labelText: 'Legal company name', prefixIcon: Icon(Icons.verified_rounded))),
                            TextField(controller: _industry, decoration: const InputDecoration(labelText: 'Industry', prefixIcon: Icon(Icons.category_rounded))),
                            TextField(controller: _timezone, decoration: const InputDecoration(labelText: 'Timezone', prefixIcon: Icon(Icons.public_rounded))),
                            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Company email', prefixIcon: Icon(Icons.email_rounded))),
                            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Company phone', prefixIcon: Icon(Icons.phone_rounded))),
                            TextField(controller: _website, decoration: const InputDecoration(labelText: 'Website', prefixIcon: Icon(Icons.language_rounded))),
                            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.location_on_rounded))),
                            TextField(controller: _city, decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city_rounded))),
                            TextField(controller: _stateName, decoration: const InputDecoration(labelText: 'State', prefixIcon: Icon(Icons.map_rounded))),
                            TextField(controller: _country, decoration: const InputDecoration(labelText: 'Country', prefixIcon: Icon(Icons.flag_rounded))),
                          ];
                          if (!twoCols) {
                            return Column(children: fields.map((field) => Padding(padding: const EdgeInsets.only(bottom: 12), child: field)).toList());
                          }
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: fields.map((field) => SizedBox(width: (constraints.maxWidth - 12) / 2, child: field)).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Only the manually-created users/${user.uid} document with role superAdmin can submit this setup.',
                              style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: state.isSaving
                                ? null
                                : () => ref.read(workspaceProvider.notifier).completeCompanySetupFromSuperAdmin(
                                      companyName: _companyName.text,
                                      legalName: _legalName.text,
                                      industry: _industry.text,
                                      timezone: _timezone.text,
                                      email: _email.text,
                                      phone: _phone.text,
                                      website: _website.text,
                                      address: _address.text,
                                      city: _city.text,
                                      stateName: _stateName.text,
                                      country: _country.text,
                                      ownerName: _ownerName.text,
                                    ),
                            icon: state.isSaving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_done_rounded),
                            label: const Text('Create company workspace'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}