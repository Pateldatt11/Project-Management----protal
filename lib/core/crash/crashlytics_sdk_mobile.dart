import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get isCrashlyticsSupported {
  if (kIsWeb || Firebase.apps.isEmpty) return false;
  try {
    return Platform.isAndroid || Platform.isIOS;
  } catch (_) {
    return false;
  }
}

Future<void> initializeCrashlytics({String? entryPoint}) async {
  if (!isCrashlyticsSupported) return;
  try {
    final crashlytics = FirebaseCrashlytics.instance;

    // APK/mobile only. Do not call this from admin web.
    await crashlytics.setCrashlyticsCollectionEnabled(true);

    await crashlytics.setCustomKey('flutter_entry_point', entryPoint ?? 'unknown');
    await crashlytics.setCustomKey('flutter_k_debug_mode', kDebugMode);
    await crashlytics.setCustomKey('flutter_k_profile_mode', kProfileMode);
    await crashlytics.setCustomKey('flutter_k_release_mode', kReleaseMode);
    crashlytics.log('Crashlytics SDK initialized');
  } catch (error, stack) {
    debugPrint('Crashlytics initialization skipped: $error');
    debugPrintStack(stackTrace: stack);
  }
}

void logCrashlytics(String message) {
  if (!isCrashlyticsSupported) return;
  try {
    FirebaseCrashlytics.instance.log(message);
  } catch (_) {
    // Do not let logging crash the app.
  }
}

Future<void> setCrashlyticsKey(String key, Object value) async {
  if (!isCrashlyticsSupported) return;
  try {
    await FirebaseCrashlytics.instance.setCustomKey(key, value);
  } catch (_) {
    // Best-effort diagnostics only.
  }
}

Future<void> setCrashlyticsUserId(String userId) async {
  if (!isCrashlyticsSupported) return;
  try {
    await FirebaseCrashlytics.instance.setUserIdentifier(userId);
  } catch (_) {
    // Best-effort diagnostics only.
  }
}

Future<void> triggerCrashlyticsTestCrash({String source = 'manual_test'}) async {
  if (!isCrashlyticsSupported) {
    throw StateError('Crashlytics is available only on Android/iOS Firebase builds.');
  }
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(true);
  await crashlytics.setCustomKey('manual_test_crash', true);
  await crashlytics.setCustomKey('manual_test_source', source);
  await crashlytics.setCustomKey('manual_test_started_at', DateTime.now().toIso8601String());
  crashlytics.log('Manual Crashlytics test crash requested from $source');
  crashlytics.crash();
}

Future<void> recordCrashlyticsFlutterError(FlutterErrorDetails details, {required bool fatal}) async {
  if (!isCrashlyticsSupported) return;
  try {
    if (fatal) {
      await FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    } else {
      await FirebaseCrashlytics.instance.recordFlutterError(details);
    }
  } catch (_) {
    // Never crash while reporting a crash.
  }
}

Future<void> recordCrashlyticsError(Object error, StackTrace stack, {required bool fatal}) async {
  if (!isCrashlyticsSupported) return;
  try {
    await FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
  } catch (_) {
    // Never crash while reporting a crash.
  }
}
