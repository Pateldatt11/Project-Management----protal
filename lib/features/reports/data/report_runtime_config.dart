class ReportRuntimeConfig {
  const ReportRuntimeConfig._();

  /// Local Flutter Web report generation is always available. Storage upload is
  /// optional so localhost does not fail because of Storage rules/CORS.
  static const bool uploadPdfToFirebaseStorage = bool.fromEnvironment(
    'UPLOAD_REPORTS_TO_FIREBASE_STORAGE',
    defaultValue: false,
  );
}
