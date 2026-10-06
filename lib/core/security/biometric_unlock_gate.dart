import 'dart:async';

import 'package:flutter/material.dart';

import 'biometric_auth_service.dart';

/// PhonePe-style app-open device lock gate.
///
/// The gate is shown only after the user enables Profile -> Security -> App
/// lock. It opens a single native OS authentication prompt that supports both
/// fingerprint/face and the phone screen lock fallback. A successful unlock
/// opens the workspace directly and records a short 5-second grace window.
/// Opening the system notification center / quick settings shade is not treated
/// as leaving the app, so it will not trigger the lock screen.
class BiometricUnlockGate extends StatefulWidget {
  const BiometricUnlockGate({
    super.key,
    required this.uid,
    required this.companyId,
    required this.child,
    this.lockAfterSeconds = BiometricAuthService.secureRecheckGraceSeconds,
    this.title = 'Unlock workspace',
    this.subtitle = 'Use fingerprint or phone screen lock to continue.',
  });

  final String uid;
  final String companyId;
  final Widget child;
  final int lockAfterSeconds;
  final String title;
  final String subtitle;

  @override
  State<BiometricUnlockGate> createState() => _BiometricUnlockGateState();
}

class _BiometricUnlockGateState extends State<BiometricUnlockGate> with WidgetsBindingObserver {
  BiometricAuthService? _service;
  BiometricAvailability? _availability;
  bool _locked = false;
  bool _checking = true;
  bool _authInProgress = false;
  bool _screenLockPreferred = false;
  String? _unlockError;
  DateTime? _lastBackgroundedAt;
  Future<void>? _activeUnlockAttempt;
  int _initGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init(autoPrompt: true));
  }

  @override
  void didUpdateWidget(covariant BiometricUnlockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid || oldWidget.companyId != widget.companyId) {
      _activeUnlockAttempt = null;
      _locked = false;
      _checking = true;
      _authInProgress = false;
      _screenLockPreferred = false;
      _unlockError = null;
      _lastBackgroundedAt = null;
      unawaited(_init(autoPrompt: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // Do not treat `inactive` as a real app leave. Android can report this
        // while the user pulls down the system notification center / quick
        // settings shade or while a native overlay is shown. Locking here caused
        // the app to show the authentication screen when the user only opened
        // notifications, so we ignore this state for app-lock timing.
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _lastBackgroundedAt ??= DateTime.now();
        break;
      case AppLifecycleState.resumed:
        // Only re-check the app lock after a real background transition. Opening
        // the notification center can create inactive/resumed callbacks without
        // the app actually being backgrounded, and that must not trigger auth.
        if (_lastBackgroundedAt != null && !_authInProgress && _activeUnlockAttempt == null) {
          unawaited(_lockIfRequired(source: 'resumed'));
        }
        break;
    }
  }

  Future<void> _init({required bool autoPrompt}) async {
    final generation = ++_initGeneration;
    final service = await BiometricAuthService.create();
    final shouldLock = await service.shouldLock(
      uid: widget.uid,
      companyId: widget.companyId,
      lockAfterSeconds: widget.lockAfterSeconds,
    );
    final availability = await service.availability();
    if (!mounted || generation != _initGeneration) return;

    setState(() {
      _service = service;
      _availability = availability;
      _checking = false;
      _locked = shouldLock;
      _authInProgress = shouldLock && autoPrompt;
      _screenLockPreferred = false;
      _unlockError = null;
    });

    if (shouldLock && autoPrompt) {
      unawaited(_unlock(autoStarted: true));
    }
  }

  Future<void> _lockIfRequired({required String source}) async {
    final service = _service;
    if (service == null || !mounted || _checking || _authInProgress || _activeUnlockAttempt != null) return;

    final shouldLock = await service.shouldLock(
      uid: widget.uid,
      companyId: widget.companyId,
      lockAfterSeconds: widget.lockAfterSeconds,
    );
    if (!mounted || _authInProgress || _activeUnlockAttempt != null) return;
    if (!shouldLock) {
      _lastBackgroundedAt = null;
      return;
    }

    final availability = await service.availability();
    if (!mounted) return;
    setState(() {
      _availability = availability;
      _locked = true;
      _authInProgress = true;
      _screenLockPreferred = false;
      _unlockError = null;
    });
    unawaited(_unlock(autoStarted: true));
  }

  Future<void> _unlock({bool autoStarted = false, bool preferScreenLock = false}) {
    final active = _activeUnlockAttempt;
    if (active != null) return active;

    final service = _service;
    if (service == null) return Future<void>.value();

    final future = _runUnlock(
      service: service,
      autoStarted: autoStarted,
      preferScreenLock: preferScreenLock,
    );
    _activeUnlockAttempt = future;
    future.whenComplete(() {
      if (identical(_activeUnlockAttempt, future)) {
        _activeUnlockAttempt = null;
      }
    });
    return future;
  }

  Future<void> _runUnlock({
    required BiometricAuthService service,
    required bool autoStarted,
    required bool preferScreenLock,
  }) async {
    if (!mounted) return;
    setState(() {
      _locked = true;
      _authInProgress = true;
      _screenLockPreferred = preferScreenLock;
      _unlockError = null;
    });

    // Re-check just before showing the OS prompt. If another caller already
    // authenticated and saved the 5-second session, skip this prompt entirely.
    final stillShouldLock = await service.shouldLock(
      uid: widget.uid,
      companyId: widget.companyId,
      lockAfterSeconds: widget.lockAfterSeconds,
    );
    if (!mounted) return;
    if (!stillShouldLock) {
      setState(() {
        _locked = false;
        _authInProgress = false;
        _screenLockPreferred = false;
        _unlockError = null;
      });
      return;
    }

    final availability = await service.availability();
    if (!mounted) return;
    setState(() => _availability = availability);

    if (!availability.canEnableDeviceLock) {
      setState(() {
        _locked = true;
        _authInProgress = false;
        _screenLockPreferred = false;
        _unlockError = availability.label;
      });
      return;
    }

    final ok = preferScreenLock
        ? await service.authenticateScreenLockPreferred(
            reason: 'Unlock ProjectFlow using your phone screen lock or fingerprint.',
          )
        : await service.authenticateDeviceLock(
            reason: 'Unlock ProjectFlow using fingerprint or phone screen lock.',
          );
    if (!mounted) return;

    if (ok) {
      await service.markUnlocked(uid: widget.uid, companyId: widget.companyId);
      _lastBackgroundedAt = null;
    }
    if (!mounted) return;

    setState(() {
      _locked = !ok;
      _authInProgress = false;
      _screenLockPreferred = false;
      _unlockError = ok ? null : 'Authentication was cancelled or did not complete.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const _PhonePeCheckingScreen();
    }
    if (!_locked && !_authInProgress) return widget.child;
    if (_authInProgress) {
      return _PhonePeAuthenticatingScreen(
        title: widget.title,
        subtitle: _screenLockPreferred
            ? 'Complete your phone screen lock to continue.'
            : 'Complete fingerprint or phone screen lock to continue.',
        screenLockPreferred: _screenLockPreferred,
      );
    }
    return _PhonePeLockScreen(
      title: widget.title,
      subtitle: widget.subtitle,
      error: _unlockError,
      availability: _availability,
      authenticating: _authInProgress,
      onUnlock: () => unawaited(_unlock()),
      onScreenLock: () => unawaited(_unlock(preferScreenLock: true)),
      graceSeconds: widget.lockAfterSeconds,
      lastBackgroundedAt: _lastBackgroundedAt,
    );
  }
}

class _PhonePeCheckingScreen extends StatelessWidget {
  const _PhonePeCheckingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF7F8F4),
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF5F7F55)),
          ),
        ),
      ),
    );
  }
}

class _PhonePeAuthenticatingScreen extends StatelessWidget {
  const _PhonePeAuthenticatingScreen({
    required this.title,
    required this.subtitle,
    required this.screenLockPreferred,
  });

  final String title;
  final String subtitle;
  final bool screenLockPreferred;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F4),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _PhonePeAuthCard(
              title: title,
              subtitle: subtitle,
              icon: screenLockPreferred ? Icons.password_rounded : Icons.fingerprint_rounded,
              footer: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF5F7F55)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhonePeLockScreen extends StatelessWidget {
  const _PhonePeLockScreen({
    required this.title,
    required this.subtitle,
    required this.error,
    required this.availability,
    required this.authenticating,
    required this.onUnlock,
    required this.onScreenLock,
    required this.graceSeconds,
    required this.lastBackgroundedAt,
  });

  final String title;
  final String subtitle;
  final String? error;
  final BiometricAvailability? availability;
  final bool authenticating;
  final VoidCallback onUnlock;
  final VoidCallback onScreenLock;
  final int graceSeconds;
  final DateTime? lastBackgroundedAt;

  @override
  Widget build(BuildContext context) {
    final hasBiometric = availability?.hasBiometric ?? true;
    final hasScreenLock = availability?.hasScreenLockFallback ?? true;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F4),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _PhonePeAuthCard(
              title: title,
              subtitle: subtitle,
              icon: Icons.lock_rounded,
              error: error,
              chips: <Widget>[
                _PhonePeSecurityChip(
                  icon: Icons.fingerprint_rounded,
                  label: hasBiometric ? 'Fingerprint ready' : 'Fingerprint optional',
                ),
                _PhonePeSecurityChip(
                  icon: Icons.password_rounded,
                  label: hasScreenLock ? 'Phone lock fallback' : 'Set phone lock',
                ),
              ],
              footer: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: authenticating ? null : onUnlock,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5F7F55),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
                      ),
                      icon: authenticating
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.lock_open_rounded),
                      label: Text(authenticating ? 'Checking…' : 'Unlock with device lock'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: authenticating ? null : onScreenLock,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF5F7F55),
                        side: const BorderSide(color: Color(0xFFD8DED4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        backgroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.password_rounded),
                      label: const Text('Use phone screen lock'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Security check is required after $graceSeconds seconds away from the app.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF7A8278), fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhonePeAuthCard extends StatelessWidget {
  const _PhonePeAuthCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.footer,
    this.error,
    this.chips = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget footer;
  final String? error;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFD8DED4)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.08), blurRadius: 34, offset: const Offset(0, 18))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: const Color(0xFF5F7F55).withOpacity(.10),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF5F7F55).withOpacity(.14)),
              ),
              child: Icon(icon, color: const Color(0xFF5F7F55), size: 42),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF0F140F), fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -.4),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF5F675E), fontSize: 13.2, fontWeight: FontWeight.w700, height: 1.35),
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: chips,
              ),
            ],
            if (error != null && error!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withOpacity(.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDC2626).withOpacity(.13)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w800, fontSize: 12.2, height: 1.25),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            footer,
          ],
        ),
      ),
    );
  }
}

class _PhonePeSecurityChip extends StatelessWidget {
  const _PhonePeSecurityChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF5F7F55).withOpacity(.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF5F7F55).withOpacity(.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF5F7F55)),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF5F7F55), fontWeight: FontWeight.w900, fontSize: 10.8),
          ),
        ],
      ),
    );
  }
}
