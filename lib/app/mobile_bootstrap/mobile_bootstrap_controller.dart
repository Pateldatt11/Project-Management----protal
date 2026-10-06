import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mobile_ui_cache_service.dart';

class MobileBootstrapDecision {
  const MobileBootstrapDecision({
    required this.showBlockingInitialization,
    required this.hasUsableUiCache,
    required this.firstBootstrapDone,
    this.cachedConfig,
  });

  final bool showBlockingInitialization;
  final bool hasUsableUiCache;
  final bool firstBootstrapDone;
  final Map<String, dynamic>? cachedConfig;
}

class MobileBootstrapController extends ChangeNotifier {
  MobileBootstrapController({
    required MobileUiCacheService cacheService,
    required Future<Map<String, dynamic>> Function(String companyId) fetchRemoteUiConfig,
    Future<void> Function(String uid, String companyId)? preloadWorkspace,
  })  : _cacheService = cacheService,
        _fetchRemoteUiConfig = fetchRemoteUiConfig,
        _preloadWorkspace = preloadWorkspace;

  final MobileUiCacheService _cacheService;
  final Future<Map<String, dynamic>> Function(String companyId) _fetchRemoteUiConfig;
  final Future<void> Function(String uid, String companyId)? _preloadWorkspace;

  bool _backgroundRefreshRunning = false;
  Map<String, dynamic>? _activeConfig;

  Map<String, dynamic>? get activeConfig => _activeConfig;

  Future<MobileBootstrapDecision> decide({
    required String uid,
    required String companyId,
  }) async {
    final cached = await _cacheService.readActiveConfig(companyId);
    final hasUsableCache = cached != null && _cacheService.isUsableConfig(cached);
    final firstBootstrapDone = await _cacheService.hasBootstrapCompleted(uid: uid, companyId: companyId);
    _activeConfig = hasUsableCache ? cached : null;

    return MobileBootstrapDecision(
      showBlockingInitialization: !firstBootstrapDone || !hasUsableCache,
      hasUsableUiCache: hasUsableCache,
      firstBootstrapDone: firstBootstrapDone,
      cachedConfig: _activeConfig,
    );
  }

  /// Visible initialization path. Use this only for a fresh signed-in user or when cache is empty/broken.
  Future<Map<String, dynamic>> runBlockingInitialization({
    required String uid,
    required String companyId,
    void Function(String message)? onStatus,
  }) async {
    onStatus?.call('Loading company profile and permissions…');
    await _preloadWorkspace?.call(uid, companyId);

    onStatus?.call('Downloading mobile UI configuration…');
    final remoteConfig = await _fetchRemoteUiConfig(companyId);

    onStatus?.call('Preparing your workspace…');
    await _cacheService.saveActiveConfigAtomically(companyId: companyId, config: remoteConfig);
    await _cacheService.markBootstrapCompleted(uid: uid, companyId: companyId);

    _activeConfig = remoteConfig;
    notifyListeners();
    return remoteConfig;
  }

  /// Returning user path. Current cached UI stays visible; update happens silently.
  void startBackgroundRefresh({
    required String companyId,
    bool notifyWhenUpdated = true,
  }) {
    if (_backgroundRefreshRunning) return;
    _backgroundRefreshRunning = true;

    unawaited(() async {
      try {
        final oldVersion = _cacheService.cachedVersion(companyId);
        final remoteConfig = await _fetchRemoteUiConfig(companyId);
        final newVersion = _cacheService.versionOf(remoteConfig);

        // If version is missing, still update only when the JSON validates. If version exists,
        // skip equal/older versions to avoid unnecessary rebuilds.
        if (newVersion > 0 && oldVersion > 0 && newVersion <= oldVersion) return;

        await _cacheService.saveActiveConfigAtomically(companyId: companyId, config: remoteConfig);
        _activeConfig = remoteConfig;
        if (notifyWhenUpdated) notifyListeners();
      } catch (error, stackTrace) {
        debugPrint('Background mobile SDUI refresh failed: $error');
        debugPrint('$stackTrace');
        await _cacheService.recordLastError(companyId, error);
      } finally {
        _backgroundRefreshRunning = false;
      }
    }());
  }
}
