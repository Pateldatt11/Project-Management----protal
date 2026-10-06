# V281 HTML/CSS Report + Browser Print Preview

This patch changes the **Flutter Web** report output to real HTML/CSS and invokes
the active browser's standard print preview.

## Files

```text
lib/features/reports/html/dynamic_report_html_builder.dart
lib/features/reports/html/report_html_printer.dart
lib/features/reports/html/report_html_printer_web.dart
lib/features/reports/html/report_html_printer_stub.dart
lib/features/reports/html/html_report_print_service.dart
```

## Reports screen integration

Add imports:

```dart
import '../html/dynamic_report_html_builder.dart';
import '../html/report_html_printer.dart';
```

In the report-generation method, after the project/task/member scope is built:

```dart
final reportTitle =
    '${report.reportType}_${report.monthId.isEmpty ? report.period : report.monthId}';

if (kIsWeb) {
  final html = const DynamicReportHtmlBuilder().build(
    report: report,
    projects: scopedProjects,
    tasks: scopedTasks,
    members: scopedMembers,
    monthlySnapshot: loadedSnapshot,
    minPages: 8,
  );

  if (openPreview) {
    final opened = await ReportHtmlPrinter.printHtml(
      title: reportTitle,
      html: html,
    );
    if (!opened && mounted) {
      _show('The browser print preview could not be opened.');
    }
  } else {
    _show('HTML/CSS report generated. Use Print / Save PDF.');
  }
  return;
}
```

Keep the existing `DynamicReportPdfBuilder` path for Android, iOS and desktop.

## Browser print settings

The template already includes:

```css
@page { size: A4 portrait; margin: 0; }
* {
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
```

For the closest output in Chrome/Edge:

- Destination: **Save as PDF** or a physical printer
- Layout: **Portrait**
- Paper: **A4**
- Margins: **None**
- Scale: **Default / 100%**
- Background graphics: **Enabled**
- Browser headers and footers: **Disabled**

## Security

All dynamic strings are HTML escaped before insertion. The report does not load
external JavaScript or chart libraries.
