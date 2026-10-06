import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/json_value.dart';

class FileAttachment {
  const FileAttachment({
    required this.attachmentId,
    required this.taskId,
    required this.projectId,
    required this.uploadedBy,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.publicId,
    required this.createdAt,
    this.secureUrl = '',
  });

  final String attachmentId;
  final String taskId;
  final String projectId;
  final String uploadedBy;
  final String fileName;
  final String fileType;
  final int fileSize; // size in bytes
  final String publicId; // Cloudinary public_id / storage path
  final DateTime createdAt;
  final String secureUrl; // Cloudinary secure_url

  /// Returns readable file size string (e.g. "450 KB", "2.1 MB")
  String get formattedSize {
    if (fileSize <= 0) return '0 B';
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(0)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Extracts the file extension (e.g. "png", "pdf", "docx")
  String get fileExtension {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < fileName.length - 1) {
      return fileName.substring(dotIndex + 1).toLowerCase();
    }
    return '';
  }

  /// True if the attachment is an image
  bool get isImage =>
      fileType.startsWith('image/') ||
      ['jpg', 'jpeg', 'png', 'webp', 'gif', 'svg'].contains(fileExtension);

  /// True if a valid Cloudinary/external URL exists
  bool get hasValidUrl => secureUrl.trim().isNotEmpty;

  factory FileAttachment.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate = DateTime.now();
    final rawCreated = json['createdAt'];
    if (rawCreated is Timestamp) {
      parsedDate = rawCreated.toDate();
    } else if (rawCreated is DateTime) {
      parsedDate = rawCreated;
    } else if (rawCreated is String) {
      parsedDate = DateText.parse(rawCreated) ?? DateTime.now();
    }

    return FileAttachment(
      attachmentId: JsonValue.string(json['attachmentId'] ?? json['id']),
      taskId: JsonValue.string(json['taskId']),
      projectId: JsonValue.string(json['projectId']),
      uploadedBy: JsonValue.string(json['uploadedBy'] ?? json['authorId']),
      fileName: JsonValue.string(json['fileName'] ?? json['name'], fallback: 'Attachment'),
      fileType: JsonValue.string(json['fileType'] ?? json['contentType'], fallback: 'application/octet-stream'),
      fileSize: JsonValue.integer(json['fileSize'] ?? json['size'], fallback: 0),
      publicId: JsonValue.string(
        json['publicId'] ?? json['public_id'] ?? json['storagePath'] ?? json['path'] ?? json['url'],
      ),
      secureUrl: JsonValue.string(
        json['secureUrl'] ?? json['secure_url'] ?? json['downloadUrl'] ?? json['url'],
      ),
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'attachmentId': attachmentId,
        'taskId': taskId,
        'projectId': projectId,
        'uploadedBy': uploadedBy,
        'fileName': fileName,
        'fileType': fileType,
        'fileSize': fileSize,
        'publicId': publicId,
        'secureUrl': secureUrl,
        'createdAt': createdAt.toIso8601String(),
      };

  FileAttachment copyWith({
    String? attachmentId,
    String? taskId,
    String? projectId,
    String? uploadedBy,
    String? fileName,
    String? fileType,
    int? fileSize,
    String? publicId,
    DateTime? createdAt,
    String? secureUrl,
  }) {
    return FileAttachment(
      attachmentId: attachmentId ?? this.attachmentId,
      taskId: taskId ?? this.taskId,
      projectId: projectId ?? this.projectId,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
      fileSize: fileSize ?? this.fileSize,
      publicId: publicId ?? this.publicId,
      createdAt: createdAt ?? this.createdAt,
      secureUrl: secureUrl ?? this.secureUrl,
    );
  }
}