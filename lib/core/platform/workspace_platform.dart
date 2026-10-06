import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Centralized platform detector for the shared codebase.
///
/// The project now uses one Flutter/Firebase codebase for both surfaces:
/// - Web/desktop browser: management dashboard experience.
/// - Android/iOS app: employee-first workspace experience.
class WorkspacePlatform {
  const WorkspacePlatform._();

  static bool get isWeb => kIsWeb;

  static bool get isAndroidApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isIosApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isNativeMobileApp => isAndroidApp || isIosApp;

  static bool get isDesktopApp => !kIsWeb && <TargetPlatform>{
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);

  static bool isCompactScreen(BuildContext context) => MediaQuery.sizeOf(context).width < 760;

  static String get surfaceLabel {
    if (isWeb) return 'Web dashboard';
    if (isAndroidApp) return 'Android app';
    if (isIosApp) return 'iOS app';
    if (isDesktopApp) return 'Desktop app';
    return 'Flutter app';
  }

  static String get surfaceValue {
    if (isWeb) return 'web';
    if (isAndroidApp) return 'android';
    if (isIosApp) return 'ios';
    if (isDesktopApp) return 'desktop';
    return 'unknown';
  }
}
