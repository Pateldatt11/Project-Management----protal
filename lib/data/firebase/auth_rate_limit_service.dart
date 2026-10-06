import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthRateLimitConfig {
  const AuthRateLimitConfig({
    required this.enabled,
    required this.useCloudFunctions,
    required this.localFallback,
    required this.maxLoginFailures,
    required this.maxSignupFailures,
    required this.maxResetRequests,
    required this.windowMinutes,
    required this.lockoutMinutes,
    required this.maxLockoutMinutes,
    required this.genericAuthErrors,
    required this.lockedMessage,
  });

  final bool enabled;
  final bool useCloudFunctions;
  final bool localFallback;
  final int maxLoginFailures;
  final int maxSignupFailures;
  final int maxResetRequests;
  final int windowMinutes;
  final int lockoutMinutes;
  final int maxLockoutMinutes;
  final bool genericAuthErrors;
  final String lockedMessage;

  static const AuthRateLimitConfig defaults = AuthRateLimitConfig(
    enabled: true,
    useCloudFunctions: true,
    localFallback: true,
    maxLoginFailures: 5,
    maxSignupFailures: 3,
    maxResetRequests: 3,
    windowMinutes: 15,
    lockoutMinutes: 15,
    maxLockoutMinutes: 60,
    genericAuthErrors: true,
    lockedMessage: 'Too many attempts. Please wait and try again.',
  );

  factory AuthRateLimitConfig.fromAuthUiPolicy(Map<String, dynamic> raw) {
    final security = _readMap(raw['bruteForceProtection'] ?? raw['authSecurityPolicy'] ?? raw['security']);
    if (security.isEmpty) return defaults;
    return AuthRateLimitConfig(
      enabled: _bool(security['enabled'], defaults.enabled),
      useCloudFunctions: _bool(security['useCloudFunctions'], defaults.useCloudFunctions),
      localFallback: _bool(security['localFallback'], defaults.localFallback),
      maxLoginFailures: _positiveInt(security['maxLoginFailures'], defaults.maxLoginFailures),
      maxSignupFailures: _positiveInt(security['maxSignupFailures'], defaults.maxSignupFailures),
      maxResetRequests: _positiveInt(security['maxResetRequests'], defaults.maxResetRequests),
      windowMinutes: _positiveInt(security['windowMinutes'], defaults.windowMinutes),
      lockoutMinutes: _positiveInt(security['lockoutMinutes'], defaults.lockoutMinutes),
      maxLockoutMinutes: _positiveInt(security['maxLockoutMinutes'], defaults.maxLockoutMinutes),
      genericAuthErrors: _bool(security['genericAuthErrors'], defaults.genericAuthErrors),
      lockedMessage: _string(security['lockedMessage'], defaults.lockedMessage),
    );
  }

  Map<String, dynamic> toFunctionPayload() => <String, dynamic>{
        'maxLoginFailures': maxLoginFailures,
        'maxSignupFailures': maxSignupFailures,
        'maxResetRequests': maxResetRequests,
        'windowMinutes': windowMinutes,
        'lockoutMinutes': lockoutMinutes,
        'maxLockoutMinutes': maxLockoutMinutes,
      };

  int maxFailuresFor(String action) {
    switch (action.trim().toLowerCase()) {
      case 'signup':
      case 'register':
        return maxSignupFailures;
      case 'passwordreset':
      case 'password_reset':
      case 'reset':
        return maxResetRequests;
      case 'login':
      case 'signin':
      default:
        return maxLoginFailures;
    }
  }

  static Map<String, dynamic> _readMap(dynamic value) {
    if (value is Map) return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    return const <String, dynamic>{};
  }

  static bool _bool(dynamic value, bool fallback) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final raw = value?.toString().trim().toLowerCase();
    if (raw == 'true' || raw == '1' || raw == 'yes' || raw == 'enabled') return true;
    if (raw == 'false' || raw == '0' || raw == 'no' || raw == 'disabled') return false;
    return fallback;
  }

  static int _positiveInt(dynamic value, int fallback) {
    final parsed = value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) return fallback;
    return parsed;
  }

  static String _string(dynamic value, String fallback) {
    final raw = value?.toString().trim();
    return raw == null || raw.isEmpty ? fallback : raw;
  }
}

class AuthRateLimitService {
  AuthRateLimitService({
    FirebaseFunctions? functions,
    this.config = AuthRateLimitConfig.defaults,
  }) : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;
  final AuthRateLimitConfig config;

  static final Map<String, _LocalAttemptBucket> _localBuckets = <String, _LocalAttemptBucket>{};

  Future<void> check({required String email, required String action}) async {
    if (!config.enabled) return;
    final identifier = _normalizeIdentifier(email);
    if (identifier.isEmpty) return;

    if (config.localFallback) _checkLocal(identifier: identifier, action: action);
    if (!config.useCloudFunctions) return;

    try {
      await _functions.httpsCallable('checkAuthRateLimit').call(<String, dynamic>{
        'email': identifier,
        'action': action,
        'policy': config.toFunctionPayload(),
      });
    } on FirebaseFunctionsException catch (error) {
      if (_isRateLimited(error)) {
        throw _rateLimitException(_messageFromDetails(error.details) ?? error.message ?? config.lockedMessage);
      }
      // Do not block production login if the function is not deployed yet.
      if (!_isFunctionUnavailable(error)) rethrow;
    }
  }

  Future<void> recordSuccess({required String email, required String action}) async {
    if (!config.enabled) return;
    final identifier = _normalizeIdentifier(email);
    if (identifier.isEmpty) return;
    _clearLocal(identifier: identifier, action: action);
    await _recordCloud(identifier: identifier, action: action, success: true);
  }

  Future<void> recordFailure({required String email, required String action, Object? error}) async {
    if (!config.enabled) return;
    final identifier = _normalizeIdentifier(email);
    if (identifier.isEmpty) return;
    if (config.localFallback) _recordLocalFailure(identifier: identifier, action: action);
    await _recordCloud(
      identifier: identifier,
      action: action,
      success: false,
      errorCode: error is FirebaseAuthException ? error.code : error.runtimeType.toString(),
    );
  }

  Future<void> _recordCloud({required String identifier, required String action, required bool success, String? errorCode}) async {
    if (!config.useCloudFunctions) return;
    try {
      await _functions.httpsCallable('recordAuthAttempt').call(<String, dynamic>{
        'email': identifier,
        'action': action,
        'success': success,
        'errorCode': errorCode ?? '',
        'policy': config.toFunctionPayload(),
      });
    } on FirebaseFunctionsException catch (error) {
      if (_isRateLimited(error)) {
        throw _rateLimitException(_messageFromDetails(error.details) ?? error.message ?? config.lockedMessage);
      }
      if (!_isFunctionUnavailable(error)) rethrow;
    }
  }

  void _checkLocal({required String identifier, required String action}) {
    final key = _localKey(identifier, action);
    final bucket = _localBuckets[key];
    if (bucket == null) return;
    final now = DateTime.now();
    final lockedUntil = bucket.lockedUntil;
    if (lockedUntil != null && lockedUntil.isAfter(now)) {
      throw _rateLimitException(_lockedMessage(lockedUntil));
    }
    if (now.difference(bucket.windowStart).inMinutes >= config.windowMinutes) {
      _localBuckets.remove(key);
    }
  }

  void _recordLocalFailure({required String identifier, required String action}) {
    final key = _localKey(identifier, action);
    final now = DateTime.now();
    final existing = _localBuckets[key];
    final maxFailures = config.maxFailuresFor(action);
    final bucket = existing == null || now.difference(existing.windowStart).inMinutes >= config.windowMinutes
        ? _LocalAttemptBucket(windowStart: now, failures: 1)
        : existing.copyWith(failures: existing.failures + 1);
    if (bucket.failures >= maxFailures) {
      final lockMultiplier = math.max(1, ((bucket.failures - maxFailures) ~/ maxFailures) + 1);
      final minutes = math.min(config.maxLockoutMinutes, config.lockoutMinutes * lockMultiplier);
      _localBuckets[key] = bucket.copyWith(lockedUntil: now.add(Duration(minutes: minutes)));
    } else {
      _localBuckets[key] = bucket;
    }
  }

  void _clearLocal({required String identifier, required String action}) {
    _localBuckets.remove(_localKey(identifier, action));
  }

  String _lockedMessage(DateTime lockedUntil) {
    final seconds = math.max(1, lockedUntil.difference(DateTime.now()).inSeconds);
    final minutes = (seconds / 60).ceil();
    return '${config.lockedMessage} Try again in ${minutes}m.';
  }

  static FirebaseAuthException _rateLimitException(String message) {
    return FirebaseAuthException(code: 'too-many-requests', message: message);
  }

  static String _normalizeIdentifier(String value) => value.trim().toLowerCase();

  static String _localKey(String identifier, String action) => '${action.trim().toLowerCase()}::$identifier';

  static bool _isRateLimited(FirebaseFunctionsException error) {
    return error.code == 'resource-exhausted' || error.code == 'failed-precondition';
  }

  static bool _isFunctionUnavailable(FirebaseFunctionsException error) {
    return error.code == 'not-found' || error.code == 'unavailable' || error.code == 'internal' || error.code == 'unknown';
  }

  static String? _messageFromDetails(dynamic details) {
    if (details is Map && details['message'] != null) return details['message'].toString();
    return null;
  }
}

class _LocalAttemptBucket {
  const _LocalAttemptBucket({required this.windowStart, required this.failures, this.lockedUntil});

  final DateTime windowStart;
  final int failures;
  final DateTime? lockedUntil;

  _LocalAttemptBucket copyWith({DateTime? windowStart, int? failures, DateTime? lockedUntil}) {
    return _LocalAttemptBucket(
      windowStart: windowStart ?? this.windowStart,
      failures: failures ?? this.failures,
      lockedUntil: lockedUntil ?? this.lockedUntil,
    );
  }
}
