import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/android_alert_notification_service.dart';
import '../core/services/notification_service.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/tasks/presentation/tasks_screen.dart';
import 'app_theme.dart';

class ProjectManagementDashboardApp extends ConsumerWidget {
  const ProjectManagementDashboardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Project Management Dashboard',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      builder: (context, child) => AndroidNotificationAlertWatcher(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AuthGate(),
      onGenerateRoute: (settings) {
        final args = settings.arguments as Map<String, dynamic>?;

        switch (settings.name) {
          case '/notifications':
          case '/tasks':
          case '/task_details':
            return MaterialPageRoute(
              builder: (context) => const TasksScreen(),
              settings: settings,
            );
          default:
            return MaterialPageRoute(
              builder: (context) => const AuthGate(),
              settings: settings,
            );
        }
      },
    );
  }
}