import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/crash/crashlytics_sdk.dart';
import '../core/crash/apk_crash_forensics.dart';
import '../firebase_options.dart';

Future<void> runProjectWorkspaceApp({
  required Widget child,
  List<Override> overrides = const <Override>[],
}) async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // v124: Android figure-one edge-to-edge for the wireframe floating nav shell.
    // System bars stay visible for Android gestures/accessibility, but their
    // backgrounds are transparent so the app surface continues behind them.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    FlutterError.onError = (FlutterErrorDetails details) {
      ApkCrashForensics.recordError(details.exception, details.stack, fatal: true, source: 'FlutterError.onError');
      CrashlyticsSdk.recordFlutterError(details, fatal: true);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      ApkCrashForensics.recordError(error, stack, fatal: true, source: 'PlatformDispatcher.onError');
      CrashlyticsSdk.recordError(error, stack, fatal: true);
      return true;
    };

    ErrorWidget.builder = (FlutterErrorDetails details) => _StartupErrorSurface(
          title: 'Startup UI error caught',
          message: 'The app did not stay blank. Check the debug console for the exact Flutter error.',
          details: details.exceptionAsString(),
        );

    if (AppConfig.useFirebase) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
        } else {
          Firebase.app();
        }
        debugPrint('Firebase initialized for project: ${DefaultFirebaseOptions.currentPlatform.projectId}');
        await CrashlyticsSdk.initialize(entryPoint: child.runtimeType.toString());
        await ApkCrashForensics.initialize(entryPoint: child.runtimeType.toString());
      } catch (error, stack) {
        debugPrint('Firebase initialization failed: $error');
        debugPrintStack(stackTrace: stack);
        runApp(_StartupFailedApp(error: error));
        return;
      }
    } else {
      debugPrint('Running in demo mode because USE_FIREBASE=false.');
    }

    runApp(ProviderScope(overrides: overrides, child: child));
  }, (Object error, StackTrace stack) {
    ApkCrashForensics.recordError(error, stack, fatal: true, source: 'runZonedGuarded');
    CrashlyticsSdk.recordError(error, stack, fatal: true);
    runApp(_StartupFailedApp(error: error));
  });
}

class _StartupFailedApp extends StatelessWidget {
  const _StartupFailedApp({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _StartupErrorSurface(
        title: 'App startup failed',
        message: 'Firebase mode is active. The app will not silently skip login initialization or fall back to demo data.',
        details: '$error',
      ),
    );
  }
}

class _StartupErrorSurface extends StatelessWidget {
  const _StartupErrorSurface({required this.title, required this.message, required this.details});

  final String title;
  final String message;
  final String details;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8FAFC),
      child: Center(
        child: Container(
          width: 620,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 28, offset: Offset(0, 16))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 34),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              Text(message, style: const TextStyle(color: Color(0xFF475569), height: 1.4)),
              const SizedBox(height: 14),
              Text(
                details,
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 16),
              const Text(
                'For demo mode only, run with --dart-define=USE_FIREBASE=false',
                style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF334155)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
