import '../../core/utils/date_utils.dart';
import '../../core/utils/json_value.dart';

class TaskComment {
  const TaskComment({
    required this.commentId,
    required this.taskId,
    required this.authorId,
    required this.message,
    required this.createdAt,
    this.mentionedUserIds = const [],
    this.isEdited = false,
  });

  final String commentId;
  final String taskId;
  final String authorId;
  final String message;
  final DateTime createdAt;
  final List<String> mentionedUserIds;
  final bool isEdited;

  factory TaskComment.fromJson(Map<String, dynamic> json) => TaskComment(
        commentId: JsonValue.string(json['commentId'] ?? json['id']),
        taskId: JsonValue.string(json['taskId']),
        authorId: JsonValue.string(json['authorId'] ?? json['createdBy']),
        message: JsonValue.string(json['message'] ?? json['text']),
        createdAt: DateText.parse(json['createdAt']) ?? DateTime.now(),
        mentionedUserIds: JsonValue.stringList(json['mentionedUserIds'] ?? json['mentions']),
        isEdited: JsonValue.boolean(json['isEdited'], fallback: false),
      );

  Map<String, dynamic> toJson() => {
        'commentId': commentId,
        'taskId': taskId,
        'authorId': authorId,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
        'mentionedUserIds': mentionedUserIds,
        'isEdited': isEdited,
      };
}
