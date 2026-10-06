import '../../core/constants/app_enums.dart';
import '../../core/utils/json_value.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.defaultCompanyId,
    this.photoUrl,
    this.phone,
    this.status = 'active',
    this.notificationPreferences = const <String, dynamic>{},
  });

  final String uid;
  final String displayName;
  final String email;
  final UserRole role;
  final String defaultCompanyId;
  final String? photoUrl;
  final String? phone;
  final String status;
  final Map<String, dynamic> notificationPreferences;

  AppUser copyWith({
    String? uid,
    String? displayName,
    String? email,
    UserRole? role,
    String? defaultCompanyId,
    String? photoUrl,
    String? phone,
    String? status,
    Map<String, dynamic>? notificationPreferences,
  }) =>
      AppUser(
        uid: uid ?? this.uid,
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        role: role ?? this.role,
        defaultCompanyId: defaultCompanyId ?? this.defaultCompanyId,
        photoUrl: photoUrl ?? this.photoUrl,
        phone: phone ?? this.phone,
        status: status ?? this.status,
        notificationPreferences: notificationPreferences ?? this.notificationPreferences,
      );

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        uid: JsonValue.string(json['uid'] ?? json['id']),
        displayName: JsonValue.string(json['displayName'] ?? json['name'], fallback: 'Employee'),
        email: JsonValue.string(json['email']),
        role: UserRoleX.fromValue(JsonValue.string(json['role'], fallback: UserRole.employee.value)),
        defaultCompanyId: JsonValue.string(json['defaultCompanyId'], fallback: ''),
        photoUrl: JsonValue.optionalString(json['photoUrl'] ?? json['photoURL']),
        phone: JsonValue.optionalString(json['phone'] ?? json['phoneNumber']),
        status: JsonValue.string(json['status'], fallback: 'active'),
        notificationPreferences: JsonValue.map(json['notificationPreferences'] ?? json['notificationSettings']) ?? const <String, dynamic>{},
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'email': email,
        'role': role.value,
        'defaultCompanyId': defaultCompanyId,
        'photoUrl': photoUrl,
        'phone': phone,
        'status': status,
        'notificationPreferences': notificationPreferences,
      };
}
