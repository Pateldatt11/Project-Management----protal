import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'crashlytics_sdk.dart';

/// APK-only local forensic logger.
///
/// This does not write to Firestore and does not add any admin dashboard page.
/// It keeps a small local text log in the app cache directory so QA can copy it
/// from the Profile screen when Crashlytics does not create a real fatal issue
/// for process kills, ANRs, OEM kills, or silent blank-screen failures.
class ApkCrashForensicsImpl {
  ApkCrashForensicsImpl._();

  static final DateTime _startedAt = DateTime.now();
  static Timer? _heartbeatTimer;
  static String _lastTab = 'unknown';
  static String _lastRoute = 'unknown';
  static String _lastAction = 'startup';
  static String _lastScreenLog = '';
  static bool _initialized = false;

  static File get _logFile => File('${Directory.systemTemp.path}/management_dashboard_apk_forensics.log');

  static Future<void> initialize({String entryPoint = 'unknown'}) async {
    if (kIsWeb || _initialized) return;
    _initialized = true;
    await _append('APP_START entry=$entryPoint debug=$kDebugMode profile=$kProfileMode release=$kReleaseMode');
    await _setCrashlyticsKeys(<String, Object>{
      'forensics_enabled': true,
      'forensics_entry_point': entryPoint,
      'forensics_started_at': _startedAt.toIso8601String(),
      'forensics_log_available_in_profile': true,
    });
    _startHeartbeat();
  }

  static void setScreen({String? tab, String? route}) {
    final nextTab = tab != null && tab.trim().isNotEmpty ? tab.trim() : _lastTab;
    final nextRoute = route != null && route.trim().isNotEmpty ? route.trim() : _lastRoute;
    final signature = '$nextTab|$nextRoute';
    _lastTab = nextTab;
    _lastRoute = nextRoute;
    if (_lastScreenLog == signature) return;
    _lastScreenLog = signature;
    _lastAction = 'screen:$lastLocation';
    unawaited(_append('SCREEN tab=$_lastTab route=$_lastRoute'));
    unawaited(_setCrashlyticsKeys(<String, Object>{
      'forensics_last_tab': _lastTab,
      'forensics_last_route': _lastRoute,
      'forensics_last_action': _lastAction,
      'forensics_uptime_sec': uptimeSeconds,
    }));
  }

  static void log(String message, {Map<String, Object?> data = const <String, Object?>{}}) {
    final suffix = data.isEmpty ? '' : ' ${data.entries.map((entry) => '${entry.key}=${entry.value}').join(' ')}';
    _lastAction = message;
    unawaited(_append('EVENT $message$suffix'));
    unawaited(_setCrashlyticsKeys(<String, Object>{
      'forensics_last_action': _lastAction,
      'forensics_uptime_sec': uptimeSeconds,
    }));
    try {
      CrashlyticsSdk.log('FORensics $message$suffix');
    } catch (_) {
      // Crashlytics may not be ready in demo/startup mode.
    }
  }

  static void recordError(Object error, StackTrace? stack, {bool fatal = false, String source = 'unknown'}) {
    _lastAction = 'error:$source';
    unawaited(_append('ERROR source=$source fatal=$fatal error=$error\n${stack ?? ''}'));
    unawaited(_setCrashlyticsKeys(<String, Object>{
      'forensics_last_error_source': source,
      'forensics_last_error': _short(error.toString(), 180),
      'forensics_last_action': _lastAction,
      'forensics_uptime_sec': uptimeSeconds,
    }));
  }

  static int get uptimeSeconds => DateTime.now().difference(_startedAt).inSeconds;
  static String get lastLocation => 'tab=$_lastTab route=$_lastRoute';

  static Future<String> readLog() async {
    if (kIsWeb) return 'APK forensic log is available only on Android/iOS builds.';
    try {
      if (!await _logFile.exists()) {
        return 'No local APK forensic log found yet. Open the app, reproduce the crash/blank screen, reopen the app, then copy again.';
      }
      final text = await _logFile.readAsString();
      if (text.trim().isEmpty) return 'Local APK forensic log is empty.';
      const maxChars = 18000;
      return text.length <= maxChars ? text : text.substring(text.length - maxChars);
    } catch (error, stack) {
      return 'Failed to read APK forensic log: $error\n$stack';
    }
  }

  static Future<void> copyLogToClipboard() async {
    final text = await readLog();
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<void> clearLog() async {
    if (kIsWeb) return;
    try {
      if (await _logFile.exists()) await _logFile.delete();
      await _append('LOG_CLEARED_AND_RESTARTED');
    } catch (_) {
      // Best-effort only.
    }
  }

  static void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final rssMb = _safeRssMb();
      unawaited(_append('HEARTBEAT uptime=${uptimeSeconds}s $_lastAction $lastLocation rssMb=$rssMb'));
      unawaited(_setCrashlyticsKeys(<String, Object>{
        'forensics_uptime_sec': uptimeSeconds,
        'forensics_last_tab': _lastTab,
        'forensics_last_route': _lastRoute,
        'forensics_last_action': _lastAction,
        'forensics_rss_mb': rssMb,
      }));
    });
  }

  static Future<void> _append(String line) async {
    if (kIsWeb) return;
    try {
      final timestamp = DateTime.now().toIso8601String();
      final file = _logFile;
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      final currentLength = await file.length();
      if (currentLength > 240000) {
        final current = await file.readAsString();
        final tail = current.length > 120000 ? current.substring(current.length - 120000) : current;
        await file.writeAsString('--- log trimmed at $timestamp ---\n$tail', flush: true);
      }
      await file.writeAsString('[$timestamp] $line\n', mode: FileMode.append, flush: true);
    } catch (error) {
      debugPrint('Forensic log write failed: $error');
    }
  }

  static Future<void> _setCrashlyticsKeys(Map<String, Object> keys) async {
    try {
      for (final entry in keys.entries) {
        await CrashlyticsSdk.setKey(entry.key, entry.value);
      }
    } catch (_) {
      // Do not let diagnostics create new crashes.
    }
  }

  static int _safeRssMb() {
    try {
      return (ProcessInfo.currentRss / (1024 * 1024)).round();
    } catch (_) {
      return -1;
    }
  }

  static String _short(String value, int max) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}…';
  }
}
