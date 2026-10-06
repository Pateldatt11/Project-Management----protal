import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local, on-device app lock for the signed-in employee APK.
///
/// The gate follows a PhonePe-style device-lock model: one OS prompt is opened
/// for the app entry check and the operating system decides whether to use
/// fingerprint/face first or screen lock fallback. The app never stores any
/// fingerprint, face data, PIN, pattern, passcode, or password.
class BiometricAuthService {
  BiometricAuthService._(this._prefs, this._auth);

  /// Security grace window after a successful local unlock.
  ///
  /// Reopening within this small window skips the prompt. Any cold start/resume
  /// after this window requires local authentication again.
  static const int secureRecheckGraceSeconds = 5;

  /// Process-wide single-flight guard. This prevents two LocalAuthentication
  /// prompts from being opened by the initial gate and lifecycle resume at the
  /// same time.
  static Future<bool>? _activeAuthentication;

  final SharedPreferences _prefs;
  final LocalAuthentication _auth;

  static Future<BiometricAuthService> create({LocalAuthentication? auth}) async {
    final prefs = await SharedPreferences.getInstance();
    return BiometricAuthService._(prefs, auth ?? LocalAuthentication());
  }

  static String enabledKey(String uid, String companyId) => 'biometric_lock_enabled_${uid}_$companyId';
  static String lastUnlockedAtKey(String uid, String companyId) => 'biometric_lock_last_unlocked_at_${uid}_$companyId';
  static String lastAvailabilityErrorKey(String uid, String companyId) => 'biometric_lock_last_error_${uid}_$companyId';

  Future<BiometricAvailability> availability() async {
    if (kIsWeb) {
      return const BiometricAvailability(
        supported: false,
        enrolled: false,
        deviceCredentialSupported: false,
        label: 'App lock is not available in web preview.',
        types: <BiometricType>[],
      );
    }

    try {
      final canCheck = await _auth.canCheckBiometrics;
      final deviceSupported = await _auth.isDeviceSupported();
      final types = await _auth.getAvailableBiometrics();
      final enrolled = types.isNotEmpty;
      final supported = canCheck || deviceSupported;
      return BiometricAvailability(
        supported: supported,
        enrolled: enrolled,
        deviceCredentialSupported: deviceSupported,
        label: _labelFor(
          types,
          supported: supported,
          enrolled: enrolled,
          deviceCredentialSupported: deviceSupported,
        ),
        types: types,
      );
    } catch (error) {
      return BiometricAvailability(
        supported: false,
        enrolled: false,
        deviceCredentialSupported: false,
        label: 'App lock is unavailable on this device.',
        types: const <BiometricType>[],
        error: error,
      );
    }
  }

  Future<bool> isEnabled({required String uid, required String companyId}) async {
    return _prefs.getBool(enabledKey(uid, companyId)) ?? false;
  }

  Future<bool> enable({required String uid, required String companyId}) async {
    final available = await availability();
    if (!available.canEnableDeviceLock) {
      await _prefs.setString(lastAvailabilityErrorKey(uid, companyId), available.label);
      return false;
    }

    final ok = await authenticateDeviceLock(
      reason: available.enrolled
          ? 'Confirm your fingerprint or phone screen lock to enable app protection.'
          : 'Confirm your phone screen lock to enable app protection.',
    );
    if (!ok) return false;

    await _prefs.setBool(enabledKey(uid, companyId), true);
    await markUnlocked(uid: uid, companyId: companyId);
    return true;
  }

  Future<void> disable({required String uid, required String companyId}) async {
    await _prefs.setBool(enabledKey(uid, companyId), false);
    await _prefs.remove(lastUnlockedAtKey(uid, companyId));
  }

  /// PhonePe-style app-open unlock. This is the primary path used by the gate.
  /// biometricOnly:false allows fingerprint/face when available and the native
  /// screen lock fallback such as PIN, pattern, passcode, or password.
  Future<bool> authenticateDeviceLock({required String reason}) {
    return authenticate(reason: reason, biometricOnly: false, stickyAuth: false);
  }

  /// Alias used by the lock screen's secondary action. local_auth does not
  /// provide a cross-platform "device credential only" switch in this project
  /// version, so this opens the same OS device-lock prompt with copy focused on
  /// screen lock fallback.
  Future<bool> authenticateScreenLockPreferred({required String reason}) {
    return authenticate(reason: reason, biometricOnly: false, stickyAuth: false);
  }

  Future<bool> authenticateBiometricOnly({required String reason}) {
    return authenticate(reason: reason, biometricOnly: true, stickyAuth: false);
  }

  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
    bool stickyAuth = false,
  }) {
    if (kIsWeb) return Future<bool>.value(false);

    final active = _activeAuthentication;
    if (active != null) return active;

    final future = _authenticateOnce(
      reason: reason,
      biometricOnly: biometricOnly,
      stickyAuth: stickyAuth,
    );
    _activeAuthentication = future;
    future.whenComplete(() {
      if (identical(_activeAuthentication, future)) {
        _activeAuthentication = null;
      }
    });
    return future;
  }

  Future<bool> _authenticateOnce({
    required String reason,
    required bool biometricOnly,
    required bool stickyAuth,
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          // Keep stickyAuth false for the app-open gate. Sticky auth can restart
          // the native prompt after a lifecycle resume and cause the old double
          // fingerprint flow.
          stickyAuth: stickyAuth,
          useErrorDialogs: true,
        ),
      );
    } catch (error) {
      debugPrint('Local auth failed: $error');
      return false;
    }
  }

  Future<void> markUnlocked({required String uid, required String companyId}) async {
    await _prefs.setInt(lastUnlockedAtKey(uid, companyId), DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> clearUnlockSession({required String uid, required String companyId}) async {
    await _prefs.remove(lastUnlockedAtKey(uid, companyId));
  }

  Future<bool> shouldLock({
    required String uid,
    required String companyId,
    int lockAfterSeconds = secureRecheckGraceSeconds,
  }) async {
    if (!await isEnabled(uid: uid, companyId: companyId)) return false;

    final last = _prefs.getInt(lastUnlockedAtKey(uid, companyId));
    if (last == null) return true;

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = now - last;

    // Clock rollback / corrupted future timestamps must not bypass app lock.
    if (elapsedMs < 0) {
      await clearUnlockSession(uid: uid, companyId: companyId);
      return true;
    }

    final graceSeconds = lockAfterSeconds.clamp(0, 300).toInt();
    if (graceSeconds <= 0) return true;
    return elapsedMs >= graceSeconds * 1000;
  }

  static String _labelFor(
    List<BiometricType> types, {
    required bool supported,
    required bool enrolled,
    required bool deviceCredentialSupported,
  }) {
    if (!supported) return 'This device does not support app lock.';
    if (types.contains(BiometricType.fingerprint)) return 'Fingerprint unlock available with phone screen-lock fallback.';
    if (types.contains(BiometricType.face)) return 'Face unlock available with phone screen-lock fallback.';
    if (types.contains(BiometricType.strong)) return 'Strong biometric unlock available with phone screen-lock fallback.';
    if (types.contains(BiometricType.weak)) return 'Biometric unlock available with phone screen-lock fallback.';
    if (deviceCredentialSupported) return 'Phone screen lock available. Add fingerprint for faster unlock.';
    if (!enrolled) return 'Add fingerprint or phone screen lock first.';
    return 'Device lock available.';
  }
}

class BiometricAvailability {
  const BiometricAvailability({
    required this.supported,
    required this.enrolled,
    required this.deviceCredentialSupported,
    required this.label,
    required this.types,
    this.error,
  });

  final bool supported;
  final bool enrolled;
  final bool deviceCredentialSupported;
  final String label;
  final List<BiometricType> types;
  final Object? error;

  bool get canEnable => supported && enrolled;
  bool get canEnableDeviceLock => supported && (enrolled || deviceCredentialSupported);
  bool get canEnableSecureLock => canEnableDeviceLock;
  bool get hasBiometric => enrolled;
  bool get hasScreenLockFallback => deviceCredentialSupported;
  bool get hasScreenPasswordFallback => deviceCredentialSupported;
}
