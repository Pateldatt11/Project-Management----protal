class NotificationBackendConfig {
  const NotificationBackendConfig._();

  /// Production example:
  /// flutter build web -t lib/main_admin.dart \
  ///   --dart-define=NOTIFICATION_BACKEND_BASE_URL=https://api.example.com
  static const String baseUrl = String.fromEnvironment(
    'NOTIFICATION_BACKEND_BASE_URL',
    defaultValue: '',
  );

  static bool get isConfigured => baseUrl.trim().isNotEmpty;

  static Uri endpoint(String path) {
    final cleanBase = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final cleanPath = path.startsWith('/') ? path : '/$path';
    if (cleanBase.isEmpty) {
      throw StateError(
        'NOTIFICATION_BACKEND_BASE_URL is not configured. '
        'Build the admin web app with --dart-define.',
      );
    }
    return Uri.parse('$cleanBase$cleanPath');
  }
}
