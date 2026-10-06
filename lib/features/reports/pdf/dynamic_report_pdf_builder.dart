import 'dart:typed_data';

import '../../../data/models/member.dart';
import '../../../data/models/monthly_analytics_snapshot.dart';
import '../../../data/models/project.dart';
import '../../../data/models/report.dart';
import '../../../data/models/task.dart';
import 'premium_v280_report_pdf_builder.dart';

/// Stable report entry point used by the reports screen.
class DynamicReportPdfBuilder {
  const DynamicReportPdfBuilder();

  Future<Uint8List> build({
    required ReportModel report,
    required List<Project> projects,
    required List<ProjectTask> tasks,
    required List<Member> members,
    MonthlyAnalyticsSnapshot? monthlySnapshot,
    int minPages = 8,
  }) {
    return const PremiumV280ReportPdfBuilder().build(
      report: report,
      projects: projects,
      tasks: tasks,
      members: members,
      monthlySnapshot: monthlySnapshot,
      minPages: minPages,
    );
  }
}