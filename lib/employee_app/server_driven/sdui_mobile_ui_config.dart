import 'package:flutter/material.dart';

/// Safe parser for the Firestore SDUI mobile UI document.
///
/// This class intentionally keeps the raw map available so your existing
/// renderer can continue reading old keys while the new floating native shell
/// reads the v62 keys.
class SduiMobileUiConfig {
  const SduiMobileUiConfig(this.raw);

  final Map<String, dynamic> raw;

  factory SduiMobileUiConfig.fromFirestore(Map<String, dynamic>? data) {
    return SduiMobileUiConfig(Map<String, dynamic>.from(data ?? const {}));
  }

  bool get enabled => _bool(raw['enabled'], fallback: true);
  bool get compactMode => _bool(raw['compactMode']);
  int get version => _int(raw['version']);
  String get templateName {
    final direct = _str(raw['templateName']);
    if (direct.isNotEmpty) return direct;
    final fromDesignSystem = _str(designSystem['templateName']);
    if (fromDesignSystem.isNotEmpty) return fromDesignSystem;
    final mode = _str(designSystem['mode']);
    if (mode == 'minimalPaperNative' || mode == 'projectManagementNeutralNative') return 'editorialNativeUi';
    return 'cleanWorkApp';
  }


  List<String> get bottomTabs => _stringList(raw['bottomTabs'], fallback: const [
        'home',
        'tasks',
        'projects',
        'profile',
      ]);

  List<String> get supportedWidgets => _stringList(raw['supportedWidgets']);

  Map<String, dynamic> get designSystem => _map(raw['designSystem']);
  Map<String, dynamic> get animationConfig => _map(raw['animationConfig']);
  Map<String, dynamic> get layoutConfig => _map(raw['layoutConfig']);
  Map<String, dynamic> get navigationConfig => _map(raw['navigationConfig']);
  Map<String, dynamic> get topNav => _map(raw['topNav']);
  Map<String, dynamic> get bottomNav => _map(raw['bottomNav']);
  Map<String, dynamic> get floatingTopNav => _map(raw['floatingTopNav']);
  Map<String, dynamic> get floatingBottomNav => _map(raw['floatingBottomNav']);
  Map<String, dynamic> get quickActionDock => _map(raw['quickActionDock']);
  Map<String, dynamic> get homeLayout => _map(raw['homeLayout']);
  Map<String, dynamic> get homeCardConfig => _map(raw['homeCardConfig']);
  Map<String, dynamic> get screenConfigs => _map(raw['screenConfigs']);
  Map<String, dynamic> get profileCardConfig => _map(raw['profileCardConfig']);
  Map<String, dynamic> get projectListConfig => _map(raw['projectListConfig']);
  Map<String, dynamic> get taskListConfig => _map(raw['taskListConfig']);
  Map<String, dynamic> get profileActions => _map(raw['profileActions']);
  Map<String, dynamic> get taskCard => _map(raw['taskCard']);
  Map<String, dynamic> get projectCard => _map(raw['projectCard']);

  Map<String, dynamic> get dataBindings => _map(raw['dataBindings']);
  Map<String, dynamic> get rendererCompatibility => _map(raw['rendererCompatibility']);
  Map<String, dynamic> get inboxConfig => _map(raw['inboxConfig']);
  Map<String, dynamic> get textConfig => _map(raw['text'] ?? raw['texts'] ?? raw['strings'] ?? raw['copy'] ?? raw['textOverrides']);

  String text(String key, {String fallback = ''}) {
    final keys = <String>[key];
    final dotCompact = key.replaceAll('.', '_');
    if (dotCompact != key) keys.add(dotCompact);
    for (final candidate in keys) {
      final direct = _str(textConfig[candidate]);
      if (direct.isNotEmpty) return direct;
      final nested = _lookupPath(textConfig, candidate);
      if (nested.isNotEmpty) return nested;
    }
    return fallback;
  }

  String routeLabel(String route, {String fallback = ''}) {
    final screen = _map(screenConfigs[route]);
    final labels = _map(textConfig['routeLabels'] ?? textConfig['screenLabels'] ?? raw['routeLabels'] ?? raw['screenLabels']);
    final fromText = text('routes.$route', fallback: text('screens.$route.title'));
    if (fromText.isNotEmpty) return fromText;
    final fromLabels = _str(labels[route]);
    if (fromLabels.isNotEmpty) return fromLabels;
    final fromScreen = _str(screen['label'] ?? screen['title']);
    if (fromScreen.isNotEmpty) return fromScreen;
    return fallback;
  }

  bool get screenBodyOnly {
    return _bool(layoutConfig['screenBodyOnly']) ||
        _str(navigationConfig['contentRenderMode']) == 'screenBodyOnly';
  }

  bool get preserveNativeShell {
    return _str(navigationConfig['shellPolicy']) == 'preserveNativeShell' ||
        _str(designSystem['shellPolicy']) == 'preserveNativeShell';
  }

  bool get nativeStatusBarOnly {
    return _str(navigationConfig['statusBarPolicy']) == 'nativeOnly' ||
        _str(designSystem['statusBarPolicy']) == 'nativeOnly';
  }

  bool get floatingTopEnabled {
    return _bool(topNav['enabled'], fallback: true) &&
        (_bool(topNav['floating']) || _bool(floatingTopNav['enabled']));
  }

  bool get floatingBottomEnabled {
    return _bool(bottomNav['enabled'], fallback: true) ||
        _bool(floatingBottomNav['enabled']);
  }

  double get contentPaddingTop => _double(layoutConfig['contentPaddingTop'], fallback: 86);
  double get contentPaddingBottom => _double(layoutConfig['contentPaddingBottom'], fallback: 106);
  double get horizontalPadding => _double(layoutConfig['horizontalPadding'], fallback: 18);
  double get maxContentWidth => _double(layoutConfig['maxContentWidth'], fallback: 560);

  Duration get shortAnimationDuration {
    final enabled = _bool(animationConfig['enabled'], fallback: true);
    if (!enabled) return Duration.zero;
    final milliseconds = _int(
      animationConfig['shortDurationMs'],
      fallback: 220,
    ).clamp(0, 1200).toInt();
    return Duration(milliseconds: milliseconds);
  }

  Duration get mediumAnimationDuration {
    final enabled = _bool(animationConfig['enabled'], fallback: true);
    if (!enabled) return Duration.zero;
    final milliseconds = _int(
      animationConfig['mediumDurationMs'],
      fallback: 320,
    ).clamp(0, 1600).toInt();
    return Duration(milliseconds: milliseconds);
  }

  Curve get defaultCurve {
    final style = _str(animationConfig['style']).toLowerCase().trim();
    if (style == 'smooth') return Curves.easeInOutCubicEmphasized;
    if (style == 'linear') return Curves.linear;
    return Curves.easeOutCubic;
  }

  Color surfaceColor(BuildContext context) => colorFromHex(
        _str(designSystem['surface'], fallback: '#F3F4F1'),
        Theme.of(context).colorScheme.surface,
      );

  Color cardColor(BuildContext context) => colorFromHex(
        _str(designSystem['card'], fallback: '#FFFFFF'),
        Theme.of(context).cardColor,
      );

  Color primaryTextColor(BuildContext context) => colorFromHex(
        _str(designSystem['textPrimary'], fallback: '#0A0D0A'),
        Theme.of(context).colorScheme.onSurface,
      );

  Color secondaryTextColor(BuildContext context) => colorFromHex(
        _str(designSystem['textSecondary'], fallback: '#687269'),
        Theme.of(context).colorScheme.onSurfaceVariant,
      );

  Color borderColor(BuildContext context) => colorFromHex(
        _str(designSystem['border'], fallback: '#D9DFDA'),
        Theme.of(context).dividerColor,
      );

  String titleForTab(String tab) {
    final routeTitleMap = _map(floatingTopNav['routeTitleMap']);
    final fromFloating = _str(routeTitleMap[tab]);
    if (fromFloating.isNotEmpty) return fromFloating;

    final fromText = routeLabel(tab);
    if (fromText.isNotEmpty) return fromText;

    return _humanizeRoute(tab);
  }

  static Color colorFromHex(String hex, Color fallback) {
    var value = hex.trim();
    if (value.isEmpty) return fallback;
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 6) value = 'FF$value';
    if (value.length != 8) return fallback;
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed);
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<String> _stringList(dynamic value, {List<String> fallback = const []}) {
    if (value is Iterable) {
      final result = value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      return result.isEmpty ? fallback : result;
    }
    return fallback;
  }

  static String _lookupPath(Map<String, dynamic> source, String path) {
    if (path.trim().isEmpty) return '';
    dynamic current = source;
    for (final part in path.split('.')) {
      if (current is Map) {
        current = current[part];
      } else {
        return '';
      }
    }
    return _str(current);
  }

  static String _humanizeRoute(String route) {
    final raw = route.trim();
    if (raw.isEmpty) return '';
    final spaced = raw
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (match) => '${match.group(1)} ${match.group(2)}')
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .trim();
    if (spaced.isEmpty) return raw;
    return spaced
        .split(RegExp(r'\s+'))
        .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static String _str(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  static bool _bool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase().trim();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return fallback;
  }

  static int _int(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _double(dynamic value, {double fallback = 0}) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
