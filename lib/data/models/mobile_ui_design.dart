import 'dart:convert';

import '../../core/utils/json_value.dart';
import 'mobile_ui_config.dart';

class MobileUiDesign {
  const MobileUiDesign({
    required this.version,
    required this.enabled,
    required this.templateName,
    required this.theme,
    required this.bottomNav,
    required this.topNav,
    required this.sections,
    required this.taskCard,
    required this.projectCard,
    required this.taskListConfig,
    required this.profileActions,
    this.designSystem = MobileUiConfig.defaultDesignSystem,
    this.animationConfig = MobileUiConfig.defaultAnimationConfig,
    this.layoutConfig = MobileUiConfig.defaultLayoutConfig,
    this.navigationConfig = MobileUiConfig.defaultNavigationConfig,
    this.floatingTopNav = MobileUiConfig.defaultFloatingTopNav,
    this.floatingBottomNav = MobileUiConfig.defaultFloatingBottomNav,
    this.quickActionDock = MobileUiConfig.defaultQuickActionDock,
    this.sideMenuConfig = MobileUiConfig.defaultSideMenuConfig,
    this.homeLayout = MobileUiConfig.defaultHomeLayout,
    this.homeCardConfig = MobileUiConfig.defaultHomeCardConfig,
    this.screenConfigs = MobileUiConfig.defaultScreenConfigs,
    this.screenRegistry = const <String, dynamic>{},
    this.navigationGraph = const <String, dynamic>{},
    this.profileCardConfig = MobileUiConfig.defaultProfileCardConfig,
    this.projectListConfig = MobileUiConfig.defaultProjectListConfig,
    this.dataBindings = MobileUiConfig.defaultDataBindings,
    this.rendererCompatibility = MobileUiConfig.defaultRendererCompatibility,
    this.inboxConfig = MobileUiConfig.defaultInboxConfig,
    this.profileFields = MobileUiConfig.defaultProfileFields,
    this.supportedWidgets = MobileUiConfig.defaultSupportedWidgets,
    this.notificationAlertConfig = MobileUiConfig.defaultNotificationAlertConfig,
    this.notificationSoundOptions = MobileUiConfig.defaultNotificationSoundOptions,
    this.texts = const <String, dynamic>{},
    this.screenOverrides = const <String, Map<String, dynamic>>{},
    this.updatedAt,
    this.updatedBy,
  });

  final int version;
  final bool enabled;
  final String templateName;
  final Map<String, dynamic> theme;
  final Map<String, dynamic> bottomNav;
  final Map<String, dynamic> topNav;
  final List<Map<String, dynamic>> sections;
  final Map<String, dynamic> taskCard;
  final Map<String, dynamic> projectCard;
  final Map<String, dynamic> taskListConfig;
  final Map<String, dynamic> profileActions;
  final Map<String, dynamic> designSystem;
  final Map<String, dynamic> animationConfig;
  final Map<String, dynamic> layoutConfig;
  final Map<String, dynamic> navigationConfig;
  final Map<String, dynamic> floatingTopNav;
  final Map<String, dynamic> floatingBottomNav;
  final Map<String, dynamic> quickActionDock;
  final Map<String, dynamic> sideMenuConfig;
  final Map<String, dynamic> homeLayout;
  final Map<String, dynamic> homeCardConfig;
  final Map<String, dynamic> screenConfigs;
  final Map<String, dynamic> screenRegistry;
  final Map<String, dynamic> navigationGraph;
  final Map<String, dynamic> profileCardConfig;
  final Map<String, dynamic> projectListConfig;
  final Map<String, dynamic> dataBindings;
  final Map<String, dynamic> rendererCompatibility;
  final Map<String, dynamic> inboxConfig;
  final List<String> profileFields;
  final List<String> supportedWidgets;
  final Map<String, dynamic> notificationAlertConfig;
  final Map<String, dynamic> notificationSoundOptions;
  final Map<String, dynamic> texts;
  final Map<String, Map<String, dynamic>> screenOverrides;
  final DateTime? updatedAt;
  final String? updatedBy;

  static const List<String> templateNames = <String>[
    'cleanWorkApp',
    'compactEmployeeApp',
    'modernCardUi',
    'progressFocusUi',
    'minimalFieldUi',
    'editorialNativeUi',
  ];

  static const Map<String, String> templateLabels = <String, String>{
    'cleanWorkApp': 'Clean Work App',
    'compactEmployeeApp': 'Compact Employee App',
    'modernCardUi': 'Modern Card UI',
    'progressFocusUi': 'Progress Focus UI',
    'minimalFieldUi': 'Minimal Field UI',
    'editorialNativeUi': 'Editorial Native UI',
  };

  static const List<String> sectionIds = <String>[
    'workSummary',
    'deadlineTimer',
    'myOpenTasks',
    'todayTasks',
    'projectProgress',
    'activeProjectsGrid',
    'projectMetrics',
    'onlineStatus',
  ];

  static const Map<String, String> sectionLabels = <String, String>{
    'workSummary': 'Work Summary',
    'deadlineTimer': 'Deadline Timer',
    'myOpenTasks': 'My Open Tasks',
    'todayTasks': 'Today Tasks',
    'projectProgress': 'Project Progress',
    'activeProjectsGrid': 'Active Projects',
    'projectMetrics': 'Project Metrics',
    'onlineStatus': 'Online Status',
  };

  static const Map<String, String> sectionTypes = <String, String>{
    'workSummary': 'heroCard',
    'deadlineTimer': 'deadlineCard',
    'myOpenTasks': 'taskList',
    'todayTasks': 'todayTaskList',
    'projectProgress': 'projectProgressCard',
    'activeProjectsGrid': 'activeProjectsGrid',
    'projectMetrics': 'grid',
    'onlineStatus': 'onlineStatusCard',
  };

  static const List<String> cardVariants = <String>[
    'modernCard',
    'minimalCard',
    'compactCard',
    'timelineCard',
    'progressCard',
    'advancedProgressCard',
    'nativeListRow',
    'editorialProgressCard',
    'editorialStatusCard',
    'editorialProjectRow',
    'darkEditorialHero',
    'smallMetricTile',
    'softProgressCard',
    'wireframeProjectFeedCard',
    'wireframeProfileSettings',
    'taskDetailHeader',
    'compactHeader',
  ];

  factory MobileUiDesign.defaults() {
    return MobileUiDesign.fromConfig(MobileUiConfig.defaults(), templateName: 'editorialNativeUi');
  }

  factory MobileUiDesign.fromConfig(MobileUiConfig config, {String templateName = 'editorialNativeUi'}) {
    final homeCards = config.homeCards.isEmpty ? MobileUiConfig.defaults().homeCards : config.homeCards;
    final sections = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'workSummary',
        'type': 'heroCard',
        'title': 'My Work',
        'subtitle': 'Today overview',
        'style': 'soft',
        'visible': true,
      },
      ...homeCards.map((id) => _sectionFromId(id)),
    ];
    return MobileUiDesign(
      version: config.version,
      enabled: config.enabled,
      templateName: templateName,
      theme: <String, dynamic>{
        'mode': 'light',
        'background': config.designSystem['surface'] ?? '#F8F5EF',
        'surface': config.designSystem['card'] ?? '#FFFFFF',
        'accent': config.designSystem['accent'] ?? '#111111',
        'textPrimary': config.designSystem['textPrimary'] ?? '#151515',
        'textSecondary': config.designSystem['textSecondary'] ?? '#76736D',
        'cardRadius': config.designSystem['radiusLarge'] ?? (config.compactMode ? 16 : 24),
        'cardPadding': config.compactMode ? 12 : 16,
        'density': config.compactMode ? 'compact' : 'comfortable',
      },
      bottomNav: <String, dynamic>{
        ...config.bottomNav,
        'tabs': config.bottomTabs,
        if (!config.bottomNav.containsKey('style')) 'style': 'floating',
      },
      topNav: <String, dynamic>{
        ...config.topNav,
        if (!config.topNav.containsKey('style')) 'style': 'glassAdvanced',
        if (!config.topNav.containsKey('density')) 'density': config.compactMode ? 'compact' : 'comfortable',
        if (!config.topNav.containsKey('enabled')) 'enabled': true,
        if (!config.topNav.containsKey('showInbox')) 'showInbox': true,
        if (!config.topNav.containsKey('showCompanyName')) 'showCompanyName': true,
        if (!config.topNav.containsKey('showUserRole')) 'showUserRole': true,
        if (!config.topNav.containsKey('showOnlineStatus')) 'showOnlineStatus': true,
        if (!config.topNav.containsKey('showLogout')) 'showLogout': false,
        if (!config.topNav.containsKey('inboxBadge')) 'inboxBadge': true,
        if (!config.topNav.containsKey('showAvatar')) 'showAvatar': true,
        if (!config.topNav.containsKey('showPresenceGlow')) 'showPresenceGlow': true,
      },
      sections: sections,
      taskCard: <String, dynamic>{
        'variant': MobileUiConfig.allowedCardVariants.contains(config.taskCardVariant) ? config.taskCardVariant : 'modernCard',
        'showFields': config.taskCardFields,
        'actions': <String>['changeStatus', 'comment', 'uploadFile'],
      },
      projectCard: <String, dynamic>{
        'variant': MobileUiConfig.allowedCardVariants.contains(config.projectCardVariant) ? config.projectCardVariant : 'progressCard',
        'showFields': config.projectCardFields,
        'actions': <String>['openDetails'],
      },
      taskListConfig: Map<String, dynamic>.from(config.taskListConfig),
      profileActions: Map<String, dynamic>.from(config.profileActions),
      designSystem: Map<String, dynamic>.from(config.designSystem),
      animationConfig: Map<String, dynamic>.from(config.animationConfig),
      layoutConfig: Map<String, dynamic>.from(config.layoutConfig),
      navigationConfig: Map<String, dynamic>.from(config.navigationConfig),
      floatingTopNav: Map<String, dynamic>.from(config.floatingTopNav),
      floatingBottomNav: Map<String, dynamic>.from(config.floatingBottomNav),
      quickActionDock: Map<String, dynamic>.from(config.quickActionDock),
      sideMenuConfig: Map<String, dynamic>.from(config.sideMenuConfig),
      homeLayout: Map<String, dynamic>.from(config.homeLayout),
      homeCardConfig: Map<String, dynamic>.from(config.homeCardConfig),
      screenConfigs: Map<String, dynamic>.from(config.screenConfigs),
      screenRegistry: Map<String, dynamic>.from(config.screenRegistry),
      navigationGraph: Map<String, dynamic>.from(config.navigationGraph),
      profileCardConfig: Map<String, dynamic>.from(config.profileCardConfig),
      projectListConfig: Map<String, dynamic>.from(config.projectListConfig),
      dataBindings: Map<String, dynamic>.from(config.dataBindings),
      rendererCompatibility: Map<String, dynamic>.from(config.rendererCompatibility),
      inboxConfig: Map<String, dynamic>.from(config.inboxConfig),
      profileFields: List<String>.from(config.profileFields),
      supportedWidgets: List<String>.from(config.supportedWidgets),
      notificationAlertConfig: Map<String, dynamic>.from(config.notificationAlertConfig),
      notificationSoundOptions: Map<String, dynamic>.from(config.notificationSoundOptions),
      texts: Map<String, dynamic>.from(config.texts),
      updatedAt: config.updatedAt,
      updatedBy: config.updatedBy,
    );
  }

  factory MobileUiDesign.fromMap(Map<String, dynamic>? data) {
    if (data == null) return MobileUiDesign.defaults();
    return MobileUiDesign(
      version: JsonValue.integer(data['version'], fallback: 1),
      enabled: JsonValue.boolean(data['enabled'], fallback: true),
      templateName: JsonValue.string(data['templateName'], fallback: 'cleanWorkApp'),
      theme: _safeMap(data['theme'], MobileUiDesign.defaults().theme),
      bottomNav: _safeMap(data['bottomNav'], MobileUiDesign.defaults().bottomNav),
      topNav: _safeMap(data['topNav'] ?? data['topNva'], MobileUiDesign.defaults().topNav),
      sections: _safeMapList(data['sections'], MobileUiDesign.defaults().sections),
      taskCard: _safeMap(data['taskCard'], MobileUiDesign.defaults().taskCard),
      projectCard: _safeMap(data['projectCard'], MobileUiDesign.defaults().projectCard),
      taskListConfig: _safeMap(data['taskListConfig'], MobileUiDesign.defaults().taskListConfig),
      profileActions: _safeMap(data['profileActions'], MobileUiDesign.defaults().profileActions),
      designSystem: _safeMap(data['designSystem'], MobileUiDesign.defaults().designSystem),
      animationConfig: _safeMap(data['animationConfig'], MobileUiDesign.defaults().animationConfig),
      layoutConfig: _safeMap(data['layoutConfig'], MobileUiDesign.defaults().layoutConfig),
      navigationConfig: _safeMap(data['navigationConfig'], MobileUiDesign.defaults().navigationConfig),
      floatingTopNav: _safeMap(data['floatingTopNav'], MobileUiDesign.defaults().floatingTopNav),
      floatingBottomNav: _safeMap(data['floatingBottomNav'], MobileUiDesign.defaults().floatingBottomNav),
      quickActionDock: _safeMap(data['quickActionDock'], MobileUiDesign.defaults().quickActionDock),
      sideMenuConfig: _safeMap(data['sideMenuConfig'], MobileUiDesign.defaults().sideMenuConfig),
      homeLayout: _safeMap(data['homeLayout'], MobileUiDesign.defaults().homeLayout),
      homeCardConfig: _safeMap(data['homeCardConfig'], MobileUiDesign.defaults().homeCardConfig),
      screenConfigs: _safeMap(data['screenConfigs'], MobileUiDesign.defaults().screenConfigs),
      screenRegistry: _safeMap(data['screenRegistry'], MobileUiDesign.defaults().screenRegistry),
      navigationGraph: _safeMap(data['navigationGraph'], MobileUiDesign.defaults().navigationGraph),
      profileCardConfig: _safeMap(data['profileCardConfig'], MobileUiDesign.defaults().profileCardConfig),
      projectListConfig: _safeMap(data['projectListConfig'], MobileUiDesign.defaults().projectListConfig),
      dataBindings: _safeMap(data['dataBindings'], MobileUiDesign.defaults().dataBindings),
      rendererCompatibility: _safeMap(data['rendererCompatibility'], MobileUiDesign.defaults().rendererCompatibility),
      inboxConfig: _safeMap(data['inboxConfig'], MobileUiDesign.defaults().inboxConfig),
      profileFields: _safeStringList(data['profileFields'], MobileUiDesign.defaults().profileFields, MobileUiConfig.defaultProfileFields.toSet()),
      supportedWidgets: _safeLooseStringList(data['supportedWidgets'], MobileUiDesign.defaults().supportedWidgets),
      notificationAlertConfig: _safeMap(data['notificationAlertConfig'], MobileUiDesign.defaults().notificationAlertConfig),
      notificationSoundOptions: _safeMap(data['notificationSoundOptions'], MobileUiDesign.defaults().notificationSoundOptions),
      texts: _safeMap(data['texts'] ?? data['text'] ?? data['strings'] ?? data['copy'] ?? data['textOverrides'], const <String, dynamic>{}),
      screenOverrides: _safeScreenOverrides(data['screenOverrides']),
      updatedAt: _parseDate(data['updatedAt']),
      updatedBy: JsonValue.optionalString(data['updatedBy']),
    );
  }

  static Map<String, dynamic> _safeMap(dynamic value, Map<String, dynamic> fallback) {
    if (value is Map) {
      return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    }
    return Map<String, dynamic>.from(fallback);
  }

  static List<Map<String, dynamic>> _safeMapList(dynamic value, List<Map<String, dynamic>> fallback) {
    if (value is List) {
      final result = value.whereType<Map>().map((item) => item.map((key, mapValue) => MapEntry(key.toString(), mapValue))).toList();
      return result.isEmpty ? fallback : result;
    }
    return fallback.map(Map<String, dynamic>.from).toList();
  }

  static Map<String, Map<String, dynamic>> _safeScreenOverrides(dynamic value) {
    if (value is! Map) return const <String, Map<String, dynamic>>{};
    final result = <String, Map<String, dynamic>>{};
    for (final entry in value.entries) {
      final screenKey = entry.key.toString();
      final screenValue = entry.value;
      if (screenValue is Map) {
        result[screenKey] = screenValue.map((key, mapValue) => MapEntry(key.toString(), mapValue));
      }
    }
    return result;
  }

  static Map<String, dynamic> _deepCloneMap(Map<String, dynamic> value) {
    return value.map((key, mapValue) {
      if (mapValue is Map) return MapEntry(key, _deepCloneMap(mapValue.map((k, v) => MapEntry(k.toString(), v))));
      if (mapValue is List) {
        return MapEntry(key, mapValue.map((item) {
          if (item is Map) return _deepCloneMap(item.map((k, v) => MapEntry(k.toString(), v)));
          return item;
        }).toList());
      }
      return MapEntry(key, mapValue);
    });
  }

  static Map<String, Map<String, dynamic>> _deepCloneScreenOverrides(Map<String, Map<String, dynamic>> value) {
    return value.map((key, mapValue) => MapEntry(key, _deepCloneMap(mapValue)));
  }

  static Map<String, Map<String, dynamic>> cloneScreenOverrides(Map<String, Map<String, dynamic>> value) {
    return _deepCloneScreenOverrides(value);
  }

  static Map<String, dynamic>? screenPayload(Map<String, dynamic> rawJson, String screen) {
    final screens = rawJson['screens'];
    if (screens is Map) {
      final exact = screens[screen];
      if (exact is Map) return exact.map((key, value) => MapEntry(key.toString(), value));
    }
    final screenLayouts = rawJson['screenLayouts'];
    if (screenLayouts is Map) {
      final exact = screenLayouts[screen];
      if (exact is Map) return exact.map((key, value) => MapEntry(key.toString(), value));
    }
    return rawJson;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    try {
      if (value is DateTime) return value;
      if (value.runtimeType.toString() == 'Timestamp') {
        return (value as dynamic).toDate() as DateTime;
      }
      return DateTime.tryParse(value.toString());
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _sectionFromId(String id) {
    return <String, dynamic>{
      'id': id,
      'type': sectionTypes[id] ?? id,
      'title': sectionLabels[id] ?? id,
      'style': id == 'deadlineTimer' ? 'compact' : 'modern',
      'visible': true,
    };
  }

  List<String> get bottomTabs => _safeStringList(bottomNav['tabs'], MobileUiConfig.defaults().bottomTabs, MobileUiConfig.allowedBottomTabs.toSet());
  List<String> get visibleHomeCardIds => sections
      .where((section) => section['visible'] != false)
      .map((section) => section['id']?.toString() ?? '')
      .where((id) => MobileUiConfig.allowedHomeCards.contains(id))
      .toSet()
      .toList();
  List<String> get taskFields => _safeStringList(taskCard['showFields'], MobileUiConfig.defaults().taskCardFields, MobileUiConfig.allowedTaskCardFields.toSet());
  List<String> get projectFields => _safeStringList(projectCard['showFields'], MobileUiConfig.defaults().projectCardFields, MobileUiConfig.allowedProjectCardFields.toSet());

  static List<String> _safeLooseStringList(dynamic value, List<String> fallback) {
    final rawItems = JsonValue.stringList(value);
    if (rawItems.isEmpty) return fallback;
    final seen = <String>{};
    final result = rawItems.where((item) => item.trim().isNotEmpty && seen.add(item)).toList();
    return result.isEmpty ? fallback : result;
  }

  static List<String> _safeStringList(dynamic value, List<String> fallback, Set<String> allowed) {
    final rawItems = JsonValue.stringList(value);
    if (rawItems.isEmpty) return fallback;
    final result = rawItems.where(allowed.contains).toSet().toList();
    return result.isEmpty ? fallback : result;
  }

  int get cardRadius => JsonValue.integer(theme['cardRadius'], fallback: 24).clamp(8, 40).toInt();
  int get cardPadding => JsonValue.integer(theme['cardPadding'], fallback: 16).clamp(8, 32).toInt();
  bool get compactMode => JsonValue.string(theme['density'], fallback: 'comfortable') == 'compact';
  String get accent => JsonValue.string(theme['accent'], fallback: '#2563EB');
  String get background => JsonValue.string(theme['background'], fallback: '#F6F8FB');
  String get surface => JsonValue.string(theme['surface'], fallback: '#FFFFFF');
  String get topNavStyle => JsonValue.string(topNav['style'], fallback: 'glassAdvanced');
  bool get topNavEnabled => JsonValue.boolean(topNav['enabled'], fallback: true);

  MobileUiConfig toMobileConfig({int? versionOverride}) {
    final homeCards = visibleHomeCardIds;
    return MobileUiConfig(
      enabled: enabled,
      version: versionOverride ?? version,
      bottomTabs: bottomTabs,
      topNav: topNav,
      homeCards: homeCards.isEmpty ? MobileUiConfig.defaults().homeCards : homeCards,
      taskCardFields: taskFields,
      projectCardFields: projectFields,
      taskCardVariant: MobileUiConfig.allowedCardVariants.contains(taskCard['variant']?.toString()) ? taskCard['variant'].toString() : MobileUiConfig.defaults().taskCardVariant,
      projectCardVariant: MobileUiConfig.allowedCardVariants.contains(projectCard['variant']?.toString()) ? projectCard['variant'].toString() : MobileUiConfig.defaults().projectCardVariant,
      taskListConfig: taskListConfig.isEmpty ? MobileUiConfig.defaults().taskListConfig : taskListConfig,
      profileActions: profileActions.isEmpty ? MobileUiConfig.defaults().profileActions : profileActions,
      inboxConfig: inboxConfig,
      profileFields: profileFields,
      supportedWidgets: supportedWidgets,
      notificationAlertConfig: notificationAlertConfig,
      notificationSoundOptions: notificationSoundOptions,
      texts: texts,
      designSystem: designSystem,
      animationConfig: animationConfig,
      layoutConfig: layoutConfig,
      navigationConfig: navigationConfig,
      bottomNav: bottomNav,
      floatingTopNav: floatingTopNav,
      floatingBottomNav: floatingBottomNav,
      quickActionDock: quickActionDock,
      sideMenuConfig: sideMenuConfig,
      homeLayout: homeLayout,
      homeCardConfig: homeCardConfig,
      screenConfigs: screenConfigs,
      screenOverrides: screenOverrides,
      screenRegistry: screenRegistry,
      navigationGraph: navigationGraph,
      profileCardConfig: profileCardConfig,
      projectListConfig: projectListConfig,
      dataBindings: dataBindings,
      rendererCompatibility: rendererCompatibility,
      compactMode: compactMode,
      updatedAt: DateTime.now(),
      updatedBy: updatedBy,
    );
  }

  String get cacheSignature => jsonEncode(<String, Object?>{
        'version': version,
        'enabled': enabled,
        'templateName': templateName,
        'theme': theme,
        'bottomNav': bottomNav,
        'topNav': topNav,
        'sections': sections,
        'taskCard': taskCard,
        'projectCard': projectCard,
        'taskListConfig': taskListConfig,
        'profileActions': profileActions,
        'designSystem': designSystem,
        'animationConfig': animationConfig,
        'layoutConfig': layoutConfig,
        'navigationConfig': navigationConfig,
        'floatingTopNav': floatingTopNav,
        'floatingBottomNav': floatingBottomNav,
        'quickActionDock': quickActionDock,
        'sideMenuConfig': sideMenuConfig,
        'homeLayout': homeLayout,
        'homeCardConfig': homeCardConfig,
        'screenConfigs': screenConfigs,
        'screenRegistry': screenRegistry,
        'navigationGraph': navigationGraph,
        'profileCardConfig': profileCardConfig,
        'projectListConfig': projectListConfig,
        'dataBindings': dataBindings,
        'rendererCompatibility': rendererCompatibility,
        'inboxConfig': inboxConfig,
        'profileFields': profileFields,
        'supportedWidgets': supportedWidgets,
        'notificationAlertConfig': notificationAlertConfig,
        'notificationSoundOptions': notificationSoundOptions,
        'texts': texts,
        'screenOverrides': screenOverrides,
      });

  Map<String, dynamic> toMap({String? updatedBy}) {
    return <String, dynamic>{
      'version': version,
      'enabled': enabled,
      'templateName': templateName,
      'theme': theme,
      'bottomNav': bottomNav,
      'topNav': topNav,
      'sections': sections,
      'taskCard': taskCard,
      'projectCard': projectCard,
      'taskListConfig': taskListConfig,
      'profileActions': profileActions,
      'designSystem': designSystem,
      'animationConfig': animationConfig,
      'layoutConfig': layoutConfig,
      'navigationConfig': navigationConfig,
      'floatingTopNav': floatingTopNav,
      'floatingBottomNav': floatingBottomNav,
      'quickActionDock': quickActionDock,
      'sideMenuConfig': sideMenuConfig,
      'homeLayout': homeLayout,
      'homeCardConfig': homeCardConfig,
      'screenConfigs': screenConfigs,
      'screenRegistry': screenRegistry,
      'navigationGraph': navigationGraph,
      'profileCardConfig': profileCardConfig,
      'projectListConfig': projectListConfig,
      'dataBindings': dataBindings,
      'rendererCompatibility': rendererCompatibility,
      'inboxConfig': inboxConfig,
      'profileFields': profileFields,
      'supportedWidgets': supportedWidgets,
      'notificationAlertConfig': notificationAlertConfig,
      'notificationSoundOptions': notificationSoundOptions,
      'texts': texts,
      if (screenOverrides.isNotEmpty) 'screenOverrides': _deepCloneScreenOverrides(screenOverrides),
      'updatedBy': updatedBy ?? this.updatedBy,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  String toPrettyJson({String? updatedBy}) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toMap(updatedBy: updatedBy));
  }

  MobileUiDesign copyWith({
    int? version,
    bool? enabled,
    String? templateName,
    Map<String, dynamic>? theme,
    Map<String, dynamic>? bottomNav,
    Map<String, dynamic>? topNav,
    List<Map<String, dynamic>>? sections,
    Map<String, dynamic>? taskCard,
    Map<String, dynamic>? projectCard,
    Map<String, dynamic>? taskListConfig,
    Map<String, dynamic>? profileActions,
    Map<String, dynamic>? designSystem,
    Map<String, dynamic>? animationConfig,
    Map<String, dynamic>? layoutConfig,
    Map<String, dynamic>? navigationConfig,
    Map<String, dynamic>? floatingTopNav,
    Map<String, dynamic>? floatingBottomNav,
    Map<String, dynamic>? quickActionDock,
    Map<String, dynamic>? sideMenuConfig,
    Map<String, dynamic>? homeLayout,
    Map<String, dynamic>? homeCardConfig,
    Map<String, dynamic>? screenConfigs,
    Map<String, dynamic>? screenRegistry,
    Map<String, dynamic>? navigationGraph,
    Map<String, dynamic>? profileCardConfig,
    Map<String, dynamic>? projectListConfig,
    Map<String, dynamic>? dataBindings,
    Map<String, dynamic>? rendererCompatibility,
    Map<String, dynamic>? inboxConfig,
    List<String>? profileFields,
    List<String>? supportedWidgets,
    Map<String, dynamic>? notificationAlertConfig,
    Map<String, dynamic>? notificationSoundOptions,
    Map<String, dynamic>? texts,
    Map<String, Map<String, dynamic>>? screenOverrides,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return MobileUiDesign(
      version: version ?? this.version,
      enabled: enabled ?? this.enabled,
      templateName: templateName ?? this.templateName,
      theme: theme ?? this.theme,
      bottomNav: bottomNav ?? this.bottomNav,
      topNav: topNav ?? this.topNav,
      sections: sections ?? this.sections,
      taskCard: taskCard ?? this.taskCard,
      projectCard: projectCard ?? this.projectCard,
      taskListConfig: taskListConfig ?? this.taskListConfig,
      profileActions: profileActions ?? this.profileActions,
      designSystem: designSystem ?? this.designSystem,
      animationConfig: animationConfig ?? this.animationConfig,
      layoutConfig: layoutConfig ?? this.layoutConfig,
      navigationConfig: navigationConfig ?? this.navigationConfig,
      floatingTopNav: floatingTopNav ?? this.floatingTopNav,
      floatingBottomNav: floatingBottomNav ?? this.floatingBottomNav,
      quickActionDock: quickActionDock ?? this.quickActionDock,
      sideMenuConfig: sideMenuConfig ?? this.sideMenuConfig,
      homeLayout: homeLayout ?? this.homeLayout,
      homeCardConfig: homeCardConfig ?? this.homeCardConfig,
      screenConfigs: screenConfigs ?? this.screenConfigs,
      screenRegistry: screenRegistry ?? this.screenRegistry,
      navigationGraph: navigationGraph ?? this.navigationGraph,
      profileCardConfig: profileCardConfig ?? this.profileCardConfig,
      projectListConfig: projectListConfig ?? this.projectListConfig,
      dataBindings: dataBindings ?? this.dataBindings,
      rendererCompatibility: rendererCompatibility ?? this.rendererCompatibility,
      inboxConfig: inboxConfig ?? this.inboxConfig,
      profileFields: profileFields ?? this.profileFields,
      supportedWidgets: supportedWidgets ?? this.supportedWidgets,
      notificationAlertConfig: notificationAlertConfig ?? this.notificationAlertConfig,
      notificationSoundOptions: notificationSoundOptions ?? this.notificationSoundOptions,
      texts: texts ?? this.texts,
      screenOverrides: screenOverrides ?? this.screenOverrides,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
