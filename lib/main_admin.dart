// lib/admin_main.dart

import 'admin_app/admin_web_app.dart';
import 'app/app_bootstrap.dart';
import 'app/app_surface.dart';

Future<void> main() {
  return runProjectWorkspaceApp(
    child: const AdminWebApp(),
    overrides: [
      appSurfaceModeProvider.overrideWithValue(AppSurfaceMode.adminWeb),
    ],
  );
}