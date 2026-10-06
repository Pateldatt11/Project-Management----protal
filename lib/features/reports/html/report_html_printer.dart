import 'report_html_printer_stub.dart'
    if (dart.library.html) 'report_html_printer_web.dart' as implementation;

/// Opens the browser's native print preview for a complete HTML document.
///
/// On Web, the implementation writes the report into an isolated same-origin
/// iframe and invokes `print()` on that iframe. This avoids popup blockers and
/// keeps Chrome, Edge and Firefox print/Save-as-PDF behavior.
///
/// On non-Web platforms, [printHtml] throws [UnsupportedError]. Keep the
/// existing PDF renderer for Android, iOS and desktop builds.
abstract final class ReportHtmlPrinter {
  static Future<bool> printHtml({
    required String title,
    required String html,
  }) {
    return implementation.printHtml(
      title: title,
      html: html,
    );
  }
}
