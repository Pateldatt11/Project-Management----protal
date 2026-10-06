import '../../core/constants/app_enums.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/json_value.dart';

enum EmploymentActionType {
  promotion,
  demotion,
  roleChange,
  departmentTransfer,
  gradeChange,
  salaryBandChange,
  probationExtension,
  performanceImprovementPlan,
  contractRenewal,
  exitRecommendation,
}

enum EmploymentActionStatus {
  draft,
  recommended,
  underReview,
  scheduled,
  approved,
  rejected,
  cancelled,
  error,
}

extension EmploymentActionTypeX on EmploymentActionType {
  String get value => name;

  String get label => switch (this) {
        EmploymentActionType.promotion => 'Promotion',
        EmploymentActionType.demotion => 'Demotion',
        EmploymentActionType.roleChange => 'Role change',
        EmploymentActionType.departmentTransfer => 'Department transfer',
        EmploymentActionType.gradeChange => 'Grade change',
        EmploymentActionType.salaryBandChange => 'Salary-band change',
        EmploymentActionType.probationExtension => 'Probation extension',
        EmploymentActionType.performanceImprovementPlan => 'Performance improvement plan',
        EmploymentActionType.contractRenewal => 'Contract renewal',
        EmploymentActionType.exitRecommendation => 'Exit recommendation',
      };

  static EmploymentActionType fromValue(String? value) {
    final normalized = (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    return EmploymentActionType.values.firstWhere(
      (item) => item.name.toLowerCase() == normalized,
      orElse: () => switch (normalized) {
        'transfer' || 'departmenttransfer' => EmploymentActionType.departmentTransfer,
        'pip' || 'improvementplan' => EmploymentActionType.performanceImprovementPlan,
        'salarychange' || 'salarybandchange' => EmploymentActionType.salaryBandChange,
        'renewal' => EmploymentActionType.contractRenewal,
        'exit' => EmploymentActionType.exitRecommendation,
        _ => EmploymentActionType.roleChange,
      },
    );
  }
}

extension EmploymentActionStatusX on EmploymentActionStatus {
  String get value => name;

  String get label => switch (this) {
        EmploymentActionStatus.draft => 'Draft',
        EmploymentActionStatus.recommended => 'Recommended',
        EmploymentActionStatus.underReview => 'Under review',
        EmploymentActionStatus.scheduled => 'Approved • scheduled',
        EmploymentActionStatus.approved => 'Approved • effective',
        EmploymentActionStatus.rejected => 'Rejected',
        EmploymentActionStatus.cancelled => 'Cancelled',
        EmploymentActionStatus.error => 'Processing error',
      };

  static EmploymentActionStatus fromValue(String? value) {
    final normalized = (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');
    return EmploymentActionStatus.values.firstWhere(
      (item) => item.name.toLowerCase() == normalized,
      orElse: () => switch (normalized) {
        'review' || 'inreview' => EmploymentActionStatus.underReview,
        'recommendation' => EmploymentActionStatus.recommended,
        _ => EmploymentActionStatus.draft,
      },
    );
  }
}

class EmploymentAction {
  const EmploymentAction({
    required this.actionId,
    required this.companyId,
    required this.employeeId,
    required this.employeeName,
    required this.actionType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.currentRole,
    this.proposedRole,
    this.currentDepartment,
    this.proposedDepartment,
    this.currentJobTitle,
    this.proposedJobTitle,
    this.currentGrade,
    this.proposedGrade,
    this.currentSalaryBand,
    this.proposedSalaryBand,
    this.currentReportingManagerId,
    this.proposedReportingManagerId,
    this.effectiveDate,
    this.reason = '',
    this.managerRecommendation = '',
    this.hrComments = '',
    this.recommendedBy,
    this.recommendedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectedAt,
    this.appraisalPeriod,
    this.appraisalScore,
  });

  final String actionId;
  final String companyId;
  final String employeeId;
  final String employeeName;
  final EmploymentActionType actionType;
  final EmploymentActionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final UserRole? currentRole;
  final UserRole? proposedRole;
  final String? currentDepartment;
  final String? proposedDepartment;
  final String? currentJobTitle;
  final String? proposedJobTitle;
  final String? currentGrade;
  final String? proposedGrade;
  final String? currentSalaryBand;
  final String? proposedSalaryBand;
  final String? currentReportingManagerId;
  final String? proposedReportingManagerId;
  final DateTime? effectiveDate;
  final String reason;
  final String managerRecommendation;
  final String hrComments;
  final String? recommendedBy;
  final DateTime? recommendedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectedBy;
  final DateTime? rejectedAt;
  final String? appraisalPeriod;
  final int? appraisalScore;

  bool get isTerminal =>
      status == EmploymentActionStatus.scheduled ||
      status == EmploymentActionStatus.approved ||
      status == EmploymentActionStatus.rejected ||
      status == EmploymentActionStatus.cancelled ||
      status == EmploymentActionStatus.error;
  bool get requiresApproval => !isTerminal;

  EmploymentAction copyWith({
    EmploymentActionStatus? status,
    UserRole? proposedRole,
    String? proposedDepartment,
    String? proposedJobTitle,
    String? proposedGrade,
    String? proposedSalaryBand,
    String? proposedReportingManagerId,
    DateTime? effectiveDate,
    String? reason,
    String? managerRecommendation,
    String? hrComments,
    String? recommendedBy,
    DateTime? recommendedAt,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? approvedBy,
    DateTime? approvedAt,
    String? rejectedBy,
    DateTime? rejectedAt,
    DateTime? updatedAt,
  }) {
    return EmploymentAction(
      actionId: actionId,
      companyId: companyId,
      employeeId: employeeId,
      employeeName: employeeName,
      actionType: actionType,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      currentRole: currentRole,
      proposedRole: proposedRole ?? this.proposedRole,
      currentDepartment: currentDepartment,
      proposedDepartment: proposedDepartment ?? this.proposedDepartment,
      currentJobTitle: currentJobTitle,
      proposedJobTitle: proposedJobTitle ?? this.proposedJobTitle,
      currentGrade: currentGrade,
      proposedGrade: proposedGrade ?? this.proposedGrade,
      currentSalaryBand: currentSalaryBand,
      proposedSalaryBand: proposedSalaryBand ?? this.proposedSalaryBand,
      currentReportingManagerId: currentReportingManagerId,
      proposedReportingManagerId: proposedReportingManagerId ?? this.proposedReportingManagerId,
      effectiveDate: effectiveDate ?? this.effectiveDate,
      reason: reason ?? this.reason,
      managerRecommendation: managerRecommendation ?? this.managerRecommendation,
      hrComments: hrComments ?? this.hrComments,
      recommendedBy: recommendedBy ?? this.recommendedBy,
      recommendedAt: recommendedAt ?? this.recommendedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      appraisalPeriod: appraisalPeriod,
      appraisalScore: appraisalScore,
    );
  }

  factory EmploymentAction.fromJson(Map<String, dynamic> json) {
    final currentRoleValue = JsonValue.optionalString(json['currentRole']);
    final proposedRoleValue = JsonValue.optionalString(json['proposedRole']);
    return EmploymentAction(
      actionId: JsonValue.string(json['actionId'] ?? json['id']),
      companyId: JsonValue.string(json['companyId']),
      employeeId: JsonValue.string(json['employeeId'] ?? json['memberId'] ?? json['uid']),
      employeeName: JsonValue.string(json['employeeName'] ?? json['memberName'], fallback: 'Employee'),
      actionType: EmploymentActionTypeX.fromValue(JsonValue.string(json['actionType'] ?? json['type'])),
      status: EmploymentActionStatusX.fromValue(JsonValue.string(json['status'])),
      createdAt: DateText.parse(json['createdAt']) ?? DateTime.now(),
      updatedAt: DateText.parse(json['updatedAt']) ?? DateText.parse(json['createdAt']) ?? DateTime.now(),
      currentRole: currentRoleValue == null ? null : UserRoleX.fromValue(currentRoleValue),
      proposedRole: proposedRoleValue == null ? null : UserRoleX.fromValue(proposedRoleValue),
      currentDepartment: JsonValue.optionalString(json['currentDepartment']),
      proposedDepartment: JsonValue.optionalString(json['proposedDepartment']),
      currentJobTitle: JsonValue.optionalString(json['currentJobTitle']),
      proposedJobTitle: JsonValue.optionalString(json['proposedJobTitle']),
      currentGrade: JsonValue.optionalString(json['currentGrade']),
      proposedGrade: JsonValue.optionalString(json['proposedGrade']),
      currentSalaryBand: JsonValue.optionalString(json['currentSalaryBand']),
      proposedSalaryBand: JsonValue.optionalString(json['proposedSalaryBand']),
      currentReportingManagerId: JsonValue.optionalString(json['currentReportingManagerId']),
      proposedReportingManagerId: JsonValue.optionalString(json['proposedReportingManagerId']),
      effectiveDate: DateText.parse(json['effectiveDate']),
      reason: JsonValue.string(json['reason']),
      managerRecommendation: JsonValue.string(json['managerRecommendation']),
      hrComments: JsonValue.string(json['hrComments']),
      recommendedBy: JsonValue.optionalString(json['recommendedBy']),
      recommendedAt: DateText.parse(json['recommendedAt']),
      reviewedBy: JsonValue.optionalString(json['reviewedBy']),
      reviewedAt: DateText.parse(json['reviewedAt']),
      approvedBy: JsonValue.optionalString(json['approvedBy']),
      approvedAt: DateText.parse(json['approvedAt']),
      rejectedBy: JsonValue.optionalString(json['rejectedBy']),
      rejectedAt: DateText.parse(json['rejectedAt']),
      appraisalPeriod: JsonValue.optionalString(json['appraisalPeriod']),
      appraisalScore: json['appraisalScore'] == null ? null : JsonValue.integer(json['appraisalScore']).clamp(0, 100).toInt(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'actionId': actionId,
        'companyId': companyId,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'actionType': actionType.value,
        'status': status.value,
        'currentRole': currentRole?.value,
        'proposedRole': proposedRole?.value,
        'currentDepartment': currentDepartment,
        'proposedDepartment': proposedDepartment,
        'currentJobTitle': currentJobTitle,
        'proposedJobTitle': proposedJobTitle,
        'currentGrade': currentGrade,
        'proposedGrade': proposedGrade,
        'currentSalaryBand': currentSalaryBand,
        'proposedSalaryBand': proposedSalaryBand,
        'currentReportingManagerId': currentReportingManagerId,
        'proposedReportingManagerId': proposedReportingManagerId,
        'effectiveDate': effectiveDate?.toIso8601String(),
        'reason': reason,
        'managerRecommendation': managerRecommendation,
        'hrComments': hrComments,
        'recommendedBy': recommendedBy,
        'recommendedAt': recommendedAt?.toIso8601String(),
        'reviewedBy': reviewedBy,
        'reviewedAt': reviewedAt?.toIso8601String(),
        'approvedBy': approvedBy,
        'approvedAt': approvedAt?.toIso8601String(),
        'rejectedBy': rejectedBy,
        'rejectedAt': rejectedAt?.toIso8601String(),
        'appraisalPeriod': appraisalPeriod,
        'appraisalScore': appraisalScore,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
