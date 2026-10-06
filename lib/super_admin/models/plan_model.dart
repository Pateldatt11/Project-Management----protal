import 'dart:convert';

class PlanModel {
  final String id;

  /// Plan Information
  final String name;
  final String description;

  /// Pricing
  final double monthlyPrice;
  final double yearlyPrice;
  final String currency;

  /// Limits
  final int maxUsers;
  final int maxProjects;
  final int maxStorageGB;

  /// Feature Flags
  final bool enableProjects;
  final bool enableTasks;
  final bool enableTeams;
  final bool enableChat;
  final bool enableAnalytics;
  final bool enableTimeline;
  final bool enableReports;
  final bool enableNotifications;
  final bool enableAttendance;
  final bool enableLeaveManagement;
  final bool enablePayroll;
  final bool enableRecruitment;
  final bool enableAppraisal;
  final bool enableHelpDesk;
  final bool enableKnowledgeBase;
  final bool enableAssets;
  final bool enableCalendar;
  final bool enableMeetings;
  final bool enableInvoices;
  final bool enableCustomBranding;
  final bool enableApiAccess;
  final bool enableSSO;

  /// Status
  final bool isActive;
  final bool isPopular;

  /// Metadata
  final DateTime createdAt;
  final DateTime updatedAt;

  const PlanModel({
    required this.id,
    required this.name,
    required this.description,

    required this.monthlyPrice,
    required this.yearlyPrice,
    this.currency = 'INR',

    required this.maxUsers,
    required this.maxProjects,
    required this.maxStorageGB,

    this.enableProjects = true,
    this.enableTasks = true,
    this.enableTeams = true,
    this.enableChat = true,
    this.enableAnalytics = true,
    this.enableTimeline = true,
    this.enableReports = true,
    this.enableNotifications = true,
    this.enableAttendance = false,
    this.enableLeaveManagement = false,
    this.enablePayroll = false,
    this.enableRecruitment = false,
    this.enableAppraisal = false,
    this.enableHelpDesk = false,
    this.enableKnowledgeBase = false,
    this.enableAssets = false,
    this.enableCalendar = true,
    this.enableMeetings = true,
    this.enableInvoices = false,
    this.enableCustomBranding = false,
    this.enableApiAccess = false,
    this.enableSSO = false,

    this.isActive = true,
    this.isPopular = false,

    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,

      'monthlyPrice': monthlyPrice,
      'yearlyPrice': yearlyPrice,
      'currency': currency,

      'maxUsers': maxUsers,
      'maxProjects': maxProjects,
      'maxStorageGB': maxStorageGB,

      'features': {
        'projects': enableProjects,
        'tasks': enableTasks,
        'teams': enableTeams,
        'chat': enableChat,
        'analytics': enableAnalytics,
        'timeline': enableTimeline,
        'reports': enableReports,
        'notifications': enableNotifications,
        'attendance': enableAttendance,
        'leaveManagement': enableLeaveManagement,
        'payroll': enablePayroll,
        'recruitment': enableRecruitment,
        'appraisal': enableAppraisal,
        'helpDesk': enableHelpDesk,
        'knowledgeBase': enableKnowledgeBase,
        'assets': enableAssets,
        'calendar': enableCalendar,
        'meetings': enableMeetings,
        'invoices': enableInvoices,
        'customBranding': enableCustomBranding,
        'apiAccess': enableApiAccess,
        'sso': enableSSO,
      },

      'isActive': isActive,
      'isPopular': isPopular,

      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PlanModel.fromMap(Map<String, dynamic> map) {
    final features = Map<String, dynamic>.from(map['features'] ?? {});

    return PlanModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',

      monthlyPrice: (map['monthlyPrice'] ?? 0).toDouble(),
      yearlyPrice: (map['yearlyPrice'] ?? 0).toDouble(),
      currency: map['currency'] ?? 'INR',

      maxUsers: map['maxUsers'] ?? 0,
      maxProjects: map['maxProjects'] ?? 0,
      maxStorageGB: map['maxStorageGB'] ?? 0,

      enableProjects: features['projects'] ?? true,
      enableTasks: features['tasks'] ?? true,
      enableTeams: features['teams'] ?? true,
      enableChat: features['chat'] ?? true,
      enableAnalytics: features['analytics'] ?? true,
      enableTimeline: features['timeline'] ?? true,
      enableReports: features['reports'] ?? true,
      enableNotifications: features['notifications'] ?? true,
      enableAttendance: features['attendance'] ?? false,
      enableLeaveManagement: features['leaveManagement'] ?? false,
      enablePayroll: features['payroll'] ?? false,
      enableRecruitment: features['recruitment'] ?? false,
      enableAppraisal: features['appraisal'] ?? false,
      enableHelpDesk: features['helpDesk'] ?? false,
      enableKnowledgeBase: features['knowledgeBase'] ?? false,
      enableAssets: features['assets'] ?? false,
      enableCalendar: features['calendar'] ?? true,
      enableMeetings: features['meetings'] ?? true,
      enableInvoices: features['invoices'] ?? false,
      enableCustomBranding: features['customBranding'] ?? false,
      enableApiAccess: features['apiAccess'] ?? false,
      enableSSO: features['sso'] ?? false,

      isActive: map['isActive'] ?? true,
      isPopular: map['isPopular'] ?? false,

      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory PlanModel.fromJson(String source) =>
      PlanModel.fromMap(jsonDecode(source));

  @override
  String toString() => 'PlanModel(id: $id, name: $name)';
}