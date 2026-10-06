import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/config/cloudinary_config.dart';

class CloudinaryUploadResult {
  const CloudinaryUploadResult({
    required this.secureUrl,
    required this.publicId,
  });

  final String secureUrl;
  final String publicId;
}

class CloudinaryUploadService {
  CloudinaryUploadService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<CloudinaryUploadResult> uploadImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!CloudinaryConfig.isConfigured) {
      throw StateError(
        'Cloudinary is not configured. Check cloudName and uploadPreset in cloudinary_config.dart.',
      );
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName.trim()}/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = CloudinaryConfig.uploadPreset.trim();

    final folder = CloudinaryConfig.folder.trim();
    if (folder.isNotEmpty) {
      request.fields['folder'] = folder;
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ),
    );

    final streamedResponse = await _client.send(request);
    final responseBody = await streamedResponse.stream.bytesToString();

    if (streamedResponse.statusCode < 200 || streamedResponse.statusCode >= 300) {
      throw StateError('Cloudinary upload failed (${streamedResponse.statusCode}): $responseBody');
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Cloudinary upload returned invalid response.');
    }

    final secureUrl = (decoded['secure_url'] ?? '').toString();
    final publicId = (decoded['public_id'] ?? '').toString();

    if (secureUrl.trim().isEmpty || publicId.trim().isEmpty) {
      throw StateError('Cloudinary upload response is missing secure_url/public_id.');
    }

    return CloudinaryUploadResult(secureUrl: secureUrl, publicId: publicId);
  }
}