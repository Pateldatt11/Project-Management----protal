import 'package:flutter/material.dart';

bool get isCrashlyticsSupported => false;

Future<void> initializeCrashlytics({String? entryPoint}) async {}

void logCrashlytics(String message) {}

Future<void> setCrashlyticsKey(String key, Object value) async {}

Future<void> setCrashlyticsUserId(String userId) async {}

Future<void> triggerCrashlyticsTestCrash({String source = 'manual_test'}) async {
  throw StateError('Crashlytics is available only on Android/iOS builds.');
}

Future<void> recordCrashlyticsFlutterError(FlutterErrorDetails details, {required bool fatal}) async {}

Future<void> recordCrashlyticsError(Object error, StackTrace stack, {required bool fatal}) async {}
