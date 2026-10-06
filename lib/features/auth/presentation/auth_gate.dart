import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/workspace_shell_router.dart';
import '../../../app/workspace_state.dart';
import '../../../core/config/app_config.dart';
import '../../../core/security/biometric_auth_service.dart';
import '../../../core/security/biometric_unlock_gate.dart';
import '../../../data/firebase/auth_service.dart';
import '../../../data/firebase/auth_rate_limit_service.dart';
import 'login_screen.dart';

final demoLoggedInProvider = StateProvider<bool>((ref) => false);
final authServiceProvider = Provider<AuthService>((ref) {
  final authPolicy = ref.watch(workspaceProvider.select((state) => state.mobileUiConfig.authUiPolicy));
  return AuthService(rateLimit: AuthRateLimitService(config: AuthRateLimitConfig.fromAuthUiPolicy(authPolicy)));
});

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.useFirebase) {
      final loggedIn = ref.watch(demoLoggedInProvider);
      if (loggedIn) return const WorkspaceShellRouter();
      return const LoginScreen();
    }

    final auth = ref.watch(authServiceProvider);
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoading(message: 'Checking Firebase login...');
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return _FirebaseWorkspaceBootstrap(user: user);
      },
    );
  }
}

class _FirebaseWorkspaceBootstrap extends ConsumerStatefulWidget {
  const _FirebaseWorkspaceBootstrap({required this.user});
  final User user;

  @override
  ConsumerState<_FirebaseWorkspaceBootstrap> createState() => _FirebaseWorkspaceBootstrapState();
}

class _FirebaseWorkspaceBootstrapState extends ConsumerState<_FirebaseWorkspaceBootstrap> {
  Future<void>? _bootstrapFuture;
  String? _bootstrappingUid;
  bool _bootstrapStartScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleBootstrapStart();
  }

  @override
  void didUpdateWidget(covariant _FirebaseWorkspaceBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid || oldWidget.user.email != widget.user.email) {
      _bootstrapFuture = null;
      _bootstrappingUid = null;
      _bootstrapStartScheduled = false;
      _scheduleBootstrapStart();
    }
  }

  void _scheduleBootstrapStart({bool force = false}) {
    if (!force && _bootstrappingUid == widget.user.uid && _bootstrapFuture != null) return;
    if (_bootstrapStartScheduled) return;

    _bootstrapStartScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!force && _bootstrappingUid == widget.user.uid && _bootstrapFuture != null) {
        _bootstrapStartScheduled = false;
        return;
      }

      final future = ref.read(workspaceProvider.notifier).connectFirebaseUser(
            uid: widget.user.uid,
            email: widget.user.email ?? '',
            displayName: widget.user.displayName,
          );

      setState(() {
        _bootstrappingUid = widget.user.uid;
        _bootstrapFuture = future;
        _bootstrapStartScheduled = false;
      });
    });
  }

  void _retryBootstrap() {
    setState(() {
      _bootstrapFuture = null;
      _bootstrappingUid = null;
      _bootstrapStartScheduled = false;
    });
    _scheduleBootstrapStart(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final future = _bootstrapFuture;

    if (future == null) {
      _scheduleBootstrapStart();
      return const _AuthLoading(message: 'Starting Firebase workspace initialization...');
    }

    return FutureBuilder<void>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AuthLoading(message: 'Initializing company workspace from Firebase...');
        }

        if (snapshot.hasError) {
          return _AuthError(
            title: 'Firebase workspace initialization failed',
            message: snapshot.error.toString(),
            onRetry: _retryBootstrap,
          );
        }

        if (workspace.user.uid != widget.user.uid) {
          return _AuthError(
            title: 'Firebase workspace did not finish loading',
            message: workspace.lastError ?? 'The authenticated user was not mapped to a company member document.',
            onRetry: _retryBootstrap,
          );
        }

        final companyId = workspace.user.defaultCompanyId.trim().isNotEmpty
            ? workspace.user.defaultCompanyId.trim()
            : AppConfig.fallbackCompanyId;
        return BiometricUnlockGate(
          uid: workspace.user.uid,
          companyId: companyId,
          lockAfterSeconds: BiometricAuthService.secureRecheckGraceSeconds,
          child: const WorkspaceShellRouter(),
        );
      },
    );
  }
}

class _AuthLoading extends StatelessWidget {
  const _AuthLoading({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 18),
                Text(message, style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthError extends StatelessWidget {
  const _AuthError({required this.title, required this.message, required this.onRetry});

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
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
              const Icon(Icons.cloud_off_rounded, color: Color(0xFFDC2626), size: 34),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              Text(message, style: const TextStyle(color: Color(0xFF475569), height: 1.4)),
              const SizedBox(height: 18),
              Row(
                children: [
                  FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => FirebaseAuth.instance.signOut(),
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
