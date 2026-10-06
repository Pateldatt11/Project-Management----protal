import '../../core/utils/date_utils.dart';
import '../../core/utils/json_value.dart';

class AuditLog {
  const AuditLog({
    required this.auditLogId,
    required this.action,
    required this.actorId,
    required this.targetType,
    required this.targetId,
    required this.createdAt,
    this.before,
    this.after,
    this.platform = 'flutter',
  });

  final String auditLogId;
  final String action;
  final String actorId;
  final String targetType;
  final String targetId;
  final DateTime createdAt;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final String platform;

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
        auditLogId: JsonValue.string(json['auditLogId'] ?? json['id']),
        action: JsonValue.string(json['action'], fallback: 'unknown'),
        actorId: JsonValue.string(json['actorId']),
        targetType: JsonValue.string(json['targetType']),
        targetId: JsonValue.string(json['targetId']),
        createdAt: DateText.parse(json['createdAt']) ?? DateTime.now(),
        before: JsonValue.map(json['before']),
        after: JsonValue.map(json['after']),
        platform: JsonValue.string(json['platform'], fallback: 'flutter'),
      );

  Map<String, dynamic> toJson() => {
        'auditLogId': auditLogId,
        'action': action,
        'actorId': actorId,
        'targetType': targetType,
        'targetId': targetId,
        'createdAt': createdAt.toIso8601String(),
        'before': before,
        'after': after,
        'platform': platform,
      };
}
