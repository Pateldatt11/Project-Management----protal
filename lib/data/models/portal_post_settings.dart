import '../../core/constants/app_enums.dart';
import '../../core/utils/json_value.dart';

/// Company-level configuration that controls which portal posts/roles are active.
///
/// Store this in Firestore at:
/// companies/{companyId}/settings/portalPosts
class PortalPostSettings {
  const PortalPostSettings({
    required this.enabledRoleValues,
    this.updatedBy,
    this.updatedAt,
  });

  final List<String> enabledRoleValues;
  final String? updatedBy;
  final DateTime? updatedAt;

  static List<String> defaultEnabledRoleValues() => UserRole.values.map((role) => role.value).toList();

  Set<UserRole> get enabledRoles => enabledRoleValues.map(UserRoleX.fromValue).toSet();

  bool isRoleEnabled(UserRole role) => role.isCorePortalPost || enabledRoleValues.contains(role.value);

  PortalPostSettings copyWith({
    List<String>? enabledRoleValues,
    String? updatedBy,
    DateTime? updatedAt,
  }) =>
      PortalPostSettings(
        enabledRoleValues: enabledRoleValues ?? this.enabledRoleValues,
        updatedBy: updatedBy ?? this.updatedBy,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory PortalPostSettings.fromJson(Map<String, dynamic> json) {
    final values = JsonValue.stringList(json['enabledRoleValues']).isEmpty ? defaultEnabledRoleValues() : JsonValue.stringList(json['enabledRoleValues']);
    final safeValues = {
      ...UserRole.values.where((role) => role.isCorePortalPost).map((role) => role.value),
      ...values,
    }.toList();
    return PortalPostSettings(
      enabledRoleValues: safeValues,
      updatedBy: JsonValue.optionalString(json['updatedBy']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabledRoleValues': enabledRoleValues,
        'updatedBy': updatedBy,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      return value.toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}
