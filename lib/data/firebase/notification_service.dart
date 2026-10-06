import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import 'firebase_paths.dart';
import 'firestore_service.dart';

class NotificationService {
  NotificationService({FirestoreService? firestoreService}) : _firestoreService = firestoreService ?? FirestoreService();

  final FirestoreService _firestoreService;

  /// Reads the durable member inbox path. The Admin SDK Cloud Function sends
  /// FCM from the root company notification doc, while every UI reads this
  /// member mirror so foreground/background/terminated state stays consistent.
  Stream<List<AppNotification>> watchPrivateNotifications({
    required String companyId,
    required String currentUserId,
  }) {
    return _firestoreService.collectionStream<AppNotification>(
      path: FirebasePaths.memberNotifications(companyId, currentUserId),
      builder: AppNotification.fromJson,
      queryBuilder: (query) => query.orderBy('createdAt', descending: true),
    );
  }

  Future<void> createTaskAssignedNotification({
    required String companyId,
    required String projectId,
    required String taskId,
    required String taskTitle,
    required String projectName,
    required String recipientId,
    required String actorId,
  }) async {
    final now = DateTime.now();
    final id = 'notification_${now.microsecondsSinceEpoch}';
    final notification = AppNotification(
      notificationId: id,
      title: 'Task assigned to you',
      message: '$taskTitle in $projectName has been assigned to you.',
      type: 'taskAssigned',
      recipientId: recipientId,
      companyId: companyId,
      projectId: projectId,
      taskId: taskId,
      actorId: actorId,
      createdAt: now,
      expiresAt: _defaultExpiryFor(now),
    );

    await _writeRootAndMemberNotification(
      companyId: companyId,
      recipientId: recipientId,
      notification: notification,
      extra: <String, dynamic>{
        'body': notification.message,
        'read': false,
        'accepted': false,
        'targetUid': recipientId,
        'recipientIds': <String>[recipientId],
        'requiresAccept': true,
        'loopUntilAccept': true,
        'acceptButtonEnabled': true,
        'soundName': 'user_preference',
        'androidSoundName': 'task_alert_airport_ding',
        'forceSoundName': false,
        'assistantVoice': true,
        'assistantText': 'You are assigned a new task. Please accept the notification.',
        'styleVariant': 'task_glass_remoteviews_v84',
        'pushStatus': 'queued_oracle_backend',
        'source': 'client_notification_service_oracle_backend_queue',
        'deliveryPipeline': 'firestore_queue_to_oracle_admin_sdk_to_fcm_all_states',
        'pushPrimaryTrigger': 'oracle_worker_company_root',
      },
    );
  }

  Future<void> createMeetingInviteNotification({
    required String companyId,
    required String title,
    required String message,
    required String recipientId,
    required String actorId,
    String? projectId,
    String? taskId,
    required String meetingUrl,
    String actionLabel = 'Accept & Join',
    String rejectLabel = 'Reject',
  }) async {
    final now = DateTime.now();
    final id = 'meeting_${now.microsecondsSinceEpoch}';
    final notification = AppNotification(
      notificationId: id,
      title: title.trim().isEmpty ? 'Meeting invite' : title.trim(),
      message: message.trim().isEmpty ? 'Join the scheduled meeting.' : message.trim(),
      type: 'meetingInvite',
      recipientId: recipientId,
      companyId: companyId,
      projectId: projectId,
      taskId: taskId,
      actorId: actorId,
      actionUrl: meetingUrl,
      actionLabel: actionLabel,
      rejectLabel: rejectLabel,
      actionType: meetingUrl.toLowerCase().contains('whatsapp') ? 'whatsappMeeting' : 'googleMeet',
      createdAt: now,
      expiresAt: _defaultExpiryFor(now),
    );

    await _writeRootAndMemberNotification(
      companyId: companyId,
      recipientId: recipientId,
      notification: notification,
      extra: <String, dynamic>{
        'body': notification.message,
        'read': false,
        'accepted': false,
        'targetUid': recipientId,
        'recipientIds': <String>[recipientId],
        'meetingUrl': meetingUrl,
        'joinUrl': meetingUrl,
        'requiresAccept': true,
        'loopUntilAccept': true,
        'acceptButtonEnabled': true,
        'soundName': 'user_preference',
        'androidSoundName': 'task_alert_airport_ding',
        'forceSoundName': false,
        'assistantVoice': true,
        'assistantText': 'You have a meeting invite. Please accept and join, or reject the notification.',
        'styleVariant': 'meeting_glass_remoteviews_v84',
        'pushStatus': 'queued_oracle_backend',
        'source': 'client_notification_service_oracle_backend_queue',
        'deliveryPipeline': 'firestore_queue_to_oracle_admin_sdk_to_fcm_all_states',
        'pushPrimaryTrigger': 'oracle_worker_company_root',
      },
    );
  }

  Future<void> _writeRootAndMemberNotification({
    required String companyId,
    required String recipientId,
    required AppNotification notification,
    required Map<String, dynamic> extra,
  }) async {
    final data = <String, dynamic>{
      ...notification.toJson(),
      ...extra,
      'notificationId': notification.notificationId,
      'companyId': companyId,
      'recipientId': recipientId,
      'message': notification.message,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    final rootRef = FirebaseFirestore.instance.doc('${FirebasePaths.notifications(companyId)}/${notification.notificationId}');
    final memberRef = FirebaseFirestore.instance.doc('${FirebasePaths.memberNotifications(companyId, recipientId)}/${notification.notificationId}');
    final requiresAccept = data['requiresAccept'] == true;
    final rootData = <String, dynamic>{
      ...data,
      'queueScope': 'company_root',
      'activeQueue': true,
      'deliveryProvider': 'oracle_admin_sdk',
      'deliveryStatus': 'queued',
      'responseStatus': requiresAccept ? 'pending' : 'not_required',
      'pushStatus': 'queued_oracle_backend',
      'nextAttemptAt': Timestamp.now(),
      'attemptCount': 0,
      'maxAttempts': 3,
      'retryIntervalMinutes': 5,
      'adminAttentionRequired': false,
    };
    final memberData = <String, dynamic>{
      ...data,
      'queueScope': 'member_mirror',
      'activeQueue': false,
      'deliveryProvider': 'oracle_admin_sdk',
      'deliveryStatus': 'queued',
      'responseStatus': requiresAccept ? 'pending' : 'not_required',
      'pushStatus': 'queued_oracle_backend',
      'adminAttentionRequired': false,
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.set(rootRef, rootData, SetOptions(merge: true));
    batch.set(memberRef, memberData, SetOptions(merge: true));
    await batch.commit();
  }

  DateTime _defaultExpiryFor(DateTime createdAt) {
    final local = createdAt.toLocal();
    return DateTime(local.year, local.month + 1);
  }

  Future<void> markPrivateNotificationRead({
    required String companyId,
    required String notificationId,
  }) async {
    final rootRef = FirebaseFirestore.instance.doc('${FirebasePaths.notifications(companyId)}/$notificationId');
    final rootSnapshot = await rootRef.get();
    final rootData = rootSnapshot.data();
    final recipientId = (rootData?['recipientId'] as String?)?.trim() ?? '';
    final update = <String, dynamic>{
      'isRead': true,
      'read': true,
      'accepted': true,
      'readAt': Timestamp.now(),
      'acceptedAt': Timestamp.now(),
      'pushStatus': 'accepted_from_client',
      'deliveryStatus': 'responded',
      'responseStatus': 'accepted',
      'nextAttemptAt': FieldValue.delete(),
      'leaseOwner': FieldValue.delete(),
      'leaseUntil': FieldValue.delete(),
      'adminAttentionRequired': false,
      'activeQueue': false,
    };

    final batch = FirebaseFirestore.instance.batch();
    batch.set(rootRef, update, SetOptions(merge: true));
    if (recipientId.isNotEmpty) {
      final memberRef = FirebaseFirestore.instance.doc('${FirebasePaths.memberNotifications(companyId, recipientId)}/$notificationId');
      batch.set(memberRef, update, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
