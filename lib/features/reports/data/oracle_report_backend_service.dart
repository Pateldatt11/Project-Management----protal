import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/notification_backend_config.dart';
import '../../../data/models/monthly_analytics_snapshot.dart';

class OracleReportBackendService {
  OracleReportBackendService({
    FirebaseAuth? auth,
    http.Client? client,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _client = client ?? http.Client();

  final FirebaseAuth _auth;
  final http.Client _client;

  bool get canAttempt => NotificationBackendConfig.isConfigured || kDebugMode;

  Future<MonthlyAnalyticsSnapshot> rebuildMonthlyAnalytics({
    required String companyId,
    required String monthId,
    String? projectId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in before rebuilding monthly analytics.');
    final token = await user.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Could not obtain the Firebase authentication token.');
    }

    final endpoint = NotificationBackendConfig.isConfigured
        ? NotificationBackendConfig.endpoint('/api/v1/reports/monthly/rebuild')
        : Uri.parse('http://127.0.0.1:8080/api/v1/reports/monthly/rebuild');
    final response = await _client
        .post(
          endpoint,
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'companyId': companyId,
            'monthId': monthId,
            if ((projectId ?? '').trim().isNotEmpty) 'projectId': projectId!.trim(),
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var detail = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          detail = decoded['error']?.toString() ?? detail;
        }
      } catch (_) {
        // Preserve raw response for diagnostics.
      }
      throw StateError('Monthly analytics backend failed (${response.statusCode}): $detail');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backend response is not a JSON object.');
    }
    final rawSnapshot = decoded['snapshot'];
    if (rawSnapshot is! Map) {
      throw const FormatException('Backend response does not contain a snapshot.');
    }
    return MonthlyAnalyticsSnapshot.fromJson(
      rawSnapshot.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  void close() => _client.close();
}
