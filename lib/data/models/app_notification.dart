import '../../core/utils/date_utils.dart';
import '../../core/utils/json_value.dart';

class AppNotification {
  const AppNotification({
    required this.notificationId,
    required this.title,
    required this.message,
    required this.type,
    required this.recipientId,
    required this.createdAt,
    this.companyId,
    this.projectId,
    this.taskId,
    this.actorId,
    this.actionUrl,
    this.actionLabel,
    this.rejectLabel,
    this.actionType,
    this.expiresAt,
    this.recipientIds = const <String>[],
    this.recipientRole,
    this.recipientRoleGroup,
    this.isRead = false,
  });

  final String notificationId;
  final String title;
  final String message;
  final String type;
  final String recipientId;
  final DateTime createdAt;
  final String? companyId;
  final String? projectId;
  final String? taskId;
  final String? actorId;
  final String? actionUrl;
  final String? actionLabel;
  final String? rejectLabel;
  final String? actionType;
  final DateTime? expiresAt;
  final List<String> recipientIds;
  final String? recipientRole;
  final String? recipientRoleGroup;
  bool get hasActionUrl => actionUrl != null && actionUrl!.trim().isNotEmpty;
  bool get hasExpiry => expiresAt != null;
  bool isExpiredAt(DateTime now) {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return !expiry.toLocal().isAfter(now.toLocal());
  }
  bool get isMeetingInvite {
    final normalized = type.trim().toLowerCase().replaceAll('_', '').replaceAll('-', '');
    return normalized == 'meetinginvite' || normalized == 'callinvite' || hasActionUrl;
  }
  final bool isRead;

  AppNotification copyWith({
    String? title,
    String? message,
    String? type,
    String? recipientId,
    DateTime? createdAt,
    String? companyId,
    String? projectId,
    String? taskId,
    String? actorId,
    String? actionUrl,
    String? actionLabel,
    String? rejectLabel,
    String? actionType,
    DateTime? expiresAt,
    List<String>? recipientIds,
    String? recipientRole,
    String? recipientRoleGroup,
    bool? isRead,
  }) =>
      AppNotification(
        notificationId: notificationId,
        title: title ?? this.title,
        message: message ?? this.message,
        type: type ?? this.type,
        recipientId: recipientId ?? this.recipientId,
        createdAt: createdAt ?? this.createdAt,
        companyId: companyId ?? this.companyId,
        projectId: projectId ?? this.projectId,
        taskId: taskId ?? this.taskId,
        actorId: actorId ?? this.actorId,
        actionUrl: actionUrl ?? this.actionUrl,
        actionLabel: actionLabel ?? this.actionLabel,
        rejectLabel: rejectLabel ?? this.rejectLabel,
        actionType: actionType ?? this.actionType,
        expiresAt: expiresAt ?? this.expiresAt,
        recipientIds: recipientIds ?? this.recipientIds,
        recipientRole: recipientRole ?? this.recipientRole,
        recipientRoleGroup: recipientRoleGroup ?? this.recipientRoleGroup,
        isRead: isRead ?? this.isRead,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        notificationId: JsonValue.string(json['notificationId'] ?? json['id']),
        title: JsonValue.string(json['title'], fallback: 'Notification'),
        message: JsonValue.string(json['message'] ?? json['body']),
        type: JsonValue.string(json['type'], fallback: 'taskUpdated'),
        recipientId: JsonValue.string(json['recipientId'] ?? json['uid'] ?? json['memberId']),
        createdAt: DateText.parse(json['createdAt']) ?? DateTime.now(),
        companyId: JsonValue.optionalString(json['companyId']),
        projectId: JsonValue.optionalString(json['projectId']),
        taskId: JsonValue.optionalString(json['taskId']),
        actorId: JsonValue.optionalString(json['actorId']),
        actionUrl: JsonValue.optionalString(json['actionUrl'] ?? json['meetingUrl'] ?? json['meetingLink'] ?? json['meetLink'] ?? json['googleMeetUrl'] ?? json['whatsappUrl'] ?? json['whatsappMeetingUrl'] ?? json['joinUrl'] ?? json['conferenceUrl'] ?? json['url']),
        actionLabel: JsonValue.optionalString(json['actionLabel'] ?? json['joinLabel'] ?? json['primaryActionLabel']),
        rejectLabel: JsonValue.optionalString(json['rejectLabel'] ?? json['secondaryActionLabel']),
        actionType: JsonValue.optionalString(json['actionType'] ?? json['meetingProvider'] ?? json['actionMode']),
        expiresAt: DateText.parse(json['expiresAt'] ?? json['visibleUntil'] ?? json['hideAfter'] ?? json['notificationExpiresAt'] ?? json['ttlUntil'] ?? json['validUntil']),
        recipientIds: JsonValue.stringList(json['recipientIds'] ?? json['recipients'] ?? json['memberIds']),
        recipientRole: JsonValue.optionalString(json['recipientRole'] ?? json['role']),
        recipientRoleGroup: JsonValue.optionalString(json['recipientRoleGroup'] ?? json['roleGroup']),
        isRead: JsonValue.boolean(json['isRead'] ?? json['read'], fallback: false),
      );

  Map<String, dynamic> toJson() => {
        'notificationId': notificationId,
        'title': title,
        'message': message,
        'type': type,
        'recipientId': recipientId,
        'createdAt': createdAt.toIso8601String(),
        'companyId': companyId,
        'projectId': projectId,
        'taskId': taskId,
        'actorId': actorId,
        'actionUrl': actionUrl,
        'actionLabel': actionLabel,
        'rejectLabel': rejectLabel,
        'actionType': actionType,
        'expiresAt': expiresAt?.toIso8601String(),
        'visibleUntil': expiresAt?.toIso8601String(),
        'recipientIds': recipientIds,
        'recipientRole': recipientRole,
        'recipientRoleGroup': recipientRoleGroup,
        'isRead': isRead,
      };
}
