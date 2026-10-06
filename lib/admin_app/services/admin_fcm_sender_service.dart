import 'package:cloud_firestore/cloud_firestore.dart';

class AdminFcmSendResult {
  const AdminFcmSendResult({
    required this.success,
    required this.sent,
    required this.failed,
    required this.tokenCount,
    required this.invalidTokenCount,
    required this.noTokenUids,
    this.targetCount,
    this.message,
  });

  factory AdminFcmSendResult.fromMap(Map<String, dynamic> data) {
    return AdminFcmSendResult(
      success: data['success'] == true,
      sent: _asInt(data['sent']),
      failed: _asInt(data['failed']),
      tokenCount: _asInt(data['tokenCount']),
      invalidTokenCount: _asInt(data['invalidTokenCount']),
      targetCount: data.containsKey('targetCount') ? _asInt(data['targetCount']) : null,
      noTokenUids: (data['noTokenUids'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      message: data['message'] as String?,
    );
  }

  final bool success;
  final int sent;
  final int failed;
  final int tokenCount;
  final int invalidTokenCount;
  final int? targetCount;
  final List<String> noTokenUids;
  final String? message;

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class AdminFcmSenderService {
  AdminFcmSenderService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Queues a private notification by writing a Firestore document.
  ///
  /// The backend Cloud Functions listen to the company root notification and
  /// member mirror notification paths. The company root trigger sends the FCM
  /// push, while the member mirror keeps the notification visible in every
  /// scoped inbox/UI. This keeps the admin panel simple and avoids exposing FCM
  /// server credentials in the client.
  Future<AdminFcmSendResult> sendDirectFcm({
    required String companyId,
    required String targetUid,
    required String title,
    required String body,
    String type = 'teamMention',
    String? taskId,
    String? projectId,
    String? teamId,
    String? deepLink,
    String? actionUrl,
    String? actionLabel,
    String? rejectLabel,
    String? actionType,
    String soundName = 'user_preference',
    bool requiresAccept = false,
    bool loopUntilAccept = false,
    bool assistantVoice = false,
    String? assistantText,
    DateTime? expiresAt,
  }) async {
    final cleanCompanyId = companyId.trim();
    final cleanTargetUid = targetUid.trim();
    final cleanTitle = title.trim().isEmpty ? 'Project update' : title.trim();
    final cleanBody = body.trim().isEmpty ? 'You have a new notification.' : body.trim();
    if (cleanCompanyId.isEmpty || cleanTargetUid.isEmpty) {
      return const AdminFcmSendResult(
        success: false,
        sent: 0,
        failed: 0,
        tokenCount: 0,
        invalidTokenCount: 0,
        noTokenUids: <String>[],
        message: 'companyId and targetUid are required.',
      );
    }

    final now = DateTime.now();
    final rootNotificationRef = _firestore
        .collection('companies')
        .doc(cleanCompanyId)
        .collection('notifications')
        .doc();
    final memberNotificationRef = _firestore
        .collection('companies')
        .doc(cleanCompanyId)
        .collection('members')
        .doc(cleanTargetUid)
        .collection('notifications')
        .doc(rootNotificationRef.id);

    final notificationPayload = <String, dynamic>{
      'notificationId': rootNotificationRef.id,
      'companyId': cleanCompanyId,
      'recipientId': cleanTargetUid,
      'targetUid': cleanTargetUid,
      'recipientIds': <String>[cleanTargetUid],
      'title': cleanTitle,
      'body': cleanBody,
      'message': cleanBody,
      'type': _rulesAllowedNotificationType(type, fallback: requiresAccept ? 'taskAssigned' : 'teamMention'),
      'taskId': taskId?.trim() ?? '',
      'projectId': projectId?.trim() ?? '',
      'teamId': teamId?.trim() ?? '',
      'deepLink': deepLink?.trim() ?? '',
      'actionUrl': actionUrl?.trim() ?? '',
      'meetingUrl': actionUrl?.trim() ?? '',
      'joinUrl': actionUrl?.trim() ?? '',
      'actionLabel': (actionLabel?.trim().isNotEmpty ?? false)
          ? actionLabel!.trim()
          : ((actionUrl?.trim().isNotEmpty ?? false) ? 'Accept & Join' : 'Accept'),
      'rejectLabel': (rejectLabel?.trim().isNotEmpty ?? false) ? rejectLabel!.trim() : 'Reject',
      'actionType': actionType?.trim() ?? '',
      'soundName': soundName.trim().isEmpty ? 'user_preference' : soundName.trim(),
      'requiresAccept': requiresAccept,
      'loopUntilAccept': loopUntilAccept,
      'acceptButtonEnabled': requiresAccept,
      'assistantVoice': assistantVoice,
      'assistantText': assistantText?.trim() ?? '',
      'isRead': false,
      'read': false,
      'accepted': false,
      'createdAt': Timestamp.fromDate(now),
      'createdAtMillis': now.millisecondsSinceEpoch.toString(),
      'expiresAt': Timestamp.fromDate(expiresAt ?? _defaultNotificationExpiry()),
      'visibleUntil': Timestamp.fromDate(expiresAt ?? _defaultNotificationExpiry()),
      'deliveryProvider': 'oracle_admin_sdk',
      'deliveryStatus': 'queued',
      'responseStatus': requiresAccept ? 'pending' : 'not_required',
      'attemptCount': 0,
      'maxAttempts': 3,
      'retryIntervalMinutes': 5,
      'adminAttentionRequired': false,
      'source': 'admin_panel_oracle_backend_queue',
      'deliveryPipeline': 'firestore_queue_to_oracle_admin_sdk_to_fcm_all_states',
      'pushPrimaryTrigger': 'oracle_worker_company_root',
    };
    final rootPayload = <String, dynamic>{
      ...notificationPayload,
      'queueScope': 'company_root',
      'activeQueue': true,
      'pushStatus': 'queued_oracle_backend',
      'nextAttemptAt': Timestamp.fromDate(now),
    };
    final memberPayload = <String, dynamic>{
      ...notificationPayload,
      'queueScope': 'member_mirror',
      'activeQueue': false,
      'pushStatus': 'queued_oracle_backend',
    };

    final batch = _firestore.batch();
    batch.set(rootNotificationRef, rootPayload, SetOptions(merge: false));
    batch.set(memberNotificationRef, memberPayload, SetOptions(merge: false));
    await batch.commit();

    return AdminFcmSendResult(
      success: true,
      sent: 0,
      failed: 0,
      tokenCount: 0,
      invalidTokenCount: 0,
      targetCount: 1,
      noTokenUids: const <String>[],
      message: 'Notification queued in Firestore. The Oracle Admin SDK backend will send FCM and update delivery status.',
    );
  }

  Future<AdminFcmSendResult> sendTaskAssignmentFcm({
    required String companyId,
    required String targetUid,
    required String taskId,
    required String projectId,
    required String taskTitle,
  }) {
    return sendDirectFcm(
      companyId: companyId,
      targetUid: targetUid,
      title: 'New task assigned',
      body: '$taskTitle has been assigned to you. Please accept it.',
      type: 'taskAssigned',
      taskId: taskId,
      projectId: projectId,
      deepLink: 'pmd://task/$taskId',
      soundName: 'user_preference',
      requiresAccept: true,
      loopUntilAccept: true,
      assistantVoice: true,
      assistantText: 'You are assigned a new task. Please accept the notification.',
      expiresAt: _defaultNotificationExpiry(),
    );
  }


  static String _rulesAllowedNotificationType(String type, {required String fallback}) {
    const allowed = <String>{
      'taskAssigned',
      'taskUpdated',
      'taskCompleted',
      'deadlineReminder',
      'projectUpdated',
      'teamMention',
      'securityAlert',
      'meetingInvite',
      'callInvite',
    };
    final trimmed = type.trim();
    return allowed.contains(trimmed) ? trimmed : fallback;
  }

  DateTime _defaultNotificationExpiry() {
    final now = DateTime.now();
    return DateTime(now.year, now.month + 1);
  }

  Future<AdminFcmSendResult> sendProjectFcm({
    required String companyId,
    required String projectId,
    required String title,
    required String body,
    String type = 'projectUpdated',
  }) async {
    final snapshot = await _firestore
        .collection('companies')
        .doc(companyId.trim())
        .collection('members')
        .where('projectIds', arrayContains: projectId.trim())
        .get();
    return _queueBroadcast(
      companyId: companyId,
      targetUids: snapshot.docs
          .where((doc) => (doc.data()['status'] as String? ?? 'active').toLowerCase() == 'active')
          .map((doc) => doc.id),
      title: title,
      body: body,
      type: type,
      projectId: projectId,
    );
  }

  Future<AdminFcmSendResult> sendTeamFcm({
    required String companyId,
    required String teamId,
    required String title,
    required String body,
    String type = 'teamMention',
  }) async {
    final snapshot = await _firestore
        .collection('companies')
        .doc(companyId.trim())
        .collection('members')
        .where('teamIds', arrayContains: teamId.trim())
        .get();
    return _queueBroadcast(
      companyId: companyId,
      targetUids: snapshot.docs
          .where((doc) => (doc.data()['status'] as String? ?? 'active').toLowerCase() == 'active')
          .map((doc) => doc.id),
      title: title,
      body: body,
      type: type,
      teamId: teamId,
    );
  }

  Future<AdminFcmSendResult> _queueBroadcast({
    required String companyId,
    required Iterable<String> targetUids,
    required String title,
    required String body,
    required String type,
    String? projectId,
    String? teamId,
  }) async {
    final uids = targetUids.map((uid) => uid.trim()).where((uid) => uid.isNotEmpty).toSet().toList();
    if (uids.isEmpty) {
      return const AdminFcmSendResult(
        success: false,
        sent: 0,
        failed: 0,
        tokenCount: 0,
        invalidTokenCount: 0,
        targetCount: 0,
        noTokenUids: <String>[],
        message: 'No active members matched this broadcast.',
      );
    }
    final results = await Future.wait(uids.map((uid) => sendDirectFcm(
          companyId: companyId,
          targetUid: uid,
          title: title,
          body: body,
          type: type,
          projectId: projectId,
          teamId: teamId,
        )));
    final failedUids = <String>[];
    for (var index = 0; index < results.length; index += 1) {
      if (!results[index].success) failedUids.add(uids[index]);
    }
    return AdminFcmSendResult(
      success: failedUids.isEmpty,
      sent: 0,
      failed: failedUids.length,
      tokenCount: 0,
      invalidTokenCount: 0,
      targetCount: uids.length,
      noTokenUids: failedUids,
      message: failedUids.isEmpty
          ? '${uids.length} notification job(s) queued for the Oracle backend.'
          : '${failedUids.length} notification job(s) could not be queued.',
    );
  }

}
