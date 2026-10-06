import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NavigationPlacement {
  automatic,
  left,
  right,
  top,
  bottom,
}

enum NavigationDisplayMode {
  expanded,
  compact,
  iconsOnly,
}

enum NavigationAnimationStyle {
  system,
  smooth,
  fast,
  disabled,
}

@immutable
class NavigationPreferences {
  const NavigationPreferences({
    this.placement = NavigationPlacement.automatic,
    this.displayMode = NavigationDisplayMode.expanded,
    this.animationStyle = NavigationAnimationStyle.smooth,
    this.autoCollapseOnTimeline = true,
    this.expandOnHover = false,
    this.restoreAfterTimeline = true,
  });

  final NavigationPlacement placement;
  final NavigationDisplayMode displayMode;
  final NavigationAnimationStyle animationStyle;
  final bool autoCollapseOnTimeline;
  final bool expandOnHover;
  final bool restoreAfterTimeline;

  static const NavigationPreferences defaults = NavigationPreferences();

  NavigationPreferences copyWith({
    NavigationPlacement? placement,
    NavigationDisplayMode? displayMode,
    NavigationAnimationStyle? animationStyle,
    bool? autoCollapseOnTimeline,
    bool? expandOnHover,
    bool? restoreAfterTimeline,
  }) {
    return NavigationPreferences(
      placement: placement ?? this.placement,
      displayMode: displayMode ?? this.displayMode,
      animationStyle: animationStyle ?? this.animationStyle,
      autoCollapseOnTimeline:
          autoCollapseOnTimeline ?? this.autoCollapseOnTimeline,
      expandOnHover: expandOnHover ?? this.expandOnHover,
      restoreAfterTimeline:
          restoreAfterTimeline ?? this.restoreAfterTimeline,
    );
  }

  factory NavigationPreferences.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    return NavigationPreferences(
      placement: _enumByName(
        NavigationPlacement.values,
        data['placement'],
        NavigationPlacement.automatic,
      ),
      displayMode: _enumByName(
        NavigationDisplayMode.values,
        data['displayMode'],
        NavigationDisplayMode.expanded,
      ),
      animationStyle: _enumByName(
        NavigationAnimationStyle.values,
        data['animationStyle'],
        NavigationAnimationStyle.smooth,
      ),
      autoCollapseOnTimeline:
          _boolValue(data['autoCollapseOnTimeline'], fallback: true),
      expandOnHover: _boolValue(data['expandOnHover']),
      restoreAfterTimeline:
          _boolValue(data['restoreAfterTimeline'], fallback: true),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'placement': placement.name,
        'displayMode': displayMode.name,
        'animationStyle': animationStyle.name,
        'autoCollapseOnTimeline': autoCollapseOnTimeline,
        'expandOnHover': expandOnHover,
        'restoreAfterTimeline': restoreAfterTimeline,
        'scope': 'webOnly',
      };

  static T _enumByName<T extends Enum>(
    Iterable<T> values,
    dynamic raw,
    T fallback,
  ) {
    final name = raw?.toString().trim();
    if (name == null || name.isEmpty) return fallback;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static bool _boolValue(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) {
    return other is NavigationPreferences &&
        other.placement == placement &&
        other.displayMode == displayMode &&
        other.animationStyle == animationStyle &&
        other.autoCollapseOnTimeline == autoCollapseOnTimeline &&
        other.expandOnHover == expandOnHover &&
        other.restoreAfterTimeline == restoreAfterTimeline;
  }

  @override
  int get hashCode => Object.hash(
        placement,
        displayMode,
        animationStyle,
        autoCollapseOnTimeline,
        expandOnHover,
        restoreAfterTimeline,
      );
}

final navigationPreferencesProvider = StateNotifierProvider<
    NavigationPreferencesController, NavigationPreferences>((ref) {
  return NavigationPreferencesController();
});

/// Personal web-dashboard navigation preferences.
///
/// Deliberately does nothing on Android/iOS. The APK continues to use its
/// existing SDUI navigation configuration and never reads these preferences.
class NavigationPreferencesController
    extends StateNotifier<NavigationPreferences> {
  NavigationPreferencesController() : super(NavigationPreferences.defaults);

  String? _boundIdentity;
  int _loadGeneration = 0;

  Future<void> bindWebUser({
    required String companyId,
    required String userId,
  }) async {
    if (!kIsWeb) return;

    final identity = _identity(companyId, userId);
    if (identity == _boundIdentity) return;
    _boundIdentity = identity;
    final generation = ++_loadGeneration;

    final local = await _readLocal(identity);
    if (generation != _loadGeneration) return;
    state = local ?? NavigationPreferences.defaults;
  }

  void preview(NavigationPreferences next) {
    if (!kIsWeb || next == state) return;
    state = next;
  }

  Future<void> saveForWebUser({
    required String companyId,
    required String userId,
    required NavigationPreferences preferences,
  }) async {
    if (!kIsWeb) return;

    final identity = _identity(companyId, userId);
    _boundIdentity = identity;
    state = preferences;
    await _writeLocal(identity, preferences);
  }

  Future<void> resetForWebUser({
    required String companyId,
    required String userId,
  }) {
    return saveForWebUser(
      companyId: companyId,
      userId: userId,
      preferences: NavigationPreferences.defaults,
    );
  }

  Future<NavigationPreferences?> _readLocal(String identity) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey(identity));
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return NavigationPreferences.fromMap(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLocal(
    String identity,
    NavigationPreferences preferences,
  ) async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.setString(
        _storageKey(identity),
        jsonEncode(preferences.toMap()),
      );
    } catch (_) {
      // Keep the current in-memory preference when browser storage is blocked.
    }
  }

  String _identity(String companyId, String userId) {
    final company = companyId.trim().isEmpty ? 'platform' : companyId.trim();
    final user = userId.trim().isEmpty ? 'anonymous' : userId.trim();
    return '$company::$user';
  }

  String _storageKey(String identity) {
    return 'web_navigation_preferences_v289::$identity';
  }
}
