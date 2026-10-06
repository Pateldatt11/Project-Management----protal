import 'dart:typed_data';

import 'package:flutter/services.dart';
// THIS IS THE FIX: Added "as fp" to prevent naming conflicts
import 'package:file_picker/file_picker.dart' as fp; 

class PickedBusinessFile {
  const PickedBusinessFile({
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final int sizeBytes;
  final Uint8List bytes;
}

class AndroidFilePickerService {
  AndroidFilePickerService._();

  static const int maxBusinessFileBytes = 25 * 1024 * 1024;

  static const List<String> allowedMimeTypes = <String>[
    'image/png',
    'image/jpeg',
    'image/webp',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain',
  ];

  static Future<PickedBusinessFile?> pickBusinessFile() async {
    try {
      // THIS IS THE FIX: Using fp.FilePicker and fp.FileType
      final result = await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'],
        withData: true, // CRITICAL FOR WEB: Loads file directly into memory as bytes
      );

      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes == null) {
        throw PlatformException(
          code: 'INVALID_FILE_RESULT',
          message: 'The selected file could not be read into memory.',
        );
      }

      final rawName = file.name.trim();
      final name = rawName.isEmpty ? 'attachment' : rawName;
      final sizeBytes = file.size;

      return PickedBusinessFile(
        name: name,
        mimeType: _getMimeTypeFromExtension(file.extension),
        sizeBytes: sizeBytes,
        bytes: bytes,
      );
    } catch (e) {
      if (e is PlatformException) rethrow;
      throw PlatformException(
        code: 'FILE_PICKER_ERROR',
        message: 'Failed to pick file: $e',
      );
    }
  }

  static String _getMimeTypeFromExtension(String? extension) {
    final ext = extension?.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }
}