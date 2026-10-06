/// Web/admin-safe no-op implementation for APK forensic logging.
///
/// The real log file is Android/iOS only. Admin web can import the public
/// facade without loading dart:io or firebase_crashlytics.
class ApkCrashForensicsImpl {
  static Future<void> initialize({String entryPoint = 'unknown'}) async {}
  static void setScreen({String? tab, String? route}) {}
  static void log(String message, {Map<String, Object?> data = const <String, Object?>{}}) {}
  static void recordError(Object error, StackTrace? stack, {bool fatal = false, String source = 'unknown'}) {}
  static int get uptimeSeconds => 0;
  static String get lastLocation => 'web/admin';
  static Future<String> readLog() async => 'APK diagnostic log is available only inside Android/iOS APK builds.';
  static Future<void> copyLogToClipboard() async {}
  static Future<void> clearLog() async {}
}
