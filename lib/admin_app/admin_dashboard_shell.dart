import 'package:flutter/material.dart';

import '../app/app_shell.dart';

/// Admin dashboard shell wrapper kept in the admin_app code area.
/// Existing dashboard feature screens remain shared, but routing enters them through this fixed admin shell.
class AdminDashboardShell extends StatelessWidget {
  const AdminDashboardShell({super.key});

  @override
  Widget build(BuildContext context) => const AppShell();
}
