import '../../../data/models/member.dart';
import '../../../data/models/monthly_analytics_snapshot.dart';
import '../../../data/models/project.dart';
import '../../../data/models/report.dart';
import '../../../data/models/task.dart';
import 'dynamic_report_html_builder.dart';
import 'report_html_printer.dart';

/// Convenience facade used by the Reports screen.
class HtmlReportPrintService {
  const HtmlReportPrintService({
    this.builder = const DynamicReportHtmlBuilder(),
  });

  final DynamicReportHtmlBuilder builder;

  Future<bool> buildAndPrint({
    required String title,
    required ReportModel report,
    required List<Project> projects,
    required List<ProjectTask> tasks,
    required List<Member> members,
    MonthlyAnalyticsSnapshot? monthlySnapshot,
    int minPages = 8,
  }) {
    final html = builder.build(
      report: report,
      projects: projects,
      tasks: tasks,
      members: members,
      monthlySnapshot: monthlySnapshot,
      minPages: minPages,
    );

    return ReportHtmlPrinter.printHtml(
      title: title,
      html: html,
    );
  }
}
