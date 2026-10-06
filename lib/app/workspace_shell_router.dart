import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/constants/app_enums.dart';
import '../core/permissions/permission_service.dart';
import '../core/platform/workspace_platform.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../admin_app/admin_dashboard_shell.dart';
import '../employee_app/employee_mobile_shell.dart';
import '../features/settings/presentation/super_admin_company_setup_screen.dart';
import 'app_surface.dart';
import 'workspace_state.dart';

class WorkspaceShellRouter extends ConsumerWidget {
  const WorkspaceShellRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final member = state.currentMember;

    if (state.company.companyId == 'platform' && member.role == UserRole.superAdmin) {
      return const SuperAdminCompanySetupScreen();
    }

    final surfaceMode = ref.watch(appSurfaceModeProvider);

    if (surfaceMode == AppSurfaceMode.adminWeb) {
      return const AdminDashboardShell();
    }

    if (surfaceMode == AppSurfaceMode.employeeMobile) {
      if (PermissionService.isAdminDashboardRole(member)) {
        return const AdminWebOnlyScreen();
      }
      return const EmployeeMobileShell();
    }

    // Auto mode keeps the original shared app behavior:
    // native Android/iOS opens the employee mobile shell; web/desktop opens the admin dashboard.
    if (WorkspacePlatform.isNativeMobileApp && PermissionService.isAdminDashboardRole(member)) {
      return const AdminWebOnlyScreen();
    }

    if (PermissionService.shouldUseEmployeeWorkspace(member)) {
      return const EmployeeMobileShell();
    }

    return const AdminDashboardShell();
  }
}

class AdminWebOnlyScreen extends ConsumerWidget {
  const AdminWebOnlyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceProvider);
    final member = state.currentMember;
    return Scaffold(
      body: Center(
        child: Container(
          width: 620,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 28, offset: Offset(0, 16))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF2563EB), size: 42),
              const SizedBox(height: 16),
              const Text('Admin dashboard is web-only', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              Text(
                '${member.role.label} is a management/admin role. For security and better controls, open the web dashboard in a browser. The Android/iOS app surface is reserved for employees and contributors.',
                style: const TextStyle(color: Color(0xFF475569), height: 1.45, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  Chip(label: Text('Signed in: ${state.user.email}')),
                  Chip(label: Text(WorkspacePlatform.surfaceLabel)),
                  Chip(label: Text(member.role.label)),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      ref.read(workspaceProvider.notifier).setMyOnlineStatus(false);
                      if (AppConfig.useFirebase) {
                        await FirebaseAuth.instance.signOut();
                      } else {
                        ref.read(demoLoggedInProvider.notifier).state = false;
                      }
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
