import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OneSignalApiService {
  const OneSignalApiService._();

  static const String _notificationApiUrl = '/api/send-notification';

  /// Send targeted push notification to specific user UIDs (external_id)
  /// Includes action buttons ('Reply' & 'View Task') and UI accent branding
  static Future<bool> sendPushToUsers({
    required List<String> recipientUids,
    required String title,
    required String message,
    Map<String, dynamic>? additionalData,
  }) async {
    if (recipientUids.isEmpty) return false;

    // Filter out empty or whitespace UIDs
    final cleanUids = recipientUids
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty)
        .toList();

    if (cleanUids.isEmpty) return false;

    try {
      final payload = {
        'include_aliases': {
          'external_id': cleanUids,
        },
        'target_channel': 'push',
        'headings': {'en': title},
        'contents': {'en': message},
        'data': additionalData ?? {},
        'android_accent_color': 'FF2563EB',
        'small_icon': 'ic_stat_onesignal_default',
        // Action buttons matching the notification live preview
        'buttons': [
          {'id': 'reply_action', 'text': 'Reply', 'icon': 'ic_menu_send'},
          {'id': 'view_task_action', 'text': 'View Task', 'icon': 'ic_menu_view'},
        ],
      };

      final response = await http.post(
        _resolveUri(_notificationApiUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[OneSignal REST] Push sent successfully: ${response.body}');
        return true;
      } else {
        debugPrint('[OneSignal REST] Error: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[OneSignal REST] Exception sending push: $e');
      return false;
    }
  }

  static Uri _resolveUri(String url) {
    final parsed = Uri.parse(url);
    return parsed.hasScheme ? parsed : Uri.base.resolve(url);
  }
}