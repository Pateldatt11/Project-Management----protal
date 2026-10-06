import 'dart:convert';

class SubscriptionModel {
  final String id;

  /// Company
  final String companyId;

  /// Plan
  final String planId;
  final String planName;

  /// Limits
  final int maxUsers;
  final int maxProjects;
  final int storageLimitGB;

  /// Billing
  final double price;
  final String billingCycle; // monthly, yearly, lifetime

  /// Status
  final bool isActive;
  final bool autoRenew;

  /// Dates
  final DateTime startDate;
  final DateTime expiryDate;

  /// Metadata
  final DateTime createdAt;
  final DateTime updatedAt;

  const SubscriptionModel({
    required this.id,
    required this.companyId,
    required this.planId,
    required this.planName,
    required this.maxUsers,
    required this.maxProjects,
    required this.storageLimitGB,
    required this.price,
    required this.billingCycle,
    this.isActive = true,
    this.autoRenew = true,
    required this.startDate,
    required this.expiryDate,
    required this.createdAt,
    required this.updatedAt,
  });

  SubscriptionModel copyWith({
    String? id,
    String? companyId,
    String? planId,
    String? planName,
    int? maxUsers,
    int? maxProjects,
    int? storageLimitGB,
    double? price,
    String? billingCycle,
    bool? isActive,
    bool? autoRenew,
    DateTime? startDate,
    DateTime? expiryDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SubscriptionModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      planId: planId ?? this.planId,
      planName: planName ?? this.planName,
      maxUsers: maxUsers ?? this.maxUsers,
      maxProjects: maxProjects ?? this.maxProjects,
      storageLimitGB: storageLimitGB ?? this.storageLimitGB,
      price: price ?? this.price,
      billingCycle: billingCycle ?? this.billingCycle,
      isActive: isActive ?? this.isActive,
      autoRenew: autoRenew ?? this.autoRenew,
      startDate: startDate ?? this.startDate,
      expiryDate: expiryDate ?? this.expiryDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'companyId': companyId,
      'planId': planId,
      'planName': planName,
      'maxUsers': maxUsers,
      'maxProjects': maxProjects,
      'storageLimitGB': storageLimitGB,
      'price': price,
      'billingCycle': billingCycle,
      'isActive': isActive,
      'autoRenew': autoRenew,
      'startDate': startDate.toIso8601String(),
      'expiryDate': expiryDate.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory SubscriptionModel.fromMap(Map<String, dynamic> map) {
    return SubscriptionModel(
      id: map['id'] ?? '',
      companyId: map['companyId'] ?? '',
      planId: map['planId'] ?? '',
      planName: map['planName'] ?? '',
      maxUsers: map['maxUsers'] ?? 0,
      maxProjects: map['maxProjects'] ?? 0,
      storageLimitGB: map['storageLimitGB'] ?? 0,
      price: (map['price'] ?? 0).toDouble(),
      billingCycle: map['billingCycle'] ?? 'monthly',
      isActive: map['isActive'] ?? true,
      autoRenew: map['autoRenew'] ?? true,
      startDate:
          DateTime.tryParse(map['startDate'] ?? '') ?? DateTime.now(),
      expiryDate:
          DateTime.tryParse(map['expiryDate'] ?? '') ??
              DateTime.now().add(const Duration(days: 30)),
      createdAt:
          DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory SubscriptionModel.fromJson(String source) =>
      SubscriptionModel.fromMap(jsonDecode(source));

  bool get isExpired => expiryDate.isBefore(DateTime.now());

  int get daysRemaining =>
      expiryDate.difference(DateTime.now()).inDays;

  @override
  String toString() {
    return 'SubscriptionModel(companyId: $companyId, plan: $planName)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}