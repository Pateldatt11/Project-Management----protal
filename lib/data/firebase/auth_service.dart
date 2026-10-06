import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_rate_limit_service.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, AuthRateLimitService? rateLimit, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        _rateLimit = rateLimit ?? AuthRateLimitService(),
        _googleSignIn = googleSignIn;

  final FirebaseAuth _auth;
  final AuthRateLimitService _rateLimit;

  /// Lazily initialized so Flutter Web does not initialize google_sign_in_web
  /// at app startup. The web plugin asserts when no web OAuth client id/meta tag
  /// exists, even if the user never taps Google login. Web Google login uses
  /// FirebaseAuth.signInWithProvider instead; native Android/iOS uses this SDK.
  GoogleSignIn? _googleSignIn;

  GoogleSignIn get _nativeGoogleSignIn => _googleSignIn ??= GoogleSignIn(
        scopes: const <String>['email', 'profile'],
      );

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmail(String email, String password) {
    return signInEmailPassword(email: email, password: password);
  }

  Future<UserCredential> registerWithEmail(String email, String password) {
    return signUpEmailPassword(email: email, password: password);
  }

  Future<UserCredential> signInEmailPassword({required String email, required String password}) async {
    final safeEmail = email.trim();
    await _rateLimit.check(email: safeEmail, action: 'login');
    try {
      final credential = await _auth.signInWithEmailAndPassword(email: safeEmail, password: password);
      await _rateLimit.recordSuccess(email: safeEmail, action: 'login');
      return credential;
    } catch (error) {
      await _rateLimit.recordFailure(email: safeEmail, action: 'login', error: error);
      rethrow;
    }
  }

  Future<UserCredential> signUpEmailPassword({required String email, required String password, String? displayName}) async {
    final safeEmail = email.trim();
    await _rateLimit.check(email: safeEmail, action: 'signup');
    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: safeEmail, password: password);
      final safeName = displayName?.trim();
      if (safeName != null && safeName.isNotEmpty) {
        await credential.user?.updateDisplayName(safeName);
      }
      await _rateLimit.recordSuccess(email: safeEmail, action: 'signup');
      return credential;
    } catch (error) {
      await _rateLimit.recordFailure(email: safeEmail, action: 'signup', error: error);
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final safeEmail = email.trim();
    await _rateLimit.check(email: safeEmail, action: 'passwordReset');
    try {
      await _auth.sendPasswordResetEmail(email: safeEmail);
      await _rateLimit.recordSuccess(email: safeEmail, action: 'passwordReset');
    } catch (error) {
      await _rateLimit.recordFailure(email: safeEmail, action: 'passwordReset', error: error);
      rethrow;
    }
  }

  Future<void> sendCurrentUserEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<void> reloadCurrentUser() => _auth.currentUser?.reload() ?? Future<void>.value();

  Future<UserCredential> signInWithProviderId(String providerId) {
    switch (_canonicalProvider(providerId)) {
      case 'google':
        return signInWithGoogle();
      case 'apple':
        return signInWithApple();
      case 'facebook':
        return signInWithFacebook();
      default:
        throw FirebaseAuthException(
          code: 'unsupported-provider',
          message: 'Unsupported auth provider: $providerId',
        );
    }
  }

  bool isProviderSupported(String providerId) {
    return const <String>{'google', 'apple', 'facebook'}.contains(_canonicalProvider(providerId));
  }

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');
      return _signInWithProviderCompat(provider);
    }

    try {
      final googleUser = await _nativeGoogleSignIn.signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(code: 'canceled', message: 'Google sign-in was cancelled.');
      }
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      if ((idToken == null || idToken.isEmpty) && (accessToken == null || accessToken.isEmpty)) {
        throw FirebaseAuthException(
          code: 'missing-google-token',
          message: 'Google did not return an auth token. Check OAuth client and SHA certificate configuration in Firebase.',
        );
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken, accessToken: accessToken);
      return _auth.signInWithCredential(credential);
    } on FirebaseAuthException {
      rethrow;
    } catch (error) {
      final message = error.toString();
      if (message.contains('ApiException: 10') || message.toLowerCase().contains('developer_error')) {
        throw FirebaseAuthException(
          code: 'google-sha-missing',
          message: 'Google sign-in is not configured for this APK. Add debug/release SHA-1 and SHA-256 in Firebase, download the updated google-services.json, then rebuild.',
        );
      }
      throw FirebaseAuthException(code: 'google-sign-in-failed', message: message);
    }
  }

  Future<UserCredential> signInWithApple() async {
    final provider = OAuthProvider('apple.com')
      ..addScope('email')
      ..addScope('name');
    return _signInWithProviderCompat(provider);
  }

  Future<UserCredential> signInWithFacebook() async {
    final provider = FacebookAuthProvider()
      ..addScope('email')
      ..addScope('public_profile');
    return _signInWithProviderCompat(provider);
  }

  Future<UserCredential> _signInWithProviderCompat(AuthProvider provider) async {
    try {
      return await _auth.signInWithProvider(provider);
    } on UnimplementedError catch (error) {
      throw FirebaseAuthException(
        code: 'provider-flow-unavailable',
        message: 'This provider flow is not available on ${_platformName()}: $error',
      );
    } on FirebaseAuthException {
      rethrow;
    } catch (error) {
      throw FirebaseAuthException(code: 'provider-sign-in-failed', message: error.toString());
    }
  }

  Future<void> signOut() async {
    try {
      if (!kIsWeb) await _nativeGoogleSignIn.signOut();
    } catch (_) {
      // Firebase sign-out must still run even when the local Google session is already gone.
    }
    await _auth.signOut();
  }

  static String friendlyAuthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Email or password is incorrect.';
        case 'email-already-in-use':
          return 'This account could not be created. Try Login or reset password.';
        case 'weak-password':
          return 'Password is too weak. Use at least 6 characters.';
        case 'invalid-email':
          return 'Enter a valid email address.';
        case 'too-many-requests':
          return error.message ?? 'Too many attempts. Please wait and try again.';
        case 'operation-not-allowed':
          return 'This sign-in method is not enabled in Firebase Authentication.';
        case 'account-exists-with-different-credential':
          return 'This email already exists with a different sign-in method.';
        case 'popup-closed-by-user':
        case 'web-context-canceled':
        case 'web-context-cancelled':
        case 'canceled':
          return 'Sign-in was cancelled.';
        case 'google-sha-missing':
        case 'missing-google-token':
          return error.message ?? 'Google sign-in is not configured correctly.';
        case 'provider-flow-unavailable':
          return error.message ?? 'This sign-in method is not available on this platform.';
        case 'provider-sign-in-failed':
        case 'google-sign-in-failed':
          return error.message ?? 'Provider sign-in failed.';
        default:
          return error.message ?? 'Firebase auth failed: ${error.code}';
      }
    }
    return error.toString();
  }

  static String _canonicalProvider(String value) {
    final raw = value.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    if (raw == 'google' || raw == 'googlecom') return 'google';
    if (raw == 'apple' || raw == 'applecom') return 'apple';
    if (raw == 'facebook' || raw == 'facebookcom' || raw == 'fb') return 'facebook';
    return raw;
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }
}
