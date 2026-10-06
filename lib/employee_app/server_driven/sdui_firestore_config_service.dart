import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/firebase/firebase_paths.dart';
import 'sdui_mobile_ui_config.dart';

/// Firestore loader for the active mobile SDUI config.
///
/// Release APK default merge:
///   companies/{companyId}/uiConfigs/mobileEmployee
/// + companies/{companyId}/uiConfigs/mobileEmployeeDesign
/// + companies/{companyId}/uiConfigs/mobileEmployeeScreens
///
/// Test APK merge:
///   flutter build apk --release --dart-define=SDUI_CONFIG_DOC=mobileEmployeeNext
///
/// Then this service reads:
///   mobileEmployeeNext + mobileEmployeeNextDesign + mobileEmployeeNextScreens
class SduiFirestoreConfigService {
  SduiFirestoreConfigService({
    required this.companyId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final String companyId;
  final FirebaseFirestore _firestore;

  static const String _configuredActiveDocId = String.fromEnvironment(
    'SDUI_CONFIG_DOC',
    defaultValue: 'mobileEmployee',
  );

  String get activeDocId {
    final trimmed = _configuredActiveDocId.trim();
    if (trimmed.isEmpty || trimmed.contains('/') || trimmed.contains('..')) {
      return 'mobileEmployee';
    }
    return trimmed;
  }

  String get activeDesignDocId {
    return activeDocId == 'mobileEmployeeNext' ? 'mobileEmployeeNextDesign' : 'mobileEmployeeDesign';
  }

  String get activeScreensDocId {
    return activeDocId == 'mobileEmployeeNext' ? 'mobileEmployeeNextScreens' : 'mobileEmployeeScreens';
  }

  DocumentReference<Map<String, dynamic>> get activeConfigRef => _firestore.doc(
        FirebasePaths.mobileEmployeeUiConfigDoc(companyId, activeDocId),
      );

  DocumentReference<Map<String, dynamic>> get activeDesignRef => _firestore.doc(
        FirebasePaths.mobileEmployeeUiConfigDoc(companyId, activeDesignDocId),
      );

  DocumentReference<Map<String, dynamic>> get activeScreensRef => _firestore.doc(
        FirebasePaths.mobileEmployeeUiConfigDoc(companyId, activeScreensDocId),
      );

  DocumentReference<Map<String, dynamic>> get previewConfigRef => _firestore.doc(
        FirebasePaths.mobileEmployeeUiConfigDoc(
          companyId,
          activeDocId == 'mobileEmployeeNext' ? 'mobileEmployeeNextDesignDraft' : 'mobileEmployeeDesignDraft',
        ),
      );

  CollectionReference<Map<String, dynamic>> get versionsRef => activeConfigRef.collection('versions');

  Stream<SduiMobileUiConfig> watchActiveConfig() {
    return activeConfigRef.snapshots().asyncMap((_) => loadActiveConfig());
  }

  Future<SduiMobileUiConfig> loadActiveConfig() async {
    final merged = await loadMergedActiveConfigMap();
    return SduiMobileUiConfig.fromFirestore(merged);
  }

  Future<Map<String, dynamic>> loadMergedActiveConfigMap() async {
    var core = await _readConfig(activeDocId);
    if (core.isEmpty && activeDocId != 'mobileEmployee') {
      final releaseCore = await _readConfig('mobileEmployee');
      if (releaseCore.isNotEmpty) core = releaseCore;
    }
    final design = await _readConfig(activeDesignDocId);
    final screens = await _readConfig(activeScreensDocId);

    var merged = _deepMergeRuntimeMaps(core, design);
    merged = _deepMergeRuntimeMaps(merged, screens);

    final mergedVersion = <int>[
      _runtimeVersionOf(core),
      _runtimeVersionOf(design),
      _runtimeVersionOf(screens),
      _runtimeVersionOf(merged),
    ].fold<int>(1, (max, value) => value > max ? value : max);

    return <String, dynamic>{
      ...merged,
      'enabled': merged['enabled'] ?? true,
      'version': mergedVersion,
      'targetDocId': activeDocId,
      'sourceCoreDocId': activeDocId,
      'sourceDesignDocId': activeDesignDocId,
      'sourceScreensDocId': activeScreensDocId,
      'apkSplitDocMergeEnabled': true,
      'apkSplitDocMergeOrder': <String>['core', 'design', 'screens'],
    };
  }

  Future<void> savePreview(Map<String, dynamic> config, {required String updatedBy}) {
    return previewConfigRef.set({
      ...config,
      'targetDocId': activeDocId,
      'updatedBy': updatedBy,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Publishes the design/UI layer for the current active SDUI target.
  ///
  /// This intentionally writes the design doc, not only the core doc, so the
  /// Test APK and admin preview both keep the same split-doc structure.
  Future<void> publishGlobalConfig(Map<String, dynamic> config, {required String updatedBy}) async {
    final designRef = activeDesignRef;
    final designSnap = await designRef.get();
    final designData = designSnap.data();
    final designVersion = designData?['version']?.toString();

    await _firestore.runTransaction((tx) async {
      if (designData != null && designVersion != null && designVersion.isNotEmpty) {
        tx.set(designRef.collection('versions').doc('v$designVersion'), {
          ...designData,
          'backupCreatedAt': DateTime.now().toIso8601String(),
          'backupReason': 'before_global_sdui_design_publish',
          'targetDocId': activeDocId,
        }, SetOptions(merge: true));
      }

      final nextVersion = config['version'];
      tx.set(designRef, {
        ...config,
        'enabled': config['enabled'] ?? true,
        'targetDocId': activeDocId,
        'publishTarget': activeDocId == 'mobileEmployeeNext' ? 'test' : 'release',
        'updatedBy': updatedBy,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      if (nextVersion != null) {
        tx.set(designRef.collection('versions').doc('v$nextVersion'), {
          ...config,
          'targetDocId': activeDocId,
          'updatedBy': updatedBy,
          'updatedAt': DateTime.now().toIso8601String(),
          'savedAsRollbackVersion': true,
        }, SetOptions(merge: true));
      }
    });
  }

  Future<Map<String, dynamic>> _readConfig(String docId) async {
    final snap = await _firestore
        .doc(FirebasePaths.mobileEmployeeUiConfigDoc(companyId, docId))
        .get(const GetOptions(source: Source.serverAndCache));
    return _extractSduiConfig(snap.data());
  }

  static Map<String, dynamic> _extractSduiConfig(Map<String, dynamic>? rawData) {
    if (rawData == null || rawData.isEmpty) return const <String, dynamic>{};
    final wrappedConfig = rawData['config'];
    if (wrappedConfig is Map) {
      return wrappedConfig.map((key, value) => MapEntry(key.toString(), value));
    }
    return rawData.map((key, value) => MapEntry(key.toString(), value));
  }

  static Map<String, dynamic> _cloneRuntimeMap(Map<String, dynamic> source) {
    return source.map((key, value) {
      if (value is Map) {
        return MapEntry(key, _cloneRuntimeMap(value.map((k, v) => MapEntry(k.toString(), v))));
      }
      if (value is List) {
        return MapEntry(key, value.map((item) {
          if (item is Map) return _cloneRuntimeMap(item.map((k, v) => MapEntry(k.toString(), v)));
          if (item is List) return List<dynamic>.from(item);
          return item;
        }).toList());
      }
      return MapEntry(key, value);
    });
  }

  static Map<String, dynamic> _deepMergeRuntimeMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay,
  ) {
    final next = _cloneRuntimeMap(base);
    for (final entry in overlay.entries) {
      final overlayValue = entry.value;
      final baseValue = next[entry.key];
      if (overlayValue is Map && baseValue is Map) {
        next[entry.key] = _deepMergeRuntimeMaps(
          baseValue.map((key, value) => MapEntry(key.toString(), value)),
          overlayValue.map((key, value) => MapEntry(key.toString(), value)),
        );
      } else {
        next[entry.key] = overlayValue;
      }
    }
    return next;
  }

  static int _runtimeVersionOf(Map<String, dynamic> data) {
    final value = data['version'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
