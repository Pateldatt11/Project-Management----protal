import 'dart:convert';

class CompanyAdminModel {
  final String uid;

  // Personal Information
  final String fullName;
  final String email;
  final String phone;
  final String photoUrl;

  // Company
  final String companyId;
  final String companyName;

  // Role
  final String role;

  // Status
  final bool isActive;
  final bool emailVerified;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;

  const CompanyAdminModel({
    required this.uid,
    required this.fullName,
    required this.email,
    this.phone = '',
    this.photoUrl = '',
    required this.companyId,
    required this.companyName,
    this.role = 'companyAdmin',
    this.isActive = true,
    this.emailVerified = false,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
  });

  CompanyAdminModel copyWith({
    String? uid,
    String? fullName,
    String? email,
    String? phone,
    String? photoUrl,
    String? companyId,
    String? companyName,
    String? role,
    bool? isActive,
    bool? emailVerified,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
  }) {
    return CompanyAdminModel(
      uid: uid ?? this.uid,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      emailVerified: emailVerified ?? this.emailVerified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'photoUrl': photoUrl,
      'companyId': companyId,
      'companyName': companyName,
      'role': role,
      'isActive': isActive,
      'emailVerified': emailVerified,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
    };
  }

  factory CompanyAdminModel.fromMap(Map<String, dynamic> map) {
    return CompanyAdminModel(
      uid: map['uid'] ?? '',
      fullName: map['fullName'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
      companyId: map['companyId'] ?? '',
      companyName: map['companyName'] ?? '',
      role: map['role'] ?? 'companyAdmin',
      isActive: map['isActive'] ?? true,
      emailVerified: map['emailVerified'] ?? false,
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
      lastLoginAt: map['lastLoginAt'] != null
          ? DateTime.tryParse(map['lastLoginAt'])
          : null,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory CompanyAdminModel.fromJson(String source) =>
      CompanyAdminModel.fromMap(jsonDecode(source));

  @override
  String toString() {
    return 'CompanyAdminModel(uid: $uid, company: $companyName)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanyAdminModel &&
          runtimeType == other.runtimeType &&
          uid == other.uid;

  @override
  int get hashCode => uid.hashCode;
}