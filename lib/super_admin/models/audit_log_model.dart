import 'dart:convert';

enum AuditAction {
  companyCreated,
  companyUpdated,
  companyDeleted,
  companyActivated,
  companySuspended,
  planAssigned,
  planChanged,
  subscriptionRenewed,
  companyAdminCreated,
  companyAdminUpdated,
  companyAdminDeleted,
  passwordReset,
  login,
  logout,
}

class AuditLogModel {
  final String id;

  /// Action
  final AuditAction action;

  /// Company
  final String companyId;
  final String companyName;

  /// User performing action
  final String performedByUid;
  final String performedByName;
  final String performedByEmail;

  /// Optional target user
  final String? targetUserUid;
  final String? targetUserEmail;

  /// Description
  final String description;

  /// Additional metadata
  final Map<String, dynamic> metadata;

  /// Platform information
  final String ipAddress;
  final String device;
  final String platform;

  /// Timestamp
  final DateTime createdAt;

  const AuditLogModel({
    required this.id,
    required this.action,

    required this.companyId,
    required this.companyName,

    required this.performedByUid,
    required this.performedByName,
    required this.performedByEmail,

    this.targetUserUid,
    this.targetUserEmail,

    required this.description,

    this.metadata = const {},

    this.ipAddress = '',
    this.device = '',
    this.platform = '',

    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,

      'action': action.name,

      'companyId': companyId,
      'companyName': companyName,

      'performedByUid': performedByUid,
      'performedByName': performedByName,
      'performedByEmail': performedByEmail,

      'targetUserUid': targetUserUid,
      'targetUserEmail': targetUserEmail,

      'description': description,

      'metadata': metadata,

      'ipAddress': ipAddress,
      'device': device,
      'platform': platform,

      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AuditLogModel.fromMap(Map<String, dynamic> map) {
    return AuditLogModel(
      id: map['id'] ?? '',

      action: AuditAction.values.firstWhere(
        (e) => e.name == map['action'],
        orElse: () => AuditAction.companyCreated,
      ),

      companyId: map['companyId'] ?? '',
      companyName: map['companyName'] ?? '',

      performedByUid: map['performedByUid'] ?? '',
      performedByName: map['performedByName'] ?? '',
      performedByEmail: map['performedByEmail'] ?? '',

      targetUserUid: map['targetUserUid'],
      targetUserEmail: map['targetUserEmail'],

      description: map['description'] ?? '',

      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),

      ipAddress: map['ipAddress'] ?? '',
      device: map['device'] ?? '',
      platform: map['platform'] ?? '',

      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ??
          DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AuditLogModel.fromJson(String source) =>
      AuditLogModel.fromMap(jsonDecode(source));

  AuditLogModel copyWith({
    String? id,
    AuditAction? action,
    String? companyId,
    String? companyName,
    String? performedByUid,
    String? performedByName,
    String? performedByEmail,
    String? targetUserUid,
    String? targetUserEmail,
    String? description,
    Map<String, dynamic>? metadata,
    String? ipAddress,
    String? device,
    String? platform,
    DateTime? createdAt,
  }) {
    return AuditLogModel(
      id: id ?? this.id,
      action: action ?? this.action,
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      performedByUid: performedByUid ?? this.performedByUid,
      performedByName: performedByName ?? this.performedByName,
      performedByEmail: performedByEmail ?? this.performedByEmail,
      targetUserUid: targetUserUid ?? this.targetUserUid,
      targetUserEmail: targetUserEmail ?? this.targetUserEmail,
      description: description ?? this.description,
      metadata: metadata ?? this.metadata,
      ipAddress: ipAddress ?? this.ipAddress,
      device: device ?? this.device,
      platform: platform ?? this.platform,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'AuditLogModel(action: ${action.name}, company: $companyName)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditLogModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}