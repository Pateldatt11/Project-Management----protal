import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:project_management_dashboard/core/constants/app_enums.dart';

import '../../../app/app_theme.dart';
import '../../../app/workspace_state.dart';
import '../../../core/config/app_config.dart';
import '../../../data/demo/demo_data.dart';
import '../../../data/firebase/auth_service.dart';
import 'auth_gate.dart';

class _AuthUiRuntimePolicy {
  const _AuthUiRuntimePolicy({
    required this.newLoginSignupEnabled,
    required this.disableOnWeb,
    required this.allowEmailPassword,
    required this.allowSignUp,
    required this.allowPasswordReset,
    required this.socialProviders,
    required this.loginTitle,
    required this.signupTitle,
    required this.loginSubtitle,
    required this.signupSubtitle,
    required this.loginTabLabel,
    required this.signupTabLabel,
    required this.loginButtonLabel,
    required this.signupButtonLabel,
    required this.forgotPasswordLabel,
    required this.otherWaysLabel,
    required this.securityEnabled,
    required this.securityNote,
  });

  final bool newLoginSignupEnabled;
  final bool disableOnWeb;
  final bool allowEmailPassword;
  final bool allowSignUp;
  final bool allowPasswordReset;
  final List<_FirebaseProvider> socialProviders;
  final String loginTitle;
  final String signupTitle;
  final String loginSubtitle;
  final String signupSubtitle;
  final String loginTabLabel;
  final String signupTabLabel;
  final String loginButtonLabel;
  final String signupButtonLabel;
  final String forgotPasswordLabel;
  final String otherWaysLabel;
  final bool securityEnabled;
  final String securityNote;

  factory _AuthUiRuntimePolicy.fromMap(Map<String, dynamic> raw) {
    final labels = raw['labels'] is Map ? (raw['labels'] as Map).map((key, value) => MapEntry(key.toString(), value)) : const <String, dynamic>{};
    final methods = _stringList(raw['methods'], fallback: const <String>['emailPassword', 'signUp', 'passwordReset', 'google', 'apple', 'facebook'])
        .map((value) => value.toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), ''))
        .toSet();
    final providers = <_FirebaseProvider>[
      if (methods.contains('apple') || methods.contains('applecom')) _FirebaseProvider.apple,
      if (methods.contains('google') || methods.contains('googlecom')) _FirebaseProvider.google,
      if (methods.contains('facebook') || methods.contains('facebookcom') || methods.contains('fb')) _FirebaseProvider.facebook,
    ];
    final security = raw['bruteForceProtection'] is Map
        ? (raw['bruteForceProtection'] as Map).map((key, value) => MapEntry(key.toString(), value))
        : raw['authSecurityPolicy'] is Map
            ? (raw['authSecurityPolicy'] as Map).map((key, value) => MapEntry(key.toString(), value))
            : const <String, dynamic>{};
    return _AuthUiRuntimePolicy(
      newLoginSignupEnabled: _bool(raw['newLoginSignupEnabled'], fallback: true),
      disableOnWeb: _bool(raw['disableOnWeb'], fallback: true),
      allowEmailPassword: _bool(raw['allowEmailPassword'], fallback: methods.contains('emailpassword') || methods.contains('email')),
      allowSignUp: _bool(raw['allowSignUp'], fallback: methods.contains('signup') || methods.contains('register')),
      allowPasswordReset: _bool(raw['allowPasswordReset'], fallback: methods.contains('passwordreset') || methods.contains('forgotpassword')),
      socialProviders: providers,
      loginTitle: _label(labels, 'loginTitle', 'Welcome back'),
      signupTitle: _label(labels, 'signupTitle', 'Create your workspace account'),
      loginSubtitle: _label(labels, 'loginSubtitle', 'Sign in to continue to your project dashboard.'),
      signupSubtitle: _label(labels, 'signupSubtitle', 'Use company email to request access or create the first admin account.'),
      loginTabLabel: _label(labels, 'loginTab', 'Login'),
      signupTabLabel: _label(labels, 'signupTab', 'Sign Up'),
      loginButtonLabel: _label(labels, 'loginButton', 'Login'),
      signupButtonLabel: _label(labels, 'signupButton', 'Create account'),
      forgotPasswordLabel: _label(labels, 'forgotPassword', 'Forgot password?'),
      otherWaysLabel: _label(labels, 'otherWays', 'Other ways to sign in'),
      securityEnabled: _bool(security['enabled'], fallback: true),
      securityNote: _label(labels, 'securityNote', 'Protected with rate limiting and Firebase security checks.'),
    );
  }

  static bool _bool(dynamic value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final raw = value?.toString().trim().toLowerCase();
    if (raw == 'true' || raw == '1' || raw == 'yes') return true;
    if (raw == 'false' || raw == '0' || raw == 'no') return false;
    return fallback;
  }

  static String _label(Map<String, dynamic> labels, String key, String fallback) {
    final value = labels[key]?.toString().trim();
    return value == null || value.isEmpty ? fallback : value;
  }
}

List<String> _stringList(dynamic value, {required List<String> fallback}) {
  if (value is List) return value.map((item) => item.toString()).where((item) => item.trim().isNotEmpty).toList();
  if (value is String && value.trim().isNotEmpty) return value.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
  return fallback;
}


class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authPolicy = _AuthUiRuntimePolicy.fromMap(ref.watch(workspaceProvider).mobileUiConfig.authUiPolicy);
    if (kIsWeb && authPolicy.disableOnWeb) return const _LegacyWebLoginScreen();
    if (!authPolicy.newLoginSignupEnabled) return const _LegacyWebLoginScreen();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F2EA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.92),
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(color: const Color(0xFFD9DED2)),
                  boxShadow: const [BoxShadow(color: Color(0x160F172A), blurRadius: 36, offset: Offset(0, 18))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(34),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 880;
                      final hero = _LoginHero(compact: compact);
                      final form = _RoleLoginPanel(compact: compact);
                      if (compact) {
                        return Column(children: [hero, form]);
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 11, child: hero),
                          Expanded(flex: 10, child: form),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _LegacyWebLoginScreen extends StatelessWidget {
  const _LegacyWebLoginScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [BoxShadow(color: Color(0x120F172A), blurRadius: 24, offset: Offset(0, 12))],
                ),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(10, 18, 10, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LegacyWebAuthHeader(),
                      _RoleLoginPanel(compact: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegacyWebAuthHeader extends StatelessWidget {
  const _LegacyWebAuthHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF5F7F58), size: 30),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Project Management Dashboard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Web portal login',
            style: TextStyle(color: AppTheme.slate700, fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _LoginHero extends StatelessWidget {
  const _LoginHero({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 430 : 720),
      padding: EdgeInsets.fromLTRB(compact ? 22 : 38, compact ? 22 : 36, compact ? 22 : 38, compact ? 26 : 36),
      decoration: const BoxDecoration(
        color: Color(0xFFF2F5EC),
        border: Border(right: BorderSide(color: Color(0xFFDDE4D5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF5F7F58),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: const Color(0xFF5F7F58).withOpacity(.20), blurRadius: 18, offset: const Offset(0, 8))],
                ),
                child: const Icon(Icons.task_alt_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Project Management',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 24 : 52),
          AspectRatio(
            aspectRatio: compact ? 1.55 : 1.25,
            child: const _ProjectWireframeCard(),
          ),
          const SizedBox(height: 28),
          Text(
            'Streamline Your Team\'s Perfect Project',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.navy,
                  fontSize: compact ? 28 : 34,
                  height: 1.04,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Team setup, tasks, projects and progress stay connected with Firebase Auth and Firestore.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.slate700, height: 1.45, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _HeroChip(icon: Icons.verified_user_rounded, label: 'Secure login'),
              _HeroChip(icon: Icons.groups_rounded, label: 'Team roles'),
              _HeroChip(icon: Icons.notifications_active_rounded, label: 'Task alerts'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectWireframeCard extends StatelessWidget {
  const _ProjectWireframeCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.68),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFBECBB8), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: CustomPaint(
          painter: _ProjectWireframePainter(),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _ProjectWireframePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = const Color(0xFF223423).withOpacity(.70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final soft = Paint()
      ..color = const Color(0xFF5F7F58).withOpacity(.18)
      ..style = PaintingStyle.fill;
    final green = Paint()
      ..color = const Color(0xFF5F7F58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
    canvas.drawRect(rect, border);
    canvas.drawLine(rect.topLeft, rect.bottomRight, border..color = const Color(0xFF223423).withOpacity(.28));
    canvas.drawLine(rect.topRight, rect.bottomLeft, border);

    final center = Offset(size.width * .52, size.height * .55);
    canvas.drawCircle(center, math.min(size.width, size.height) * .11, soft);
    canvas.drawCircle(center, math.min(size.width, size.height) * .075, border..color = const Color(0xFF223423).withOpacity(.82));
    final check = Path()
      ..moveTo(center.dx - 12, center.dy)
      ..lineTo(center.dx - 3, center.dy + 9)
      ..lineTo(center.dx + 16, center.dy - 13);
    canvas.drawPath(check, green);

    final peoplePaint = Paint()
      ..color = const Color(0xFF111827).withOpacity(.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    _drawPerson(canvas, Offset(size.width * .52, size.height * .22), peoplePaint);
    _drawPerson(canvas, Offset(size.width * .22, size.height * .55), peoplePaint);

    final card = RRect.fromRectAndRadius(Rect.fromLTWH(size.width * .62, size.height * .42, size.width * .18, size.height * .20), const Radius.circular(2));
    canvas.drawRRect(card, border..color = const Color(0xFF223423).withOpacity(.80));
    canvas.drawLine(card.outerRect.topLeft, card.outerRect.bottomRight, border);
    canvas.drawLine(card.outerRect.topRight, card.outerRect.bottomLeft, border);

    final chart = Rect.fromLTWH(size.width * .55, size.height * .65, size.width * .33, size.height * .16);
    canvas.drawRRect(RRect.fromRectAndRadius(chart, const Radius.circular(4)), border);
    final path = Path()
      ..moveTo(chart.left + 18, chart.bottom - 18)
      ..lineTo(chart.left + 55, chart.bottom - 28)
      ..lineTo(chart.left + 82, chart.bottom - 26)
      ..lineTo(chart.left + 110, chart.top + 26)
      ..lineTo(chart.right - 18, chart.top + 20);
    canvas.drawPath(path, green..strokeWidth = 2.2);
  }

  void _drawPerson(Canvas canvas, Offset center, Paint paint) {
    canvas.drawCircle(center.translate(0, -18), 9, paint);
    final path = Path()
      ..moveTo(center.dx - 22, center.dy + 12)
      ..quadraticBezierTo(center.dx, center.dy - 10, center.dx + 22, center.dy + 12);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.70),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD4DDCD)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF5F7F58)),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w900, fontSize: 12)),
        ],
      ),
    );
  }
}

class _RoleLoginPanel extends ConsumerWidget {
  const _RoleLoginPanel({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (AppConfig.useFirebase) {
      return _FirebaseLoginPanel(
        compact: compact,
        policy: _AuthUiRuntimePolicy.fromMap(ref.watch(workspaceProvider).mobileUiConfig.authUiPolicy),
      );
    }

    final state = ref.watch(workspaceProvider);
    final demoUsers = DemoData.demoUsers.where((user) => state.isPortalPostActive(user.role)).toList();
    return Padding(
      padding: EdgeInsets.all(compact ? 22 : 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AuthModeHeader(activeLabel: 'Login', inactiveLabel: 'Sign Up'),
          const SizedBox(height: 20),
          Text('Choose demo login', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          Text('Active roles: ${demoUsers.length}/${DemoData.demoUsers.length}', style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextFormField(
            initialValue: 'select-role@company.demo',
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
            readOnly: true,
          ),
          const SizedBox(height: 12),
          const TextField(
            obscureText: true,
            readOnly: true,
            decoration: InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline_rounded), hintText: 'demo123'),
          ),
          const SizedBox(height: 18),
          _SocialAuthRow(
            enabled: false,
            providers: const <_FirebaseProvider>[_FirebaseProvider.apple, _FirebaseProvider.google, _FirebaseProvider.facebook],
            onProvider: (_) {},
          ),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: demoUsers.length,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: compact ? 230 : 250,
              mainAxisExtent: 104,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (context, index) {
              final user = demoUsers[index];
              return _RoleLoginCard(
                name: user.displayName,
                email: user.email,
                role: user.role.shortLabel,
                description: user.role.department,
                color: user.role.color,
                onTap: () {
                  ref.read(workspaceProvider.notifier).selectDemoUser(user.uid);
                  ref.read(demoLoggedInProvider.notifier).state = true;
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FirebaseLoginPanel extends ConsumerStatefulWidget {
  const _FirebaseLoginPanel({required this.compact, required this.policy});

  final bool compact;
  final _AuthUiRuntimePolicy policy;

  @override
  ConsumerState<_FirebaseLoginPanel> createState() => _FirebaseLoginPanelState();
}

class _FirebaseLoginPanelState extends ConsumerState<_FirebaseLoginPanel> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registerMode = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.policy;
    if (_registerMode && !policy.allowSignUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _registerMode = false);
      });
    }

    return Padding(
      padding: EdgeInsets.all(widget.compact ? 22 : 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (policy.allowSignUp)
            _AuthModeHeader(
              activeLabel: _registerMode ? policy.signupTabLabel : policy.loginTabLabel,
              inactiveLabel: _registerMode ? policy.loginTabLabel : policy.signupTabLabel,
              onInactiveTap: _loading ? null : () => setState(() => _registerMode = !_registerMode),
            ),
          if (policy.allowSignUp) const SizedBox(height: 24),
          Text(
            _registerMode ? policy.signupTitle : policy.loginTitle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            _registerMode ? policy.signupSubtitle : policy.loginSubtitle,
            style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, height: 1.35),
          ),
          if (policy.securityEnabled) ...[
            const SizedBox(height: 12),
            _AuthSecurityNote(text: policy.securityNote),
          ],
          const SizedBox(height: 22),
          if (_registerMode) ...[
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            onSubmitted: (_) {
              if (!_loading) _submit();
            },
            decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline_rounded)),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_registerMode ? Icons.person_add_alt_1_rounded : Icons.login_rounded),
            label: Text(_registerMode ? policy.signupButtonLabel : policy.loginButtonLabel),
          ),
          if (policy.socialProviders.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(policy.otherWaysLabel, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 14),
            _SocialAuthRow(
              enabled: !_loading,
              providers: policy.socialProviders,
              onProvider: _oauth,
            ),
          ],
          if (policy.allowPasswordReset) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _loading ? null : _resetPassword,
              icon: const Icon(Icons.password_rounded),
              label: Text(policy.forgotPasswordLabel),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid email and at least 6 characters password.')));
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = ref.read(authServiceProvider);
      if (_registerMode) {
        if (!widget.policy.allowSignUp) {
          throw Exception('Sign up is disabled by the active auth UI policy.');
        }
        await auth.signUpEmailPassword(
          email: email,
          password: password,
          displayName: _name.text.trim().isEmpty ? email.split('@').first : _name.text.trim(),
        );
      } else {
        await auth.signInEmailPassword(email: email, password: password);
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthService.friendlyAuthError(error))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _oauth(_FirebaseProvider provider) async {
    setState(() => _loading = true);
    try {
      final auth = ref.read(authServiceProvider);
      await auth.signInWithProviderId(provider.name);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Provider sign-in failed. ${AuthService.friendlyAuthError(error)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter email first.')));
      return;
    }
    try {
      await ref.read(authServiceProvider).sendPasswordResetEmail(email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset email sent.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthService.friendlyAuthError(error))));
    }
  }
}


class _AuthSecurityNote extends StatelessWidget {
  const _AuthSecurityNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5EC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8E1D1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFF5F7F58), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.slate700, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

enum _FirebaseProvider { google, apple, facebook }

class _AuthModeHeader extends StatelessWidget {
  const _AuthModeHeader({required this.activeLabel, required this.inactiveLabel, this.onInactiveTap});

  final String activeLabel;
  final String inactiveLabel;
  final VoidCallback? onInactiveTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5EC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E1D1)),
      ),
      child: Row(
        children: [
          Expanded(child: _AuthModePill(label: activeLabel, active: true, onTap: null)),
          Expanded(child: _AuthModePill(label: inactiveLabel, active: false, onTap: onInactiveTap)),
        ],
      ),
    );
  }
}

class _AuthModePill extends StatelessWidget {
  const _AuthModePill({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF5F7F58) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(color: active ? Colors.white : AppTheme.slate700, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _SocialAuthRow extends StatelessWidget {
  const _SocialAuthRow({required this.enabled, required this.providers, required this.onProvider});

  final bool enabled;
  final List<_FirebaseProvider> providers;
  final ValueChanged<_FirebaseProvider> onProvider;

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: providers.asMap().entries.expand((entry) sync* {
        if (entry.key > 0) yield const SizedBox(width: 12);
        final provider = entry.value;
        yield switch (provider) {
          _FirebaseProvider.apple => _SocialAuthButton(label: 'Apple', icon: Icons.apple_rounded, enabled: enabled, onTap: () => onProvider(provider)),
          _FirebaseProvider.google => _SocialAuthButton(label: 'Google', textIcon: 'G', enabled: enabled, onTap: () => onProvider(provider)),
          _FirebaseProvider.facebook => _SocialAuthButton(label: 'Facebook', textIcon: 'f', enabled: enabled, onTap: () => onProvider(provider)),
        };
      }).toList(),
    );
  }
}

class _SocialAuthButton extends StatelessWidget {
  const _SocialAuthButton({required this.label, required this.enabled, required this.onTap, this.icon, this.textIcon});

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final IconData? icon;
  final String? textIcon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: enabled ? 1 : .42,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD8E1D1)),
              boxShadow: const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 14, offset: Offset(0, 6))],
            ),
            child: icon != null
                ? Icon(icon, color: AppTheme.navy)
                : Text(textIcon ?? '?', style: const TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w900, fontSize: 20)),
          ),
        ),
      ),
    );
  }
}

class _RoleLoginCard extends StatelessWidget {
  const _RoleLoginCard({
    required this.name,
    required this.email,
    required this.role,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final String name;
  final String email;
  final String role;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBF8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD8E1D1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 17, backgroundColor: color, child: Text(role.characters.first, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
                const SizedBox(width: 9),
                Expanded(child: Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
              ],
            ),
            const Spacer(),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.navy)),
            const SizedBox(height: 2),
            Text(description, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
