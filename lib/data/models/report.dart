import '../../core/utils/date_utils.dart';
import '../../core/utils/json_value.dart';

class ReportModel {
  const ReportModel({
    required this.reportId,
    required this.reportType,
    required this.period,
    required this.status,
    required this.createdAt,
    this.generatedBy,
    this.pdfPath,
    this.xlsxPath,
    this.monthId = '',
    this.projectId,
    this.projectScope = 'all',
    this.snapshotGeneratedAt,
    this.isSnapshotFinalized = false,
    this.metrics = const <String, dynamic>{},
  });

  final String reportId;
  final String reportType;
  final String period;
  final String status;
  final DateTime createdAt;
  final String? generatedBy;
  final String? pdfPath;
  final String? xlsxPath;
  final String monthId;
  final String? projectId;
  final String projectScope;
  final DateTime? snapshotGeneratedAt;
  final bool isSnapshotFinalized;
  final Map<String, dynamic> metrics;

  String get summary {
    final scope = projectScope == 'project'
        ? (metrics['projectName']?.toString().trim().isNotEmpty == true
            ? metrics['projectName'].toString()
            : 'Selected project')
        : 'All projects';
    final snapshotLabel = isSnapshotFinalized ? 'finalized monthly snapshot' : 'live monthly snapshot';
    return '$reportType for ${monthId.isEmpty ? period : monthId} • $scope • $snapshotLabel';
  }

  ReportModel copyWith({
    String? status,
    String? pdfPath,
    String? xlsxPath,
    String? monthId,
    String? projectId,
    String? projectScope,
    DateTime? snapshotGeneratedAt,
    bool? isSnapshotFinalized,
    Map<String, dynamic>? metrics,
  }) =>
      ReportModel(
        reportId: reportId,
        reportType: reportType,
        period: period,
        status: status ?? this.status,
        createdAt: createdAt,
        generatedBy: generatedBy,
        pdfPath: pdfPath ?? this.pdfPath,
        xlsxPath: xlsxPath ?? this.xlsxPath,
        monthId: monthId ?? this.monthId,
        projectId: projectId ?? this.projectId,
        projectScope: projectScope ?? this.projectScope,
        snapshotGeneratedAt: snapshotGeneratedAt ?? this.snapshotGeneratedAt,
        isSnapshotFinalized: isSnapshotFinalized ?? this.isSnapshotFinalized,
        metrics: metrics ?? this.metrics,
      );

  factory ReportModel.fromJson(Map<String, dynamic> json) => ReportModel(
        reportId: JsonValue.string(json['reportId'] ?? json['id']),
        reportType: JsonValue.string(json['reportType'] ?? json['type']),
        period: JsonValue.string(json['period']),
        status: JsonValue.string(json['status'], fallback: 'draft'),
        createdAt: DateText.parse(json['createdAt']) ?? DateTime.now(),
        generatedBy: JsonValue.optionalString(json['generatedBy']),
        pdfPath: JsonValue.optionalString(json['pdfPath']),
        xlsxPath: JsonValue.optionalString(json['xlsxPath']),
        monthId: JsonValue.string(json['monthId']),
        projectId: JsonValue.optionalString(json['projectId']),
        projectScope: JsonValue.string(json['projectScope'], fallback: 'all'),
        snapshotGeneratedAt: DateText.parse(json['snapshotGeneratedAt']),
        isSnapshotFinalized: JsonValue.boolean(json['isSnapshotFinalized'], fallback: false),
        metrics: JsonValue.map(json['metrics']) ?? const <String, dynamic>{},
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'reportId': reportId,
        'reportType': reportType,
        'period': period,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'generatedBy': generatedBy,
        'pdfPath': pdfPath,
        'xlsxPath': xlsxPath,
        'monthId': monthId,
        'projectId': projectId,
        'projectScope': projectScope,
        'snapshotGeneratedAt': snapshotGeneratedAt?.toIso8601String(),
        'isSnapshotFinalized': isSnapshotFinalized,
        'metrics': metrics,
      };
}
