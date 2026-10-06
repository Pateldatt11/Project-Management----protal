import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/workspace_platform.dart';

/// Controls which product surface is running.
///
/// - [auto] keeps the existing single-entry behavior.
/// - [adminWeb] forces the fixed admin dashboard shell.
/// - [employeeMobile] forces the employee mobile shell where server-driven JSON UI is allowed.
enum AppSurfaceMode {
  auto,
  adminWeb,
  employeeMobile,
}

final appSurfaceModeProvider = Provider<AppSurfaceMode>((ref) => AppSurfaceMode.auto);

/// True only for the employee mobile runtime. Admin web can preview/publish JSON,
/// but admin screens must never be rendered from server JSON.
final useMobileServerDrivenUiProvider = Provider<bool>((ref) {
  final mode = ref.watch(appSurfaceModeProvider);
  return switch (mode) {
    AppSurfaceMode.employeeMobile => true,
    AppSurfaceMode.adminWeb => false,
    AppSurfaceMode.auto => WorkspacePlatform.isNativeMobileApp,
  };
});
