import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TimelineDefaultScale {
  day,
  week,
  month,
  quarter,
}

enum TimelineDefaultGrouping {
  project,
  assignee,
  status,
  department,
}

@immutable
class TimelinePreferences {
  const TimelinePreferences({
    this.enabled = true,
    this.showOriginalProjectPlan = true,
    this.autoFitOriginalProjectPlan = true,
    this.showTaskBaselines = true,
    this.showCriticalPath = true,
    this.showTodayLine = true,
    this.defaultScale = TimelineDefaultScale.week,
    this.defaultGrouping = TimelineDefaultGrouping.project,
  });

  final bool enabled;
  final bool showOriginalProjectPlan;
  final bool autoFitOriginalProjectPlan;
  final bool showTaskBaselines;
  final bool showCriticalPath;
  final bool showTodayLine;
  final TimelineDefaultScale defaultScale;
  final TimelineDefaultGrouping defaultGrouping;

  static const TimelinePreferences defaults = TimelinePreferences();

  TimelinePreferences copyWith({
    bool? enabled,
    bool? showOriginalProjectPlan,
    bool? autoFitOriginalProjectPlan,
    bool? showTaskBaselines,
    bool? showCriticalPath,
    bool? showTodayLine,
    TimelineDefaultScale? defaultScale,
    TimelineDefaultGrouping? defaultGrouping,
  }) {
    return TimelinePreferences(
      enabled: enabled ?? this.enabled,
      showOriginalProjectPlan:
          showOriginalProjectPlan ?? this.showOriginalProjectPlan,
      autoFitOriginalProjectPlan:
          autoFitOriginalProjectPlan ?? this.autoFitOriginalProjectPlan,
      showTaskBaselines: showTaskBaselines ?? this.showTaskBaselines,
      showCriticalPath: showCriticalPath ?? this.showCriticalPath,
      showTodayLine: showTodayLine ?? this.showTodayLine,
      defaultScale: defaultScale ?? this.defaultScale,
      defaultGrouping: defaultGrouping ?? this.defaultGrouping,
    );
  }

  factory TimelinePreferences.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    return TimelinePreferences(
      enabled: _boolValue(data['enabled'], fallback: true),
      showOriginalProjectPlan:
          _boolValue(data['showOriginalProjectPlan'], fallback: true),
      autoFitOriginalProjectPlan:
          _boolValue(data['autoFitOriginalProjectPlan'], fallback: true),
      showTaskBaselines:
          _boolValue(data['showTaskBaselines'], fallback: true),
      showCriticalPath:
          _boolValue(data['showCriticalPath'], fallback: true),
      showTodayLine: _boolValue(data['showTodayLine'], fallback: true),
      defaultScale: _enumByName(
        TimelineDefaultScale.values,
        data['defaultScale'],
        TimelineDefaultScale.week,
      ),
      defaultGrouping: _enumByName(
        TimelineDefaultGrouping.values,
        data['defaultGrouping'],
        TimelineDefaultGrouping.project,
      ),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'enabled': enabled,
        'showOriginalProjectPlan': showOriginalProjectPlan,
        'autoFitOriginalProjectPlan': autoFitOriginalProjectPlan,
        'showTaskBaselines': showTaskBaselines,
        'showCriticalPath': showCriticalPath,
        'showTodayLine': showTodayLine,
        'defaultScale': defaultScale.name,
        'defaultGrouping': defaultGrouping.name,
        'scope': 'webTimelineOnly',
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
    return other is TimelinePreferences &&
        other.enabled == enabled &&
        other.showOriginalProjectPlan == showOriginalProjectPlan &&
        other.autoFitOriginalProjectPlan == autoFitOriginalProjectPlan &&
        other.showTaskBaselines == showTaskBaselines &&
        other.showCriticalPath == showCriticalPath &&
        other.showTodayLine == showTodayLine &&
        other.defaultScale == defaultScale &&
        other.defaultGrouping == defaultGrouping;
  }

  @override
  int get hashCode => Object.hash(
        enabled,
        showOriginalProjectPlan,
        autoFitOriginalProjectPlan,
        showTaskBaselines,
        showCriticalPath,
        showTodayLine,
        defaultScale,
        defaultGrouping,
      );
}

final timelinePreferencesProvider = StateNotifierProvider<
    TimelinePreferencesController, TimelinePreferences>((ref) {
  return TimelinePreferencesController();
});

/// Web-only personal Timeline preferences.
///
/// Android/iOS employee APK navigation and SDUI configuration never read this
/// provider. The settings only control the web/admin realtime Timeline screen.
class TimelinePreferencesController
    extends StateNotifier<TimelinePreferences> {
  TimelinePreferencesController() : super(TimelinePreferences.defaults);

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
    state = local ?? TimelinePreferences.defaults;
  }

  void preview(TimelinePreferences next) {
    if (!kIsWeb || next == state) return;
    state = next;
  }

  Future<void> saveForWebUser({
    required String companyId,
    required String userId,
    required TimelinePreferences preferences,
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
      preferences: TimelinePreferences.defaults,
    );
  }

  Future<TimelinePreferences?> _readLocal(String identity) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey(identity));
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return TimelinePreferences.fromMap(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLocal(
    String identity,
    TimelinePreferences preferences,
  ) async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.setString(
        _storageKey(identity),
        jsonEncode(preferences.toMap()),
      );
    } catch (_) {
      // Keep the current in-memory setting if browser storage is unavailable.
    }
  }

  String _identity(String companyId, String userId) {
    final company = companyId.trim().isEmpty ? 'platform' : companyId.trim();
    final user = userId.trim().isEmpty ? 'anonymous' : userId.trim();
    return '$company::$user';
  }

  String _storageKey(String identity) {
    return 'web_timeline_preferences_v294::$identity';
  }
}
