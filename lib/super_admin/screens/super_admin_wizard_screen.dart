import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/wizard_state_provider.dart';

class SuperAdminWizardScreen extends StatelessWidget {
  const SuperAdminWizardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<WizardStateProvider>(context);

    // Calculate active modules count
    int activeModulesCount = [
      state.enableProjects,
      state.enableTimeline,
      state.enableReports,
      state.enableNotifications,
      state.enableAppraisal,
    ].where((element) => element).length;

    // Calculate estimated monthly cost based on selected plan tier
    double estimatedCost = 0.0;
    if (state.selectedPlan == 'pro') {
      estimatedCost = 49.0;
    } else if (state.selectedPlan == 'enterprise') {
      estimatedCost = 199.0;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Create New Company Profile"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: const Color(0xFFF5F6FA),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Side: Stepper Form
          Expanded(
            flex: 3,
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF673AB7),
                ),
              ),
              child: Stepper(
                type: StepperType.vertical,
                currentStep: state.currentStep,
                onStepTapped: (step) => state.jumpToStep(step),
                onStepContinue: () {
                  if (state.currentStep == 3) {
                    state.jumpToStep(4);
                  } else {
                    state.nextStep();
                  }
                },
                onStepCancel: state.currentStep > 0 ? state.previousStep : null,
                controlsBuilder: (context, details) {
                  if (state.currentStep == 4) return const SizedBox.shrink();
                  
                  return Padding(
                    padding: const EdgeInsets.only(top: 24.0),
                    child: Row(
                      children: [
                        ElevatedButton(
                          onPressed: details.onStepContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF673AB7),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Continue'),
                        ),
                        const SizedBox(width: 16),
                        if (state.currentStep > 0)
                          TextButton(
                            onPressed: details.onStepCancel,
                            child: const Text('Back', style: TextStyle(color: Colors.grey)),
                          ),
                      ],
                    ),
                  );
                },
                steps: [
                  _buildStep1(state),
                  _buildStep2(state),
                  _buildStep3(state),
                  _buildStep4(state),
                  _buildStep5(context, state),
                ],
              ),
            ),
          ),

          // Right Side: Comprehensive Live Profile Preview Card with Integrated UID Generation
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(24.0),
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF673AB7).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.preview_rounded, color: Color(0xFF673AB7), size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              "Live Profile Preview",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E1E26)),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.purple.shade200),
                          ),
                          child: Text("Step ${state.currentStep + 1} of 5", style: const TextStyle(color: Color(0xFF673AB7), fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: Color(0xFFEEEEEE)),
                    
                    // Section 1: Core Identification
                    const Text("COMPANY IDENTIFICATION", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    _buildPreviewRow("Workspace Name", state.companyNameController.text.isEmpty ? "Not specified" : state.companyNameController.text),
                    _buildPreviewRow("Primary Owner", state.ownerNameController.text.isEmpty ? "Not specified" : state.ownerNameController.text),
                    _buildPreviewRow("Admin Email", state.emailController.text.isEmpty ? "Not specified" : state.emailController.text),
                    _buildPreviewRow("Phone Number", state.phoneController.text.isEmpty ? "Not provided" : state.phoneController.text),
                    
                    const Divider(height: 24, color: Color(0xFFEEEEEE)),

                    // Section 2: Plan Details & Financial Estimates
                    const Text("PLAN DETAILS & FINANCIALS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    _buildPreviewRow("Subscription Tier", state.selectedPlan.toUpperCase()),
                    _buildPreviewRow("Estimated MRR", "\$${estimatedCost.toStringAsFixed(2)} / mo"),
                    _buildPreviewRow("Employee Capacity", "${state.employeeLimit} Seats"),
                    _buildPreviewRow("Cloud Storage Cap", "${state.storageLimit} GB"),

                    const Divider(height: 24, color: Color(0xFFEEEEEE)),

                    // Section 3: Security & UID Generator Action Panel
                    const Text("SECURITY & AUTHENTICATION", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    _buildPreviewRow("Password Status", state.passwordController.text.isNotEmpty ? "Configured & Secured" : "Pending Password"),
                    _buildPreviewRow("Confirmation", state.passwordController.text == state.confirmPasswordController.text && state.passwordController.text.isNotEmpty ? "Verified Match" : "Mismatch / Blank"),
                    
                    const SizedBox(height: 12),
                    
                    // Live Generate UID Button Box inside Preview Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Firebase Auth Identity", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E1E26))),
                          const SizedBox(height: 6),
                          Text(
                            state.generatedUid ?? "Not generated yet",
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: state.generatedUid != null ? const Color(0xFF673AB7) : Colors.grey.shade500,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF673AB7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                elevation: 0,
                              ),
                              icon: state.isGeneratingAuth 
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.bolt_rounded, size: 16),
                              label: Text(state.generatedUid != null ? "UID Generated & Synced" : "Generate UID Now"),
                              onPressed: state.isGeneratingAuth || state.passwordController.text.isEmpty || state.emailController.text.isEmpty
                                  ? null
                                  : () async {
                                      bool success = await state.preCreateAuthUser(state.passwordController.text);
                                      if (success && context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Auth user created and synced in Firestore successfully!"), backgroundColor: Colors.green),
                                        );
                                      } else if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text("Error: ${state.errorMessage ?? 'Failed to generate UID'}"), backgroundColor: Colors.red),
                                        );
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 24, color: Color(0xFFEEEEEE)),

                    // Section 4: Module Framework Audit
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("MODULE FRAMEWORK", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                        Text("$activeModulesCount / 5 Enabled", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF673AB7))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (state.enableProjects) _buildModuleChip("Projects"),
                        if (state.enableTimeline) _buildModuleChip("Timeline"),
                        if (state.enableReports) _buildModuleChip("Reports"),
                        if (state.enableNotifications) _buildModuleChip("Notifications"),
                        if (state.enableAppraisal) _buildModuleChip("Appraisal"),
                        if (activeModulesCount == 0)
                          const Text("No modules selected", style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Color(0xFF1E1E26), fontSize: 13, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF673AB7).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF673AB7).withOpacity(0.2)),
      ),
      child: Text(label, style: const TextStyle(color: Color(0xFF673AB7), fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Step _buildStep1(WizardStateProvider state) {
    return Step(
      title: const Text('Company Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      isActive: state.currentStep >= 0,
      state: state.currentStep > 0 ? StepState.complete : StepState.indexed,
      content: Column(
        children: [
          TextFormField(
            controller: state.companyNameController,
            onChanged: (_) => state.notifyListeners(),
            decoration: const InputDecoration(labelText: 'Target Workspace Name', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: state.ownerNameController,
            onChanged: (_) => state.notifyListeners(),
            decoration: const InputDecoration(labelText: 'Primary Owner Name', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: state.emailController,
            onChanged: (_) => state.notifyListeners(),
            decoration: const InputDecoration(labelText: 'Admin Email Address', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: state.phoneController,
            onChanged: (_) => state.notifyListeners(),
            decoration: const InputDecoration(labelText: 'Phone Number (Optional)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Step _buildStep2(WizardStateProvider state) {
    return Step(
      title: const Text('Subscription Plan & Constraints', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      isActive: state.currentStep >= 1,
      state: state.currentStep > 1 ? StepState.complete : StepState.indexed,
      content: Column(
        children: [
          DropdownButtonFormField<String>(
            value: state.selectedPlan,
            decoration: const InputDecoration(labelText: 'Subscription Tier', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
            items: const [
              DropdownMenuItem(value: 'free', child: Text('Free Allocation')),
              DropdownMenuItem(value: 'pro', child: Text('Pro Tier')),
              DropdownMenuItem(value: 'enterprise', child: Text('Enterprise Tier')),
            ],
            onChanged: (val) {
              if (val != null) state.setPlan(val);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: state.employeeLimit.toString(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Max Employee Limit', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
            onChanged: (val) {
              state.setEmployeeLimit(int.tryParse(val) ?? 10);
              state.notifyListeners();
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: state.storageLimit.toString(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Storage Limit (GB)', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
            onChanged: (val) {
              state.setStorageLimit(int.tryParse(val) ?? 5);
              state.notifyListeners();
            },
          ),
        ],
      ),
    );
  }

  Step _buildStep3(WizardStateProvider state) {
    return Step(
      title: const Text('Security & Authentication', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      isActive: state.currentStep >= 2,
      state: state.currentStep > 2 ? StepState.complete : StepState.indexed,
      content: Column(
        children: [
          TextFormField(
            controller: state.passwordController,
            onChanged: (_) => state.notifyListeners(),
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Initial Admin Password', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: state.confirmPasswordController,
            onChanged: (_) => state.notifyListeners(),
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm Password', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Step _buildStep4(WizardStateProvider state) {
    return Step(
      title: const Text('Initialize Modules Framework', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      isActive: state.currentStep >= 3,
      state: state.currentStep > 3 ? StepState.complete : StepState.indexed,
      content: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16.0),
              child: Text(
                "Toggle the core features to provision for this workspace:",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
            SwitchListTile(
              activeColor: const Color(0xFF673AB7),
              title: const Text('Projects Module'),
              value: state.enableProjects,
              onChanged: state.toggleProjects,
            ),
            const Divider(height: 1),
            SwitchListTile(
              activeColor: const Color(0xFF673AB7),
              title: const Text('Timeline Module'),
              value: state.enableTimeline,
              onChanged: state.toggleTimeline,
            ),
            const Divider(height: 1),
            SwitchListTile(
              activeColor: const Color(0xFF673AB7),
              title: const Text('Reports Module'),
              value: state.enableReports,
              onChanged: state.toggleReports,
            ),
            const Divider(height: 1),
            SwitchListTile(
              activeColor: const Color(0xFF673AB7),
              title: const Text('Notifications Module'),
              value: state.enableNotifications,
              onChanged: state.toggleNotifications,
            ),
            const Divider(height: 1),
            SwitchListTile(
              activeColor: const Color(0xFF673AB7),
              title: const Text('Appraisal Module'),
              value: state.enableAppraisal,
              onChanged: state.toggleAppraisal,
            ),
          ],
        ),
      ),
    );
  }

  Step _buildStep5(BuildContext context, WizardStateProvider state) {
    return Step(
      title: const Text('Review System Parameters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      isActive: state.currentStep >= 4,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text("Target Workspace: ${state.companyNameController.text}", style: const TextStyle(fontSize: 15, height: 1.8)),
          Text("Assigned Tier: ${state.selectedPlan.toUpperCase()}", style: const TextStyle(fontSize: 15, height: 1.8)),
          Text("Infrastructure Owner: [${state.emailController.text}]", style: const TextStyle(fontSize: 15, height: 1.8)),
          const SizedBox(height: 24),
          if (state.errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                border: Border.all(color: Colors.redAccent),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              SizedBox(
                height: 48,
                width: 140,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF673AB7),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: state.isLoading
                      ? null
                      : () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Error: No admin logged in.")),
                            );
                            return;
                          }

                          bool success = await state.createCompany(
                            platformAdminUid: user.uid,
                          );

                          if (success && context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Workspace Provisioned Successfully!")),
                            );
                          }
                        },
                  child: state.isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Provision"),
                ),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () => state.jumpToStep(3),
                child: const Text("Back", style: TextStyle(color: Colors.grey)),
              )
            ],
          ),
        ],
      ),
    );
  }
}