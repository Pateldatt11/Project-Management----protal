import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'employee_mobile_theme.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../core/platform/android_alert_notification_service.dart';

/// Employee mobile product surface.
///
/// This is the only runtime surface where server-driven JSON UI is allowed to affect app screens.
class EmployeeMobileApp extends ConsumerWidget {
  const EmployeeMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Project Management Employee App',
      theme: EmployeeMobileTheme.light,
      themeMode: ThemeMode.light,
      builder: (context, child) => AndroidNotificationAlertWatcher(child: child ?? const SizedBox.shrink()),
      home: const AuthGate(),
    );
  }
}
