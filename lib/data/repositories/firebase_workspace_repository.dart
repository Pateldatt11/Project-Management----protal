import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/config/app_config.dart';
import '../../core/crash/apk_crash_forensics.dart';
import '../../core/utils/json_value.dart';
import '../cache/mobile_ui_config_cache.dart';
import '../firebase/firebase_paths.dart';
import '../firebase/firestore_service.dart';
import '../models/activity_log.dart';
import '../models/app_notification.dart';
import '../models/audit_log.dart';
import '../models/file_attachment.dart';
import '../models/member.dart';
import '../models/mobile_ui_config.dart';
import '../models/mobile_ui_design.dart';
import '../models/project.dart';
import '../models/report.dart';
import '../models/task.dart';
import '../models/task_comment.dart';
import '../models/team.dart';
import 'workspace_repository.dart';

class FirebaseWorkspaceRepository implements WorkspaceRepository {
  FirebaseWorkspaceRepository({
    FirestoreService? firestore,
    MobileUiConfigCache? mobileUiConfigCache,
    this.defaultCompanyId = AppConfig.fallbackCompanyId,
  })  : _firestore = firestore ?? FirestoreService(),
        _mobileUiConfigCache = mobileUiConfigCache ?? const MobileUiConfigCache();

  final FirestoreService _firestore;
  final MobileUiConfigCache _mobileUiConfigCache;
  final String defaultCompanyId;

  /// Platform-global APK SDUI stability policy: never keep a live Firestore listener attached
  /// to the renderer. The employee APK checks for a newer server UI at most
  /// twice per hour, stages it in SQLite, and applies it only on the next cold
  /// start. This prevents mid-session shell/body rebuilds while the user works.
  static const Duration _mobileUiServerCheckInterval = Duration(minutes: 30);
  static bool get _isTestMobileUiRuntime => _activeMobileUiCoreDocId == 'mobileEmployeeNext';

  /// APK/runtime SDUI document selector.
  ///
  /// Release APK default:
  ///   core    = mobileEmployee
  ///   design  = mobileEmployeeDesign
  ///   screens = mobileEmployeeScreens
  ///
  /// Test APK:
  ///   flutter build apk --release --dart-define=SDUI_CONFIG_DOC=mobileEmployeeNext
  ///
  /// Then the APK reads and deep-merges:
  ///   mobileEmployeeNext + mobileEmployeeNextDesign + mobileEmployeeNextScreens
  static const String _configuredActiveMobileUiDocId = String.fromEnvironment(
    'SDUI_CONFIG_DOC',
    defaultValue: 'mobileEmployee',
  );

  static String get _activeMobileUiCoreDocId {
    final trimmed = _configuredActiveMobileUiDocId.trim();
    if (trimmed.isEmpty || trimmed.contains('/') || trimmed.contains('..')) {
      return 'mobileEmployee';
    }
    return trimmed;
  }

  static String get _activeMobileUiDesignDocId {
    return _activeMobileUiCoreDocId == 'mobileEmployeeNext'
        ? 'mobileEmployeeNextDesign'
        : 'mobileEmployeeDesign';
  }

  static String get _activeMobileUiScreensDocId {
    return _activeMobileUiCoreDocId == 'mobileEmployeeNext'
        ? 'mobileEmployeeNextScreens'
        : 'mobileEmployeeScreens';
  }

  static String _mobileUiCacheKey(String companyId) => 'platformUiConfigs::$_activeMobileUiCoreDocId';

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

  static Map<String, dynamic> _extractSduiConfig(Map<String, dynamic>? rawData) {
    if (rawData == null || rawData.isEmpty) return const <String, dynamic>{};
    final wrappedConfig = rawData['config'];
    if (wrappedConfig is Map) {
      return wrappedConfig.map((key, value) => MapEntry(key.toString(), value));
    }
    return rawData.map((key, value) => MapEntry(key.toString(), value));
  }

  static int _runtimeVersionOf(Map<String, dynamic> data) {
    final value = data['version'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<Map<String, dynamic>> _readUiConfigDoc(String companyId, String docId) async {
    final snapshot = await FirebaseFirestore.instance
        .doc(FirebasePaths.mobileEmployeeUiConfigDoc(companyId, docId))
        .get(const GetOptions(source: Source.serverAndCache))
        .timeout(const Duration(seconds: 10));
    return _extractSduiConfig(snapshot.data());
  }

  Future<Map<String, dynamic>> _loadMergedMobileUiRuntimeConfig(String companyId) async {
    var core = await _readUiConfigDoc(companyId, _activeMobileUiCoreDocId);
    if (core.isEmpty && _activeMobileUiCoreDocId != 'mobileEmployee') {
      final releaseCore = await _readUiConfigDoc(companyId, 'mobileEmployee');
      if (releaseCore.isNotEmpty) core = releaseCore;
    }

    final design = await _readUiConfigDoc(companyId, _activeMobileUiDesignDocId);
    final screens = await _readUiConfigDoc(companyId, _activeMobileUiScreensDocId);

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
      'targetDocId': _activeMobileUiCoreDocId,
      'sourceCoreDocId': _activeMobileUiCoreDocId,
      'sourceDesignDocId': _activeMobileUiDesignDocId,
      'sourceScreensDocId': _activeMobileUiScreensDocId,
      'apkSplitDocMergeEnabled': true,
      'apkSplitDocMergeOrder': <String>['core', 'design', 'screens'],
    };
  }

  late String activeCompanyId = defaultCompanyId;

  String get _writeCompanyId => activeCompanyId.trim().isEmpty ? defaultCompanyId : activeCompanyId;

  List<T> _parseSnapshot<T>(QuerySnapshot<Map<String, dynamic>> snapshot, T Function(Map<String, dynamic>) builder) {
    final items = <T>[];
    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        items.add(builder({
          ...data,
          'id': doc.id,
          'taskId': data['taskId'] ?? doc.id,
          'projectId': data['projectId'] ?? doc.id,
          'attachmentId': data['attachmentId'] ?? doc.id,
        }));
      } catch (_) {
        // Never blank the app because one old Firestore document has a legacy shape
      }
    }
    return items;
  }

  Stream<List<T>> _safeCollectionStream<T>({
    required String path,
    required T Function(Map<String, dynamic>) builder,
    int Function(T a, T b)? sort,
  }) {
    return FirebaseFirestore.instance.collection(path).snapshots().map((snapshot) {
      final items = _parseSnapshot<T>(snapshot, builder);
      if (sort != null) items.sort(sort);
      return items;
    });
  }

  Stream<List<T>> _safeCompanyAndLegacyRootStream<T>({
    required String companyPath,
    required String legacyRootCollection,
    required String companyId,
    required T Function(Map<String, dynamic>) builder,
    required String Function(T item) idOf,
    int Function(T a, T b)? sort,
  }) {
    final controller = StreamController<List<T>>();
    var scoped = <T>[];
    var legacy = <T>[];

    void emit() {
      final byId = <String, T>{};
      for (final item in legacy) {
        final id = idOf(item);
        if (id.trim().isNotEmpty) byId[id] = item;
      }
      for (final item in scoped) {
        final id = idOf(item);
        if (id.trim().isNotEmpty) byId[id] = item;
      }
      final merged = byId.values.toList();
      if (sort != null) merged.sort(sort);
      if (!controller.isClosed) controller.add(merged);
    }

    final subs = <StreamSubscription<dynamic>>[];
    subs.add(FirebaseFirestore.instance.collection(companyPath).snapshots().listen((snapshot) {
      scoped = _parseSnapshot<T>(snapshot, builder);
      emit();
    }, onError: (_) {
      scoped = <T>[];
      emit();
    }));

    subs.add(FirebaseFirestore.instance.collection(legacyRootCollection).where('companyId', isEqualTo: companyId).snapshots().listen((snapshot) {
      legacy = _parseSnapshot<T>(snapshot, builder);
      emit();
    }, onError: (_) {
      legacy = <T>[];
      emit();
    }));

    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
    };

    return controller.stream;
  }

  List<List<String>> _chunks(List<String> values, {int size = 10}) {
    final cleaned = values.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet().toList();
    final chunks = <List<String>>[];
    for (var i = 0; i < cleaned.length; i += size) {
      chunks.add(cleaned.sublist(i, (i + size) > cleaned.length ? cleaned.length : i + size));
    }
    return chunks;
  }

  Stream<List<T>> _mergeScopedQueryStreams<T>({
    required List<Stream<QuerySnapshot<Map<String, dynamic>>>> streams,
    required T Function(Map<String, dynamic>) builder,
    required String Function(T item) idOf,
    int Function(T a, T b)? sort,
  }) {
    if (streams.isEmpty) return Stream<List<T>>.value(<T>[]);
    final controller = StreamController<List<T>>();
    final buckets = List<List<T>>.generate(streams.length, (_) => <T>[]);

    void emit() {
      final byId = <String, T>{};
      for (final bucket in buckets) {
        for (final item in bucket) {
          final id = idOf(item);
          if (id.trim().isNotEmpty) byId[id] = item;
        }
      }
      final merged = byId.values.toList();
      if (sort != null) merged.sort(sort);
      if (!controller.isClosed) controller.add(merged);
    }

    final subs = <StreamSubscription<dynamic>>[];
    for (var i = 0; i < streams.length; i++) {
      final index = i;
      subs.add(streams[index].listen((snapshot) {
        buckets[index] = _parseSnapshot<T>(snapshot, builder);
        emit();
      }, onError: (_) {
        buckets[index] = <T>[];
        emit();
      }));
    }

    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
    };
    return controller.stream;
  }

  DateTime _projectSortDate(Project project) => project.updatedAt ?? project.createdAt ?? project.dueDate;

  @override
  Stream<List<Project>> watchProjects(
    String companyId, {
    String? currentUid,
    bool canViewFullProgress = false,
    List<String> projectIds = const [],
    List<String> teamIds = const [],
  }) {
    if (canViewFullProgress || currentUid == null || currentUid.trim().isEmpty) {
      return _safeCompanyAndLegacyRootStream<Project>(
        companyPath: FirebasePaths.projects(companyId),
        legacyRootCollection: 'projects',
        companyId: companyId,
        builder: Project.fromJson,
        idOf: (project) => project.projectId,
        sort: (a, b) => _projectSortDate(b).compareTo(_projectSortDate(a)),
      );
    }

    final collection = FirebaseFirestore.instance.collection(FirebasePaths.projects(companyId));
    final streams = <Stream<QuerySnapshot<Map<String, dynamic>>>>[
      collection.where('managerIds', arrayContains: currentUid).snapshots(),
      collection.where('memberIds', arrayContains: currentUid).snapshots(),
    ];
    for (final chunk in _chunks(projectIds)) {
      streams.add(collection.where(FieldPath.documentId, whereIn: chunk).snapshots());
      streams.add(collection.where('projectId', whereIn: chunk).snapshots());
    }
    for (final chunk in _chunks(teamIds)) {
      streams.add(collection.where('teamIds', arrayContainsAny: chunk).snapshots());
    }
    return _mergeScopedQueryStreams<Project>(
      streams: streams,
      builder: Project.fromJson,
      idOf: (project) => project.projectId,
      sort: (a, b) => _projectSortDate(b).compareTo(_projectSortDate(a)),
    );
  }

  @override
  Stream<List<ProjectTask>> watchTasks(
    String companyId, {
    String? currentUid,
    bool canViewFullProgress = false,
    List<String> projectIds = const [],
    List<String> teamIds = const [],
  }) {
    int sortTasks(ProjectTask a, ProjectTask b) {
      final rankCompare = a.kanbanRank.compareTo(b.kanbanRank);
      if (rankCompare != 0) return rankCompare;
      return a.dueDate.compareTo(b.dueDate);
    }

    if (canViewFullProgress || currentUid == null || currentUid.trim().isEmpty) {
      return _safeCompanyAndLegacyRootStream<ProjectTask>(
        companyPath: FirebasePaths.tasks(companyId),
        legacyRootCollection: 'tasks',
        companyId: companyId,
        builder: ProjectTask.fromJson,
        idOf: (task) => task.taskId,
        sort: sortTasks,
      );
    }

    final collection = FirebaseFirestore.instance.collection(FirebasePaths.tasks(companyId));
    final streams = <Stream<QuerySnapshot<Map<String, dynamic>>>>[
      collection.where('assignedToIds', arrayContains: currentUid).snapshots(),
    ];
    for (final chunk in _chunks(projectIds)) {
      streams.add(collection.where('projectId', whereIn: chunk).snapshots());
    }
    for (final chunk in _chunks(teamIds)) {
      streams.add(collection.where('teamId', whereIn: chunk).snapshots());
    }
    return _mergeScopedQueryStreams<ProjectTask>(
      streams: streams,
      builder: ProjectTask.fromJson,
      idOf: (task) => task.taskId,
      sort: sortTasks,
    );
  }

  @override
  Stream<List<Member>> watchMembers(
    String companyId, {
    String? currentUid,
    bool canViewFullProgress = false,
    List<String> projectIds = const [],
    List<String> teamIds = const [],
  }) {
    if (canViewFullProgress || currentUid == null || currentUid.trim().isEmpty) {
      return _safeCompanyAndLegacyRootStream<Member>(
        companyPath: FirebasePaths.members(companyId),
        legacyRootCollection: 'members',
        companyId: companyId,
        builder: Member.fromJson,
        idOf: (member) => member.uid,
      );
    }

    final collection = FirebaseFirestore.instance.collection(FirebasePaths.members(companyId));
    final streams = <Stream<QuerySnapshot<Map<String, dynamic>>>>[
      collection.where(FieldPath.documentId, isEqualTo: currentUid).snapshots(),
    ];
    for (final chunk in _chunks(projectIds)) {
      streams.add(collection.where('projectIds', arrayContainsAny: chunk).snapshots());
    }
    for (final chunk in _chunks(teamIds)) {
      streams.add(collection.where('teamIds', arrayContainsAny: chunk).snapshots());
    }
    return _mergeScopedQueryStreams<Member>(
      streams: streams,
      builder: Member.fromJson,
      idOf: (member) => member.uid,
      sort: (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
  }

  @override
  Stream<List<Team>> watchTeams(
    String companyId, {
    String? currentUid,
    bool canViewFullProgress = false,
    List<String> projectIds = const [],
    List<String> teamIds = const [],
  }) {
    if (canViewFullProgress || currentUid == null || currentUid.trim().isEmpty) {
      return _safeCompanyAndLegacyRootStream<Team>(
        companyPath: FirebasePaths.teams(companyId),
        legacyRootCollection: 'teams',
        companyId: companyId,
        builder: Team.fromJson,
        idOf: (team) => team.teamId,
      );
    }

    final collection = FirebaseFirestore.instance.collection(FirebasePaths.teams(companyId));
    final streams = <Stream<QuerySnapshot<Map<String, dynamic>>>>[
      collection.where('memberIds', arrayContains: currentUid).snapshots(),
    ];
    for (final chunk in _chunks(teamIds)) {
      streams.add(collection.where(FieldPath.documentId, whereIn: chunk).snapshots());
    }
    for (final chunk in _chunks(projectIds)) {
      streams.add(collection.where('activeProjectIds', arrayContainsAny: chunk).snapshots());
    }
    return _mergeScopedQueryStreams<Team>(
      streams: streams,
      builder: Team.fromJson,
      idOf: (team) => team.teamId,
      sort: (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }

  @override
  Stream<List<AppNotification>> watchMyNotifications(String companyId, String uid) {
    final controller = StreamController<List<AppNotification>>();
    var byRecipient = const <AppNotification>[];
    var byRecipientArray = const <AppNotification>[];
    var byAdminGroup = const <AppNotification>[];
    var memberItems = const <AppNotification>[];

    List<AppNotification> parseSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) =>
        _parseSnapshot<AppNotification>(snapshot, AppNotification.fromJson);

    void emit() {
      final byId = <String, AppNotification>{};
      for (final item in <AppNotification>[...memberItems, ...byRecipient, ...byRecipientArray, ...byAdminGroup]) {
        final visible = item.recipientId == uid || item.recipientIds.contains(uid) || item.recipientRoleGroup == 'admins';
        if (!visible) continue;
        final existing = byId[item.notificationId];
        if (existing == null || item.createdAt.isAfter(existing.createdAt) || (item.isRead && !existing.isRead)) {
          byId[item.notificationId] = item;
        }
      }
      final merged = byId.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!controller.isClosed) controller.add(merged);
    }

    final subs = <StreamSubscription<dynamic>>[];
    final rootCollection = FirebaseFirestore.instance.collection(FirebasePaths.notifications(companyId));

    subs.add(rootCollection.where('recipientId', isEqualTo: uid).snapshots().listen((snapshot) {
      byRecipient = parseSnapshot(snapshot);
      emit();
    }, onError: (_) {
      byRecipient = const <AppNotification>[];
      emit();
    }));

    subs.add(rootCollection.where('recipientIds', arrayContains: uid).snapshots().listen((snapshot) {
      byRecipientArray = parseSnapshot(snapshot);
      emit();
    }, onError: (_) {
      byRecipientArray = const <AppNotification>[];
      emit();
    }));

    subs.add(rootCollection.where('recipientRoleGroup', isEqualTo: 'admins').snapshots().listen((snapshot) {
      byAdminGroup = parseSnapshot(snapshot);
      emit();
    }, onError: (_) {
      byAdminGroup = const <AppNotification>[];
      emit();
    }));

    subs.add(FirebaseFirestore.instance.collection(FirebasePaths.memberNotifications(companyId, uid)).snapshots().listen((snapshot) {
      memberItems = parseSnapshot(snapshot);
      emit();
    }, onError: (_) {
      memberItems = const <AppNotification>[];
      emit();
    }));

    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
    };

    return controller.stream;
  }

  @override
  Stream<List<ActivityLog>> watchActivity(String companyId) => _firestore.collectionStream(
        path: FirebasePaths.activityLogs(companyId),
        builder: ActivityLog.fromJson,
        queryBuilder: (q) => q.orderBy('createdAt', descending: true).limit(100),
      );

  @override
  Stream<List<AuditLog>> watchAuditLogs(String companyId) => _firestore.collectionStream(
        path: FirebasePaths.auditLogs(companyId),
        builder: AuditLog.fromJson,
        queryBuilder: (q) => q.orderBy('createdAt', descending: true).limit(200),
      );

  @override
  Stream<List<ReportModel>> watchReports(String companyId) => _firestore.collectionStream(
        path: FirebasePaths.reports(companyId),
        builder: ReportModel.fromJson,
        queryBuilder: (q) => q.orderBy('createdAt', descending: true),
      );

  @override
  Stream<List<TaskComment>> watchComments(String companyId) => FirebaseFirestore.instance
      .collectionGroup('comments')
      .where('companyId', isEqualTo: companyId)
      .snapshots()
      .map((snapshot) {
        final items = <TaskComment>[];
        for (final doc in snapshot.docs) {
          try {
            items.add(TaskComment.fromJson({...doc.data(), 'commentId': doc.data()['commentId'] ?? doc.id}));
          } catch (_) {}
        }
        return items;
      });

  @override
  Stream<List<FileAttachment>> watchAttachments(String companyId) => FirebaseFirestore.instance
      .collectionGroup('attachments')
      .where('companyId', isEqualTo: companyId)
      .snapshots()
      .map((snapshot) {
        final items = <FileAttachment>[];
        for (final doc in snapshot.docs) {
          try {
            items.add(FileAttachment.fromJson({...doc.data(), 'attachmentId': doc.data()['attachmentId'] ?? doc.id}));
          } catch (_) {}
        }
        return items;
      });

  @override
  Stream<MobileUiConfig> watchMobileUiConfig(String companyId) async* {
    final cacheKey = _mobileUiCacheKey(companyId);
    final promoted = await _mobileUiConfigCache.promotePendingForNextLaunch(cacheKey);
    ApkCrashForensics.log('sdui_cache_promote_on_start', data: <String, Object?>{
      'companyId': companyId,
      'cacheKey': cacheKey,
      'coreDocId': _activeMobileUiCoreDocId,
      'designDocId': _activeMobileUiDesignDocId,
      'screensDocId': _activeMobileUiScreensDocId,
      'promoted': promoted,
      'policy': 'split_doc_cache_first_30m_poll_next_launch_apply',
    });

    var cached = await _mobileUiConfigCache.read(cacheKey);
    var activeSignature = cached?.cacheSignature;
    String? lastStagedSignature;

    if (cached != null) {
      ApkCrashForensics.log('sdui_render_source', data: <String, Object?>{
        'source': 'sqlite_active_split_doc_merged',
        'version': cached.version,
        'cacheKey': cacheKey,
        'pollIntervalMinutes': _mobileUiServerCheckInterval.inMinutes,
      });
      yield cached;
    }

    var checkCount = 0;
    while (true) {
      checkCount += 1;
      try {
        ApkCrashForensics.log('sdui_poll_check_start', data: <String, Object?>{
          'companyId': companyId,
          'cacheKey': cacheKey,
          'checkCount': checkCount,
          'coreDocId': _activeMobileUiCoreDocId,
          'designDocId': _activeMobileUiDesignDocId,
          'screensDocId': _activeMobileUiScreensDocId,
          'intervalMinutes': _mobileUiServerCheckInterval.inMinutes,
        });

        final mergedData = await _loadMergedMobileUiRuntimeConfig(companyId);
        if (mergedData.isNotEmpty) {
          final config = MobileUiConfig.fromMap(mergedData);
          final signature = config.cacheSignature;

          if (activeSignature == null) {
            activeSignature = signature;
            cached = config;
            await _mobileUiConfigCache.write(companyId: cacheKey, config: config);
            ApkCrashForensics.log('sdui_first_bootstrap_from_firestore', data: <String, Object?>{
              'version': config.version,
              'source': 'split_doc_merge_poll',
              'cacheKey': cacheKey,
            });
            yield config;
          } else if (signature == activeSignature || signature == lastStagedSignature) {
            ApkCrashForensics.log('sdui_poll_no_change', data: <String, Object?>{
              'version': config.version,
              'alreadyStaged': signature == lastStagedSignature,
              'cacheKey': cacheKey,
            });
          } else if (_isTestMobileUiRuntime) {
            activeSignature = signature;
            cached = config;
            await _mobileUiConfigCache.write(companyId: cacheKey, config: config);
            ApkCrashForensics.log('sdui_test_runtime_update_applied_immediately', data: <String, Object?>{
              'version': config.version,
              'source': 'split_doc_test_immediate',
              'cacheKey': cacheKey,
            });
            yield config;
          } else {
            lastStagedSignature = signature;
            await _mobileUiConfigCache.writePending(companyId: cacheKey, config: config);
            ApkCrashForensics.log('sdui_update_staged_next_launch', data: <String, Object?>{
              'version': config.version,
              'source': 'split_doc_30m_poll',
              'cacheKey': cacheKey,
            });
          }
        }
        ApkCrashForensics.log('sdui_poll_check_done', data: <String, Object?>{
          'checkCount': checkCount,
          'cacheKey': cacheKey,
        });
      } catch (error, stack) {
        ApkCrashForensics.recordError(error, stack, fatal: false, source: 'watchMobileUiConfig.splitDocPoll');
      }

      ApkCrashForensics.log('sdui_poll_wait', data: <String, Object?>{
        'minutes': _mobileUiServerCheckInterval.inMinutes,
        'cacheKey': cacheKey,
      });
      await Future<void>.delayed(_mobileUiServerCheckInterval);
    }
  }

  @override
  Stream<MobileUiDesign> watchMobileUiDesign(String companyId) async* {
    final cacheKey = _mobileUiCacheKey(companyId);
    await _mobileUiConfigCache.promotePendingForNextLaunch(cacheKey);
    var cached = await _mobileUiConfigCache.readDesign(cacheKey);
    var activeSignature = cached?.cacheSignature;
    String? lastStagedSignature;

    if (cached != null) {
      ApkCrashForensics.log('sdui_design_render_source', data: <String, Object?>{
        'source': 'sqlite_active_split_doc_merged',
        'version': cached.version,
        'cacheKey': cacheKey,
        'pollIntervalMinutes': _mobileUiServerCheckInterval.inMinutes,
      });
      yield cached;
    }

    var checkCount = 0;
    while (true) {
      checkCount += 1;
      try {
        ApkCrashForensics.log('sdui_design_poll_check_start', data: <String, Object?>{
          'companyId': companyId,
          'cacheKey': cacheKey,
          'checkCount': checkCount,
          'coreDocId': _activeMobileUiCoreDocId,
          'designDocId': _activeMobileUiDesignDocId,
          'screensDocId': _activeMobileUiScreensDocId,
          'intervalMinutes': _mobileUiServerCheckInterval.inMinutes,
        });

        final mergedData = await _loadMergedMobileUiRuntimeConfig(companyId);
        if (mergedData.isNotEmpty) {
          final design = MobileUiDesign.fromMap(mergedData);
          final signature = design.cacheSignature;

          if (activeSignature == null) {
            activeSignature = signature;
            cached = design;
            await _mobileUiConfigCache.writeDesign(companyId: cacheKey, design: design);
            ApkCrashForensics.log('sdui_design_first_bootstrap_from_firestore', data: <String, Object?>{
              'version': design.version,
              'source': 'split_doc_merge_poll',
              'cacheKey': cacheKey,
            });
            yield design;
          } else if (signature == activeSignature || signature == lastStagedSignature) {
            ApkCrashForensics.log('sdui_design_poll_no_change', data: <String, Object?>{
              'version': design.version,
              'alreadyStaged': signature == lastStagedSignature,
              'cacheKey': cacheKey,
            });
          } else if (_isTestMobileUiRuntime) {
            activeSignature = signature;
            cached = design;
            await _mobileUiConfigCache.writeDesign(companyId: cacheKey, design: design);
            ApkCrashForensics.log('sdui_design_test_runtime_update_applied_immediately', data: <String, Object?>{
              'version': design.version,
              'source': 'split_doc_test_immediate',
              'cacheKey': cacheKey,
            });
            yield design;
          } else {
            lastStagedSignature = signature;
            await _mobileUiConfigCache.writePendingDesign(companyId: cacheKey, design: design);
            ApkCrashForensics.log('sdui_design_update_staged_next_launch', data: <String, Object?>{
              'version': design.version,
              'source': 'split_doc_30m_poll',
              'cacheKey': cacheKey,
            });
          }
        }
        ApkCrashForensics.log('sdui_design_poll_check_done', data: <String, Object?>{
          'checkCount': checkCount,
          'cacheKey': cacheKey,
        });
      } catch (error, stack) {
        ApkCrashForensics.recordError(error, stack, fatal: false, source: 'watchMobileUiDesign.splitDocPoll');
      }

      ApkCrashForensics.log('sdui_design_poll_wait', data: <String, Object?>{
        'minutes': _mobileUiServerCheckInterval.inMinutes,
        'cacheKey': cacheKey,
      });
      await Future<void>.delayed(_mobileUiServerCheckInterval);
    }
  }

  @override
  Future<void> saveProject(Project project) {
    final companyId = project.companyId.trim().isNotEmpty ? project.companyId.trim() : _writeCompanyId;
    return _firestore.setData(
      path: '${FirebasePaths.projects(companyId)}/${project.projectId}',
      data: project.toJson(),
    );
  }

  @override
  Future<void> saveTask(ProjectTask task) {
    final companyId = task.companyId.trim().isNotEmpty ? task.companyId.trim() : _writeCompanyId;
    return _firestore.setData(
      path: '${FirebasePaths.tasks(companyId)}/${task.taskId}',
      data: task.toJson(),
    );
  }

  @override
  Future<void> saveTeam(Team team) => _firestore.setData(
        path: '${FirebasePaths.teams(_writeCompanyId)}/${team.teamId}',
        data: team.toJson(),
      );

  @override
  Future<void> saveMember(Member member) => _firestore.setData(
        path: '${FirebasePaths.members(_writeCompanyId)}/${member.uid}',
        data: member.toJson(),
      );

  @override
  Future<void> saveNotification(AppNotification notification) async {
    final companyId = (notification.companyId ?? _writeCompanyId).trim();
    final recipientId = notification.recipientId.trim();
    final notificationId = notification.notificationId.trim();
    if (companyId.isEmpty || recipientId.isEmpty || notificationId.isEmpty) return;

    final normalizedType = notification.type.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    final isTaskAssigned = normalizedType == 'taskassigned';
    final isMeetingInvite = normalizedType == 'meetinginvite' ||
        normalizedType == 'callinvite' ||
        (notification.actionUrl ?? '').trim().isNotEmpty;
    final recipientIds = notification.recipientIds.isNotEmpty
        ? notification.recipientIds.where((uid) => uid.trim().isNotEmpty).toSet().toList()
        : <String>[recipientId];

    final requiresAccept = isTaskAssigned || isMeetingInvite;
    final data = Map<String, dynamic>.from(notification.toJson())
      ..addAll(<String, dynamic>{
        'notificationId': notificationId,
        'companyId': companyId,
        'recipientId': recipientId,
        'recipientIds': recipientIds,
        'body': notification.message,
        'message': notification.message,
        'read': notification.isRead,
        'accepted': notification.isRead,
        'targetUid': recipientId,
        'requiresAccept': requiresAccept,
        'loopUntilAccept': requiresAccept,
        'acceptButtonEnabled': requiresAccept,
        'assistantVoice': requiresAccept,
        'assistantText': isTaskAssigned
            ? 'You are assigned a new task. Please accept the notification.'
            : (isMeetingInvite
                ? 'You have a meeting invite. Please accept and join, or reject the notification.'
                : 'You have a new work notification.'),
        'soundName': 'user_preference',
        'androidSoundName': 'task_alert_airport_ding',
        'deliveryProvider': 'oracle_admin_sdk',
        'deliveryStatus': notification.isRead ? 'responded' : 'queued',
        'responseStatus': notification.isRead ? 'accepted' : (requiresAccept ? 'pending' : 'not_required'),
        'adminAttentionRequired': false,
        'source': 'admin_workspace_repository_oracle_backend_queue',
        'deliveryPipeline': 'firestore_queue_to_oracle_admin_sdk_to_fcm_all_states',
        'pushPrimaryTrigger': 'oracle_worker_company_root',
        'updatedAt': DateTime.now().toIso8601String(),
      });

    if (isMeetingInvite) {
      final actionUrl = (notification.actionUrl ?? '').trim();
      data['meetingUrl'] = actionUrl;
      data['joinUrl'] = actionUrl;
      data['actionLabel'] = (notification.actionLabel ?? '').trim().isNotEmpty ? notification.actionLabel : 'Accept & Join';
      data['rejectLabel'] = (notification.rejectLabel ?? '').trim().isNotEmpty ? notification.rejectLabel : 'Reject';
      data['actionType'] = (notification.actionType ?? '').trim().isNotEmpty ? notification.actionType : 'meetingInvite';
    }

    final rootRef = FirebaseFirestore.instance.doc('${FirebasePaths.notifications(companyId)}/$notificationId');
    final memberRef = FirebaseFirestore.instance.doc('${FirebasePaths.memberNotifications(companyId, recipientId)}/$notificationId');
    final rootData = <String, dynamic>{
      ...data,
      'queueScope': 'company_root',
      'activeQueue': !notification.isRead,
      'pushStatus': notification.isRead ? 'accepted_from_client' : 'queued_oracle_backend',
    };
    if (notification.isRead) {
      rootData['nextAttemptAt'] = FieldValue.delete();
    } else {
      rootData.addAll(<String, dynamic>{
        'nextAttemptAt': Timestamp.now(),
        'attemptCount': 0,
        'maxAttempts': 3,
        'retryIntervalMinutes': 5,
      });
    }
    final memberData = <String, dynamic>{
      ...data,
      'queueScope': 'member_mirror',
      'activeQueue': false,
      'pushStatus': notification.isRead ? 'accepted_from_client' : 'queued_oracle_backend',
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.set(rootRef, rootData, SetOptions(merge: true));
    batch.set(memberRef, memberData, SetOptions(merge: true));
    await batch.commit();
  }

  @override
  Future<void> saveActivity(ActivityLog log) => _firestore.setData(
        path: '${FirebasePaths.activityLogs(_writeCompanyId)}/${log.activityLogId}',
        data: log.toJson(),
      );

  @override
  Future<void> saveAuditLog(AuditLog log) => _firestore.setData(
        path: '${FirebasePaths.auditLogs(_writeCompanyId)}/${log.auditLogId}',
        data: log.toJson(),
      );

  @override
  Future<void> saveReport(ReportModel report) => _firestore.setData(
        path: '${FirebasePaths.reports(_writeCompanyId)}/${report.reportId}',
        data: report.toJson(),
      );

  int _readUiVersion(Map<String, dynamic>? data, int fallback) => JsonValue.integer(data == null ? null : data['version'], fallback: fallback);

  Future<MobileUiDesign> publishMobileUiDesign(String companyId, MobileUiDesign design, {String? updatedBy}) async {
    final configRef = FirebaseFirestore.instance.doc(FirebasePaths.mobileEmployeeUiConfig(companyId));
    final designRef = FirebaseFirestore.instance.doc(FirebasePaths.mobileEmployeeUiDesign(companyId));
    final now = DateTime.now();
    final editorUid = updatedBy ?? design.updatedBy;

    final publishedDesign = await FirebaseFirestore.instance.runTransaction<MobileUiDesign>((transaction) async {
      final configSnapshot = await transaction.get(configRef);
      final designSnapshot = await transaction.get(designRef);
      final configVersion = _readUiVersion(configSnapshot.data(), design.version);
      final designVersion = _readUiVersion(designSnapshot.data(), design.version);
      final currentVersion = configVersion > designVersion ? configVersion : designVersion;
      final nextVersion = (currentVersion > design.version ? currentVersion : design.version) + 1;
      final nextDesign = design.copyWith(version: nextVersion, updatedAt: now, updatedBy: editorUid);
      final existingConfig = MobileUiConfig.fromMap(configSnapshot.data());
      final nextConfig = nextDesign
          .toMobileConfig(versionOverride: nextVersion)
          .preserveRuntimeSafeFieldsFrom(existingConfig)
          .copyWith(updatedAt: now, updatedBy: editorUid);

      transaction.set(designRef, nextDesign.toMap(updatedBy: editorUid), SetOptions(merge: true));
      transaction.set(configRef, nextConfig.toMap(updatedBy: editorUid), SetOptions(merge: true));
      return nextDesign;
    });

    final publishedConfigSnapshot = await configRef.get();
    final publishedConfig = MobileUiConfig.fromMap(publishedConfigSnapshot.data());
    await _mobileUiConfigCache.writeDesign(companyId: _mobileUiCacheKey(companyId), design: publishedDesign);
    await _mobileUiConfigCache.write(companyId: _mobileUiCacheKey(companyId), config: publishedConfig);
    return publishedDesign;
  }

  @override
  Future<void> saveMobileUiConfig(String companyId, MobileUiConfig config, {String? updatedBy}) async {
    final configRef = FirebaseFirestore.instance.doc(FirebasePaths.mobileEmployeeUiConfig(companyId));
    final editorUid = updatedBy ?? config.updatedBy;
    final savedConfig = await FirebaseFirestore.instance.runTransaction<MobileUiConfig>((transaction) async {
      final snapshot = await transaction.get(configRef);
      final existingConfig = MobileUiConfig.fromMap(snapshot.data());
      final safeVersion = config.version <= existingConfig.version ? existingConfig.version + 1 : config.version;
      final nextConfig = config
          .copyWith(version: safeVersion, updatedBy: editorUid, updatedAt: DateTime.now())
          .preserveRuntimeSafeFieldsFrom(existingConfig);
      transaction.set(configRef, nextConfig.toMap(updatedBy: editorUid), SetOptions(merge: true));
      return nextConfig;
    });
    await _mobileUiConfigCache.write(companyId: _mobileUiCacheKey(companyId), config: savedConfig);
  }

  @override
  Future<void> saveMobileUiDesign(String companyId, MobileUiDesign design, {String? updatedBy}) async {
    final nextDesign = design.copyWith(updatedBy: updatedBy ?? design.updatedBy, updatedAt: DateTime.now());
    await _mobileUiConfigCache.writeDesign(companyId: _mobileUiCacheKey(companyId), design: nextDesign);
    await _firestore.setData(
      path: FirebasePaths.mobileEmployeeUiDesign(companyId),
      data: nextDesign.toMap(updatedBy: updatedBy),
    );
  }

  @override
  Future<void> saveComment(String companyId, TaskComment comment) => _firestore.setData(
        path: '${FirebasePaths.taskComments(companyId, comment.taskId)}/${comment.commentId}',
        data: {...comment.toJson(), 'companyId': companyId},
      );

  @override
  Future<void> saveAttachment(String companyId, FileAttachment attachment) => _firestore.setData(
        path: '${FirebasePaths.taskAttachments(companyId, attachment.taskId)}/${attachment.attachmentId}',
        data: {...attachment.toJson(), 'companyId': companyId},
      );

  @override
  Future<void> deleteTask(String companyId, String taskId) => _firestore.deleteData(path: '${FirebasePaths.tasks(companyId)}/$taskId');
}