import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../core/config/notification_backend_config.dart';

class OracleNotificationBackendService {
  OracleNotificationBackendService({
    FirebaseAuth? auth,
    http.Client? client,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client();

  final FirebaseAuth _auth;
  final http.Client _client;

  Future<void> resendNotification({
    required String companyId,
    required String notificationId,
    bool resetAttempts = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Admin authentication is required.');
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Could not obtain the Firebase ID token.');
    }

    final response = await _client
        .post(
          NotificationBackendConfig.endpoint(
            '/api/v1/notifications/$notificationId/resend',
          ),
          headers: <String, String>{
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'companyId': companyId,
            'resetAttempts': resetAttempts,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          detail = (decoded['error'] as String?) ?? detail;
        }
      } catch (_) {
        // Preserve the raw response for diagnostics.
      }
      throw StateError('Backend resend failed (${response.statusCode}): $detail');
    }
  }

  Future<bool> checkHealth() async {
    if (!NotificationBackendConfig.isConfigured) return false;
    try {
      final response = await _client
          .get(NotificationBackendConfig.endpoint('/health'))
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void close() => _client.close();
}
