class CompanyRequestModel {
  final String companyName;
  final String ownerName;
  final String email;
  final String plan;
  final int employeeLimit;
  final int storageLimit;
  final String country;
  final String? uid; // Optional or required resolved Auth UID

  CompanyRequestModel({
    required this.companyName,
    required this.ownerName,
    required this.email,
    required this.plan,
    required this.employeeLimit,
    required this.storageLimit,
    required this.country,
    this.uid,
  });

  Map<String, dynamic> toJson() {
    return {
      'companyName': companyName,
      'ownerName': ownerName,
      'email': email,
      'plan': plan.toLowerCase(),
      'employeeLimit': employeeLimit,
      'storageLimit': storageLimit,
      'country': country,
      if (uid != null) 'uid': uid,
    };
  }
}