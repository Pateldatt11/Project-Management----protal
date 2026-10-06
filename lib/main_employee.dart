import 'app/app_bootstrap.dart';
import 'app/app_surface.dart';
import 'employee_app/employee_mobile_app.dart';

Future<void> main() {
  return runProjectWorkspaceApp(
    child: const EmployeeMobileApp(),
    overrides: [
      appSurfaceModeProvider.overrideWithValue(AppSurfaceMode.employeeMobile),
    ],
  );
}
