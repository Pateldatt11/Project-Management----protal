import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_theme.dart';
import '../features/home/presentation/public_web_home_screen.dart';

/// Fixed web/admin product surface.
///
/// This surface never renders its own dashboard screens from server JSON.
/// It can still edit, import, preview, and publish employee-mobile JSON designs.
class AdminWebApp extends ConsumerWidget {
  const AdminWebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Project Management Admin Dashboard',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      builder: (context, child) => child ?? const SizedBox.shrink(),
      home: const PublicWebHomeScreen(adminPortal: true),
    );
  }
}
