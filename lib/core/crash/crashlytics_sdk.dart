import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'crashlytics_sdk_platform.dart'
    if (dart.library.io) 'crashlytics_sdk_mobile.dart' as platform;

/// Mobile-only Crashlytics facade.
///
/// This file is safe for admin web because it never imports the real
/// firebase_crashlytics package on web. Android/iOS use the mobile
/// implementation through the conditional import above.
class CrashlyticsSdk {
  const CrashlyticsSdk._();

  static bool get isSupported => platform.isCrashlyticsSupported;

  static Future<void> initialize({String? entryPoint}) async {
    await platform.initializeCrashlytics(entryPoint: entryPoint);
  }

  static void recordFlutterError(FlutterErrorDetails details, {bool fatal = true}) {
    FlutterError.presentError(details);
    debugPrint('Flutter framework error: ${details.exceptionAsString()}');
    if (details.stack != null) debugPrintStack(stackTrace: details.stack);

    if (!isSupported) return;
    unawaited(platform.recordCrashlyticsFlutterError(details, fatal: fatal));
  }

  static void recordError(Object error, StackTrace stack, {bool fatal = true}) {
    debugPrint('Uncaught error: $error');
    debugPrintStack(stackTrace: stack);

    if (!isSupported) return;
    unawaited(platform.recordCrashlyticsError(error, stack, fatal: fatal));
  }

  static void log(String message) {
    debugPrint(message);
    if (!isSupported) return;
    platform.logCrashlytics(message);
  }

  static Future<void> setKey(String key, Object value) async {
    if (!isSupported) return;
    await platform.setCrashlyticsKey(key, value);
  }

  static Future<void> setUserId(String userId) async {
    if (!isSupported) return;
    await platform.setCrashlyticsUserId(userId);
  }

  /// Intentionally crashes the app so QA can verify Firebase Crashlytics wiring.
  /// Hidden/disabled on web. Android/iOS only.
  static Future<void> triggerTestCrash({String source = 'manual_test'}) async {
    await platform.triggerCrashlyticsTestCrash(source: source);
  }
}
