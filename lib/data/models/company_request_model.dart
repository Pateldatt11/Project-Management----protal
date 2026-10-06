import 'dart:convert';

class CompanyRequestModel {
  // Step 1: Company Information
  final String companyName;
  final String country;

  // Step 2: Plan & Limits
  final String plan; // 'Free', 'Pro', 'Enterprise'
  final int employeeLimit;
  final int storageLimit; // In GB

  // Step 3: Admin Account
  final String ownerName;
  final String email;
  final String? phone;

  // Step 4: Enabled Modules (SDUI Feature Toggles)
  final bool enableProjects;
  final bool enableTimeline;
  final bool enableAppraisal;
  final bool enableReports;
  final bool enableNotifications;

  CompanyRequestModel({
    required this.companyName,
    required this.country,
    required this.plan,
    required this.employeeLimit,
    required this.storageLimit,
    required this.ownerName,
    required this.email,
    this.phone,
    this.enableProjects = true,
    this.enableTimeline = true,
    this.enableAppraisal = false,
    this.enableReports = true,
    this.enableNotifications = true,
  });

  /// Converts the Dart object state into a Map matching the Backend API contract.
  Map<String, dynamic> toMap() {
    return {
      'companyName': companyName,
      'country': country,
      'plan': plan,
      'employeeLimit': employeeLimit,
      'storageLimit': storageLimit,
      'ownerName': ownerName,
      'email': email,
      'phone': phone ?? '',
      'modules': {
        'projects': enableProjects,
        'timeline': enableTimeline,
        'appraisal': enableAppraisal,
        'reports': enableReports,
        'notifications': enableNotifications,
      }
    };
  }

  /// Serialization method to produce the final string payload for the HTTP POST request.
  String toJson() => json.encode(toMap());
}