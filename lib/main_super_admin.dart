import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'super_admin/providers/wizard_state_provider.dart';
import 'super_admin/screens/super_admin_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    riverpod.ProviderScope(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => WizardStateProvider(),
          ),
        ],
        child: const FreelensAdminApp(),
      ),
    ),
  );
}

class FreelensAdminApp extends StatelessWidget {
  const FreelensAdminApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Freelens Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
      ),

      // If logged in -> check Platform Super Admin access.
      // If not logged in -> Login screen.
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snapshot.hasData && snapshot.data != null) {
            return _PlatformSuperAdminAuthorizationGate(
              user: snapshot.data!,
            );
          }

          return const SuperAdminLoginScreen();
        },
      ),
    );
  }
}

class _PlatformSuperAdminAuthorizationGate extends StatelessWidget {
  const _PlatformSuperAdminAuthorizationGate({
    required this.user,
  });

  final User user;

  bool _isSuperAdminRole(dynamic value) {
    final normalized = (value ?? '')
        .toString()
        .replaceAll(RegExp(r'[^A-Za-z]'), '')
        .toLowerCase();

    return normalized == 'superadmin' ||
        normalized == 'platformsuperadmin';
  }

  bool _isActive(dynamic value) {
    final status =
        (value ?? 'active').toString().trim().toLowerCase();

    return status.isEmpty ||
        status == 'active' ||
        status == 'enabled';
  }

  bool _isAllowed(Map<String, dynamic>? data) {
    if (data == null) return false;

    return _isSuperAdminRole(data['role']) &&
        _isActive(data['status']);
  }

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    // First check: users/{uid}
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, usersSnapshot) {
        if (usersSnapshot.connectionState ==
                ConnectionState.waiting &&
            !usersSnapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final usersData = usersSnapshot.data?.data();

        final allowedFromUsers =
            usersSnapshot.data?.exists == true &&
                _isAllowed(usersData);

        // Second check: user/{uid}
        return StreamBuilder<
            DocumentSnapshot<Map<String, dynamic>>>(
          stream: firestore
              .collection('user')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState ==
                    ConnectionState.waiting &&
                !userSnapshot.hasData) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final userData = userSnapshot.data?.data();

            final allowedFromUser =
                userSnapshot.data?.exists == true &&
                    _isAllowed(userData);

            // Allow Platform Super Admin if valid record
            // exists in either "users" or "user".
            final allowed =
                allowedFromUsers || allowedFromUser;

            if (allowed) {
              return const SuperAdminDashboardScreen();
            }

            return Scaffold(
              backgroundColor: const Color(0xFFF4F6F9),
              body: Center(
                child: Container(
                  width: 520,
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.red.withOpacity(.18),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_person_rounded,
                        size: 62,
                        color: Colors.redAccent,
                      ),

                      const SizedBox(height: 18),

                      const Text(
                        'Platform Super Admin access required',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        'This control center, including the APK Emulator, '
                        'is available only to Platform Super Admin accounts.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black54,
                          height: 1.45,
                        ),
                      ),

                      const SizedBox(height: 22),

                      FilledButton.icon(
                        onPressed: () =>
                            FirebaseAuth.instance.signOut(),
                        icon: const Icon(
                          Icons.logout_rounded,
                        ),
                        label: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ==========================================
// QUICK LOGIN GATEWAY SCREEN
// ==========================================

class SuperAdminLoginScreen extends StatefulWidget {
  const SuperAdminLoginScreen({Key? key}) : super(key: key);

  @override
  State<SuperAdminLoginScreen> createState() =>
      _SuperAdminLoginScreenState();
}

class _SuperAdminLoginScreenState
    extends State<SuperAdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = '';

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // authStateChanges automatically redirects
      // after successful Firebase Authentication login.
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage =
            e.message ?? 'Authentication failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E26),
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Freelens Platform Admin',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 32),

              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Admin Email',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),

              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  style: const TextStyle(
                    color: Colors.red,
                  ),
                ),
              ],

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed:
                      _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                        )
                      : const Text(
                          'Secure Login',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}