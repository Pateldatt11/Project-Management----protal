import '../../core/utils/date_utils.dart';
import '../../core/utils/json_value.dart';

class MonthlyAnalyticsSnapshot {
  const MonthlyAnalyticsSnapshot({
    required this.monthId,
    required this.companyId,
    required this.periodStart,
    required this.periodEnd,
    required this.generatedAt,
    required this.isFinalized,
    this.reportingCutoff,
    required this.metrics,
    this.finalizedAt,
    this.schemaVersion = 1,
    this.generationId = '',
    this.breakdownStorage = 'inline',
    this.detailCounts = const <String, dynamic>{},
    this.projectBreakdown = const <Map<String, dynamic>>[],
    this.employeeBreakdown = const <Map<String, dynamic>>[],
    this.taskBreakdown = const <Map<String, dynamic>>[],
    this.employmentActionBreakdown = const <Map<String, dynamic>>[],
  });

  final String monthId;
  final String companyId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime generatedAt;
  final DateTime? reportingCutoff;
  final DateTime? finalizedAt;
  final bool isFinalized;
  final int schemaVersion;
  final String generationId;
  final String breakdownStorage;
  final Map<String, dynamic> detailCounts;
  final Map<String, dynamic> metrics;
  final List<Map<String, dynamic>> projectBreakdown;
  final List<Map<String, dynamic>> employeeBreakdown;
  final List<Map<String, dynamic>> taskBreakdown;
  final List<Map<String, dynamic>> employmentActionBreakdown;

  int metricInt(String key, {int fallback = 0}) => JsonValue.integer(metrics[key], fallback: fallback);
  num metricNumber(String key, {num fallback = 0}) => JsonValue.number(metrics[key], fallback: fallback);
  String metricString(String key, {String fallback = ''}) => JsonValue.string(metrics[key], fallback: fallback);

  Map<String, dynamic>? projectMetrics(String projectId) {
    for (final item in projectBreakdown) {
      if (JsonValue.string(item['projectId']) == projectId) return item;
    }
    return null;
  }

  MonthlyAnalyticsSnapshot withDetails({
    List<Map<String, dynamic>>? projects,
    List<Map<String, dynamic>>? employees,
    List<Map<String, dynamic>>? tasks,
    List<Map<String, dynamic>>? employmentActions,
  }) {
    return MonthlyAnalyticsSnapshot(
      monthId: monthId,
      companyId: companyId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      generatedAt: generatedAt,
      reportingCutoff: reportingCutoff,
      finalizedAt: finalizedAt,
      isFinalized: isFinalized,
      schemaVersion: schemaVersion,
      generationId: generationId,
      breakdownStorage: breakdownStorage,
      detailCounts: detailCounts,
      metrics: metrics,
      projectBreakdown: projects ?? projectBreakdown,
      employeeBreakdown: employees ?? employeeBreakdown,
      taskBreakdown: tasks ?? taskBreakdown,
      employmentActionBreakdown: employmentActions ?? employmentActionBreakdown,
    );
  }

  factory MonthlyAnalyticsSnapshot.fromJson(Map<String, dynamic> json) {
    return MonthlyAnalyticsSnapshot(
      monthId: JsonValue.string(json['monthId'] ?? json['id']),
      companyId: JsonValue.string(json['companyId']),
      periodStart: DateText.parse(json['periodStart']) ?? DateTime.now(),
      periodEnd: DateText.parse(json['periodEnd']) ?? DateTime.now(),
      generatedAt: DateText.parse(json['generatedAt'] ?? json['updatedAt']) ?? DateTime.now(),
      reportingCutoff: DateText.parse(json['reportingCutoff']),
      finalizedAt: DateText.parse(json['finalizedAt']),
      isFinalized: JsonValue.boolean(json['isFinalized'], fallback: false),
      schemaVersion: JsonValue.integer(json['schemaVersion'], fallback: 1),
      generationId: JsonValue.string(json['generationId']),
      breakdownStorage: JsonValue.string(json['breakdownStorage'], fallback: 'inline'),
      detailCounts: JsonValue.map(json['detailCounts']) ?? const <String, dynamic>{},
      metrics: JsonValue.map(json['metrics']) ?? const <String, dynamic>{},
      projectBreakdown: _mapList(json['projectBreakdown']),
      employeeBreakdown: _mapList(json['employeeBreakdown']),
      taskBreakdown: _mapList(json['taskBreakdown']),
      employmentActionBreakdown: _mapList(json['employmentActionBreakdown']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'monthId': monthId,
        'companyId': companyId,
        'periodStart': periodStart.toIso8601String(),
        'periodEnd': periodEnd.toIso8601String(),
        'generatedAt': generatedAt.toIso8601String(),
        'reportingCutoff': reportingCutoff?.toIso8601String(),
        'finalizedAt': finalizedAt?.toIso8601String(),
        'isFinalized': isFinalized,
        'schemaVersion': schemaVersion,
        'generationId': generationId,
        'breakdownStorage': breakdownStorage,
        'detailCounts': detailCounts,
        'metrics': metrics,
        'projectBreakdown': projectBreakdown,
        'employeeBreakdown': employeeBreakdown,
        'taskBreakdown': taskBreakdown,
        'employmentActionBreakdown': employmentActionBreakdown,
      };

  static List<Map<String, dynamic>> _mapList(dynamic raw) {
    if (raw is! Iterable) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList();
  }
}
