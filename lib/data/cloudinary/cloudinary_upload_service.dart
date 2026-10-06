import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/config/cloudinary_config.dart';

class CloudinaryUploadResult {
  const CloudinaryUploadResult({
    required this.secureUrl,
    required this.publicId,
    required this.resourceType,
    required this.bytes,
  });

  final String secureUrl;
  final String publicId;
  final String resourceType;
  final int bytes;
}

class CloudinaryUploadService {
  CloudinaryUploadService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Uploads any supported business attachment to Cloudinary.
  ///
  /// `auto/upload` is intentional: using `image/upload` rejects raw business
  /// files such as DOCX/XLSX/TXT. Cloudinary detects image/PDF/raw types.
  Future<CloudinaryUploadResult> uploadFile({
    required Uint8List bytes,
    required String fileName,
    String? contentType,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    if (!CloudinaryConfig.isConfigured) {
      throw StateError(
        'Cloudinary is not configured. Check cloudName and uploadPreset in cloudinary_config.dart.',
      );
    }
    if (bytes.isEmpty) {
      throw StateError('Cannot upload an empty file to Cloudinary.');
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName.trim()}/auto/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = CloudinaryConfig.uploadPreset.trim();

    final folder = CloudinaryConfig.folder.trim();
    if (folder.isNotEmpty) {
      request.fields['folder'] = folder;
    }

    // Keeping the original filename makes Cloudinary assets easier to identify.
    final cleanName = fileName.trim().isEmpty ? 'attachment' : fileName.trim();
    request.fields['filename_override'] = cleanName;

    final totalBytes = bytes.lengthInBytes;
    onProgress?.call(0, totalBytes);

    request.files.add(
      http.MultipartFile(
        'file',
        _trackProgress(bytes, onProgress),
        totalBytes,
        filename: cleanName,
      ),
    );

    final streamedResponse = await _client.send(request);
    final responseBody = await streamedResponse.stream.bytesToString();

    if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
      throw StateError(
        'Cloudinary upload failed (${streamedResponse.statusCode}): $responseBody',
      );
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Cloudinary upload returned an invalid response.');
    }

    final secureUrl = (decoded['secure_url'] ?? '').toString().trim();
    final publicId = (decoded['public_id'] ?? '').toString().trim();
    final resourceType = (decoded['resource_type'] ?? 'auto').toString().trim();
    final uploadedBytes = decoded['bytes'] is num
        ? (decoded['bytes'] as num).toInt()
        : totalBytes;

    if (secureUrl.isEmpty || publicId.isEmpty) {
      throw StateError(
        'Cloudinary upload response is missing secure_url/public_id.',
      );
    }

    onProgress?.call(totalBytes, totalBytes);

    return CloudinaryUploadResult(
      secureUrl: secureUrl,
      publicId: publicId,
      resourceType: resourceType,
      bytes: uploadedBytes,
    );
  }

  /// Backwards-compatible image helper for any older caller.
  Future<CloudinaryUploadResult> uploadImage({
    required Uint8List bytes,
    required String fileName,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) {
    return uploadFile(
      bytes: bytes,
      fileName: fileName,
      onProgress: onProgress,
    );
  }

  Stream<List<int>> _trackProgress(
    Uint8List bytes,
    void Function(int sentBytes, int totalBytes)? onProgress,
  ) async* {
    if (onProgress == null) {
      yield bytes;
      return;
    }

    const chunkSize = 64 * 1024;
    final totalBytes = bytes.lengthInBytes;
    var sentBytes = 0;

    for (var offset = 0; offset < totalBytes; offset += chunkSize) {
      final end = (offset + chunkSize < totalBytes)
          ? offset + chunkSize
          : totalBytes;
      final chunk = bytes.sublist(offset, end);
      yield chunk;
      sentBytes += chunk.length;
      onProgress(sentBytes, totalBytes);
    }
  }
}
