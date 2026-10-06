import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/workspace_state.dart';
import '../config/app_config.dart';
import '../crash/apk_crash_forensics.dart';
import '../../data/models/app_notification.dart';
import '../../data/cache/fcm_runtime_token_cache.dart';

/// Bridges Firestore/private inbox notifications to an Android native,
/// lock-screen-visible urgent notification with an Accept action.
///
/// The Android side owns the looping sound so it can continue while the Flutter
/// UI is backgrounded. Unsupported platforms safely no-op.

class AlertSoundOption {
  const AlertSoundOption({required this.name, required this.label, required this.description});

  final String name;
  final String label;
  final String description;
}

class AndroidAlertNotificationService {
  AndroidAlertNotificationService._();

  static const MethodChannel _channel = MethodChannel('project_management_dashboard/alert_notifications');
  static const String defaultAlertSoundName = 'emergency_alarm';
  static const List<AlertSoundOption> alertSoundOptions = <AlertSoundOption>[
    AlertSoundOption(name: 'emergency_alarm', label: 'Emergency alarm', description: 'Default urgent notification sound'),
    AlertSoundOption(name: 'task_alert_church_bell', label: 'Church bell', description: 'Deep bell hit'),
    AlertSoundOption(name: 'task_alert_airport_ding', label: 'Airport ding', description: 'Short announcement ding'),
    AlertSoundOption(name: 'old_phone_ringtone', label: 'Old phone ringtone', description: 'Classic old phone ring'),
    AlertSoundOption(name: 'ringing_old_phone', label: 'Ringing old phone', description: 'Long old-phone ring loop'),
    AlertSoundOption(name: 'old_ring_tone', label: 'Old ring tone', description: 'Soft vintage phone ring'),
  ];
  static bool _initialized = false;
  static bool _permissionRequested = false;
  static bool _autoPermissionPromptScheduled = false;
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  static final Set<String> _alertedNotificationIds = <String>{};
  static const FcmRuntimeTokenCache _fcmRuntimeTokenCache = FcmRuntimeTokenCache();
  static final Set<String> _registeredUidThisSession = <String>{};

  /// FCM stability policy: token changes are staged locally and server writes
  /// are allowed at most twice per hour. This keeps notification setup from
  /// competing with the SDUI render session while the employee is using the APK.
  static const Duration _fcmServerSyncInterval = Duration(minutes: 30);

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> initialize() async {
    if (!_isAndroid || _initialized) return;
    _initialized = true;
    ApkCrashForensics.log('android_alert_initialize_start');
    try {
      await _channel.invokeMethod<void>('initialize');
      ApkCrashForensics.log('android_alert_initialize_done');
      // Do not request POST_NOTIFICATIONS automatically during startup.
      // Some Android/OEM builds can kill/restart the process when a runtime permission
      // request is triggered from a delayed plugin callback while the employee shell is
      // still opening. Permission is requested only from an explicit user action.
    } on MissingPluginException {
      // Android channel is not available on web/desktop/debug surfaces.
    } catch (error) {
      debugPrint('Android alert notification init failed: $error');
    }
  }

  static Future<bool> areNotificationsEnabled() async {
    if (!_isAndroid) return false;
    await initialize();
    try {
      final result = await _channel.invokeMethod<bool>('areNotificationsEnabled');
      return result ?? false;
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android notification permission status failed: $error');
    }
    return false;
  }

  static Future<bool> requestPermissionIfNeeded({bool force = false}) async {
    if (!_isAndroid) return false;
    final alreadyEnabled = await areNotificationsEnabled();
    if (alreadyEnabled) return true;
    if (_permissionRequested && !force) return false;
    _permissionRequested = true;
    ApkCrashForensics.log('android_notification_permission_request_start', data: <String, Object?>{'force': force});
    try {
      await _channel.invokeMethod<void>('requestNotificationPermission');
      // Android permission dialogs are asynchronous from the user's point of view.
      // Give the platform a short moment before rechecking status so the Profile
      // button can give accurate feedback after the user responds.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      final enabled = await areNotificationsEnabled();
      ApkCrashForensics.log('android_notification_permission_request_done', data: <String, Object?>{'enabled': enabled});
      return enabled;
    } on MissingPluginException {
    } catch (error, stack) {
      ApkCrashForensics.recordError(error, stack, fatal: false, source: 'requestNotificationPermission');
      debugPrint('Android notification permission request failed: $error');
    }
    return areNotificationsEnabled();
  }

  static void schedulePermissionPromptAfterLogin() {
    if (!_isAndroid || _autoPermissionPromptScheduled) return;
    _autoPermissionPromptScheduled = true;
    unawaited(Future<void>.delayed(const Duration(milliseconds: 1400), () async {
      try {
        final enabled = await areNotificationsEnabled();
        if (!enabled) {
          ApkCrashForensics.log('android_notification_permission_auto_prompt_after_login');
          await requestPermissionIfNeeded();
        }
      } catch (error, stack) {
        ApkCrashForensics.recordError(error, stack, fatal: false, source: 'schedulePermissionPromptAfterLogin');
      }
    }));
  }

  static Future<void> showLoopingAlert(AppNotification notification) async {
    if (!_isAndroid || notification.isRead || notification.isExpiredAt(DateTime.now())) return;
    await showLoopingAlertPayload(
      title: notification.title,
      message: notification.message,
      soundName: await getPreferredAlertSound(),
      notificationId: notification.notificationId,
      notificationType: notification.type,
      assistantVoice: await getAssistantVoiceEnabled() && _isAssistantNotificationType(notification.type),
      assistantText: _assistantTextFor(notification.type),
      actionUrl: notification.actionUrl,
      actionLabel: notification.actionLabel,
      rejectLabel: notification.rejectLabel,
      actionType: notification.actionType,
    );
  }

  static Future<void> showLoopingAlertPayload({
    required String title,
    required String message,
    String? soundName,
    String? notificationId,
    String? notificationType,
    bool assistantVoice = false,
    String? assistantText,
    String? actionUrl,
    String? actionLabel,
    String? rejectLabel,
    String? actionType,
  }) async {
    if (!_isAndroid) return;
    final cleanTitle = title.trim().isEmpty ? 'New work notification' : title.trim();
    final cleanMessage = message.trim().isEmpty ? 'Open the app to review this update.' : message.trim();
    final cleanNotificationId = (notificationId ?? '').trim().isEmpty ? '${cleanTitle.hashCode}_${cleanMessage.hashCode}' : notificationId!.trim();
    final cleanType = (notificationType ?? '').trim().isEmpty ? 'general' : notificationType!.trim();
    if (_alertedNotificationIds.contains(cleanNotificationId)) return;
    await initialize();
    final accepted = await getAcceptedAlertIds();
    if (accepted.contains(cleanNotificationId)) return;
    final notificationsEnabled = await areNotificationsEnabled();
    if (!notificationsEnabled) {
      ApkCrashForensics.log('android_looping_alert_blocked_permission', data: <String, Object?>{
        'notificationId': cleanNotificationId,
        'type': cleanType,
      });
      return;
    }
    final preferredSound = _normalizeSoundName(soundName ?? await getPreferredAlertSound());
    try {
      await _channel.invokeMethod<void>('showLoopingAlert', <String, Object?>{
        'title': cleanTitle,
        'message': cleanMessage,
        'soundName': preferredSound,
        'notificationId': cleanNotificationId,
        'notificationType': cleanType,
        'assistantVoice': assistantVoice && await getAssistantVoiceEnabled(),
        'assistantText': _cleanAssistantText(assistantText, cleanType),
        'actionUrl': _cleanExternalUrl(actionUrl),
        'actionLabel': _cleanActionLabel(actionLabel, cleanType),
        'rejectLabel': _cleanRejectLabel(rejectLabel),
        'actionType': (actionType ?? '').trim(),
      });
      _alertedNotificationIds.add(cleanNotificationId);
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android looping notification failed: $error');
    }
  }

  static Future<String> getPreferredAlertSound() async {
    if (!_isAndroid) return defaultAlertSoundName;
    await initialize();
    try {
      final result = await _channel.invokeMethod<String>('getAlertSoundPreference');
      return _normalizeSoundName(result);
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android alert sound preference read failed: $error');
    }
    return defaultAlertSoundName;
  }

  static Future<String> setPreferredAlertSound(String soundName) async {
    final normalized = _normalizeSoundName(soundName);
    if (!_isAndroid) return normalized;
    await initialize();
    try {
      final result = await _channel.invokeMethod<String>('setAlertSoundPreference', <String, Object?>{'soundName': normalized});
      return _normalizeSoundName(result);
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android alert sound preference save failed: $error');
    }
    return normalized;
  }


  static Future<bool> getAssistantVoiceEnabled() async {
    if (!_isAndroid) return true;
    await initialize();
    try {
      final result = await _channel.invokeMethod<bool>('getAssistantVoiceEnabled');
      return result ?? true;
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android assistant voice preference read failed: $error');
    }
    return true;
  }


  static Future<void> setNotificationDisplayWindowPreference({
    required String mode,
    int? days,
    int? hours,
  }) async {
    if (!_isAndroid) return;
    await initialize();
    try {
      await _channel.invokeMethod<void>('setNotificationDisplayWindowPreference', <String, Object?>{
        'mode': mode,
        if (days != null) 'days': days,
        if (hours != null) 'hours': hours,
      });
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android notification display window preference save failed: $error');
    }
  }

  static Future<bool> setAssistantVoiceEnabled(bool enabled) async {
    if (!_isAndroid) return enabled;
    await initialize();
    try {
      final result = await _channel.invokeMethod<bool>('setAssistantVoiceEnabled', <String, Object?>{'enabled': enabled});
      return result ?? enabled;
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android assistant voice preference save failed: $error');
    }
    return enabled;
  }

  static String labelForSound(String soundName) {
    final normalized = _normalizeSoundName(soundName);
    return alertSoundOptions.firstWhere((option) => option.name == normalized, orElse: () => alertSoundOptions.first).label;
  }

  static String _normalizeSoundName(String? soundName) {
    final cleaned = (soundName ?? '').trim().toLowerCase().replaceAll('-', '_');
    for (final option in alertSoundOptions) {
      if (option.name == cleaned) return option.name;
    }
    return defaultAlertSoundName;
  }


  static Future<bool> testSelectedAlertSound({
    required String soundName,
    bool assistantVoice = true,
    String? assistantText,
  }) async {
    final enabled = await requestPermissionIfNeeded(force: true);
    if (!enabled) {
      ApkCrashForensics.log('android_notification_test_blocked_permission');
      return false;
    }
    final saved = await setPreferredAlertSound(soundName);
    // Stop any previous looping test first. Without this, Android may keep the
    // old MediaPlayer/foreground notification alive and the user hears the old
    // emergency sound even after selecting another option.
    await cancelLoopingAlert();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await showLoopingAlertPayload(
      title: 'Notification sound test',
      message: 'This sound is now selected. It will loop until you tap Accept.',
      soundName: saved,
      notificationId: 'sound_test_${DateTime.now().microsecondsSinceEpoch}',
      notificationType: 'soundTest',
      assistantVoice: assistantVoice,
      assistantText: assistantText ?? 'You are assigned a new task. Please accept the notification.',
    );
    return true;
  }

  static Future<void> acceptLoopingAlert(String notificationId) async {
    if (!_isAndroid || notificationId.trim().isEmpty) return;
    _alertedNotificationIds.add(notificationId.trim());
    try {
      await _channel.invokeMethod<void>('acceptLoopingAlert', <String, Object?>{'notificationId': notificationId.trim()});
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android looping notification accept failed: $error');
    }
  }

  static Future<Set<String>> getAcceptedAlertIds() async {
    if (!_isAndroid) return const <String>{};
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getAcceptedAlertIds');
      return (result ?? const <dynamic>[]).map((item) => item.toString()).where((item) => item.trim().isNotEmpty).toSet();
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android accepted alert IDs read failed: $error');
    }
    return const <String>{};
  }

  static Future<Set<String>> getAcceptedTaskIds() async {
    if (!_isAndroid) return const <String>{};
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getAcceptedTaskIds');
      return (result ?? const <dynamic>[]).map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toSet();
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android accepted task IDs read failed: $error');
    }
    return const <String>{};
  }

  static Future<void> clearAcceptedAlertIds(Iterable<String> notificationIds) async {
    if (!_isAndroid) return;
    final ids = notificationIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toList(growable: false);
    if (ids.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('clearAcceptedAlertIds', <String, Object?>{'notificationIds': ids});
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android accepted alert IDs clear failed: $error');
    }
  }

  static Future<void> clearAcceptedTaskIds(Iterable<String> taskIds) async {
    if (!_isAndroid) return;
    final ids = taskIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toList(growable: false);
    if (ids.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('clearAcceptedTaskIds', <String, Object?>{'taskIds': ids});
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android accepted task IDs clear failed: $error');
    }
  }

  static Future<void> cancelLoopingAlert() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('cancelLoopingAlert');
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android looping notification cancel failed: $error');
    }
  }



  static Future<String> readNativeNotificationLog() async {
    if (!_isAndroid) return 'Native notification log is available only on Android APK.';
    try {
      final result = await _channel.invokeMethod<String>('readNativeNotificationLog');
      return result?.trim().isNotEmpty == true ? result! : 'No native notification log found yet.';
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android native notification log read failed: $error');
    }
    return 'Could not read native notification log.';
  }

  static Future<void> clearNativeNotificationLog() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('clearNativeNotificationLog');
    } on MissingPluginException {
    } catch (error) {
      debugPrint('Android native notification log clear failed: $error');
    }
  }

  static bool _isAssistantNotificationType(String notificationType) {
    final normalized = notificationType.trim().toLowerCase().replaceAll('-', '').replaceAll('_', '');
    return normalized == 'taskassigned' || normalized == 'deadlinereminder' || normalized == 'meetinginvite' || normalized == 'callinvite';
  }

  static String _assistantTextFor(String notificationType) {
    final normalized = notificationType.trim().toLowerCase().replaceAll('-', '').replaceAll('_', '');
    if (normalized == 'taskassigned') return 'You are assigned a new task. Please accept the notification.';
    if (normalized == 'meetinginvite' || normalized == 'callinvite') return 'You have a meeting invite. Please accept and join, or reject the notification.';
    return 'You have a new work notification. Please accept the notification.';
  }

  static String _cleanAssistantText(String? text, String notificationType) {
    final trimmed = (text ?? '').trim();
    return trimmed.isEmpty ? _assistantTextFor(notificationType) : trimmed;
  }

  static String _cleanActionLabel(String? label, String notificationType) {
    final trimmed = (label ?? '').trim();
    if (trimmed.isNotEmpty) return trimmed.length > 18 ? trimmed.substring(0, 18) : trimmed;
    final normalized = notificationType.trim().toLowerCase().replaceAll('-', '').replaceAll('_', '');
    return normalized == 'meetinginvite' || normalized == 'callinvite' ? 'Accept & Join' : 'Open';
  }

  static String _cleanRejectLabel(String? label) {
    final trimmed = (label ?? '').trim();
    if (trimmed.isNotEmpty) return trimmed.length > 18 ? trimmed.substring(0, 18) : trimmed;
    return 'Reject';
  }

  static String _cleanExternalUrl(String? url) {
    final trimmed = (url ?? '').trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('https://') || lower.startsWith('http://') || lower.startsWith('whatsapp://')) return trimmed;
    if (lower.startsWith('meet.google.com/') || lower.startsWith('wa.me/') || lower.startsWith('api.whatsapp.com/') || lower.startsWith('chat.whatsapp.com/') || lower.startsWith('call.whatsapp.com/')) return 'https://$trimmed';
    return '';
  }


  static Future<void> registerFcmTokenForUser(String uid) async {
    final cleanUid = uid.trim();
    if (!_isAndroid || !AppConfig.useFirebase || cleanUid.isEmpty) return;
    if (_registeredUidThisSession.contains(cleanUid)) {
      ApkCrashForensics.log('fcm_register_skipped_session_cache', data: <String, Object?>{'uid': cleanUid});
      _attachForegroundFcmAlert();
      return;
    }
    _registeredUidThisSession.add(cleanUid);
    ApkCrashForensics.log('fcm_register_start', data: <String, Object?>{
      'uid': cleanUid,
      'mode': 'staged_30m_server_sync',
      'serverSyncIntervalMinutes': _fcmServerSyncInterval.inMinutes,
    });
    try {
      schedulePermissionPromptAfterLogin();
      await FirebaseMessaging.instance.setAutoInitEnabled(true).timeout(const Duration(seconds: 6));
      ApkCrashForensics.log('fcm_auto_init_done');

      var canServerSync = await _fcmRuntimeTokenCache.canSyncWithServer(cleanUid, _fcmServerSyncInterval);
      ApkCrashForensics.log('fcm_server_sync_window', data: <String, Object?>{
        'canSync': canServerSync,
        'intervalMinutes': _fcmServerSyncInterval.inMinutes,
      });

      // Flush one previously staged token only when the 30-minute sync window is open.
      // Otherwise keep it pending locally. This prevents repeated Firestore writes
      // during the same user session.
      final pending = await _fcmRuntimeTokenCache.readPendingToken(cleanUid);
      if (pending != null && canServerSync) {
        ApkCrashForensics.log('fcm_pending_flush_start');
        await _saveFcmToken(cleanUid, pending['token']!, pending['permissionStatus'] ?? 'unknown').timeout(const Duration(seconds: 8));
        await _fcmRuntimeTokenCache.markActiveToken(
          uid: cleanUid,
          token: pending['token']!,
          permissionStatus: pending['permissionStatus'] ?? 'unknown',
        );
        await _fcmRuntimeTokenCache.markServerSynced(cleanUid);
        canServerSync = false;
        ApkCrashForensics.log('fcm_pending_flush_done');
      } else if (pending != null) {
        ApkCrashForensics.log('fcm_pending_flush_deferred', data: <String, Object?>{
          'reason': '30m_window_closed',
        });
      }

      // Important stability fix: do not call requestPermission() automatically here.
      // Token registration is safe without the Android 13 notification prompt. The user
      // can grant notification permission from the explicit Profile notification controls.
      final settings = await FirebaseMessaging.instance.getNotificationSettings().timeout(const Duration(seconds: 6));
      ApkCrashForensics.log('fcm_permission_status', data: <String, Object?>{'status': settings.authorizationStatus.name});

      final token = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 10));
      ApkCrashForensics.log('fcm_get_token_done', data: <String, Object?>{'hasToken': token != null && token.isNotEmpty});
      if (token != null && token.isNotEmpty) {
        final activeToken = await _fcmRuntimeTokenCache.readActiveToken(cleanUid);
        canServerSync = await _fcmRuntimeTokenCache.canSyncWithServer(cleanUid, _fcmServerSyncInterval);
        if (activeToken == null || activeToken.isEmpty) {
          if (canServerSync) {
            // First install: save once so terminated/background FCM can work.
            await _saveFcmToken(cleanUid, token, settings.authorizationStatus.name).timeout(const Duration(seconds: 8));
            await _fcmRuntimeTokenCache.markActiveToken(uid: cleanUid, token: token, permissionStatus: settings.authorizationStatus.name);
            await _fcmRuntimeTokenCache.markServerSynced(cleanUid);
            ApkCrashForensics.log('fcm_token_saved_first_bootstrap');
          } else {
            await _fcmRuntimeTokenCache.stagePendingToken(uid: cleanUid, token: token, permissionStatus: settings.authorizationStatus.name);
            ApkCrashForensics.log('fcm_token_first_bootstrap_staged', data: <String, Object?>{
              'reason': '30m_window_closed',
            });
          }
        } else if (activeToken != token) {
          if (canServerSync) {
            await _saveFcmToken(cleanUid, token, settings.authorizationStatus.name).timeout(const Duration(seconds: 8));
            await _fcmRuntimeTokenCache.markActiveToken(uid: cleanUid, token: token, permissionStatus: settings.authorizationStatus.name);
            await _fcmRuntimeTokenCache.markServerSynced(cleanUid);
            ApkCrashForensics.log('fcm_token_changed_saved_30m_window');
          } else {
            await _fcmRuntimeTokenCache.stagePendingToken(uid: cleanUid, token: token, permissionStatus: settings.authorizationStatus.name);
            ApkCrashForensics.log('fcm_token_staged_next_30m_window');
          }
        } else {
          ApkCrashForensics.log('fcm_token_unchanged_no_write');
        }
      }
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((nextToken) {
        ApkCrashForensics.log('fcm_token_refresh_staged_next_30m_window');
        unawaited(_fcmRuntimeTokenCache.stagePendingToken(
          uid: cleanUid,
          token: nextToken,
          permissionStatus: settings.authorizationStatus.name,
        ));
      }, onError: (Object error, StackTrace stack) {
        ApkCrashForensics.recordError(error, stack, fatal: false, source: 'FirebaseMessaging.onTokenRefresh');
      });
      _attachForegroundFcmAlert();
      ApkCrashForensics.log('fcm_register_done');
    } catch (error, stack) {
      ApkCrashForensics.recordError(error, stack, fatal: false, source: 'registerFcmTokenForUser');
      debugPrint('FCM token registration failed: $error');
    }
  }


  static Future<void> _saveFcmToken(String uid, String token, [String permissionStatus = 'unknown']) async {
    ApkCrashForensics.log('fcm_token_save_start');
    final tokenId = token.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final ref = FirebaseFirestore.instance.collection('users').doc(uid).collection('fcmTokens').doc(tokenId);
    await ref.set(<String, Object?>{
      'token': token,
      'platform': 'android',
      'enabled': true,
      'permissionStatus': permissionStatus,
      'appPackage': 'com.example.test',
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      final snap = await ref.get();
      final data = snap.data();
      if (data == null || !data.containsKey('createdAt')) {
        await ref.set(<String, Object?>{'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
    } catch (_) {}
    ApkCrashForensics.log('fcm_token_save_done');
  }

  static bool _isRemoteAlertExpired(Map<String, dynamic> data) {
    final value = data['expiresAt'] ??
        data['visibleUntil'] ??
        data['hideAfter'] ??
        data['notificationExpiresAt'] ??
        data['ttlUntil'] ??
        data['validUntil'] ??
        data['expiresAtMillis'];
    if (value == null) return false;
    DateTime? expiresAt;
    if (value is num) {
      final raw = value.toInt();
      expiresAt = DateTime.fromMillisecondsSinceEpoch(raw < 10000000000 ? raw * 1000 : raw);
    } else {
      final text = value.toString().trim();
      final asInt = int.tryParse(text);
      if (asInt != null) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(asInt < 10000000000 ? asInt * 1000 : asInt);
      } else {
        expiresAt = DateTime.tryParse(text);
      }
    }
    if (expiresAt == null) return false;
    return !expiresAt.toLocal().isAfter(DateTime.now());
  }

  static void _attachForegroundFcmAlert() {
    if (_foregroundMessageSub != null) return;
    _foregroundMessageSub = FirebaseMessaging.onMessage.listen((message) async {
      if (_isRemoteAlertExpired(message.data)) {
        ApkCrashForensics.log('foreground_fcm_skipped_expired_notification');
        return;
      }
      final title = message.notification?.title ?? message.data['title']?.toString() ?? 'New work notification';
      final body = message.notification?.body ?? message.data['body']?.toString() ?? message.data['message']?.toString() ?? 'Open the app to review this update.';
      final notificationId = message.data['notificationId']?.toString() ?? message.data['id']?.toString();
      final notificationType = message.data['notificationType']?.toString() ?? message.data['type']?.toString() ?? 'general';
      final assistantVoice = await getAssistantVoiceEnabled() && ((message.data['assistantVoice']?.toString().toLowerCase() == 'true') || _isAssistantNotificationType(notificationType));
      final assistantText = message.data['assistantText']?.toString();
      final actionUrl = message.data['actionUrl']?.toString()
          ?? message.data['meetingUrl']?.toString()
          ?? message.data['meetLink']?.toString()
          ?? message.data['googleMeetUrl']?.toString()
          ?? message.data['whatsappUrl']?.toString()
          ?? message.data['joinUrl']?.toString()
          ?? message.data['url']?.toString();
      await showLoopingAlertPayload(
        title: title,
        message: body,
        soundName: await getPreferredAlertSound(),
        notificationId: notificationId,
        notificationType: notificationType,
        assistantVoice: assistantVoice,
        assistantText: assistantText,
        actionUrl: actionUrl,
        actionLabel: message.data['actionLabel']?.toString() ?? message.data['joinLabel']?.toString(),
        rejectLabel: message.data['rejectLabel']?.toString(),
        actionType: message.data['actionType']?.toString() ?? message.data['meetingProvider']?.toString(),
      );
    });
  }

}

/// Watches the signed-in user's private Firestore inbox and raises one native
/// Android urgent alert for each new unread notification.
class AndroidNotificationAlertWatcher extends ConsumerStatefulWidget {
  const AndroidNotificationAlertWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AndroidNotificationAlertWatcher> createState() => _AndroidNotificationAlertWatcherState();
}

class _AndroidNotificationAlertWatcherState extends ConsumerState<AndroidNotificationAlertWatcher> with WidgetsBindingObserver {
  final Set<String> _knownUnreadIds = <String>{};
  bool _bootstrappedUnreadSet = false;
  String? _activeAlertId;
  String? _registeredUid;
  bool _syncScheduled = false;
  String? _nativeWindowSeed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AndroidAlertNotificationService.initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ApkCrashForensics.log('app_lifecycle_state', data: <String, Object?>{'state': state.name});
    // FCM registration is intentionally not repeated on every resume.
    // It is a staged, once-per-session startup task so the UI does not trigger
    // delayed token writes while the employee is working.
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final unread = workspace.myNotifications.where((notification) => !notification.isRead).toList(growable: false);
    if (workspace.user.uid.isNotEmpty && workspace.user.uid != _registeredUid) {
      _registeredUid = workspace.user.uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AndroidAlertNotificationService.registerFcmTokenForUser(workspace.user.uid);
      });
    }
    _scheduleNativeWindowSync(workspace);
    _scheduleSync(unread);
    return widget.child;
  }


  void _scheduleNativeWindowSync(WorkspaceState workspace) {
    final config = workspace.effectiveNotificationDisplayConfig;
    final mode = _displayWindowMode(config);
    final days = _displayWindowInt(config, const <String>['displayWindowDays', 'notificationDisplayDays', 'visibleDays'], fallback: 31).clamp(1, 3660).toInt();
    final hours = _displayWindowInt(config, const <String>['displayWindowHours', 'notificationDisplayHours', 'visibleHours'], fallback: 24).clamp(1, 24 * 3660).toInt();
    final seed = '${workspace.user.uid}:$mode:$days:$hours';
    if (_nativeWindowSeed == seed) return;
    _nativeWindowSeed = seed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AndroidAlertNotificationService.setNotificationDisplayWindowPreference(mode: mode, days: days, hours: hours);
    });
  }

  static String _displayWindowMode(Map<String, dynamic> config) {
    final raw = (config['displayWindowMode'] ?? config['notificationDisplayWindowMode'] ?? config['notificationHistoryMode'] ?? config['visibleWindowMode'] ?? 'currentMonth').toString();
    final normalized = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    return switch (normalized) {
      'all' || 'forever' || 'unlimited' || 'none' => 'all',
      'customhours' || 'lasthours' || 'hours' || 'usersethours' => 'customHours',
      'customdays' || 'lastdays' || 'days' || 'usersetdays' || 'retentiondays' => 'customDays',
      _ => 'currentMonth',
    };
  }

  static int _displayWindowInt(Map<String, dynamic> config, List<String> keys, {required int fallback}) {
    for (final key in keys) {
      final value = config[key];
      if (value is int) return value;
      if (value is num) return value.round();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return fallback;
  }

  void _scheduleSync(List<AppNotification> unread) {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _syncUnread(unread);
    });
  }

  Future<void> _syncUnread(List<AppNotification> unread) async {
    final acceptedNativeIds = await AndroidAlertNotificationService.getAcceptedAlertIds();
    if (acceptedNativeIds.isNotEmpty) {
      final acceptedStillUnread = unread
          .where((notification) => acceptedNativeIds.contains(notification.notificationId))
          .map((notification) => notification.notificationId)
          .toList(growable: false);
      for (final notificationId in acceptedStillUnread) {
        ref.read(workspaceProvider.notifier).acceptNotificationAndStartWorkCounter(notificationId);
      }
      // Keep the native accepted cache bounded on Android. Do not clear it here;
      // it protects against duplicate ringing while Firestore read updates sync.
    }

    final acceptedTaskIds = await AndroidAlertNotificationService.getAcceptedTaskIds();
    if (acceptedTaskIds.isNotEmpty) {
      for (final taskId in acceptedTaskIds) {
        ref.read(workspaceProvider.notifier).startTaskWorkTimerFromNotification(taskId);
      }
      await AndroidAlertNotificationService.clearAcceptedTaskIds(acceptedTaskIds);
    }

    final effectiveUnread = unread.where((notification) => !acceptedNativeIds.contains(notification.notificationId)).toList(growable: false);
    final unreadIds = effectiveUnread.map((notification) => notification.notificationId).toSet();
    _knownUnreadIds.removeWhere((id) => !unreadIds.contains(id));

    if (!_bootstrappedUnreadSet) {
      // Existing unread docs from Firestore should not ring again every time the
      // employee opens the APK. New notifications after this first sync still
      // raise the native alert.
      _bootstrappedUnreadSet = true;
      _knownUnreadIds.addAll(unreadIds);
      return;
    }

    if (effectiveUnread.isEmpty) {
      _activeAlertId = null;
      await AndroidAlertNotificationService.cancelLoopingAlert();
      return;
    }

    if (_activeAlertId != null && !unreadIds.contains(_activeAlertId)) {
      _activeAlertId = null;
      await AndroidAlertNotificationService.cancelLoopingAlert();
    }

    final newUnread = effectiveUnread.where((notification) => !_knownUnreadIds.contains(notification.notificationId)).toList(growable: false);
    if (newUnread.isEmpty) return;

    // myNotifications is already newest-first in WorkspaceState. Sort again here
    // so this bridge stays correct even if the provider implementation changes.
    final sorted = [...newUnread]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final latest = sorted.first;
    _knownUnreadIds.addAll(newUnread.map((notification) => notification.notificationId));
    _activeAlertId = latest.notificationId;
    await AndroidAlertNotificationService.showLoopingAlert(latest);
  }
}
