import 'apk_crash_forensics_stub.dart'
    if (dart.library.io) 'apk_crash_forensics_io.dart' as impl;

/// Public APK forensic logger facade.
///
/// Safe for admin web because the dart:io implementation is only imported on
/// mobile/native builds. Web/admin receives a no-op implementation.
class ApkCrashForensics {
  ApkCrashForensics._();

  static Future<void> initialize({String entryPoint = 'unknown'}) =>
      impl.ApkCrashForensicsImpl.initialize(entryPoint: entryPoint);

  static void setScreen({String? tab, String? route}) =>
      impl.ApkCrashForensicsImpl.setScreen(tab: tab, route: route);

  static void log(String message, {Map<String, Object?> data = const <String, Object?>{}}) =>
      impl.ApkCrashForensicsImpl.log(message, data: data);

  static void recordError(Object error, StackTrace? stack, {bool fatal = false, String source = 'unknown'}) =>
      impl.ApkCrashForensicsImpl.recordError(error, stack, fatal: fatal, source: source);

  static int get uptimeSeconds => impl.ApkCrashForensicsImpl.uptimeSeconds;

  static String get lastLocation => impl.ApkCrashForensicsImpl.lastLocation;

  static Future<String> readLog() => impl.ApkCrashForensicsImpl.readLog();

  static Future<void> copyLogToClipboard() => impl.ApkCrashForensicsImpl.copyLogToClipboard();

  static Future<void> clearLog() => impl.ApkCrashForensicsImpl.clearLog();
}
