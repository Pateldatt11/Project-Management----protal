import '../../core/constants/app_enums.dart';
import '../../core/utils/json_value.dart';

class Member {
  const Member({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.status,
    this.teamIds = const [],
    this.projectIds = const [],
    this.capacityHoursPerWeek = 40,
    this.available = true,
    this.isOnline = false,
    this.lastSeenAt,
    this.department,
    this.jobTitle,
    this.location = 'Remote',
    this.industryDiscipline = 'General',
    this.grade = '',
    this.employmentLevel = '',
    this.salaryBand = '',
    this.reportingManagerId,
    this.appraisalScore = 0,
    this.previousAppraisalScore = 0,
    this.appraisalNotes = '',
    this.appraisalStatus = 'notReviewed',
    this.appraisalTemplateId = '',
    this.appraisalCompetencyScores = const <String, int>{},
    this.appraisalSelfReview = '',
    this.appraisalManagerReview = '',
    this.appraisalPeerReview = '',
    this.appraisalPeriod = '',
    this.appraisalUpdatedAt,
    this.appraisalUpdatedBy,
    this.lastCareerActionId,
    this.lastCareerActionAt,
  });

  final String uid;
  final String displayName;
  final String email;
  final UserRole role;
  final String status;
  final List<String> teamIds;
  final List<String> projectIds;
  final num capacityHoursPerWeek;
  final bool available;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final String? department;
  final String? jobTitle;
  final String location;
  final String industryDiscipline;
  final String grade;
  final String employmentLevel;
  final String salaryBand;
  final String? reportingManagerId;
  final int appraisalScore;
  final int previousAppraisalScore;
  final String appraisalNotes;
  final String appraisalStatus;
  final String appraisalTemplateId;
  final Map<String, int> appraisalCompetencyScores;
  final String appraisalSelfReview;
  final String appraisalManagerReview;
  final String appraisalPeerReview;
  final String appraisalPeriod;
  final DateTime? appraisalUpdatedAt;
  final String? appraisalUpdatedBy;
  final String? lastCareerActionId;
  final DateTime? lastCareerActionAt;

  String get effectiveDepartment {
    final clean = (department ?? '').trim();
    return clean.isEmpty ? role.department : clean;
  }

  String get effectiveJobTitle {
    final clean = (jobTitle ?? '').trim();
    return clean.isEmpty ? role.label : clean;
  }

  String get effectiveIndustryDiscipline {
    final clean = industryDiscipline.trim();
    return clean.isEmpty || clean.toLowerCase() == 'general' ? effectiveDepartment : clean;
  }
  String get presenceLabel => isOnline ? 'Online' : 'Offline';
  bool get isOffline => !isOnline;

  Member copyWith({
    String? displayName,
    String? email,
    UserRole? role,
    String? status,
    List<String>? teamIds,
    List<String>? projectIds,
    num? capacityHoursPerWeek,
    bool? available,
    bool? isOnline,
    DateTime? lastSeenAt,
    bool clearLastSeenAt = false,
    String? department,
    String? jobTitle,
    String? location,
    String? industryDiscipline,
    String? grade,
    String? employmentLevel,
    String? salaryBand,
    String? reportingManagerId,
    bool clearReportingManagerId = false,
    int? appraisalScore,
    int? previousAppraisalScore,
    String? appraisalNotes,
    String? appraisalStatus,
    String? appraisalTemplateId,
    Map<String, int>? appraisalCompetencyScores,
    String? appraisalSelfReview,
    String? appraisalManagerReview,
    String? appraisalPeerReview,
    String? appraisalPeriod,
    DateTime? appraisalUpdatedAt,
    String? appraisalUpdatedBy,
    String? lastCareerActionId,
    DateTime? lastCareerActionAt,
  }) =>
      Member(
        uid: uid,
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        role: role ?? this.role,
        status: status ?? this.status,
        teamIds: teamIds ?? this.teamIds,
        projectIds: projectIds ?? this.projectIds,
        capacityHoursPerWeek: capacityHoursPerWeek ?? this.capacityHoursPerWeek,
        available: available ?? this.available,
        isOnline: isOnline ?? this.isOnline,
        lastSeenAt: clearLastSeenAt ? null : lastSeenAt ?? this.lastSeenAt,
        department: department ?? this.department,
        jobTitle: jobTitle ?? this.jobTitle,
        location: location ?? this.location,
        industryDiscipline: industryDiscipline ?? this.industryDiscipline,
        grade: grade ?? this.grade,
        employmentLevel: employmentLevel ?? this.employmentLevel,
        salaryBand: salaryBand ?? this.salaryBand,
        reportingManagerId: clearReportingManagerId ? null : reportingManagerId ?? this.reportingManagerId,
        appraisalScore: appraisalScore ?? this.appraisalScore,
        previousAppraisalScore: previousAppraisalScore ?? this.previousAppraisalScore,
        appraisalNotes: appraisalNotes ?? this.appraisalNotes,
        appraisalStatus: appraisalStatus ?? this.appraisalStatus,
        appraisalTemplateId: appraisalTemplateId ?? this.appraisalTemplateId,
        appraisalCompetencyScores: appraisalCompetencyScores ?? this.appraisalCompetencyScores,
        appraisalSelfReview: appraisalSelfReview ?? this.appraisalSelfReview,
        appraisalManagerReview: appraisalManagerReview ?? this.appraisalManagerReview,
        appraisalPeerReview: appraisalPeerReview ?? this.appraisalPeerReview,
        appraisalPeriod: appraisalPeriod ?? this.appraisalPeriod,
        appraisalUpdatedAt: appraisalUpdatedAt ?? this.appraisalUpdatedAt,
        appraisalUpdatedBy: appraisalUpdatedBy ?? this.appraisalUpdatedBy,
        lastCareerActionId: lastCareerActionId ?? this.lastCareerActionId,
        lastCareerActionAt: lastCareerActionAt ?? this.lastCareerActionAt,
      );

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        uid: JsonValue.string(json['uid'] ?? json['id']),
        displayName: JsonValue.string(json['displayName'] ?? json['name'], fallback: 'Employee'),
        email: JsonValue.string(json['email']),
        role: UserRoleX.fromValue(JsonValue.string(json['role'], fallback: UserRole.employee.value)),
        status: JsonValue.string(json['status'], fallback: 'active'),
        teamIds: JsonValue.stringList(json['teamIds'] ?? json['teams'] ?? json['taskForceIds']),
        projectIds: JsonValue.stringList(json['projectIds'] ?? json['projects'] ?? json['assignedProjectIds']),
        capacityHoursPerWeek: JsonValue.number(json['capacityHoursPerWeek'], fallback: 40),
        available: JsonValue.boolean(json['available'], fallback: true),
        isOnline: JsonValue.boolean(json['isOnline'] ?? json['online'], fallback: false),
        lastSeenAt: _dateFromJson(json['lastSeenAt']),
        department: JsonValue.optionalString(json['department']),
        jobTitle: JsonValue.optionalString(json['jobTitle'] ?? json['postName'] ?? json['roleTitle']),
        location: JsonValue.string(json['location'], fallback: 'Remote'),
        industryDiscipline: JsonValue.string(json['industryDiscipline'] ?? json['discipline'] ?? json['industry'], fallback: 'General'),
        grade: JsonValue.string(json['grade'] ?? json['employeeGrade']),
        employmentLevel: JsonValue.string(json['employmentLevel'] ?? json['level']),
        salaryBand: JsonValue.string(json['salaryBand'] ?? json['payBand']),
        reportingManagerId: JsonValue.optionalString(json['reportingManagerId'] ?? json['managerId']),
        appraisalScore: JsonValue.integer(json['appraisalScore'] ?? json['performanceScore'], fallback: 0).clamp(0, 100).toInt(),
        previousAppraisalScore: JsonValue.integer(json['previousAppraisalScore'], fallback: 0).clamp(0, 100).toInt(),
        appraisalNotes: JsonValue.string(json['appraisalNotes'] ?? json['performanceNotes']),
        appraisalStatus: JsonValue.string(json['appraisalStatus'], fallback: 'notReviewed'),
        appraisalTemplateId: JsonValue.string(json['appraisalTemplateId'] ?? json['competencyTemplateId']),
        appraisalCompetencyScores: _intMapFromJson(json['appraisalCompetencyScores'] ?? json['competencyScores']),
        appraisalSelfReview: JsonValue.string(json['appraisalSelfReview'] ?? json['selfReview']),
        appraisalManagerReview: JsonValue.string(json['appraisalManagerReview'] ?? json['managerReview']),
        appraisalPeerReview: JsonValue.string(json['appraisalPeerReview'] ?? json['peerReview']),
        appraisalPeriod: JsonValue.string(json['appraisalPeriod'] ?? json['reviewPeriod']),
        appraisalUpdatedAt: _dateFromJson(json['appraisalUpdatedAt']),
        appraisalUpdatedBy: JsonValue.optionalString(json['appraisalUpdatedBy']),
        lastCareerActionId: JsonValue.optionalString(json['lastCareerActionId']),
        lastCareerActionAt: _dateFromJson(json['lastCareerActionAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uid': uid,
        'displayName': displayName,
        'email': email,
        'role': role.value,
        'status': status,
        'teamIds': teamIds,
        'projectIds': projectIds,
        'capacityHoursPerWeek': capacityHoursPerWeek,
        'available': available,
        'isOnline': isOnline,
        'lastSeenAt': lastSeenAt?.toIso8601String(),
        'department': effectiveDepartment,
        'jobTitle': effectiveJobTitle,
        'location': location,
        'industryDiscipline': effectiveIndustryDiscipline,
        'grade': grade,
        'employmentLevel': employmentLevel,
        'salaryBand': salaryBand,
        'reportingManagerId': reportingManagerId,
        'appraisalScore': appraisalScore,
        'previousAppraisalScore': previousAppraisalScore,
        'appraisalNotes': appraisalNotes,
        'appraisalStatus': appraisalStatus,
        'appraisalTemplateId': appraisalTemplateId,
        'appraisalCompetencyScores': appraisalCompetencyScores,
        'appraisalSelfReview': appraisalSelfReview,
        'appraisalManagerReview': appraisalManagerReview,
        'appraisalPeerReview': appraisalPeerReview,
        'appraisalPeriod': appraisalPeriod,
        'appraisalUpdatedAt': appraisalUpdatedAt?.toIso8601String(),
        'appraisalUpdatedBy': appraisalUpdatedBy,
        'lastCareerActionId': lastCareerActionId,
        'lastCareerActionAt': lastCareerActionAt?.toIso8601String(),
      };

  static Map<String, int> _intMapFromJson(dynamic value) {
    final raw = JsonValue.map(value);
    if (raw == null) return const <String, int>{};
    final output = <String, int>{};
    for (final entry in raw.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      output[key] = JsonValue.integer(entry.value).clamp(0, 100).toInt();
    }
    return output;
  }

  static DateTime? _dateFromJson(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      final dynamic firestoreDate = value.toDate();
      if (firestoreDate is DateTime) return firestoreDate;
    } catch (_) {
      // Ignore non-Firestore timestamp values.
    }
    return null;
  }
}
