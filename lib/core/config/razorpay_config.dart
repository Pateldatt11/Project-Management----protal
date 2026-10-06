class RazorpayConfig {
  const RazorpayConfig._();

  /// Build with:
  ///   flutter run -d chrome --dart-define=RAZORPAY_KEY_ID=rzp_test_xxxxx
  static const String keyId = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: '',
  );

  static bool get isConfigured => keyId.trim().isNotEmpty;

  static String get displayName {
    final trimmed = keyId.trim();
    if (trimmed.isEmpty) return 'Razorpay not configured';
    if (trimmed.length <= 8) return trimmed;
    return '${trimmed.substring(0, 4)}...${trimmed.substring(trimmed.length - 4)}';
  }
}