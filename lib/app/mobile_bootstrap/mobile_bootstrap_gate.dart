import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'firebase_initialization_screen.dart';
import 'mobile_bootstrap_controller.dart';
import 'mobile_ui_cache_service.dart';

typedef MobileCompanyIdResolver = Future<String> Function(User user);
typedef MobileRemoteUiFetcher = Future<Map<String, dynamic>> Function(String companyId);
typedef MobileWorkspacePreloader = Future<void> Function(User user, String companyId);
typedef MobileAppBuilder = Widget Function(BuildContext context, Map<String, dynamic>? initialUiConfig);

/// Gate that implements the production startup policy:
///
/// Fresh user / empty cache:
///   show visible Firebase initialization once, then enter app.
///
/// Returning user with usable cache:
///   render cached UI immediately, then refresh Firestore UI in background.
class MobileBootstrapGate extends StatefulWidget {
  const MobileBootstrapGate({
    super.key,
    required this.user,
    required this.loginBuilder,
    required this.companyIdResolver,
    required this.remoteUiFetcher,
    required this.appBuilder,
    this.workspacePreloader,
    this.initializationTitle = 'Setting up your workspace',
    this.initializationSubtitle = 'Loading company profile, permissions, and mobile UI…',
  });

  final User? user;
  final WidgetBuilder loginBuilder;
  final MobileCompanyIdResolver companyIdResolver;
  final MobileRemoteUiFetcher remoteUiFetcher;
  final MobileWorkspacePreloader? workspacePreloader;
  final MobileAppBuilder appBuilder;
  final String initializationTitle;
  final String initializationSubtitle;

  @override
  State<MobileBootstrapGate> createState() => _MobileBootstrapGateState();
}

class _MobileBootstrapGateState extends State<MobileBootstrapGate> {
  MobileBootstrapController? _controller;
  MobileUiCacheService? _cacheService;
  String? _uid;
  String? _companyId;
  Map<String, dynamic>? _initialUiConfig;
  bool _checking = true;
  bool _blockingInit = false;
  Object? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void didUpdateWidget(covariant MobileBootstrapGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUid = oldWidget.user?.uid;
    final newUid = widget.user?.uid;
    if (oldUid != newUid) {
      _controller?.removeListener(_handleControllerUpdate);
      _controller = null;
      _cacheService = null;
      _uid = null;
      _companyId = null;
      _initialUiConfig = null;
      _checking = true;
      _blockingInit = false;
      _error = null;
      _status = null;
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerUpdate);
    super.dispose();
  }

  Future<void> _start() async {
    final user = widget.user;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _blockingInit = false;
        _error = null;
      });
      return;
    }

    try {
      final cache = await MobileUiCacheService.create();
      final companyId = await widget.companyIdResolver(user);
      if (companyId.trim().isEmpty) throw StateError('Company ID could not be resolved for this user.');

      final controller = MobileBootstrapController(
        cacheService: cache,
        fetchRemoteUiConfig: widget.remoteUiFetcher,
        preloadWorkspace: widget.workspacePreloader == null ? null : (uid, cid) => widget.workspacePreloader!(user, cid),
      )..addListener(_handleControllerUpdate);

      final decision = await controller.decide(uid: user.uid, companyId: companyId);
      if (!mounted) return;

      _cacheService = cache;
      _controller = controller;
      _uid = user.uid;
      _companyId = companyId;
      _initialUiConfig = decision.cachedConfig;

      if (decision.showBlockingInitialization) {
        setState(() {
          _checking = false;
          _blockingInit = true;
          _error = null;
          _status = 'Connecting to Firebase…';
        });
        await _runBlockingInit();
        return;
      }

      // Returning user: show cached UI instantly and refresh silently.
      setState(() {
        _checking = false;
        _blockingInit = false;
        _error = null;
      });
      controller.startBackgroundRefresh(companyId: companyId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _blockingInit = true;
        _error = error;
      });
    }
  }

  Future<void> _runBlockingInit() async {
    final user = widget.user;
    final uid = _uid ?? user?.uid;
    final companyId = _companyId;
    final controller = _controller;
    if (uid == null || companyId == null || controller == null) return;

    try {
      final config = await controller.runBlockingInitialization(
        uid: uid,
        companyId: companyId,
        onStatus: (message) {
          if (!mounted) return;
          setState(() => _status = message);
        },
      );
      if (!mounted) return;
      setState(() {
        _initialUiConfig = config;
        _blockingInit = false;
        _checking = false;
        _error = null;
        _status = null;
      });
    } catch (error) {
      if (!mounted) return;
      await _cacheService?.recordLastError(companyId, error);
      setState(() {
        _blockingInit = true;
        _checking = false;
        _error = error;
      });
    }
  }

  void _handleControllerUpdate() {
    final config = _controller?.activeConfig;
    if (!mounted || config == null) return;
    setState(() => _initialUiConfig = config);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.user == null) return widget.loginBuilder(context);

    if (_checking || _blockingInit) {
      return FirebaseInitializationScreen(
        title: widget.initializationTitle,
        subtitle: widget.initializationSubtitle,
        status: _status,
        error: _error,
        onRetry: () {
          setState(() {
            _error = null;
            _status = 'Retrying setup…';
          });
          unawaited(_runBlockingInit());
        },
      );
    }

    return widget.appBuilder(context, _initialUiConfig);
  }
}
