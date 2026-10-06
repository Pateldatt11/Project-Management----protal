import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/company_request_model.dart';
import '../services/company_provisioning_service.dart';

class WizardStateProvider extends ChangeNotifier {
  int _currentStep = 0;
  int get currentStep => _currentStep;

  // Form Controllers
  final TextEditingController companyNameController = TextEditingController();
  final TextEditingController ownerNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  String selectedPlan = 'free';
  int employeeLimit = 10;
  int storageLimit = 5;

  bool enableProjects = true;
  bool enableTimeline = true;
  bool enableReports = false;
  bool enableNotifications = true;
  bool enableAppraisal = false;

  bool isLoading = false;
  String? errorMessage;

  // Pre-generated Auth UID tracked live
  String? _generatedUid;
  String? get generatedUid => _generatedUid;
  bool isGeneratingAuth = false;

  @override
  void dispose() {
    companyNameController.dispose();
    ownerNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  void jumpToStep(int step) {
    _currentStep = step;
    notifyListeners();
  }

  void nextStep() {
    if (_currentStep < 4) {
      _currentStep++;
      notifyListeners();
    }
  }

  void previousStep() {
    if (_currentStep > 0) {
      _currentStep--;
      notifyListeners();
    }
  }

  void setPlan(String plan) {
    selectedPlan = plan;
    if (plan == 'free') {
      employeeLimit = 10;
      storageLimit = 5;
    } else if (plan == 'pro') {
      employeeLimit = 50;
      storageLimit = 50;
    } else if (plan == 'enterprise') {
      employeeLimit = 500;
      storageLimit = 500;
    }
    notifyListeners();
  }

  void setEmployeeLimit(int limit) {
    employeeLimit = limit;
    notifyListeners();
  }

  void setStorageLimit(int limit) {
    storageLimit = limit;
    notifyListeners();
  }

  void toggleProjects(bool val) { enableProjects = val; notifyListeners(); }
  void toggleTimeline(bool val) { enableTimeline = val; notifyListeners(); }
  void toggleReports(bool val) { enableReports = val; notifyListeners(); }
  void toggleNotifications(bool val) { enableNotifications = val; notifyListeners(); }
  void toggleAppraisal(bool val) { enableAppraisal = val; notifyListeners(); }

  // 1. Pre-generate or resolve Firebase Auth user via secondary app (triggered by preview button)
  Future<bool> preCreateAuthUser(String adminPassword) async {
    final email = emailController.text.trim().toLowerCase();
    if (email.isEmpty || adminPassword.isEmpty) {
      errorMessage = "Email and password cannot be empty.";
      notifyListeners();
      return false;
    }

    isGeneratingAuth = true;
    errorMessage = null;
    notifyListeners();

    try {
      // Check if user already exists in Firestore 'user' collection
      final userQuery = await FirebaseFirestore.instance
          .collection('user')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        _generatedUid = userQuery.docs.first.id;
      } else {
        // Create in Firebase Auth using a secondary app instance so Super Admin stays logged in
        FirebaseApp secondaryApp = await Firebase.initializeApp(
          name: 'WizardAuthApp_${DateTime.now().millisecondsSinceEpoch}',
          options: Firebase.app().options,
        );
        
        FirebaseAuth secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
        UserCredential creds = await secondaryAuth.createUserWithEmailAndPassword(
          email: email,
          password: adminPassword,
        );
        _generatedUid = creds.user!.uid;

        await secondaryApp.delete();
      }

      isGeneratingAuth = false;
      notifyListeners();
      return true;
    } catch (e) {
      isGeneratingAuth = false;
      errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // 2. Execute final atomic provisioning using the pre-generated UID
  Future<bool> createCompany({required String platformAdminUid}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      if (_generatedUid == null) {
        throw Exception("Auth UID has not been generated yet. Please generate the UID in the preview panel before provisioning.");
      }

      final requestModel = CompanyRequestModel(
        companyName: companyNameController.text.trim(),
        ownerName: ownerNameController.text.trim(),
        email: emailController.text.trim().toLowerCase(),
        plan: selectedPlan,
        employeeLimit: employeeLimit,
        storageLimit: storageLimit,
        country: 'Global',
        uid: _generatedUid,
      );

      final provisioningService = CompanyProvisioningService();
      await provisioningService.provisionNewCompany(
        request: requestModel,
        adminPassword: passwordController.text,
        platformAdminUid: platformAdminUid,
        preGeneratedUid: _generatedUid!,
      );

      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      isLoading = false;
      errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
}