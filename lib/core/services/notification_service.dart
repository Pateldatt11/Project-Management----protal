import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  /// Global navigator key for routing when notification is clicked
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Default OneSignal App ID fallback
  static const String defaultAppId = 'e2475e54-448e-4067-9ceb-08cb4b8ff968';

  /// Check if the current platform supports native OneSignal plugin channels
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Initialize OneSignal with configuration and listeners
  static Future<void> initialize({String appId = defaultAppId}) async {
    if (!isSupportedPlatform) {
      debugPrint('[OneSignal] Skipping initialization: Platform not supported.');
      return;
    }

    if (kDebugMode) {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    } else {
      OneSignal.Debug.setLogLevel(OSLogLevel.none);
    }

    OneSignal.initialize(appId);
    await requestPermission();

    _setupForegroundListener();
    _setupClickListener();
  }

  /// Request Notification Permissions (Android 13+ & iOS)
  static Future<bool> requestPermission() async {
    if (!isSupportedPlatform) return false;
    try {
      final granted = await OneSignal.Notifications.requestPermission(true);
      debugPrint('[OneSignal] Notification Permission Granted: $granted');
      return granted;
    } catch (e) {
      debugPrint('[OneSignal] Error requesting permission: $e');
      return false;
    }
  }

  /// Handle notifications received when the app is in the FOREGROUND
  static void _setupForegroundListener() {
    if (!isSupportedPlatform) return;
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      debugPrint('[OneSignal] Foreground Notification: ${event.notification.title}');
      
      // Displays the floating heads-up banner on screen even when app is open
      event.notification.display();
    });
  }

  /// Handle notification CLICK / TAP events (Routing & Deep Linking)
  static void _setupClickListener() {
    if (!isSupportedPlatform) return;
    OneSignal.Notifications.addClickListener((event) {
      final notification = event.notification;
      final Map<String, dynamic>? data = notification.additionalData;

      debugPrint('[OneSignal] Notification Clicked: ${notification.title}');
      if (data != null) {
        _handlePayloadNavigation(data);
      }
    });
  }

  /// Route user to a specific screen based on payload
  static void _handlePayloadNavigation(Map<String, dynamic> data) {
    final String? route = data['route'] as String?;
    if (route == null || route.isEmpty) {
      debugPrint('[OneSignal] No route found in notification payload.');
      return;
    }

    final String? taskId = data['taskId'] as String? ?? data['task_id'] as String?;
    final String? projectId = data['projectId'] as String? ?? data['project_id'] as String?;
    final String? type = data['type'] as String?;

    void navigate() {
      navigatorKey.currentState?.pushNamed(
        route,
        arguments: {
          'taskId': taskId,
          'projectId': projectId,
          'type': type,
          'data': data,
        },
      );
    }

    // Ensure the navigator is fully attached before routing (handles cold start launches)
    if (navigatorKey.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
    } else {
      navigate();
    }
  }

  // =========================================================================
  // USER IDENTIFICATION & TARGETING METHODS
  // =========================================================================

  /// Link user identity after authentication
  static void setExternalUserId(String userId) {
    if (!isSupportedPlatform || userId.trim().isEmpty) return;
    OneSignal.login(userId.trim());
    debugPrint('[OneSignal] Logged in user: $userId');
  }

  /// Unlink user identity on logout
  static void logoutUser() {
    if (!isSupportedPlatform) return;
    OneSignal.logout();
    debugPrint('[OneSignal] Logged out user');
  }

  /// Alias for backward compatibility
  static void logoutExternalUserId() => logoutUser();

  /// Add a custom tag (e.g., role: "admin", team: "dev")
  static void addTag(String key, String value) {
    if (!isSupportedPlatform || key.isEmpty) return;
    OneSignal.User.addTagWithKey(key, value);
  }

  /// Add multiple custom tags at once
  static void addTags(Map<String, String> tags) {
    if (!isSupportedPlatform || tags.isEmpty) return;
    OneSignal.User.addTags(tags);
  }

  /// Remove a tag
  static void removeTag(String key) {
    if (!isSupportedPlatform || key.isEmpty) return;
    OneSignal.User.removeTag(key);
  }

  /// Remove multiple tags
  static void removeTags(List<String> tagKeys) {
    if (!isSupportedPlatform || tagKeys.isEmpty) return;
    OneSignal.User.removeTags(tagKeys);
  }

  /// Get current User-level OneSignal ID
  static Future<String?> getOneSignalId() async {
    if (!isSupportedPlatform) return null;
    return await OneSignal.User.getOnesignalId();
  }

  /// Get current device Push Subscription ID
  static String? getSubscriptionId() {
    if (!isSupportedPlatform) return null;
    return OneSignal.User.pushSubscription.id;
  }

  /// Get current device Push Token
  static String? getPushToken() {
    if (!isSupportedPlatform) return null;
    return OneSignal.User.pushSubscription.token;
  }
}