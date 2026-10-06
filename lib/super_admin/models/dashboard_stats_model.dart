import 'dart:convert';

class DashboardStatsModel {
  // ==============================
  // Companies
  // ==============================

  final int totalCompanies;
  final int activeCompanies;
  final int suspendedCompanies;
  final int inactiveCompanies;

  // ==============================
  // Company Admins
  // ==============================

  final int totalCompanyAdmins;
  final int activeCompanyAdmins;

  // ==============================
  // Plans
  // ==============================

  final int freePlanCompanies;
  final int starterPlanCompanies;
  final int professionalPlanCompanies;
  final int enterprisePlanCompanies;

  // ==============================
  // Revenue
  // ==============================

  final double monthlyRevenue;
  final double yearlyRevenue;

  // ==============================
  // Subscriptions
  // ==============================

  final int expiringSubscriptions;
  final int expiredSubscriptions;

  // ==============================
  // Growth
  // ==============================

  final int companiesCreatedToday;
  final int companiesCreatedThisWeek;
  final int companiesCreatedThisMonth;
  final int companiesCreatedThisYear;

  // ==============================
  // Storage
  // ==============================

  final double totalAllocatedStorageGB;
  final double totalUsedStorageGB;

  // ==============================
  // Platform Health
  // ==============================

  final int totalLoginsToday;
  final int activeSessions;
  final int failedLoginsToday;

  // ==============================
  // Metadata
  // ==============================

  final DateTime lastUpdated;

  const DashboardStatsModel({
    this.totalCompanies = 0,
    this.activeCompanies = 0,
    this.suspendedCompanies = 0,
    this.inactiveCompanies = 0,

    this.totalCompanyAdmins = 0,
    this.activeCompanyAdmins = 0,

    this.freePlanCompanies = 0,
    this.starterPlanCompanies = 0,
    this.professionalPlanCompanies = 0,
    this.enterprisePlanCompanies = 0,

    this.monthlyRevenue = 0,
    this.yearlyRevenue = 0,

    this.expiringSubscriptions = 0,
    this.expiredSubscriptions = 0,

    this.companiesCreatedToday = 0,
    this.companiesCreatedThisWeek = 0,
    this.companiesCreatedThisMonth = 0,
    this.companiesCreatedThisYear = 0,

    this.totalAllocatedStorageGB = 0,
    this.totalUsedStorageGB = 0,

    this.totalLoginsToday = 0,
    this.activeSessions = 0,
    this.failedLoginsToday = 0,

    required this.lastUpdated,
  });

  DashboardStatsModel copyWith({
    int? totalCompanies,
    int? activeCompanies,
    int? suspendedCompanies,
    int? inactiveCompanies,
    int? totalCompanyAdmins,
    int? activeCompanyAdmins,
    int? freePlanCompanies,
    int? starterPlanCompanies,
    int? professionalPlanCompanies,
    int? enterprisePlanCompanies,
    double? monthlyRevenue,
    double? yearlyRevenue,
    int? expiringSubscriptions,
    int? expiredSubscriptions,
    int? companiesCreatedToday,
    int? companiesCreatedThisWeek,
    int? companiesCreatedThisMonth,
    int? companiesCreatedThisYear,
    double? totalAllocatedStorageGB,
    double? totalUsedStorageGB,
    int? totalLoginsToday,
    int? activeSessions,
    int? failedLoginsToday,
    DateTime? lastUpdated,
  }) {
    return DashboardStatsModel(
      totalCompanies: totalCompanies ?? this.totalCompanies,
      activeCompanies: activeCompanies ?? this.activeCompanies,
      suspendedCompanies:
          suspendedCompanies ?? this.suspendedCompanies,
      inactiveCompanies:
          inactiveCompanies ?? this.inactiveCompanies,
      totalCompanyAdmins:
          totalCompanyAdmins ?? this.totalCompanyAdmins,
      activeCompanyAdmins:
          activeCompanyAdmins ?? this.activeCompanyAdmins,
      freePlanCompanies:
          freePlanCompanies ?? this.freePlanCompanies,
      starterPlanCompanies:
          starterPlanCompanies ?? this.starterPlanCompanies,
      professionalPlanCompanies:
          professionalPlanCompanies ??
              this.professionalPlanCompanies,
      enterprisePlanCompanies:
          enterprisePlanCompanies ??
              this.enterprisePlanCompanies,
      monthlyRevenue:
          monthlyRevenue ?? this.monthlyRevenue,
      yearlyRevenue:
          yearlyRevenue ?? this.yearlyRevenue,
      expiringSubscriptions:
          expiringSubscriptions ??
              this.expiringSubscriptions,
      expiredSubscriptions:
          expiredSubscriptions ??
              this.expiredSubscriptions,
      companiesCreatedToday:
          companiesCreatedToday ??
              this.companiesCreatedToday,
      companiesCreatedThisWeek:
          companiesCreatedThisWeek ??
              this.companiesCreatedThisWeek,
      companiesCreatedThisMonth:
          companiesCreatedThisMonth ??
              this.companiesCreatedThisMonth,
      companiesCreatedThisYear:
          companiesCreatedThisYear ??
              this.companiesCreatedThisYear,
      totalAllocatedStorageGB:
          totalAllocatedStorageGB ??
              this.totalAllocatedStorageGB,
      totalUsedStorageGB:
          totalUsedStorageGB ??
              this.totalUsedStorageGB,
      totalLoginsToday:
          totalLoginsToday ??
              this.totalLoginsToday,
      activeSessions:
          activeSessions ??
              this.activeSessions,
      failedLoginsToday:
          failedLoginsToday ??
              this.failedLoginsToday,
      lastUpdated:
          lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalCompanies': totalCompanies,
      'activeCompanies': activeCompanies,
      'suspendedCompanies': suspendedCompanies,
      'inactiveCompanies': inactiveCompanies,

      'totalCompanyAdmins': totalCompanyAdmins,
      'activeCompanyAdmins': activeCompanyAdmins,

      'freePlanCompanies': freePlanCompanies,
      'starterPlanCompanies': starterPlanCompanies,
      'professionalPlanCompanies': professionalPlanCompanies,
      'enterprisePlanCompanies': enterprisePlanCompanies,

      'monthlyRevenue': monthlyRevenue,
      'yearlyRevenue': yearlyRevenue,

      'expiringSubscriptions': expiringSubscriptions,
      'expiredSubscriptions': expiredSubscriptions,

      'companiesCreatedToday': companiesCreatedToday,
      'companiesCreatedThisWeek': companiesCreatedThisWeek,
      'companiesCreatedThisMonth': companiesCreatedThisMonth,
      'companiesCreatedThisYear': companiesCreatedThisYear,

      'totalAllocatedStorageGB': totalAllocatedStorageGB,
      'totalUsedStorageGB': totalUsedStorageGB,

      'totalLoginsToday': totalLoginsToday,
      'activeSessions': activeSessions,
      'failedLoginsToday': failedLoginsToday,

      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory DashboardStatsModel.fromMap(Map<String, dynamic> map) {
    return DashboardStatsModel(
      totalCompanies: map['totalCompanies'] ?? 0,
      activeCompanies: map['activeCompanies'] ?? 0,
      suspendedCompanies: map['suspendedCompanies'] ?? 0,
      inactiveCompanies: map['inactiveCompanies'] ?? 0,

      totalCompanyAdmins: map['totalCompanyAdmins'] ?? 0,
      activeCompanyAdmins: map['activeCompanyAdmins'] ?? 0,

      freePlanCompanies: map['freePlanCompanies'] ?? 0,
      starterPlanCompanies: map['starterPlanCompanies'] ?? 0,
      professionalPlanCompanies:
          map['professionalPlanCompanies'] ?? 0,
      enterprisePlanCompanies:
          map['enterprisePlanCompanies'] ?? 0,

      monthlyRevenue:
          (map['monthlyRevenue'] ?? 0).toDouble(),
      yearlyRevenue:
          (map['yearlyRevenue'] ?? 0).toDouble(),

      expiringSubscriptions:
          map['expiringSubscriptions'] ?? 0,
      expiredSubscriptions:
          map['expiredSubscriptions'] ?? 0,

      companiesCreatedToday:
          map['companiesCreatedToday'] ?? 0,
      companiesCreatedThisWeek:
          map['companiesCreatedThisWeek'] ?? 0,
      companiesCreatedThisMonth:
          map['companiesCreatedThisMonth'] ?? 0,
      companiesCreatedThisYear:
          map['companiesCreatedThisYear'] ?? 0,

      totalAllocatedStorageGB:
          (map['totalAllocatedStorageGB'] ?? 0)
              .toDouble(),
      totalUsedStorageGB:
          (map['totalUsedStorageGB'] ?? 0)
              .toDouble(),

      totalLoginsToday:
          map['totalLoginsToday'] ?? 0,
      activeSessions:
          map['activeSessions'] ?? 0,
      failedLoginsToday:
          map['failedLoginsToday'] ?? 0,

      lastUpdated: DateTime.tryParse(
              map['lastUpdated'] ?? '') ??
          DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory DashboardStatsModel.fromJson(String source) =>
      DashboardStatsModel.fromMap(jsonDecode(source));
}