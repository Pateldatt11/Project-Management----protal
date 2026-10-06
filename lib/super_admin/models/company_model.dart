import 'dart:convert';

class CompanyModel {
  final String id;

  // Company Information
  final String companyName;
  final String legalCompanyName;
  final String industry;
  final String companySize;
  final String description;

  // Contact
  final String email;
  final String phone;
  final String website;

  // Address
  final String address;
  final String city;
  final String state;
  final String country;
  final String postalCode;

  // Company Admin
  final String adminUid;
  final String adminName;
  final String adminEmail;

  // Subscription
  final String planId;
  final int employeeLimit;
  final int storageLimit;
  final int projectLimit;

  // Status
  final bool isActive;
  final bool isSuspended;

  // Platform Metadata
  final DateTime createdAt;
  final DateTime updatedAt;

  const CompanyModel({
    required this.id,

    required this.companyName,
    this.legalCompanyName = '',
    this.industry = '',
    this.companySize = '',
    this.description = '',

    required this.email,
    this.phone = '',
    this.website = '',

    this.address = '',
    this.city = '',
    this.state = '',
    required this.country,
    this.postalCode = '',

    required this.adminUid,
    required this.adminName,
    required this.adminEmail,

    required this.planId,
    required this.employeeLimit,
    required this.storageLimit,
    this.projectLimit = 100,

    this.isActive = true,
    this.isSuspended = false,

    required this.createdAt,
    required this.updatedAt,
  });

  CompanyModel copyWith({
    String? id,
    String? companyName,
    String? legalCompanyName,
    String? industry,
    String? companySize,
    String? description,
    String? email,
    String? phone,
    String? website,
    String? address,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? adminUid,
    String? adminName,
    String? adminEmail,
    String? planId,
    int? employeeLimit,
    int? storageLimit,
    int? projectLimit,
    bool? isActive,
    bool? isSuspended,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CompanyModel(
      id: id ?? this.id,
      companyName: companyName ?? this.companyName,
      legalCompanyName: legalCompanyName ?? this.legalCompanyName,
      industry: industry ?? this.industry,
      companySize: companySize ?? this.companySize,
      description: description ?? this.description,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      website: website ?? this.website,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      postalCode: postalCode ?? this.postalCode,
      adminUid: adminUid ?? this.adminUid,
      adminName: adminName ?? this.adminName,
      adminEmail: adminEmail ?? this.adminEmail,
      planId: planId ?? this.planId,
      employeeLimit: employeeLimit ?? this.employeeLimit,
      storageLimit: storageLimit ?? this.storageLimit,
      projectLimit: projectLimit ?? this.projectLimit,
      isActive: isActive ?? this.isActive,
      isSuspended: isSuspended ?? this.isSuspended,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,

      'companyName': companyName,
      'legalCompanyName': legalCompanyName,
      'industry': industry,
      'companySize': companySize,
      'description': description,

      'email': email,
      'phone': phone,
      'website': website,

      'address': address,
      'city': city,
      'state': state,
      'country': country,
      'postalCode': postalCode,

      'adminUid': adminUid,
      'adminName': adminName,
      'adminEmail': adminEmail,

      'planId': planId,
      'employeeLimit': employeeLimit,
      'storageLimit': storageLimit,
      'projectLimit': projectLimit,

      'isActive': isActive,
      'isSuspended': isSuspended,

      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory CompanyModel.fromMap(Map<String, dynamic> map) {
    return CompanyModel(
      id: map['id'] ?? '',

      companyName: map['companyName'] ?? '',
      legalCompanyName: map['legalCompanyName'] ?? '',
      industry: map['industry'] ?? '',
      companySize: map['companySize'] ?? '',
      description: map['description'] ?? '',

      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      website: map['website'] ?? '',

      address: map['address'] ?? '',
      city: map['city'] ?? '',
      state: map['state'] ?? '',
      country: map['country'] ?? '',
      postalCode: map['postalCode'] ?? '',

      adminUid: map['adminUid'] ?? '',
      adminName: map['adminName'] ?? '',
      adminEmail: map['adminEmail'] ?? '',

      planId: map['planId'] ?? '',
      employeeLimit: map['employeeLimit'] ?? 0,
      storageLimit: map['storageLimit'] ?? 0,
      projectLimit: map['projectLimit'] ?? 100,

      isActive: map['isActive'] ?? true,
      isSuspended: map['isSuspended'] ?? false,

      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory CompanyModel.fromJson(String source) =>
      CompanyModel.fromMap(jsonDecode(source));

  @override
  String toString() {
    return 'CompanyModel(id: $id, companyName: $companyName, planId: $planId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CompanyModel &&
            other.id == id &&
            other.companyName == companyName;
  }

  @override
  int get hashCode => Object.hash(id, companyName);
}