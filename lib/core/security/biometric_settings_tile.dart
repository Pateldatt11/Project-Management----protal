import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'biometric_auth_service.dart';

/// Profile settings tile for enabling/disabling local biometric + device
/// screen-password app lock.
class BiometricSettingsTile extends StatefulWidget {
  const BiometricSettingsTile({
    super.key,
    required this.uid,
    required this.companyId,
    this.title = 'Device lock protection',
    this.subtitle = 'PhonePe-style unlock: fingerprint first, phone screen lock as fallback.',
    this.previewMode = false,
  });

  final String uid;
  final String companyId;
  final String title;
  final String subtitle;

  /// Admin Mobile UI Designer preview must show this hardcoded app-lock
  /// setting without calling the OS security prompt. The real APK uses
  /// local_auth only when previewMode is false.
  final bool previewMode;

  @override
  State<BiometricSettingsTile> createState() => _BiometricSettingsTileState();
}

class _BiometricSettingsTileState extends State<BiometricSettingsTile> {
  BiometricAuthService? _service;
  BiometricAvailability? _availability;
  bool _enabled = false;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (widget.previewMode) {
      if (!mounted) return;
      setState(() {
        _service = null;
        _availability = const BiometricAvailability(
          supported: true,
          enrolled: true,
          deviceCredentialSupported: true,
          label: 'Admin preview only. Real device-lock prompt appears in the APK.',
          types: <BiometricType>[],
        );
        _enabled = false;
        _busy = false;
      });
      return;
    }

    final service = await BiometricAuthService.create();
    final availability = await service.availability();
    final enabled = await service.isEnabled(uid: widget.uid, companyId: widget.companyId);
    if (!mounted) return;
    setState(() {
      _service = service;
      _availability = availability;
      _enabled = enabled;
      _busy = false;
    });
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;

    if (widget.previewMode) {
      setState(() => _enabled = value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? 'App lock enabled in preview only.' : 'App lock disabled in preview only.')),
      );
      return;
    }

    final service = _service;
    final availability = _availability;
    if (service == null || availability == null) return;
    setState(() => _busy = true);

    var next = _enabled;
    var message = '';
    if (value) {
      if (!availability.canEnableSecureLock) {
        message = availability.label;
      } else {
        final ok = await service.enable(uid: widget.uid, companyId: widget.companyId);
        next = ok;
        message = ok ? 'Device lock protection enabled.' : 'Security confirmation was cancelled.';
      }
    } else {
      await service.disable(uid: widget.uid, companyId: widget.companyId);
      next = false;
      message = 'App lock disabled.';
    }

    if (!mounted) return;
    setState(() {
      _enabled = next;
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availability = _availability;
    final canEnable = availability?.canEnableSecureLock ?? false;
    final subtitle = availability == null
        ? widget.subtitle
        : canEnable
            ? widget.subtitle
            : availability.label;
    final fallbackLabel = availability?.hasScreenLockFallback == true ? 'Phone screen lock • 5 sec timeout' : '5 sec timeout';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD8DED4)),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: _enabled,
            onChanged: _busy ? null : _toggle,
            secondary: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: const Color(0xFF5F7F55).withOpacity(.10), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.lock_rounded, color: Color(0xFF5F7F55)),
            ),
            title: Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: const Color(0xFF0F140F))),
            subtitle: Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF5F675E))),
            activeColor: const Color(0xFF5F7F55),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                _SecurityChip(icon: Icons.fingerprint_rounded, label: availability?.hasBiometric == true ? 'Fingerprint ready' : 'Fingerprint optional'),
                const SizedBox(width: 8),
                Expanded(child: _SecurityChip(icon: Icons.password_rounded, label: fallbackLabel)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityChip extends StatelessWidget {
  const _SecurityChip({required this.icon, required this.label});

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
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF5F7F55), fontWeight: FontWeight.w900, fontSize: 10.8),
            ),
          ),
        ],
      ),
    );
  }
}
