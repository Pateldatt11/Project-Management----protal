class AppConfig {
  const AppConfig._();

  /// Firebase is now the default because the project already contains
  /// firebase_options.dart, google-services.json, firebase.json, and Firestore rules.
  ///
  /// Normal run:
  ///   flutter run -d chrome
  ///
  /// Force demo mode only when needed:
  ///   flutter run -d chrome --dart-define=USE_FIREBASE=false
  static const bool useFirebase = bool.fromEnvironment('USE_FIREBASE', defaultValue: true);

  /// Default company workspace used for first bootstrap and local/demo mode.
  static const String fallbackCompanyId = String.fromEnvironment('COMPANY_ID', defaultValue: 'company_001');

  /// Controls whether Firebase mode starts with demo overlay enabled when the
  /// Firestore settings document has not been created yet.
  ///
  /// Admins can still change it from Settings -> Data Source Control.
  static const bool defaultDemoDataEnabled = bool.fromEnvironment('ENABLE_DEMO_DATA', defaultValue: true);

  static const String appName = 'ProjectOS Dashboard';
  static const String version = '1.0.0';
}
