class CloudinaryConfig {
  const CloudinaryConfig._();

  /// Cloudinary Cloud Name
  static const String cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'oebzufak',
  );

  /// Unsigned upload preset created in Cloudinary dashboard.
  static const String uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'testing',
  );

  /// Optional Cloudinary folder where images are stored.
  static const String folder = String.fromEnvironment(
    'CLOUDINARY_FOLDER',
    defaultValue: 'project_management_dashboard',
  );

  static bool get isConfigured =>
      cloudName.trim().isNotEmpty && uploadPreset.trim().isNotEmpty;
}