import '../../core/utils/date_utils.dart';
import '../../core/utils/json_value.dart';

class ActivityLog {
  const ActivityLog({
    required this.activityLogId,
    required this.title,
    required this.description,
    required this.actorId,
    required this.targetType,
    required this.targetId,
    required this.createdAt,
  });

  final String activityLogId;
  final String title;
  final String description;
  final String actorId;
  final String targetType;
  final String targetId;
  final DateTime createdAt;

  factory ActivityLog.fromJson(Map<String, dynamic> json) => ActivityLog(
        activityLogId: JsonValue.string(json['activityLogId'] ?? json['id']),
        title: JsonValue.string(json['title'], fallback: 'Activity'),
        description: JsonValue.string(json['description'] ?? json['message']),
        actorId: JsonValue.string(json['actorId']),
        targetType: JsonValue.string(json['targetType']),
        targetId: JsonValue.string(json['targetId']),
        createdAt: DateText.parse(json['createdAt']) ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'activityLogId': activityLogId,
        'title': title,
        'description': description,
        'actorId': actorId,
        'targetType': targetType,
        'targetId': targetId,
        'createdAt': createdAt.toIso8601String(),
      };
}
