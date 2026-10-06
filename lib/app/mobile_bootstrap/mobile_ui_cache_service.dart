import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local cache for mobile SDUI JSON.
///
/// Production rule:
/// - Never clear this cache on logout.
/// - Never overwrite the active cache until the replacement JSON is valid.
/// - Returning users render this cached config immediately while Firestore refreshes in background.
class MobileUiCacheService {
  MobileUiCacheService._(this._prefs);

  final SharedPreferences _prefs;

  static Future<MobileUiCacheService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return MobileUiCacheService._(prefs);
  }

  static String bootDoneKey(String uid, String companyId) => 'mobile_bootstrap_done_${uid}_$companyId';
  static String uiCacheKey(String companyId) => 'mobile_sdui_cache_$companyId';
  static String uiTempCacheKey(String companyId) => 'mobile_sdui_cache_tmp_$companyId';
  static String uiVersionKey(String companyId) => 'mobile_sdui_version_$companyId';
  static String uiUpdatedAtKey(String companyId) => 'mobile_sdui_updated_at_$companyId';
  static String uiLastErrorKey(String companyId) => 'mobile_sdui_last_error_$companyId';

  Future<bool> hasBootstrapCompleted({required String uid, required String companyId}) async {
    return _prefs.getBool(bootDoneKey(uid, companyId)) ?? false;
  }

  Future<void> markBootstrapCompleted({required String uid, required String companyId}) async {
    await _prefs.setBool(bootDoneKey(uid, companyId), true);
  }

  Future<bool> hasUsableUiCache(String companyId) async {
    final cached = await readActiveConfig(companyId);
    return cached != null && isUsableConfig(cached);
  }

  Future<Map<String, dynamic>?> readActiveConfig(String companyId) async {
    final raw = _prefs.getString(uiCacheKey(companyId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.map((key, value) => MapEntry(key.toString(), value));
      return null;
    } catch (error, stackTrace) {
      debugPrint('Mobile UI cache read failed: $error');
      debugPrint('$stackTrace');
      return null;
    }
  }

  int cachedVersion(String companyId) => _prefs.getInt(uiVersionKey(companyId)) ?? 0;

  Future<void> saveActiveConfigAtomically({
    required String companyId,
    required Map<String, dynamic> config,
  }) async {
    validateConfig(config);
    final encoded = const JsonEncoder.withIndent('  ').convert(config);

    // Stage first.
    await _prefs.setString(uiTempCacheKey(companyId), encoded);

    // Verify staged payload can be decoded and still passes validation.
    final staged = _prefs.getString(uiTempCacheKey(companyId));
    if (staged == null || staged.trim().isEmpty) {
      throw StateError('Failed to stage mobile SDUI cache.');
    }
    final decoded = jsonDecode(staged);
    final stagedMap = decoded is Map<String, dynamic>
        ? decoded
        : decoded is Map
            ? decoded.map((key, value) => MapEntry(key.toString(), value))
            : null;
    if (stagedMap == null) {
      throw FormatException('Staged mobile SDUI cache is not a JSON object.');
    }
    validateConfig(stagedMap);

    // Commit only after the staged JSON is known-good.
    await _prefs.setString(uiCacheKey(companyId), staged);
    await _prefs.setInt(uiVersionKey(companyId), versionOf(stagedMap));
    await _prefs.setString(uiUpdatedAtKey(companyId), DateTime.now().toUtc().toIso8601String());
    await _prefs.remove(uiTempCacheKey(companyId));
    await _prefs.remove(uiLastErrorKey(companyId));
  }

  Future<void> recordLastError(String companyId, Object error) async {
    await _prefs.setString(uiLastErrorKey(companyId), error.toString());
  }

  /// Clears only user/session bootstrap markers. It intentionally keeps the SDUI cache.
  Future<void> clearSessionOnly({required String uid, required String companyId}) async {
    await _prefs.remove(bootDoneKey(uid, companyId));
  }

  bool isUsableConfig(Map<String, dynamic> config) {
    try {
      validateConfig(config);
      return true;
    } catch (_) {
      return false;
    }
  }

  void validateConfig(Map<String, dynamic> config) {
    if (config.isEmpty) throw FormatException('Mobile SDUI config is empty.');
    if (config['enabled'] == false) throw FormatException('Mobile SDUI config is disabled.');
    final hasRenderableScreenOverrides = config['screenOverrides'] is Map && (config['screenOverrides'] as Map).isNotEmpty;
    final hasScreenConfigs = config['screenConfigs'] is Map && (config['screenConfigs'] as Map).isNotEmpty;
    final hasTabs = config['bottomTabs'] is List || config['navigationGraph'] is Map;
    if (!hasRenderableScreenOverrides && !hasScreenConfigs && !hasTabs) {
      throw FormatException('Mobile SDUI config does not contain renderable screen/tabs data.');
    }
  }

  int versionOf(Map<String, dynamic> config) {
    final raw = config['version'] ?? config['minRendererVersion'];
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
